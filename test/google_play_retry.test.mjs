import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const workflow = readFileSync(new URL('../.github/workflows/google-play.yml', import.meta.url), 'utf8');
const script = workflow.match(/          script: \|\n([\s\S]*?)\n      - name:/)[1]
  .split('\n').map(line => line.slice(12)).join('\n');
const validate = new (Object.getPrototypeOf(async () => {}).constructor)('github', 'context', 'core', script);
const validSource = {
  head_repository: { full_name: 'tianma-if/leeef-reader' },
  path: '.github/workflows/google-play.yml', event: 'workflow_dispatch',
  status: 'completed', head_sha: 'release-commit',
};
const requiredSteps = ['Build signed Android App Bundle', 'Verify Play build cannot self-install APKs', 'Upload build artifact'];

async function check({ source = validSource, steps = requiredSteps, runId = '1234', tag = 'v1.1.5' } = {}) {
  const originalRun = process.env.SOURCE_RUN_ID;
  const originalTag = process.env.RELEASE_TAG;
  process.env.SOURCE_RUN_ID = runId;
  process.env.RELEASE_TAG = tag;
  try {
    await validate({
      rest: {
        actions: { getWorkflowRun: async () => ({ data: source }), listJobsForWorkflowRun: () => {} },
        repos: { getCommit: async () => ({ data: { sha: 'release-commit' } }) },
      },
      paginate: async () => [{ name: 'publish', steps: steps.map(name => ({ name, conclusion: 'success' })) }],
    }, { repo: { owner: 'tianma-if', repo: 'leeef-reader' } }, { info() {} });
  } finally {
    if (originalRun === undefined) delete process.env.SOURCE_RUN_ID;
    else process.env.SOURCE_RUN_ID = originalRun;
    if (originalTag === undefined) delete process.env.RELEASE_TAG;
    else process.env.RELEASE_TAG = originalTag;
  }
}

test('allows the exact official signed and checked artifact', async () => {
  await check();
  await check({ source: { ...validSource, event: 'release' } });
});

test('rejects wrong provenance and incomplete artifact gates', async () => {
  for (const patch of [
    { head_repository: { full_name: 'other/fork' } },
    { head_sha: 'different-release' },
    { path: '.github/workflows/other.yml' },
    { event: 'pull_request' },
    { status: 'in_progress' },
  ]) await assert.rejects(check({ source: { ...validSource, ...patch } }));
  for (const missing of requiredSteps) {
    await assert.rejects(check({ steps: requiredSteps.filter(step => step !== missing) }));
  }
  for (const runId of ['-1', 'abc', '1;echo']) await assert.rejects(check({ runId }));
  for (const tag of ['main', 'v1.1.5-beta', '']) await assert.rejects(check({ tag }));
});

test('review retention is opt-in and reused AABs skip signing/building', () => {
  assert.match(workflow, /changes_not_sent_for_review:[\s\S]*?default: false/);
  assert.match(workflow, /changesNotSentForReview: \$\{\{ env.CHANGES_NOT_SENT_FOR_REVIEW \}\}/);
  for (const name of ['Restore upload keystore', ...requiredSteps]) {
    assert(workflow.includes(`- name: ${name}\n        if: env.REUSE_ARTIFACT_RUN_ID == ''`));
  }
  assert.match(workflow, /github.repository == 'tianma-if\/leeef-reader'/);
});

test('a stable published release automatically targets Play production', () => {
  assert.match(workflow, /release:\n    types: \[published\]/);
  assert.match(workflow, /PLAY_TRACK: \$\{\{ github.event_name == 'release' && 'production'/);
  assert.match(workflow, /PLAY_RELEASE_STATUS: \$\{\{ github.event_name == 'release' && 'completed'/);
  assert.match(workflow, /ref: \$\{\{ github.event_name == 'release' && github.event.release.tag_name/);
  assert.match(workflow, /if: github.event_name == 'release'\n        run: \|/);
  assert.match(workflow, /github.event.release.prerelease == false/);
});
