# SHA256 hashes of the header sources RDKitWheel downloads.
#
# To build against a new rdkit wheel version, add the hash of its RDKit
# release tarball (and of its Boost and RingDecomposerLib releases, if they
# changed). The error message of a failing build names the missing entry and
# its URL. Compute the hash with:
#   curl -sSL <url> | shasum -a 256

# https://github.com/rdkit/rdkit/archive/refs/tags/<tag>.tar.gz
set(MOLPERT_SHA256_rdkit-Release_2024_09_6
  337075aadd51760fe920442c73972c2fef2561645785fac246615fcb03914062)
set(MOLPERT_SHA256_rdkit-Release_2026_03_6
  d4d20b3b140237084694518aab34fdba6929d44bd7f720bce69329516abef663)

# https://github.com/boostorg/boost/releases/download/boost-<version>/boost-<version>-b2-nodocs.tar.xz
set(MOLPERT_SHA256_boost-1.85.0
  09f0628bded81d20b0145b30925d7d7492fd99583671586525d5d66d4c28266a)

# https://raw.githubusercontent.com/rareylab/RingDecomposerLib/v<version>/src/RingDecomposerLib/RingDecomposerLib.h
set(MOLPERT_SHA256_RingDecomposerLib-1.1.3_rdkit
  7292fbe0285cc8b769b7bcce1c96a6ed356e0402e644fd6d9a8e1a374a922907)
