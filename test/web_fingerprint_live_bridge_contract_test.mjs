import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const bridgeUrl = new URL(
  '../lib/services/web/browser_fingerprint_analysis_bridge_web.dart',
  import.meta.url,
);
const audioGatewayUrl = new URL(
  '../lib/audio/web/browser_audio_worklet_gateway_web.dart',
  import.meta.url,
);
const runtimeUrl = new URL(
  '../lib/audio/web/browser_capture_runtime_web.dart',
  import.meta.url,
);
const lookupControllerUrl = new URL(
  '../lib/services/web/browser_fingerprint_lookup_controller.dart',
  import.meta.url,
);
const appSurfaceUrl = new URL('../lib/app/app_surface_web.dart', import.meta.url);

test('live fingerprint bridge streams bounded Worklet PCM directly to the Dedicated Worker', async () => {
  const source = await readFile(bridgeUrl, 'utf8');

  assert.match(source, /fingerprint\/livemixmaster-fingerprint-worker\.js/);
  assert.match(source, /livemixmaster-chromaprint\.mjs/);
  assert.match(source, /livemixmaster-chromaprint-core\.wasm/);
  assert.match(source, /case 'ready'/);
  assert.match(source, /case 'pcmAck'/);
  assert.match(source, /case 'fingerprint'/);
  assert.match(source, /maximumOutstandingPcm\s*=\s*4/);
  assert.match(source, /initialWindowSeconds\s*=\s*10/);
  assert.match(source, /analysisCadenceSeconds\s*=\s*8/);
  assert.match(source, /acceptedFrames/);
  assert.match(source, /nextFlushFrame/);
  assert.doesNotMatch(source, /List<double>/, 'live PCM must not be accumulated as a Dart double list');
  assert.doesNotMatch(source, /Float32List\.fromList/, 'live PCM must not be recopied through a full Dart buffer');
});

test('WebAudioWorkletGateway relays analysis PCM and ACKs independently from recorder PCM', async () => {
  const source = await readFile(audioGatewayUrl, 'utf8');

  assert.match(source, /case 'analysisPcm'/);
  assert.match(source, /forwardAnalysisPcm/);
  assert.match(source, /type['"]?:?\s*['"]analysis['"]/);
  assert.match(source, /analysisAck/);
  assert.match(source, /preparedFingerprintHandler/);
  assert.doesNotMatch(
    source,
    /case 'analysisPcm'[\s\S]{0,500}_recordingFailureHandler/,
    'analysis failure must never enter the recorder failure path',
  );
});

test('fingerprint preparation failures reach the visible lookup state', async () => {
  const audioGateway = await readFile(audioGatewayUrl, 'utf8');
  const runtime = await readFile(runtimeUrl, 'utf8');
  const lookupController = await readFile(lookupControllerUrl, 'utf8');

  assert.match(audioGateway, /fingerprintPreparationUnavailableHandler/);
  assert.match(
    audioGateway,
    /onUnavailable:\s*\(\)\s*\{[\s\S]*fingerprintPreparationUnavailableHandler/,
  );
  assert.match(runtime, /fingerprintPreparationUnavailableHandler/);
  assert.match(runtime, /reportPreparationUnavailable/);
  assert.match(lookupController, /reportPreparationUnavailable/);
});

test('default Web runtime and UI share lookup state while injected controllers remain isolated', async () => {
  const runtime = await readFile(runtimeUrl, 'utf8');
  const lookupController = await readFile(lookupControllerUrl, 'utf8');
  const appSurface = await readFile(appSurfaceUrl, 'utf8');

  assert.match(runtime, /BrowserFingerprintLookupController/);
  assert.match(runtime, /fingerprintController/);
  assert.match(runtime, /lookupPreparedFingerprint/);
  assert.match(runtime, /preparedFingerprintHandler/);
  assert.match(lookupController, /_defaultFingerprintLookupStore/);
  assert.match(lookupController, /gateway == null/);
  assert.match(appSurface, /BrowserFingerprintLookupController\(\)/);
});
