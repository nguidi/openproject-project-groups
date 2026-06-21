# Production image: the official OpenProject image with the ProjectGroups plugin
# baked in. Build from the plugin repo root (build context = the repo):
#
#   docker build -f deploy/Dockerfile -t openproject-project-groups:17 \
#                --build-arg OPENPROJECT_TAG=17 .
#
# Then point your stack's OpenProject service at this image (see deploy/DEPLOYMENT.md).

# Pin to the SAME OpenProject version your stack runs (e.g. 17, or 17.5.x).
ARG OPENPROJECT_TAG=17
FROM openproject/openproject:${OPENPROJECT_TAG}

# 1) Bake the plugin source into the image.
COPY . /app/plugins/openproject-project_groups

# 2) Register it with the app's bundle.
COPY deploy/Gemfile.plugins /app/Gemfile.plugins

# 3) Install the plugin gem. The base image ships a frozen bundle, so temporarily
#    unfreeze to add our path gem to the lock, then re-freeze (this mirrors the
#    official "adding plugins to Docker" recipe). Our gem only depends on Rails,
#    which is already present, so this is a minimal lock update.
RUN bundle config unset deployment \
 && bundle install \
 && bundle config set deployment 'true'

# NOTE: no asset precompile step on purpose — ProjectGroups is backend-only
# (server-rendered Primer/ERB; no JS/CSS/frontend module), so the base image's
# already-compiled assets are sufficient. If you ever add frontend assets, append:
#   RUN ./docker/prod/setup/precompile-assets.sh
#
# Pending migrations run automatically on container start (the OpenProject image
# entrypoint handles them); no manual db:migrate is required.
