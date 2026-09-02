#!/usr/bin/env bash
###############################################################################
# Zero-downtime probe.
#
# Hits GET /info in a tight loop and records one line per request. Run it while
# a deployment is in flight; a zero-downtime release produces zero FAIL lines
# while the reported commit changes from the old build to the new one.
#
#   ./scripts/zero-downtime-check.sh http://<alb-dns> [logfile] [interval]
#
# Line format:
#   OK   <timestamp> <http_code> <commit> <version> <hostname> <seconds>
#   FAIL <timestamp> <http_code> <curl_exit>
###############################################################################
set -uo pipefail

BASE_URL="${1:?usage: zero-downtime-check.sh <base-url> [logfile] [interval-seconds]}"
LOG_FILE="${2:-/tmp/zero-downtime.log}"
INTERVAL="${3:-0.25}"

: > "${LOG_FILE}"

total=0
failed=0

cleanup() {
  {
    echo "---"
    echo "SUMMARY total=${total} failed=${failed}"
  } >> "${LOG_FILE}"

  echo
  echo "======================================================"
  echo " Zero-downtime probe summary"
  echo "======================================================"
  echo " Requests sent  : ${total}"
  echo " Failed requests: ${failed}"
  echo " Commits seen   : $(grep '^OK' "${LOG_FILE}" | awk '{print $4}' | sort -u | tr '\n' ' ')"
  echo " Log            : ${LOG_FILE}"
  echo "======================================================"

  [[ "${failed}" -eq 0 ]] && exit 0 || exit 1
}
trap cleanup EXIT INT TERM

echo "Probing ${BASE_URL}/info every ${INTERVAL}s. Ctrl-C to stop."

while true; do
  total=$((total + 1))
  start="$(date +%s.%N)"

  # --max-time keeps a hung connection from stalling the probe; a non-2xx
  # response makes curl exit non-zero because of --fail.
  body="$(curl -sS --fail --max-time 5 -w '\n%{http_code}' "${BASE_URL}/info" 2>/dev/null)"
  rc=$?
  end="$(date +%s.%N)"
  elapsed="$(awk -v a="${start}" -v b="${end}" 'BEGIN { printf "%.3f", b - a }')"
  ts="$(date -u +%H:%M:%S.%3N)"

  if [[ ${rc} -eq 0 ]]; then
    code="$(echo "${body}" | tail -n1)"
    json="$(echo "${body}" | sed '$d')"
    commit="$(echo "${json}"  | sed -n 's/.*"commit":"\([^"]*\)".*/\1/p')"
    version="$(echo "${json}" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
    host="$(echo "${json}"    | sed -n 's/.*"hostname":"\([^"]*\)".*/\1/p')"
    echo "OK   ${ts} ${code} ${commit:-?} ${version:-?} ${host:-?} ${elapsed}" >> "${LOG_FILE}"
  else
    failed=$((failed + 1))
    code="$(echo "${body}" | tail -n1)"
    echo "FAIL ${ts} ${code:-000} curl_exit=${rc} ${elapsed}" >> "${LOG_FILE}"
  fi

  sleep "${INTERVAL}"
done
