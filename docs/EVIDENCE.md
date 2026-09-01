# Submission evidence checklist

Artefacts to capture and store under `docs/evidence/` before submitting.

## 1. Application & container

- [ ] `docker build` output showing the multi-stage build succeeding
- [ ] `docker run --rm <image> id` → `uid=10001(appuser)` (proves non-root)
- [ ] `npm test` output — all tests passing
- [ ] `curl /health` → 200 and `curl /info` → version, commit, hostname
- [ ] `docker compose up --scale api=2` with `/info` returning two hostnames

```bash
docker build -t demo:local .
docker run --rm demo:local id
docker image inspect demo:local --format '{{.Config.User}} {{.Config.Env}}'
```

## 2. Infrastructure

- [ ] `terraform apply` output / summary
- [ ] `terraform output` showing the ALB DNS name
- [ ] AWS console screenshots: VPC subnet map, ALB target group (2 healthy),
      ASG showing min 2 / max 4 and health check type `ELB`
- [ ] Proof there is no port-22 rule:

```bash
aws ec2 describe-security-groups \
  --filters Name=tag:Project,Values=devops-assignment \
  --query 'SecurityGroups[].IpPermissions[?FromPort==`22`]' --output json   # -> []

grep -rn "from_port *= *22" terraform/ || echo "no port 22 rule in the codebase"
```

- [ ] Tags on every resource:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=ManagedBy,Values=terraform Key=Project,Values=devops-assignment \
  --query 'length(ResourceTagMappingList)'
```

- [ ] State bucket versioning and encryption:

```bash
aws s3api get-bucket-versioning --bucket <state-bucket>
aws s3api get-bucket-encryption  --bucket <state-bucket>
```

## 3. CI/CD

- [ ] Screenshot of a green pipeline run on `main`
- [ ] Screenshot of a **red** run where Trivy found a HIGH/CRITICAL — for
      example by temporarily pinning an older base image
- [ ] Screenshot of a **red** run where a unit test fails
- [ ] The ECR repository listing images tagged with short SHAs (no `latest`)
- [ ] The `zero-downtime-log` artifact with `SUMMARY total=<n> failed=0`
- [ ] The job summary table showing the commit change in `/info`

Reproduce the zero-downtime proof by hand:

```bash
ALB="$(terraform -chdir=terraform/envs/prod output -raw app_url)"
./scripts/zero-downtime-check.sh "${ALB}" ./docs/evidence/zero-downtime.log 0.2
# ... push a commit to main, wait for the deployment, then Ctrl-C
```

## 4. Security & monitoring

- [ ] `aws ssm start-session` connecting successfully (no SSH)
- [ ] The instance IAM policy JSON, showing no `"Action": "*"`

```bash
ROLE="$(terraform -chdir=terraform/envs/prod output -raw instance_role_name)"
POLICY_ARN="$(aws iam list-attached-role-policies --role-name "${ROLE}" \
  --query "AttachedPolicies[?contains(PolicyName,'instance-policy')].PolicyArn" --output text)"
aws iam get-policy-version --policy-arn "${POLICY_ARN}" \
  --version-id "$(aws iam get-policy --policy-arn "${POLICY_ARN}" --query 'Policy.DefaultVersionId' --output text)" \
  --query 'PolicyVersion.Document' | tee docs/evidence/instance-policy.json
```

- [ ] SecureString parameter listed **without** its value:

```bash
aws ssm describe-parameters \
  --parameter-filters "Key=Name,Option=BeginsWith,Values=/devops-assignment/" --output table
```

- [ ] CloudWatch log group with the retention period:

```bash
aws logs describe-log-groups --log-group-name-prefix /aws/ec2/devops-assignment \
  --query 'logGroups[].{Name:logGroupName,RetentionDays:retentionInDays}' --output table
```

- [ ] Recent application log lines
- [ ] Alarm in ALARM state + the SNS email (see `ALARM-DEMO.md`)

## 5. Repository

- [ ] Public GitHub repository URL
- [ ] Incremental commit history (`git log --oneline`), not a single squashed commit
