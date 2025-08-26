#!/bin/bash

# AWS DCV (Desktop and Cloud Visualization) Setup Script for Windows EC2
# This script follows the AWS DCV documentation methodology for Windows Server instances
# Reference: https://docs.aws.amazon.com/pdfs/dcv/latest/adminguide/dcv-ag.pdf#setting-up-installing

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
LOG_FILE="$SCRIPT_DIR/dcv_setup.log"
DCV_VERSION="2023.2-15773"
DCV_DOWNLOAD_URL="https://d1uj6qtbmh3dt5.cloudfront.net/2023.2/Servers/nice-dcv-server-${DCV_VERSION}.x86_64.msi"
DCV_CLIENT_URL="https://d1uj6qtbmh3dt5.cloudfront.net/2023.2/Clients/nice-dcv-viewer-${DCV_VERSION}.x86_64.msi"
DCV_AGENT_URL="https://d1uj6qtbmh3dt5.cloudfront.net/2023.2/Agents/nice-dcv-gl-agent-${DCV_VERSION}.x86_64.msi"

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to check if running on Windows
check_windows() {
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        print_status $GREEN "Detected Windows environment"
        return 0
    else
        print_status $RED "This script is designed for Windows EC2 instances"
        print_status $RED "Current OS: $OSTYPE"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status $BLUE "Checking prerequisites..."
    
    # Check if running as administrator
    if ! net session >/dev/null 2>&1; then
        print_status $RED "This script must be run as Administrator"
        print_status $YELLOW "Please right-click and 'Run as Administrator'"
        exit 1
    fi
    
    # Check Windows version
    local windows_version=$(wmic os get Caption /value | grep "Caption=" | cut -d'=' -f2)
    print_status $GREEN "Windows Version: $windows_version"
    
    # Check available disk space (need at least 2GB)
    local free_space=$(wmic logicaldisk where "DeviceID='C:'" get FreeSpace /value | grep "FreeSpace=" | cut -d'=' -f2)
    local free_space_gb=$((free_space / 1024 / 1024 / 1024))
    
    if [ "$free_space_gb" -lt 2 ]; then
        print_status $RED "Insufficient disk space. Need at least 2GB, available: ${free_space_gb}GB"
        exit 1
    fi
    
    print_status $GREEN "Available disk space: ${free_space_gb}GB"
    log_message "INFO" "Prerequisites check passed"
}

# Function to download DCV components
download_dcv_components() {
    print_status $BLUE "Downloading DCV components..."
    
    local download_dir="$SCRIPT_DIR/downloads"
    mkdir -p "$download_dir"
    
    # Download DCV Server
    print_status $YELLOW "Downloading DCV Server..."
    if ! curl -L -o "$download_dir/dcv-server.msi" "$DCV_DOWNLOAD_URL"; then
        print_status $RED "Failed to download DCV Server"
        exit 1
    fi
    
    # Download DCV Client (for testing)
    print_status $YELLOW "Downloading DCV Client..."
    if ! curl -L -o "$download_dir/dcv-client.msi" "$DCV_CLIENT_URL"; then
        print_status $RED "Failed to download DCV Client"
        exit 1
    fi
    
    # Download DCV GL Agent (for hardware acceleration)
    print_status $YELLOW "Downloading DCV GL Agent..."
    if ! curl -L -o "$download_dir/dcv-gl-agent.msi" "$DCV_AGENT_URL"; then
        print_status $RED "Failed to download DCV GL Agent"
        exit 1
    fi
    
    print_status $GREEN "All DCV components downloaded successfully"
    log_message "INFO" "DCV components downloaded to $download_dir"
}

# Function to install DCV Server
install_dcv_server() {
    print_status $BLUE "Installing DCV Server..."
    
    local download_dir="$SCRIPT_DIR/downloads"
    
    # Install DCV Server silently
    print_status $YELLOW "Installing DCV Server (this may take a few minutes)..."
    if ! msiexec /i "$download_dir/dcv-server.msi" /quiet /norestart /log "$SCRIPT_DIR/dcv-server-install.log"; then
        print_status $RED "Failed to install DCV Server"
        print_status $YELLOW "Check the log file: $SCRIPT_DIR/dcv-server-install.log"
        exit 1
    fi
    
    # Wait for installation to complete
    sleep 10
    
    # Verify installation
    if ! dcv --version >/dev/null 2>&1; then
        print_status $RED "DCV Server installation verification failed"
        exit 1
    fi
    
    print_status $GREEN "DCV Server installed successfully"
    log_message "INFO" "DCV Server installed successfully"
}

# Function to install DCV GL Agent
install_dcv_gl_agent() {
    print_status $BLUE "Installing DCV GL Agent..."
    
    local download_dir="$SCRIPT_DIR/downloads"
    
    # Install DCV GL Agent silently
    print_status $YELLOW "Installing DCV GL Agent..."
    if ! msiexec /i "$download_dir/dcv-gl-agent.msi" /quiet /norestart /log "$SCRIPT_DIR/dcv-gl-agent-install.log"; then
        print_status $RED "Failed to install DCV GL Agent"
        print_status $YELLOW "Check the log file: $SCRIPT_DIR/dcv-gl-agent-install.log"
        exit 1
    fi
    
    # Wait for installation to complete
    sleep 5
    
    print_status $GREEN "DCV GL Agent installed successfully"
    log_message "INFO" "DCV GL Agent installed successfully"
}

# Function to configure DCV Server
configure_dcv_server() {
    print_status $BLUE "Configuring DCV Server..."
    
    # Create DCV configuration directory
    local dcv_config_dir="C:\ProgramData\DCV\conf"
    mkdir -p "$dcv_config_dir"
    
    # Create DCV server configuration
    cat > "$dcv_config_dir\dcv.conf" << 'EOF'
[license]
license-file = C:\ProgramData\DCV\license.lic

[log]
level = info
file = C:\ProgramData\DCV\log\dcv-server.log
max-file-size = 10MB
max-file-count = 5

[display]
# Enable hardware acceleration
enable-gl-support = true
enable-software-rendering = false

# Display settings
width = 1920
height = 1080
color-depth = 24

# Performance settings
max-fps = 60
enable-vsync = true

[security]
# Authentication settings
auth-token-verifier = none
enable-auth-token-verifier = false

# Session settings
max-concurrent-sessions = 10
session-creation-timeout = 30

[network]
# Network settings
port = 8443
enable-quic = true
enable-websocket = true

# SSL/TLS settings
certificate = C:\ProgramData\DCV\cert\dcv-server.crt
private-key = C:\ProgramData\DCV\cert\dcv-server.key

[storage]
# Storage settings
enable-file-transfer = true
max-file-transfer-size = 100MB
EOF
    
    # Create certificates directory
    local cert_dir="C:\ProgramData\DCV\cert"
    mkdir -p "$cert_dir"
    
    # Generate self-signed certificate for testing
    print_status $YELLOW "Generating self-signed certificate..."
    openssl req -x509 -newkey rsa:4096 -keyout "$cert_dir\dcv-server.key" -out "$cert_dir\dcv-server.crt" -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
    
    # Set proper permissions
    icacls "$cert_dir\dcv-server.key" /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)"
    icacls "$cert_dir\dcv-server.crt" /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)"
    
    print_status $GREEN "DCV Server configuration completed"
    log_message "INFO" "DCV Server configured successfully"
}

# Function to create DCV session
create_dcv_session() {
    print_status $BLUE "Creating DCV session..."
    
    # Create a new DCV session
    local session_name="ue5-session"
    
    # Check if session already exists
    if dcv list-sessions | grep -q "$session_name"; then
        print_status $YELLOW "Session '$session_name' already exists, removing it..."
        dcv close-session "$session_name"
        sleep 2
    fi
    
    # Create new session
    print_status $YELLOW "Creating new DCV session: $session_name"
    if ! dcv create-session --owner "$env:USERNAME" "$session_name"; then
        print_status $RED "Failed to create DCV session"
        exit 1
    fi
    
    # Start the session
    print_status $YELLOW "Starting DCV session..."
    if ! dcv start-session "$session_name"; then
        print_status $RED "Failed to start DCV session"
        exit 1
    fi
    
    # Get session information
    local session_info=$(dcv describe-session "$session_name")
    print_status $GREEN "DCV session created and started successfully"
    print_status $BLUE "Session Name: $session_name"
    print_status $BLUE "Session Info: $session_info"
    
    log_message "INFO" "DCV session '$session_name' created and started"
}

# Function to configure Windows firewall
configure_firewall() {
    print_status $BLUE "Configuring Windows Firewall..."
    
    # Add DCV Server to Windows Firewall
    netsh advfirewall firewall add rule name="DCV Server" dir=in action=allow protocol=TCP localport=8443
    netsh advfirewall firewall add rule name="DCV Server QUIC" dir=in action=allow protocol=UDP localport=8443
    netsh advfirewall firewall add rule name="DCV Server WebSocket" dir=in action=allow protocol=TCP localport=8443
    
    # Add DCV Client to Windows Firewall
    netsh advfirewall firewall add rule name="DCV Client" dir=out action=allow program="C:\Program Files\NICE\DCV\bin\dcv.exe"
    
    print_status $GREEN "Windows Firewall configured for DCV"
    log_message "INFO" "Windows Firewall configured for DCV"
}

# Function to start DCV services
start_dcv_services() {
    print_status $BLUE "Starting DCV services..."
    
    # Start DCV Server service
    print_status $YELLOW "Starting DCV Server service..."
    if ! net start "DCV Server"; then
        print_status $RED "Failed to start DCV Server service"
        exit 1
    fi
    
    # Set DCV Server service to start automatically
    sc config "DCV Server" start= auto
    
    # Start DCV GL Agent service
    print_status $YELLOW "Starting DCV GL Agent service..."
    if ! net start "DCV GL Agent"; then
        print_status $YELLOW "DCV GL Agent service not found or already running"
    else
        # Set DCV GL Agent service to start automatically
        sc config "DCV GL Agent" start= auto
    fi
    
    print_status $GREEN "DCV services started successfully"
    log_message "INFO" "DCV services started successfully"
}

# Function to create connection script
create_connection_script() {
    print_status $BLUE "Creating connection script..."
    
    local connection_script="$SCRIPT_DIR/connect_dcv.bat"
    
    cat > "$connection_script" << 'EOF'
@echo off
REM DCV Connection Script for Unreal Engine 5 Development
REM This script connects to the DCV session for remote desktop access

echo ========================================
echo DCV Connection Script
echo ========================================
echo.

REM Get the current instance's public IP
for /f "tokens=2 delims=:" %%a in ('curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2^>nul') do set PUBLIC_IP=%%a

if "%PUBLIC_IP%"=="" (
    echo Warning: Could not retrieve public IP address
    echo You may need to manually specify the IP address
    set /p PUBLIC_IP="Enter the public IP address: "
)

echo Connecting to DCV session...
echo Public IP: %PUBLIC_IP%
echo Port: 8443
echo Session: ue5-session
echo.

REM Launch DCV Viewer
echo Launching DCV Viewer...
start "" "C:\Program Files\NICE\DCV\bin\dcv.exe" connect --web-url https://%PUBLIC_IP%:8443 ue5-session

echo.
echo If the DCV Viewer doesn't open automatically, you can:
echo 1. Open a web browser and navigate to: https://%PUBLIC_IP%:8443
echo 2. Or manually launch: "C:\Program Files\NICE\DCV\bin\dcv.exe" connect --web-url https://%PUBLIC_IP%:8443 ue5-session
echo.
echo Note: You may see a security warning due to the self-signed certificate.
echo Click "Advanced" and "Proceed to localhost (unsafe)" to continue.
echo.
pause
EOF
    
    print_status $GREEN "Connection script created: $connection_script"
    log_message "INFO" "Connection script created: $connection_script"
}

# Function to create status check script
create_status_script() {
    print_status $BLUE "Creating status check script..."
    
    local status_script="$SCRIPT_DIR/check_dcv_status.bat"
    
    cat > "$status_script" << 'EOF'
@echo off
REM DCV Status Check Script
REM This script checks the status of DCV services and sessions

echo ========================================
echo DCV Status Check
echo ========================================
echo.

echo Checking DCV Server service...
sc query "DCV Server"
echo.

echo Checking DCV GL Agent service...
sc query "DCV GL Agent"
echo.

echo Checking DCV sessions...
dcv list-sessions
echo.

echo Checking DCV server status...
dcv --version
echo.

echo Checking network connectivity...
netstat -an | findstr :8443
echo.

echo ========================================
echo Status Check Complete
echo ========================================
pause
EOF
    
    print_status $GREEN "Status check script created: $status_script"
    log_message "INFO" "Status check script created: $status_script"
}

# Function to create documentation
create_documentation() {
    print_status $BLUE "Creating documentation..."
    
    local doc_file="$SCRIPT_DIR/DCV_SETUP_GUIDE.md"
    
    cat > "$doc_file" << 'EOF'
# AWS DCV Setup Guide for Unreal Engine 5 Development

## Overview
This guide covers the setup and configuration of AWS DCV (Desktop and Cloud Visualization) on Windows EC2 instances for Unreal Engine 5 development.

## Installation Summary
- **DCV Server Version**: 2023.2-15773
- **Installation Path**: C:\Program Files\NICE\DCV\
- **Configuration Path**: C:\ProgramData\DCV\conf\
- **Log Path**: C:\ProgramData\DCV\log\
- **Certificate Path**: C:\ProgramData\DCV\cert\

## Services Installed
1. **DCV Server**: Main DCV server service
2. **DCV GL Agent**: Hardware acceleration support
3. **DCV Client**: Local client for testing

## Configuration Details

### Network Configuration
- **Port**: 8443 (HTTPS)
- **Protocols**: TCP, UDP (QUIC), WebSocket
- **Authentication**: Token-based (disabled for development)

### Display Configuration
- **Resolution**: 1920x1080
- **Color Depth**: 24-bit
- **Max FPS**: 60
- **Hardware Acceleration**: Enabled

### Security Configuration
- **SSL/TLS**: Self-signed certificate
- **Firewall**: Windows Firewall rules configured
- **Authentication**: Disabled for development (enable for production)

## Usage Instructions

### Connecting to DCV Session

#### Method 1: Using the Connection Script
```bash
# Run the connection script
./connect_dcv.bat
```

#### Method 2: Manual Connection
```bash
# Get the public IP address
curl http://169.254.169.254/latest/meta-data/public-ipv4

# Connect using DCV client
"C:\Program Files\NICE\DCV\bin\dcv.exe" connect --web-url https://<PUBLIC_IP>:8443 ue5-session
```

#### Method 3: Web Browser
1. Open a web browser
2. Navigate to: `https://<PUBLIC_IP>:8443`
3. Enter session name: `ue5-session`
4. Click "Connect"

### Managing DCV Sessions

#### List Sessions
```bash
dcv list-sessions
```

#### Create New Session
```bash
dcv create-session --owner <username> <session-name>
```

#### Start Session
```bash
dcv start-session <session-name>
```

#### Stop Session
```bash
dcv stop-session <session-name>
```

#### Close Session
```bash
dcv close-session <session-name>
```

### Checking Status
```bash
# Run the status check script
./check_dcv_status.bat

# Or manually check services
sc query "DCV Server"
sc query "DCV GL Agent"
```

## Troubleshooting

### Common Issues

#### 1. Service Not Starting
- Check Windows Event Logs
- Verify firewall settings
- Ensure proper permissions

#### 2. Connection Refused
- Verify DCV Server is running
- Check firewall rules
- Confirm port 8443 is open

#### 3. Certificate Warnings
- This is expected with self-signed certificates
- Click "Advanced" and "Proceed to localhost (unsafe)"

#### 4. Performance Issues
- Check hardware acceleration is enabled
- Verify sufficient system resources
- Monitor network bandwidth

### Log Files
- **DCV Server**: C:\ProgramData\DCV\log\dcv-server.log
- **Installation**: dcv-server-install.log, dcv-gl-agent-install.log
- **Setup**: dcv_setup.log

### Performance Optimization
1. **Hardware Acceleration**: Ensure DCV GL Agent is running
2. **Network**: Use stable, high-bandwidth connection
3. **Display**: Adjust resolution based on network capacity
4. **Compression**: DCV automatically optimizes based on network conditions

## Security Considerations

### For Development
- Self-signed certificates are acceptable
- Authentication is disabled for ease of use
- Firewall rules are permissive

### For Production
- Use proper SSL certificates
- Enable authentication
- Restrict firewall rules to specific IPs
- Implement proper access controls

## Integration with Unreal Engine 5

### Benefits
1. **Remote Development**: Access UE5 editor remotely
2. **Hardware Acceleration**: GPU support for rendering
3. **File Transfer**: Easy file sharing between local and remote
4. **Multi-user**: Support for multiple developers

### Best Practices
1. **Session Management**: Create separate sessions for different projects
2. **Resource Monitoring**: Monitor system resources during compilation
3. **Backup**: Regular backups of UE5 projects
4. **Updates**: Keep DCV and UE5 updated

## Support and Resources

### Official Documentation
- [AWS DCV Administrator Guide](https://docs.aws.amazon.com/dcv/latest/adminguide/)
- [DCV User Guide](https://docs.aws.amazon.com/dcv/latest/userguide/)

### Community Resources
- AWS DCV Forum
- GitHub Issues
- Stack Overflow

### Contact Information
- AWS Support: For AWS-specific issues
- NICE Software Support: For DCV-specific issues
EOF
    
    print_status $GREEN "Documentation created: $doc_file"
    log_message "INFO" "Documentation created: $doc_file"
}

# Function to perform post-installation verification
verify_installation() {
    print_status $BLUE "Performing post-installation verification..."
    
    # Check DCV version
    local dcv_version=$(dcv --version 2>/dev/null || echo "Not found")
    print_status $BLUE "DCV Version: $dcv_version"
    
    # Check services
    local dcv_server_status=$(sc query "DCV Server" | grep "STATE" | head -1)
    local dcv_gl_agent_status=$(sc query "DCV GL Agent" | grep "STATE" | head -1)
    
    print_status $BLUE "DCV Server Status: $dcv_server_status"
    print_status $BLUE "DCV GL Agent Status: $dcv_gl_agent_status"
    
    # Check sessions
    local sessions=$(dcv list-sessions 2>/dev/null || echo "No sessions found")
    print_status $BLUE "DCV Sessions: $sessions"
    
    # Check network
    local port_status=$(netstat -an | grep ":8443" || echo "Port 8443 not listening")
    print_status $BLUE "Port 8443 Status: $port_status"
    
    # Check firewall rules
    local firewall_rules=$(netsh advfirewall firewall show rule name="DCV*" | grep "Enabled" || echo "No DCV firewall rules found")
    print_status $BLUE "Firewall Rules: $firewall_rules"
    
    print_status $GREEN "Verification completed"
    log_message "INFO" "Post-installation verification completed"
}

# Function to display completion summary
display_summary() {
    print_status $GREEN "=========================================="
    print_status $GREEN "AWS DCV Setup Completed Successfully!"
    print_status $GREEN "=========================================="
    print_status $BLUE ""
    print_status $BLUE "Installation Summary:"
    print_status $BLUE "- DCV Server: Installed and configured"
    print_status $BLUE "- DCV GL Agent: Installed for hardware acceleration"
    print_status $BLUE "- DCV Client: Downloaded for testing"
    print_status $BLUE "- Session: 'ue5-session' created and started"
    print_status $BLUE "- Firewall: Configured for DCV traffic"
    print_status $BLUE "- Services: Started and set to auto-start"
    print_status $BLUE ""
    print_status $BLUE "Next Steps:"
    print_status $BLUE "1. Run: ./connect_dcv.bat"
    print_status $BLUE "2. Or connect via web browser: https://<PUBLIC_IP>:8443"
    print_status $BLUE "3. Session name: ue5-session"
    print_status $BLUE "4. Check status: ./check_dcv_status.bat"
    print_status $BLUE ""
    print_status $BLUE "Files Created:"
    print_status $BLUE "- Connection script: ./connect_dcv.bat"
    print_status $BLUE "- Status script: ./check_dcv_status.bat"
    print_status $BLUE "- Documentation: ./DCV_SETUP_GUIDE.md"
    print_status $BLUE "- Log file: ./dcv_setup.log"
    print_status $BLUE ""
    print_status $YELLOW "Note: You may see certificate warnings due to self-signed certificate."
    print_status $YELLOW "This is normal for development environments."
    print_status $GREEN "=========================================="
    
    log_message "INFO" "DCV setup completed successfully"
}

# Main execution function
main() {
    print_status $GREEN "Starting AWS DCV Setup for Windows EC2"
    print_status $GREEN "======================================="
    
    # Initialize log file
    echo "AWS DCV Setup Log - $(date)" > "$LOG_FILE"
    
    # Execute setup steps
    check_windows
    check_prerequisites
    download_dcv_components
    install_dcv_server
    install_dcv_gl_agent
    configure_dcv_server
    create_dcv_session
    configure_firewall
    start_dcv_services
    create_connection_script
    create_status_script
    create_documentation
    verify_installation
    display_summary
    
    print_status $GREEN "Setup completed successfully!"
    print_status $BLUE "Check the log file for detailed information: $LOG_FILE"
}

# Execute main function
main "$@"
