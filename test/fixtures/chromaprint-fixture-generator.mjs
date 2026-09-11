import fs from 'node:fs/promises';
import path from 'node:path';

export const FIXTURE_SAMPLE_RATE = 48000;
export const FIXTURE_CHANNELS = 2;
export const FIXTURE_DURATION_SECONDS = 12;

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

export function floatToPcm16(value) {
  const finite = Number.isFinite(value) ? value : 0;
  const sample = clamp(finite, -1, 1);
  return Math.round(sample < 0 ? sample * 32768 : sample * 32767);
}

export function createChromaprintFixturePcm16() {
  const frames = FIXTURE_SAMPLE_RATE * FIXTURE_DURATION_SECONDS;
  const pcm = new Int16Array(frames * FIXTURE_CHANNELS);

  for (let frame = 0; frame < frames; frame += 1) {
    const t = frame / FIXTURE_SAMPLE_RATE;
    const pulse = 0.62 + 0.22 * Math.sin(2 * Math.PI * 1.75 * t);
    const left = pulse * (
      0.43 * Math.sin(2 * Math.PI * 173.0 * t) +
      0.31 * Math.sin(2 * Math.PI * 347.0 * t) +
      0.17 * Math.sin(2 * Math.PI * 701.0 * t)
    );
    const right = (0.58 + 0.19 * Math.sin(2 * Math.PI * 2.25 * t)) * (
      0.39 * Math.sin(2 * Math.PI * 211.0 * t) +
      0.29 * Math.sin(2 * Math.PI * 419.0 * t) +
      0.19 * Math.sin(2 * Math.PI * 839.0 * t)
    );
    pcm[frame * 2] = floatToPcm16(left);
    pcm[frame * 2 + 1] = floatToPcm16(right);
  }

  return pcm;
}

export async function writePcm16Wav(filePath, pcm, {
  sampleRate = FIXTURE_SAMPLE_RATE,
  channels = FIXTURE_CHANNELS,
} = {}) {
  const bytesPerSample = 2;
  const dataBytes = pcm.length * bytesPerSample;
  const buffer = Buffer.alloc(44 + dataBytes);
  const byteRate = sampleRate * channels * bytesPerSample;
  const blockAlign = channels * bytesPerSample;

  buffer.write('RIFF', 0, 'ascii');
  buffer.writeUInt32LE(36 + dataBytes, 4);
  buffer.write('WAVE', 8, 'ascii');
  buffer.write('fmt ', 12, 'ascii');
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(channels, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(byteRate, 28);
  buffer.writeUInt16LE(blockAlign, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36, 'ascii');
  buffer.writeUInt32LE(dataBytes, 40);

  for (let index = 0; index < pcm.length; index += 1) {
    buffer.writeInt16LE(pcm[index], 44 + index * 2);
  }

  await fs.mkdir(path.dirname(filePath), {recursive: true});
  await fs.writeFile(filePath, buffer);
}
