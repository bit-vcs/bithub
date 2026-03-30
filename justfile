# bithub task runner

default:
  just --list

# ---- Build & Test ----

check:
  moon check --target js

test:
  moon test --target js

build:
  moon build --target js

fmt:
  moon fmt

test-e2e:
  pnpm test:e2e

# ---- Server ----

# Start bithub on current repo
serve:
  moon run src/cmd/main_ssr --target js -- 4174 .

# Start bithub on a specific repo
serve-repo repo:
  moon run src/cmd/main_ssr --target js -- 4174 {{repo}}

# Start bithub with seed data (no local repo)
serve-demo:
  moon run src/cmd/main_ssr --target js -- 4174

# ---- Cloudflare ----

deploy:
  moon build --target js && pnpm wrangler deploy

dev-worker:
  moon build --target js && pnpm wrangler dev

# ---- Agent ----

# Create an issue for agents to work on
issue title body="":
  BITHUB_URL=http://127.0.0.1:4174 pnpm tsx scripts/create-issue.ts "{{title}}" "{{body}}"

# Run agent on a specific issue
agent-run id:
  BITHUB_URL=http://127.0.0.1:4174 ISSUE_ID={{id}} pnpm tsx scripts/agent-harness.ts

# Run agent on a free-form task
agent-task task:
  BITHUB_URL=http://127.0.0.1:4174 TASK="{{task}}" pnpm tsx scripts/agent-harness.ts

# Start daemon: auto-process open issues
agent-daemon:
  BITHUB_URL=http://127.0.0.1:4174 pnpm tsx scripts/agent-daemon.ts

# Process open issues once and exit
agent-once:
  BITHUB_URL=http://127.0.0.1:4174 pnpm tsx scripts/agent-daemon.ts --once

# Run multiple agents in parallel
agent-parallel:
  BITHUB_URL=http://127.0.0.1:4174 pnpm tsx scripts/parallel-agents.ts

# ---- Workflow: Issue → Agent → Done ----

# ---- VRT (Visual Regression + Semantic Testing) ----

# Initialize VRT baselines (requires running server)
vrt-init:
  npx tsx vrt/src/vrt-cli.ts init

# Capture current VRT snapshots
vrt-capture:
  npx tsx vrt/src/vrt-cli.ts capture

# Verify VRT snapshots against baselines
vrt-verify:
  npx tsx vrt/src/vrt-cli.ts verify

# Accept current snapshots as new baselines
vrt-approve:
  npx tsx vrt/src/vrt-cli.ts approve

# Show VRT report
vrt-report:
  npx tsx vrt/src/vrt-cli.ts report

# Show affected components
vrt-affected:
  npx tsx vrt/src/vrt-cli.ts affected

# Generate spec.json from current state
vrt-introspect:
  npx tsx vrt/src/vrt-cli.ts introspect

# Verify spec.json invariants
vrt-spec-verify:
  npx tsx vrt/src/vrt-cli.ts spec-verify

# Auto-generate expectation.json from diff
vrt-expect:
  npx tsx vrt/src/vrt-cli.ts expect

# Run VRT demo (kitty graphics)
vrt-demo:
  npx tsx vrt/src/demo.ts

# Run fix loop demo (detect → reason → fix → verify)
vrt-demo-fix:
  npx tsx vrt/src/demo-fix-loop.ts

# Run multi-scenario demo (3 complex scenarios)
vrt-demo-multi:
  npx tsx vrt/src/demo-scenarios.ts

# Run 6-step dashboard rebuild demo
vrt-demo-multistep:
  npx tsx vrt/src/demo-multistep.ts

# Run VRT unit tests
vrt-test:
  cd vrt && node --test --experimental-strip-types src/**/*.test.ts

# Full VRT cycle: capture + verify
vrt: vrt-capture vrt-verify

# ---- Workflow: Issue → Agent → Done ----

# Full workflow: create issue, run daemon once
auto title body="":
  #!/usr/bin/env bash
  set -euo pipefail
  echo "Creating issue..."
  BITHUB_URL=http://127.0.0.1:4174 pnpm tsx scripts/create-issue.ts "{{title}}" "{{body}}"
  echo ""
  echo "Running daemon..."
  BITHUB_URL=http://127.0.0.1:4174 MAX_ISSUES=1 pnpm tsx scripts/agent-daemon.ts --once
