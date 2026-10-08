import {BlockList, isIP} from 'node:net';

export const ADDRESS_POLICY_VERSION = '2026-10-07-v1';
export const BLOCKED_IPV4_CIDRS = Object.freeze([
  '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8',
  '169.254.0.0/16', '172.16.0.0/12', '192.0.0.0/24', '192.0.2.0/24',
  '192.31.196.0/24', '192.52.193.0/24', '192.88.99.0/24',
  '192.168.0.0/16', '192.175.48.0/24', '198.18.0.0/15',
  '198.51.100.0/24', '203.0.113.0/24', '224.0.0.0/4', '240.0.0.0/4',
]);
export const BLOCKED_IPV6_CIDRS = Object.freeze([
  '2001::/23', '2001:db8::/32', '2002::/16',
  '2620:4f:8000::/48', '3fff::/20',
]);
function list(cidrs, type) {
  const result = new BlockList();
  for (const cidr of cidrs) {
    const [address, prefix] = cidr.split('/');
    result.addSubnet(address, Number(prefix), type);
  }
  return result;
}
const blocked4 = list(BLOCKED_IPV4_CIDRS, 'ipv4');
const blocked6 = list(BLOCKED_IPV6_CIDRS, 'ipv6');
const global6 = list(['2000::/3'], 'ipv6');
const mapped6 = list(['::ffff:0:0/96'], 'ipv6');
const reject = (kind, reason) => Object.freeze({kind, reason});

export function classifyAddress(value) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 128 || value !== value.trim() || value.includes('%')) return reject('invalid', 'invalidAddress');
  const originalFamily = isIP(value);
  if (originalFamily === 0) return reject('invalid', 'invalidAddress');
  try {
    let address = originalFamily === 6
      ? new URL(`https://[${value}]/`).hostname.slice(1, -1)
      : value;
    let family = originalFamily;
    if (family === 6 && mapped6.check(address, 'ipv6')) {
      const words = address.split(':').slice(-2).map((part) => Number.parseInt(part, 16));
      if (words.length !== 2 || words.some((part) => !Number.isInteger(part) || part < 0 || part > 65535)) return reject('invalid', 'invalidAddress');
      address = [words[0] >>> 8, words[0] & 255, words[1] >>> 8, words[1] & 255].join('.');
      family = 4;
    }
    if (isIP(address) !== family) return reject('invalid', 'invalidAddress');
    const blocked = family === 4 ? blocked4.check(address, 'ipv4') : !global6.check(address, 'ipv6') || blocked6.check(address, 'ipv6');
    if (blocked) return reject('blocked', 'destinationNotPermitted');
    return Object.freeze({kind: 'approved', address, family, originalFamily, policyVersion: ADDRESS_POLICY_VERSION});
  } catch (_) { return reject('invalid', 'invalidAddress'); }
}

export function validateDnsAnswers(records) {
  if (!Array.isArray(records) || records.length === 0 || records.length > 64) return reject('invalid', 'invalidDnsAnswers');
  const addresses = []; const seen = new Set();
  for (const record of records) {
    if (record == null || typeof record !== 'object' || typeof record.address !== 'string' || (record.family !== 4 && record.family !== 6) || isIP(record.address) !== record.family) return reject('invalid', 'invalidDnsAnswers');
    const result = classifyAddress(record.address);
    if (result.kind !== 'approved') return result;
    const key = `${result.family}:${result.address}`;
    if (!seen.has(key)) { seen.add(key); addresses.push(Object.freeze({address: result.address, family: result.family})); }
  }
  return Object.freeze({kind: 'approved', addresses: Object.freeze(addresses), policyVersion: ADDRESS_POLICY_VERSION});
}

// These results are internal routing decisions, never public diagnostics.
export function classifyDestination(value) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 4096 || value !== value.trim() || /[\x00-\x1f\x7f]/.test(value)) return reject('invalid', 'invalidDestination');
  let url;
  try { url = new URL(value); } catch (_) { return reject('invalid', 'invalidDestination'); }
  if (url.username || url.password || url.hash || !url.hostname) return reject('invalid', 'invalidDestination');
  const hostname = url.hostname.replace(/^\[|\]$/g, '').toLowerCase().replace(/\.$/, '');
  const family = isIP(hostname);
  if (family) {
    const result = classifyAddress(hostname);
    if (result.kind !== 'approved') return result;
    if (url.protocol !== 'https:' || Number(url.port || 443) < 1) return reject('invalid', 'invalidDestination');
    return Object.freeze({kind: 'literal', url: url.href, addresses: Object.freeze([Object.freeze({address: result.address, family: result.family})])});
  }
  if (hostname === 'localhost' || ['.localhost', '.local', '.lan', '.internal'].some((suffix) => hostname.endsWith(suffix))) return reject('blocked', 'destinationNotPermitted');
  const label = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;
  if (url.protocol !== 'https:' || Number(url.port || 443) < 1 || hostname.length > 253 || !hostname.includes('.') || !hostname.split('.').every((part) => label.test(part))) return reject('invalid', 'invalidDestination');
  url.hostname = hostname;
  return Object.freeze({kind: 'dns', url: url.href, hostname});
}
