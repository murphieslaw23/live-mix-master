import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';

const root = process.cwd();
const manifestPath = path.join(root, 'web', 'manifest.json');
const iconPath = path.join(root, 'web', 'icons', 'livemixmaster-maskable.svg');
const indexPath = path.join(root, 'web', 'index.html');

test('PWA manifest uses a local maskable LiveMixMaster icon', async () => {
  const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  const icon = manifest.icons.find(
    (candidate) => candidate.src === 'icons/livemixmaster-maskable.svg',
  );

  assert.ok(icon, 'manifest must declare the checked-in LiveMixMaster maskable icon');
  assert.equal(icon.type, 'image/svg+xml');
  assert.equal(icon.sizes, 'any');
  assert.equal(icon.purpose, 'any maskable');
  assert.doesNotMatch(icon.src, /^https?:/);

  const svg = await fs.readFile(iconPath, 'utf8');
  assert.match(svg, /viewBox="0 0 512 512"/);
  assert.match(svg, /data-safe-zone="102 102 308 308"/);

  const index = await fs.readFile(indexPath, 'utf8');
  assert.match(
    index,
    /<link rel="icon" type="image\/svg\+xml" href="icons\/livemixmaster-maskable\.svg">/,
  );
  assert.doesNotMatch(index, /gcdn\.picsart\.com/);
});
