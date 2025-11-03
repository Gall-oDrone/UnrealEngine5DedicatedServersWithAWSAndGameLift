package main

import (
	"context"
	"encoding/json"
	"os"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestHandler_GET(t *testing.T) {
	// Set environment variables
	os.Setenv("ENVIRONMENT", "test")
	os.Setenv("PROJECT", "test-project")
	defer os.Unsetenv("ENVIRONMENT")
	defer os.Unsetenv("PROJECT")

	// Create a test event
	event := events.APIGatewayProxyRequest{
		HTTPMethod: "GET",
		Path:       "/test",
		Body:       "",
		RequestContext: events.APIGatewayProxyRequestContext{
			RequestID: "test-request-id-12345",
		},
	}

	// Call the handler
	response, err := Handler(context.Background(), event)

	// Assertions
	if err != nil {
		t.Fatalf("Handler returned error: %v", err)
	}
	if response.StatusCode != 200 {
		t.Errorf("Expected status code 200, got %d", response.StatusCode)
	}

	var responseBody Response
	err = json.Unmarshal([]byte(response.Body), &responseBody)
	if err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}
	if responseBody.Status != "success" {
		t.Errorf("Expected status 'success', got '%s'", responseBody.Status)
	}
	if responseBody.Environment != "test" {
		t.Errorf("Expected environment 'test', got '%s'", responseBody.Environment)
	}
	if responseBody.Method != "GET" {
		t.Errorf("Expected method 'GET', got '%s'", responseBody.Method)
	}
}

func TestHandler_POST(t *testing.T) {
	// Set environment variables
	os.Setenv("ENVIRONMENT", "test")
	os.Setenv("PROJECT", "test-project")
	defer os.Unsetenv("ENVIRONMENT")
	defer os.Unsetenv("PROJECT")

	// Create a test event with body
	event := events.APIGatewayProxyRequest{
		HTTPMethod: "POST",
		Path:       "/test",
		Body:       `{"test": "data"}`,
		RequestContext: events.APIGatewayProxyRequestContext{
			RequestID: "test-request-id-12345",
		},
	}

	// Call the handler
	response, err := Handler(context.Background(), event)

	// Assertions
	if err != nil {
		t.Fatalf("Handler returned error: %v", err)
	}
	if response.StatusCode != 200 {
		t.Errorf("Expected status code 200, got %d", response.StatusCode)
	}

	var responseBody Response
	err = json.Unmarshal([]byte(response.Body), &responseBody)
	if err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}
	if responseBody.Status != "success" {
		t.Errorf("Expected status 'success', got '%s'", responseBody.Status)
	}
	if responseBody.Data == nil {
		t.Error("Expected data to be not nil")
	}
}

func TestHandler_UnsupportedMethod(t *testing.T) {
	// Set environment variables
	os.Setenv("ENVIRONMENT", "test")
	os.Setenv("PROJECT", "test-project")
	defer os.Unsetenv("ENVIRONMENT")
	defer os.Unsetenv("PROJECT")

	// Create a test event with unsupported method
	event := events.APIGatewayProxyRequest{
		HTTPMethod: "DELETE",
		Path:       "/test",
		Body:       "",
		RequestContext: events.APIGatewayProxyRequestContext{
			RequestID: "test-request-id-12345",
		},
	}

	// Call the handler
	response, err := Handler(context.Background(), event)

	// Assertions
	if err != nil {
		t.Fatalf("Handler returned error: %v", err)
	}
	if response.StatusCode != 405 {
		t.Errorf("Expected status code 405, got %d", response.StatusCode)
	}

	var responseBody Response
	err = json.Unmarshal([]byte(response.Body), &responseBody)
	if err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}
	if responseBody.Status != "error" {
		t.Errorf("Expected status 'error', got '%s'", responseBody.Status)
	}
}

func TestHealthCheck(t *testing.T) {
	// Set environment variable
	os.Setenv("ENVIRONMENT", "production")
	defer os.Unsetenv("ENVIRONMENT")

	// Create a test event
	event := events.APIGatewayProxyRequest{
		HTTPMethod: "GET",
		Path:       "/health",
		RequestContext: events.APIGatewayProxyRequestContext{
			RequestID: "test-request-id-12345",
		},
	}

	// Call the health check handler
	response, err := HealthCheck(context.Background(), event)

	// Assertions
	if err != nil {
		t.Fatalf("HealthCheck returned error: %v", err)
	}
	if response.StatusCode != 200 {
		t.Errorf("Expected status code 200, got %d", response.StatusCode)
	}

	var responseBody map[string]string
	err = json.Unmarshal([]byte(response.Body), &responseBody)
	if err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}
	if responseBody["status"] != "healthy" {
		t.Errorf("Expected status 'healthy', got '%s'", responseBody["status"])
	}
	if responseBody["service"] != "go-lambda" {
		t.Errorf("Expected service 'go-lambda', got '%s'", responseBody["service"])
	}
}

