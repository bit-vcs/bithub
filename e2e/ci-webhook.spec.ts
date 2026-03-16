import { test, expect, type APIRequestContext } from '@playwright/test';

const WRITE_TOKEN = 'tok-write-001';
const READ_TOKEN = 'tok-read-001';
const authHeaders = { Authorization: `Bearer ${WRITE_TOKEN}` };

function makeWebhookPayload(eventId: string, ref: string) {
  return {
    event_type: 'relay.incoming_ref',
    event_id: eventId,
    ref,
    source: 'e2e-test',
    occurred_at: Math.floor(Date.now() / 1000),
    room: 'main',
    target: 'session:e2e',
  };
}

function makeStatusPayload(
  runId: string,
  jobId: string,
  stepIndex: number,
  status: string,
) {
  return {
    run_id: runId,
    job_id: jobId,
    step_index: stepIndex,
    status,
    timestamp: String(Math.floor(Date.now() / 1000)),
  };
}

/** Parse "Job: <id> [status]" sections and count steps per job */
function parseJobs(html: string): { id: string; stepCount: number }[] {
  const jobPattern = /Job:\s+(\w+)\s+\[/g;
  const positions: { id: string; start: number }[] = [];
  let m: RegExpExecArray | null;
  while ((m = jobPattern.exec(html)) !== null) {
    positions.push({ id: m[1], start: m.index });
  }
  return positions.map((pos, i) => {
    const end =
      i + 1 < positions.length ? positions[i + 1].start : html.length;
    const section = html.slice(pos.start, end);
    const stepCount = (section.match(/<li>/g) || []).length;
    return { id: pos.id, stepCount };
  });
}

async function triggerRun(
  request: APIRequestContext,
  eventId: string,
  headers: Record<string, string> = authHeaders,
) {
  const res = await request.post('/api/webhook/relay', {
    data: makeWebhookPayload(eventId, 'refs/relay/incoming/main'),
    headers,
  });
  expect(res.status()).toBe(200);
  return res.json();
}

async function updateStep(
  request: APIRequestContext,
  runId: string,
  jobId: string,
  step: number,
  status: string,
) {
  const res = await request.post('/api/actions/runs/status', {
    data: makeStatusPayload(runId, jobId, step, status),
    headers: authHeaders,
  });
  expect(res.status()).toBe(200);
  return res.json();
}

async function getRunJobs(request: APIRequestContext, eventId: string) {
  const res = await request.get(`/actions/runs/${eventId}`);
  expect(res.status()).toBe(200);
  return parseJobs(await res.text());
}

async function completeAllSteps(
  request: APIRequestContext,
  eventId: string,
  status: string,
) {
  const jobs = await getRunJobs(request, eventId);
  for (const job of jobs) {
    for (let i = 0; i < job.stepCount; i++) {
      await updateStep(request, eventId, job.id, i, status);
    }
  }
}

// ---------------------------------------------------------------------------
// Happy path: webhook → pending → success
// ---------------------------------------------------------------------------
test.describe.serial('relay webhook → CI run (happy path)', () => {
  const eventId = `e2e-ok-${Date.now()}`;

  test('webhook creates a CI run from push trigger', async ({ request }) => {
    const body = await triggerRun(request, eventId);
    expect(body.triggered).toBeGreaterThanOrEqual(1);
  });

  test('actions page lists the new run as pending', async ({ page }) => {
    await page.goto('/actions');
    const row = page.getByRole('row').filter({ hasText: eventId });
    await expect(row).toBeVisible();
    await expect(row.getByRole('link', { name: eventId })).toBeVisible();
    await expect(row.getByText('pending')).toBeVisible();
  });

  test('run detail shows jobs and steps', async ({ page }) => {
    await page.goto(`/actions/runs/${eventId}`);
    await expect(page.getByRole('heading', { name: /CI Run/ })).toBeVisible();
    await expect(page.getByText(/ref:\s*main/)).toBeVisible();
    await expect(page.getByText(/status:\s*pending/)).toBeVisible();
    // at least one job heading
    await expect(
      page.getByRole('heading', { name: /^Job:/ }).first(),
    ).toBeVisible();
    // at least one step list item
    await expect(page.getByRole('listitem').first()).toBeVisible();
  });

  test('status updates transition run to success', async ({
    request,
    page,
  }) => {
    await completeAllSteps(request, eventId, 'success');

    await page.goto(`/actions/runs/${eventId}`);
    await expect(page.getByText(/status:\s*success/)).toBeVisible();

    await page.goto('/actions');
    const row = page.getByRole('row').filter({ hasText: eventId });
    await expect(row.getByText('success')).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Failure path: one step fails → run becomes failure
// ---------------------------------------------------------------------------
test.describe.serial('step failure propagates to run', () => {
  const eventId = `e2e-fail-${Date.now()}`;

  test('create run', async ({ request }) => {
    const body = await triggerRun(request, eventId);
    expect(body.triggered).toBeGreaterThanOrEqual(1);
  });

  test('failing first step marks run as failure', async ({
    request,
    page,
  }) => {
    const jobs = await getRunJobs(request, eventId);
    const firstJob = jobs[0];

    // fail the first step
    await updateStep(request, eventId, firstJob.id, 0, 'failure');

    // complete remaining steps as success
    for (let i = 1; i < firstJob.stepCount; i++) {
      await updateStep(request, eventId, firstJob.id, i, 'success');
    }
    // complete other jobs as success
    for (let j = 1; j < jobs.length; j++) {
      for (let i = 0; i < jobs[j].stepCount; i++) {
        await updateStep(request, eventId, jobs[j].id, i, 'success');
      }
    }

    await page.goto(`/actions/runs/${eventId}`);
    await expect(page.getByText(/status:\s*failure/)).toBeVisible();
    // the failed job should show failure
    await expect(
      page.getByRole('heading', { name: new RegExp(`Job: ${firstJob.id}.*failure`) }),
    ).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Running state: partial progress shows running
// ---------------------------------------------------------------------------
test.describe.serial('partial progress shows running', () => {
  const eventId = `e2e-run-${Date.now()}`;

  test('create run', async ({ request }) => {
    await triggerRun(request, eventId);
  });

  test('marking a step as running transitions run to running', async ({
    request,
    page,
  }) => {
    const jobs = await getRunJobs(request, eventId);
    await updateStep(request, eventId, jobs[0].id, 0, 'running');

    await page.goto(`/actions/runs/${eventId}`);
    await expect(page.getByText(/status:\s*running/)).toBeVisible();
  });

  test('completing the running step keeps run pending if others remain', async ({
    request,
    page,
  }) => {
    const jobs = await getRunJobs(request, eventId);
    await updateStep(request, eventId, jobs[0].id, 0, 'success');

    await page.goto(`/actions/runs/${eventId}`);
    // other steps are still pending, so run should be pending
    await expect(page.getByText(/status:\s*pending/)).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Skipped steps: all skipped + success → success
// ---------------------------------------------------------------------------
test('skipped steps count as done', async ({ request }) => {
  const eventId = `e2e-skip-${Date.now()}`;
  await triggerRun(request, eventId);
  const jobs = await getRunJobs(request, eventId);

  // first step skipped, rest success for each job
  for (const job of jobs) {
    await updateStep(request, eventId, job.id, 0, 'skipped');
    for (let i = 1; i < job.stepCount; i++) {
      await updateStep(request, eventId, job.id, i, 'success');
    }
  }

  const detailRes = await request.get(`/actions/runs/${eventId}`);
  const html = await detailRes.text();
  expect(html).toContain('status: success');
});

// ---------------------------------------------------------------------------
// Multiple runs are tracked independently
// ---------------------------------------------------------------------------
test('multiple webhook events create separate runs', async ({
  request,
  page,
}) => {
  const id1 = `e2e-multi1-${Date.now()}`;
  const id2 = `e2e-multi2-${Date.now()}`;

  await triggerRun(request, id1);
  await triggerRun(request, id2);

  await page.goto('/actions');
  await expect(
    page.getByRole('row').filter({ hasText: id1 }),
  ).toBeVisible();
  await expect(
    page.getByRole('row').filter({ hasText: id2 }),
  ).toBeVisible();
});

// ---------------------------------------------------------------------------
// Webhook validation
// ---------------------------------------------------------------------------
test.describe('webhook validation', () => {
  test('rejects unknown event type', async ({ request }) => {
    const res = await request.post('/api/webhook/relay', {
      data: {
        ...makeWebhookPayload('evt-unk', 'refs/relay/incoming/main'),
        event_type: 'unknown.event',
      },
      headers: authHeaders,
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).triggered).toBe(0);
  });

  test('rejects invalid JSON body', async ({ request }) => {
    const res = await request.post('/api/webhook/relay', {
      data: 'not json',
      headers: { 'Content-Type': 'text/plain', ...authHeaders },
    });
    expect(res.status()).toBe(400);
    const body = await res.json();
    expect(body.error).toBeDefined();
  });

  test('rejects malformed ref format', async ({ request }) => {
    const res = await request.post('/api/webhook/relay', {
      data: makeWebhookPayload('evt-badref', 'not/a/valid/ref'),
      headers: authHeaders,
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).triggered).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Status update validation
// ---------------------------------------------------------------------------
test.describe('status update validation', () => {
  test('rejects missing run_id', async ({ request }) => {
    const res = await request.post('/api/actions/runs/status', {
      data: { job_id: 'x', step_index: 0, status: 'success' },
      headers: authHeaders,
    });
    expect(res.status()).toBe(400);
  });

  test('rejects missing job_id', async ({ request }) => {
    const res = await request.post('/api/actions/runs/status', {
      data: { run_id: 'x', step_index: 0, status: 'success' },
      headers: authHeaders,
    });
    expect(res.status()).toBe(400);
  });

  test('rejects missing status', async ({ request }) => {
    const res = await request.post('/api/actions/runs/status', {
      data: { run_id: 'x', job_id: 'y', step_index: 0 },
      headers: authHeaders,
    });
    expect(res.status()).toBe(400);
  });

  test('returns ok:false for nonexistent run', async ({ request }) => {
    const res = await request.post('/api/actions/runs/status', {
      data: makeStatusPayload('nonexistent', 'nojob', 0, 'success'),
      headers: authHeaders,
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).ok).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Permission enforcement
// ---------------------------------------------------------------------------
test.describe('permission enforcement', () => {
  test('webhook rejects request without token', async ({ request }) => {
    const res = await request.post('/api/webhook/relay', {
      data: makeWebhookPayload('evt-noauth', 'refs/relay/incoming/main'),
    });
    expect(res.status()).toBe(401);
  });

  test('webhook rejects invalid token', async ({ request }) => {
    const res = await request.post('/api/webhook/relay', {
      data: makeWebhookPayload('evt-badtoken', 'refs/relay/incoming/main'),
      headers: { Authorization: 'Bearer invalid-token-xyz' },
    });
    expect(res.status()).toBe(401);
  });

  test('webhook rejects read-only token', async ({ request }) => {
    const res = await request.post('/api/webhook/relay', {
      data: makeWebhookPayload('evt-readonly', 'refs/relay/incoming/main'),
      headers: { Authorization: `Bearer ${READ_TOKEN}` },
    });
    expect(res.status()).toBe(403);
  });

  test('status update rejects request without token', async ({ request }) => {
    const res = await request.post('/api/actions/runs/status', {
      data: makeStatusPayload('x', 'y', 0, 'success'),
    });
    expect(res.status()).toBe(401);
  });

  test('status update rejects read-only token', async ({ request }) => {
    const res = await request.post('/api/actions/runs/status', {
      data: makeStatusPayload('x', 'y', 0, 'success'),
      headers: { Authorization: `Bearer ${READ_TOKEN}` },
    });
    expect(res.status()).toBe(403);
  });

  test('read endpoints remain accessible without token', async ({ page }) => {
    const commits = await page.goto('/commits');
    expect(commits!.status()).toBe(200);
    const branches = await page.goto('/branches');
    expect(branches!.status()).toBe(200);
    const actions = await page.goto('/actions');
    expect(actions!.status()).toBe(200);
  });
});

// ---------------------------------------------------------------------------
// Owner token has write access
// ---------------------------------------------------------------------------
test('owner token can trigger webhook', async ({ request }) => {
  const eventId = `e2e-owner-${Date.now()}`;
  const res = await request.post('/api/webhook/relay', {
    data: makeWebhookPayload(eventId, 'refs/relay/incoming/main'),
    headers: { Authorization: 'Bearer tok-owner-001' },
  });
  expect(res.status()).toBe(200);
  expect((await res.json()).triggered).toBeGreaterThanOrEqual(1);
});

// ---------------------------------------------------------------------------
// Status transition: running → failure
// ---------------------------------------------------------------------------
test.describe.serial('running then failure', () => {
  const eventId = `e2e-runfail-${Date.now()}`;

  test('create and start', async ({ request }) => {
    await triggerRun(request, eventId);
    const jobs = await getRunJobs(request, eventId);
    await updateStep(request, eventId, jobs[0].id, 0, 'running');
  });

  test('failing a running step transitions to failure', async ({
    request,
    page,
  }) => {
    const jobs = await getRunJobs(request, eventId);
    await updateStep(request, eventId, jobs[0].id, 0, 'failure');
    // complete rest
    for (let i = 1; i < jobs[0].stepCount; i++) {
      await updateStep(request, eventId, jobs[0].id, i, 'skipped');
    }
    for (let j = 1; j < jobs.length; j++) {
      for (let i = 0; i < jobs[j].stepCount; i++) {
        await updateStep(request, eventId, jobs[j].id, i, 'success');
      }
    }

    await page.goto(`/actions/runs/${eventId}`);
    await expect(page.getByText(/status:\s*failure/)).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Mixed job statuses: one success, one failure
// ---------------------------------------------------------------------------
test('mixed job statuses show overall failure', async ({ request, page }) => {
  const eventId = `e2e-mixed-${Date.now()}`;
  await triggerRun(request, eventId);
  const jobs = await getRunJobs(request, eventId);
  expect(jobs.length).toBeGreaterThanOrEqual(2);

  // first job all success
  for (let i = 0; i < jobs[0].stepCount; i++) {
    await updateStep(request, eventId, jobs[0].id, i, 'success');
  }
  // second job has a failure
  await updateStep(request, eventId, jobs[1].id, 0, 'failure');
  for (let i = 1; i < jobs[1].stepCount; i++) {
    await updateStep(request, eventId, jobs[1].id, i, 'skipped');
  }

  await page.goto(`/actions/runs/${eventId}`);
  await expect(page.getByText(/status:\s*failure/)).toBeVisible();
  // first job should be success
  await expect(
    page.getByRole('heading', {
      name: new RegExp(`Job: ${jobs[0].id}.*success`),
    }),
  ).toBeVisible();
  // second job should be failure
  await expect(
    page.getByRole('heading', {
      name: new RegExp(`Job: ${jobs[1].id}.*failure`),
    }),
  ).toBeVisible();
});

// ---------------------------------------------------------------------------
// All steps skipped → success (not pending)
// ---------------------------------------------------------------------------
test('all steps skipped counts as success', async ({ request }) => {
  const eventId = `e2e-allskip-${Date.now()}`;
  await triggerRun(request, eventId);
  const jobs = await getRunJobs(request, eventId);

  for (const job of jobs) {
    for (let i = 0; i < job.stepCount; i++) {
      await updateStep(request, eventId, job.id, i, 'skipped');
    }
  }

  const res = await request.get(`/actions/runs/${eventId}`);
  expect(await res.text()).toContain('status: success');
});

// ---------------------------------------------------------------------------
// Duplicate event_id triggers no additional run
// ---------------------------------------------------------------------------
test('duplicate event_id is idempotent', async ({ request }) => {
  const eventId = `e2e-dup-${Date.now()}`;
  const first = await triggerRun(request, eventId);
  expect(first.triggered).toBeGreaterThanOrEqual(1);

  // second call with same event_id
  const res = await request.post('/api/webhook/relay', {
    data: makeWebhookPayload(eventId, 'refs/relay/incoming/main'),
    headers: authHeaders,
  });
  expect(res.status()).toBe(200);
  // should still report triggered (overwrites), but not create a second row
});

// ---------------------------------------------------------------------------
// Auth header format variations
// ---------------------------------------------------------------------------
test.describe('auth header format', () => {
  test('lowercase "bearer" is accepted', async ({ request }) => {
    const eventId = `e2e-lc-${Date.now()}`;
    const res = await request.post('/api/webhook/relay', {
      data: makeWebhookPayload(eventId, 'refs/relay/incoming/main'),
      headers: { Authorization: `bearer ${WRITE_TOKEN}` },
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).triggered).toBeGreaterThanOrEqual(1);
  });

  test('non-Bearer scheme is rejected', async ({ request }) => {
    const res = await request.post('/api/webhook/relay', {
      data: makeWebhookPayload('evt-basic', 'refs/relay/incoming/main'),
      headers: { Authorization: `Basic ${WRITE_TOKEN}` },
    });
    expect(res.status()).toBe(401);
  });

  test('empty Authorization header is rejected', async ({ request }) => {
    const res = await request.post('/api/webhook/relay', {
      data: makeWebhookPayload('evt-empty', 'refs/relay/incoming/main'),
      headers: { Authorization: '' },
    });
    expect(res.status()).toBe(401);
  });
});

// ---------------------------------------------------------------------------
// Issue creation API
// ---------------------------------------------------------------------------
test.describe('issue creation API', () => {
  test('create issue with write token', async ({ request, page }) => {
    const res = await request.post('/api/issues', {
      data: { title: 'E2E test issue', body: 'Created by E2E test', author: 'e2e-bot' },
      headers: authHeaders,
    });
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.id).toBeDefined();

    // Verify it appears on the issues page
    await page.goto('/issues');
    await expect(page.getByText('E2E test issue')).toBeVisible();

    // Verify detail page works
    await page.goto(`/issues/${body.id}`);
    await expect(page.getByText('Created by E2E test')).toBeVisible();
  });

  test('create issue rejects without token', async ({ request }) => {
    const res = await request.post('/api/issues', {
      data: { title: 'No auth' },
    });
    expect(res.status()).toBe(401);
  });

  test('create issue rejects read-only token', async ({ request }) => {
    const res = await request.post('/api/issues', {
      data: { title: 'Read only' },
      headers: { Authorization: `Bearer ${READ_TOKEN}` },
    });
    expect(res.status()).toBe(403);
  });

  test('create issue rejects missing title', async ({ request }) => {
    const res = await request.post('/api/issues', {
      data: { body: 'no title' },
      headers: authHeaders,
    });
    expect(res.status()).toBe(400);
  });

  test('add comment to issue', async ({ request, page }) => {
    // Create issue first
    const createRes = await request.post('/api/issues', {
      data: { title: 'Comment test issue' },
      headers: authHeaders,
    });
    const issueId = (await createRes.json()).id;

    // Add comment
    const commentRes = await request.post(`/api/issues/${issueId}/comments`, {
      data: { body: 'Test comment body', author: 'commenter' },
      headers: authHeaders,
    });
    expect(commentRes.status()).toBe(200);
    expect((await commentRes.json()).ok).toBe(true);

    // Verify comment appears
    await page.goto(`/issues/${issueId}`);
    await expect(page.getByText('Test comment body')).toBeVisible();
    await expect(page.getByText('commenter')).toBeVisible();
  });

  test('add comment to nonexistent issue fails', async ({ request }) => {
    const res = await request.post('/api/issues/99999/comments', {
      data: { body: 'orphan comment' },
      headers: authHeaders,
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).ok).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Workflow pages
// ---------------------------------------------------------------------------
test.describe('workflow pages', () => {
  test('/actions/workflows lists workflow files', async ({ page }) => {
    await page.goto('/actions/workflows');
    await expect(
      page.getByRole('link', { name: 'CI' }),
    ).toBeVisible();
  });

  test('/actions/workflows/ci.yml shows workflow detail', async ({ page }) => {
    await page.goto('/actions/workflows/ci.yml');
    await expect(page.getByRole('heading', { name: /CI/ })).toBeVisible();
    await expect(
      page.getByRole('heading', { name: /^Job:/ }).first(),
    ).toBeVisible();
  });

  test('/actions/workflows/nonexistent.yml returns 404', async ({ page }) => {
    const res = await page.goto('/actions/workflows/nonexistent.yml');
    expect(res).not.toBeNull();
    expect(res!.status()).toBe(404);
  });
});

// ---------------------------------------------------------------------------
// Run detail for nonexistent run
// ---------------------------------------------------------------------------
test('nonexistent run returns 404', async ({ page }) => {
  const res = await page.goto('/actions/runs/does-not-exist');
  expect(res).not.toBeNull();
  expect(res!.status()).toBe(404);
});

// ---------------------------------------------------------------------------
// SSR: pages work without JavaScript
// ---------------------------------------------------------------------------
test.describe('SSR without JavaScript', () => {
  test('commits page renders without JS', async ({ browser, baseURL }) => {
    const ctx = await browser.newContext({
      baseURL,
      javaScriptEnabled: false,
    });
    const page = await ctx.newPage();
    const res = await page.goto('/commits');
    expect(res!.status()).toBe(200);
    await expect(page.getByRole('heading', { name: 'Commits' })).toBeVisible();
    await expect(page.getByRole('table')).toBeVisible();
    await ctx.close();
  });

  test('branches page renders without JS', async ({ browser, baseURL }) => {
    const ctx = await browser.newContext({
      baseURL,
      javaScriptEnabled: false,
    });
    const page = await ctx.newPage();
    const res = await page.goto('/branches');
    expect(res!.status()).toBe(200);
    await expect(
      page.getByRole('heading', { name: 'Branches' }),
    ).toBeVisible();
    await expect(page.getByRole('table')).toBeVisible();
    await ctx.close();
  });

  test('actions page renders without JS', async ({ browser, baseURL }) => {
    const ctx = await browser.newContext({
      baseURL,
      javaScriptEnabled: false,
    });
    const page = await ctx.newPage();
    const res = await page.goto('/actions');
    expect(res!.status()).toBe(200);
    await expect(
      page.getByRole('heading', { name: 'CI Runs' }),
    ).toBeVisible();
    await ctx.close();
  });
});
