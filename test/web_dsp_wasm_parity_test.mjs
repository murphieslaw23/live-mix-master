import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

import { runWasmVector } from './helpers/dsp_wasm_harness.mjs';

const parityFixtureUrl = new URL('./fixtures/dsp_parity_vectors.tsv', import.meta.url);

function parseFloatList(value) {
  if (value === '~') {
    return [];
  }
  return value.split(',').map((token) => Number.parseFloat(token));
}

function parseChannel(value) {
  const [id, linearTrim, fader, muted, solo, interleaved] = value.split(';');
  return {
    id,
    linearTrim: Number.parseFloat(linearTrim),
    fader: Number.parseFloat(fader),
    muted: muted === '1',
    solo: solo === '1',
    interleaved: parseFloatList(interleaved),
  };
}

function parseMeter(value) {
  const [id, processed, peakLeft, peakRight, rmsLeft, rmsRight, clipping] = value.split(';');
  return {
    id,
    processed: processed === '1',
    peakLeft: Number.parseFloat(peakLeft),
    peakRight: Number.parseFloat(peakRight),
    rmsLeft: Number.parseFloat(rmsLeft),
    rmsRight: Number.parseFloat(rmsRight),
    clipping: clipping === '1',
  };
}

async function loadParityVectors() {
  const raw = await fs.readFile(parityFixtureUrl, 'utf8');
  return raw
    .split(/\r?\n/)
    .filter((line) => line.length > 0 && !line.startsWith('#'))
    .map((line) => {
      const fields = line.split('\t');
      assert.equal(fields.length, 8, `fixture row must contain 8 fields: ${line}`);
      return {
        name: fields[0],
        masterGainLinear: Number.parseFloat(fields[1]),
        channels: fields[2] === '~' ? [] : fields[2].split('|').map(parseChannel),
        expected: parseFloatList(fields[3]),
        limiterActive: fields[4] === '1',
        masterPeakLeft: Number.parseFloat(fields[5]),
        masterPeakRight: Number.parseFloat(fields[6]),
        meters: fields[7] === '~' ? [] : fields[7].split('|').map(parseMeter),
      };
    });
}

function assertClose(actual, expected, message) {
  assert.ok(Math.abs(actual - expected) <= 1e-6, `${message}: expected ${expected}, got ${actual}`);
}

test('Wasm DSP matches canonical parity vectors', async () => {
  const vectors = await loadParityVectors();
  assert.ok(vectors.length >= 11, 'shared parity fixture must include the empty-frame boundary');

  for (const vector of vectors) {
    const actual = await runWasmVector(vector);
    assert.equal(actual.output.length, vector.expected.length, `${vector.name}: output length`);
    actual.output.forEach((sample, index) => {
      assertClose(sample, vector.expected[index], `${vector.name}: output[${index}]`);
    });
    assert.equal(actual.limiterActive, vector.limiterActive, `${vector.name}: limiter state`);
    assertClose(actual.masterPeakLeft, vector.masterPeakLeft, `${vector.name}: master left peak`);
    assertClose(actual.masterPeakRight, vector.masterPeakRight, `${vector.name}: master right peak`);

    assert.equal(actual.meters.length, vector.meters.length, `${vector.name}: meter count`);
    actual.meters.forEach((meter, index) => {
      const expected = vector.meters[index];
      assert.equal(meter.id, expected.id, `${vector.name}: meter id ${index}`);
      assert.equal(meter.processed, expected.processed, `${vector.name}: ${meter.id} processed`);
      assertClose(meter.peakLeft, expected.peakLeft, `${vector.name}: ${meter.id} peakLeft`);
      assertClose(meter.peakRight, expected.peakRight, `${vector.name}: ${meter.id} peakRight`);
      assertClose(meter.rmsLeft, expected.rmsLeft, `${vector.name}: ${meter.id} rmsLeft`);
      assertClose(meter.rmsRight, expected.rmsRight, `${vector.name}: ${meter.id} rmsRight`);
      assert.equal(meter.clipping, expected.clipping, `${vector.name}: ${meter.id} clipping`);
    });
  }
});