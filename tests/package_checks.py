"""Custom package validation checks.

This module provides custom validation checks for the package that are
executed during the build verification process. These checks ensure the
package meets project-specific requirements beyond standard validation.

Usage:
    python tests/package_checks.py

Exit Codes:
    0 - All checks passed
    1 - One or more checks failed (assertion error)
"""

from __future__ import annotations

import logging

import myproject

logger = logging.getLogger(__name__)


def check_version() -> None:
    """Verify package version is not the default placeholder.

    Ensures that the package version has been properly set and is not
    the default "0.0.0" placeholder value.

    Raises:
        AssertionError: If version is "0.0.0"
    """
    logger.info("Checking __version__...")
    assert myproject.__version__ != "0.0.0"


def main() -> None:
    """Run all custom package checks."""
    check_version()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    main()
