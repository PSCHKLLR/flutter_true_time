import { spawn } from 'node:child_process';
import { mkdtemp, readFile } from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

const root = path.resolve(process.argv[2]);
const profile = await mkdtemp(path.join(os.tmpdir(), 'true-time-read-profile-'));
const files = new Map([
  ['/read.js', 'application/javascript'],
  ['/read.mjs', 'application/javascript'],
  ['/read.wasm', 'application/wasm'],
]);
const server = http.createServer(async (request, response) => {
  const route = request.url;
  if (route === '/js') {
    response.writeHead(200, {'Content-Type': 'text/html'}).end('<!doctype html><script src="/read.js" defer></script>');
  } else if (route === '/wasm') {
    response.writeHead(200, {'Content-Type': 'text/html'}).end(`<!doctype html><script type="module">
      import {compileStreaming} from '/read.mjs';
      const program = await compileStreaming(fetch('/read.wasm'));
      const instance = await program.instantiate({});
      instance.invokeMain();
    </script>`);
  } else if (files.has(route)) {
    const bytes = await readFile(path.join(root, route.slice(1)));
    response.writeHead(200, {'Content-Type': files.get(route)}).end(bytes);
  } else {
    response.writeHead(404).end();
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank',
], {windowsHide: true});
let ws;
try {
  const endpoint = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Chrome did not start')), 15000);
    let output = '';
    chrome.stderr.on('data', chunk => {
      output += chunk;
      const match = output.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (match) { clearTimeout(timer); resolve(match[1]); }
    });
    chrome.on('error', error => { clearTimeout(timer); reject(error); });
  });
  ws = new WebSocket(endpoint);
  await new Promise((resolve, reject) => {
    ws.addEventListener('open', resolve, {once: true});
    ws.addEventListener('error', reject, {once: true});
  });
  let next = 0;
  const pending = new Map();
  const exceptions = [];
  ws.addEventListener('message', event => {
    const reply = JSON.parse(event.data);
    if (reply.method === 'Runtime.exceptionThrown') exceptions.push(reply.params.exceptionDetails.exception?.description ?? reply.params.exceptionDetails.text);
    const call = pending.get(reply.id);
    if (!call) return;
    pending.delete(reply.id);
    clearTimeout(call.timer);
    if (reply.error) call.reject(new Error(JSON.stringify(reply.error)));
    else call.resolve(reply.result);
  });
  function send(method, params = {}, sessionId) {
    return new Promise((resolve, reject) => {
      const id = ++next;
      const timer = setTimeout(() => { pending.delete(id); reject(new Error(`${method} timed out`)); }, 30000);
      pending.set(id, {resolve, reject, timer});
      ws.send(JSON.stringify({id, method, params, ...(sessionId ? {sessionId} : {})}));
    });
  }

  const {product, jsVersion} = await send('Browser.getVersion');
  const {targetId} = await send('Target.createTarget', {url: 'about:blank'});
  const {sessionId} = await send('Target.attachToTarget', {targetId, flatten: true});
  const cmd = (method, params) => send(method, params, sessionId);
  async function evaluate(expression) {
    const reply = await cmd('Runtime.evaluate', {expression, returnByValue: true});
    if (reply.exceptionDetails) throw new Error(reply.exceptionDetails.exception?.description ?? reply.exceptionDetails.text);
    return reply.result.value;
  }
  await cmd('Runtime.enable');
  await cmd('Page.enable');
  await cmd('Network.enable');
  const wasmResponses = [];
  ws.addEventListener('message', event => {
    const value = JSON.parse(event.data);
    if (value.method === 'Network.responseReceived' && value.params.response.url.endsWith('/read.wasm')) {
      wasmResponses.push(value.params.response.status);
    }
  });
  await cmd('Page.navigate', {url: 'http://127.0.0.1:' + server.address().port + '/wasm'});
  for (let attempt = 0; attempt < 60; attempt++) {
    if (await evaluate('typeof globalThis.trueTimeBench === "function" && typeof globalThis.trueTimeAllocationControl === "function"')) break;
    if (exceptions.length) throw new Error(exceptions.join('\n'));
    if (attempt === 59) throw new Error('The WASM fixture did not initialize');
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  if (wasmResponses.length !== 1 || wasmResponses[0] !== 200) throw new Error('Missing WASM module load');
  const clockDomain = await evaluate('globalThis.trueTimeClockDomain');
  const samplingIntervalBytes = 8192;
  const calls = 500000;
  const measurements = [];
  await cmd('HeapProfiler.enable');
  for (const mode of ['baseline','now','read','control']) {
    const detailed = mode === 'read';
    if (mode === 'now' || mode === 'read') await evaluate('trueTimeBench(' + detailed + ', 100000)');
    await cmd('HeapProfiler.collectGarbage');
    const before = await cmd('Runtime.getHeapUsage');
    await cmd('HeapProfiler.startSampling', {
      samplingInterval: samplingIntervalBytes,
      includeObjectsCollectedByMajorGC: true,
      includeObjectsCollectedByMinorGC: true,
    });
    let expression;
    if (mode === 'baseline') expression = '(() => { let n = 0; for(let i = 0; i < ' + calls + '; i++) n ^= i; return n; })()';
    else if (mode === 'control') expression = 'trueTimeAllocationControl(100000)';
    else expression = 'trueTimeBench(' + detailed + ',' + calls + ')';
    const checksum = await evaluate(expression);
    const {profile: heap} = await cmd('HeapProfiler.stopSampling');
    await cmd('HeapProfiler.collectGarbage');
    const after = await cmd('Runtime.getHeapUsage');
    const nodes = [heap.head];
    let scaledProfileBytes = 0;
    const topFrames = [];
    while (nodes.length) {
      const current = nodes.pop();
      scaledProfileBytes += current.selfSize;
      if (current.selfSize > 0) topFrames.push({
        functionName: current.callFrame.functionName, url: current.callFrame.url, selfSize: current.selfSize,
      });
      nodes.push(...current.children);
    }
    topFrames.sort((a,b) => b.selfSize - a.selfSize);
    measurements.push({
      mode, calls: mode === 'control' ? 100000 : calls, checksum, scaledProfileBytes,
      rawSampleEntries: heap.samples.length, beforeGcHeapUsed: before.usedSize,
      afterGcHeapUsed: after.usedSize, topFrames: topFrames.slice(0,5),
    });
  }
  await cmd('HeapProfiler.disable');
  await send('Target.closeTarget', {targetId});
  if (exceptions.length) throw new Error(exceptions.join('\n'));
  console.log(JSON.stringify({browser: product, v8: jsVersion, clockDomain, samplingIntervalBytes, measurements}, null, 2));
} finally {
  ws?.close();
  chrome.kill();
  await new Promise(resolve => server.close(resolve));
}
