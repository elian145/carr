#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1] / "lib"
for path in ROOT.rglob("*.dart"):
    text = path.read_text(encoding="utf-8")
    orig = text
    text = re.sub(r"import 'import '([^']+)';';", r"import '\1';", text)
    text = re.sub(r"import 'import ([^']+)';';", r"import '\1';", text)
    if text != orig:
        path.write_text(text, encoding="utf-8")
        print(path.relative_to(ROOT.parent))
