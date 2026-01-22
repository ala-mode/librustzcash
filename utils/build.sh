#!/bin/sh

set -e

DIR="$( cd "$( dirname "$0" )" && pwd )"
REPO_ROOT="$(git rev-parse --show-toplevel)"
PLATFORM="linux/amd64"
OCI_OUTPUT="$REPO_ROOT/build/oci"
DOCKERFILE="$REPO_ROOT/Dockerfile"

export DOCKER_BUILDKIT=1
export SOURCE_DATE_EPOCH=1

echo $DOCKERFILE
mkdir -p $OCI_OUTPUT

# Extract crates from export stage
echo "Extracting crates..."
docker build -f "$DOCKERFILE" "$REPO_ROOT" --quiet \
	--platform "$PLATFORM" \
	--target export \
	--output type=local,dest="$REPO_ROOT/build" \
	"$@"
