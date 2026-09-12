import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const workflow = readFileSync(
  '.github/workflows/promote-tested-web-artifact.yml',
  'utf8',
);

test('production promotion requires merged PR provenance for the exact commit', () => {
  assert.match(
    workflow,
    /permissions:\s*[\s\S]*?pull-requests:\s*read/,
    'promotion workflow must grant read-only pull-request metadata access',
  );

  assert.match(
    workflow,
    /name:\s*Verify production merge provenance/,
    'promotion must contain an explicit production provenance gate',
  );
  assert.match(
    workflow,
    /if:\s*inputs\.target\s*==\s*['"]production['"]/,
    'the merged-PR gate must apply to production while leaving preview staging unchanged',
  );
  assert.match(workflow, /actions\/github-script@v7/);
  assert.match(workflow, /listPullRequestsAssociatedWithCommit/);
  assert.match(workflow, /pr\.base\.ref\s*===\s*['"]main['"]/);
  assert.match(workflow, /pr\.merged_at/);
  assert.match(
    workflow,
    /pr\.merge_commit_sha\s*===\s*commitSha/,
    'production must require the exact pushed commit to be the merged PR commit',
  );
  assert.match(
    workflow,
    /No merged pull request targeting main is associated with production commit/,
    'production must fail closed when merged-PR provenance is missing',
  );
});
