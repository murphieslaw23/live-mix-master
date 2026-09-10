const PROVIDER_URL = 'https://api.acoustid.org/v2/lookup';
const DEFAULT_TIMEOUT_MS = 6000;
const DEFAULT_RETRY_DELAY_MS = 150;
const RETRYABLE_STATUSES = new Set([429, 502, 503, 504]);

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}

function failure(status, failureCode, message) {
  return jsonResponse(status, {ok: false, failureCode, message});
}

function isFiniteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

function parseLookupRequest(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }

  const duration = value.duration;
  const fingerprint = value.fingerprint;
  const minimumConfidence = value.minimumConfidence ?? 0.65;

  if (
    !isFiniteNumber(duration) ||
    duration < 1 ||
    duration > 120 ||
    typeof fingerprint !== 'string' ||
    fingerprint.length === 0 ||
    fingerprint.length > 65536 ||
    !isFiniteNumber(minimumConfidence) ||
    minimumConfidence < 0 ||
    minimumConfidence > 1
  ) {
    return null;
  }

  return {
    duration: Math.round(duration),
    fingerprint,
    minimumConfidence,
  };
}

function normalizedTrack(providerBody, minimumConfidence) {
  if (providerBody?.status !== 'ok' || !Array.isArray(providerBody?.results)) {
    return {kind: 'providerUnavailable'};
  }

  for (const result of providerBody.results) {
    const confidence = Number(result?.score ?? 0);
    if (!Number.isFinite(confidence) || confidence < minimumConfidence) {
      continue;
    }

    const recordings = Array.isArray(result?.recordings) ? result.recordings : [];
    if (recordings.length === 0) {
      continue;
    }

    const recording = recordings[0] ?? {};
    const artists = Array.isArray(recording.artists) ? recording.artists : [];
    const releasegroups = Array.isArray(recording.releasegroups)
      ? recording.releasegroups
      : [];

    return {
      kind: 'match',
      track: {
        artist:
          typeof artists[0]?.name === 'string' && artists[0].name.length > 0
            ? artists[0].name
            : 'Unknown Artist',
        title:
          typeof recording.title === 'string' && recording.title.length > 0
            ? recording.title
            : 'Untitled Track',
        release:
          typeof releasegroups[0]?.title === 'string' && releasegroups[0].title.length > 0
            ? releasegroups[0].title
            : null,
        providerId: typeof result?.id === 'string' ? result.id : '',
        confidence,
      },
    };
  }

  return {kind: 'noMatch'};
}

function providerFailure(response) {
  if (response.status === 401 || response.status === 403) {
    return failure(502, 'unauthorized', 'Fingerprint provider rejected server credentials');
  }
  if (response.status === 429) {
    return failure(503, 'rateLimited', 'Fingerprint provider rate limit exceeded');
  }
  return failure(502, 'unavailable', 'Fingerprint provider is unavailable');
}

async function delay(ms, sleepImpl) {
  if (ms <= 0) return;
  await sleepImpl(ms);
}

async function providerRequest({
  fetchImpl,
  apiKey,
  lookup,
  timeoutMs,
  requestSignal,
}) {
  const controller = new AbortController();
  let timedOut = false;
  let callerAborted = false;

  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, timeoutMs);

  const abortFromCaller = () => {
    callerAborted = true;
    controller.abort();
  };

  if (requestSignal) {
    if (requestSignal.aborted) {
      abortFromCaller();
    } else {
      requestSignal.addEventListener('abort', abortFromCaller, {once: true});
    }
  }

  try {
    const body = new URLSearchParams({
      client: apiKey,
      meta: 'recordings releasegroups',
      duration: String(lookup.duration),
      fingerprint: lookup.fingerprint,
    });

    const response = await fetchImpl(PROVIDER_URL, {
      method: 'POST',
      headers: {
        accept: 'application/json',
        'content-type': 'application/x-www-form-urlencoded',
      },
      body,
      signal: controller.signal,
    });
    return {response};
  } catch (error) {
    if (timedOut) {
      return {failureKind: 'timeout'};
    }
    if (callerAborted || requestSignal?.aborted) {
      return {failureKind: 'cancelled'};
    }
    return {failureKind: 'offline'};
  } finally {
    clearTimeout(timeout);
    requestSignal?.removeEventListener?.('abort', abortFromCaller);
  }
}

export function createFingerprintLookupHandler({
  env = globalThis.process?.env ?? {},
  fetchImpl = globalThis.fetch,
  sleepImpl = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  timeoutMs = DEFAULT_TIMEOUT_MS,
  retryDelayMs = DEFAULT_RETRY_DELAY_MS,
} = {}) {
  return async function fingerprintLookupHandler(request) {
    if (request?.method !== 'POST') {
      return failure(405, 'invalidRequest', 'Fingerprint lookup request is invalid');
    }

    const apiKey = typeof env.ACOUSTID_API_KEY === 'string'
      ? env.ACOUSTID_API_KEY.trim()
      : '';
    if (apiKey.length === 0) {
      return failure(
        503,
        'invalidConfiguration',
        'Fingerprint provider is not configured',
      );
    }

    let rawBody;
    try {
      rawBody = await request.json();
    } catch (_) {
      return failure(400, 'invalidRequest', 'Fingerprint lookup request is invalid');
    }

    const lookup = parseLookupRequest(rawBody);
    if (lookup == null) {
      return failure(400, 'invalidRequest', 'Fingerprint lookup request is invalid');
    }

    if (typeof fetchImpl !== 'function') {
      return failure(503, 'unavailable', 'Fingerprint provider is unavailable');
    }

    for (let attempt = 1; attempt <= 2; attempt += 1) {
      const upstream = await providerRequest({
        fetchImpl,
        apiKey,
        lookup,
        timeoutMs,
        requestSignal: request.signal,
      });

      if (upstream.failureKind === 'timeout') {
        return failure(504, 'timeout', 'Fingerprint provider request timed out');
      }
      if (upstream.failureKind === 'cancelled') {
        return failure(408, 'cancelled', 'Fingerprint lookup request was cancelled');
      }
      if (upstream.failureKind === 'offline') {
        if (attempt < 2) {
          await delay(retryDelayMs, sleepImpl);
          continue;
        }
        return failure(503, 'offline', 'Fingerprint provider is unreachable');
      }

      const response = upstream.response;
      if (RETRYABLE_STATUSES.has(response.status) && attempt < 2) {
        await delay(retryDelayMs, sleepImpl);
        continue;
      }
      if (response.status !== 200) {
        return providerFailure(response);
      }

      let providerBody;
      try {
        providerBody = await response.json();
      } catch (_) {
        return failure(
          502,
          'malformedResponse',
          'Fingerprint provider returned malformed data',
        );
      }

      const normalized = normalizedTrack(providerBody, lookup.minimumConfidence);
      if (normalized.kind === 'providerUnavailable') {
        return failure(502, 'unavailable', 'Fingerprint provider is unavailable');
      }
      if (normalized.kind === 'noMatch') {
        return jsonResponse(200, {ok: true, track: null});
      }
      return jsonResponse(200, {ok: true, track: normalized.track});
    }

    return failure(502, 'unavailable', 'Fingerprint provider is unavailable');
  };
}

const defaultHandler = createFingerprintLookupHandler();

export async function POST(request) {
  return defaultHandler(request);
}
