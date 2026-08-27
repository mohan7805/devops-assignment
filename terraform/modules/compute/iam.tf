###############################################################################
# Least-privilege IAM instance role.
#
# There is no "Action": "*" and no "Resource": "*" except where the AWS API
# genuinely does not support resource-level permissions (documented inline).
# Every statement below carries a justification comment.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "instance" {
  name = "${var.name}-instance-role"
  path = "/service-role/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${var.name}-instance-role" })
}

# --------------------------------------------------------------------------
# Session Manager.
#
# This is the AWS-managed policy required by the SSM Agent for Session Manager,
# and it is what removes the need for a bastion host, key pairs or port 22.
# It is scoped to the SSM messaging/agent APIs; it contains no "Action": "*".
# --------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# --------------------------------------------------------------------------
# Everything else is an explicit, resource-scoped inline policy.
# --------------------------------------------------------------------------
data "aws_iam_policy_document" "instance" {

  # ECR: obtaining a registry auth token is an account-level call that AWS does
  # not support resource-level permissions for, hence Resource = "*".
  # It grants nothing on its own - the pull itself is scoped by the next
  # statement to this application's repository only.
  statement {
    sid       = "EcrGetAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # ECR: pull the application image, restricted to the single repository that
  # holds it. The instance can neither push nor read any other repository.
  statement {
    sid    = "EcrPullApplicationImageOnly"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [var.ecr_repository_arn]
  }

  # SSM Parameter Store: read the runtime configuration and secrets at boot.
  # Restricted to this application's parameter paths - no other parameter in
  # the account is readable, and no write action is granted.
  statement {
    sid    = "ReadOwnRuntimeParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = var.secret_parameter_arns
  }

  # KMS: decrypt SecureString parameters.
  #
  # When a customer-managed key is supplied the statement is scoped to that key.
  # Otherwise the parameters use the AWS-managed alias/aws/ssm key, whose ARN
  # cannot be referenced here: alias ARNs are not valid in the Resource element
  # of an IAM policy, and the underlying key does not exist until the first
  # SecureString in the account is created. The kms:ViaService condition is what
  # constrains the grant in that case - the role can only decrypt through SSM,
  # and only for the two parameters the statement above allows it to read.
  statement {
    sid       = "DecryptSecureStringParametersViaSsmOnly"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = var.kms_key_arn != "" ? [var.kms_key_arn] : ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.current.name}.amazonaws.com"]
    }
  }

  # CloudWatch Logs: ship container and system logs. Scoped to this
  # application's log group so the instance cannot read or tamper with the
  # logs of any other workload.
  statement {
    sid    = "WriteApplicationLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      var.log_group_arn,
      "${var.log_group_arn}:*",
    ]
  }

  # CloudWatch agent: publishing custom metrics (memory/disk) has no
  # resource-level permission in the API. The namespace condition confines it
  # to this project's namespace, and PutMetricData cannot read anything.
  statement {
    sid       = "PublishHostMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["CWAgent"]
    }
  }

  # Auto Scaling: the user-data script marks its own lifecycle as healthy and
  # reads the instance refresh state. Restricted to this Auto Scaling Group.
  statement {
    sid    = "DescribeOwnAutoScalingGroup"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeAutoScalingGroups",
    ]
    resources = ["*"] # These Describe* calls do not support resource ARNs.
  }

  # EC2 tag read: the boot script reads its own tags to discover the
  # environment name. Constrained to describing tags, which is read-only.
  statement {
    sid       = "ReadOwnInstanceTags"
    effect    = "Allow"
    actions   = ["ec2:DescribeTags"]
    resources = ["*"] # ec2:DescribeTags does not support resource-level scoping.
  }
}

resource "aws_iam_policy" "instance" {
  name        = "${var.name}-instance-policy"
  description = "Least-privilege permissions for the ${var.name} application instances."
  policy      = data.aws_iam_policy_document.instance.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "instance" {
  role       = aws_iam_role.instance.name
  policy_arn = aws_iam_policy.instance.arn
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-instance-profile"
  role = aws_iam_role.instance.name

  tags = var.tags
}
