"""Wheel metadata that depends on the rdkit wheel molpert is built against.

The Python module links against the libraries bundled with the rdkit wheel in
the build environment, so the resulting wheel only works with that exact rdkit
version. This provider pins it as a dependency and appends it to the version as
a local version label, e.g. 0.0.1+rdkit2024.9.6.

Set MOLPERT_LOCAL_VERSION_SUFFIX to append a segment to the local version
label, e.g. MOLPERT_LOCAL_VERSION_SUFFIX=test1 gives 0.0.1+rdkit2024.9.6.test1.
"""

import os
import re
from importlib.metadata import version


def dynamic_metadata(settings, project):
    rdkit_version = version("rdkit")
    local_version = f"rdkit{rdkit_version}"
    suffix = os.environ.get("MOLPERT_LOCAL_VERSION_SUFFIX", "")
    if suffix:
        if not re.fullmatch(r"[a-z0-9]+(\.[a-z0-9]+)*", suffix):
            raise ValueError(
                f"MOLPERT_LOCAL_VERSION_SUFFIX={suffix!r} is not a valid local "
                "version segment: use lowercase letters and digits separated "
                "by dots, without a leading '+'")
        local_version += f".{suffix}"
    return {
        "version": f"{settings['base-version']}+{local_version}",
        "dependencies": [f"rdkit=={rdkit_version}"],
    }
