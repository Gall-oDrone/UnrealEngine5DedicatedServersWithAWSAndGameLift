output "api_endpoint_url" {
  description = "Value for UFrontendGameLiftSettings.ApiEndpointUrl / -GameLiftEndpoint= / GAMELIFT_ENDPOINT_URL."
  value       = "${aws_apigatewayv2_api.proxy.api_endpoint}/"
}

output "lambda_function_name" {
  value = aws_lambda_function.proxy.function_name
}

output "lambda_log_group" {
  value = aws_cloudwatch_log_group.lambda.name
}
