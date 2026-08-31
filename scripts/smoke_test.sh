#!/usr/bin/env bash
# Smoke tests run immediately after a Development deployment
# (Section 2: Deploy to DEV -> Smoke Testing).
#
# Usage: ./scripts/smoke_test.sh <environment> <base_url>

set -euo pipefail

ENVIRONMENT="${1:?environment is required}"
BASE_URL="${2:?base_url is required}"

echo "Running smoke tests against ${ENVIRONMENT} (${BASE_URL})"

echo "-> GET /health"
HEALTH_RESPONSE=$(curl --fail --silent --show-error "${BASE_URL}/health")
echo "${HEALTH_RESPONSE}"
echo "${HEALTH_RESPONSE}" | grep -q '"status":[[:space:]]*"ok"'

echo "-> GET /"
curl --fail --silent --show-error "${BASE_URL}/" > /dev/null

echo "Smoke tests passed."
