import assert from 'node:assert/strict';
import test from 'node:test';
import {ADDRESS_POLICY_VERSION, BLOCKED_IPV4_CIDRS, classifyAddress, validateDnsAnswers, classifyDestination} from '../api/lib/outbound-address-policy.mjs';

function ipv4(number) { return [24n, 16n, 8n, 0n].map((shift) => Number((number >> shift) & 255n)).join('.'); }
for (const cidr of BLOCKED_IPV4_CIDRS) {
  test(`address policy blocks IPv4 first/last address of ${cidr}`, () => {
    const [value, prefix] = cidr.split('/');
    const start = value.split('.').reduce((number, octet) => (number << 8n) | BigInt(octet), 0n);
    const end = start + (1n << (32n - BigInt(prefix))) - 1n;
    assert.equal(classifyAddress(ipv4(start)).kind, 'blocked');
    assert.equal(classifyAddress(ipv4(end)).kind, 'blocked');
  });
}
for (const address of ['::', '::1', 'fc00::1', 'fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff', 'fe80::1', 'ff02::1', '2001:db8::1', '2001::1', '2002::1', '2620:4f:8000::1', '3fff::1', '3fff:fff:ffff:ffff:ffff:ffff:ffff:ffff', '4000::']) {
  test(`address policy blocks ${address}`, () => assert.equal(classifyAddress(address).kind, 'blocked'));
}
for (const address of ['::ffff:127.0.0.1', '::ffff:7f00:1', '::ffff:10.0.0.1', '::ffff:a00:1', '::ffff:169.254.169.254', '::ffff:0:0', '::ffff:ffff:ffff']) {
  test(`address policy classifies mapped IPv6 ${address} as underlying IPv4`, () => assert.equal(classifyAddress(address).kind, 'blocked'));
}
for (const address of ['', '127.000.000.001', '127.1', '0x7f000001', '2130706433', ' 8.8.8.8', '8.8.8.8 ', '999.1.1.1', '[::1]', 'fe80::1%eth0', '8.8.8.8\n', 'x'.repeat(129), null]) {
  test(`address policy rejects malformed fixture ${String(address).slice(0, 30)}`, () => assert.equal(classifyAddress(address).kind, 'invalid'));
}
test('address policy approves and normalizes public IPv4, IPv6 and mapped IPv6 fixtures', () => {
  for (const value of ['8.8.8.8', '2001:4860:4860::8888']) assert.equal(classifyAddress(value).kind, 'approved');
  for (const value of ['::ffff:8.8.8.8', '::ffff:808:808']) {
    const result = classifyAddress(value); assert.equal(result.kind, 'approved'); assert.equal(result.address, '8.8.8.8'); assert.equal(result.family, 4); assert.equal(result.originalFamily, 6);
  }
});
test('DNS validation rejects any private or malformed answer in a mixed set', () => {
  const publicAnswer = {address: '8.8.8.8', family: 4};
  assert.equal(validateDnsAnswers([publicAnswer, {address: '10.0.0.1', family: 4}]).kind, 'blocked');
  assert.equal(validateDnsAnswers([{address: '::ffff:127.0.0.1', family: 6}]).kind, 'blocked');
  assert.equal(validateDnsAnswers([publicAnswer, {address: 'garbage', family: 4}]).kind, 'invalid');
});
test('DNS validation rejects empty, oversized and family-mismatched sets', () => {
  for (const records of [[], null, [{address: '::1', family: 4}], [{address: '8.8.8.8', family: 6}], Array(65).fill({address: '8.8.8.8', family: 4})]) assert.equal(validateDnsAnswers(records).kind, 'invalid');
});
test('DNS validation deduplicates normalized mapped addresses and freezes returned records', () => {
  const result = validateDnsAnswers([{address: '8.8.8.8', family: 4}, {address: '::ffff:808:808', family: 6}, {address: '2001:4860:4860::8888', family: 6}]);
  assert.equal(result.kind, 'approved'); assert.equal(result.addresses.length, 2); assert.equal(result.policyVersion, ADDRESS_POLICY_VERSION);
  assert.ok(Object.isFrozen(result)); assert.ok(Object.isFrozen(result.addresses)); assert.ok(result.addresses.every(Object.isFrozen));
});
test('destination parsing canonicalizes alternate IPv4 syntax before classifying it', () => {
  for (const value of ['https://127.1/path', 'https://0x7f000001/path', 'https://2130706433/path']) assert.equal(classifyDestination(value).kind, 'blocked');
});
test('ordinary fc/fd hostnames are DNS destinations, not IPv6 prefixes', () => {
  for (const host of ['fc-radio.example.test', 'fd-radio.example.test']) assert.equal(classifyDestination(`https://${host}/path`).kind, 'dns');
});
test('local hostname rules and parsed private literals are blocked', () => {
  for (const value of ['https://localhost./path', 'https://studio.local/path', 'https://studio.lan/path', 'https://studio.internal/path', 'http://192.168.1.20:4455/path', 'https://[::]/path']) assert.equal(classifyDestination(value).kind, 'blocked');
});
test('destination rejects userinfo, public HTTP, fragments, zero ports and control characters', () => {
  for (const value of ['https://user:synthetic-secret@example.test/path', 'http://example.test/path', 'ftp://example.test/path', 'https://example.test/path#fragment', 'https://example.test:0/path', 'https://example.test/\npath', 'https://intranet/path']) assert.equal(classifyDestination(value).kind, 'invalid');
});
test('rejection results contain safe reasons only, not supplied address or URL', () => {
  for (const value of ['https://user:synthetic-secret@example.test/path', 'https://127.0.0.1/path']) {
    const result = classifyDestination(value); assert.deepEqual(Object.keys(result).sort(), ['kind', 'reason']); assert.doesNotMatch(JSON.stringify(result), /synthetic-secret|127\.0\.0\.1|example\.test/);
  }
});
