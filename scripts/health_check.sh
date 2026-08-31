#!/usr/bin/env bash
# Post-deployment health check
# (Section 3: Post-Deployment Verification & Resilience).
#
# Exits non-zero on failure so the calling workflow can trigger an
# automated rollback. Retries with backoff since the service may need a
# few seconds to settle right after a deployment.
#
# Usage: ./scripts/health_check.sh <environment> <base_url>

set -euo pipefail

ENVIRONMENT="${1:?environment is required}"
BASE_URL="${2:?base_url is required}"

MAX_ATTEMPTS=5
SLEEP_SECONDS=5

echo "Running automated health checks against ${ENVIRONMENT} (${BASE_URL})"

for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
  if RESPONSE=$(curl --fail --silent --show-error "${BASE_URL}/health"); then
    if echo "${RESPONSE}" | grep -q '"status":[[:space:]]*"ok"'; then
      echo "Health check passed on attempt ${attempt}/${MAX_ATTEMPTS}: ${RESPONSE}"
      exit 0
    fi
    echo "Attempt ${attempt}/${MAX_ATTEMPTS}: unexpected response body: ${RESPONSE}"
  else
    echo "Attempt ${attempt}/${MAX_ATTEMPTS}: request to ${BASE_URL}/health failed"
  fi

  if [ "${attempt}" -lt "${MAX_ATTEMPTS}" ]; then
    sleep "${SLEEP_SECONDS}"
  fi
done

echo "Health check failed after ${MAX_ATTEMPTS} attempts against ${BASE_URL}/health" >&2
exit 1
