# Security notes

## Administrative access

There is **no SSH path into this environment**:

- no `key_name` on the launch template — no key pair exists;
- no bastion host;
- no security-group rule for port 22 anywhere in `terraform/` (verify with
  `grep -rn "22" terraform/modules/security/`);
- instances run in private subnets with no public IP and no inbound route from
  the internet.

Shell access is `aws ssm start-session`, which the SSM Agent establishes as an
**outbound** connection. Sessions are authenticated by IAM, and can be logged to
CloudWatch or S3.

## IAM: why every statement exists

`terraform/modules/compute/iam.tf`. No statement uses `"Action": "*"`.

| Sid | Actions | Resource | Justification |
|---|---|---|---|
| `EcrGetAuthorizationToken` | `ecr:GetAuthorizationToken` | `*` | Account-level API with no resource-level permission support. Grants nothing by itself — the pull is scoped separately. |
| `EcrPullApplicationImageOnly` | `BatchCheckLayerAvailability`, `GetDownloadUrlForLayer`, `BatchGetImage` | this repository ARN | Pull the application image only. No push, no other repository. |
| `ReadOwnRuntimeParameters` | `ssm:GetParameter(s)`, `GetParametersByPath` | the two parameter ARNs | Read the image tag and the greeting secret. No write. No other parameter is readable. |
| `DecryptSecureStringParameters` | `kms:Decrypt` | the SSM KMS key | Decrypt the SecureString, constrained further by `kms:ViaService = ssm.<region>.amazonaws.com`. |
| `WriteApplicationLogs` | `logs:CreateLogStream`, `PutLogEvents`, `DescribeLogStreams` | this log group | Ship container and system logs. Cannot read or delete any log group. |
| `PublishHostMetrics` | `cloudwatch:PutMetricData` | `*` | No resource-level permission exists; confined by `cloudwatch:namespace = CWAgent`. Write-only. |
| `DescribeOwnAutoScalingGroup` | `autoscaling:Describe*` | `*` | Read-only Describe calls that do not accept resource ARNs. |
| `ReadOwnInstanceTags` | `ec2:DescribeTags` | `*` | Read-only; `DescribeTags` has no resource-level scoping. |

The AWS-managed `AmazonSSMManagedInstanceCore` policy is attached because it is
the documented prerequisite for Session Manager. It is scoped to the SSM
messaging APIs and contains no `"Action": "*"`.

## Secrets

- `/devops-assignment/prod/greeting` — SSM **SecureString**, KMS-encrypted,
  read at boot by user-data and written to a `0600` root-only env file, so it
  never appears in the process table or in the launch template.
- Terraform creates the parameter with a placeholder and
  `lifecycle { ignore_changes = [value] }`, so the real value is set once out of
  band and an apply can never revert or print it.
- No secret is committed: `.gitignore` excludes `terraform.tfvars`, `*.auto.tfvars`
  and `.env`.
- CI credentials live in GitHub Secrets. GitHub masks them; the account ID and
  the ECR registry hostname are masked explicitly with `::add-mask::`.

## Network

| Control | Where |
|---|---|
| App instances in private subnets, no public IP | `modules/vpc`, `map_public_ip_on_launch = false` |
| App SG accepts traffic only from the ALB SG (by SG ID, not CIDR) | `modules/security` |
| Egress limited to 80/443 | `modules/security` |
| VPC flow logs for REJECTed traffic, 30-day retention | `modules/vpc` |
| ALB drops invalid header fields | `modules/alb` |

## Instance and image hardening

- IMDSv2 required (`http_tokens = "required"`) — blocks SSRF credential theft.
- Encrypted gp3 root volumes.
- Container runs as UID 10001, read-only root filesystem, `--cap-drop ALL`,
  `no-new-privileges`.
- Base image pinned to `node:24.20.0-alpine3.24`.
- ECR: immutable tags, scan-on-push, AES256 encryption.
- CI fails on any HIGH/CRITICAL finding from Trivy — the image is never pushed.

## Known trade-offs (deliberate, for the assignment)

1. **HTTP only.** No domain or ACM certificate is in scope, so the listener is
   port 80. Production would add an HTTPS listener plus an HTTP→HTTPS redirect.
2. **Static AWS keys in GitHub Secrets.** The assignment asks for secrets-based
   credentials. Prefer GitHub OIDC in a real account:
   ```yaml
   permissions:
     id-token: write
   - uses: aws-actions/configure-aws-credentials@v4
     with:
       role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
       aws-region: ${{ env.AWS_REGION }}
   ```
3. **`ENABLE_CHAOS=true` in the deployed environment.** Required only so the
   CloudWatch alarm can be demonstrated. Set it to `false` for real traffic.
4. **Single NAT Gateway** by default, to keep costs down. Set
   `single_nat_gateway = false` for one per AZ.
