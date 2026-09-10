import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const gatewayUrl = new URL(
  '../lib/audio/web/browser_audio_worklet_gateway_web.dart',
  import.meta.url,
);
const workletUrl = new URL('../web/audio/livemixmaster-worklet.js', import.meta.url);

async function source(url) {
  return readFile(url, 'utf8');
}

test('browser graph wires post-master PCM through a dedicated recorder Worker with ACKs', async () => {
  const gateway = await source(gatewayUrl);
  const worklet = await source(workletUrl);

  assert.match(
    gateway,
    /web\.Worker\([\s\S]*livemixmaster-recorder-worker\.js[\s\S]*WorkerOptions\(type: 'module'\)/,
    'graph must create the recorder as a module Worker',
  );
  assert.match(
    gateway,
    /workletNode\.port\.addEventListener\([\s\S]*'message'/,
    'graph must listen for AudioWorklet messages',
  );
  assert.match(
    gateway,
    /recorderWorker\.addEventListener\([\s\S]*'message'/,
    'graph must listen for recorder Worker ACK/failure messages',
  );
  assert.match(
    gateway,
    /case 'pcm':[\s\S]*recorderWorker\.postMessage/,
    'post-master PCM must be forwarded away from the audio rendering thread',
  );
  assert.match(
    gateway,
    /case 'pcmAck':[\s\S]*workletNode\.port\.postMessage/,
    'Worker PCM ACK must release AudioWorklet backpressure',
  );
  assert.match(
    gateway,
    /case 'telemetry':[\s\S]*telemetryAck/,
    'meter telemetry must be acknowledged so the worklet never queues unbounded telemetry',
  );
  assert.match(
    gateway,
    /case 'recordingError':[\s\S]*enabled[\s\S]*false/,
    'Worker storage/write failures must disable recording fail-closed',
  );
  assert.match(
    gateway,
    /recorderWorker\.terminate\(\)/,
    'stopping the graph must terminate the dedicated recorder Worker',
  );

  assert.match(
    worklet,
    /type: 'pcm'[\s\S]*samples: interleaved/,
    'AudioWorklet must emit post-master interleaved PCM, not raw capture PCM',
  );
});
