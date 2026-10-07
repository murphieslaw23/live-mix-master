import assert from 'node:assert/strict';
import test from 'node:test';
import {createBroadcastMetadataHandler} from '../../api/broadcast-metadata.mjs';
import {createFingerprintLookupHandler} from '../../api/fingerprint-lookup.mjs';

const track = {artist: 'Fixture Artist', title: 'Fixture Title'};
const publicAnswers = [{address: '8.8.8.8', family: 4}];
function request() {
  return new Request('https://workspace.example.test/api/broadcast-metadata', {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({destinationId: 'radio', track})});
}
function registry(url) {
  return {LMM_BROADCAST_DESTINATIONS_JSON: JSON.stringify({radio: {transport: 'webhook', url, authorization: 'Bearer SYNTHETIC-SERVER-SECRET'}})};
}

for (const url of ['https://[::]/metadata', 'https://[::ffff:127.0.0.1]/metadata']) {
  test(`SSRF: reject prohibited IPv6 literal ${url} before dispatch`, async () => {
    let calls = 0;
    const handler = createBroadcastMetadataHandler({env: registry(url), resolveImpl: async () => publicAnswers, fetchImpl: async () => { calls++; return new Response(null, {status: 204}); }});
    const response = await handler(request());
    assert.equal(calls, 0); assert.equal(response.status, 409); assert.equal((await response.json()).failureCode, 'localBridgeRequired');
  });
}
for (const hostname of ['fc-radio.example.test', 'fd-radio.example.test']) {
  test(`SSRF: classify ${hostname} by resolved addresses rather than IPv6 prefixes`, async () => {
    let calls = 0;
    const handler = createBroadcastMetadataHandler({env: registry(`https://${hostname}/metadata`), resolveImpl: async () => publicAnswers, fetchImpl: async () => { calls++; return new Response(null, {status: 204}); }});
    const response = await handler(request()); assert.equal(response.status, 200); assert.equal(calls, 1);
  });
}
test('SSRF: reject destination URL user information before credentials are sent', async () => {
  let calls = 0;
  const handler = createBroadcastMetadataHandler({env: registry('https://user:SYNTHETIC-URL-SECRET@metadata.example.test/path'), resolveImpl: async () => publicAnswers, fetchImpl: async () => { calls++; return new Response(null, {status: 204}); }});
  const response = await handler(request()); assert.equal(calls, 0); assert.equal(response.status, 503);
  const body = await response.text(); assert.doesNotMatch(body, /SYNTHETIC|metadata\.example/);
});
test('SSRF: private DNS result prevents dispatch and has a safe bridge response', async () => {
  let resolves = 0; let calls = 0;
  const handler = createBroadcastMetadataHandler({env: registry('https://metadata.example.test/path'), resolveImpl: async () => { resolves++; return [{address: '127.0.0.1', family: 4}]; }, fetchImpl: async () => { calls++; return new Response(null, {status: 204}); }});
  const response = await handler(request()); assert.equal(resolves, 1); assert.equal(calls, 0); assert.equal(response.status, 409);
  assert.doesNotMatch(await response.text(), /127\.0\.0\.1|SYNTHETIC|metadata\.example/);
});
test('SSRF: mixed public and private DNS results reject the complete destination', async () => {
  let calls = 0;
  const handler = createBroadcastMetadataHandler({env: registry('https://metadata.example.test/path'), resolveImpl: async () => [...publicAnswers, {address: '10.0.0.1', family: 4}], fetchImpl: async () => { calls++; return new Response(null, {status: 204}); }});
  const response = await handler(request()); assert.equal(calls, 0); assert.equal(response.status, 409);
});
test('SSRF: every retry revalidates DNS and does not dispatch a newly private result', async () => {
  let resolves = 0; let calls = 0;
  const handler = createBroadcastMetadataHandler({env: registry('https://metadata.example.test/path'), resolveImpl: async () => ++resolves === 1 ? publicAnswers : [{address: '169.254.169.254', family: 4}], fetchImpl: async () => { calls++; return new Response('', {status: 503}); }, sleepImpl: async () => {}});
  const response = await handler(request()); assert.equal(resolves, 2); assert.equal(calls, 1); assert.equal(response.status, 409);
});
test('SSRF: broadcast outbound requests explicitly reject redirects', async () => {
  let redirectPolicy;
  const handler = createBroadcastMetadataHandler({env: registry('https://metadata.example.test/path'), resolveImpl: async () => publicAnswers, fetchImpl: async (_url, init) => { redirectPolicy = init.redirect; return new Response(null, {status: 204}); }});
  assert.equal((await handler(request())).status, 200); assert.equal(redirectPolicy, 'error');
});
test('SSRF: fixed fingerprint provider requests explicitly reject redirects', async () => {
  let redirectPolicy; let destination;
  const handler = createFingerprintLookupHandler({env: {ACOUSTID_API_KEY: 'SYNTHETIC-PROVIDER-KEY'}, fetchImpl: async (url, init) => { destination = String(url); redirectPolicy = init.redirect; return new Response(JSON.stringify({status: 'ok', results: []}), {status: 200}); }});
  const input = new Request('https://workspace.example.test/api/fingerprint-lookup', {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({duration: 10, fingerprint: 'synthetic-fingerprint'})});
  assert.equal((await handler(input)).status, 200); assert.equal(destination, 'https://api.acoustid.org/v2/lookup'); assert.equal(redirectPolicy, 'error');
});
