import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const promotionWorkflow = readFileSync(
  '.github/workflows/promote-tested-web-artifact.yml',
  'utf8',
);
const ciWorkflow = readFileSync('.github/workflows/ci.yml', 'utf8');

test('production promotion requires merged PR provenance for the exact commit', () => {
  assert.match(
    promotionWorkflow,
    /permissions:\s*[\s\S]*?pull-requests:\s*read/,
    'promotion workflow must grant read-only pull-request metadata access',
  );

  assert.match(
    ciWorkflow,
    /permissions:\s*[\s\S]*?pull-requests:\s*read/,
    'caller CI workflow must grant pull-request metadata access to the reusable promotion workflow',
  );

  assert.match(
    promotionWorkflow,
    /name:\s*Verify production merge provenance/,
    'promotion must contain an explicit production provenance gate',
  );
  assert.match(
    promotionWorkflow,
    /if:\s*inputs\.target\s*==\s*['"]production['"]/,
    'the merged-PR gate must apply to production while leaving preview staging unchanged',
  );
  assert.match(promotionWorkflow, /actions\/github-script@v7/);
  assert.match(promotionWorkflow, /listPullRequestsAssociatedWithCommit/);
  assert.match(promotionWorkflow, /pr\.base\.ref\s*===\s*['"]main['"]/);
  assert.match(promotionWorkflow, /pr\.merged_at/);
  assert.match(
    promotionWorkflow,
    /pr\.merge_commit_sha\s*===\s*commitSha/,
    'production must require the exact pushed commit to be the merged PR commit',
  );
  assert.match(
    promotionWorkflow,
    /No merged pull request targeting main is associated with production commit/,
    'production must fail closed when merged-PR provenance is missing',
  );
});
