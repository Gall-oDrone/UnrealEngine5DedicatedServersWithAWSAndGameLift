"""
AWS Lambda Handler for Python Function
This handler demonstrates a simple REST API endpoint for GameLift operations
"""

import json
import os
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function
    
    Args:
        event: API Gateway event containing request information
        context: Lambda context object
        
    Returns:
        API Gateway response dictionary
    """
    
    # Get environment variables
    environment = os.environ.get('ENVIRONMENT', 'unknown')
    project = os.environ.get('PROJECT', 'unknown')
    
    # Parse the event
    http_method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')
    
    # Handle different HTTP methods
    if http_method == 'GET':
        response_body = {
            'status': 'success',
            'message': f'Python Lambda is running!',
            'environment': environment,
            'project': project,
            'method': http_method,
            'path': path,
            'timestamp': context.aws_request_id if hasattr(context, 'aws_request_id') else 'N/A'
        }
        
        status_code = 200
        
    elif http_method == 'POST':
        # Handle POST request
        body = event.get('body', '{}')
        try:
            body_data = json.loads(body) if isinstance(body, str) else body
        except json.JSONDecodeError:
            body_data = {}
            
        response_body = {
            'status': 'success',
            'message': 'POST request received',
            'environment': environment,
            'project': project,
            'received_data': body_data,
            'timestamp': context.aws_request_id if hasattr(context, 'aws_request_id') else 'N/A'
        }
        
        status_code = 200
        
    else:
        response_body = {
            'status': 'error',
            'message': f'Method {http_method} not supported',
            'supported_methods': ['GET', 'POST']
        }
        status_code = 405
    
    # Return API Gateway response
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
        },
        'body': json.dumps(response_body, indent=2)
    }


def health_check(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Health check endpoint for monitoring
    
    Args:
        event: API Gateway event
        context: Lambda context
        
    Returns:
        Health check response
    """
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps({
            'status': 'healthy',
            'service': 'python-lambda',
            'environment': os.environ.get('ENVIRONMENT', 'unknown')
        })
    }

