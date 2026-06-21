# Deploying ProjectGroups to a production OpenProject stack

There are **two ways** to get the plugin into your stack. Which one is available
depends on **which OpenProject image you run**:

| Image | What it is | Plugin install |
| --- | --- | --- |
| `openproject/openproject:17` | **All-in-one** (embedded DB; "quick start") | **Option A (bake)** *or* **Option B (runtime mount)** |
| `openproject/openproject:17-slim` | **Slim** (external DB; recommended for production — compose/Helm) | **Option A (bake) only** |

- **Option A — Bake (recommended).** Build a derived image with the plugin baked in.
  Fast, deterministic, offline startup; works on **both** images. (§1–§4.)
- **Option B — Runtime mount (all-in-one only).** Mount the plugin folder + a
  `Gemfile.local`; the all-in-one image's startup runs `bundle install` and loads it.
  No image build, but **every container start** re-runs `bundle install` + `npm
  install` + `assets:precompile` (slow, **needs internet**), and you must set
  `BUNDLE_FROZEN=false`. Good for trying it out; less ideal for production. (§B.)

Artifacts in this folder:
- **`Dockerfile.slim`** + **`build.sh`** + **`Gemfile.plugins`** — Option A for a
  **slim** stack: OpenProject's official **multi-stage** technique (build the plugin on
  the full image → copy into slim). *Recommended — this is your case.*
- **`Dockerfile`** — Option A **single-stage**, for a quick **all-in-one** eval only.
- **`Dockerfile.git-slim`** / **`Dockerfile.git-slim-singlestage`** + **`Gemfile.plugins.git`**
  — Option A **git-sourced**: the plugin is **cloned from git at build time**, so the build
  context is just a Dockerfile + a one-line Gemfile.plugins (no source tree). Two flavors —
  multi-stage (cleanest image) or single-stage (the classic recipe; installs+purges git).
  See §2b.
- **`Gemfile.local`** — for Option B (runtime mount, all-in-one only).
- **`smoke-test.yml`** + **`smoke_check.rb`** — verify a built image.
- (`.dockerignore` lives at the repo root.)

---

# Option A — Bake the plugin into a derived image (recommended)

---

## 1. Pin the version

Build against the **exact image tag your stack runs** — match the `image:` in your
compose so the result is a drop-in replacement. Set `OPENPROJECT_TAG` accordingly:

- **Compose / Helm (slim):** use the **`-slim`** tag, e.g. `17-slim` or `17.5.1-slim`.
- All-in-one: `17` or `17.5.1`.

```bash
OPENPROJECT_TAG=17-slim ./deploy/build.sh   # → openproject-project-groups:17-slim
```

> Backend-only plugin → no asset precompile, no Node build. The Dockerfile is
> intentionally minimal. (`bundle install` adds the path gem; our only dependency,
> Rails, is already in the base image, so no native compilation — works on slim.)
>
> Relation to the docs: OpenProject's *deb/rpm* plugin guide
> (`configuration/plugins`) uses `CUSTOM_PLUGIN_GEMFILE` + `openproject configure` —
> that's the **package** installer, not Docker. The Docker equivalent is this bake
> (`Gemfile.plugins` is auto-loaded by OpenProject's `Gemfile`, same as the env var).

---

## 2. Build the image

From the **plugin repo root**. Set `OPENPROJECT_TAG` to your stack's version **without**
`-slim` — the multi-stage build uses the *full* image as the builder and outputs a
*slim* image (`…-slim`):

```bash
OPENPROJECT_TAG=17 ./deploy/build.sh        # → openproject-project-groups:17-slim
# or directly:
docker build -f deploy/Dockerfile.slim --build-arg OPENPROJECT_TAG=17 \
             -t openproject-project-groups:17-slim --pull .
```

It builds the plugin on `openproject/openproject:17` (which has git/node/build tools, so
`bundle install` works), then copies the gem + plugin source into
`openproject/openproject:17-slim`. The slim image can't build the gem itself — that's
why the full image is used as a builder (OpenProject's official multi-stage technique).

> Quick all-in-one eval instead (single image, embedded DB):
> `docker build -f deploy/Dockerfile --build-arg OPENPROJECT_TAG=17 -t openproject-project-groups:17 --pull .`

### Verify the build (runtime smoke test)

Boots the image in **production mode** against a throwaway Postgres, initialises the
schema, runs the plugin's migrations, and asserts the module/tables/permissions are
wired up:

```bash
SMOKE_IMAGE=openproject-project-groups:17-slim \
  docker compose -f deploy/smoke-test.yml up --abort-on-container-exit --exit-code-from smoke-app
docker compose -f deploy/smoke-test.yml down -v   # cleanup
```

Pass = `SMOKE_RESULT ok=true …` and exit code 0. (Defaults to the all-in-one
`openproject-project-groups:17`; override with `SMOKE_IMAGE` as above.)

> The harness is image-aware: the all-in-one image ships `db/structure.sql` (loaded
> directly), while the **slim** image omits it on purpose, so the schema is built from
> migration history (`db:migrate` from scratch — the same path OpenProject's own CI
> uses). The slim run is therefore a few minutes slower but exercises the real deploy
> artifact end-to-end.

---

## 2b. Variant — git-sourced build (minimal build context)

Use this when you want to build the image **on the deploy host** (or in CI) **without
shipping the plugin source tree** — e.g. dropping just two files into
`/setup/openproject`. Instead of a `path:` gem copied from the context, Bundler
**clones the plugin from git at build time**.

**Why the source still ends up in the image:** OpenProject loads the plugin as a *gem*,
so its code must be present at runtime. A `Gemfile`/`Gemfile.lock` alone never carries
code. The git variant just changes *where the code comes from* (a clone, fetched during
`bundle install`) — not whether it's in the image.

**Prerequisites**
- The plugin is pushed to a git repo with the **tag** referenced in `Gemfile.plugins.git`
  (default `v0.1.0`, matching `OpenProject::ProjectGroups::VERSION`).
- The **build host has network access** to that repo. Private repo → supply build-time
  credentials, e.g. a token in the URL via a `--build-arg`/secret, or a mounted SSH
  key + `git:` URL. (No git or credentials are needed at *runtime*.)

**Steps**

```bash
# 1) one-time: publish the plugin to git with a release tag
cd ProjectGroups
git init && git add -A && git commit -m "Release v0.1.0"
git remote add origin https://github.com/<you>/openproject-project_groups.git
git push -u origin main
git tag v0.1.0 && git push --tags

# 2) in your build folder (e.g. /setup/openproject) keep just two files:
#    Dockerfile        (copy of deploy/Dockerfile.git-slim)
#    Gemfile.plugins   (copy of deploy/Gemfile.plugins.git — set your repo URL + tag)
cp deploy/Dockerfile.git-slim   /setup/openproject/Dockerfile   # multi-stage (see flavors below)
cp deploy/Gemfile.plugins.git   /setup/openproject/Gemfile.plugins
# edit Gemfile.plugins -> point git: at your repo, tag: at your release

# 3) build (context = that folder; no plugin source in it)
cd /setup/openproject
docker build -f Dockerfile --build-arg OPENPROJECT_TAG=17 \
             -t openproject-project-groups:17-slim --pull .
```

**Two flavors** (the slim image ships no `git`/compiler, so a fresh clone needs git from
somewhere):

- **Multi-stage** — `Dockerfile.git-slim` (above). Bundler clones + installs on the
  *full* image (which has git), then only the finished bundle is copied into slim. The
  runtime image never carries build tools. `--build-arg OPENPROJECT_TAG=17` (no `-slim`;
  the file appends it). *Cleanest image — recommended.*
- **Single-stage** — `Dockerfile.git-slim-singlestage`. The classic "FROM image → add
  plugin → bundle install → boot" recipe, run directly on slim: it `apt-get install`s git
  for the build and **purges it again** in the same layer. One `FROM`, easier to read;
  pass your **exact slim tag**, `--build-arg OPENPROJECT_TAG=17-slim`. Functionally
  identical result.

Verify it with the same smoke test (`SMOKE_IMAGE=openproject-project-groups:17-slim …`,
§2), then use it in your stack exactly as below. To release a new plugin version, push a
new tag, bump `tag:` in `Gemfile.plugins`, and rebuild.

---

## 3. Use it in your stack

In your stack's `docker-compose.yml`, point **every OpenProject service** (commonly
`web`, `worker`, `cron`, and the `seeder`/`migrate` one-off) at the new image instead
of `openproject/openproject:17-slim`:

```yaml
services:
  web:
    image: openproject-project-groups:17-slim   # was: openproject/openproject:17-slim
    # ...unchanged: env, volumes, depends_on (db, cache, nextcloud), ...
  worker:
    image: openproject-project-groups:17-slim
    # ...
  seeder:
    image: openproject-project-groups:17-slim
    # ...
```

> Update **all** OpenProject services to the same image. The `seeder`/`migrate`
> service runs the DB migrations (incl. our 4 tables) for the slim/compose stack.

> Use the **same image** for web and worker — the worker runs our `ReconcileJob`.

Then:

```bash
docker compose up -d
```

**Migrations** for the four `project_groups_*` tables run automatically on container
start (the image entrypoint applies pending migrations). Confirm in the web logs, or
run a full re-sync once after first deploy:

```bash
docker compose exec web bundle exec rake project_groups:reconcile_all
```

---

## 4. Turn it on (per the README usage)

1. **Administration → Users & Permissions → Group role-sets** → assign project roles
   to each group (e.g. the BIM groups).
2. In a project: **Project settings → Modules** → enable **Groups and Members**
   (native *Members* hides).
3. **Project → Groups and Members** → attach a group → add users.

Health check any time:

```bash
docker compose exec web bundle exec rake project_groups:check   # reports core-propagation conflicts
```

---

## 5. Upgrading

- **OpenProject upgrade:** bump `OPENPROJECT_TAG` to the new version, rebuild, redeploy.
  Pending migrations (core + ours) run on start. Re-test the plugin pages on the new
  version first (Primer component APIs can shift between releases).
- **Plugin upgrade:** pull the new plugin source, rebuild the image, redeploy.

## 6. Rollback

Point the OpenProject services back at the stock `openproject/openproject:<tag>`.
Our tables remain but are inert (no engine to read them); native membership is
unaffected because our roles are plain `MemberRole`s. To also strip the materialised
roles first, run `rake project_groups:reconcile_all` after emptying the role-sets, or
remove the rows manually.

---

## 7. Registry (optional)

For multi-host stacks, tag and push to a registry instead of building on each host:

```bash
docker tag openproject-project-groups:17 registry.example.com/openproject-project-groups:17
docker push registry.example.com/openproject-project-groups:17
```

---

# Option B — Runtime mount (all-in-one image only)

No image build: mount the plugin folder + a `Gemfile.local`, and the **all-in-one**
image installs the plugin on startup. Its `supervisord` startup runs `bundle install`
(+ `npm install` + `assets:precompile`) and migrations whenever `/app/Gemfile.local`
is present — verified against `openproject/openproject:17`.

**Requirements / caveats** (why Option A is recommended for production):
- **All-in-one image only** (`openproject/openproject:17`), *not* `-slim` — the slim
  image's `web`/`worker` entrypoints don't run the plugin installer.
- You **must set `BUNDLE_FROZEN=false`** — the image ships a frozen bundle; without it
  the startup `bundle install` aborts with *"the lockfile can't be updated because
  frozen mode is set"* (confirmed).
- The container needs **internet at startup** (bundle re-resolves from rubygems/git),
  and **every start re-runs** `bundle install` + `npm install` + `assets:precompile`
  → noticeably **slower boots** than the baked image.

### Steps

1. Place the plugin source + `Gemfile.local` where your compose can mount them, e.g.:

   ```
   <stack>/plugins/openproject-project_groups/   # this plugin's source
   <stack>/plugins/Gemfile.local                 # copy of deploy/Gemfile.local
   ```

   `Gemfile.local` (path is relative to /app):

   ```ruby
   group :opf_plugins do
     gem "openproject-project_groups", path: "plugins/openproject-project_groups"
   end
   ```

2. On the **openproject** (all-in-one) service in your `docker-compose.yml`:

   ```yaml
   services:
     openproject:
       image: openproject/openproject:17
       environment:
         BUNDLE_FROZEN: "false"          # required
         # ...your existing env (SECRET_KEY_BASE, OPENPROJECT_HOST__NAME, ...)
       volumes:
         - ./plugins/openproject-project_groups:/app/plugins/openproject-project_groups:ro
         - ./plugins/Gemfile.local:/app/Gemfile.local:ro
         # ...your existing volumes (pgdata, opdata, ...)
   ```

3. `docker compose up -d` and watch the logs: you'll see *"Installing plugins…"* →
   migrations → app start. Our four `project_groups_*` tables migrate automatically.

   > Instead of mounting `Gemfile.local`, you can set **`PLUGIN_GEMFILE_URL`** to a URL
   > the container downloads the Gemfile.local from on each start.

Enabling the plugin afterwards is the same as **§4** above.
