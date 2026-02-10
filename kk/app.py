"""
Legacy entrypoint wrapper.

The canonical backend is `kk/app_new.py`. This module remains to avoid breaking
older imports/scripts; it forwards to the legacy implementation archived under
`kk/legacy/app.py`.
"""

from .legacy.app import *  # noqa: F401,F403

