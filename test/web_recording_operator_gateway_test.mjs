import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const gatewayUrl = new URL('../lib/audio/web/browser_audio_worklet_gateway_web.dart', import.meta.url);

async function source(url) {
  return fs.readFile(url, 'utf8');
}

test('WebAudioWorkletGateway is the shared processing and recording gateway', async () => {
  const gateway = await source(gatewayUrl);

  assert.match(
    gateway,
    /class WebAudioWorkletGateway[\s\S]*BrowserAudioProcessingGateway[\s\S]*BrowserRecordingGateway[\s\S]*BrowserRecordingLifecycleGateway/,
    'one gateway instance must own processing and recording lifecycle',
  );
  assert.match(
    gateway,
    /final recorderWorker = web\.Worker\([\s\S]*livemixmaster-recorder-worker\.js/,
    'processing startup must create the recorder Worker',
  );
});

test('recording starts only after the Worker is ready and then enables post-master PCM', async () => {
  const gateway = await source(gatewayUrl);

  assert.match(
    gateway,
    /Future<void> startRecording\(\)[\s\S]*type': 'start'[\s\S]*_recorderStartCompleter![\s\S]*_setWorkletRecording\([\s\S]*enabled: true,[\s\S]*maxOutstandingPcm: _recorderMaxOutstandingPcm\(context\.sampleRate\)/,
    'operator start must wait for Worker readiness before enabling PCM with the active sample-rate budget',
  );
  assert.match(
    gateway,
    /case 'recordingStarted':[\s\S]*completer\.complete\(\)/,
    'Worker readiness must resolve the start handshake',
  );
  assert.match(
    gateway,
    /void _setWorkletRecording\([\s\S]*type': 'recording'[\s\S]*enabled': enabled/,
    'recording helper must send the worklet protocol message',
  );
});

test('recording backpressure window tolerates browser scheduler jitter while remaining bounded', async () => {
  const gateway = await source(gatewayUrl);
  const quantumMatch = gateway.match(
    /const int _recorderRenderQuantumFrames = (\d+);/,
  );
  const budgetMatch = gateway.match(
    /const int _recorderBackpressureBudgetMilliseconds = (\d+);/,
  );

  assert.ok(quantumMatch, 'gateway must declare the Web Audio render quantum size');
  assert.ok(budgetMatch, 'gateway must declare a bounded audio-time backlog window');

  const quantumFrames = Number.parseInt(quantumMatch[1], 10);
  const budgetMilliseconds = Number.parseInt(budgetMatch[1], 10);
  assert.equal(quantumFrames, 128, 'Web Audio render quantum contract changed unexpectedly');
  assert.ok(
    budgetMilliseconds >= 250,
    `PCM backlog window must tolerate ordinary browser scheduling jitter, got ${budgetMilliseconds}ms`,
  );
  assert.ok(
    budgetMilliseconds <= 1000,
    `PCM backlog window must remain bounded, got ${budgetMilliseconds}ms`,
  );
  assert.match(
    gateway,
    /int _recorderMaxOutstandingPcm\(num sampleRate\)[\s\S]*_recorderBackpressureBudgetMilliseconds[\s\S]*_recorderRenderQuantumFrames/,
    'PCM backlog blocks must be derived from the active sample rate and bounded audio-time window',
  );
});

test('stop, failure, and export are explicit fail-closed operator transitions', async () => {
  const gateway = await source(gatewayUrl);

  assert.match(
    gateway,
    /Future<BrowserRecordingArtifact> stopRecording\(\)[\s\S]*_setWorkletRecording\(workletNode, enabled: false\)[\s\S]*type': 'stop'[\s\S]*return await/,
    'stop must disable PCM before asking the Worker to finalize',
  );
  assert.match(
    gateway,
    /case 'recordingStopped':[\s\S]*fileName[\s\S]*bytesWritten[\s\S]*dataBytes/,
    'finalized artifact metadata must reach the controller',
  );
  assert.match(
    gateway,
    /case 'recordingError':[\s\S]*_notifyRecordingFailure/,
    'Worker recording errors must propagate into operator state',
  );
  assert.match(
    gateway,
    /case 'recordingError':[\s\S]*BACKPRESSURE[\s\S]*_notifyRecordingFailure/,
    'AudioWorklet backpressure must propagate as an explicit recording failure',
  );
  assert.match(
    gateway,
    /Future<void> exportRecording\([\s\S]*type': 'export'[\s\S]*_recorderExportCompleter![\s\S]*future\.timeout[\s\S]*createObjectURL[\s\S]*click\(\)[\s\S]*revokeObjectURL/,
    'explicit export must await the finalized object and trigger a bounded browser download',
  );
});
