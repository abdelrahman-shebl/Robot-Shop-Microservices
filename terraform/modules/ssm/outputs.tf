output "parameter_arns" {
  description = "A list of the exact ARNs for the created SSM parameters"
  value = [
    aws_ssm_parameter.mysql_creds.arn,
    aws_ssm_parameter.mongo_creds.arn,
    aws_ssm_parameter.dojo_creds.arn,
    aws_ssm_parameter.opencost_integration.arn
  ]
}