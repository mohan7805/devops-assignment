#!/usr/bin/env bash
###############################################################################
# Open a shell on an application instance through SSM Session Manager.
#
# This is the ONLY administrative access path: there is no bastion host, no key
# pair and no security-group rule for port 22 anywhere in this repository.
#
#   ./scripts/ssm-session.sh [project] [environment]
###############################################################################
set -euo pipefail

PROJECT="${1:-devops-assignment}"
ENVIRONMENT="${2:-prod}"

echo "==> Instances tagged Project=${PROJECT}, Environment=${ENVIRONMENT}:"
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=${PROJECT}" \
            "Name=tag:Environment,Values=${ENVIRONMENT}" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{ID:InstanceId,AZ:Placement.AvailabilityZone,IP:PrivateIpAddress,Launched:LaunchTime}' \
  --output table

INSTANCE_ID="$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=${PROJECT}" \
            "Name=tag:Environment,Values=${ENVIRONMENT}" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)"

if [[ -z "${INSTANCE_ID}" || "${INSTANCE_ID}" == "None" ]]; then
  echo "No running instances found." >&2
  exit 1
fi

echo "==> Starting a Session Manager session on ${INSTANCE_ID}"
echo "    Useful commands once connected:"
echo "      sudo systemctl status app"
echo "      sudo docker ps"
echo "      curl -s localhost:8080/info | jq"
echo "      sudo tail -f /var/log/user-data.log"
echo

exec aws ssm start-session --target "${INSTANCE_ID}"
