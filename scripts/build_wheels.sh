#!/usr/bin/env bash
# Builds molpert wheels for every combination of rdkit and Python version,
# installs each into a fresh venv and runs the smoke test before keeping it.
#
# Usage:
#   RDKIT_VERSIONS="2024.9.6 2026.3.6" PYTHON_VERSIONS="3.11 3.12" \
#     scripts/build_wheels.sh
#
# Wheels are written to $OUT_DIR (default: dist).
# Set MOLPERT_LOCAL_VERSION_SUFFIX to append a segment to the wheels' local
# version label, e.g. test1 gives 0.0.1+rdkit2024.9.6.test1.
# For GNU/Linux wheels use build_linux_wheels.sh, which runs this script in
# the manylinux containers the rdkit wheels are built in.
set -euo pipefail

RDKIT_VERSIONS=${RDKIT_VERSIONS:-2024.9.6}
PYTHON_VERSIONS=${PYTHON_VERSIONS:-3.12}
OUT_DIR=${OUT_DIR:-dist}
# Match the minimum macOS version of the rdkit wheels.
export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-11.0}

repo=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT_DIR"
out_dir=$(cd "$OUT_DIR" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for rdkit in $RDKIT_VERSIONS; do
  echo "rdkit==$rdkit" > "$tmp/constraints.txt"
  for python in $PYTHON_VERSIONS; do
    echo "==> rdkit $rdkit, Python $python"
    rm -rf "$tmp/wheel" "$tmp/venv"
    uv build "$repo" --wheel --python "$python" \
      --build-constraint "$tmp/constraints.txt" --out-dir "$tmp/wheel"
    wheel=$(ls "$tmp"/wheel/*.whl)
    if [[ $(uname) == Linux ]]; then
      # Check manylinux compliance and apply the platform tag. RDKit and Boost
      # are excluded: they are loaded from the rdkit wheel at runtime.
      auditwheel repair --exclude 'libRDKit*' --exclude 'libboost*' \
        --wheel-dir "$tmp/wheel/repaired" "$wheel"
      wheel=$(ls "$tmp"/wheel/repaired/*.whl)
    fi
    uv venv --quiet --python "$python" "$tmp/venv"
    VIRTUAL_ENV="$tmp/venv" uv pip install --quiet "$wheel"
    # Run outside the repository so the installed module is imported.
    (cd "$tmp" && "$tmp/venv/bin/python" "$repo/tests/smoke_test.py")
    mv "$wheel" "$out_dir/"
    echo "==> $out_dir/$(basename "$wheel")"
  done
done
