import { readFile, writeSync } from 'node:fs';
import { promisify } from 'node:util';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [directory, mode] = process.argv.slice(2);
if (!['baseline', 'control', 'now', 'read'].includes(mode) || !globalThis.gc) {
  throw new Error('Use Node with --expose-gc and a valid benchmark mode');
}
const base = path.resolve(directory);
const {compile} = await import(pathToFileURL(path.join(base, 'read.mjs')).href);
const wasm = await promisify(readFile)(path.join(base, 'read.wasm'));
const instance = await (await compile(wasm)).instantiate({});
instance.invokeMain();
for (let attempt = 0; typeof globalThis.trueTimeBench !== 'function'; attempt++) {
  if (attempt >= 100) throw new Error('Fixture did not initialize');
  await new Promise(resolve => setTimeout(resolve, 10));
}
const reads = 2_000_000;
const details = mode === 'read';
if (mode === 'now' || mode === 'read') globalThis.trueTimeBench(details, 100_000);
globalThis.gc();
globalThis.gc();
writeSync(2, `QUALIFICATION_BEGIN ${mode} ${reads} ${process.versions.v8} ${globalThis.trueTimeClockDomain}\n`);
let checksum = 0;
if (mode === 'now' || mode === 'read') {
  checksum = globalThis.trueTimeBench(details, reads);
} else if (mode === 'control') {
  checksum = globalThis.trueTimeAllocationControl(100_000);
} else {
  for (let i = 0; i < reads; i++) checksum ^= i;
}
// Close the last allocation interval. The objects in the positive control remain live.
globalThis.gc();
globalThis.gc();
writeSync(2, `QUALIFICATION_END ${checksum}\n`);
