import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const workflow = readFileSync('.github/workflows/ci.yml', 'utf8');

test('production deploy requires merged PR provenance for main pushes', () => {
  assert.match(
    workflow,
    /permissions:\s*[\s\S]*?pull-requests:\s*read/,
    'CI must grant read-only pull-request metadata access for provenance verification',
  );

  assert.match(
    workflow,
    /release-branch-provenance:\s*[\s\S]*?name:\s*Release Branch Provenance/,
    'CI must define a release-branch provenance gate',
  );

  assert.match(
    workflow,
    /actions\/github-script@v7/,
    'main provenance must be verified against GitHub pull-request metadata',
  );
  assert.match(workflow, /listPullRequestsAssociatedWithCommit/);
  assert.match(workflow, /pr\.base\.ref\s*===\s*['"]main['"]/);
  assert.match(workflow, /pr\.merged_at/);

  assert.match(
    workflow,
    /deploy-tested-web-artifact:\s*[\s\S]*?needs:\s*\[[^\]]*release-branch-provenance[^\]]*\]/,
    'deployment must depend on the provenance gate',
  );
});
