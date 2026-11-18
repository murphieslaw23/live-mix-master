import assert from 'node:assert/strict';
import test from 'node:test';
import {EventEmitter} from 'node:events';
import {Readable} from 'node:stream';
import {createGuardedRequest, OutboundRequestError} from '../api/lib/guarded-outbound-request.mjs';

const url = 'https://metadata.example.test/path?token=synthetic';
const publicAnswers = [{address: '8.8.8.8', family: 4}];
function harness({status = 200, chunks = ['ok'], peer, authorized = true, stall = false, networkError = false} = {}) {
  const calls = [];
  const requestImpl = (options, onResponse) => {
    const request = new EventEmitter(); const call = {options, ends: 0, body: null, destroyed: false}; calls.push(call);
    request.destroy = () => { call.destroyed = true; };
    request.end = (body) => {
      call.ends++; call.body = body;
      queueMicrotask(() => {
        if (networkError) { request.emit('error', new Error('synthetic-secret endpoint')); return; }
        const response = stall ? new Readable({read() {}}) : Readable.from(chunks);
        response.statusCode = status; response.headers = {'content-type': 'text/plain', 'set-cookie': 'synthetic-secret'};
        onResponse(response);
      });
    };
    queueMicrotask(() => {
      options.lookup(options.hostname, {}, (error, address, family) => {
        if (error) { request.emit('error', error); return; }
        call.lookupAddress = address; call.lookupFamily = family;
        const socket = new EventEmitter(); socket.remoteAddress = peer ?? address; socket.authorized = authorized;
        request.emit('socket', socket); queueMicrotask(() => socket.emit('secureConnect'));
      });
    });
    return request;
  };
  return {calls, requestImpl};
}
const code = (expected) => (error) => error instanceof OutboundRequestError && error.code === expected && !/synthetic-secret|example\.test/.test(error.message);

test('guard pins one DNS result for repeated connection lookup calls and preserves TLS hostname', async () => {
  let resolves = 0; const fake = harness();
  const guarded = createGuardedRequest({resolveImpl: async () => { resolves++; return resolves === 1 ? publicAnswers : [{address: '127.0.0.1', family: 4}]; }, requestImpl: fake.requestImpl});
  assert.equal((await guarded(url, {headers: {authorization: 'Bearer synthetic-secret'}, body: 'payload'})).status, 200);
  const options = fake.calls[0].options;
  for (let i = 0; i < 2; i++) options.lookup('metadata.example.test', {}, (error, address, family) => { assert.ifError(error); assert.equal(address, '8.8.8.8'); assert.equal(family, 4); });
  options.lookup('metadata.example.test', {all: true}, (error, answers) => { assert.ifError(error); assert.deepEqual(answers, publicAnswers); });
  options.lookup('other.example.test', {}, (error) => assert.equal(error.code, 'invalidDestination'));
  assert.equal(resolves, 1); assert.equal(options.hostname, 'metadata.example.test'); assert.equal(options.servername, 'metadata.example.test'); assert.equal(options.rejectUnauthorized, true); assert.equal(options.agent, false);
  assert.equal(options.path, '/path?token=synthetic'); assert.equal(options.headers.host, 'metadata.example.test'); assert.equal(fake.calls[0].body, 'payload');
});
test('guard rejects private and mixed DNS answers before creating request', async () => {
  for (const answers of [[{address: '127.0.0.1', family: 4}], [...publicAnswers, {address: '10.0.0.1', family: 4}]]) {
    const fake = harness(); const guarded = createGuardedRequest({resolveImpl: async () => answers, requestImpl: fake.requestImpl});
    await assert.rejects(guarded(url), code('blockedDestination')); assert.equal(fake.calls.length, 0);
  }
});
test('guard rejects empty and malformed DNS answers without request', async () => {
  for (const answers of [[], [{address: '8.8.8.8', family: 6}]]) {
    const fake = harness(); const guarded = createGuardedRequest({resolveImpl: async () => answers, requestImpl: fake.requestImpl});
    await assert.rejects(guarded(url), code('invalidDnsAnswers')); assert.equal(fake.calls.length, 0);
  }
});
test('guard validates literals before DNS and normalizes mapped public addresses', async () => {
  let resolves = 0; const fake = harness(); const guarded = createGuardedRequest({resolveImpl: async () => { resolves++; return publicAnswers; }, requestImpl: fake.requestImpl});
  await assert.rejects(guarded('https://[::ffff:127.0.0.1]/'), code('blockedDestination'));
  assert.equal((await guarded('https://[::ffff:8.8.8.8]/')).status, 200); assert.equal(resolves, 0); assert.equal(fake.calls[0].options.hostname, '8.8.8.8');
});
test('guard bounds DNS wait and does not connect after late resolution', async () => {
  let resolve; const fake = harness(); const guarded = createGuardedRequest({timeoutMs: 5, resolveImpl: () => new Promise((r) => { resolve = r; }), requestImpl: fake.requestImpl});
  await assert.rejects(guarded(url), code('timeout')); resolve(publicAnswers); await new Promise((r) => setImmediate(r)); assert.equal(fake.calls.length, 0);
});
test('guard cancellation during DNS prevents late dispatch', async () => {
  let resolve; const ready = new Promise((r) => { resolve = r; }); const fake = harness(); const controller = new AbortController();
  const guarded = createGuardedRequest({resolveImpl: () => ready, requestImpl: fake.requestImpl}); const response = guarded(url, {signal: controller.signal}); controller.abort();
  await assert.rejects(response, code('cancelled')); resolve(publicAnswers); await new Promise((r) => setImmediate(r)); assert.equal(fake.calls.length, 0);
});
test('guard pre-aborted request makes no resolver or transport call', async () => {
  let resolves = 0; const fake = harness(); const controller = new AbortController(); controller.abort();
  const guarded = createGuardedRequest({resolveImpl: async () => { resolves++; return publicAnswers; }, requestImpl: fake.requestImpl});
  await assert.rejects(guarded(url, {signal: controller.signal}), code('cancelled')); assert.equal(resolves, 0); assert.equal(fake.calls.length, 0);
});
test('guard rejects mismatched peer before sending credentials or body', async () => {
  const fake = harness({peer: '127.0.0.1'}); const guarded = createGuardedRequest({resolveImpl: async () => publicAnswers, requestImpl: fake.requestImpl});
  await assert.rejects(guarded(url, {headers: {authorization: 'Bearer synthetic-secret'}, body: 'private payload'}), code('peerMismatch')); assert.equal(fake.calls[0].ends, 0); assert.equal(fake.calls[0].destroyed, true);
});
test('guard rejects unauthorized TLS fixture before writing', async () => {
  const fake = harness({authorized: false}); const guarded = createGuardedRequest({resolveImpl: async () => publicAnswers, requestImpl: fake.requestImpl});
  await assert.rejects(guarded(url), code('tlsRejected')); assert.equal(fake.calls[0].ends, 0);
});
test('guard rejects redirects without a second request', async () => {
  const fake = harness({status: 302}); const guarded = createGuardedRequest({resolveImpl: async () => publicAnswers, requestImpl: fake.requestImpl});
  await assert.rejects(guarded(url), code('redirectRejected')); assert.equal(fake.calls.length, 1);
});
test('guard bounds response size and destroys oversized response', async () => {
  const fake = harness({chunks: [Buffer.alloc(17)]}); const guarded = createGuardedRequest({maxResponseBytes: 16, resolveImpl: async () => publicAnswers, requestImpl: fake.requestImpl});
  await assert.rejects(guarded(url), code('responseTooLarge')); assert.equal(fake.calls[0].destroyed, true);
});
test('guard applies total deadline while reading body', async () => {
  const fake = harness({stall: true}); const guarded = createGuardedRequest({timeoutMs: 10, resolveImpl: async () => publicAnswers, requestImpl: fake.requestImpl});
  await assert.rejects(guarded(url), code('timeout')); assert.equal(fake.calls[0].destroyed, true);
});
test('guard prevents caller override of Host and rejects oversized request bodies', async () => {
  let resolves = 0; const fake = harness(); const guarded = createGuardedRequest({maxRequestBytes: 4, resolveImpl: async () => { resolves++; return publicAnswers; }, requestImpl: fake.requestImpl});
  await assert.rejects(guarded(url, {headers: {host: 'other.example.test'}}), code('invalidRequest')); await assert.rejects(guarded(url, {body: '12345'}), code('invalidRequest')); assert.equal(resolves, 0); assert.equal(fake.calls.length, 0);
});
test('guard produces bodyless 204 response and does not forward cookie headers', async () => {
  const fake = harness({status: 204, chunks: []}); const guarded = createGuardedRequest({resolveImpl: async () => publicAnswers, requestImpl: fake.requestImpl});
  const response = await guarded(url, {body: new URLSearchParams({track: 'A & B'})}); assert.equal(response.status, 204); assert.equal(await response.text(), ''); assert.equal(response.headers.has('set-cookie'), false); assert.equal(fake.calls[0].body, 'track=A+%26+B');
});
test('guard re-resolves on a new attempt and blocks newly private DNS', async () => {
  let resolves = 0; const fake = harness({status: 503}); const guarded = createGuardedRequest({resolveImpl: async () => ++resolves === 1 ? publicAnswers : [{address: '10.0.0.1', family: 4}], requestImpl: fake.requestImpl});
  assert.equal((await guarded(url)).status, 503); await assert.rejects(guarded(url), code('blockedDestination')); assert.equal(resolves, 2); assert.equal(fake.calls.length, 1);
});
test('guard hides transport exception details and validates its limits', async () => {
  const fake = harness({networkError: true}); const guarded = createGuardedRequest({resolveImpl: async () => publicAnswers, requestImpl: fake.requestImpl});
  await assert.rejects(guarded(url), code('networkUnavailable')); assert.throws(() => createGuardedRequest({timeoutMs: 0}), code('invalidConfiguration'));
});

test('guard connection fixture consumes normalized public IPv6 and mapped DNS answers', async () => {
  for (const answers of [[{address: '2001:4860:4860::8888', family: 6}], [{address: '::ffff:808:808', family: 6}]]) {
    const fake = harness(); const guarded = createGuardedRequest({resolveImpl: async () => answers, requestImpl: fake.requestImpl});
    assert.equal((await guarded(url)).status, 200);
    assert.equal(fake.calls[0].lookupFamily, answers[0].address.startsWith('::ffff') ? 4 : 6);
  }
});
test('guard certificate identity callback verifies original configured hostname', async () => {
  const fake = harness(); const guarded = createGuardedRequest({resolveImpl: async () => publicAnswers, requestImpl: fake.requestImpl});
  await guarded(url); const verify = fake.calls[0].options.checkServerIdentity;
  assert.equal(verify('ignored.example.test', {subjectaltname: 'DNS:metadata.example.test'}), undefined);
  assert.equal(verify('metadata.example.test', {subjectaltname: 'DNS:wrong.example.test'}).code, 'ERR_TLS_CERT_ALTNAME_INVALID');
});
