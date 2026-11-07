/**
 * CSV building with spreadsheet-formula-injection (CWE-1236) protection.
 *
 * Exported cells come from user-controlled data (names, titles, messages...).
 * Excel / LibreOffice / Google Sheets evaluate a cell as a formula when it
 * starts with `=`, `+`, `-`, `@`, TAB or CR, so an attacker-supplied value such
 * as `=HYPERLINK(...)` would run on the admin's machine when the export is
 * opened. Following the OWASP guidance such cells are prefixed with a single
 * quote, which makes spreadsheets treat them as plain text.
 *
 * Numbers: rows are `string[]`, so "numeric column" is decided per cell. A cell
 * that is *only* a plain decimal number (`-12`, `3.5`, `1250000`) cannot carry
 * a formula (nothing but digits after an optional leading minus) and is
 * emitted unchanged so negative numbers stay numeric. Anything else that starts
 * with a trigger character - including `+964...` phone numbers and `-5 - 3` -
 * is prefixed. A leading `+` is deliberately NOT exempt: `+1+1` / `+cmd|...`
 * are classic payloads and a phone number is text, not a number.
 */

const FORMULA_TRIGGERS = new Set(["=", "+", "-", "@", "\t", "\r", "\n"]);

/** Plain decimal number: optional leading minus, digits, optional fraction. */
const PLAIN_NUMBER = /^-?\d+(?:\.\d+)?$/;

/** Neutralise a value that a spreadsheet could interpret as a formula. */
export function neutralizeFormula(value: string): string {
  if (value === "") return value;
  if (PLAIN_NUMBER.test(value)) return value;
  // Also guard values that only *start* with whitespace before the trigger
  // (some spreadsheets trim before evaluating).
  const firstSignificant = value.replace(/^[ \u00a0]+/, "");
  if (
    FORMULA_TRIGGERS.has(value[0]) ||
    (firstSignificant.length > 0 && FORMULA_TRIGGERS.has(firstSignificant[0]))
  ) {
    return `'${value}`;
  }
  return value;
}

/** Escape one cell: formula-neutralise, then RFC 4180 quote when required. */
export function escapeCsvCell(cell: unknown): string {
  let s: string;
  if (typeof cell === "number" && Number.isFinite(cell)) {
    // A real number (negative included) is data, never a formula.
    return String(cell);
  }
  s = cell === null || cell === undefined ? "" : String(cell);
  s = neutralizeFormula(s);
  if (/[",\r\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}

export function buildCsv(headers: string[], rows: unknown[][]): string {
  const lines = [
    headers.map(escapeCsvCell).join(","),
    ...rows.map((row) => row.map(escapeCsvCell).join(",")),
    "",
  ];
  return lines.join("\n");
}
