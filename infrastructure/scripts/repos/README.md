# Repository Deployment and OpenSSL Build

This directory contains AWS Systems Manager (SSM) documents for deploying essential repositories and building OpenSSL from source on Windows EC2 instances. The system supports automated deployment of the AWS GameLift Plugin for Unreal Engine and OpenSSL compilation for secure game server operations.

## Files

### Scripts
- `deploy_repos_staged.sh` - Main script for deploying repositories to Windows EC2 instances
- `deploy_openssl_ssm_doc.sh` - Script to deploy the OpenSSL build SSM document to AWS

### SSM Documents
- `ssm_doc_repo_operations.json` - SSM document for repository operations (clone, update, validate)
- `ssm_doc_build_openssl.json` - SSM document that builds OpenSSL following the official Windows build steps

### Documentation
- `README.md` - This documentation file

## AWS GameLift Plugin for Unreal Engine

The repository deployment system automatically clones the [AWS GameLift Plugin for Unreal Engine](https://github.com/amazon-gamelift/amazon-gamelift-plugin-unreal) to enable seamless integration with Amazon GameLift Servers.

### Plugin Features

The AWS GameLift Plugin provides:

- **Server SDK Integration**: Full access to Amazon GameLift Servers SDK features
- **Guided UI Workflows**: Quick deployment with minimal setup
- **Build Target Support**: Separate client and server build configurations
- **Game Session Management**: Handle game sessions, player connections, and server lifecycle
- **Health Monitoring**: Built-in health checks and status reporting
- **Logging Integration**: Automatic log file management and cloud storage

### Repository Details

| Property | Value |
|----------|-------|
| **Repository URL** | `https://github.com/amazon-gamelift/amazon-gamelift-plugin-unreal.git` |
| **Branch** | `main` |
| **Destination** | `C:\AmazonGameLiftPlugin` |
| **License** | Apache 2.0 |

### Integration Process

The plugin deployment follows these steps:

1. **Repository Clone**: Downloads the latest plugin source code
2. **Build Target Setup**: Creates separate client and server build targets
3. **Module Configuration**: Updates project module rules for GameLift dependency
4. **Server Code Integration**: Adds required GameLift server functionality
5. **Packaging Support**: Prepares game server for GameLift deployment

### Build Target Configuration

The plugin requires specific build targets for proper integration:

#### Client Target (`[ProjectName]Client.Target.cs`)
```csharp
public class [ProjectName]ClientTarget : TargetRules
{
    public [ProjectName]ClientTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Client;
        DefaultBuildSettings = BuildSettingsVersion.V2;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_1;
        ExtraModuleNames.Add("[ProjectName]");
    }
}
```

#### Server Target (`[ProjectName]Server.Target.cs`)
```csharp
public class [ProjectName]ServerTarget : TargetRules
{
    public [ProjectName]ServerTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Server;
        DefaultBuildSettings = BuildSettingsVersion.V2;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_1;
        ExtraModuleNames.Add("[ProjectName]");
    }
}
```

### Module Rules Update

The project's `.Build.cs` file must be updated to include GameLift dependencies:

```csharp
public class [ProjectName] : ModuleRules
{
    public [ProjectName](ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new string[] { 
            "Core", "CoreUObject", "Engine", "InputCore", 
            "HeadMountedDisplay", "EnhancedInput" 
        });
        
        // Add GameLift dependency for server builds
        if (Target.Type == TargetType.Server)
        {
            PublicDependencyModuleNames.Add("GameLiftServerSDK");
        }
        else
        {
            PublicDefinitions.Add("WITH_GAMELIFT=0");
        }
        
        bEnableExceptions = true;
    }
}
```

### Server Integration Code

The plugin requires specific server code integration for GameLift functionality:

#### GameMode Header (`[ProjectName]GameMode.h`)
```cpp
#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "[ProjectName]GameMode.generated.h"

struct FProcessParameters;

DECLARE_LOG_CATEGORY_EXTERN(GameServerLog, Log, All);

UCLASS(minimalapi)
class A[ProjectName]GameMode : public AGameModeBase
{
    GENERATED_BODY()

public:
    A[ProjectName]GameMode();

protected:
    virtual void BeginPlay() override;

private:
    void InitGameLift();

private:
    TSharedPtr<FProcessParameters> ProcessParameters;
};
```

#### GameMode Implementation (`[ProjectName]GameMode.cpp`)
Key integration points include:
- **ProcessReady()**: Notifies GameLift when server is ready
- **OnStartGameSession**: Handles new game session requests
- **OnProcessTerminate**: Manages server shutdown
- **OnHealthCheck**: Provides server health status

## OpenSSL Build Process

The SSM document follows the official OpenSSL Windows build steps from [NOTES-WINDOWS.md](https://github.com/openssl/openssl/blob/master/NOTES-WINDOWS.md):

### Step 1: Repository Check
- Verifies that the OpenSSL repository is cloned and accessible
- Checks for the presence of the source code

### Step 2: Build Tools Verification
- Checks for Visual Studio Build Tools (using vswhere.exe)
- Verifies Perl installation (required for OpenSSL build)
- Verifies NASM installation (required for assembly code)

### Step 3: Visual Studio Environment Setup
- Sets up the Visual Studio build environment using `vcvarsall.bat`
- Configures environment variables for the target architecture
- Supports x86, x64, ARM, and ARM64 architectures

### Step 4: OpenSSL Configuration
- Runs `perl Configure VC-WIN64A` (or appropriate variant)
- Configures build options based on architecture and build type
- Sets installation paths and SSL directory

### Step 5: Build Process
- Executes `nmake` to build OpenSSL
- Handles build errors and provides detailed logging
- Supports both Release and Debug builds

### Step 6: Testing and Installation
- Runs `nmake test` to verify the build
- Executes `nmake install` to install OpenSSL
- Verifies installation and reports file sizes

## Prerequisites

Before running the OpenSSL build, ensure the following are installed on the Windows EC2 instance:

1. **Visual Studio Build Tools** or **Visual Studio Community/Professional**
   - Required for C/C++ compilation
   - Must include MSVC compiler and Windows SDK

2. **Perl**
   - Strawberry Perl or ActivePerl
   - Required for OpenSSL configuration scripts

3. **NASM (Netwide Assembler)**
   - Required for assembly code compilation
   - Download from: https://www.nasm.us/

4. **Git**
   - Required for cloning the OpenSSL repository
   - Should be installed via the repository deployment script

## Usage

### 1. Deploy Repositories (Including GameLift Plugin)

The main repository deployment script handles both the AWS GameLift Plugin and OpenSSL repository:

```bash
# Deploy all configured repositories to a Windows EC2 instance
./deploy_repos_staged.sh i-1234567890abcdef0

# Deploy with specific environment and region
./deploy_repos_staged.sh -e prod -r us-west-2 i-1234567890abcdef0

# List configured repositories
./deploy_repos_staged.sh --list-repos

# Add a new repository interactively
./deploy_repos_staged.sh --add-repo

# Update existing repositories
./deploy_repos_staged.sh --update-repos i-1234567890abcdef0

# Validate repository URLs
./deploy_repos_staged.sh --validate-repos
```

#### Repository Deployment Process

The script automatically deploys:

1. **AWS GameLift Plugin** → `C:\AmazonGameLiftPlugin`
2. **OpenSSL Source** → `C:\OpenSSL`

### 2. Deploy the OpenSSL Build SSM Document

```bash
# Deploy with default settings
./deploy_openssl_ssm_doc.sh

# Deploy to specific environment and region
./deploy_openssl_ssm_doc.sh -e prod -r us-west-2

# Update existing document
./deploy_openssl_ssm_doc.sh --update

# Validate JSON syntax only
./deploy_openssl_ssm_doc.sh --validate
```

### 3. Clone OpenSSL Repository

The OpenSSL repository is automatically cloned during the repository deployment process (Step 1 above) to `C:\OpenSSL`.

### 4. Execute the OpenSSL Build

Use AWS Systems Manager to execute the document on your Windows EC2 instance:

```bash
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "OpenSSL-Build-Windows" \
    --parameters '{
        "opensslRepoPath": ["C:\\OpenSSL"],
        "buildType": ["Release"],
        "architecture": ["x64"],
        "installPath": ["C:\\OpenSSL"]
    }' \
    --region us-east-1
```

## Parameters

The SSM document accepts the following parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `opensslRepoPath` | String | `C:\OpenSSL` | Path to the cloned OpenSSL repository |
| `buildType` | String | `Release` | Build type: `Release` or `Debug` |
| `architecture` | String | `x64` | Target architecture: `x86`, `x64`, `ARM`, `ARM64` |
| `installPath` | String | `C:\OpenSSL` | Installation path for OpenSSL |
| `region` | String | `us-east-1` | AWS region |

## Build Output

The build process will:

1. **Install OpenSSL** to the specified installation path
2. **Create logs** in `C:\logs\openssl-build-YYYYMMDD-HHMMSS.log`
3. **Report success/failure** with detailed error messages
4. **Verify installation** and report file sizes

## Troubleshooting

### Common Issues

1. **Visual Studio Build Tools Not Found**
   - Ensure Visual Studio Build Tools are installed
   - Check that vswhere.exe is available in the expected location

2. **Perl Not Found**
   - Install Strawberry Perl or ActivePerl
   - Ensure Perl is in the system PATH

3. **NASM Not Found**
   - Download and install NASM from https://www.nasm.us/
   - Ensure NASM is in the system PATH

4. **Repository Not Found**
   - Ensure the OpenSSL repository is cloned first
   - Check the repository path parameter

5. **Build Failures**
   - Check the detailed log file in `C:\logs\`
   - Verify all prerequisites are installed
   - Ensure sufficient disk space is available

### Log Files

All build operations are logged to:
- `C:\logs\openssl-build-YYYYMMDD-HHMMSS.log`

The log file contains:
- Parameter values
- Build tool verification results
- Configuration output
- Build progress and errors
- Installation verification

## Integration with Unreal Engine

This repository deployment system is designed to work with Unreal Engine 5 dedicated servers and provides essential components for game server development:

### AWS GameLift Plugin Integration

The AWS GameLift Plugin enables:

- **Scalable Game Hosting**: Deploy game servers to AWS GameLift managed fleets
- **Session Management**: Handle game sessions, player connections, and matchmaking
- **Health Monitoring**: Built-in health checks and automatic server replacement
- **Log Management**: Automatic log collection and cloud storage
- **Fleet Management**: Support for managed EC2, container, and Anywhere fleets
- **Cost Optimization**: Pay-per-use pricing with automatic scaling

### OpenSSL Integration

The built OpenSSL libraries provide:

- **SSL/TLS Connections**: Secure communication in game servers
- **AWS Service Integration**: Secure communication with AWS services
- **Cryptographic Operations**: Encryption and decryption capabilities
- **HTTPS Client/Server**: Web-based game features and APIs

### Combined Benefits

Together, these components provide:

- **Complete Game Server Stack**: From development to production deployment
- **Security**: End-to-end encryption and secure AWS integration
- **Scalability**: Automatic scaling based on player demand
- **Reliability**: Health monitoring and automatic failover
- **Cost Efficiency**: Pay only for resources used

## References

### AWS GameLift Documentation
- [Integrate Amazon GameLift Servers into an Unreal Engine project](https://docs.aws.amazon.com/gameliftservers/latest/developerguide/integration-engines-setup-unreal.html)
- [Amazon GameLift Servers Plugin for Unreal Engine](https://github.com/amazon-gamelift/amazon-gamelift-plugin-unreal)
- [C++ (Unreal) server SDK 5.x for Amazon GameLift Servers](https://docs.aws.amazon.com/gameliftservers/latest/developerguide/integration-server-sdk-cpp-ref-actions.html)
- [Amazon GameLift Servers Anywhere fleets](https://docs.aws.amazon.com/gameliftservers/latest/developerguide/fleets-anywhere.html)
- [Amazon GameLift Servers managed EC2 fleets](https://docs.aws.amazon.com/gameliftservers/latest/developerguide/fleets-creating.html)

### OpenSSL Documentation
- [OpenSSL Windows Build Notes](https://github.com/openssl/openssl/blob/master/NOTES-WINDOWS.md)
- [Microsoft C++ Build Tools](https://learn.microsoft.com/en-us/cpp/build/building-on-the-command-line)

### AWS Services
- [AWS Systems Manager Documents](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-ssm-docs.html)
- [Unreal Engine Build Requirements](https://docs.unrealengine.com/5.4/en-US/building-unreal-engine-from-source/)
