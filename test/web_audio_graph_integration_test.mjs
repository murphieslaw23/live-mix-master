import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const gatewayUrl = new URL(
  '../lib/audio/web/browser_audio_worklet_gateway_web.dart',
  import.meta.url,
);
const runtimeUrl = new URL(
  '../lib/audio/web/browser_capture_runtime_web.dart',
  import.meta.url,
);
const mediaClientUrl = new URL(
  '../lib/audio/web/browser_media_client_web.dart',
  import.meta.url,
);

test('web runtime wires the W2 active MediaStream into the W3 AudioWorklet graph', async () => {
  const [gateway, runtime, mediaClient] = await Promise.all([
    fs.readFile(gatewayUrl, 'utf8'),
    fs.readFile(runtimeUrl, 'utf8'),
    fs.readFile(mediaClientUrl, 'utf8'),
  ]);

  for (const token of [
    'AudioContext(',
    '.audioWorklet.addModule(',
    'createMediaStreamSource(',
    'AudioWorkletNode(',
    'createMediaStreamDestination(',
    '.connect(',
  ]) {
    assert.equal(gateway.includes(token), true, `missing Web Audio graph token: ${token}`);
  }

  assert.equal(gateway.includes("'audio/livemixmaster-worklet.js'"), true);
  assert.equal(gateway.includes("'livemixmaster-dsp'"), true);
  assert.equal(gateway.includes('context.destination'), false, 'capture must not create implicit audible loopback');

  assert.equal(mediaClient.includes('web.MediaStream? get activeStream'), true);
  assert.equal(runtime.includes('WebAudioWorkletGateway'), true);
  assert.equal(runtime.includes('activeStream: () => client.activeStream'), true);
  assert.equal(runtime.includes('BrowserAudioRuntimeCoordinator'), true);
});
