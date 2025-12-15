r"""Implement a module for testing purposes."""

from __future__ import annotations

__all__ = ["my_function"]

def my_function(name: str) -> str:
    r"""Return Hello World message.

    Args:
        name: Name of the person to greet.

    Returns:
        Hello World message.
    """
    return f'Hello {name}!'