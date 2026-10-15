#!/usr/bin/env bash
# Builds manylinux wheels by running build_wheels.sh in the manylinux_2_28
# containers the rdkit wheels are built in. Requires Docker.
#
# Usage:
#   RDKIT_VERSIONS="2024.9.6" PYTHON_VERSIONS="3.12" ARCHS="x86_64 aarch64" \
#     scripts/build_linux_wheels.sh
#
# Takes the same variables as build_wheels.sh, plus ARCHS
# (default: x86_64 aarch64). Building for a foreign architecture runs under
# emulation and is considerably slower.
set -euo pipefail

ARCHS=${ARCHS:-x86_64 aarch64}
repo=$(cd "$(dirname "$0")/.." && pwd)

for arch in $ARCHS; do
  case $arch in
    x86_64) platform=linux/amd64 ;;
    aarch64) platform=linux/arm64 ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
  esac
  echo "==> manylinux_2_28 $arch"
  docker run --rm --platform "$platform" \
    --volume "$repo":/molpert --workdir /molpert \
    --env RDKIT_VERSIONS --env PYTHON_VERSIONS --env OUT_DIR \
    --env MOLPERT_LOCAL_VERSION_SUFFIX \
    "quay.io/pypa/manylinux_2_28_$arch" \
    bash -c '
      set -euo pipefail
      pipx install --quiet uv
      export PATH="/root/.local/bin:$PATH"
      # Build with the CPython installations of the manylinux image.
      for python in /opt/python/cp3*-cp3*[0-9]/bin; do PATH="$python:$PATH"; done
      export UV_PYTHON_PREFERENCE=only-system
      scripts/build_wheels.sh'
done
