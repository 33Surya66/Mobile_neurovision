#!/usr/bin/env bash
# Deploy helper for NeuroVision backend (bash)
# Usage:
#   ./deploy.sh build               # build image
#   ./deploy.sh run                 # build then run (localhost:5000)
#   ./deploy.sh push <docker/repo>  # tag & push to provided repo

set -euo pipefail
ROOT_DIR=$(dirname "$0")
IMAGE_NAME="neurovision-backend:local"

cmd=${1:-run}

case "$cmd" in
  build)
    echo "Building image $IMAGE_NAME"
    docker build -t "$IMAGE_NAME" "$ROOT_DIR"
    ;;
  run)
    echo "Building image $IMAGE_NAME"
    docker build -t "$IMAGE_NAME" "$ROOT_DIR"
    echo "Running image, mapping 5000:5000 and loading .env"
    docker run --rm -it -p 5000:5000 --env-file "$ROOT_DIR/.env" "$IMAGE_NAME"
    ;;
  push)
    repo=${2:-}
    if [ -z "$repo" ]; then
      echo "Usage: $0 push user/repo" >&2
      exit 2
    fi
    tag="$repo:latest"
    echo "Tagging $IMAGE_NAME -> $tag"
    docker tag "$IMAGE_NAME" "$tag"
    echo "Pushing $tag"
    docker push "$tag"
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    echo "Usage: $0 [build|run|push <repo>]" >&2
    exit 2
    ;;
esac
