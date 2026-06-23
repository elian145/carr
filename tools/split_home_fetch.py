"""Split home_fetch.dart into core feed loading and sort fallback mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FETCH = REPO / "lib/features/home/home_fetch.dart"
FLOW = REPO / "lib/features/home/home_flow.dart"
PAGE = REPO / "lib/features/home/home_page.dart"
OUT = REPO / "lib/features/home"

lines = FETCH.read_text(encoding="utf-8").splitlines()


def find(substr: str, start: int = 0) -> int:
    for i in range(start, len(lines)):
        if substr in lines[i]:
            return i
    raise ValueError(substr)


core_start = find("void _persistCurrentHomeOffsetNow()")
sort_start = find("void onSortChanged()")

core_block = "\n".join(lines[core_start:sort_start]).rstrip()
sort_block = "\n".join(lines[sort_start:-1]).rstrip()

# Delegate client-side sort to pure helper.
sort_block = sort_block.replace(
    "List<Map<String, dynamic>> sortedCars = List.from(cars);\n\n    try {\n      switch (apiSortValue) {",
    "try {\n      final sortedCars = homeFeedClientSortedListings(cars, apiSortValue);",
)
# Remove switch body through closing of switch before "if (mounted)"
switch_start = sort_block.find("try {\n      final sortedCars")
if switch_start >= 0:
    mounted_idx = sort_block.find("      if (mounted) {\n        setState(() {\n          cars = sortedCars;")
    if mounted_idx > 0:
        # Drop old switch cases between sortedCars assignment and if (mounted)
        old_tail = sort_block[sort_block.find("homeFeedClientSortedListings(cars, apiSortValue);") : mounted_idx]
        if "switch (apiSortValue)" in old_tail or "case 'price_asc'" in old_tail:
            sort_block = (
                sort_block[: sort_block.find("homeFeedClientSortedListings(cars, apiSortValue);")
                + len("homeFeedClientSortedListings(cars, apiSortValue);")]
                + "\n\n"
                + sort_block[mounted_idx:]
            )

(OUT / "home_fetch_core.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageFetchCore on _HomePageFields {\n"
    f"{core_block}\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "home_fetch.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageFetch on _HomePageFetchCore {\n"
    f"{sort_block}\n"
    "}\n",
    encoding="utf-8",
)

flow = FLOW.read_text(encoding="utf-8")
if "home_fetch_core.dart" not in flow:
    flow = flow.replace(
        "part 'home_fetch.dart';\n",
        "part 'home_fetch_core.dart';\npart 'home_fetch.dart';\n",
    )
if "home_feed_client_sort.dart" not in flow:
    flow = flow.replace(
        "import 'home_filters_query.dart';\n",
        "import 'home_filters_query.dart';\nimport 'home_feed_client_sort.dart';\n",
    )
FLOW.write_text(flow, encoding="utf-8")

page = PAGE.read_text(encoding="utf-8")
page = page.replace(
    "_HomePageFetch,\n        _HomePageFilterCatalog",
    "_HomePageFetchCore,\n        _HomePageFetch,\n        _HomePageFilterCatalog",
)
PAGE.write_text(page, encoding="utf-8")

print("core", len(core_block.splitlines()), "sort", len(sort_block.splitlines()))
