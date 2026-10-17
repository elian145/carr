"""Automated listing moderation (advisory engine + guarded auto-approval).

Decisions: ``AUTO_APPROVE`` / ``NEEDS_REVIEW`` / ``HOLD`` -- never a reject.
Default mode is ``shadow``: decisions are recorded and compared with human
decisions, nothing is published. See ``config.py`` for the modes, the kill
switch and the environment variables, and ``engine.py`` for the pipeline.
"""

ENGINE_VERSION = "1"
