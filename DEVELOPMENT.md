# Dockerized development environment

Goal: develop the **ProjectGroups** plugin with **nothing installed on the host but
Docker Desktop**. Ruby / Node / PostgreSQL all live in containers. The plugin stays
a normal local folder and is **bind-mounted** into a running OpenProject dev stack.
(Note: plugin files do not hot-reload — restart the backend after edits; see §5.)

> Why not just the `openproject/openproject:17` image? That image is **production**:
> `RAILS_ENV=production`, no dev/test gems, no code reload → no `rspec`, no console
> reload, no live editing. Use OpenProject's **docker-compose dev stack** for
> development; keep the production image only to verify the final deploy (see §8.4 of
> the README).

---

## 0. Prerequisites (host)

- **Docker Desktop** with the **WSL2 backend** enabled (Windows 11).
- That's it — no Ruby, Node or Postgres on Windows.

### ⚠️ Windows performance: keep the code inside WSL2

A Rails app is tens of thousands of small files. Bind-mounting from the Windows
filesystem (`E:\…` / `/mnt/e/…`) into a Linux container is **very slow** for that
workload. **Clone everything inside the WSL2 Linux filesystem** (e.g.
`\\wsl$\Ubuntu\home\<you>\dev\…`, which is `~/dev/…` inside WSL) and run all
`docker` / `git` commands from the WSL2 shell. (You can still edit with VS Code via
the *WSL* remote extension.)

> If you keep the plugin under `E:\UNISA\PhD\dev\OpenProject\ProjectGroups`, copy or
> move the working tree into WSL2 for the dev loop; treat the Windows path as the
> "archive" copy or use git to sync.

---

## 1. Directory layout

Inside WSL2, side by side:

```
~/dev/openproject-bim/
├── openproject/            # cloned opf/openproject, checked out at the v17 tag
└── ProjectGroups/          # THIS plugin (becomes gem "openproject-project_groups")
```

The OpenProject clone is just the "host app" we run the plugin inside; the plugin is
the thing we actually version and ship.

---

## 2. One-time bootstrap

> Actual setup used here: clone is on `E:\UNISA\PhD\dev\OpenProject\openproject`
> (sibling of `ProjectGroups`), branch `release/17.5`, BIM edition. Runtimes
> confirmed from the image build: **Ruby 4.0.2**, **Node 22.21.0**.

```bash
# 1) Get OpenProject at the deployed major (v17). Shallow + single branch is faster.
git clone --depth 1 --single-branch --branch release/17.5 \
  https://github.com/opf/openproject.git openproject
cd openproject
```

### ⚠️ 1b. Windows: fix line endings BEFORE building (mandatory)

Windows git checks out the shell scripts (`docker/dev/backend/scripts/setup`,
`run-app`, …) with **CRLF**. They have no `.sh` extension, so `.gitattributes`
doesn't force LF, and the `\r` corrupts the shebang → the container fails with
`exec /usr/sbin/setup: no such file or directory`. Renormalize to LF, **then** build:

```bash
git config core.autocrlf false
git config core.eol lf
git rm --cached -r -q .      # clear index (leaves untracked .env etc. alone)
git reset --hard            # re-checkout all files as LF
```

```bash
# 2) Dev env config
cp .env.example .env
#   set OPENPROJECT_EDITION=bim in .env
cp docker-compose.override.example.yml docker-compose.override.yml
#   add the plugin bind mount (§3a) + Gemfile.plugins (§3b) now, so the first
#   bundle includes the plugin (the gemspec already exists from Phase 0 scaffolding)

# 3) Build + setup (rebuild image so the LF scripts get baked in)
docker compose run --build --rm -T backend setup   # image build + bundle + db create/migrate/seed
docker compose run --rm frontend npm install

# 4) BIM edition seed (the 8 BIM groups)
docker compose up -d worker
docker compose exec -u root worker setup-bim

# 5) Start + verify
docker compose up -d backend                        # app on http://localhost:3000
```

Confirm `http://localhost:3000` loads, then continue.

---

## 3. Mount the plugin into the dev stack

### 3a. Add a bind mount (in `openproject/docker-compose.override.yml`)

Mount the plugin to a fixed absolute path in **every app container** (`backend`,
`backend-test`, and a `worker` if your compose defines one — our `ReconcileJob` runs
on the background queue):

```yaml
services:
  backend:
    volumes:
      - ../ProjectGroups:/plugins/openproject-project_groups
  backend-test:
    volumes:
      - ../ProjectGroups:/plugins/openproject-project_groups
  # worker:
  #   volumes:
  #     - ../ProjectGroups:/plugins/openproject-project_groups
```

### 3b. Register the gem (in `openproject/Gemfile.plugins`)

```ruby
group :opf_plugins do
  gem "openproject-project_groups", path: "/plugins/openproject-project_groups"
end
```

> `bundle install` reads `/plugins/openproject-project_groups/openproject-project_groups.gemspec`.
> That file doesn't exist until we scaffold the engine — so do §4 first, or bundle
> will fail.

---

## 4. Scaffold the plugin (once)

Run the official generator **inside the backend container**, targeting the mounted
path so the output lands in the local `ProjectGroups/` folder:

```bash
docker compose run --rm \
  -v ../ProjectGroups:/plugins/openproject-project_groups \
  backend bundle exec rails generate open_project:plugin project_groups /plugins
```

This creates `openproject-project_groups` (engine, gemspec, `db/`, `lib/`, etc.) in
`ProjectGroups/`. Then do §3 (mount + `Gemfile.plugins`) and re-bundle:

```bash
docker compose run --rm backend setup            # re-bundle (now includes our gem) + migrate
docker compose restart backend
```

---

## 5. Daily loop

```bash
# logs / app
docker compose up -d backend
docker compose logs -f backend

# Rails console (poke at our models / services)
docker compose exec backend bundle exec rails console

# run OUR migrations after adding one
docker compose run --rm backend setup            # or: ... bundle exec rake db:migrate

# tests (the §4 reconciliation scenarios live here)
# The test stack uses a SEPARATE DB (db-test) reachable only from backend-test, and
# the test image's entrypoint (run-test) blocks waiting for the Selenium grid.
# For non-browser (service/unit) specs, start db-test and override the entrypoint to
# skip the grid wait — no selenium/frontend-test needed:
docker compose up -d db-test
docker compose run --rm --no-deps --entrypoint sh backend-test -lc \
  "bundle exec rails db:test:prepare && bundle exec rspec /plugins/openproject-project_groups/spec/services/project_groups/reconcile_spec.rb"
# (For browser/system specs, run the full stack so the grid is available:
#  docker compose up -d backend-test  — which starts selenium-hub, chrome, frontend-test, …)
```

**What reloads vs. what needs a restart:**
- ⚠️ **Plugin `app/` files (views, controllers, models, services) do NOT hot-reload**
  in this stack — only the *main app's* views live-reload. After editing any plugin
  file, `docker compose restart backend` (~1–2 min) before testing in the browser.
  (Specs are unaffected — each `rspec` run boots fresh and sees current code.)
- Editing `lib/open_project/project_groups/engine.rb`, initializers, routes,
  `config/locales/*.yml`, or adding a migration → `docker compose restart backend`
  (and run migrations).
- Changing the gemspec / `Gemfile.plugins` → `docker compose run --rm backend setup`.

---

## 6. Verifying the production build (occasionally)

Before shipping, confirm the plugin also works in the real production image (this is
the §8.4 path in the README), since dev mode masks asset/bundle issues:

```bash
# from a folder containing the Dockerfile + Gemfile.plugins (see README §8.4)
docker build --pull -t openproject-projectgroups .
docker run -p 8080:80 --rm -it openproject-projectgroups
```

Then point the OpenProject service in the **real stack's** `docker-compose.yml` at
`openproject-projectgroups` instead of the stock image.

---

## 7. Cheat sheet

| Task | Command |
| --- | --- |
| Start app | `docker compose up -d backend` |
| Logs | `docker compose logs -f backend` |
| Console | `docker compose exec backend bundle exec rails console` |
| Migrate / reseed | `docker compose run --rm backend setup` |
| Run our specs | `docker compose exec backend-test bundle exec rspec /plugins/openproject-project_groups/spec` |
| Re-bundle | `docker compose run --rm backend setup` |
| Restart after engine change | `docker compose restart backend` |
| Build prod image | `docker build -t openproject-projectgroups .` |

*(Service names — `backend`, `backend-test`, `frontend`, possibly `worker` — and the
exact v17 tag should be confirmed against your checkout. Sources: OpenProject [Docker
dev setup](https://www.openproject.org/docs/development/development-environment/docker/)
and [adding plugins to Docker](https://www.openproject.org/docs/installation-and-operations/installation/docker/).)*
