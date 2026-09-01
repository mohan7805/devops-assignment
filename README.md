# DevOps Assignment — Containerised API on AWS, entirely in code

A small REST API, containerised, provisioned with Terraform and deployed by GitHub
Actions. A push to `main` results in a running, load-balanced, publicly reachable
application with **no manual intervention**.

```
                       ┌──────────────────────── AWS region ───────────────────────────┐
                       │                        VPC 10.0.0.0/16                        │
   push to main        │                                                               │
        │              │   AZ-a                              AZ-b                      │
        ▼              │  ┌──────────────────┐             ┌──────────────────┐        │
 ┌──────────────┐      │  │ public 10.0.0/20 │             │ public 10.0.16/20│        │
 │GitHub Actions│      │  │   ALB  +  NAT    │◀───IGW────▶ │       ALB        │        │
 │ test → build │      │  └────────┬─────────┘             └────────┬─────────┘        │
 │ → trivy scan │      │           │  :8080 (alb-sg ▶ app-sg)       │                  │
 │ → push ECR   │──────┼──▶ ECR    ▼                                ▼                  │
 │ → deploy     │      │  ┌──────────────────┐             ┌──────────────────┐        │
 └──────────────┘      │  │private 10.0.128  │             │private 10.0.144  │        │
        │              │  │  t3.micro (asg)  │             │  t3.micro (asg)  │        │
        └── SSM param  │  │  docker run app  │             │  docker run app  │        │
            + instance │  └──────────────────┘             └──────────────────┘        │
            refresh    │        │  │  │                                                │
                       │        │  │  └──▶ CloudWatch Logs (30d) ──▶ alarms ──▶ SNS ──▶ email
                       │        │  └─────▶ SSM Parameter Store (image tag + secret)    │
                       │        └────────▶ SSM Session Manager (admin access)          │
                       └───────────────────────────────────────────────────────────────┘
```

---

## Repository layout

```
.
├── app/                            Node.js 24 REST API
│   ├── src/{app,config,server}.js  Express app, env-driven config, graceful shutdown
│   └── tests/                      Jest unit tests (11 tests, meaningful assertions)
├── Dockerfile                      Multi-stage, pinned base image, non-root user
├── docker-compose.yml              Local stack: 2 API replicas behind nginx
├── nginx/nginx.conf                Local stand-in for the ALB
├── terraform/
│   ├── bootstrap/                  S3 state bucket (versioned+encrypted) + DynamoDB lock
│   ├── envs/prod/                  Root module wiring everything together
│   └── modules/
│       ├── vpc/                    VPC, 2 AZ, 2 public + 2 private subnets, IGW, NAT
│       ├── security/               Security groups chained by reference
│       ├── alb/                    ALB + target group with /health check
│       ├── compute/                Launch template, ASG, least-privilege IAM, user-data
│       ├── ecr/                    Image repository with immutable tags
│       └── observability/          Log group, SNS topic, CloudWatch alarms, dashboard
├── .github/workflows/
│   ├── ci-cd.yml                   test → build → scan → push → deploy → verify
│   └── terraform.yml               fmt/validate/IaC-scan → plan → apply
├── scripts/                        zero-downtime probe, alarm demo, SSM session, smoke test
└── docs/                           Runbook, alarm demo, security notes, evidence
```

---

## 1. Application & container

| Requirement | Where |
|---|---|
| `GET /health` returns 200 | `app/src/app.js` |
| `GET /info` returns version, git SHA, hostname | `app/src/app.js` |
| Multi-stage Dockerfile | `Dockerfile` (deps → test → prod-deps → runtime) |
| Non-root final image | `USER 10001:10001` |
| Base image pinned | `node:24.20.0-alpine3.24` — never `latest` |
| All config from env vars | `app/src/config.js` — `PORT`, `APP_VERSION`, `GIT_COMMIT_SHA`, `GREETING`, `APP_ENV` |
| Unit tests | `app/tests/` — 11 tests across 2 files |

```console
$ curl -s http://<alb-dns>/info | jq
{
  "version": "1.0.0",
  "commit": "a3f9c21",
  "hostname": "ip-10-0-131-84.ap-south-1.compute.internal",
  "environment": "prod",
  "greeting": "Hello from SSM Parameter Store"
}
```

### Run it locally with Docker Compose

```bash
cp .env.example .env

# Two API replicas behind an nginx load balancer on :8080
docker compose up --build -d --scale api=2

curl localhost:8080/health          # {"status":"ok","uptime_s":3.1}
curl localhost:8080/info            # hostname alternates between the two replicas
./scripts/smoke-test.sh http://localhost:8080

# Unit tests inside the image (Dockerfile `test` stage)
docker compose --profile test run --rm tests

docker compose down -v
```

`make up`, `make smoke`, `make compose-test` and `make down` are shortcuts for the same.

---

## 2. Infrastructure (Terraform)

| Requirement | Implementation |
|---|---|
| VPC `10.0.0.0/16`, 2 AZs | `modules/vpc` — `/20` subnets carved with `cidrsubnet()` |
| 2 public + 2 private subnets | `10.0.0.0/20`, `10.0.16.0/20` public; `10.0.128.0/20`, `10.0.144.0/20` private |
| IGW, NAT, route tables per tier | one public route table, one private route table per AZ |
| ALB in public subnets | `modules/alb`, health check on `/health`, matcher `200` |
| ASG of 2 × t3.micro, private subnets | `modules/compute`, min 2 / max 4 / desired 2 |
| `health_check_type = "ELB"` | `modules/compute/main.tf` |
| Container started by user-data | `modules/compute/user_data.sh.tftpl` |
| SGs chained by reference | `internet → alb-sg → app-sg`, via `referenced_security_group_id` |
| Port 22 never open to `0.0.0.0/0` | there is **no** port 22 rule at all — SSM only |
| No hardcoded AMI IDs | `data "aws_ssm_parameter" "al2023_ami"` |
| No hardcoded AZ names | `data "aws_availability_zones" "available"` |
| Remote state, versioned + encrypted | `terraform/bootstrap` S3 bucket + SSE + versioning |
| State locking | DynamoDB table `devops-assignment-tf-locks` |
| Modules | six reusable modules under `terraform/modules/` |
| Provider versions pinned | `required_version >= 1.6.0, < 2.0.0`, `aws ~> 5.60` |
| `Project` / `Owner` / `ManagedBy=terraform` tags | provider-level `default_tags` **and** per-module `tags` |

### First-time setup

```bash
# 1. Remote state backend (run once)
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply \
  -var="owner=platform-team" \
  -var="state_bucket_name=devops-assignment-tfstate-<account-id>"

# 2. Main stack
terraform -chdir=terraform/envs/prod init \
  -backend-config="bucket=devops-assignment-tfstate-<account-id>" \
  -backend-config="key=prod/terraform.tfstate" \
  -backend-config="region=ap-south-1" \
  -backend-config="dynamodb_table=devops-assignment-tf-locks"

cp terraform/envs/prod/terraform.tfvars.example terraform/envs/prod/terraform.tfvars
terraform -chdir=terraform/envs/prod apply

# 3. Set the real secret (never stored in git)
aws ssm put-parameter --name /devops-assignment/prod/greeting \
  --type SecureString --value "Hello from SSM Parameter Store" --overwrite

# 4. Confirm the SNS subscription email AWS just sent you.
terraform -chdir=terraform/envs/prod output app_url
```

---

## 3. CI/CD pipeline

`.github/workflows/ci-cd.yml` runs on **every push to `main`**.

| Stage | Fails the build when… | Implementation |
|---|---|---|
| **Test** | any unit test fails | `npm run test:ci` — Jest exits non-zero |
| **Build** | the image build fails | `docker/build-push-action`, tagged `${short_sha}` — never `latest` |
| **Scan** | any HIGH or CRITICAL vulnerability | `trivy-action` with `severity: HIGH,CRITICAL` and **`exit-code: '1'`** |
| **Push** | the push to ECR fails | `docker push` under `set -euo pipefail` |
| **Deploy** | the new version never becomes healthy in the ALB target group | instance refresh + `describe-target-health` gate + `/info` commit assertion |

Additional guards: a zero-downtime probe asserts **0 failed requests**, and a
`rollback` job cancels an in-flight refresh if the deploy job fails.

### Credentials

All from **GitHub Secrets**, masked automatically by GitHub; the account ID and
ECR registry are masked explicitly with `::add-mask::`.

| Secret | Purpose |
|---|---|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | deploy identity |
| `TF_STATE_BUCKET` | S3 backend bucket |
| `TF_LOCK_TABLE` | DynamoDB lock table |
| `ALARM_EMAIL` | SNS subscription address |

| Repository variable | Default |
|---|---|
| `AWS_REGION` | `ap-south-1` |
| `PROJECT` | `devops-assignment` |
| `ENVIRONMENT` | `prod` |
| `APP_VERSION` | `1.0.0` |

> For a production account, prefer GitHub OIDC (`role-to-assume:`) over static
> keys — see `docs/SECURITY.md`.

### How the deployment achieves zero downtime

1. CI writes the new short SHA to SSM `/devops-assignment/prod/image_tag`.
2. `start-instance-refresh` with `MinHealthyPercentage: 100`,
   `MaxHealthyPercentage: 200` — a **new** instance enters service **before** an
   old one leaves.
3. New instances boot, read the tag from SSM, pull from ECR and only report
   success once their own `/health` returns 200 (user-data blocks on it).
4. The ALB registers them; old instances are drained over a 30 s
   deregistration delay while the app answers `SIGTERM` by flipping `/health`
   to 503 and finishing in-flight requests.
5. The pipeline fails unless every target reaches `healthy` and `/info` reports
   the new commit.

Proof is produced automatically by `scripts/zero-downtime-check.sh`, which runs
throughout the release and is uploaded as the `zero-downtime-log` artifact:

```
OK   09:14:02.118 200 a3f9c21 1.0.0 ip-10-0-131-84  0.041
OK   09:14:02.402 200 a3f9c21 1.0.0 ip-10-0-147-12  0.038
OK   09:14:31.884 200 7d1e4b8 1.0.0 ip-10-0-131-201 0.044   <- new version appears
OK   09:15:12.556 200 7d1e4b8 1.0.0 ip-10-0-147-77  0.039
---
SUMMARY total=642 failed=0
```

---

## 4. Security & monitoring

| Requirement | Implementation |
|---|---|
| SSM Session Manager only | `AmazonSSMManagedInstanceCore` on the instance role; **no** `key_name`, **no** bastion, **no** port 22 rule |
| Least-privilege IAM, no `"Action": "*"` | `modules/compute/iam.tf` — every statement resource-scoped and justified in a comment |
| Secrets in Parameter Store | `/devops-assignment/prod/greeting` (SecureString), read at boot; `ignore_changes = [value]` keeps the real value out of git |
| Logs to CloudWatch with retention | Docker `awslogs` driver + CloudWatch agent → `/aws/ec2/devops-assignment-prod/app`, 30-day retention |
| Alarm on 5XX / UnHealthyHostCount + SNS email | `modules/observability` — 4 alarms, all wired to an SNS email subscription |

Extra hardening: IMDSv2 required, encrypted gp3 root volumes, VPC flow logs for
REJECT traffic, immutable ECR tags with scan-on-push, TLS-only state bucket,
read-only container filesystem with all capabilities dropped.

```bash
# Administrative access — no SSH anywhere
./scripts/ssm-session.sh
# or: aws ssm start-session --target i-0abc...
```

### Alarm demonstration

```bash
./scripts/trigger-alarm.sh http://<alb-dns> devops-assignment-prod-target-5xx
```

Full walkthrough and the resulting email: **[docs/ALARM-DEMO.md](docs/ALARM-DEMO.md)**.

---

## Documentation

- **[docs/RUNBOOK.md](docs/RUNBOOK.md)** — deploy, roll back, debug, scale
- **[docs/ALARM-DEMO.md](docs/ALARM-DEMO.md)** — firing the alarm and the SNS notification
- **[docs/SECURITY.md](docs/SECURITY.md)** — IAM justifications and the threat model
- **[docs/EVIDENCE.md](docs/EVIDENCE.md)** — checklist of artefacts to capture for submission

## Cost

Roughly **$45–55/month** in `ap-south-1`: ALB ~$18, 2 × t3.micro ~$15,
NAT Gateway ~$32 (set `single_nat_gateway = false` for HA and double it),
plus a few dollars for logs, ECR and DynamoDB. `terraform destroy` removes
everything except the state bucket and lock table, which are protected by
`prevent_destroy`.
