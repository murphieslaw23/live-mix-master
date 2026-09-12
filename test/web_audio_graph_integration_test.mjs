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

test('canonical DSP module is compiled and acknowledged before the live graph starts', async () => {
  const gateway = await fs.readFile(gatewayUrl, 'utf8');

  for (const token of [
    "const String _dspAssetPath = 'audio/livemixmaster-dsp.wasm';",
    'const int _dspAbiVersion = 1;',
    'final dspModule = await _compileDspModule();',
    "await context.audioWorklet.addModule('audio/livemixmaster-worklet.js').toDart;",
    "'type': 'dspInit'",
    "case 'dspReady':",
    'await dspReady.future.timeout(_dspHandshakeTimeout)',
    'sourceNode.connect(workletNode);',
    'workletNode.connect(destinationNode);',
    'await context.resume().toDart;',
  ]) {
    assert.equal(gateway.includes(token), true, `missing DSP startup token: ${token}`);
  }

  const compileIndex = gateway.indexOf('final dspModule = await _compileDspModule();');
  const addModuleIndex = gateway.indexOf("await context.audioWorklet.addModule('audio/livemixmaster-worklet.js').toDart;");
  const nodeIndex = gateway.indexOf("web.AudioWorkletNode(context, 'livemixmaster-dsp')");
  const initIndex = gateway.indexOf("'type': 'dspInit'");
  const readyIndex = gateway.indexOf('await dspReady.future.timeout(_dspHandshakeTimeout)');
  const connectIndex = gateway.indexOf('sourceNode.connect(workletNode);');
  const resumeIndex = gateway.indexOf('await context.resume().toDart;');

  assert.ok(compileIndex < addModuleIndex, 'Wasm compile must precede worklet module load');
  assert.ok(addModuleIndex < nodeIndex, 'worklet module must load before AudioWorkletNode construction');
  assert.ok(nodeIndex < initIndex, 'AudioWorkletNode must exist before dspInit');
  assert.ok(initIndex < readyIndex, 'dspInit must precede readiness wait');
  assert.ok(readyIndex < connectIndex, 'dspReady must precede graph connection');
  assert.ok(connectIndex < resumeIndex, 'graph connection must precede AudioContext resume');

  assert.equal(gateway.includes("_dspAssetPath = '\${"), false, 'DSP asset path must not be session/user-derived');
});
