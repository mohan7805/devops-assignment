# CloudWatch alarm demonstration

## The alarms

`terraform/modules/observability/main.tf` creates four alarms, all publishing to
the SNS topic `devops-assignment-prod-alarms`, which has a confirmed email
subscription.

| Alarm | Metric | Condition |
|---|---|---|
| `devops-assignment-prod-target-5xx` | `HTTPCode_Target_5XX_Count` | ≥ 5 in 1 minute |
| `devops-assignment-prod-elb-5xx` | `HTTPCode_ELB_5XX_Count` | ≥ 5 in 1 minute |
| `devops-assignment-prod-unhealthy-hosts` | `UnHealthyHostCount` | > 0 for 2 consecutive minutes |
| `devops-assignment-prod-healthy-hosts-low` | `HealthyHostCount` | < 2 for 3 consecutive minutes |

## Prerequisite: confirm the subscription

Terraform creates the subscription in `PendingConfirmation`; AWS emails a link
that must be clicked once.

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn "$(terraform -chdir=terraform/envs/prod output -raw sns_topic_arn)" \
  --query 'Subscriptions[].{Endpoint:Endpoint,Arn:SubscriptionArn}' --output table
```

`SubscriptionArn` must be a real ARN, not `PendingConfirmation`.

## Firing the 5XX alarm

The API exposes `GET /simulate/500`, which is enabled only when
`ENABLE_CHAOS=true` (set by user-data in the deployed environment, off by
default everywhere else).

```bash
ALB="$(terraform -chdir=terraform/envs/prod output -raw app_url)"
./scripts/trigger-alarm.sh "${ALB}" devops-assignment-prod-target-5xx
```

Expected output:

```
==> Sending 40 requests to http://devops-assignment-prod-alb-....elb.amazonaws.com/simulate/500
  request  1 -> HTTP 500
  request  2 -> HTTP 500
  ...
  request 40 -> HTTP 500

==> Waiting for alarm 'devops-assignment-prod-target-5xx' to fire ...
  attempt 1: state=OK
  attempt 2: state=OK
  attempt 3: state=ALARM

==> Alarm fired. Reason:
-------------------------------------------------------------------------------
|                               DescribeAlarms                                |
+---------+-------------------------------------------------------------------+
| State   | ALARM                                                             |
| Reason  | Threshold Crossed: 1 datapoint [40.0 (…)] was greater than or      |
|         | equal to the threshold (5.0).                                     |
| Updated | 2026-09-02T09:41:07.482000+00:00                                  |
+---------+-------------------------------------------------------------------+
```

## Firing the UnHealthyHostCount alarm

An alternative demonstration — stop the container on one instance and let the
ELB health check notice:

```bash
INSTANCE="$(aws ec2 describe-instances \
  --filters Name=tag:Project,Values=devops-assignment Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)"

aws ssm start-session --target "${INSTANCE}"
# inside the session:
sudo systemctl stop app
```

Within ~45 s (`interval 15` × `unhealthy_threshold 3`) the target goes
`unhealthy`; after two 1-minute periods the alarm fires. The ASG's `ELB` health
check then replaces the instance automatically, and the alarm returns to `OK`.

## The notification

The SNS email looks like this:

```
From:    AWS Notifications <no-reply@sns.amazonaws.com>
Subject: ALARM: "devops-assignment-prod-target-5xx" in Asia Pacific (Mumbai)

You are receiving this email because your Amazon CloudWatch Alarm
"devops-assignment-prod-target-5xx" in the Asia Pacific (Mumbai) region has
entered the ALARM state, because "Threshold Crossed: 1 out of the last 1
datapoints [40.0 (02/09/26 09:40:00)] was greater than or equal to the
threshold (5.0) (minimum 1 datapoint for OK -> ALARM transition)."

Alarm Details:
- Name:        devops-assignment-prod-target-5xx
- Description: Application targets returned 5 or more 5XX responses in one minute.
- State:       ALARM
- Timestamp:   Wednesday 02 September, 2026 09:41:07 UTC
- Namespace:   AWS/ApplicationELB
- Metric:      HTTPCode_Target_5XX_Count
- Statistic:   Sum / Period: 60 seconds / Evaluation periods: 1
- Threshold:   HTTPCode_Target_5XX_Count >= 5.0
```

## Evidence to capture

Save these under `docs/evidence/`:

1. `alarm-in-alarm-state.png` — the CloudWatch console showing the alarm red.
2. `sns-email.png` — the notification email.
3. `alarm-history.png` — the alarm's History tab showing `OK → ALARM → OK`.
4. `trigger-alarm-output.txt` — the terminal output of the script above.

```bash
aws cloudwatch describe-alarm-history \
  --alarm-name devops-assignment-prod-target-5xx \
  --history-item-type StateUpdate --max-records 5 \
  --query 'AlarmHistoryItems[].{When:Timestamp,Summary:HistorySummary}' --output table \
  | tee docs/evidence/alarm-history.txt
```
