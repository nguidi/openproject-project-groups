# Changelog

All notable changes to the OpenProject Project Groups plugin are documented in
this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.2] - 2026-06-22

### Changed
- **Reworked the "Project roles" tab into a two-column add/remove UI** (replacing the
  checkbox-set + Save form): the left column lists the group's **current roles** (each
  with a Remove button) and the right lists the **available roles**, filtered to exclude
  those already in the group (each with an Add button). **Both columns are independently
  paginated** (10/page, with distinct page params so they don't interfere). Add/remove
  act on a single role via new `GroupRolesController#add_role` / `#remove_role` actions,
  which recompute the set and hand it to `SetGroupRoleSet` (so member reconciliation
  still runs); the `update` action/route was replaced by these member routes.

## [0.4.1] - 2026-06-22

### Removed
- The standalone **"Group role-sets" admin screen and its sidebar entry**
  (Administration ▸ Users & Permissions) — redundant now that role-sets are edited on
  the **"Project roles" tab** of the native Group page (v0.4.0). The `index`/`edit`
  actions, their views, the `admin_menu` registration, and the unused
  `label_project_group_roles` string were removed; only `GroupRolesController#update`
  remains (the tab posts to it), now redirecting back to the tab.

## [0.4.0] - 2026-06-22

### Added
- **"Project roles" tab on the native Group page** (Administration ▸ Groups ▸ <group>).
  The group's role-set is now editable inline, alongside General / Users / Projects /
  Global roles / Synchronized groups — the same extension point the LDAP module uses
  (`GroupsHelper#group_settings_tabs`, prepended from the engine). Saves through the
  existing `ProjectGroups::Admin::GroupRolesController#update` and returns to the tab
  (via a validated `back_url`). The standalone admin role-set screen remains.

## [0.3.1] - 2026-06-22

### Fixed
- **Storage (Nextcloud) folder permissions were not provisioned** for users added to a
  group. Because `Reconcile` writes `Member`/`MemberRole` rows directly (to avoid
  add/remove e-mails), it never published the member events the storages module listens
  for, so its automatically-managed folder sync never ran. `Reconcile` now emits the
  matching `MEMBER_CREATED` / `MEMBER_UPDATED` / `MEMBER_DESTROYED` event after commit
  (with `send_notifications: false`, so the storage sync runs but no e-mails are sent) —
  mirroring OpenProject's own `Notifications::GroupMemberAlteredJob`. Any other
  event-driven integration now reacts to our materialised members too.

## [0.3.0] - 2026-06-22

### Changed
- **UI re-modeled on OpenProject's native Members module**, split into two pages:
  - **Groups** (`GroupsController#index`) — a paginated table (Name → links to the
    group's members, Roles, detach action) built on the core `::TableComponent`.
  - **Members of a group** (`MembershipsController#index`, scoped to an assignment) —
    a paginated table (Name, Email, remove action). Reached by clicking a group name;
    breadcrumbs lead back to the groups list.
- **Add Group / Add Member** use a native `Primer::OpenProject`-styled button that
  reveals an inline section (autocomplete + Add + Close) via a **CSS-only toggle** —
  no JavaScript, so it works in a backend-only plugin under OpenProject's CSP.
- Routes restructured (`project_groups/groups` + nested `…/members`); the project
  menu and permissions now point at both controllers.

## [0.2.0] - 2026-06-22

### Changed
- The "add member to group" picker is now OpenProject's `opce-user-autocompleter`
  (server-backed typeahead over active principals via `/api/v3/principals`) instead of
  a full `<select>` of every user. The controller no longer preloads `@candidate_users`.
- Destructive confirmations now use OpenProject's native `Primer::Alpha::Dialog` modal
  (with a danger Turbo `DELETE` action) instead of the browser's `confirm()` dialog.
  **Removing a member now also asks for confirmation** (previously one-click).

## [0.1.0] - 2026-06-21

Initial release. Project-scoped group membership for OpenProject: add users to a
reusable group **per project**, materialized as native project members carrying
the group's roles — without the native cross-project propagation.

### Added
- Rails engine (`OpenProject::Plugins::ActsAsOpEngine`) registering the
  **"Groups and Members"** per-project module, its `view_project_groups` and
  `manage_project_group_members` permissions, project menu entry, and a `Group`
  model patch.
- Data model: `project_groups_group_roles`, `project_groups_assignments`,
  `project_groups_memberships`, and `project_groups_managed_member_roles` tables
  with their migrations.
- `ProjectGroups::Reconcile` service (per user/project) and `Reconcile.for_group`
  fan-out, backed by managed-member-role bookkeeping so reconciliation only ever
  touches roles the plugin owns. Covered by the 8 RSpec scenarios.
- `ProjectGroups::ReconcileJob` for background fan-out on the Good Job queue.
- Project UI ("Groups and Members" page) to attach/detach groups and add/remove
  members, with the native Members menu hidden where the module is enabled.
- Admin UI (Administration ▸ Users & Permissions ▸ Group role-sets) to define
  each group's role-set; `SetGroupRoleSet` applies the change synchronously and
  fans member reconciliation out to background `ReconcileJob`s.
- All three screens rebuilt with OpenProject's native Primer ViewComponents.
- Operations: `ProjectGroups::ReconcileAll` service + `rake
  project_groups:reconcile_all` (drift repair) and `rake project_groups:check`
  (core-propagation conflict report), plus an in-page conflict warning banner.
- Deployment kit under `deploy/` (multi-stage `Dockerfile.slim`, `build.sh`,
  `Gemfile.plugins`, smoke test, and `DEPLOYMENT.md`).
- RSpec suite under `spec/`: the 8 reconciliation scenarios plus `ReconcileAll`,
  `SetGroupRoleSet`, and `ReconcileJob` service/worker specs, and model + `Group`
  patch specs (validations, `Assignment#roles`, `Membership` delegations,
  `table_name_prefix` and FK-cascade wiring).

[Unreleased]: https://github.com/nguidi/openproject-project-groups/compare/v0.4.2...HEAD
[0.4.2]: https://github.com/nguidi/openproject-project-groups/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/nguidi/openproject-project-groups/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/nguidi/openproject-project-groups/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/nguidi/openproject-project-groups/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/nguidi/openproject-project-groups/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/nguidi/openproject-project-groups/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nguidi/openproject-project-groups/releases/tag/v0.1.0
