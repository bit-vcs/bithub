import { test, expect } from '@playwright/test';

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

test.describe.serial('relay webhook → CI run', () => {
  const eventId = `e2e-${Date.now()}`;

  test('webhook creates a CI run from push trigger', async ({ request }) => {
    const res = await request.post('/api/webhook/relay', {
      data: makeWebhookPayload(eventId, 'refs/relay/incoming/main'),
    });
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.triggered).toBeGreaterThanOrEqual(1);
  });

  test('actions page lists the new run as pending', async ({ page }) => {
    await page.goto('/actions');
    const row = page.getByRole('row').filter({ hasText: eventId });
    await expect(row).toBeVisible();
    await expect(row.getByRole('link', { name: eventId })).toBeVisible();
    await expect(row.getByText('pending')).toBeVisible();
  });

  test('status updates transition run to success', async ({
    request,
    page,
  }) => {
    const detailRes = await request.get(`/actions/runs/${eventId}`);
    expect(detailRes.status()).toBe(200);
    const html = await detailRes.text();

    const jobs = parseJobs(html);
    expect(jobs.length).toBeGreaterThan(0);

    for (const job of jobs) {
      for (let i = 0; i < job.stepCount; i++) {
        const payload = makeStatusPayload(eventId, job.id, i, 'success');
        const res = await request.post('/api/actions/runs/status', {
          data: payload,
        });
        const body = await res.json();
        expect(
          body.ok,
          `status update failed for job=${job.id} step=${i}: ${JSON.stringify(body)}`,
        ).toBe(true);
      }
    }

    await page.goto(`/actions/runs/${eventId}`);
    await expect(
      page.getByText(/status:\s*success/, { exact: false }),
    ).toBeVisible();

    await page.goto('/actions');
    const row = page.getByRole('row').filter({ hasText: eventId });
    await expect(row.getByText('success')).toBeVisible();
  });
});

test('webhook rejects unknown event types', async ({ request }) => {
  const res = await request.post('/api/webhook/relay', {
    data: {
      ...makeWebhookPayload('evt-bad', 'refs/relay/incoming/main'),
      event_type: 'unknown.event',
    },
  });
  expect(res.status()).toBe(200);
  const body = await res.json();
  expect(body.triggered).toBe(0);
});
