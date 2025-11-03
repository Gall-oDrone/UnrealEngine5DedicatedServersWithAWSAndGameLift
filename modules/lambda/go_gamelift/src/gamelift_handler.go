package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/gamelift"
	"github.com/aws/aws-sdk-go-v2/service/gamelift/types"
)

// GameLiftLambdaHandler handles Lambda requests
type GameLiftLambdaHandler struct {
	gameliftClient *gamelift.Client
}

// GameLiftResponse represents the API response structure
type GameLiftResponse struct {
	Status      string                 `json:"status"`
	Message     string                 `json:"message,omitempty"`
	Operation   string                 `json:"operation,omitempty"`
	FleetCount  int                    `json:"fleet_count,omitempty"`
	Fleets      []string               `json:"fleets,omitempty"`
	Fleet       *FleetInfo             `json:"fleet,omitempty"`
	NextToken   *string                `json:"next_token,omitempty"`
	Error       *ErrorInfo             `json:"error,omitempty"`
	Timestamp   string                 `json:"timestamp,omitempty"`
}

// FleetInfo represents fleet information
type FleetInfo struct {
	FleetId          *string `json:"FleetId"`
	FleetArn         *string `json:"FleetArn"`
	FleetType        types.FleetType `json:"FleetType"`
	EC2InstanceType  types.EC2InstanceType `json:"EC2InstanceType"`
	BuildId          *string `json:"BuildId"`
	Status           types.FleetStatus `json:"Status"`
	Description      *string `json:"Description"`
	Name             *string `json:"Name"`
	CreationTime     *string `json:"CreationTime,omitempty"`
	TerminationTime  *string `json:"TerminationTime,omitempty"`
}

// ErrorInfo represents error information
type ErrorInfo struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// GameLiftRequest represents the incoming request
type GameLiftRequest struct {
	Action  string `json:"action"`
	FleetID string `json:"fleet_id"`
}

// Handler is the main Lambda handler function for GameLift operations
func (h *GameLiftLambdaHandler) Handler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	// Get request details
	httpMethod := request.HTTPMethod

	// Handle different HTTP methods
	switch httpMethod {
	case "GET":
		return h.handleListFleets(ctx, request)

	case "POST":
		// Parse request body
		var bodyData GameLiftRequest
		if err := json.Unmarshal([]byte(request.Body), &bodyData); err != nil {
			bodyData = GameLiftRequest{Action: "list_fleets"}
		}

		switch bodyData.Action {
		case "list_fleets":
			return h.handleListFleets(ctx, request)
		case "describe_fleet":
			if bodyData.FleetID == "" {
				return h.createErrorResponse(400, "Missing required parameter: fleet_id", "", request.RequestContext.RequestID), nil
			}
			return h.handleDescribeFleet(ctx, bodyData.FleetID, request)
		default:
			return h.createErrorResponse(400, fmt.Sprintf("Unknown action: %s", bodyData.Action), "", request.RequestContext.RequestID), nil
		}

	default:
		return h.createErrorResponse(405, fmt.Sprintf("Method %s not supported", httpMethod), "", request.RequestContext.RequestID), nil
	}
}

// handleListFleets handles ListFleets request
func (h *GameLiftLambdaHandler) handleListFleets(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	// Call GameLift ListFleets API
	result, err := h.gameliftClient.ListFleets(ctx, &gamelift.ListFleetsInput{})
	if err != nil {
		return h.createErrorResponse(500, "Failed to list fleets", err.Error(), request.RequestContext.RequestID), nil
	}

	// Prepare response
	responseBody := GameLiftResponse{
		Status:     "success",
		Operation:  "list_fleets",
		FleetCount: len(result.FleetIds),
		Fleets:     result.FleetIds,
		NextToken:  result.NextToken,
		Timestamp:  request.RequestContext.RequestID,
	}

	// Marshal response to JSON
	responseJSON, err := json.Marshal(responseBody)
	if err != nil {
		return h.createErrorResponse(500, "Failed to encode response", err.Error(), request.RequestContext.RequestID), nil
	}

	// Return API Gateway response
	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Headers: map[string]string{
			"Content-Type":                 "application/json",
			"Access-Control-Allow-Origin":  "*",
			"Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key",
			"Access-Control-Allow-Methods": "GET,POST,OPTIONS",
		},
		Body: string(responseJSON),
	}, nil
}

// handleDescribeFleet handles DescribeFleetAttributes request
func (h *GameLiftLambdaHandler) handleDescribeFleet(ctx context.Context, fleetID string, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	// Call GameLift DescribeFleetAttributes API
	result, err := h.gameliftClient.DescribeFleetAttributes(ctx, &gamelift.DescribeFleetAttributesInput{
		FleetIds: []string{fleetID},
	})
	if err != nil {
		return h.createErrorResponse(500, "Failed to describe fleet", err.Error(), request.RequestContext.RequestID), nil
	}

	if len(result.FleetAttributes) == 0 {
		return h.createErrorResponse(404, fmt.Sprintf("Fleet not found: %s", fleetID), "", request.RequestContext.RequestID), nil
	}

	// Convert fleet to FleetInfo
	fleetAttribute := result.FleetAttributes[0]
	fleetInfo := &FleetInfo{
		FleetId:         fleetAttribute.FleetId,
		FleetArn:        fleetAttribute.FleetArn,
		FleetType:       fleetAttribute.FleetType,
		EC2InstanceType: fleetAttribute.EC2InstanceType,
		BuildId:         fleetAttribute.BuildId,
		Status:          fleetAttribute.Status,
		Description:     fleetAttribute.Description,
		Name:            fleetAttribute.Name,
	}

	// Format timestamps if available
	if fleetAttribute.CreationTime != nil {
		ct := fleetAttribute.CreationTime.Format("2006-01-02T15:04:05Z07:00")
		fleetInfo.CreationTime = &ct
	}
	if fleetAttribute.TerminationTime != nil {
		tt := fleetAttribute.TerminationTime.Format("2006-01-02T15:04:05Z07:00")
		fleetInfo.TerminationTime = &tt
	}

	// Prepare response
	responseBody := GameLiftResponse{
		Status:     "success",
		Operation:  "describe_fleet",
		Fleet:      fleetInfo,
		Timestamp:  request.RequestContext.RequestID,
	}

	// Marshal response to JSON
	responseJSON, err := json.Marshal(responseBody)
	if err != nil {
		return h.createErrorResponse(500, "Failed to encode response", err.Error(), request.RequestContext.RequestID), nil
	}

	// Return API Gateway response
	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Headers: map[string]string{
			"Content-Type":                 "application/json",
			"Access-Control-Allow-Origin":  "*",
			"Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key",
			"Access-Control-Allow-Methods": "GET,POST,OPTIONS",
		},
		Body: string(responseJSON),
	}, nil
}

// createErrorResponse creates standardized error response
func (h *GameLiftLambdaHandler) createErrorResponse(statusCode int, message string, details string, timestamp string) events.APIGatewayProxyResponse {
	errorBody := GameLiftResponse{
		Status:    "error",
		Message:   message,
		Timestamp: timestamp,
	}

	if details != "" {
		errorBody.Error = &ErrorInfo{
			Code:    fmt.Sprintf("%d", statusCode),
			Message: details,
		}
	}

	responseJSON, _ := json.Marshal(errorBody)

	return events.APIGatewayProxyResponse{
		StatusCode: statusCode,
		Headers: map[string]string{
			"Content-Type":                 "application/json",
			"Access-Control-Allow-Origin":  "*",
			"Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key",
			"Access-Control-Allow-Methods": "GET,POST,OPTIONS",
		},
		Body: string(responseJSON),
	}
}

// initGameLiftClient initializes the GameLift client
func initGameLiftClient() (*gamelift.Client, error) {
	// Load AWS config
	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		return nil, fmt.Errorf("failed to load AWS config: %w", err)
	}

	// Create GameLift client
	client := gamelift.NewFromConfig(cfg)
	return client, nil
}

func main() {
	// Initialize GameLift client
	gameliftClient, err := initGameLiftClient()
	if err != nil {
		fmt.Printf("Error initializing GameLift client: %v\n", err)
		os.Exit(1)
	}

	// Create handler with GameLift client
	handler := &GameLiftLambdaHandler{
		gameliftClient: gameliftClient,
	}

	// Start Lambda handler
	lambda.Start(handler.Handler)
}

