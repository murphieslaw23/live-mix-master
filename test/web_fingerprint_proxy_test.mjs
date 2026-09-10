import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createFingerprintLookupHandler,
} from '../api/fingerprint-lookup.mjs';

function jsonRequest(body, signal) {
  return new Request('https://livemixmaster.test/api/fingerprint-lookup', {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify(body),
    signal,
  });
}

async function readJson(response) {
  return JSON.parse(await response.text());
}

test('provider key is required from server environment and never accepted from browser payload', async () => {
  let calls = 0;
  const handler = createFingerprintLookupHandler({
    env: {},
    fetchImpl: async () => {
      calls += 1;
      throw new Error('must not be called');
    },
  });

  const response = await handler(jsonRequest({
    duration: 10,
    fingerprint: 'prepared-fingerprint',
    acoustIdApiKey: 'browser-must-not-control-this',
  }));
  const body = await readJson(response);

  assert.equal(response.status, 503);
  assert.deepEqual(body, {
    ok: false,
    failureCode: 'invalidConfiguration',
    message: 'Fingerprint provider is not configured',
  });
  assert.equal(calls, 0);
  assert.doesNotMatch(JSON.stringify(body), /browser-must-not-control-this/);
});

test('successful lookup injects server credential upstream and returns only normalized track data', async () => {
  const upstreamBodies = [];
  const handler = createFingerprintLookupHandler({
    env: {ACOUSTID_API_KEY: 'server-secret-key'},
    fetchImpl: async (_url, options) => {
      upstreamBodies.push(options.body.toString());
      return new Response(JSON.stringify({
        status: 'ok',
        results: [{
          id: 'acoustid-1',
          score: 0.93,
          recordings: [{
            title: 'Signal Ritual',
            artists: [{name: 'System Corrupt'}],
            releasegroups: [{title: 'Test Release'}],
          }],
        }],
      }), {status: 200, headers: {'content-type': 'application/json'}});
    },
  });

  const response = await handler(jsonRequest({
    duration: 10,
    fingerprint: 'prepared-fingerprint',
    minimumConfidence: 0.65,
  }));
  const body = await readJson(response);

  assert.equal(response.status, 200);
  assert.equal(upstreamBodies.length, 1);
  assert.match(upstreamBodies[0], /client=server-secret-key/);
  assert.match(upstreamBodies[0], /fingerprint=prepared-fingerprint/);
  assert.deepEqual(body, {
    ok: true,
    track: {
      artist: 'System Corrupt',
      title: 'Signal Ritual',
      release: 'Test Release',
      providerId: 'acoustid-1',
      confidence: 0.93,
    },
  });
  assert.doesNotMatch(JSON.stringify(body), /server-secret-key/);
});

test('rate limit is retried once and succeeds without exposing provider diagnostics', async () => {
  let calls = 0;
  const handler = createFingerprintLookupHandler({
    env: {ACOUSTID_API_KEY: 'server-secret-key'},
    sleepImpl: async () => {},
    fetchImpl: async () => {
      calls += 1;
      if (calls === 1) {
        return new Response('provider said secret=server-secret-key', {status: 429});
      }
      return new Response(JSON.stringify({
        status: 'ok',
        results: [{
          id: 'acoustid-2',
          score: 0.88,
          recordings: [{title: 'Retry Works', artists: [{name: 'LMM'}]}],
        }],
      }), {status: 200});
    },
  });

  const response = await handler(jsonRequest({duration: 10, fingerprint: 'fp'}));
  const body = await readJson(response);

  assert.equal(calls, 2);
  assert.equal(response.status, 200);
  assert.equal(body.ok, true);
  assert.doesNotMatch(JSON.stringify(body), /server-secret-key|provider said secret/);
});

test('timeout maps to a safe typed failure without leaking request or provider data', async () => {
  const handler = createFingerprintLookupHandler({
    env: {ACOUSTID_API_KEY: 'server-secret-key'},
    timeoutMs: 5,
    sleepImpl: async () => {},
    fetchImpl: async (_url, {signal}) => new Promise((_resolve, reject) => {
      signal.addEventListener('abort', () => {
        const error = new Error('upstream aborted with server-secret-key');
        error.name = 'AbortError';
        reject(error);
      }, {once: true});
    }),
  });

  const response = await handler(jsonRequest({duration: 10, fingerprint: 'private-fingerprint'}));
  const body = await readJson(response);

  assert.equal(response.status, 504);
  assert.deepEqual(body, {
    ok: false,
    failureCode: 'timeout',
    message: 'Fingerprint provider request timed out',
  });
  assert.doesNotMatch(JSON.stringify(body), /server-secret-key|private-fingerprint|upstream aborted/);
});

test('malformed provider JSON maps to malformedResponse and unsupported browser input is rejected before fetch', async () => {
  let calls = 0;
  const handler = createFingerprintLookupHandler({
    env: {ACOUSTID_API_KEY: 'server-secret-key'},
    fetchImpl: async () => {
      calls += 1;
      return new Response('{not-json', {status: 200});
    },
  });

  const malformed = await handler(jsonRequest({duration: 10, fingerprint: 'fp'}));
  assert.equal(malformed.status, 502);
  assert.deepEqual(await readJson(malformed), {
    ok: false,
    failureCode: 'malformedResponse',
    message: 'Fingerprint provider returned malformed data',
  });

  const invalid = await handler(jsonRequest({duration: 0, fingerprint: ''}));
  assert.equal(invalid.status, 400);
  assert.deepEqual(await readJson(invalid), {
    ok: false,
    failureCode: 'invalidRequest',
    message: 'Fingerprint lookup request is invalid',
  });
  assert.equal(calls, 1);
});
