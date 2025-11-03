package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

// Response represents the API response structure
type Response struct {
	Status      string      `json:"status"`
	Message     string      `json:"message,omitempty"`
	Environment string      `json:"environment"`
	Project     string      `json:"project"`
	Method      string      `json:"method,omitempty"`
	Path        string      `json:"path,omitempty"`
	Data        interface{} `json:"received_data,omitempty"`
	Timestamp   string      `json:"timestamp,omitempty"`
}

// Handler is the main Lambda handler function
func Handler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	// Get environment variables
	environment := getEnv("ENVIRONMENT", "unknown")
	project := getEnv("PROJECT", "unknown")

	// Get request details
	httpMethod := request.HTTPMethod
	path := request.Path

	// Handle different HTTP methods
	var responseBody Response
	var statusCode int

	switch httpMethod {
	case "GET":
		responseBody = Response{
			Status:      "success",
			Message:     "Go Lambda is running!",
			Environment: environment,
			Project:     project,
			Method:      httpMethod,
			Path:        path,
			Timestamp:   request.RequestContext.RequestID,
		}
		statusCode = 200

	case "POST":
		// Parse request body
		var bodyData map[string]interface{}
		if err := json.Unmarshal([]byte(request.Body), &bodyData); err != nil {
			bodyData = make(map[string]interface{})
		}

		responseBody = Response{
			Status:      "success",
			Message:     "POST request received",
			Environment: environment,
			Project:     project,
			Data:        bodyData,
			Timestamp:   request.RequestContext.RequestID,
		}
		statusCode = 200

	default:
		responseBody = Response{
			Status:  "error",
			Message: fmt.Sprintf("Method %s not supported", httpMethod),
		}
		statusCode = 405
	}

	// Marshal response to JSON
	responseJSON, err := json.Marshal(responseBody)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Body:       `{"status":"error","message":"Failed to encode response"}`,
			Headers: map[string]string{
				"Content-Type": "application/json",
			},
		}, nil
	}

	// Return API Gateway response
	return events.APIGatewayProxyResponse{
		StatusCode: statusCode,
		Headers: map[string]string{
			"Content-Type":                 "application/json",
			"Access-Control-Allow-Origin":  "*",
			"Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key",
			"Access-Control-Allow-Methods": "GET,POST,OPTIONS",
		},
		Body: string(responseJSON),
	}, nil
}

// HealthCheck is a health check endpoint for monitoring
func HealthCheck(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	environment := getEnv("ENVIRONMENT", "unknown")

	response := map[string]string{
		"status":      "healthy",
		"service":     "go-lambda",
		"environment": environment,
	}

	responseJSON, err := json.Marshal(response)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Body:       `{"status":"error"}`,
		}, nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: string(responseJSON),
	}, nil
}

// getEnv gets an environment variable or returns a default value
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func main() {
	// Start Lambda handler
	lambda.Start(Handler)
}

