"""
AWS Lambda Handler for GameLift Operations
This handler implements GameLift ListFleets API using boto3
"""

import json
import os
from typing import Dict, Any, Optional
import boto3
from botocore.exceptions import ClientError


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for GameLift operations
    
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
    
    # Initialize GameLift client
    try:
        gamelift_client = boto3.client('gamelift')
        aws_region = os.environ.get('AWS_REGION', 'us-east-1')
    except Exception as e:
        return create_error_response(
            500,
            "Failed to initialize GameLift client",
            str(e),
            context
        )
    
    # Handle different HTTP methods
    if http_method == 'GET':
        # List GameLift fleets
        return handle_list_fleets(gamelift_client, context)
        
    elif http_method == 'POST':
        # Handle other GameLift operations based on body
        body = event.get('body', '{}')
        try:
            body_data = json.loads(body) if isinstance(body, str) else body
        except json.JSONDecodeError:
            body_data = {}
            
        action = body_data.get('action', 'list_fleets')
        
        if action == 'list_fleets':
            return handle_list_fleets(gamelift_client, context)
        elif action == 'describe_fleet':
            fleet_id = body_data.get('fleet_id')
            if not fleet_id:
                return create_error_response(
                    400,
                    "Missing required parameter: fleet_id",
                    None,
                    context
                )
            return handle_describe_fleet(gamelift_client, fleet_id, context)
        else:
            return create_error_response(
                400,
                f"Unknown action: {action}",
                None,
                context
            )
    else:
        return create_error_response(
            405,
            f'Method {http_method} not supported',
            None,
            context
        )


def handle_list_fleets(gamelift_client: boto3.client, context: Any) -> Dict[str, Any]:
    """
    Handle ListFleets request
    
    Args:
        gamelift_client: Boto3 GameLift client
        context: Lambda context
        
    Returns:
        API Gateway response with fleet list
    """
    try:
        # Call GameLift ListFleets API
        response = gamelift_client.list_fleets()
        
        fleet_ids = response.get('FleetIds', [])
        next_token = response.get('NextToken', None)
        
        # Prepare response
        response_body = {
            'status': 'success',
            'operation': 'list_fleets',
            'fleet_count': len(fleet_ids),
            'fleets': fleet_ids,
            'next_token': next_token,
            'timestamp': context.aws_request_id if hasattr(context, 'aws_request_id') else 'N/A'
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
            },
            'body': json.dumps(response_body, indent=2, default=str)
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        
        return create_error_response(
            500,
            f'GameLift API error: {error_code}',
            error_message,
            context
        )
    except Exception as e:
        return create_error_response(
            500,
            'Unexpected error listing fleets',
            str(e),
            context
        )


def handle_describe_fleet(gamelift_client: boto3.client, fleet_id: str, context: Any) -> Dict[str, Any]:
    """
    Handle DescribeFleet request
    
    Args:
        gamelift_client: Boto3 GameLift client
        fleet_id: Fleet ID to describe
        context: Lambda context
        
    Returns:
        API Gateway response with fleet details
    """
    try:
        # Call GameLift DescribeFleetAttributes API
        response = gamelift_client.describe_fleet_attributes(
            FleetIds=[fleet_id]
        )
        
        fleet_attributes = response.get('FleetAttributes', [])
        
        if not fleet_attributes:
            return create_error_response(
                404,
                f'Fleet not found: {fleet_id}',
                None,
                context
            )
        
        # Convert datetime objects to strings for JSON serialization
        fleet = fleet_attributes[0]
        
        response_body = {
            'status': 'success',
            'operation': 'describe_fleet',
            'fleet': convert_fleet_to_dict(fleet),
            'timestamp': context.aws_request_id if hasattr(context, 'aws_request_id') else 'N/A'
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
            },
            'body': json.dumps(response_body, indent=2, default=str)
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        
        return create_error_response(
            500,
            f'GameLift API error: {error_code}',
            error_message,
            context
        )
    except Exception as e:
        return create_error_response(
            500,
            'Unexpected error describing fleet',
            str(e),
            context
        )


def convert_fleet_to_dict(fleet: Any) -> Dict[str, Any]:
    """
    Convert GameLift fleet object to dictionary for JSON serialization
    
    Args:
        fleet: GameLift fleet object
        
    Returns:
        Dictionary representation
    """
    return {
        'FleetId': fleet.get('FleetId'),
        'FleetArn': fleet.get('FleetArn'),
        'FleetType': fleet.get('FleetType'),
        'EC2InstanceType': fleet.get('EC2InstanceType'),
        'BuildId': fleet.get('BuildId'),
        'Status': fleet.get('Status'),
        'Description': fleet.get('Description'),
        'Name': fleet.get('Name'),
        'CreationTime': fleet.get('CreationTime').isoformat() if fleet.get('CreationTime') else None,
        'TerminationTime': fleet.get('TerminationTime').isoformat() if fleet.get('TerminationTime') else None,
    }


def create_error_response(
    status_code: int,
    message: str,
    details: Optional[str],
    context: Any
) -> Dict[str, Any]:
    """
    Create standardized error response
    
    Args:
        status_code: HTTP status code
        message: Error message
        details: Optional error details
        context: Lambda context
        
    Returns:
        API Gateway error response
    """
    error_body = {
        'status': 'error',
        'message': message,
        'timestamp': context.aws_request_id if hasattr(context, 'aws_request_id') else 'N/A'
    }
    
    if details:
        error_body['details'] = details
    
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
        },
        'body': json.dumps(error_body, indent=2)
    }

