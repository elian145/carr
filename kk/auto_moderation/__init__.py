"""Automated listing moderation (advisory engine + guarded auto-approval).

Decisions: ``AUTO_APPROVE`` / ``NEEDS_REVIEW`` / ``HOLD`` -- never a reject.
Default mode is ``shadow``: decisions are recorded and compared with human
decisions, nothing is published. See ``config.py`` for the modes, the kill
switch and the environment variables, and ``engine.py`` for the pipeline.
"""

# "2": adds the cross-field consistency checks (rules.check_consistency). Only
# recorded on each run so decisions made before / after can be told apart; it
# never changes how an existing run is claimed or applied.
ENGINE_VERSION = "2"
