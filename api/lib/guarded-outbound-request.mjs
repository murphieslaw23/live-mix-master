import {lookup} from 'node:dns/promises';
import {request as httpsRequest} from 'node:https';
import {checkServerIdentity} from 'node:tls';
import {classifyAddress, classifyDestination, validateDnsAnswers} from './outbound-address-policy.mjs';

export class OutboundRequestError extends Error {
  constructor(code) { super('Outbound request failed'); this.name = 'OutboundRequestError'; this.code = code; }
}
const fail = (code) => new OutboundRequestError(code);
function abortable(work, signal) {
  return new Promise((resolve, reject) => {
    const stop = () => { signal.removeEventListener('abort', stop); reject(signal.reason); };
    signal.addEventListener('abort', stop, {once: true});
    Promise.resolve(work).then((value) => { signal.removeEventListener('abort', stop); resolve(value); }, (error) => { signal.removeEventListener('abort', stop); reject(error); });
    if (signal.aborted) stop();
  });
}

export function createGuardedRequest({
  resolveImpl = (hostname) => lookup(hostname, {all: true, verbatim: true}),
  requestImpl = httpsRequest,
  timeoutMs = 5000,
  maxResponseBytes = 65536,
  maxRequestBytes = 262144,
} = {}) {
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 60000 || !Number.isInteger(maxResponseBytes) || maxResponseBytes < 1 || maxResponseBytes > 1048576 || !Number.isInteger(maxRequestBytes) || maxRequestBytes < 1 || maxRequestBytes > 1048576 || typeof resolveImpl !== 'function' || typeof requestImpl !== 'function') throw fail('invalidConfiguration');
  return async function guardedRequest(value, init = {}) {
    const destination = classifyDestination(String(value));
    if (destination.kind === 'blocked') throw fail('blockedDestination');
    if (destination.kind === 'invalid') throw fail('invalidDestination');
    const url = new URL(destination.url);
    const method = init.method ?? 'POST';
    if (method !== 'POST' && method !== 'GET') throw fail('invalidRequest');
    let headers; let body;
    try {
      const supplied = new Headers(init.headers ?? {});
      for (const [name] of supplied) if (!['accept', 'content-type', 'authorization'].includes(name)) throw fail('invalidRequest');
      headers = Object.fromEntries(supplied);
      if (init.body != null && typeof init.body !== 'string' && !(init.body instanceof URLSearchParams)) throw fail('invalidRequest');
      body = init.body == null ? '' : String(init.body);
      if (Buffer.byteLength(body) > maxRequestBytes || (method === 'GET' && body.length > 0)) throw fail('invalidRequest');
    } catch (_) { throw fail('invalidRequest'); }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(fail('timeout')), timeoutMs);
    const callerStop = () => controller.abort(fail('cancelled'));
    const signal = controller.signal;
    init.signal?.addEventListener('abort', callerStop, {once: true});
    if (init.signal?.aborted) callerStop();
    let request; let response;
    try {
      signal.throwIfAborted();
      const validated = destination.kind === 'literal'
        ? validateDnsAnswers(destination.addresses)
        : validateDnsAnswers(await abortable(Promise.resolve().then(() => resolveImpl(destination.hostname)), signal));
      signal.throwIfAborted();
      if (validated.kind === 'blocked') throw fail('blockedDestination');
      if (validated.kind !== 'approved') throw fail('invalidDnsAnswers');
      const pinned = validated.addresses[0];
      const hostname = destination.kind === 'dns' ? destination.hostname : pinned.address;
      const options = {
        protocol: 'https:', hostname, port: Number(url.port || 443),
        path: `${url.pathname}${url.search}`, method,
        headers: {...headers, host: url.host}, agent: false,
        family: pinned.family, autoSelectFamily: false,
        servername: destination.kind === 'dns' ? hostname : undefined,
        rejectUnauthorized: true,
        checkServerIdentity: (_host, cert) => checkServerIdentity(hostname, cert),
        signal,
        lookup(queried, lookupOptions, callback) {
          if (queried.toLowerCase().replace(/\.$/, '') !== hostname) { callback(fail('invalidDestination')); return; }
          if (lookupOptions.all) callback(null, [{address: pinned.address, family: pinned.family}]);
          else callback(null, pinned.address, pinned.family);
        },
      };
      const exchange = new Promise((resolve, reject) => {
        let settled = false;
        const rejectOnce = (error) => {
          if (settled) return;
          settled = true; reject(error);
          response?.destroy(); request?.destroy();
        };
        request = requestImpl(options, (incoming) => {
          response = incoming;
          incoming.on('error', () => rejectOnce(fail('networkUnavailable')));
          incoming.on('aborted', () => rejectOnce(fail('networkUnavailable')));
          const status = incoming.statusCode;
          if (!Number.isInteger(status) || status < 200 || status > 599) { rejectOnce(fail('invalidResponse')); return; }
          if (status >= 300 && status < 400) { rejectOnce(fail('redirectRejected')); return; }
          let size = 0; const chunks = [];
          incoming.on('data', (chunk) => {
            if (settled) return;
            const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
            size += bytes.length;
            if (size > maxResponseBytes) { rejectOnce(fail('responseTooLarge')); return; }
            chunks.push(bytes);
          });
          incoming.on('end', () => {
            if (settled) return;
            try {
              const bodyless = status === 204 || status === 205;
              const safeHeaders = incoming.headers?.['content-type'] ? {'content-type': incoming.headers['content-type']} : {};
              const result = new Response(bodyless ? null : Buffer.concat(chunks), {status, headers: safeHeaders});
              settled = true; resolve(result);
            } catch (_) { rejectOnce(fail('invalidResponse')); }
          });
        });
        request.on('error', () => rejectOnce(signal.aborted ? signal.reason : fail('networkUnavailable')));
        request.once('socket', (socket) => {
          socket.once('secureConnect', () => {
            if (settled) return;
            const peer = classifyAddress(socket.remoteAddress);
            if (signal.aborted) { rejectOnce(signal.reason); return; }
            if (socket.authorized !== true) { rejectOnce(fail('tlsRejected')); return; }
            if (peer.kind !== 'approved' || peer.address !== pinned.address || peer.family !== pinned.family) { rejectOnce(fail('peerMismatch')); return; }
            request.end(body);
          });
        });
      });
      return await abortable(exchange, signal);
    } catch (error) {
      if (signal.aborted) throw signal.reason;
      if (error instanceof OutboundRequestError) throw error;
      throw fail('networkUnavailable');
    } finally {
      clearTimeout(timer); init.signal?.removeEventListener('abort', callerStop);
      response?.destroy(); request?.destroy();
    }
  };
}
