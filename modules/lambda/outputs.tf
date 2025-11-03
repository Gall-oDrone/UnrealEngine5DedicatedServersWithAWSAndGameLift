# Lambda Module Outputs

# Python Lambda outputs
output "python_lambda_arn" {
  description = "ARN of the Python Lambda function"
  value       = var.enable_python_lambda ? aws_lambda_function.python_lambda[0].arn : null
}

output "python_lambda_function_name" {
  description = "Name of the Python Lambda function"
  value       = var.enable_python_lambda ? aws_lambda_function.python_lambda[0].function_name : null
}

output "python_lambda_invoke_arn" {
  description = "Invoke ARN of the Python Lambda function"
  value       = var.enable_python_lambda ? aws_lambda_function.python_lambda[0].invoke_arn : null
}

# Go Lambda outputs
output "go_lambda_arn" {
  description = "ARN of the Go Lambda function"
  value       = var.enable_go_lambda ? aws_lambda_function.go_lambda[0].arn : null
}

output "go_lambda_function_name" {
  description = "Name of the Go Lambda function"
  value       = var.enable_go_lambda ? aws_lambda_function.go_lambda[0].function_name : null
}

output "go_lambda_invoke_arn" {
  description = "Invoke ARN of the Go Lambda function"
  value       = var.enable_go_lambda ? aws_lambda_function.go_lambda[0].invoke_arn : null
}

# Python GameLift Lambda outputs
output "python_gamelift_lambda_arn" {
  description = "ARN of the Python GameLift Lambda function"
  value       = var.enable_gamelift_lambda && var.enable_python_lambda ? aws_lambda_function.python_gamelift_lambda[0].arn : null
}

output "python_gamelift_lambda_function_name" {
  description = "Name of the Python GameLift Lambda function"
  value       = var.enable_gamelift_lambda && var.enable_python_lambda ? aws_lambda_function.python_gamelift_lambda[0].function_name : null
}

output "python_gamelift_lambda_invoke_arn" {
  description = "Invoke ARN of the Python GameLift Lambda function"
  value       = var.enable_gamelift_lambda && var.enable_python_lambda ? aws_lambda_function.python_gamelift_lambda[0].invoke_arn : null
}

# Go GameLift Lambda outputs
output "go_gamelift_lambda_arn" {
  description = "ARN of the Go GameLift Lambda function"
  value       = var.enable_gamelift_lambda && var.enable_go_lambda ? aws_lambda_function.go_gamelift_lambda[0].arn : null
}

output "go_gamelift_lambda_function_name" {
  description = "Name of the Go GameLift Lambda function"
  value       = var.enable_gamelift_lambda && var.enable_go_lambda ? aws_lambda_function.go_gamelift_lambda[0].function_name : null
}

output "go_gamelift_lambda_invoke_arn" {
  description = "Invoke ARN of the Go GameLift Lambda function"
  value       = var.enable_gamelift_lambda && var.enable_go_lambda ? aws_lambda_function.go_gamelift_lambda[0].invoke_arn : null
}

# API Gateway outputs
output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = var.enable_api_gateway ? aws_api_gateway_rest_api.api[0].id : null
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway"
  value       = var.enable_api_gateway ? aws_api_gateway_rest_api.api[0].arn : null
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = var.enable_api_gateway ? aws_api_gateway_rest_api.api[0].execution_arn : null
}

output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = var.enable_api_gateway ? "${aws_api_gateway_rest_api.api[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com" : null
}

output "api_gateway_stage_url" {
  description = "Stage URL of the API Gateway"
  value       = var.enable_api_gateway ? "${aws_api_gateway_rest_api.api[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage[0].stage_name}" : null
}

output "python_endpoint_url" {
  description = "Python Lambda endpoint URL"
  value       = var.enable_api_gateway && var.enable_python_lambda ? "${aws_api_gateway_rest_api.api[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage[0].stage_name}/" : null
}

output "go_endpoint_url" {
  description = "Go Lambda endpoint URL"
  value       = var.enable_api_gateway && var.enable_go_lambda ? "${aws_api_gateway_rest_api.api[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage[0].stage_name}/" : null
}

# Lambda execution role
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

