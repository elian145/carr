#!/usr/bin/env python3
"""Fail CI when a pytest run that must execute everything reports skips.

A skipped test is not a passed test. The PostgreSQL job runs PG-only modules
that ``pytest.skip`` themselves when no server is wired; green-with-zero-PG-tests
is a false green. ``kk/tests/conftest.py`` turns the known "no PostgreSQL" skips
into failures when ``CARNET_REQUIRE_PG_TESTS=1``; this script is the
independent, reason-agnostic backstop: it reads the JUnit XML written by
``pytest --junitxml=...`` and exits 1 if

  * the file is missing/unparseable (the run never produced a report),
  * fewer than ``--min-tests`` tests were collected (a deselected/empty run),
  * any test was skipped (skip reasons are listed), unless its reason contains
    one of the ``--allow-skip`` substrings (used by the SQLite job, where the
    PostgreSQL-only tests are expected to skip and everything else must run), or
  * any test failed/errored (belt and braces; pytest already exits non-zero).

Usage:
  python -m pytest -ra --junitxml=pg.xml <files>
  python scripts/ci_assert_no_skips.py pg.xml --min-tests 200

  python -m pytest kk/tests -ra --junitxml=sqlite.xml
  python scripts/ci_assert_no_skips.py sqlite.xml --min-tests 2000 \\
      --allow-skip "CARNET_PG_TEST_URL not set" --allow-skip "..."
"""
from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET


def summarize(path: str) -> tuple[int, int, list[tuple[str, str]]]:
    """Return (tests, failures+errors, [(test id, skip reason), ...])."""
    root = ET.parse(path).getroot()
    suites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
    tests = bad = 0
    skips: list[tuple[str, str]] = []
    for suite in suites:
        for case in suite.iter("testcase"):
            tests += 1
            if case.find("failure") is not None or case.find("error") is not None:
                bad += 1
            skip = case.find("skipped")
            if skip is not None:
                name = f"{case.get('classname', '')}::{case.get('name', '')}"
                skips.append((name, (skip.get("message") or "").strip()))
    return tests, bad, skips


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("junit_xml")
    ap.add_argument("--min-tests", type=int, default=1, help="minimum tests that must have run")
    ap.add_argument(
        "--allow-skip",
        action="append",
        default=[],
        metavar="SUBSTRING",
        help="tolerate skips whose reason contains SUBSTRING (repeatable)",
    )
    args = ap.parse_args(argv)
    try:
        tests, bad, skips = summarize(args.junit_xml)
    except (OSError, ET.ParseError) as exc:
        print(f"ERROR: cannot read JUnit report {args.junit_xml}: {type(exc).__name__}: {exc}")
        return 1
    tolerated = [s for s in skips if any(a in s[1] for a in args.allow_skip)]
    unexpected = [s for s in skips if s not in tolerated]
    print(
        f"ci_assert_no_skips: {tests} tests, {len(skips)} skipped "
        f"({len(tolerated)} allowed), {bad} failed/errored"
    )
    rc = 0
    if tests < args.min_tests:
        print(f"ERROR: expected at least {args.min_tests} tests to run, got {tests}")
        rc = 1
    if unexpected:
        print(f"ERROR: {len(unexpected)} test(s) skipped in a run that must execute them:")
        for name, reason in unexpected:
            print(f"  SKIPPED {name} -- {reason}")
        rc = 1
    if bad:
        print(f"ERROR: {bad} test(s) failed or errored")
        rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
