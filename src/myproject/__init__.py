r"""Root package for myproject.

This is a test package used to validate the verify-uv-build-action GitHub Action.
It demonstrates proper package structure including:

- Version management via importlib.metadata
- Type hints with py.typed marker
- Standard package metadata

Attributes:
    __version__: Package version string, retrieved from package metadata
"""

from __future__ import annotations

__all__ = ["__version__"]

from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version(__name__)
except PackageNotFoundError:  # pragma: no cover
    # Package is not installed, fallback if needed
    __version__ = "0.0.0"


