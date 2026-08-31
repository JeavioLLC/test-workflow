#!/usr/bin/env bash
# UAT validation run after a Staging deployment
# (Section 2: Deploy to Staging -> UAT Validation and Approval).
#
# This is a sample end-to-end business-flow check standing in for real
# UAT sign-off - replace/extend with the actual acceptance scenarios.
#
# Usage: ./scripts/uat_validation.sh <environment> <base_url>

set -euo pipefail

ENVIRONMENT="${1:?environment is required}"
BASE_URL="${2:?base_url is required}"

echo "Running UAT validation against ${ENVIRONMENT} (${BASE_URL})"

echo "-> GET /health"
curl --fail --silent --show-error "${BASE_URL}/health" > /dev/null

echo "-> End-to-end: create an item, then confirm it's listed"
ITEM_NAME="uat-validation-$(date +%s)"
CREATE_RESPONSE=$(curl --fail --silent --show-error -X POST "${BASE_URL}/items" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"${ITEM_NAME}\"}")
echo "${CREATE_RESPONSE}"

LIST_RESPONSE=$(curl --fail --silent --show-error "${BASE_URL}/items")
echo "${LIST_RESPONSE}" | grep -q "\"name\":[[:space:]]*\"${ITEM_NAME}\""

echo "UAT validation passed."
