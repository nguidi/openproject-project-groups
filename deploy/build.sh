#!/usr/bin/env bash
# Build the SLIM production image with the ProjectGroups plugin baked in, using
# OpenProject's official multi-stage technique (build on the full image, copy into
# slim). This is the image to run in a docker-compose / Helm (slim) stack.
#
#   OPENPROJECT_TAG=17 ./deploy/build.sh        # → openproject-whisperer:17-slim
#   OPENPROJECT_TAG=17.5.1 ./deploy/build.sh    # pin to your exact version
#
# (For a quick all-in-one eval instead, build the single-stage Dockerfile directly:
#   docker build -f deploy/Dockerfile --build-arg OPENPROJECT_TAG=17 \
#                -t openproject-whisperer:17 --pull .)
set -euo pipefail

TAG="${OPENPROJECT_TAG:-17}"                       # full base tag; final image is ${TAG}-slim
IMAGE="${IMAGE:-openproject-whisperer:${TAG}-slim}"

# Run from the repo root so the build context is the whole plugin.
cd "$(dirname "$0")/.."

echo "Building ${IMAGE} (multi-stage: builder openproject/openproject:${TAG} → slim) ..."
docker build \
  -f deploy/Dockerfile.slim \
  --build-arg "OPENPROJECT_TAG=${TAG}" \
  --pull \
  -t "${IMAGE}" \
  .

echo "Done. Image: ${IMAGE}"
echo "Smoke-test it:  SMOKE_IMAGE=${IMAGE} docker compose -f deploy/smoke-test.yml up --abort-on-container-exit --exit-code-from smoke-app"
echo "Then point your stack's OpenProject services at ${IMAGE} (see deploy/DEPLOYMENT.md)."
