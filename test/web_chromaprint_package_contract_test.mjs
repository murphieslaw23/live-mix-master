import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
import test from 'node:test';

const generatedRoot = new URL('../build/chromaprint-wasm/', import.meta.url);
const packagedRoot = new URL('../web/fingerprint/vendor/', import.meta.url);
const workerUrl = new URL('../web/fingerprint/livemixmaster-fingerprint-worker.js', import.meta.url);
const gitignoreUrl = new URL('../.gitignore', import.meta.url);

const assets = [
  'livemixmaster-chromaprint.mjs',
  'livemixmaster-chromaprint-core.mjs',
  'livemixmaster-chromaprint-core.wasm',
];

test('checksum-built Chromaprint outputs are packaged byte-for-byte for Flutter Web', async () => {
  for (const asset of assets) {
    const generated = new URL(asset, generatedRoot);
    const packaged = new URL(asset, packagedRoot);
    await access(generated);
    await access(packaged);
    assert.deepEqual(
      await readFile(packaged),
      await readFile(generated),
      `${asset} must be copied from the verified build output without modification`,
    );
  }

  const adapter = await readFile(new URL('livemixmaster-chromaprint.mjs', packagedRoot), 'utf8');
  assert.match(adapter, /\.\/livemixmaster-chromaprint-core\.mjs/);
  await access(workerUrl);
});

test('generated browser vendor directory is not committed as source', async () => {
  const gitignore = await readFile(gitignoreUrl, 'utf8');
  assert.match(gitignore, /^web\/fingerprint\/vendor\/$/m);
});
