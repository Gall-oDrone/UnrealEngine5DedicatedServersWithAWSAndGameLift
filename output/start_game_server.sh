#!/bin/bash

# GameLift Anywhere Server Startup Script
# Generated on Tue Oct 21 14:17:39 CST 2025

# GameLift Configuration
export GAMELIFT_SDK_WEBSOCKET_URL="wss://us-east-1.api.amazongamelift.com"
export GAMELIFT_SDK_FLEET_ID="fleet-a739a48a-0709-46f1-9715-d1a9bd277a58"
export GAMELIFT_SDK_PROCESS_ID="Compute-0898c4db3aa69497b-m6i-large-20251021-141719-1761077859"
export GAMELIFT_SDK_HOST_ID="Compute-0898c4db3aa69497b-m6i-large-20251021-141719"
export GAMELIFT_SDK_AUTH_TOKEN="49f8f0b8-6858-4a08-944e-a68a1a6dca5a"
export GAMELIFT_COMPUTE_TYPE="ANYWHERE"
export GAMELIFT_REGION="us-east-1"

# Server Configuration
SERVER_PORT=7777
MAX_PLAYERS=10
LOG_LEVEL=verbose

echo "Starting GameLift Anywhere Server..."
echo "Fleet ID: fleet-a739a48a-0709-46f1-9715-d1a9bd277a58"
echo "Compute Name: Compute-0898c4db3aa69497b-m6i-large-20251021-141719"
echo "Server Port: "
echo "Max Players: "
echo "IP Address: 98.87.3.91"

# Start the server
./FPSTemplateServer \
    -port ${SERVER_PORT} \
    -maxplayers ${MAX_PLAYERS} \
    -log \
    -logFile /local/game/logs/server.log \
    -glAnywhere=true \
    -glAnywhereWebSocketUrl=${GAMELIFT_SDK_WEBSOCKET_URL} \
    -glAnywhereFleetId=${GAMELIFT_SDK_FLEET_ID} \
    -glAnywhereProcessId=${GAMELIFT_SDK_PROCESS_ID} \
    -glAnywhereHostId=${GAMELIFT_SDK_HOST_ID} \
    -glAnywhereAuthToken=${GAMELIFT_SDK_AUTH_TOKEN} \
    -glAnywhereAwsRegion=${GAMELIFT_REGION}

