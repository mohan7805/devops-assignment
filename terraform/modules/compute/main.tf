###############################################################################
# Compute tier: launch template + Auto Scaling Group in the private subnets.
#
# The AMI is never hardcoded - it is resolved from the AWS-published SSM public
# parameter for the latest Amazon Linux 2023 image in the current region.
###############################################################################

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

locals {
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region          = var.aws_region
    ecr_repository_url  = var.ecr_repository_url
    image_tag_parameter = var.image_tag_parameter_name
    greeting_parameter  = var.greeting_parameter_name
    app_port            = var.app_port
    app_version         = var.app_version
    log_group           = var.log_group_name
    environment         = lookup(var.tags, "Environment", "prod")
  })
}

resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-lt-"
  image_id               = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  update_default_version = true

  # No key_name is set anywhere in this configuration: there are no SSH key
  # pairs, and therefore no SSH access. Administration is via SSM Session Manager.

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  vpc_security_group_ids = [var.security_group_id]

  user_data = base64encode(local.user_data)

  # IMDSv2 required: blocks SSRF-style credential theft through IMDSv1.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-app" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name}-app-volume" })
  }

  tags = merge(var.tags, { Name = "${var.name}-lt" })

  lifecycle {
    create_before_destroy = true
  }
}

# The Auto Scaling service needs a service-linked role to validate ALB/TG
# configuration. In fresh accounts this role may not exist yet.
resource "aws_iam_service_linked_role" "autoscaling" {
  aws_service_name = "autoscaling.amazonaws.com"

  # If the role already exists, Terraform will import it on the next apply.
  lifecycle {
    ignore_changes = [description]
  }
}

resource "aws_autoscaling_group" "this" {
  depends_on = [aws_iam_service_linked_role.autoscaling]
  name_prefix         = "${var.name}-asg-"
  vpc_zone_identifier = var.private_subnet_ids

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  # ELB health checks: an instance whose /health stops returning 200 is replaced,
  # not just one whose EC2 status check fails.
  health_check_type         = "ELB"
  health_check_grace_period = 180
  default_cooldown          = 60
  wait_for_capacity_timeout = "15m"

  # Terraform waits until this many instances are healthy in the target group
  # before reporting success, which makes `terraform apply` a real deploy gate.
  min_elb_capacity = var.min_size

  target_group_arns = [var.target_group_arn]

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  # Rolling replacement used for deployments. min_healthy_percentage = 100 with
  # max_healthy_percentage = 200 means a replacement instance is in service
  # before an old one is taken out => zero downtime.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage       = 100
      max_healthy_percentage       = 200
      instance_warmup              = var.instance_warmup_seconds
      scale_in_protected_instances = "Ignore"
    }

    # launch_template changes always trigger a refresh implicitly; a tag
    # change is listed so an operator can force one without a code change.
    triggers = ["tag"]
  }

  # Replace instances one AZ at a time and keep capacity balanced.
  termination_policies = ["OldestLaunchTemplate", "OldestInstance"]

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  dynamic "tag" {
    for_each = merge(var.tags, { Name = "${var.name}-app" })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    # desired_capacity is managed by the scaling policy after the first apply.
    ignore_changes = [desired_capacity]
  }
}

###############################################################################
# Scaling policy - target tracking on average CPU.
###############################################################################

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                      = "${var.name}-cpu-target-tracking"
  autoscaling_group_name    = aws_autoscaling_group.this.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = var.instance_warmup_seconds

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 60
  }
}
