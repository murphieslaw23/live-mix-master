const DEFAULT_TIMEOUT_MS = 5000;
const DEFAULT_RETRY_DELAY_MS = 150;
const RETRYABLE_STATUSES = new Set([429, 502, 503, 504]);
const ALLOWED_REQUEST_KEYS = new Set(['destinationId', 'track']);
const ALLOWED_TRACK_KEYS = new Set([
  'artist',
  'title',
  'release',
  'confidence',
  'detectedAt',
  'sessionOffsetMs',
]);

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

function hasOnlyKeys(value, allowed) {
  return Object.keys(value).every((key) => allowed.has(key));
}

function finiteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

function safeString(value, {required = false, maxLength = 512} = {}) {
  if (value == null) {
    return required ? null : null;
  }
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if ((required && trimmed.length === 0) || trimmed.length > maxLength) {
    return null;
  }
  return trimmed;
}

function parseTrack(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  if (!hasOnlyKeys(value, ALLOWED_TRACK_KEYS)) return null;

  const artist = safeString(value.artist, {required: true});
  const title = safeString(value.title, {required: true});
  if (artist == null || title == null) return null;

  let release = null;
  if (value.release != null) {
    release = safeString(value.release);
    if (release == null) return null;
  }

  let confidence = null;
  if (value.confidence != null) {
    if (!finiteNumber(value.confidence) || value.confidence < 0 || value.confidence > 1) {
      return null;
    }
    confidence = value.confidence;
  }

  let detectedAt = null;
  if (value.detectedAt != null) {
    detectedAt = safeString(value.detectedAt, {maxLength: 64});
    if (detectedAt == null || Number.isNaN(Date.parse(detectedAt))) return null;
  }

  let sessionOffsetMs = null;
  if (value.sessionOffsetMs != null) {
    if (
      !Number.isInteger(value.sessionOffsetMs) ||
      value.sessionOffsetMs < 0 ||
      value.sessionOffsetMs > 604800000
    ) {
      return null;
    }
    sessionOffsetMs = value.sessionOffsetMs;
  }

  return {
    artist,
    title,
    release,
    confidence,
    detectedAt,
    sessionOffsetMs,
  };
}

function parseBrowserRequest(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  if (!hasOnlyKeys(value, ALLOWED_REQUEST_KEYS)) return null;

  const destinationId = safeString(value.destinationId, {required: true, maxLength: 64});
  if (destinationId == null || !/^[A-Za-z0-9._-]+$/.test(destinationId)) {
    return null;
  }
  const track = parseTrack(value.track);
  if (track == null) return null;
  return {destinationId, track};
}

function parseDestinationRegistry(env) {
  const raw = env?.LMM_BROADCAST_DESTINATIONS_JSON;
  if (typeof raw !== 'string' || raw.trim().length === 0) {
    return null;
  }
  try {
    const parsed = JSON.parse(raw);
    if (parsed == null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return null;
    }
    return parsed;
  } catch (_) {
    return null;
  }
}

function isPrivateIpv4(hostname) {
  const parts = hostname.split('.');
  if (parts.length !== 4 || parts.some((part) => !/^\d{1,3}$/.test(part))) {
    return false;
  }
  const octets = parts.map(Number);
  if (octets.some((octet) => octet < 0 || octet > 255)) return false;
  const [a, b] = octets;
  return (
    a === 0 ||
    a === 10 ||
    a === 127 ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168)
  );
}

function isLocalHostname(hostname) {
  const host = hostname.toLowerCase().replace(/^\[|\]$/g, '');
  if (
    host === 'localhost' ||
    host === '::1' ||
    host.endsWith('.localhost') ||
    host.endsWith('.local') ||
    host.endsWith('.lan') ||
    host.endsWith('.internal')
  ) {
    return true;
  }
  if (isPrivateIpv4(host)) return true;
  return (
    host.startsWith('fc') ||
    host.startsWith('fd') ||
    host.startsWith('fe80:')
  );
}

function classifyDestination(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return {kind: 'invalid'};
  }
  if (value.transport === 'localBridge') {
    return {kind: 'localBridge'};
  }
  if (value.transport !== 'webhook' || typeof value.url !== 'string') {
    return {kind: 'invalid'};
  }

  let url;
  try {
    url = new URL(value.url);
  } catch (_) {
    return {kind: 'invalid'};
  }

  if (isLocalHostname(url.hostname)) {
    return {kind: 'localBridge'};
  }
  if (url.protocol !== 'https:') {
    return {kind: 'invalid'};
  }

  const authorization = value.authorization;
  if (authorization != null && typeof authorization !== 'string') {
    return {kind: 'invalid'};
  }

  return {
    kind: 'webhook',
    url,
    authorization: typeof authorization === 'string' ? authorization : null,
  };
}

function webhookPayload(track) {
  return {
    event: 'track_change',
    artist: track.artist,
    title: track.title,
    release: track.release,
    confidence: track.confidence,
    detectedAt: track.detectedAt,
    sessionOffsetMs: track.sessionOffsetMs,
  };
}

async function delay(ms, sleepImpl) {
  if (ms <= 0) return;
  await sleepImpl(ms);
}

async function dispatchWebhook({
  destination,
  track,
  fetchImpl,
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
    const headers = {
      accept: 'application/json',
      'content-type': 'application/json; charset=utf-8',
    };
    if (destination.authorization != null && destination.authorization.length > 0) {
      headers.authorization = destination.authorization;
    }

    const response = await fetchImpl(destination.url, {
      method: 'POST',
      headers,
      body: JSON.stringify(webhookPayload(track)),
      signal: controller.signal,
    });
    return {response};
  } catch (_) {
    if (timedOut) return {failureKind: 'timeout'};
    if (callerAborted || requestSignal?.aborted) return {failureKind: 'cancelled'};
    return {failureKind: 'offline'};
  } finally {
    clearTimeout(timeout);
    requestSignal?.removeEventListener?.('abort', abortFromCaller);
  }
}

function upstreamFailure(response) {
  if (response.status === 401 || response.status === 403) {
    return failure(502, 'unauthorized', 'Broadcast destination rejected server credentials');
  }
  if (response.status === 429) {
    return failure(503, 'rateLimited', 'Broadcast destination rate limit exceeded');
  }
  return failure(502, 'unavailable', 'Broadcast destination is unavailable');
}

export function createBroadcastMetadataHandler({
  env = globalThis.process?.env ?? {},
  fetchImpl = globalThis.fetch,
  sleepImpl = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  timeoutMs = DEFAULT_TIMEOUT_MS,
  retryDelayMs = DEFAULT_RETRY_DELAY_MS,
} = {}) {
  return async function broadcastMetadataHandler(request) {
    if (request?.method !== 'POST') {
      return failure(405, 'invalidRequest', 'Broadcast metadata request is invalid');
    }

    const registry = parseDestinationRegistry(env);
    if (registry == null) {
      return failure(
        503,
        'invalidConfiguration',
        'Broadcast metadata service is not configured',
      );
    }

    let rawBody;
    try {
      rawBody = await request.json();
    } catch (_) {
      return failure(400, 'invalidRequest', 'Broadcast metadata request is invalid');
    }

    const input = parseBrowserRequest(rawBody);
    if (input == null) {
      return failure(400, 'invalidRequest', 'Broadcast metadata request is invalid');
    }

    if (!Object.prototype.hasOwnProperty.call(registry, input.destinationId)) {
      return failure(404, 'unknownDestination', 'Broadcast destination is not configured');
    }

    const destination = classifyDestination(registry[input.destinationId]);
    if (destination.kind === 'localBridge') {
      return failure(
        409,
        'localBridgeRequired',
        'Broadcast destination requires a local bridge',
      );
    }
    if (destination.kind !== 'webhook') {
      return failure(
        503,
        'invalidConfiguration',
        'Broadcast metadata service is not configured',
      );
    }
    if (typeof fetchImpl !== 'function') {
      return failure(503, 'unavailable', 'Broadcast destination is unavailable');
    }

    for (let attempt = 1; attempt <= 2; attempt += 1) {
      const upstream = await dispatchWebhook({
        destination,
        track: input.track,
        fetchImpl,
        timeoutMs,
        requestSignal: request.signal,
      });

      if (upstream.failureKind === 'timeout') {
        return failure(504, 'timeout', 'Broadcast metadata request timed out');
      }
      if (upstream.failureKind === 'cancelled') {
        return failure(408, 'cancelled', 'Broadcast metadata request was cancelled');
      }
      if (upstream.failureKind === 'offline') {
        if (attempt < 2) {
          await delay(retryDelayMs, sleepImpl);
          continue;
        }
        return failure(503, 'offline', 'Broadcast destination is unreachable');
      }

      const response = upstream.response;
      if (RETRYABLE_STATUSES.has(response.status) && attempt < 2) {
        await delay(retryDelayMs, sleepImpl);
        continue;
      }
      if (response.status < 200 || response.status >= 300) {
        return upstreamFailure(response);
      }

      return jsonResponse(200, {
        ok: true,
        destinationId: input.destinationId,
      });
    }

    return failure(502, 'unavailable', 'Broadcast destination is unavailable');
  };
}

const defaultHandler = createBroadcastMetadataHandler();

export async function POST(request) {
  return defaultHandler(request);
}
