import test from "node:test";
import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

test("entry page references local assets that exist", async () => {
  const html = await readFile(resolve(projectRoot, "index.html"), "utf8");
  const paths = [...html.matchAll(/(?:href|src)="\.\/([^"#?]+)(?:[?#][^"]*)?"/g)].map((match) => match[1]);
  assert.deepEqual(paths.sort(), ["src/app.js", "styles.css"]);
  await Promise.all(paths.map((path) => access(resolve(projectRoot, path))));
});

test("reference Swift baseline is retained and identified", async () => {
  const source = await readFile(resolve(projectRoot, "reference/MASTER_v1.9.1_PRO_BASE.swift"), "utf8");
  assert.match(source, /MASTER_v1\.9\.1_PRO_BASE/);
  assert.match(source, /let handsCount = 10/);
  assert.match(source, /EV core unchanged \(MC-first, Exact-on-demand\)/);
});
