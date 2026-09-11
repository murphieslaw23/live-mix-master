import assert from 'node:assert/strict';
import test from 'node:test';

import {createBroadcastMetadataHandler} from '../api/broadcast-metadata.mjs';

function request(body, method = 'POST') {
  return new Request('https://live-mix-master.example/api/broadcast-metadata', {
    method,
    headers: {'content-type': 'application/json'},
    body: method === 'POST' ? JSON.stringify(body) : undefined,
  });
}

async function json(response) {
  return /** @type {Record<string, any>} */ (await response.json());
}

const normalizedTrack = {
  artist: 'System Corrupt',
  title: 'Tekno Total 2026',
  release: 'SYCO EP 01',
  confidence: 0.95,
  detectedAt: '2026-09-11T00:00:00.000Z',
  sessionOffsetMs: 320000,
};

function envWith(destinations) {
  return {
    LMM_BROADCAST_DESTINATIONS_JSON: JSON.stringify(destinations),
  };
}

test('browser payload may select only a server-configured destination and normalized track data', async () => {
  let fetchCount = 0;
  const handler = createBroadcastMetadataHandler({
    env: envWith({
      radio: {
        transport: 'webhook',
        url: 'https://metadata.example.test/now-playing',
        authorization: 'Bearer SERVER-ONLY-SECRET',
      },
    }),
    fetchImpl: async () => {
      fetchCount += 1;
      return new Response(null, {status: 204});
    },
  });

  const injected = await handler(request({
    destinationId: 'radio',
    track: normalizedTrack,
    url: 'https://attacker.invalid/steal',
    token: 'browser-token',
    password: 'browser-password',
  }));

  assert.equal(injected.status, 400);
  assert.deepEqual(await json(injected), {
    ok: false,
    failureCode: 'invalidRequest',
    message: 'Broadcast metadata request is invalid',
  });
  assert.equal(fetchCount, 0);
});

test('public webhook destination resolves server-side URL and authorization without leaking them', async () => {
  let observedRequest;
  const handler = createBroadcastMetadataHandler({
    env: envWith({
      radio: {
        transport: 'webhook',
        url: 'https://metadata.example.test/now-playing',
        authorization: 'Bearer SERVER-ONLY-SECRET',
      },
    }),
    fetchImpl: async (url, init) => {
      observedRequest = {url: String(url), init};
      return new Response(null, {status: 204});
    },
  });

  const response = await handler(request({destinationId: 'radio', track: normalizedTrack}));
  assert.equal(response.status, 200);
  assert.deepEqual(await json(response), {
    ok: true,
    destinationId: 'radio',
  });

  assert.equal(observedRequest.url, 'https://metadata.example.test/now-playing');
  assert.equal(observedRequest.init.method, 'POST');
  assert.equal(observedRequest.init.headers.authorization, 'Bearer SERVER-ONLY-SECRET');
  const body = JSON.parse(observedRequest.init.body);
  assert.deepEqual(body, {
    event: 'track_change',
    artist: normalizedTrack.artist,
    title: normalizedTrack.title,
    release: normalizedTrack.release,
    confidence: normalizedTrack.confidence,
    detectedAt: normalizedTrack.detectedAt,
    sessionOffsetMs: normalizedTrack.sessionOffsetMs,
  });

  const serialized = JSON.stringify(await handler(request({destinationId: 'missing', track: normalizedTrack})).then(json));
  assert.doesNotMatch(serialized, /SERVER-ONLY-SECRET|metadata\.example\.test/);
});

test('unknown destinations fail before fetch with no endpoint disclosure', async () => {
  let fetchCount = 0;
  const handler = createBroadcastMetadataHandler({
    env: envWith({
      radio: {
        transport: 'webhook',
        url: 'https://metadata.example.test/now-playing',
        authorization: 'Bearer SERVER-ONLY-SECRET',
      },
    }),
    fetchImpl: async () => {
      fetchCount += 1;
      return new Response(null, {status: 204});
    },
  });

  const response = await handler(request({destinationId: 'missing', track: normalizedTrack}));
  assert.equal(response.status, 404);
  assert.deepEqual(await json(response), {
    ok: false,
    failureCode: 'unknownDestination',
    message: 'Broadcast destination is not configured',
  });
  assert.equal(fetchCount, 0);
});

test('local or LAN destinations require a local bridge and never use serverless fetch', async () => {
  let fetchCount = 0;
  const handler = createBroadcastMetadataHandler({
    env: envWith({
      studio: {
        transport: 'localBridge',
      },
      unsafeLiteral: {
        transport: 'webhook',
        url: 'http://192.168.1.20:4455/metadata',
      },
    }),
    fetchImpl: async () => {
      fetchCount += 1;
      return new Response(null, {status: 204});
    },
  });

  for (const destinationId of ['studio', 'unsafeLiteral']) {
    const response = await handler(request({destinationId, track: normalizedTrack}));
    assert.equal(response.status, 409);
    assert.deepEqual(await json(response), {
      ok: false,
      failureCode: 'localBridgeRequired',
      message: 'Broadcast destination requires a local bridge',
    });
  }
  assert.equal(fetchCount, 0);
});

test('retryable upstream response is retried once and then succeeds', async () => {
  let attempts = 0;
  const delays = [];
  const handler = createBroadcastMetadataHandler({
    env: envWith({
      radio: {
        transport: 'webhook',
        url: 'https://metadata.example.test/now-playing',
      },
    }),
    fetchImpl: async () => {
      attempts += 1;
      return attempts === 1
        ? new Response('', {status: 503})
        : new Response(null, {status: 204});
    },
    sleepImpl: async (ms) => delays.push(ms),
    retryDelayMs: 7,
  });

  const response = await handler(request({destinationId: 'radio', track: normalizedTrack}));
  assert.equal(response.status, 200);
  assert.deepEqual(await json(response), {ok: true, destinationId: 'radio'});
  assert.equal(attempts, 2);
  assert.deepEqual(delays, [7]);
});

test('timeout and malformed server configuration fail closed with safe typed responses', async () => {
  const timeoutHandler = createBroadcastMetadataHandler({
    env: envWith({
      radio: {
        transport: 'webhook',
        url: 'https://metadata.example.test/now-playing',
        authorization: 'Bearer TOP-SECRET',
      },
    }),
    timeoutMs: 5,
    fetchImpl: async (_url, init) => new Promise((_resolve, reject) => {
      init.signal.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')));
    }),
  });

  const timedOut = await timeoutHandler(request({destinationId: 'radio', track: normalizedTrack}));
  assert.equal(timedOut.status, 504);
  const timedOutBody = await json(timedOut);
  assert.deepEqual(timedOutBody, {
    ok: false,
    failureCode: 'timeout',
    message: 'Broadcast metadata request timed out',
  });
  assert.doesNotMatch(JSON.stringify(timedOutBody), /TOP-SECRET|metadata\.example\.test/);

  const malformedHandler = createBroadcastMetadataHandler({
    env: {LMM_BROADCAST_DESTINATIONS_JSON: '{not-json'},
    fetchImpl: async () => new Response(null, {status: 204}),
  });
  const malformed = await malformedHandler(request({destinationId: 'radio', track: normalizedTrack}));
  assert.equal(malformed.status, 503);
  assert.deepEqual(await json(malformed), {
    ok: false,
    failureCode: 'invalidConfiguration',
    message: 'Broadcast metadata service is not configured',
  });
});
