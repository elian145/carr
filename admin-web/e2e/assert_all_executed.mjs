// Fails the CI job unless every Playwright spec actually RAN and passed.
//
// Playwright reports a skipped test as a success, so a gate that only checks the
// exit code stays green while the authenticated specs silently skip (that was
// the state of this job before the seeded backend was added: 9 passed / 17
// skipped). Usage: node e2e/assert_all_executed.mjs <min-total> <report.json>...
import fs from "node:fs";

const [minTotalArg, ...files] = process.argv.slice(2);
const minTotal = Number(minTotalArg);
if (!Number.isFinite(minTotal) || files.length === 0) {
  console.error("usage: assert_all_executed.mjs <min-total> <report.json>...");
  process.exit(2);
}

const sum = { expected: 0, skipped: 0, unexpected: 0, flaky: 0 };
for (const f of files) {
  if (!fs.existsSync(f)) {
    console.error(`MISSING report ${f} (the Playwright run did not produce results)`);
    process.exit(1);
  }
  const stats = JSON.parse(fs.readFileSync(f, "utf-8")).stats || {};
  for (const k of Object.keys(sum)) sum[k] += Number(stats[k] || 0);
  console.log(`${f}: ${JSON.stringify(stats)}`);
}
const total = sum.expected + sum.skipped + sum.unexpected + sum.flaky;
console.log(`TOTAL ${JSON.stringify({ ...sum, total })} (required: total >= ${minTotal}, skipped = 0)`);

const problems = [];
if (sum.skipped > 0) problems.push(`${sum.skipped} test(s) were SKIPPED - skipped is not passed`);
if (sum.unexpected > 0) problems.push(`${sum.unexpected} test(s) failed`);
if (sum.flaky > 0) problems.push(`${sum.flaky} test(s) were flaky (passed only on retry)`);
if (total < minTotal) problems.push(`only ${total} tests found, expected at least ${minTotal}`);
if (problems.length) {
  for (const p of problems) console.error(`FAIL: ${p}`);
  process.exit(1);
}
console.log("OK: every Playwright spec executed and passed");
