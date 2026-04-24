#!/bin/bash

# Unreal Engine 5 IDE CloudFormation Stack Deployment Script
# This script deploys the CloudFormation stack for the Unreal Engine 5 IDE

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

# Function to validate CloudFormation template
validate_template() {
    local template_file="$1"
    print_status "Validating CloudFormation template..."
    
    if ! aws cloudformation validate-template --template-body file://"$template_file" &> /dev/null; then
        print_error "CloudFormation template validation failed"
        exit 1
    fi
    print_success "CloudFormation template is valid"
}

# Function to check if stack already exists and can be updated
stack_exists() {
    local stack_name="$1"
    local status
    status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].StackStatus' --output text 2>/dev/null)
    if [ $? -eq 0 ]; then
        # Check if stack is in a state that allows updates
        case $status in
            "CREATE_COMPLETE"|"UPDATE_COMPLETE"|"UPDATE_ROLLBACK_COMPLETE")
                return 0  # Stack exists and can be updated
                ;;
            "ROLLBACK_COMPLETE"|"CREATE_FAILED"|"UPDATE_FAILED")
                return 1  # Stack exists but cannot be updated
                ;;
            *)
                return 0  # Other states, assume it can be updated
                ;;
        esac
    else
        return 1  # Stack doesn't exist
    fi
}

# Function to deploy the stack
deploy_stack() {
    local stack_name="$1"
    local template_file="$2"
    shift 2
    local parameters=("$@")
    
    print_status "Deploying CloudFormation stack: $stack_name"
    
    if stack_exists "$stack_name"; then
        print_warning "Stack '$stack_name' already exists. Updating..."
        aws cloudformation update-stack \
            --stack-name "$stack_name" \
            --template-body file://"$template_file" \
            --parameters "${parameters[@]}" \
            --capabilities CAPABILITY_NAMED_IAM
    else
        print_status "Creating new stack: $stack_name"
        aws cloudformation create-stack \
            --stack-name "$stack_name" \
            --template-body file://"$template_file" \
            --parameters "${parameters[@]}" \
            --capabilities CAPABILITY_NAMED_IAM \
            --on-failure ROLLBACK
    fi
    
    print_status "Waiting for stack operation to complete..."
    
    # Set timeout for stack operations
    TIMEOUT_SECONDS=$((TIMEOUT_MINUTES * 60))
    START_TIME=$(date +%s)
    
    # Function to check if timeout has been reached
    check_timeout() {
        local current_time=$(date +%s)
        local elapsed=$((current_time - START_TIME))
        local remaining=$((TIMEOUT_SECONDS - elapsed))
        
        if [ $elapsed -ge $TIMEOUT_SECONDS ]; then
            print_error "Stack operation timed out after $TIMEOUT_MINUTES minutes"
            print_status "You can check the stack status manually with: aws cloudformation describe-stacks --stack-name $stack_name"
            exit 1
        fi
        
        # Show progress every 2 minutes
        if [ $((elapsed % 120)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            print_status "Elapsed: $((elapsed / 60)) minutes, Remaining: $((remaining / 60)) minutes"
        fi
    }
    
    # Wait for stack operation with timeout
    while true; do
        check_timeout
        
        # Check if stack exists and get its status
        if ! aws cloudformation describe-stacks --stack-name "$stack_name" &>/dev/null; then
            print_error "Stack '$stack_name' not found or failed to create"
            exit 1
        fi
        
        # Get stack status
        STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].StackStatus' --output text 2>/dev/null)
        
        case $STACK_STATUS in
            "CREATE_COMPLETE"|"UPDATE_COMPLETE")
                print_success "Stack operation completed successfully!"
                break
                ;;
            "CREATE_FAILED"|"UPDATE_FAILED"|"ROLLBACK_COMPLETE"|"UPDATE_ROLLBACK_COMPLETE")
                print_error "Stack operation failed with status: $STACK_STATUS"
                print_status "Check the CloudFormation console for detailed error information"
                show_recent_events "$stack_name"
                exit 1
                ;;
            "CREATE_IN_PROGRESS"|"UPDATE_IN_PROGRESS"|"UPDATE_ROLLBACK_IN_PROGRESS"|"ROLLBACK_IN_PROGRESS")
                print_status "Stack operation in progress... (Status: $STACK_STATUS)"
                sleep 30
                ;;
            *)
                print_warning "Unknown stack status: $STACK_STATUS"
                sleep 30
                ;;
        esac
    done
    
    print_success "Stack deployment completed successfully!"
}

# Function to display stack outputs
show_outputs() {
    local stack_name="$1"
    print_status "Retrieving stack outputs..."
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query 'Stacks[0].Outputs' \
        --output table
}

# Function to show recent stack events
show_recent_events() {
    local stack_name="$1"
    print_status "Retrieving recent stack events..."
    
    aws cloudformation describe-stack-events \
        --stack-name "$stack_name" \
        --query 'StackEvents[0:10]' \
        --output table 2>/dev/null || print_warning "Could not retrieve stack events"
}

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --stack-name NAME     CloudFormation stack name (default: unreal-engine-5-ide)"
    echo "  -t, --template FILE       CloudFormation template file (default: unreal-engine-5-ide-cfn.yaml)"
    echo "  -r, --region REGION       AWS region (default: us-east-1)"
    echo "  -o, --owner OWNER         GitHub repository owner (default: Gall-oDrone)"
    echo "  -n, --repo-name NAME      GitHub repository name (default: UnrealEngine5DedicatedServersWithAWSAndGameLift)"
    echo "  -b, --branch BRANCH       Git branch/ref (default: main)"
    echo "  -v, --volume-size SIZE    Instance volume size in GB (default: 30)"
    echo "  -e, --environment ENV     Environment for testing (default: empty)"
    echo "  -t, --timeout MINUTES     Timeout for stack operations in minutes (default: 30)"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --stack-name my-unreal-engine-ide --region us-west-2"
    echo "  $0 --owner myusername --repo-name my-repo --branch develop"
}

# Main script
main() {
    # Default values
    STACK_NAME="unreal-engine-5-ide"
    TEMPLATE_FILE="unreal-engine-5-ide-cfn.yaml"
    AWS_REGION="us-east-1"
    REPO_OWNER="Gall-oDrone"
    REPO_NAME="UnrealEngine5DedicatedServersWithAWSAndGameLift"
    REPO_REF="main"
    VOLUME_SIZE="30"
    ENVIRONMENT=""
    TIMEOUT_MINUTES="30"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--stack-name)
                STACK_NAME="$2"
                shift 2
                ;;
            -t|--template)
                TEMPLATE_FILE="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -o|--owner)
                REPO_OWNER="$2"
                shift 2
                ;;
            -n|--repo-name)
                REPO_NAME="$2"
                shift 2
                ;;
            -b|--branch)
                REPO_REF="$2"
                shift 2
                ;;
            -v|--volume-size)
                VOLUME_SIZE="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT_MINUTES="$2"
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
    
    # Set AWS region
    export AWS_DEFAULT_REGION="$AWS_REGION"
    
    print_status "Starting Unreal Engine 5 IDE stack deployment"
    print_status "Stack Name: $STACK_NAME"
    print_status "Template File: $TEMPLATE_FILE"
    print_status "AWS Region: $AWS_REGION"
    print_status "Repository: $REPO_OWNER/$REPO_NAME@$REPO_REF"
    print_status "Timeout: $TIMEOUT_MINUTES minutes"
    
    # Check prerequisites
    check_aws_cli
    check_aws_credentials
    
    # Check if template file exists
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        print_error "Template file '$TEMPLATE_FILE' not found"
        exit 1
    fi
    
    # Validate template
    validate_template "$TEMPLATE_FILE"
    
    # Prepare parameters
    PARAMETERS=(
        "ParameterKey=RepositoryOwner,ParameterValue=$REPO_OWNER"
        "ParameterKey=RepositoryName,ParameterValue=$REPO_NAME"
        "ParameterKey=RepositoryRef,ParameterValue=$REPO_REF"
        "ParameterKey=InstanceVolumeSize,ParameterValue=$VOLUME_SIZE"
        "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
        "ParameterKey=EksClusterId,ParameterValue=$STACK_NAME"
    )
    
    # Deploy stack
    deploy_stack "$STACK_NAME" "$TEMPLATE_FILE" "${PARAMETERS[@]}"
    
    # Show outputs
    show_outputs "$STACK_NAME"
    
    print_success "Deployment completed successfully!"
    print_status "You can now access your Unreal Engine 5 IDE using the URLs above"
}

# Run main function
main "$@"
