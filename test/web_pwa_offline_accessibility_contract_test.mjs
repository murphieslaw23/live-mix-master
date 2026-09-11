import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync, readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root = resolve(import.meta.dirname, '..');
const read = (relativePath) => readFileSync(resolve(root, relativePath), 'utf8');

function iconBySize(manifest, size) {
  return manifest.icons?.find((icon) =>
    typeof icon.sizes === 'string' && icon.sizes.split(/\s+/).includes(size),
  );
}

test('PWA manifest packages deterministic 192 and 512 maskable PNG icons', () => {
  const manifest = JSON.parse(read('web/manifest.json'));

  for (const size of ['192x192', '512x512']) {
    const icon = iconBySize(manifest, size);
    assert.ok(icon, `manifest must declare a ${size} icon`);
    assert.equal(icon.type, 'image/png');
    assert.match(icon.purpose ?? '', /(?:^|\s)maskable(?:\s|$)/);
    assert.ok(
      existsSync(resolve(root, 'web', icon.src)),
      `manifest icon ${icon.src} must exist in web/`,
    );
  }
});

test('web bootstrap preserves browser zoom and registers an explicit offline-shell worker', () => {
  const index = read('web/index.html');

  assert.doesNotMatch(index, /user-scalable\s*=\s*no/i);
  assert.doesNotMatch(index, /maximum-scale\s*=\s*1(?:\.0)?/i);
  assert.match(index, /serviceWorker/);
  assert.match(index, /lmm-service-worker\.js/);
});

test('Flutter bootstrap leaves service-worker ownership to the explicit LiveMixMaster worker', () => {
  assert.ok(
    existsSync(resolve(root, 'web/flutter_bootstrap.js')),
    'web/flutter_bootstrap.js must explicitly disable Flutter service-worker registration',
  );

  const bootstrap = read('web/flutter_bootstrap.js');
  assert.match(bootstrap, /\{\{flutter_js\}\}/);
  assert.match(bootstrap, /\{\{flutter_build_config\}\}/);
  assert.match(bootstrap, /_flutter\.loader\.load\(\s*\)\s*;/);
  assert.doesNotMatch(bootstrap, /serviceWorkerSettings/);
  assert.doesNotMatch(bootstrap, /flutter_service_worker/);
});

test('offline-shell worker caches same-origin app resources but never caches API traffic', () => {
  assert.ok(
    existsSync(resolve(root, 'web/lmm-service-worker.js')),
    'web/lmm-service-worker.js must exist',
  );
  assert.ok(
    existsSync(resolve(root, 'web/offline.html')),
    'web/offline.html must provide a deterministic no-network fallback',
  );

  const worker = read('web/lmm-service-worker.js');
  assert.match(worker, /addEventListener\(['"]install['"]/);
  assert.match(worker, /addEventListener\(['"]fetch['"]/);
  assert.match(worker, /index\.html/);
  assert.match(worker, /offline\.html/);
  assert.match(worker, /manifest\.json/);
  assert.match(worker, /\/api\//);
  assert.match(worker, /request\.method\s*!==?\s*['"]GET['"]/);
  assert.match(worker, /url\.origin\s*!==?\s*self\.location\.origin/);
  assert.match(
    worker,
    /request\.mode\s*===?\s*['"]navigate['"][\s\S]*caches\.match\(['"]\.\/offline\.html['"]\)/,
  );
});
