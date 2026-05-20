# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- MIT `LICENSE` file (README previously referenced it without the file).
- `scripts/one_off_migrations/` for legacy SQLite repair scripts (moved from repo root).
- This changelog.

### Removed

- Accidental repo-root scratch files (`tash list`, `*_files.txt`, local test images).
- Root-level `migrate_*.py` scripts (relocated; use Alembic for new schema changes).

### Changed

- `.gitignore` patterns for common accidental CLI artifacts and scratch listings.

## [1.0.0] - 2026-05-20

### Added

- Initial CARZO marketplace release track (Flutter client + Flask backend).
