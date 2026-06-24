"""Split sell_entry.dart into router and draft-gate pages."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ENTRY = REPO / "lib/features/sell/sell_entry.dart"
OUT = REPO / "lib/features/sell"

IMPORTS_GATE = """import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/i18n/legacy_inline_text.dart';
import '../../shared/prefs/legacy_sell_draft_prefs.dart';
import '../../shared/prefs/sell_draft_step.dart';
import 'sell_draft_helpers.dart';
"""

IMPORTS_ROUTER = """import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/debug/app_log.dart';
import 'sell_draft_helpers.dart';
"""

lines = ENTRY.read_text(encoding="utf-8").splitlines()
gate_start = next(i for i, line in enumerate(lines) if line.startswith("class SellDraftGatePage"))

router_block = "\n".join(lines[13:gate_start]).rstrip()
gate_block = "\n".join(lines[gate_start:]).rstrip()

(OUT / "sell_entry_router.dart").write_text(
    IMPORTS_ROUTER + "\n" + router_block + "\n",
    encoding="utf-8",
)

(OUT / "sell_draft_gate.dart").write_text(
    IMPORTS_GATE + "\n" + gate_block + "\n",
    encoding="utf-8",
)

ENTRY.write_text(
    "export 'sell_draft_gate.dart';\n"
    "export 'sell_entry_router.dart';\n",
    encoding="utf-8",
)

print("Split sell_entry")
