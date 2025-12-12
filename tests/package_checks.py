from __future__ import annotations

import logging

import myproject

logger = logging.getLogger(__name__)


def check_version() -> None:
    logger.info("Checking __version__...")
    assert myproject.__version__ != "0.0.0"


def main() -> None:
    check_version()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    main()
