# 1. The Queue (The Inbox)
resource "aws_sqs_queue" "karpenter_interruption_queue" {
  name                      = "karpenter-interruption-queue-${var.cluster_name}"
  message_retention_seconds = 300   # 5 minutes
  receive_wait_time_seconds = 20    # Long polling (saves money)
}

# 2. The Queue Policy (The Security Guard)
# Allows EventBridge (and SQS itself) to write messages to this queue
resource "aws_sqs_queue_policy" "karpenter_queue_policy" {
  queue_url = aws_sqs_queue.karpenter_interruption_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter_interruption_queue.arn
      }
    ]
  })
}

# 3. Event Rules (The Sensors)
# We need to capture 4 specific types of AWS events.

# Rule A: Spot Interruption Warning (The most important one)
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "karpenter-spot-interruption-${var.cluster_name}"
  description = "Capture Spot Interruption Warnings"
  
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
}

# Rule B: Rebalance Recommendation (Early warning)
resource "aws_cloudwatch_event_rule" "rebalance_recommendation" {
  name        = "karpenter-rebalance-${var.cluster_name}"
  description = "Capture EC2 Rebalance Recommendations"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })
}

# Rule C: Instance State Change (If a node is manually stopped/terminated)
resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name        = "karpenter-state-change-${var.cluster_name}"
  description = "Capture Node State Changes"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })
}

# Rule D: AWS Health Events (Maintenance scheduled)
resource "aws_cloudwatch_event_rule" "health_event" {
  name        = "karpenter-health-${var.cluster_name}"
  description = "Capture AWS Health Events"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })
}

# 4. The Targets (The Wiring)
# Connect all 4 rules to the same SQS Queue

resource "aws_cloudwatch_event_target" "spot_target" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
}

resource "aws_cloudwatch_event_target" "rebalance_target" {
  rule      = aws_cloudwatch_event_rule.rebalance_recommendation.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
}

resource "aws_cloudwatch_event_target" "state_target" {
  rule      = aws_cloudwatch_event_rule.instance_state_change.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
}

resource "aws_cloudwatch_event_target" "health_target" {
  rule      = aws_cloudwatch_event_rule.health_event.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
}