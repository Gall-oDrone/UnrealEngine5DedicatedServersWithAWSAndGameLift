"""
Unit tests for Python Lambda handler
"""

import json
import os
from unittest.mock import Mock
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from handler import lambda_handler, health_check


class MockContext:
    """Mock Lambda context object"""
    def __init__(self):
        self.aws_request_id = "test-request-id-12345"
        self.function_name = "test-function"
        self.memory_limit_in_mb = 256
        self.remaining_time_in_millis = lambda: 30000


def test_get_request():
    """Test GET request handling"""
    os.environ['ENVIRONMENT'] = 'test'
    os.environ['PROJECT'] = 'test-project'
    
    event = {
        'httpMethod': 'GET',
        'path': '/test',
        'body': None
    }
    context = MockContext()
    
    response = lambda_handler(event, context)
    
    assert response['statusCode'] == 200
    body = json.loads(response['body'])
    assert body['status'] == 'success'
    assert body['environment'] == 'test'
    assert body['method'] == 'GET'


def test_post_request():
    """Test POST request handling"""
    os.environ['ENVIRONMENT'] = 'test'
    os.environ['PROJECT'] = 'test-project'
    
    event = {
        'httpMethod': 'POST',
        'path': '/test',
        'body': json.dumps({'test': 'data'})
    }
    context = MockContext()
    
    response = lambda_handler(event, context)
    
    assert response['statusCode'] == 200
    body = json.loads(response['body'])
    assert body['status'] == 'success'
    assert 'received_data' in body


def test_unsupported_method():
    """Test unsupported HTTP method"""
    os.environ['ENVIRONMENT'] = 'test'
    os.environ['PROJECT'] = 'test-project'
    
    event = {
        'httpMethod': 'DELETE',
        'path': '/test',
        'body': None
    }
    context = MockContext()
    
    response = lambda_handler(event, context)
    
    assert response['statusCode'] == 405
    body = json.loads(response['body'])
    assert body['status'] == 'error'


def test_health_check():
    """Test health check endpoint"""
    os.environ['ENVIRONMENT'] = 'production'
    
    event = {
        'httpMethod': 'GET',
        'path': '/health'
    }
    context = MockContext()
    
    response = health_check(event, context)
    
    assert response['statusCode'] == 200
    body = json.loads(response['body'])
    assert body['status'] == 'healthy'
    assert body['service'] == 'python-lambda'


if __name__ == '__main__':
    import pytest
    pytest.main([__file__, '-v'])

