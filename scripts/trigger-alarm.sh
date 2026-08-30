#!/usr/bin/env bash
###############################################################################
# CloudWatch alarm demonstration.
#
# Drives the ALB 5XX metric above the alarm threshold by calling the
# /simulate/500 endpoint (enabled with ENABLE_CHAOS=true), then waits for the
# alarm to move to ALARM state - at which point SNS emails the subscriber.
#
#   ./scripts/trigger-alarm.sh http://<alb-dns> devops-assignment-prod-target-5xx [count]
###############################################################################
set -euo pipefail

BASE_URL="${1:?usage: trigger-alarm.sh <base-url> <alarm-name> [request-count]}"
ALARM_NAME="${2:?usage: trigger-alarm.sh <base-url> <alarm-name> [request-count]}"
COUNT="${3:-40}"

echo "==> Sending ${COUNT} requests to ${BASE_URL}/simulate/500"
for i in $(seq 1 "${COUNT}"); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${BASE_URL}/simulate/500" || echo 000)"
  printf '  request %2d -> HTTP %s\n' "${i}" "${code}"
  sleep 0.2
done

echo
echo "==> Waiting for alarm '${ALARM_NAME}' to fire (CloudWatch aggregates over 1 minute)..."
for attempt in $(seq 1 30); do
  state="$(aws cloudwatch describe-alarms --alarm-names "${ALARM_NAME}" \
    --query 'MetricAlarms[0].StateValue' --output text)"
  echo "  attempt ${attempt}: state=${state}"

  if [[ "${state}" == "ALARM" ]]; then
    echo
    echo "==> Alarm fired. Reason:"
    aws cloudwatch describe-alarms --alarm-names "${ALARM_NAME}" \
      --query 'MetricAlarms[0].{State:StateValue,Reason:StateReason,Updated:StateUpdatedTimestamp}' \
      --output table
    echo
    echo "An email has been sent to the confirmed SNS subscriber."
    echo "Capture the notification and save it under docs/evidence/."
    exit 0
  fi
  sleep 20
done

echo "Alarm did not reach ALARM state within the timeout." >&2
exit 1
