#!/usr/bin/env bash
# QA test suite run after a QA deployment
# (Section 2: Deploy to QA -> QA Testing and Approval).
#
# Usage: ./scripts/qa_test.sh <environment> <base_url>

set -euo pipefail

ENVIRONMENT="${1:?environment is required}"
BASE_URL="${2:?base_url is required}"

echo "Running QA test suite against ${ENVIRONMENT} (${BASE_URL})"

echo "-> GET /health"
curl --fail --silent --show-error "${BASE_URL}/health" > /dev/null

echo "-> GET /items"
curl --fail --silent --show-error "${BASE_URL}/items" > /dev/null

echo "-> POST /items"
CREATE_RESPONSE=$(curl --fail --silent --show-error -X POST "${BASE_URL}/items" \
  -H "Content-Type: application/json" \
  -d '{"name": "qa-test-item"}')
echo "${CREATE_RESPONSE}"
echo "${CREATE_RESPONSE}" | grep -q '"name":[[:space:]]*"qa-test-item"'

echo "-> POST /items with invalid payload should be rejected"
INVALID_STATUS=$(curl --silent --output /dev/null --write-out '%{http_code}' -X POST "${BASE_URL}/items" \
  -H "Content-Type: application/json" \
  -d '{"name": ""}')
if [ "${INVALID_STATUS}" != "400" ]; then
  echo "Expected HTTP 400 for an invalid item, got ${INVALID_STATUS}" >&2
  exit 1
fi

echo "QA test suite passed."
