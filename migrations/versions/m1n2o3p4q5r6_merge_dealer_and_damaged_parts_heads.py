"""merge dealer and damaged_parts heads

Revision ID: m1n2o3p4q5r6
Revises: c9d8e7f6a5b4, g2h3i4j5k6l7
Create Date: 2026-04-15
"""

from __future__ import annotations


revision = "m1n2o3p4q5r6"
down_revision = ("c9d8e7f6a5b4", "g2h3i4j5k6l7")
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Merge-only migration: no schema changes, just unifies both branches.
    pass


def downgrade() -> None:
    # No-op downgrade for merge migration.
    pass
