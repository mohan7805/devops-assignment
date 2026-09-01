# Runbook

## Deploy

Normal path: **push to `main`**. The pipeline tests, builds, scans, pushes and
performs a rolling instance refresh, then fails unless the new version is
healthy in the ALB target group.

Manual deploy of an already-pushed tag:

```bash
aws ssm put-parameter --name /devops-assignment/prod/image_tag \
  --value <short-sha> --type String --overwrite

aws autoscaling start-instance-refresh \
  --auto-scaling-group-name <asg-name> \
  --preferences '{"MinHealthyPercentage":100,"MaxHealthyPercentage":200,"InstanceWarmup":120}'
```

## Roll back

Point the SSM parameter at the previous SHA and refresh again — ECR tags are
immutable, so a SHA always identifies exactly one image.

```bash
aws ecr describe-images --repository-name devops-assignment \
  --query 'sort_by(imageDetails,&imagePushedAt)[-5:].[imageTags[0],imagePushedAt]' --output table

aws ssm put-parameter --name /devops-assignment/prod/image_tag \
  --value <previous-sha> --type String --overwrite
aws autoscaling start-instance-refresh --auto-scaling-group-name <asg-name>
```

To stop a bad refresh in progress:

```bash
aws autoscaling cancel-instance-refresh --auto-scaling-group-name <asg-name>
```

## Debug an unhealthy instance

```bash
./scripts/ssm-session.sh          # no SSH, no bastion, no key pair

sudo systemctl status app
sudo journalctl -u app -n 100 --no-pager
sudo docker ps -a
curl -s localhost:8080/health
sudo tail -n 100 /var/log/user-data.log
```

Target health from outside:

```bash
aws elbv2 describe-target-health --target-group-arn <tg-arn> --output table
```

Application logs:

```bash
aws logs tail /aws/ec2/devops-assignment-prod/app --follow --since 15m
```

## Common failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Targets stuck `unhealthy` | container failed to start | check `/var/log/user-data.log`; confirm the image tag exists in ECR |
| `503` from the ALB | zero healthy targets | check the ASG desired capacity and the app SG ingress rule |
| user-data fails at the ECR login | instance role or NAT problem | verify the private route table points at the NAT Gateway |
| Deploy job times out | user-data health loop never succeeded | the SSM `greeting` parameter may still hold the placeholder |
| `terraform apply` blocks on the lock | a previous run died | `terraform force-unlock <id>` after confirming nothing is running |

## Scale

```bash
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name <asg-name> --desired-capacity 4
```

Permanent changes belong in `terraform/envs/prod/terraform.tfvars`
(`min_size` / `max_size` / `desired_capacity`). Note that `desired_capacity`
carries `ignore_changes` so the target-tracking policy owns it at runtime.

## Tear down

```bash
terraform -chdir=terraform/envs/prod destroy
```

The state bucket and lock table survive (`prevent_destroy`); delete them
manually if you really want them gone.
