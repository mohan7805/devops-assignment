#!/usr/bin/env bash
###############################################################################
# Post-deployment smoke test. Works against a local docker-compose stack or a
# deployed ALB.
#
#   ./scripts/smoke-test.sh http://localhost:8080
#   ./scripts/smoke-test.sh http://<alb-dns>
###############################################################################
set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
failures=0

check() {
  local name="$1" expected="$2" path="$3"
  local code
  code="$(curl -s -o /tmp/smoke-body -w '%{http_code}' --max-time 10 "${BASE_URL}${path}" || echo 000)"

  if [[ "${code}" == "${expected}" ]]; then
    printf '  \033[32mPASS\033[0m  %-28s %s -> %s\n' "${name}" "${path}" "${code}"
  else
    printf '  \033[31mFAIL\033[0m  %-28s %s -> %s (expected %s)\n' "${name}" "${path}" "${code}" "${expected}"
    failures=$((failures + 1))
  fi
}

echo "==> Smoke testing ${BASE_URL}"
check "health endpoint"   200 /health
check "info endpoint"     200 /info
check "root greeting"     200 /
check "unknown route 404" 404 /nope

echo
echo "==> GET /info"
curl -fsS --max-time 10 "${BASE_URL}/info" | (command -v jq >/dev/null && jq . || cat)

echo
echo "==> Load balancing check (10 requests, distinct hostnames indicate >1 target)"
for _ in $(seq 1 10); do
  # `printf '\n'` matters: curl emits no trailing newline, so without it every
  # hostname would be concatenated into a single line.
  curl -fsS --max-time 5 "${BASE_URL}/info" | sed -n 's/.*"hostname":"\([^"]*\)".*/\1/p'
  printf '\n'
done | grep -v '^$' | sort | uniq -c

echo
if [[ ${failures} -eq 0 ]]; then
  echo "All smoke tests passed."
else
  echo "${failures} smoke test(s) failed." >&2
  exit 1
fi
