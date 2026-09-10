import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const gatewayUrl = new URL(
  '../lib/audio/web/browser_audio_worklet_gateway_web.dart',
  import.meta.url,
);
const runtimeUrl = new URL(
  '../lib/audio/web/browser_capture_runtime_web.dart',
  import.meta.url,
);

async function source(url) {
  return readFile(url, 'utf8');
}

test('WebAudioWorkletGateway is the shared processing and recording gateway', async () => {
  const gateway = await source(gatewayUrl);
  const runtime = await source(runtimeUrl);

  assert.match(
    gateway,
    /implements[\s\S]*BrowserAudioProcessingGateway[\s\S]*BrowserRecordingGateway[\s\S]*BrowserRecordingLifecycleGateway/,
    'one gateway must own the live graph and recorder protocol',
  );
  assert.match(
    runtime,
    /final audioGateway = WebAudioWorkletGateway[\s\S]*BrowserAudioProcessingController\([\s\S]*gateway: audioGateway[\s\S]*BrowserRecordingController\([\s\S]*gateway: audioGateway/,
    'default web runtime must pass the same gateway to processing and recording controllers',
  );
});

test('recording starts only after the Worker is ready and then enables post-master PCM', async () => {
  const gateway = await source(gatewayUrl);

  assert.match(
    gateway,
    /Future<void> startRecording\(\)[\s\S]*type': 'start'[\s\S]*await[\s\S]*_recorderStartCompleter[\s\S]*type': 'recording'[\s\S]*enabled': true/,
    'operator start must await recordingStarted before enabling worklet PCM',
  );
  assert.match(
    gateway,
    /case 'recordingStarted':[\s\S]*_recorderStartCompleter/,
    'Worker readiness must resolve the start handshake',
  );
});

test('stop, failure, and export are explicit fail-closed operator transitions', async () => {
  const gateway = await source(gatewayUrl);

  assert.match(
    gateway,
    /Future<BrowserRecordingArtifact> stopRecording\(\)[\s\S]*enabled': false[\s\S]*type': 'stop'[\s\S]*return await/,
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
    /Future<void> exportRecording\([\s\S]*type': 'export'[\s\S]*recordingExport[\s\S]*createObjectURL[\s\S]*click\(\)[\s\S]*revokeObjectURL/,
    'explicit export must request the finalized object and trigger a bounded browser download',
  );
});
