/**
 * Minimal TypeScript loader for the admin-web unit tests (no extra deps).
 *
 * Transpiles the REAL source files in `src/` with the repo's own `typescript`
 * devDependency and evaluates them as CommonJS, so the tests exercise the
 * shipped code instead of a hand-copied mirror of it. Supports the `@/` alias,
 * relative imports, and per-test stubs for framework modules (`next/server`,
 * `next/headers`).
 */
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const nodeRequire = createRequire(import.meta.url);
const ts = nodeRequire("typescript");

function resolveFile(base) {
  const candidates = [
    base,
    `${base}.ts`,
    `${base}.tsx`,
    path.join(base, "index.ts"),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c) && fs.statSync(c).isFile()) return c;
  }
  throw new Error(`ts-loader: cannot resolve ${base}`);
}

export function createTsLoader(stubs = {}) {
  const cache = new Map();

  function load(file) {
    const abs = resolveFile(file);
    if (cache.has(abs)) return cache.get(abs).exports;
    const source = fs.readFileSync(abs, "utf8");
    const { outputText } = ts.transpileModule(source, {
      fileName: abs,
      compilerOptions: {
        module: ts.ModuleKind.CommonJS,
        target: ts.ScriptTarget.ES2020,
        esModuleInterop: true,
        jsx: ts.JsxEmit.ReactJSX,
      },
    });
    const mod = { exports: {} };
    cache.set(abs, mod);
    const req = (spec) => {
      if (Object.prototype.hasOwnProperty.call(stubs, spec)) return stubs[spec];
      if (spec.startsWith("@/")) return load(path.join(root, "src", spec.slice(2)));
      if (spec.startsWith(".")) return load(path.resolve(path.dirname(abs), spec));
      return nodeRequire(spec);
    };
    const fn = new Function("exports", "require", "module", "__filename", outputText);
    fn(mod.exports, req, mod, abs);
    return mod.exports;
  }

  return { load: (rel) => load(path.join(root, rel)), root };
}

export { root as adminWebRoot };
