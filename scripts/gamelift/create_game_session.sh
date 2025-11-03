#!/bin/bash

# GameLift GameSession Creator Script
# This script creates a new GameSession for Amazon GameLift

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        print_status "Installation guide: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
        exit 1
    fi
    print_success "AWS CLI is installed"
}

# Function to check if AWS credentials are configured
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    print_success "AWS credentials are configured"
}

# Function to check if jq is installed
check_jq() {
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed. Installing jq for JSON parsing..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            if command -v brew &> /dev/null; then
                brew install jq
            else
                print_error "Please install jq manually: https://stedolan.github.io/jq/download/"
                exit 1
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            # Linux
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y jq
            elif command -v yum &> /dev/null; then
                sudo yum install -y jq
            else
                print_error "Please install jq manually: https://stedolan.github.io/jq/download/"
                exit 1
            fi
        else
            print_error "Please install jq manually: https://stedolan.github.io/jq/download/"
            exit 1
        fi
    fi
    print_success "jq is available"
}

# Function to validate fleet ID
validate_fleet_id() {
    local fleet_id="$1"
    print_status "Validating fleet ID: $fleet_id"
    
    if ! aws gamelift describe-fleet-attributes --fleet-ids "$fleet_id" &> /dev/null; then
        print_error "Fleet ID '$fleet_id' not found or not accessible"
        print_status "Available fleets:"
        aws gamelift list-fleets --query 'FleetIds[]' --output table 2>/dev/null || print_warning "Could not list fleets"
        exit 1
    fi
    print_success "Fleet ID is valid"
}

# Function to create game session
create_game_session() {
    local fleet_id="$1"
    local alias_id="$2"
    local max_players="$3"
    local region="$4"
    local player_data="$5"
    local game_properties="$6"
    
    print_status "Creating game session for fleet: $fleet_id" >&2
    print_status "Max players: $max_players" >&2
    
    # Build the AWS CLI command
    local cmd="aws gamelift create-game-session"
    cmd="$cmd --fleet-id $fleet_id"
    cmd="$cmd --maximum-player-session-count $max_players"
    
    # Add alias ID if provided
    if [[ -n "$alias_id" ]]; then
        cmd="$cmd --alias-id $alias_id"
        print_status "Using alias ID: $alias_id" >&2
    fi
    
    # Add player data if provided
    if [[ -n "$player_data" ]]; then
        cmd="$cmd --creator-id $player_data"
        print_status "Using creator ID: $player_data" >&2
    fi
    
    # Add game properties if provided
    if [[ -n "$game_properties" ]]; then
        cmd="$cmd --game-properties $game_properties"
        print_status "Using game properties: $game_properties" >&2
    fi
    
    cmd="$cmd --region $region"
    cmd="$cmd --output json"
    
    # Create the game session
    local response
    if ! response=$(eval "$cmd" 2>&1); then
        print_error "Failed to create game session: $response" >&2
        exit 1
    fi
    
    # Extract the game session ID from the response
    local game_session_id
    if ! game_session_id=$(echo "$response" | jq -r '.GameSession.GameSessionId'); then
        print_error "Failed to parse game session ID from response" >&2
        print_error "Response: $response" >&2
        exit 1
    fi
    
    if [[ "$game_session_id" == "null" || -z "$game_session_id" ]]; then
        print_error "No game session ID found in response" >&2
        print_error "Response: $response" >&2
        exit 1
    fi
    
    print_success "Game session created successfully" >&2
    print_status "Game Session ID: $game_session_id" >&2
    
    # Return the raw JSON response for further processing
    echo "$response"
}

# Function to get game session details
get_game_session_details() {
    local game_session_id="$1"
    local region="$2"
    
    print_status "Getting game session details for: $game_session_id" >&2
    
    local response
    if ! response=$(aws gamelift describe-game-session-details \
        --game-session-id "$game_session_id" \
        --region "$region" \
        --output json 2>&1); then
        print_error "Failed to get game session details: $response" >&2
        exit 1
    fi
    
    echo "$response"
}

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --fleet-id ID        GameLift fleet ID (required)"
    echo "  -a, --alias-id ID        GameLift alias ID (optional)"
    echo "  -m, --max-players NUM    Maximum number of players (default: 10)"
    echo "  -r, --region REGION      AWS region (default: us-east-1)"
    echo "  -p, --player-data DATA   Player data/creator ID (optional)"
    echo "  -g, --game-properties    Game properties as JSON string (optional)"
    echo "  -o, --output FORMAT      Output format: text, json (default: text)"
    echo "  -s, --save FILE          Save game session info to file"
    echo "  -d, --details            Get detailed game session information"
    echo "  --cleanup TYPE           Cleanup files and environment (temp, file, env, all)"
    echo "  --cleanup-file FILE      Specify file path for cleanup"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --fleet-id fleet-12345678-1234-1234-1234-123456789012"
    echo "  $0 -f fleet-12345678-1234-1234-1234-123456789012 -m 20"
    echo "  $0 -f fleet-12345678-1234-1234-1234-123456789012 -a alias-12345678-1234-1234-1234-123456789012"
    echo "  $0 -f fleet-12345678-1234-1234-1234-123456789012 -p Player123 -g '[{\"Key\":\"GameMode\",\"Value\":\"Deathmatch\"}]'"
    echo "  $0 -f fleet-12345678-1234-1234-1234-123456789012 -o json -s game_session.json"
    echo "  $0 -f fleet-12345678-1234-1234-1234-123456789012 -d"
    echo "  $0 --cleanup temp"
    echo "  $0 --cleanup file --cleanup-file game_session.json"
    echo "  $0 --cleanup all"
    echo ""
    echo "Environment Variables:"
    echo "  GAMELIFT_FLEET_ID        Default fleet ID"
    echo "  GAMELIFT_ALIAS_ID        Default alias ID"
    echo "  GAMELIFT_MAX_PLAYERS     Default maximum players"
    echo "  AWS_DEFAULT_REGION       Default AWS region"
}

# Function to save game session info to file
save_game_session_info() {
    local game_session_info="$1"
    local file_path="$2"
    
    print_status "Saving game session info to file: $file_path"
    
    # Create directory if it doesn't exist
    local dir_path=$(dirname "$file_path")
    if [[ ! -d "$dir_path" ]]; then
        mkdir -p "$dir_path"
    fi
    
    # Save game session info
    echo "$game_session_info" > "$file_path"
    chmod 644 "$file_path"
    
    print_success "Game session info saved to $file_path"
}

# Function to cleanup temporary files, environment variables, and output files
cleanup_game_session_files() {
    local cleanup_type="$1"
    local file_path="$2"
    
    print_status "Starting cleanup process..."
    
    case $cleanup_type in
        "temp")
            # Clean up temporary files in /tmp
            local temp_files=($(find /tmp -name "*gamelift*" -type f 2>/dev/null || true))
            if [[ ${#temp_files[@]} -gt 0 ]]; then
                for file in "${temp_files[@]}"; do
                    rm -f "$file"
                    print_success "Removed temporary file: $file"
                done
            else
                print_warning "No temporary GameLift files found in /tmp"
            fi
            ;;
        "file")
            # Remove specific file
            if [[ -n "$file_path" ]]; then
                if [[ -f "$file_path" ]]; then
                    rm -f "$file_path"
                    print_success "Removed game session info file: $file_path"
                else
                    print_warning "Game session info file not found: $file_path"
                fi
            else
                print_error "File path required for file cleanup"
                return 1
            fi
            ;;
        "env")
            # Clear GameLift-related environment variables
            local env_vars=(
                "GAMELIFT_GAME_SESSION_ID"
                "GAMELIFT_FLEET_ID"
                "GAMELIFT_ALIAS_ID"
                "GAMELIFT_MAX_PLAYERS"
                "GAMELIFT_REGION"
            )
            
            local cleared_count=0
            for var in "${env_vars[@]}"; do
                if [[ -n "${!var}" ]]; then
                    unset "$var"
                    print_success "Cleared environment variable: $var"
                    ((cleared_count++))
                fi
            done
            
            if [[ $cleared_count -eq 0 ]]; then
                print_warning "No GameLift environment variables were set"
            fi
            ;;
        "all")
            # Clean up everything
            print_status "Performing comprehensive cleanup..."
            
            # Clear environment variables
            cleanup_game_session_files "env"
            
            # Remove common output file locations
            local common_paths=(
                "./game_session.json"
                "./gamelift_game_session.json"
                "/tmp/game_session.json"
                "/tmp/gamelift_game_session.json"
                "$HOME/.gamelift_game_session"
            )
            
            local removed_count=0
            for path in "${common_paths[@]}"; do
                if [[ -f "$path" ]]; then
                    rm -f "$path"
                    print_success "Removed game session info file: $path"
                    ((removed_count++))
                fi
            done
            
            # Clean up temporary files
            cleanup_game_session_files "temp"
            
            if [[ $removed_count -eq 0 ]]; then
                print_warning "No common game session info files found to remove"
            fi
            ;;
        *)
            print_error "Invalid cleanup type: $cleanup_type"
            print_status "Valid cleanup types: temp, file, env, all"
            return 1
            ;;
    esac
    
    print_success "Cleanup completed!"
}

# Main script
main() {
    # Default values
    FLEET_ID=""
    ALIAS_ID=""
    MAX_PLAYERS="${GAMELIFT_MAX_PLAYERS:-10}"
    AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    PLAYER_DATA=""
    GAME_PROPERTIES=""
    OUTPUT_FORMAT="text"
    SAVE_FILE=""
    GET_DETAILS="false"
    CLEANUP_TYPE=""
    CLEANUP_FILE=""
    
    # Check for environment variables
    if [[ -n "$GAMELIFT_FLEET_ID" ]]; then
        FLEET_ID="$GAMELIFT_FLEET_ID"
    fi
    if [[ -n "$GAMELIFT_ALIAS_ID" ]]; then
        ALIAS_ID="$GAMELIFT_ALIAS_ID"
    fi
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--fleet-id)
                FLEET_ID="$2"
                shift 2
                ;;
            -a|--alias-id)
                ALIAS_ID="$2"
                shift 2
                ;;
            -m|--max-players)
                MAX_PLAYERS="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--player-data)
                PLAYER_DATA="$2"
                shift 2
                ;;
            -g|--game-properties)
                GAME_PROPERTIES="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -s|--save)
                SAVE_FILE="$2"
                shift 2
                ;;
            -d|--details)
                GET_DETAILS="true"
                shift
                ;;
            --cleanup)
                CLEANUP_TYPE="$2"
                shift 2
                ;;
            --cleanup-file)
                CLEANUP_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Handle cleanup mode
    if [[ -n "$CLEANUP_TYPE" ]]; then
        print_status "GameLift GameSession Cleanup"
        cleanup_game_session_files "$CLEANUP_TYPE" "$CLEANUP_FILE"
        exit 0
    fi
    
    # Validate required parameters
    if [[ -z "$FLEET_ID" ]]; then
        print_error "Fleet ID is required. Use -f or --fleet-id option."
        show_usage
        exit 1
    fi
    
    # Validate max players
    if ! [[ "$MAX_PLAYERS" =~ ^[0-9]+$ ]] || [[ "$MAX_PLAYERS" -lt 1 ]] || [[ "$MAX_PLAYERS" -gt 200 ]]; then
        print_error "Max players must be a number between 1 and 200"
        exit 1
    fi
    
    # Validate output format
    if [[ "$OUTPUT_FORMAT" != "text" && "$OUTPUT_FORMAT" != "json" ]]; then
        print_error "Invalid output format: $OUTPUT_FORMAT. Must be one of: text, json"
        exit 1
    fi
    
    # Set AWS region
    export AWS_DEFAULT_REGION="$AWS_REGION"
    
    print_status "GameLift GameSession Creator"
    print_status "Fleet ID: $FLEET_ID"
    if [[ -n "$ALIAS_ID" ]]; then
        print_status "Alias ID: $ALIAS_ID"
    fi
    print_status "Max Players: $MAX_PLAYERS"
    print_status "AWS Region: $AWS_REGION"
    print_status "Output Format: $OUTPUT_FORMAT"
    
    # Check prerequisites
    check_aws_cli
    check_aws_credentials
    check_jq
    
    # Validate fleet ID
    validate_fleet_id "$FLEET_ID"
    
    # Create game session
    GAME_SESSION_INFO=$(create_game_session "$FLEET_ID" "$ALIAS_ID" "$MAX_PLAYERS" "$AWS_REGION" "$PLAYER_DATA" "$GAME_PROPERTIES" 2>/dev/null)
    
    # Extract game session ID
    GAME_SESSION_ID=$(echo "$GAME_SESSION_INFO" | jq -r '.GameSession.GameSessionId')
    
    # Get detailed information if requested
    if [[ "$GET_DETAILS" == "true" ]]; then
        print_status "Getting detailed game session information..."
        DETAILED_INFO=$(get_game_session_details "$GAME_SESSION_ID" "$AWS_REGION")
        GAME_SESSION_INFO="$DETAILED_INFO"
    fi
    
    # Handle output format
    case $OUTPUT_FORMAT in
        "text")
            echo ""
            print_success "GameSession Creation Summary:"
            echo "  Game Session ID: $GAME_SESSION_ID"
            echo "  Fleet ID: $FLEET_ID"
            if [[ -n "$ALIAS_ID" ]]; then
                echo "  Alias ID: $ALIAS_ID"
            fi
            echo "  Max Players: $MAX_PLAYERS"
            echo "  Status: $(echo "$GAME_SESSION_INFO" | jq -r '.GameSession.Status')"
            echo "  Current Players: $(echo "$GAME_SESSION_INFO" | jq -r '.GameSession.CurrentPlayerSessionCount')"
            echo "  IP Address: $(echo "$GAME_SESSION_INFO" | jq -r '.GameSession.IpAddress // "N/A"')"
            echo "  Port: $(echo "$GAME_SESSION_INFO" | jq -r '.GameSession.Port // "N/A"')"
            echo ""
            print_status "Next steps:"
            echo "  1. Players can now join this game session"
            echo "  2. Use the Game Session ID for player session creation"
            echo "  3. Monitor the session status in the GameLift console"
            ;;
        "json")
            echo "$GAME_SESSION_INFO"
            ;;
    esac
    
    # Save to file if requested
    if [[ -n "$SAVE_FILE" ]]; then
        save_game_session_info "$GAME_SESSION_INFO" "$SAVE_FILE"
    fi
    
    # Export environment variable
    export GAMELIFT_GAME_SESSION_ID="$GAME_SESSION_ID"
    
    print_success "Game session creation completed!"
    print_warning "Note: Game sessions have a limited lifetime and will be automatically cleaned up when inactive."
}

# Run main function
main "$@"
