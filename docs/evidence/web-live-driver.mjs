import { spawn } from 'node:child_process';
import { mkdtemp, readFile } from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

const mime = {'.html':'text/html', '.js':'application/javascript', '.mjs':'application/javascript', '.wasm':'application/wasm', '.json':'application/json', '.woff2':'font/woff2'};
const cases = process.argv.slice(2);
const results = [];
for (const testRoot of cases) {
  const root = path.resolve(testRoot);
  const mode = path.basename(root);
  const lane = path.basename(path.dirname(root));
  const profile = await mkdtemp(path.join(os.tmpdir(), 'true-time-web-live-'));
  const assets = new Set();
  const server = http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url, 'http://localhost');
      const file = path.resolve(root, `.${url.pathname === '/' ? '/index.html' : url.pathname}`);
      if (!file.startsWith(`${root}${path.sep}`)) { response.writeHead(403).end(); return; }
      const bytes = await readFile(file);
      assets.add(url.pathname);
      response.writeHead(200, {'Content-Type': mime[path.extname(file)] ?? 'application/octet-stream'}).end(bytes);
    } catch { response.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
    '--headless=new', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank',
  ], {windowsHide: true});
  let socket;
  try {
    const endpoint = await new Promise((resolve, reject) => {
      let output = '';
      const timeout = setTimeout(() => reject(Error('Chrome startup timed out')), 15000);
      chrome.stderr.on('data', data => {
        output += data;
        const match = output.match(/DevTools listening on (ws:\/\/[^\s]+)/);
        if (match) { clearTimeout(timeout); resolve(match[1]); }
      });
      chrome.on('error', error => { clearTimeout(timeout); reject(error); });
    });
    socket = new WebSocket(endpoint);
    await new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, {once: true});
      socket.addEventListener('error', reject, {once: true});
    });
    let sequence = 0;
    const pending = new Map(), requests = new Map(), outcomes = [], pageErrors = [];
    const timeHosts = new Set(['httpbin.org', 'httpbingo.org', 'example.com']);
    function report(event) {
      const params = event.params;
      if (event.method === 'Runtime.exceptionThrown') {
        pageErrors.push(params.exceptionDetails.exception?.description ?? params.exceptionDetails.text);
      } else if (event.method === 'Network.requestWillBeSent') {
        const url = new URL(params.request.url);
        if (timeHosts.has(url.hostname)) requests.set(params.requestId, {host: url.hostname, path: url.pathname, method: params.request.method});
      } else if (event.method === 'Network.responseReceived' && requests.has(params.requestId)) {
        const res = params.response;
        const headers = Object.fromEntries(Object.entries(res.headers).map(([k, v]) => [k.toLowerCase(), v]));
        const selected = Object.fromEntries(['date','cache-control','age','access-control-allow-origin','access-control-expose-headers'].filter(k => k in headers).map(k => [k, headers[k]]));
        outcomes.push({...requests.get(params.requestId), status: res.status, tls: res.securityDetails?.protocol, headers: selected});
      } else if (event.method === 'Network.loadingFailed' && requests.has(params.requestId)) {
        outcomes.push({...requests.get(params.requestId), networkError: params.errorText, blocked: params.blockedReason, cors: params.corsErrorStatus?.corsError, cancelled: params.canceled});
      }
    }
    socket.addEventListener('message', event => {
      const reply = JSON.parse(event.data);
      if (reply.method) report(reply);
      const item = pending.get(reply.id);
      if (!item) return;
      pending.delete(reply.id);
      clearTimeout(item.timer);
      if (reply.error) item.reject(Error(JSON.stringify(reply.error)));
      else item.resolve(reply.result);
    });
    function command(method, params = {}, sessionId) {
      return new Promise((resolve, reject) => {
        const id = ++sequence;
        const timer = setTimeout(() => {pending.delete(id); reject(Error(`${method} timed out`));}, 18000);
        pending.set(id, {resolve, reject, timer});
        socket.send(JSON.stringify({id, method, params, ...(sessionId ? {sessionId} : {})}));
      });
    }
    const {product} = await command('Browser.getVersion');
    const {targetId} = await command('Target.createTarget', {url: 'about:blank'});
    const {sessionId} = await command('Target.attachToTarget', {targetId, flatten: true});
    const cmd = (method, params) => command(method, params, sessionId);
    async function evaluate(expression, awaitPromise = false) {
      const reply = await cmd('Runtime.evaluate', {expression, awaitPromise, returnByValue: true});
      if (reply.exceptionDetails) throw Error(reply.exceptionDetails.exception?.description ?? reply.exceptionDetails.text);
      return reply.result.value;
    }
    async function awaitStatus(expression, predicate, label) {
      let status;
      for (let i = 0; i < 100; i++) {
        try { status = JSON.parse(await evaluate(expression) ?? 'null'); } catch (error) {
          if (!/context|navigation/i.test(String(error))) throw error;
        }
        if (predicate(status)) return status;
        if (pageErrors.length) throw Error(pageErrors.join('\n'));
        await new Promise(resolve => setTimeout(resolve, 200));
      }
      throw Error(`${label} timed out: ${JSON.stringify({status,outcomes})}`);
    }
    await cmd('Runtime.enable');
    await cmd('Page.enable');
    await cmd('Network.enable');
    await cmd('Network.setCacheDisabled', {cacheDisabled: true});
    await cmd('Page.navigate', {url: `http://127.0.0.1:${server.address().port}/`});
    const statusExpression = 'globalThis.timeQualificationStatus?.()';
    const ready = await awaitStatus(statusExpression, s => s?.availability === 'ready' && s?.groups?.length === 2, 'Live TLS sync');
    const online = outcomes.filter(o => o.status === 200 && o.method === 'HEAD' && o.tls && o.path === '/response-headers');
    if (new Set(online.map(o => o.host)).size !== 2) throw Error('Missing TLS HEAD evidence for both providers');
    if (ready.restored !== false || !ready.utc?.endsWith('Z')) throw Error('Unexpected UTC or restored flag');
    if (mode === 'wasm' ? !assets.has('/main.dart.wasm') || assets.has('/main.dart.js') : !assets.has('/main.dart.js') || assets.has('/main.dart.wasm')) throw Error('Wrong Flutter entrypoint');
    const probeUrl = (host, headers) => {
      const query = new URLSearchParams({...headers, probe: `${lane}-${mode}-${Date.now()}`});
      return `https://${host}/response-headers?${query}`;
    };
    async function probe(label, url, cancel = 0) {
      const result = JSON.parse(await evaluate(`globalThis.timeQualificationProbe(${JSON.stringify(url)},${cancel})`, true));
      if (result.accepted) throw Error(`${label} was accepted`);
      return {label, ...result};
    }
    const failures = [];
    failures.push(await probe('Date hidden by CORS', probeUrl('httpbin.org', {'Cache-Control':'no-store', 'Access-Control-Expose-Headers':'Cache-Control'})));
    failures.push(await probe('CORS origin denied', 'https://example.com/'));
    failures.push(await probe('nonzero Age', probeUrl('httpbingo.org', {'Cache-Control':'no-store', 'Access-Control-Expose-Headers':'Date, Cache-Control, Age', 'Age':'7'})));
    failures.push(await probe('redirect', 'https://httpbingo.org/redirect/1'));
    await evaluate(`(() => {
      const original = globalThis.fetch;
      globalThis.qualificationAbort = {started: false, aborted: false};
      globalThis.fetch = (url, options) => {
        if (String(url) === 'https://httpbingo.org/delay/3') {
          qualificationAbort.started = true;
          options?.signal?.addEventListener('abort', () => { qualificationAbort.aborted = true; }, {once: true});
        }
        return original.call(globalThis, url, options);
      };
      globalThis.restoreQualificationFetch = () => { globalThis.fetch = original; };
    })()`);
    failures.push(await probe('cancellation', 'https://httpbingo.org/delay/3', 300));
    const transportAbort = await evaluate('globalThis.qualificationAbort');
    await evaluate('globalThis.restoreQualificationFetch()');
    if (failures[0].code !== 'invalidDate' || failures[2].code !== 'cachedResponse' || failures[4].code !== 'cancelled' || failures[4].elapsedMs >= 1500) throw Error(`Unexpected rejection codes: ${JSON.stringify(failures)}`);
    if (!outcomes.some(o => o.host === 'example.com' && o.cors)) throw Error('The browser did not report a CORS rejection');
    if ([...requests.values()].some(o => o.host === 'httpbingo.org' && o.path === '/get')) throw Error('Browser followed the redirect');
    if (!transportAbort.started || !transportAbort.aborted) throw Error(`Fetch signal did not abort: ${JSON.stringify(transportAbort)}`);
    const hasSavedAnchor = 'Object.keys(localStorage).some(key => key.endsWith("dev.pschkllr.flutter_true_time_example.flutter_true_time.anchor.v2"))';
    const savedBeforeReload = await evaluate(hasSavedAnchor);
    if (!savedBeforeReload) throw Error('No secure-storage anchor was written during live sync');
    await evaluate('globalThis.beforeOfflineReload = true');
    await cmd('Network.setBlockedURLs', {urls:['https://httpbin.org/*','https://httpbingo.org/*']});
    const beforeReload = outcomes.length;
    await cmd('Page.reload', {ignoreCache: true});
    const offline = await awaitStatus('!globalThis.beforeOfflineReload && globalThis.timeQualificationStatus ? globalThis.timeQualificationStatus() : null', s => s?.availability === 'unavailable' && !s.syncing && s.error, 'Offline reload');
    const blocked = outcomes.slice(beforeReload).filter(o => o.blocked === 'inspector');
    if (offline.utc !== null || offline.restored !== null || new Set(blocked.map(o => o.host)).size !== 2) throw Error('Offline reload restored time or did not block both sources');
    if (!await evaluate(hasSavedAnchor)) throw Error('Saved anchor disappeared across reload');
    if (pageErrors.length) throw Error(pageErrors.join('\n'));
    results.push({lane, mode, browser:product, ready, failures, transportAbort, offline, savedBeforeReload, savedAfterReload: true, network:outcomes});
    await command('Target.closeTarget', {targetId});
  } catch (error) {
    results.push({lane, mode, error: String(error)});
  } finally {
    socket?.close();
    chrome.kill();
    await new Promise(resolve => server.close(resolve));
  }
}
console.log(JSON.stringify(results, null, 2));
if (results.some(result => result.error)) process.exitCode = 1;
