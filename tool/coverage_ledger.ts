#!/usr/bin/env bun
// Coverage ledger over an lcov.info file.
//
// Usage:
//   bun tool/coverage_ledger.ts <lcov> <label> <threshold> \
//       [--include <substr>] [--exclude <substr>]
//
// Computes line coverage across SF records whose path CONTAINS every --include
// substring and NONE of the --exclude substrings, and exits non-zero when the
// aggregate percentage is below <threshold>. Used for both the unit ledger
// (excludes the TestHelper) and the meta ledger (TestHelper only).

const [lcovPath, label, thresholdRaw, ...rest] = process.argv.slice(2);

if (!lcovPath || !label || !thresholdRaw) {
  console.error('usage: coverage_ledger.ts <lcov> <label> <threshold> [--include s] [--exclude s]');
  process.exit(2);
}

const includes: string[] = [];
const excludes: string[] = [];
for (let i = 0; i < rest.length; i += 2) {
  if (rest[i] === '--include') includes.push(rest[i + 1]);
  else if (rest[i] === '--exclude') excludes.push(rest[i + 1]);
}

const threshold = Number(thresholdRaw);
const text = await Bun.file(lcovPath).text();

let currentFile: string | null = null;
let selected = false;
let total = 0;
let covered = 0;
const perFile: Array<{ file: string; total: number; covered: number }> = [];
let fileTotal = 0;
let fileCovered = 0;

const flush = () => {
  if (selected && currentFile) {
    perFile.push({ file: currentFile, total: fileTotal, covered: fileCovered });
    total += fileTotal;
    covered += fileCovered;
  }
  fileTotal = 0;
  fileCovered = 0;
};

for (const line of text.split('\n')) {
  if (line.startsWith('SF:')) {
    flush();
    currentFile = line.slice(3).trim();
    selected = includes.every(s => currentFile!.includes(s)) && excludes.every(s => !currentFile!.includes(s));
  } else if (line.startsWith('DA:') && selected) {
    const [, hits] = line.slice(3).split(',');
    fileTotal += 1;
    if (Number(hits) > 0) fileCovered += 1;
  } else if (line.startsWith('end_of_record')) {
    flush();
    currentFile = null;
    selected = false;
  }
}
flush();

if (total === 0) {
  console.error(`❌ ${label} ledger: no matching lines found (filter mismatch)`);
  process.exit(1);
}

const pct = (covered / total) * 100;
for (const f of perFile) {
  const p = f.total === 0 ? 100 : (f.covered / f.total) * 100;
  console.log(`   ${p.toFixed(1).padStart(6)}%  ${f.file} (${f.covered}/${f.total})`);
}
console.log(`${label}: ${pct.toFixed(2)}% (${covered}/${total}) threshold ${threshold}%`);
if (pct + 1e-9 < threshold) {
  console.error(`❌ ${label} coverage ${pct.toFixed(2)}% below ${threshold}%`);
  process.exit(1);
}
console.log(`✅ ${label} coverage meets ${threshold}%`);
