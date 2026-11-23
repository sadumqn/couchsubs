# SPDX-License-Identifier: AGPL-3.0-only
"""Publish JSON outputs only after serialization has completed successfully."""
import json
import os
import tempfile
from pathlib import Path


def dump_atomic(value, destination, **kwargs):
    target = Path(destination)
    staged = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=target.parent,
                                         prefix="." + target.name + ".", suffix=".tmp",
                                         delete=False) as output:
            staged = Path(output.name)
            json.dump(value, output, **kwargs)
        os.replace(staged, target)
    finally:
        if staged is not None:
            staged.unlink(missing_ok=True)
