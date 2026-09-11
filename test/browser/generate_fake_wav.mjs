import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const output = resolve(process.argv[2] ?? 'test/browser/fixtures/fake-mic.wav');
const sampleRate = 48_000;
const durationSeconds = 15;
const frequencyHz = 440;
const amplitude = 0.25;
const channels = 1;
const bitsPerSample = 16;
const samples = sampleRate * durationSeconds;
const dataBytes = samples * channels * (bitsPerSample / 8);
const buffer = Buffer.alloc(44 + dataBytes);

buffer.write('RIFF', 0, 4, 'ascii');
buffer.writeUInt32LE(36 + dataBytes, 4);
buffer.write('WAVE', 8, 4, 'ascii');
buffer.write('fmt ', 12, 4, 'ascii');
buffer.writeUInt32LE(16, 16);
buffer.writeUInt16LE(1, 20);
buffer.writeUInt16LE(channels, 22);
buffer.writeUInt32LE(sampleRate, 24);
buffer.writeUInt32LE(sampleRate * channels * (bitsPerSample / 8), 28);
buffer.writeUInt16LE(channels * (bitsPerSample / 8), 32);
buffer.writeUInt16LE(bitsPerSample, 34);
buffer.write('data', 36, 4, 'ascii');
buffer.writeUInt32LE(dataBytes, 40);

for (let index = 0; index < samples; index += 1) {
  const phase = (2 * Math.PI * frequencyHz * index) / sampleRate;
  const sample = Math.round(Math.sin(phase) * amplitude * 0x7fff);
  buffer.writeInt16LE(sample, 44 + index * 2);
}

mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, buffer);
console.log(JSON.stringify({
  output,
  sampleRate,
  durationSeconds,
  frequencyHz,
  amplitude,
  channels,
  bitsPerSample,
  bytes: buffer.length,
}));
