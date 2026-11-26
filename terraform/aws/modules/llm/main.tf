data "aws_ami" "ollama" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "tag:Role"
    values = ["ollama"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  asg_name  = "${var.environment}-llm-asg"
  hook_name = "ollama-ready"

  custom_scaling = {
    queue = {
      metric = "MessagesInQueue"
      label  = "Messages in queue per Ollama instance"
      target = var.queue_target
    }
    messages = {
      metric = "MessagesPerMinute"
      label  = "Chat messages per minute per Ollama instance"
      target = var.messages_target
    }
  }

  queue_alarms = {
    high = {
      comparison = "GreaterThanThreshold"
      threshold  = var.queue_target
      periods    = 1
      policy     = "out"
    }
    low = {
      comparison = "LessThanThreshold"
      threshold  = var.scale_in_threshold
      periods    = var.scale_in_minutes
      policy     = "in"
    }
  }
}

resource "aws_iam_role" "this" {
  name = "${var.environment}-llm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#tfsec:ignore:aws-iam-no-policy-wildcards
resource "aws_iam_role_policy" "lifecycle" {
  name = "${var.environment}-llm-lifecycle"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "autoscaling:CompleteLifecycleAction"
        Resource = "arn:aws:autoscaling:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.environment}-llm-instance-profile"
  role = aws_iam_role.this.name
}

resource "aws_launch_template" "this" {
  name_prefix            = "${var.environment}-llm-"
  image_id               = data.aws_ami.ollama.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = var.instance_security_group_ids
  user_data              = base64encode(var.user_data)

  monitoring {
    enabled = true
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.this.name
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.environment}-llm"
    }
  }
}

resource "aws_autoscaling_group" "this" {
  name                      = local.asg_name
  vpc_zone_identifier       = var.subnet_ids
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  health_check_type         = "ELB"
  health_check_grace_period = 600
  target_group_arns         = [aws_lb_target_group.this.arn]
  enabled_metrics           = ["GroupInServiceInstances"]
  metrics_granularity       = "1Minute"
  force_delete              = true
  force_delete_warm_pool    = true

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  initial_lifecycle_hook {
    name                 = local.hook_name
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
    default_result       = "ABANDON"
    heartbeat_timeout    = 1200
  }

  warm_pool {
    pool_state                  = "Stopped"
    max_group_prepared_capacity = var.max_size
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.environment}-llm"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }

  depends_on = [aws_iam_role_policy.lifecycle]
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.environment}-llm-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value     = var.cpu_target
    disable_scale_in = true
  }
}

resource "aws_autoscaling_policy" "custom" {
  for_each = local.custom_scaling

  name                   = "${var.environment}-llm-${each.key}-target"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    customized_metric_specification {
      metrics {
        id          = "value"
        return_data = false

        metric_stat {
          metric {
            namespace   = "LLM"
            metric_name = each.value.metric

            dimensions {
              name  = "Environment"
              value = var.environment
            }
          }

          stat = "Average"
        }
      }

      metrics {
        id          = "instances"
        return_data = false

        metric_stat {
          metric {
            namespace   = "AWS/AutoScaling"
            metric_name = "GroupInServiceInstances"

            dimensions {
              name  = "AutoScalingGroupName"
              value = aws_autoscaling_group.this.name
            }
          }

          stat = "Average"
        }
      }

      metrics {
        id          = "per_instance"
        expression  = "value / instances"
        label       = each.value.label
        return_data = true
      }
    }

    target_value     = each.value.target
    disable_scale_in = true
  }
}

resource "aws_autoscaling_policy" "queue_out" {
  name                      = "${var.environment}-llm-queue-step-out"
  autoscaling_group_name    = aws_autoscaling_group.this.name
  policy_type               = "StepScaling"
  adjustment_type           = "ChangeInCapacity"
  metric_aggregation_type   = "Average"
  estimated_instance_warmup = 120

  step_adjustment {
    scaling_adjustment          = 1
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 2
  }

  step_adjustment {
    scaling_adjustment          = 2
    metric_interval_lower_bound = 2
  }
}

resource "aws_autoscaling_policy" "queue_in" {
  name                    = "${var.environment}-llm-queue-step-in"
  autoscaling_group_name  = aws_autoscaling_group.this.name
  policy_type             = "StepScaling"
  adjustment_type         = "ChangeInCapacity"
  metric_aggregation_type = "Average"

  step_adjustment {
    scaling_adjustment          = -1
    metric_interval_upper_bound = 0
  }
}

resource "aws_cloudwatch_metric_alarm" "queue" {
  for_each = local.queue_alarms

  alarm_name          = "${var.environment}-llm-queue-${each.key}"
  comparison_operator = each.value.comparison
  threshold           = each.value.threshold
  evaluation_periods  = each.value.periods
  datapoints_to_alarm = each.value.periods
  treat_missing_data  = "notBreaching"
  alarm_actions       = [each.value.policy == "out" ? aws_autoscaling_policy.queue_out.arn : aws_autoscaling_policy.queue_in.arn]

  metric_query {
    id = "value"

    metric {
      namespace   = "LLM"
      metric_name = "MessagesInQueue"
      period      = 60
      stat        = "Average"

      dimensions = {
        Environment = var.environment
      }
    }
  }

  metric_query {
    id = "instances"

    metric {
      namespace   = "AWS/AutoScaling"
      metric_name = "GroupInServiceInstances"
      period      = 60
      stat        = "Average"

      dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.this.name
      }
    }
  }

  metric_query {
    id          = "per_instance"
    expression  = "value / instances"
    label       = "In-flight requests per Ollama instance"
    return_data = true
  }
}

resource "aws_lb" "this" {
  name                       = "${lower(var.environment)}-llm-alb"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = var.alb_security_group_ids
  subnets                    = var.subnet_ids
  drop_invalid_header_fields = true
  idle_timeout               = 900

  tags = {
    Name = "${var.environment}-llm-alb"
  }
}

resource "aws_lb_target_group" "this" {
  name                          = "${lower(var.environment)}-llm-tg"
  port                          = 11434
  protocol                      = "HTTP"
  vpc_id                        = var.vpc_id
  load_balancing_algorithm_type = "least_outstanding_requests"

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

#tfsec:ignore:aws-elb-http-not-used
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
