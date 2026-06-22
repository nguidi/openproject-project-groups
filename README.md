# ProjectGroups

An OpenProject plugin that lets you **add users to a group _per project_**, where the
group's purpose is to bundle a **set of Roles**. Adding a user to a group in a
project grants that user the group's roles **in that project only** — without the
native "add a group and it leaks into every project" behavior.

> Status: **implemented** — Phases 0–5 complete (MVP shipped, deployable). This
> README doubles as the design spec and the development plan; the phase checklist in
> §7 tracks what's done vs. the post-MVP backlog (§7, Phase 4.5).

---

## 1. The problem

OpenProject's permission model is built on four objects:

| Object | Meaning |
| --- | --- |
| `User` | An individual account. Subclass of `Principal`. |
| `Group` | A named bag of users. Also a subclass of `Principal`. |
| `Role` | A named set of permissions. |
| `Member` | Binds a **Principal** to a **single Project**, carrying one or more Roles (via `MemberRole`). |

The friction comes from how native **Groups** behave:

- A `Group`'s user list is **global**. A user is either *in* the group or not —
  there is no "in this group, but only for project A".
- When a `Group` is added to a project, OpenProject **propagates** roles to **every
  user in the group**, generating *inherited* `Member` / `MemberRole` rows
  (`MemberRole.inherited_from`).
- So adding one user to a group silently grants that user a role across **all**
  projects that group touches.

We want: add a user to a group **scoped to a single project**, and have it mean
"give this user the group's roles in this project".

## 2. The approach

**Reuse native OpenProject Groups and Roles. Change only how membership works.**

- **Groups are native `Group` objects**, created and named through OpenProject's
  normal Groups admin. We do **not** invent our own group entity.
- **We attach a role-set to each group** — a global mapping `Group → {Role, …}`
  ("this group means these roles"), configured on **a small admin screen we add**.
  This is necessary because native Groups admin has **no project-independent
  project-role assignment**: its *Projects* tab is per-project and propagates, and
  its *Global Roles* tab assigns global (not project) roles. So the role-set is our
  one new concept on top of groups.
- **Project roles only.** The role-set contains project roles; OpenProject's
  Global Role feature is out of scope (global roles are application-wide and can't
  be project-scoped). We do not create roles — we reuse existing project roles.
- **Permissions are handled entirely by Roles.** Roles are inherently
  project-scoped because they live on `Member` (a per-project binding).
- **Per-project opt-in.** "Groups and Members" is a **project module** an admin
  enables per project (Project Settings ▸ Modules). When enabled, our page is shown
  and the native *Members* page is hidden/guarded for that project; when disabled,
  the native *Members* page stays. This is the "use ours or OpenProject's" toggle.
- **The native Group is a facade ("faked").** We use it for identity / naming /
  listing only. We **never** add the native group to a project, so its propagation
  machinery never fires, and we do **not** use its native (global) membership
  (`GroupUser`).
- **Membership is project-scoped** and lives in **our own table**:
  `(user, group, project)`. When a user is added to a group in a project, we read
  the group's role-set and **materialize direct, project-scoped `Member` /
  `MemberRole` rows** for that user. OpenProject's existing permission engine,
  work-package filters, sharing, notifications, etc. then "just work", because to
  the core app these look like ordinary direct project memberships.
- We **own** the rows we create (tracked in a bookkeeping table) so reconciliation
  only ever touches roles we manage — never the user's manually-assigned roles or
  anything else.

```
native Group  ──(our role-set)──▶  {Role A, Role B}        global: "this group = these roles"
      │
      │  user added to group, IN A PROJECT
      ▼
ProjectGroups::Membership (user, group, project)            our source of truth (project-scoped)
      │  reconcile
      ▼
native Member + MemberRole (direct, in that project)        derived; drives OpenProject permissions
```

So: *the native group + our role-set + our project-scoped membership are the source
of truth; native `Member` rows are a derived projection we keep in sync.*

## 3. Data model

We add four small tables (all namespaced `project_groups_*`). **There is no custom
"group" table** — the group is the native `Group`, referenced by its principal id.

- **`project_groups_group_roles`** — the role-set attached to a (native) group.
  - `group_id` → core `groups`/`principals` (the native Group)
  - `role_id` → core `roles`
  - unique on the pair. Global: one role-set per group, used in every project.
  - Only **assignable project roles** are selectable — the special `Non member` /
    `Anonymous` roles (auto-applied by core) and global roles are excluded.

- **`project_groups_assignments`** — a group made available in a specific project.
  - `group_id` → native Group
  - `project_id` → core `projects`
  - unique on the pair. "This group is active in this project" — gives the project
    UI something to list and lets you attach a group before adding any members.

- **`project_groups_memberships`** — a user placed into a group **within a project**.
  - `assignment_id` → `project_groups_assignments` (so it carries group + project)
  - `user_id` → core `users`
  - timestamps. **This is the project-scoped membership the plugin exists to
    provide**, and it is kept here — *not* in native `GroupUser`.

- **`project_groups_managed_member_roles`** — bookkeeping for reconciliation.
  - `member_role_id` → core `member_roles` (**unique**; FK `on_delete: cascade`)
  - Marks exactly which native `MemberRole` rows we created, so reconciliation
    never deletes a role the user got from elsewhere. **Keyed by member_role only**
    (not by membership): a role granted by two groups at once is one managed record,
    so it survives until *no* group still wants it (§4 "two groups, shared role").
    Provenance ("which group granted it") is derived, not stored.

The **per-project "use ours vs native Members" toggle needs no table**: it rides on
native **project module enablement** — enabling the "Groups and Members" module on a
project turns our flow on (and hides/guards native Members) for that project.

### Why our own membership table instead of native `GroupUser`?

Native `GroupUser` is **global** and would re-introduce cross-project coupling (and
would fire propagation if anyone ever added the group to a project in the core UI).
Keeping membership in our own table is precisely how we "fake" the group: the
native group is a label; the real, project-scoped membership is ours.

### Why a "managed" table instead of `MemberRole.inherited_from`?

`inherited_from` is core's mechanism for native-group inheritance; reusing it risks
core's `Groups::*` services fighting with us. A dedicated table keeps our ownership
explicit and upgrade-safe.

## 4. Reconciliation logic (the heart of the plugin)

A single service — `ProjectGroups::Reconcile` — converts our source-of-truth rows
into native `Member`/`MemberRole` rows for one *(user, project)* pair:

```
desired_roles(user, project) =
    ⋃ role-set of every group the user belongs to in that project
      (our memberships → assignment(group, project) → group_roles)

current_managed_roles(user, project) =
    roles we previously created for that user/project (via managed_member_roles)

→ add    desired − current     (create Member if absent, add MemberRole, record it)
→ remove current  − desired    (delete only MemberRole rows we own; drop the Member
                                 if it has no roles left AND we created it)
```

**Implementation note (confirmed against v17 source).** This mirrors core's own
group-inheritance services (`Groups::CreateInheritedRolesService` /
`CleanupInheritedRolesService`): derived roles are written **directly via
`ActiveRecord`** (build `Member` + `MemberRole`), not through `Members::CreateService`,
to avoid notification side effects — exactly what core does for inherited roles. Our
roles carry `inherited_from = NULL` (so they look "direct" to the permission engine)
and are distinguished from genuinely-manual roles only by our managed table. An
emptied `Member` (no roles left) is destroyed. `MemberRole`'s `belongs_to :member,
touch: true` keeps the member's `updated_at` (and caches) fresh.

Rules:
- **Never** touch `MemberRole` rows we don't own (manual memberships, native group
  inheritance) — protected by the managed table.
- If a user already holds a role directly, and a group would grant the same role,
  don't create a duplicate; the direct one stays authoritative (decision in §9).
- Reconciliation is **idempotent** and safe to re-run.

OpenProject emits **no webhook** for membership or group changes (webhooks cover
only projects, work packages, comments, time entries, attachments), so we hook
**in-process** via model callbacks / our own service objects — not webhooks.

Triggers that schedule a reconcile:
- User added/removed from a group in a project → reconcile that user + project.
- A group's role-set changes → reconcile every (user, project) using that group.
- A group removed from a project (assignment deleted) → reconcile each affected user.
- A user deleted/locked → core cleans members; we clean our rows too.

Heavy fan-out (e.g. editing the role-set of a group used in 50 projects) runs in a
background job (`ProjectGroups::ReconcileJob`) on OpenProject's Good Job queue.

### Test scenarios (Phase 1 — written before any UI)

These pin the behavior and become the RSpec suite:

1. **Add scopes to one project.** Add Maria to group G (`{Member}`) in project A →
   she's a direct `Member` in A; she is **not** a member of project B.
2. **Remove cleans only ours.** Remove Maria from G → the roles we added are
   removed; her `Member` record is dropped only if it has no roles left *and* we
   created it.
3. **Direct wins (overlap).** Maria is a manual `Member` in A; add her to G
   (`{Member, Reviewer}`) → no duplicate `Member`; `Reviewer` is added and owned by
   us. Remove her from G → `Reviewer` removed, `Member` **kept** (it was direct).
4. **Two groups, shared role.** Maria is in G1 (`{Member}`) and G2
   (`{Member, Reviewer}`) in A → `Member` present once. Remove her from G2 →
   `Member` **stays** (still from G1), `Reviewer` removed.
5. **Role-set edit, immediate.** G is used in 30 projects / 50 memberships; add
   `Project admin` to G → all 50 reconciled (background); removing a role revokes it
   everywhere we own it, but never where it's held directly.
6. **Idempotency.** Running reconcile twice in a row produces zero changes the
   second time.
7. **Group removed from project.** Delete the assignment of G in A → every G
   membership in A is removed and those users reconciled.
8. **User locked/deleted.** Core removes the member; our rows for that user are
   cleaned up too.

## 5. Plugin architecture (OpenProject engine)

OpenProject plugins are Rails engines mounted via
`OpenProject::Plugins::ActsAsOpEngine`. Scaffold with the official generator:

```
bundle exec rails generate open_project:plugin project_groups ../plugins/
# → creates the engine "openproject-project_groups"
```

and register it (for dev) in `Gemfile.plugins`:

```ruby
group :opf_plugins do
  gem "openproject-project_groups", path: "../plugins/openproject-project_groups"
end
```

Migrations placed in the plugin's `db/migrate` are auto-discovered by core.
Structure (as built):

```
ProjectGroups/
├── README.md  CHANGELOG.md  DEVELOPMENT.md
├── openproject-project_groups.gemspec
├── Gemfile
├── doc/
│   ├── COPYRIGHT.md
│   └── GPL.txt                       # verbatim GPLv3
├── lib/
│   ├── openproject-project_groups.rb         # gem entry point (Bundler)
│   ├── open_project/
│   │   └── project_groups/
│   │       ├── engine.rb             # register plugin, module, menus, permissions, patches
│   │       ├── version.rb
│   │       └── patches/
│   │           └── group_patch.rb    # adds project_group_roles / _assignments to core Group
│   └── tasks/
│       └── project_groups.rake       # reconcile_all (drift repair) + check (conflict report)
├── app/
│   ├── models/
│   │   └── project_groups/
│   │       ├── group_role.rb  assignment.rb  membership.rb  managed_member_role.rb
│   │       └── (project_groups.rb sets table_name_prefix)
│   ├── services/
│   │   └── project_groups/
│   │       ├── reconcile.rb           # (user, project) materialisation — the core
│   │       ├── reconcile_all.rb       # full re-sync / drift repair
│   │       └── set_group_role_set.rb  # admin role-set save + async fan-out
│   ├── controllers/
│   │   └── project_groups/
│   │       ├── admin/group_roles_controller.rb   # define each group's role-set
│   │       └── memberships_controller.rb         # add/remove members within a project
│   ├── views/                        # server-rendered Primer ViewComponents (ERB), no SPA
│   └── workers/
│       └── project_groups/reconcile_job.rb
├── config/
│   ├── routes.rb
│   └── locales/en.yml
├── db/
│   └── migrate/                      # the four project_groups_* tables
├── deploy/                           # production image + deployment kit (Phase 5)
└── spec/                             # RSpec — mirrors app/ (services, models, workers, patch)
```

> Note: the `Group` patch lives under `lib/.../patches/` (not `app/patches/`), and the
> UI is plain Primer ViewComponents inside ERB views — there is no `app/components/`
> directory and no Angular/SPA code.

Engine responsibilities (`engine.rb`):
- `register 'openproject-project_groups'` with the Op plugin DSL.
- Define plugin **permissions**: `manage_project_group_roles` (define group→role
  mappings, global/admin) and `manage_project_group_members` (add/remove members
  within a project) — so a project admin can populate predefined groups without
  being able to redefine global role-sets.
- Register **"Groups and Members" as a project module** so it can be toggled per
  project (Project Settings ▸ Modules), and add its project menu entry (the primary
  UI). Add an **admin menu** entry for defining group role-sets.
- **Conditionally hide/guard the native Members page**: when our module is enabled
  on a project, remove the native *Members* menu item and (optionally) block its
  controller for that project; when disabled, leave it alone. (Menu/route hooks to
  be verified against the deployed version.)
- Register model patches / event hooks (e.g. on user destroy, on group destroy) to
  keep our tables and the projection consistent.

UI: prefer **Primer ViewComponents with server-rendered Rails views** (what
OpenProject now uses for admin/settings screens) over the Angular SPA — far less
surface area and no frontend build coupling for an MVP.

## 6. UI surfaces

**Primary — "Groups and Members" project page** (project-first; our own project
module, enabled per project):

```
Project ▸ Groups and Members
────────────────────────────────────────
Group            Roles (from role-set)   Members
Reviewers        Reviewer                3   [+ add member]
Auditors         Reader                  1   [+ add member]
PhD Supervisors  Project admin           2   [+ add member]

[+ add a group to this project]
```

- Attach an existing (native) group to the project (creates an `assignment`).
- Add a user to a group → creates a project-scoped `membership` → reconcile writes a
  direct member with the group's roles. Removing reverses it.
- Show each user's effective roles with provenance (which group granted what).

**Per-project toggle (native Members vs ours):** "Groups and Members" is a project
module. In **Project Settings ▸ Modules** an admin enables it; while enabled we hide
(and optionally guard) the native *Members* page so there's a single way in. Disable
it and the native *Members* page returns. Exclusive by design — you pick one.

**Secondary — admin screen** (global): define/edit each group's **role-set** (pick
project roles). Group *creation/naming* stays in OpenProject's native **Admin ▸
Groups** — we only attach the role-set and never create groups or roles ourselves.

## 7. Development plan (phased)

**Phase 0 — Scaffold & boot**
- [x] Engine skeleton authored: `engine.rb` (registers the `project_groups` module +
      `view_project_groups` / `manage_project_group_members` permissions), gemspec,
      Gemfile, `version.rb`, entry requires.
- [x] Migrations for the four tables (FKs to `users`/`roles`/`projects`/`member_roles`,
      unique composite indexes).
- [x] Models (`GroupRole`, `Assignment`, `Membership`, `ManagedMemberRole`) +
      `table_name_prefix`, associations, uniqueness validations.
- [x] `Group` patch exposing `project_group_roles` / `project_group_role_set` /
      `project_group_assignments`.
- [x] **Boot verified on real v17** (release/17.5 dev stack): engine loads, the four
      `project_groups_*` tables exist, `table_name_prefix` maps models correctly, the
      `Group` patch associations resolve, the `project_groups` module is registered,
      and the `view_project_groups` / `manage_project_group_members` permissions are
      live. Migration compat `[7.1]` and the `permissible_on:` DSL both worked as-is.
- [ ] Full CRUD/reconcile smoke test (create real `Member` rows) — covered by Phase 1.

**Phase 1 — Reconciliation core (no UI)**
- [x] `ProjectGroups::Reconcile` for a (user, project) pair (`app/services/project_groups/reconcile.rb`)
      + `Reconcile.for_group` fan-out for role-set edits.
- [x] Managed-member-role bookkeeping (keyed by `member_role`; cascade cleanup).
- [x] `ReconcileJob` for fan-out (`app/workers/project_groups/reconcile_job.rb`).
- [x] **Thorough RSpec** — the 8 §4 scenarios (`spec/services/project_groups/reconcile_spec.rb`):
      project-scoping, "direct wins", shared roles, role-set edit, idempotency,
      group detach, cascade cleanup. **8 examples, 0 failures on v17 (release/17.5).**
- [ ] Trigger wiring (model callbacks / service objects that call reconcile) — folded
      into Phase 2, where the controllers that mutate memberships live.

**Phase 2 — Project UI (per-project membership)** ← the main feature
- [x] Register the **"Groups and Members" project module** + project menu entry
      (menu registered inside the `register` block so `Redmine` is loaded; shown only
      where the module is enabled).
- [x] "Groups and Members" page (`MembershipsController` + ERB): list attached groups
      with their roles + members, attach/detach a group, add/remove users — each
      mutation calls `Reconcile`. `manage_project_group_members` gating via `authorize`.
- [x] **Verified on the live dev app** (`dev/verify_phase2.rb`): attaching *BIM
      Coordinators* + adding a user materialises a native member with the group's
      role; removal reverts it — and "direct wins" held (a pre-existing direct role
      survived). Page renders 200.
- [x] Conditionally **hide the native Members menu** when our module is on
      (`MenuManager#add_condition` on `:members`, queued after config initializers).
      **Verified** (`dev/verify_menu.rb`): module OFF → Members shown / ours hidden;
      module ON → Members hidden / ours shown.
- [ ] Effective-roles view with **provenance** (which group granted which role) — the
      page already groups members under their group; a per-user effective-roles
      summary is the remaining nicety.
- [x] Primer visual polish — done in **Phase 3.1**.

> Testing note: HTML controller/UI flows are covered by the live runner now and by a
> **feature spec (Capybara)** later — OpenProject tests UI via feature specs, not
> request specs (no `spec/controllers`; request specs fight CSRF/param handling here).
> Correctness stays locked by the fast service specs (8/8).

**Phase 3 — Admin UI (group role-sets)** ✅
- [x] Admin screen (`ProjectGroups::Admin::GroupRolesController`, `layout "admin"`):
      index lists every group + its role-set; edit picks project roles (checkboxes,
      filtered to `role.member?`). Entry under **Administration ▸ Users & Permissions ▸
      Group role-sets** (verified nested).
- [x] `SetGroupRoleSet` service — applies the role-set **synchronously**, then **fans
      member reconciliation out to background `ReconcileJob`s** (one per affected
      (user, project) pair). Spec: `spec/services/project_groups/set_group_role_set_spec.rb`.
- [x] No seeded defaults — role-sets assembled by hand (§11).
- [ ] Gating is **admin-only** (`require_admin`) for now; a global
      `manage_project_group_roles` permission could replace it later (§9.3).

**Phase 3.1 — Visual polish (native Primer UI)** ✅
Rebuilt all three pages with OpenProject's own ViewComponents (modeled on the native
Members + admin Groups pages) so they read as first-class OP screens:
- `Primer::OpenProject::PageHeader` (title + description + **breadcrumbs**) — admin
  pages breadcrumb under *Users & Permissions*; the project page under the project.
- `Primer::Beta::BorderBox` cards (`with_header` / `with_row`) replacing plain tables.
- `Primer::Beta::Label` role chips, `Primer::Beta::Button` (primary / `invisible` with
  trash / ✕ / pencil / plus icons), `Primer::Beta::Blankslate` empty states.
- Native **Turbo** forms; project controller redirects with `status: :see_other`.
- [x] Verified rendering in the browser (admin index + edit, project page).

Gotchas learned (now in DEVELOPMENT.md):
- `Primer::OpenProject::PageHeader` **requires both `with_title` and
  `with_breadcrumbs`** — omitting breadcrumbs raises a 500. The project breadcrumb
  root is `project_overview_path(project.id)`.
- **Plugin `app/views` do NOT hot-reload** in the dev stack — restart the backend
  after view/controller edits (only the main app's views live-reload).

Remaining polish: a per-user **provenance** summary, and a richer member picker
(autocomplete) instead of the plain `<select>`.

**Phase 4 — Robustness & ops** ✅ (core items)
- [x] **Full re-sync / drift repair** — `ProjectGroups::ReconcileAll` service +
      `rake project_groups:reconcile_all`. Reconciles every (user, project) that has a
      membership **or** a managed role, so it both materialises missing members and
      **cleans orphaned managed roles** (e.g. a membership removed by a direct DB
      change). Spec verifies both directions (11/11 service specs pass).
- [x] **Conflict guardrails** for the operator caveat (§9): `rake project_groups:check`
      reports groups attached here that are *also* native project members (core
      propagation), and the project page shows a **warning banner** for the same
      (`Primer::Alpha::Banner`).

**Phase 4.5 — Optional enhancements (post-MVP)** — prioritised per stakeholder
- [x] **Async fan-out** — `ReconcileJob` is wired: a group's role-set edit enqueues
      one background job per affected (user, project) pair (`SetGroupRoleSet` →
      `ReconcileJob.perform_later`) instead of reconciling synchronously in the
      request. Removes the scale cliff. Covered by `reconcile_job_spec.rb` +
      `set_group_role_set_spec.rb`. (`Reconcile.for_group` remains the synchronous
      path, used by the service/rake re-sync helpers.)
- [ ] **Member picker → autocomplete** — replace the plain `<select>` of all users
      with OpenProject's user autocompleter, scoped to addable users.
- [ ] **Per-user role list** — a second **tab** on "Groups and Members" showing each
      user's effective roles in the project and which group(s) granted them (provenance).
- [ ] **REST API** *(must)* — endpoints mirroring the UI: list/attach/detach groups,
      add/remove members, get/set group role-sets. *(Add request specs.)*
- [ ] **Audit log** *(must)* — record membership + role-set changes (who/what/when).
      *(Add specs.)*
- [ ] **Watcher pruning** *(optional, may be needed)* — on member removal, use
      `Members::DeleteService` instead of `member.destroy!` so a user's work-package
      watchers are pruned when they lose project access.
- [ ] **i18n** — extract all strings; add locale(s) beyond `en`.
- **Not needed** (per stakeholder): global `manage_project_group_roles` permission;
  add/remove notifications.

> Testing to add with these (Phase C): **feature specs** (Capybara) for the project
> page + admin screen once the browser test stack is set up; **request specs** for the
> REST API; and **audit log specs**. Conflict detection (shared by the project page and
> `rake project_groups:check`) lives in `Assignment.conflicting_with_native_membership`
> and is unit-tested. The `ReconcileJob` job spec and the model + `Group` patch specs
> already exist; core logic stays covered by the service specs (`spec/services`,
> `spec/models`).

**Phase 5 — Packaging & deployment** ✅
- [x] Production **`deploy/`** kit: `Dockerfile` (`FROM openproject/openproject:<tag>`,
      copies the plugin, `bundle install` unfreeze→install→re-freeze), `Gemfile.plugins`,
      `build.sh`, root `.dockerignore`, and **`deploy/DEPLOYMENT.md`** (build → swap the
      image into the stack → migrations auto-run → enable per project).
- [x] **Backend-only → no asset precompile / Node build** (server-rendered Primer/ERB),
      so the prod Dockerfile is minimal.
- [x] Upgrade / rollback / version-pinning notes (DEPLOYMENT.md §5–§6).
- [x] **Built & runtime-smoke-tested** the **slim** artifact
      `openproject-whisperer:17-slim` (the compose/Helm deploy image) via the
      official multi-stage build (`deploy/Dockerfile.slim`). `deploy/smoke-test.yml`
      boots it in **production mode** against a throwaway Postgres → schema builds, all
      4 plugin migrations run, and `SMOKE_RESULT ok=true` (module registered, 4 tables
      present, permissions live). The smoke harness is image-aware (slim has no
      `db/structure.sql`, so it migrates from scratch); the single-stage all-in-one
      `openproject-whisperer:17` is also verified. Re-run pinned to your exact
      patch tag before going live.

## 8. Development environment, build & deploy

### 8.1 Languages & runtimes

OpenProject is a **Ruby on Rails** app, so the plugin is **~90% Ruby**. Breakdown of
what we actually write:

| Area | Language / tech |
| --- | --- |
| Engine, models, services (reconcile), controllers, migrations, gemspec | **Ruby / Rails** |
| Admin role-set screen + "Groups and Members" project page | **Primer ViewComponents** (Ruby) + **ERB** |
| Small interactivity (add-member modal, role pickers), if needed | **Stimulus (TypeScript)** + **Turbo** (Hotwire) — minimal |
| Styling | **SCSS**, minimal — rely on Primer |
| Translations | **YAML** (i18n locales) |
| Tests (the §4 scenarios) | **RSpec** (Ruby) |

We do **not** write any Angular/SPA TypeScript (the Primer/Rails decision, §9.6), so
the **Node.js toolchain is only needed to build assets**, not for feature code.

Runtime versions (confirmed from the `release/17.5` dev stack): **Ruby 4.0.2**
(`ruby:4.0.2-trixie`), **Rails 8.1.3**, **Node 22.21.0**, **PostgreSQL 17**,
Bundler 4.0.x, Angular CLI 21.

### 8.2 Build artifacts

The plugin gem ships: the Rails engine, `db/migrate` migrations, ViewComponents/ERB
views, `config/locales/*.yml`, the RSpec suite, and — for deployment — a
`Gemfile.plugins` entry + `Dockerfile`.

### 8.3 Dev workflow (recommended: OpenProject docker-compose dev env)

> **Fully dockerized — nothing on the host but Docker. See [DEVELOPMENT.md](DEVELOPMENT.md)
> for the step-by-step guide** (incl. the Windows/WSL2 performance caveat: keep the
> code inside the WSL2 filesystem, not `E:\…`).

Develop against a checkout of OpenProject **at the same release tag as the stack**
(**v17**), with our plugin **bind-mounted** via `Gemfile.plugins` (path). The prod
`openproject/openproject:17` image can't do this (production mode, no dev/test gems,
no reload) — we use OpenProject's docker-compose **dev** stack. Source is
live-reloaded, so we edit plugin files locally and see changes without rebuilds.

```bash
git clone https://github.com/opf/openproject.git      # check out the tag matching the stack
cd openproject
cp .env.example .env
cp docker-compose.override.example.yml docker-compose.override.yml
# add to Gemfile.plugins:  gem "openproject-project_groups", path: "../ProjectGroups"
docker compose run --rm backend setup                 # bundle + db setup + migrations/seeders
docker compose run --rm frontend npm install
docker compose up -d backend                          # app on http://localhost:3000
```

Day-to-day:

```bash
docker compose exec backend bundle exec rails console            # console
docker compose run --rm backend setup                            # re-run migrations/seeders
docker compose up -d backend-test
docker compose exec backend-test bundle exec rspec spec/...      # run our specs
```

### 8.4 Production: bake a custom image and swap it into the stack

Two deploy paths (full guide in **`deploy/DEPLOYMENT.md`**):
- **Option A — bake** (recommended; works on slim **and** all-in-one): build a derived
  image with the plugin baked in. Fast, deterministic, offline startup.
- **Option B — runtime mount** (**all-in-one image only**): mount the plugin folder +
  a `Gemfile.local` and set `BUNDLE_FROZEN=false`; the image installs it on startup.
  No build, but every boot re-runs `bundle install`/`assets:precompile` (slow, needs
  internet). The `-slim` (compose/Helm) image has no runtime installer → bake.

Option A as a ready-to-use kit in **`deploy/`** (slim production = official multi-stage):

```bash
# from the repo root, pin OPENPROJECT_TAG to your version (without -slim):
OPENPROJECT_TAG=17 ./deploy/build.sh
# → builds  openproject-whisperer:17-slim  (via deploy/Dockerfile.slim)
```

`deploy/Dockerfile.slim` follows OpenProject's **multi-stage** technique: it builds the
plugin on the **full** image `openproject/openproject:${TAG}` (which has git/node/build
tools for `bundle install`), then copies the gem + **plugin source** (it's a `path:`
gem) into `openproject/openproject:${TAG}-slim`. **No `precompile-assets.sh`** —
backend-only (no JS/CSS), so the slim image's own assets suffice. (`deploy/Dockerfile`
is a single-stage variant for a quick all-in-one eval.)

Then point **every** OpenProject service (`web`, `worker`, `seeder`) in the stack's
`docker-compose.yml` at `openproject-whisperer:<tag>-slim` instead of the stock
image and `docker compose up -d`. Pending migrations (core + our four tables) run on
boot. Run `rake project_groups:reconcile_all` once after first deploy; `rake
project_groups:check` reports core-propagation conflicts.

Exact tag + entrypoint behavior get pinned in Phase 5 against the stack's real image.

## 9. Interaction with native Groups & open decisions

How we coexist with the core:
- We **use** native `Group` objects (identity/naming) and native `Role` objects
  (permissions).
- We do **not** use native `GroupUser` membership, and we **never** add a native
  group to a project as a member — both would re-introduce cross-project leakage.
- We only ever create/modify the `Member`/`MemberRole` rows we own (managed table);
  manual memberships and anything core created are left untouched.
- **Per-project toggle:** on projects where the "Groups and Members" module is
  enabled, we own membership and hide the native Members page; on projects where
  it's disabled, native Members works normally and we don't touch it.
- **Caveat to document for operators:** the toggle hides the *project* Members page,
  but the global **Admin ▸ Groups ▸ Projects** tab can still add a group to a project
  (firing core propagation) independently of us. Phase 4 covers warning/guarding
  against this.

Decisions:
1. **Duplicate role from a direct membership** — *(Agreed: direct wins.)* If a role
   is granted both directly (manual member) and via a group, we never duplicate it
   and never remove the directly-granted one. We only ever add/remove roles we own
   (tracked in the managed table). Removing a user from a group leaves any role they
   also hold directly untouched.
2. **Editing a group's role-set** — *(Agreed: immediate + confirmation.)* On save we
   reconcile every affected (user, project) right away (background job for fan-out),
   but first show a blast-radius confirmation (e.g. "changes roles for N members
   across M projects").
3. **Two permissions** — separate `manage_project_group_roles` (global) from
   `manage_project_group_members` (per project). *(Agreed: yes.)*
4. **Role scope** — project roles only; Global Role feature out of scope. *(Agreed.)*
5. **Native Members** — per-project toggle via the "Groups and Members" module;
   hide/guard native Members where ours is enabled. *(Agreed.)*
6. **UI surface** — Primer/Rails views for MVP vs. Angular SPA. *(Leaning Primer/Rails.)*
7. **Nextcloud scope** — *(Agreed: rely on OpenProject's automatically-managed
   project folders.)* This plugin makes **no direct Nextcloud calls**; folder access
   follows from the native member we create. Per-discipline subfolder control belongs
   to the separate Nextcloud plugin — see §11.
8. **Role-set seeding** — *(Agreed: none.)* Admins build each group's role-set by
   hand in the admin UI; §11's table is guidance only.

## 10. What the docs confirm (verified 2026-06-18)

Checked against the official OpenProject docs:

- **Groups** — [system-admin-guide/users-permissions/groups](https://www.openproject.org/docs/system-admin-guide/users-permissions/groups/)
  - Group membership is **global**: "once users join a group, that membership is
    global." Groups also support **parent/subgroups** and **global roles** (both
    out of scope for us — we read only project roles).
  - Adding a group to a project (**Projects** tab, pick role(s), **Add**)
    "immediately enrolls all group members in those projects with the specified
    role(s)." Removing a user from a group "strips their role from associated
    projects… completely removed if no independent membership." → This is exactly
    the propagation we avoid by **never** adding the native group to a project.
- **Roles & permissions** — [system-admin-guide/users-permissions/roles-permissions](https://www.openproject.org/docs/system-admin-guide/users-permissions/roles-permissions/)
  - Project roles vs global roles; a project role **cannot** be converted to a
    global one. Special roles **Non member** / **Anonymous** are auto-applied →
    excluded from our role picker. Permissions are grouped by module. A role
    already assigned to users **cannot be deleted** (matters for our UI guards).
- **API & webhooks** — [system-admin-guide/api-and-webhooks](https://www.openproject.org/docs/system-admin-guide/api-and-webhooks/)
  - Webhook event types are **only**: projects, work packages, work package
    comments, time entries, attachments. **No membership/group event** → we drive
    reconciliation in-process, not via webhooks.
- **Memberships API** — [api/endpoints/memberships](https://www.openproject.org/docs/api/endpoints/memberships/)
  - A `Membership` = `principal` + `project` + `roles[]` (roles via `_links`);
    create needs `principal` + `roles`. Confirms our materialization shape.
- **Plugin development** — [development/create-openproject-plugin](https://www.openproject.org/docs/development/create-openproject-plugin/)
  - Generator `bundle exec rails generate open_project:plugin <name> ../plugins/`;
    register in `Gemfile.plugins` (`group :opf_plugins`); `db/` migrations
    auto-discovered; bake into the Docker image for production.
- **Docker install / adding plugins** — [installation/docker](https://www.openproject.org/docs/installation-and-operations/installation/docker/)
  - Custom image recipe: `FROM openproject/openproject:17`, COPY `Gemfile.plugins`,
    `bundle install`, `./docker/prod/setup/precompile-assets.sh`; `-slim` needs a
    multi-stage build.
- **Docker dev environment** — [development/development-environment/docker](https://www.openproject.org/docs/development/development-environment/docker/)
  - `docker compose run --rm backend setup`, `... up -d backend` (app on :3000),
    `... exec backend bundle exec rails console`, tests via `backend-test` + `rspec`;
    source is mounted with live reload.

### Confirmed on the running stack (release/17.5)
- Engine boots; `permissible_on:` permission DSL, `patches %i[Group]`, and migration
  compat `[7.1]` all work as written (on **Rails 8.1.3**).
- Runtimes: Ruby 4.0.2, Rails 8.1.3, Node 22.21.0, Postgres 17, Angular CLI 21.

### Confirmed in Phase 1 (from v17 source)
- `Member` = `(user_id, project_id, entity_type:NULL, entity_id:NULL)` for a project
  member; must always have ≥1 role; roles via `MemberRole` (`inherited_from` =
  core's group-inheritance marker — unused by us, ours are NULL).
- Reconciliation mirrors `Groups::CreateInheritedRolesService` /
  `CleanupInheritedRolesService`: write derived roles directly via AR, destroy
  emptied members. Factories: `create(:project_role)`, `create(:group)`,
  `create(:member, principal:, roles:, project:)`.

### Still to verify (Phase 2+)
- Current default **project** role names for the role picker (Phase 3).
- Primer ViewComponent availability and the project-settings menu extension point
  (Phase 2).

## 11. Use case: OpenProject BIM default groups + Nextcloud

The target deployment is **OpenProject BIM**, which seeds these groups:

> Architects · BIM Coordinators · BIM Managers · BIM Modellers ·
> Lead BIM Coordinators · MEP Engineers · Planners · Structural Engineers

Each should carry a **role-set**. We **do not ship defaults** — an admin assembles
each group's role-set **by hand** on our role-set screen. We still **never create
groups or roles** — we map each group to roles that already exist in the instance.
The tier table below is **informational guidance** for that exercise, not shipped
config.

### Key finding — "Nextcloud-oriented" roles come for free

OpenProject's file-storage permissions (**"View file links"**, **"Manage file
links"**) are ordinary **project permissions**. And with **automatically-managed
project folders**, the docs state: *"Each project member will automatically get
read, write and share access permissions (according to defined File storages
permissions in the project) to this folder."*

Because this plugin materializes **real native project members** with the group's
roles, **Nextcloud folder access is provisioned automatically** by OpenProject's
existing storage sync — read/write/share follows from the file-storage permissions
in the role. So a *"Nextcloud-oriented role"* is just an OpenProject role that
includes those permissions; **this plugin needs no direct Nextcloud calls** for the
project folder. (Source: [project-settings files](https://www.openproject.org/docs/user-guide/projects/project-settings/files/).)

### Reality check on the 8 groups

Across the *discipline* groups (Architects, MEP, Structural, Modellers, Planners),
the **OpenProject roles will mostly be identical** (a contributor role + file
write). The real differentiation between disciplines — e.g. Architects writing only
to an *Architecture* subfolder — is **per-discipline Nextcloud subfolder access**,
which the single automatically-managed project folder does **not** subdivide. That
finer control is the territory of the **separate Nextcloud-integration plugin**, not
this one. So here we map the 8 groups onto a few permission **tiers**:

| BIM group | Tier | Example OpenProject role | Project folder |
| --- | --- | --- | --- |
| BIM Managers | Admin | Project admin (+ manage file storages) | write/share |
| Lead BIM Coordinators | Coordinator | Member + manage relations/hierarchies | write |
| BIM Coordinators | Coordinator | Member + manage relations / BCF | write |
| BIM Modellers | Contributor | Member (+ manage IFC models) | write |
| Architects | Contributor | Member | write |
| Structural Engineers | Contributor | Member | write |
| MEP Engineers | Contributor | Member | write |
| Planners | Contributor | Member (Gantt / versions) | write |

*Draft only.* Role **names** must match roles that exist in the instance; BIM-edition
permissions (IFC models, BCF) and file-storage permissions are bundled into those
roles by an admin. To be confirmed with the actual role list (see §10 "still to
verify").
