#!/usr/bin/env bash
set -euo pipefail

# CI Runner for bithub
# Env vars:
#   BITHUB_URL      - bithub API base URL
#   BITHUB_TOKEN    - Bearer token for status updates
#   CI_RUN_ID       - CI run identifier
#   CI_REPO_URL     - Git repo URL to clone
#   CI_REF          - Git ref to checkout
#   CI_WORKFLOW     - Workflow YAML content (base64)

: "${BITHUB_URL:?BITHUB_URL required}"
: "${BITHUB_TOKEN:?BITHUB_TOKEN required}"
: "${CI_RUN_ID:?CI_RUN_ID required}"

report_status() {
  local job_id="$1" step_index="$2" status="$3"
  curl -sf -X POST "${BITHUB_URL}/api/actions/runs/status" \
    -H "Authorization: Bearer ${BITHUB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"run_id\":\"${CI_RUN_ID}\",\"job_id\":\"${job_id}\",\"step_index\":${step_index},\"status\":\"${status}\",\"timestamp\":\"$(date +%s)\"}" \
    || true
}

echo "=== bithub CI runner ==="
echo "run_id: ${CI_RUN_ID}"
echo "repo:   ${CI_REPO_URL:-none}"
echo "ref:    ${CI_REF:-main}"

# Clone repo if URL provided
if [ -n "${CI_REPO_URL:-}" ]; then
  echo "--- cloning ${CI_REPO_URL} ---"
  git clone --depth 1 --branch "${CI_REF:-main}" "${CI_REPO_URL}" /workspace/repo 2>&1 || {
    echo "clone failed"
    exit 1
  }
  cd /workspace/repo
fi

# Decode and parse workflow
if [ -n "${CI_WORKFLOW:-}" ]; then
  echo "${CI_WORKFLOW}" | base64 -d > /tmp/workflow.yml
  echo "--- workflow loaded ---"
fi

# Simple step executor: run shell commands from env
# Steps are passed as CI_STEP_0, CI_STEP_1, ... (base64 encoded)
# Job ID from CI_JOB_ID
JOB_ID="${CI_JOB_ID:-build}"
step_index=0

while true; do
  var="CI_STEP_${step_index}"
  step_cmd="${!var:-}"
  [ -z "${step_cmd}" ] && break

  decoded=$(echo "${step_cmd}" | base64 -d)
  echo "--- step ${step_index}: ${decoded} ---"

  report_status "${JOB_ID}" "${step_index}" "running"

  if eval "${decoded}"; then
    report_status "${JOB_ID}" "${step_index}" "success"
  else
    report_status "${JOB_ID}" "${step_index}" "failure"
    echo "step ${step_index} failed"
    # Mark remaining steps as skipped
    remaining=$((step_index + 1))
    while true; do
      rvar="CI_STEP_${remaining}"
      [ -z "${!rvar:-}" ] && break
      report_status "${JOB_ID}" "${remaining}" "skipped"
      remaining=$((remaining + 1))
    done
    exit 1
  fi

  step_index=$((step_index + 1))
done

echo "=== CI run complete ==="
