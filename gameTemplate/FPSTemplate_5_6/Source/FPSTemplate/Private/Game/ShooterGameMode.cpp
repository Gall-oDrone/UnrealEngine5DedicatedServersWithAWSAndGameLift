// Fill out your copyright notice in the Description page of Project Settings.


#include "Game/ShooterGameMode.h"

#include "UObject/ConstructorHelpers.h"
#include "Kismet/GameplayStatics.h"
#include "Engine/World.h"
#include "Engine/Engine.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"
#include "GenericPlatform/GenericPlatformMemory.h"
#include "HAL/PlatformFilemanager.h"
#include "Misc/DateTime.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"

#if WITH_GAMELIFT
#include "GameLiftServerSDK.h"
#include "GameLiftServerSDKModels.h"
#endif

DEFINE_LOG_CATEGORY(GameServerLog);

// Constructor
AShooterGameMode::AShooterGameMode() :
    ServerState(EGameLiftServerState::Uninitialized),
    bIsGameLiftInitialized(false),
    bIsGameSessionActive(false),
    bIsTerminating(false),
    bIsAnywhereFleet(false),
    CurrentPlayerCount(0),
    MaxPlayers(0),
    LastTickTime(0.0f),
    TickTimeAccumulator(0.0f),
    TickCounter(0),
    ConsecutiveInitFailures(0)
#if WITH_GAMELIFT
    , ProcessParameters(nullptr)
    , GameLiftModule(nullptr)
#endif
{
    // Set default pawn class
    static ConstructorHelpers::FClassFinder<APawn> PlayerPawnBPClass(TEXT("/Game/ThirdPerson/Blueprints/BP_ThirdPersonCharacter"));
    if (PlayerPawnBPClass.Class != NULL)
    {
        DefaultPawnClass = PlayerPawnBPClass.Class;
    }

    // Enable ticking for health monitoring
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.TickInterval = 0.0f; // Tick every frame

    UE_LOG(GameServerLog, Log, TEXT("GameLift GameMode initialized"));
}

// Begin Play
void AShooterGameMode::BeginPlay()
{
    Super::BeginPlay();

    // Initialize server statistics
    ServerStats.ServerStartTime = FDateTime::Now();
    LastTickTime = GetWorld()->GetTimeSeconds();

#if WITH_GAMELIFT
    // Parse command line arguments first
    ParseCommandLineArguments();

    // Validate configuration
    if (!ValidateServerConfiguration())
    {
        UE_LOG(GameServerLog, Error, TEXT("Invalid server configuration. GameLift initialization aborted."));
        TransitionToState(EGameLiftServerState::Error);
        return;
    }

    // Start GameLift initialization
    TransitionToState(EGameLiftServerState::Initializing);
    InitGameLift();

    // Setup periodic health check timer
    GetWorldTimerManager().SetTimer(
        HealthCheckTimerHandle,
        this,
        &AShooterGameMode::PerformHealthCheck,
        ServerConfig.HealthCheckIntervalSeconds,
        true
    );

    // Setup statistics update timer
    GetWorldTimerManager().SetTimer(
        StatisticsUpdateTimerHandle,
        this,
        &AShooterGameMode::UpdateServerStatistics,
        TICK_RATE_UPDATE_INTERVAL,
        true
    );
#else
    UE_LOG(GameServerLog, Warning, TEXT("GameLift support not compiled. Running in standalone mode."));
#endif
}

// End Play
void AShooterGameMode::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
    UE_LOG(GameServerLog, Log, TEXT("GameMode EndPlay called. Reason: %d"), (int32)EndPlayReason);

#if WITH_GAMELIFT
    // Clear all timers
    GetWorldTimerManager().ClearTimer(HealthCheckTimerHandle);
    GetWorldTimerManager().ClearTimer(StatisticsUpdateTimerHandle);
    GetWorldTimerManager().ClearTimer(RetryInitTimerHandle);

    // Perform cleanup
    ShutdownGameLift();
#endif

    Super::EndPlay(EndPlayReason);
}

// Tick
void AShooterGameMode::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);

    // Update tick rate calculation
    TickTimeAccumulator += DeltaSeconds;
    TickCounter++;

    // Track last tick time for health monitoring
    LastTickTime = GetWorld()->GetTimeSeconds();
}

// GameLift Initialization
void AShooterGameMode::InitGameLift()
{
#if WITH_GAMELIFT
    UE_LOG(GameServerLog, Log, TEXT("Initializing GameLift integration..."));

    // Load the GameLift module
    GameLiftModule = &FModuleManager::LoadModuleChecked<FGameLiftServerSDKModule>(FName("GameLiftServerSDK"));
    if (!GameLiftModule)
    {
        UE_LOG(GameServerLog, Error, TEXT("Failed to load GameLift SDK module"));
        TransitionToState(EGameLiftServerState::Error);
        return;
    }

    InitGameLiftWithRetry(0);
#endif
}

#if WITH_GAMELIFT
void AShooterGameMode::InitGameLiftWithRetry(int32 AttemptNumber)
{
#if WITH_GAMELIFT
    if (AttemptNumber >= ServerConfig.MaxRetryAttempts)
    {
        UE_LOG(GameServerLog, Error, TEXT("Failed to initialize GameLift after %d attempts"), ServerConfig.MaxRetryAttempts);
        ConsecutiveInitFailures = ServerConfig.MaxRetryAttempts;
        TransitionToState(EGameLiftServerState::Error);
        return;
    }

    // Setup server parameters
    FServerParameters ServerParameters;

    // Check if this is a GameLift Anywhere fleet
    bIsAnywhereFleet = FParse::Param(FCommandLine::Get(), TEXT("glAnywhere"));
    if (bIsAnywhereFleet)
    {
        ParseGameLiftAnywhereParameters(ServerParameters);
    }

    // Attempt initialization
    UE_LOG(GameServerLog, Log, TEXT("Attempting GameLift SDK initialization (attempt %d/%d)..."),
        AttemptNumber + 1, ServerConfig.MaxRetryAttempts);

    FGameLiftGenericOutcome InitOutcome = GameLiftModule->InitSDK(ServerParameters);

    if (InitOutcome.IsSuccess())
    {
        UE_LOG(GameServerLog, Log, TEXT("GameLift SDK initialized successfully"));
        LastInitAttemptTime = FDateTime::Now();
        ConsecutiveInitFailures = 0;

        // Setup callbacks and complete initialization
        SetupGameLiftCallbacks();

        // Call ProcessReady
        ProcessParameters = MakeShared<FProcessParameters>();

        // Set port
        ProcessParameters->port = ServerConfig.ServerPort;

        // Setup log files
        TArray<FString> LogFiles;
        LogFiles.Add(ServerConfig.LogDirectory + TEXT("server.log"));
        LogFiles.Append(ServerConfig.AdditionalLogFiles);
        ProcessParameters->logParameters = LogFiles;

        // Call ProcessReady
        FGameLiftGenericOutcome ProcessReadyOutcome = GameLiftModule->ProcessReady(*ProcessParameters);

        if (ProcessReadyOutcome.IsSuccess())
        {
            UE_LOG(GameServerLog, Log, TEXT("ProcessReady successful. Server is ready to host game sessions."));
            bIsGameLiftInitialized = true;
            TransitionToState(EGameLiftServerState::Ready);
        }
        else
        {
            FGameLiftError Error = ProcessReadyOutcome.GetError();
            LastErrorMessage = Error.m_errorMessage;
            UE_LOG(GameServerLog, Error, TEXT("ProcessReady failed: %s"), *LastErrorMessage);
            TransitionToState(EGameLiftServerState::Error);
        }
    }
    else
    {
        FGameLiftError Error = InitOutcome.GetError();
        LastErrorMessage = Error.m_errorMessage;
        ConsecutiveInitFailures++;

        UE_LOG(GameServerLog, Warning, TEXT("GameLift SDK initialization failed: %s"), *LastErrorMessage);

        // Schedule retry with exponential backoff
        float RetryDelay = ServerConfig.RetryDelaySeconds * FMath::Pow(ServerConfig.RetryBackoffMultiplier, AttemptNumber);
        UE_LOG(GameServerLog, Log, TEXT("Retrying in %.2f seconds..."), RetryDelay);

        GetWorldTimerManager().SetTimer(
            RetryInitTimerHandle,
            [this, AttemptNumber]() { InitGameLiftWithRetry(AttemptNumber + 1); },
            RetryDelay,
            false
        );
    }
#endif
}
#endif

#if WITH_GAMELIFT
void AShooterGameMode::SetupGameLiftCallbacks()
{
#if WITH_GAMELIFT
    if (!ProcessParameters.IsValid())
    {
        ProcessParameters = MakeShared<FProcessParameters>();
    }

    // OnStartGameSession callback
    ProcessParameters->OnStartGameSession.BindLambda([this](Aws::GameLift::Server::Model::GameSession InGameSession)
        {
            HandleGameSessionStart(InGameSession);
        });

    // OnProcessTerminate callback
    ProcessParameters->OnTerminate.BindLambda([this]()
        {
            HandleProcessTerminate();
        });

    // OnHealthCheck callback
    ProcessParameters->OnHealthCheck.BindLambda([this]()
        {
            return HandleHealthCheck();
        });

    // OnUpdateGameSession callback (for FlexMatch updates)
    ProcessParameters->OnUpdateGameSession.BindLambda([this](Aws::GameLift::Server::Model::UpdateGameSession UpdateGameSession)
        {
            HandleGameSessionUpdate(UpdateGameSession);
        });

    UE_LOG(GameServerLog, Log, TEXT("GameLift callbacks configured"));
#endif
}
#endif

void AShooterGameMode::ParseCommandLineArguments()
{
    // Parse port from command line
    if (!FParse::Value(FCommandLine::Get(), TEXT("port="), ServerConfig.ServerPort))
    {
        // Try to get from URL if not in command line
        if (GetWorld() && GetWorld()->URL.Port > 0)
        {
            ServerConfig.ServerPort = GetWorld()->URL.Port;
        }
    }

    // Validate port range
    if (ServerConfig.ServerPort < 1024 || ServerConfig.ServerPort > 65535)
    {
        UE_LOG(GameServerLog, Warning, TEXT("Invalid port %d specified. Using default 7777."), ServerConfig.ServerPort);
        ServerConfig.ServerPort = 7777;
    }

    // Parse other configuration options
    FParse::Value(FCommandLine::Get(), TEXT("maxplayers="), MaxPlayers);
    FParse::Bool(FCommandLine::Get(), TEXT("detailedlogging="), ServerConfig.bEnableDetailedLogging);

    UE_LOG(GameServerLog, Log, TEXT("Server configuration: Port=%d, MaxPlayers=%d"),
        ServerConfig.ServerPort, MaxPlayers);
}

#if WITH_GAMELIFT
void AShooterGameMode::ParseGameLiftAnywhereParameters(FServerParameters& OutParams)
{
#if WITH_GAMELIFT
    UE_LOG(GameServerLog, Log, TEXT("Parsing GameLift Anywhere parameters..."));

    // Parse WebSocket URL
    FString WebSocketUrl;
    if (FParse::Value(FCommandLine::Get(), TEXT("glAnywhereWebSocketUrl="), WebSocketUrl))
    {
        OutParams.m_webSocketUrl = TCHAR_TO_UTF8(*WebSocketUrl);
        UE_LOG(GameServerLog, Log, TEXT("WebSocket URL configured"));
    }

    // Parse Fleet ID
    FString FleetId;
    if (FParse::Value(FCommandLine::Get(), TEXT("glAnywhereFleetId="), FleetId))
    {
        OutParams.m_fleetId = TCHAR_TO_UTF8(*FleetId);
        UE_LOG(GameServerLog, Log, TEXT("Fleet ID: %s"), *FleetId);
    }

    // Parse or generate Process ID
    FString ProcessId;
    if (!FParse::Value(FCommandLine::Get(), TEXT("glAnywhereProcessId="), ProcessId))
    {
        // Generate unique process ID
        ProcessId = FString::Printf(TEXT("Process_%s_%d"),
            *FDateTime::Now().ToString(),
            FMath::RandRange(1000, 9999));
    }
    OutParams.m_processId = TCHAR_TO_UTF8(*ProcessId);
    UE_LOG(GameServerLog, Log, TEXT("Process ID: %s"), *ProcessId);

    // Parse Host ID
    FString HostId;
    if (FParse::Value(FCommandLine::Get(), TEXT("glAnywhereHostId="), HostId))
    {
        OutParams.m_hostId = TCHAR_TO_UTF8(*HostId);
        UE_LOG(GameServerLog, Log, TEXT("Host ID: %s"), *HostId);
    }

    // Parse sensitive parameters without logging their values
    FString AuthToken, AccessKey, SecretKey, SessionToken, AwsRegion;

    if (FParse::Value(FCommandLine::Get(), TEXT("glAnywhereAuthToken="), AuthToken))
    {
        OutParams.m_authToken = TCHAR_TO_UTF8(*AuthToken);
        UE_LOG(GameServerLog, Log, TEXT("Auth Token: [REDACTED]"));
    }

    if (FParse::Value(FCommandLine::Get(), TEXT("glAnywhereAwsRegion="), AwsRegion))
    {
        OutParams.m_awsRegion = TCHAR_TO_UTF8(*AwsRegion);
        UE_LOG(GameServerLog, Log, TEXT("AWS Region: %s"), *AwsRegion);
    }

    if (FParse::Value(FCommandLine::Get(), TEXT("glAnywhereAccessKey="), AccessKey))
    {
        OutParams.m_accessKey = TCHAR_TO_UTF8(*AccessKey);
        UE_LOG(GameServerLog, Log, TEXT("Access Key: [REDACTED]"));
    }

    if (FParse::Value(FCommandLine::Get(), TEXT("glAnywhereSecretKey="), SecretKey))
    {
        OutParams.m_secretKey = TCHAR_TO_UTF8(*SecretKey);
        UE_LOG(GameServerLog, Log, TEXT("Secret Key: [REDACTED]"));
    }

    if (FParse::Value(FCommandLine::Get(), TEXT("glAnywhereSessionToken="), SessionToken))
    {
        OutParams.m_sessionToken = TCHAR_TO_UTF8(*SessionToken);
        UE_LOG(GameServerLog, Log, TEXT("Session Token: [REDACTED]"));
    }
#endif
}
#endif

#if WITH_GAMELIFT
bool AShooterGameMode::ValidateServerConfiguration()
{
    bool bIsValid = true;

    // Validate port
    if (ServerConfig.ServerPort < 1024 || ServerConfig.ServerPort > 65535)
    {
        UE_LOG(GameServerLog, Error, TEXT("Invalid server port: %d"), ServerConfig.ServerPort);
        bIsValid = false;
    }

    // Validate memory thresholds
    if (ServerConfig.MaxMemoryUsagePercent <= 0 || ServerConfig.MaxMemoryUsagePercent > 100)
    {
        UE_LOG(GameServerLog, Error, TEXT("Invalid max memory usage percent: %.2f"), ServerConfig.MaxMemoryUsagePercent);
        bIsValid = false;
    }

    // Validate retry settings
    if (ServerConfig.MaxRetryAttempts < 0 || ServerConfig.RetryDelaySeconds < 0)
    {
        UE_LOG(GameServerLog, Error, TEXT("Invalid retry configuration"));
        bIsValid = false;
    }

    return bIsValid;
}
#endif

// State Management
void AShooterGameMode::TransitionToState(EGameLiftServerState NewState)
{
    FScopeLock Lock(&StateLock);

    if (!CanTransitionToState(NewState))
    {
        UE_LOG(GameServerLog, Warning, TEXT("Invalid state transition from %d to %d"),
            (int32)ServerState, (int32)NewState);
        return;
    }

    EGameLiftServerState OldState = ServerState;
    ServerState = NewState;

    if (ServerConfig.bEnableDetailedLogging)
    {
        UE_LOG(GameServerLog, Log, TEXT("State transition: %d -> %d"),
            (int32)OldState, (int32)NewState);
    }

    HandleStateTransition(OldState, NewState);
}

bool AShooterGameMode::CanTransitionToState(EGameLiftServerState NewState) const
{
    // Define valid state transitions
    switch (ServerState)
    {
    case EGameLiftServerState::Uninitialized:
        return NewState == EGameLiftServerState::Initializing ||
            NewState == EGameLiftServerState::Error;

    case EGameLiftServerState::Initializing:
        return NewState == EGameLiftServerState::Ready ||
            NewState == EGameLiftServerState::Error ||
            NewState == EGameLiftServerState::Shutdown;

    case EGameLiftServerState::Ready:
        return NewState == EGameLiftServerState::ActivatingSession ||
            NewState == EGameLiftServerState::Terminating ||
            NewState == EGameLiftServerState::Error ||
            NewState == EGameLiftServerState::Shutdown;

    case EGameLiftServerState::ActivatingSession:
        return NewState == EGameLiftServerState::InSession ||
            NewState == EGameLiftServerState::Ready ||
            NewState == EGameLiftServerState::Error ||
            NewState == EGameLiftServerState::Terminating;

    case EGameLiftServerState::InSession:
        return NewState == EGameLiftServerState::Ready ||
            NewState == EGameLiftServerState::Terminating ||
            NewState == EGameLiftServerState::Error;

    case EGameLiftServerState::Terminating:
        return NewState == EGameLiftServerState::Shutdown;

    case EGameLiftServerState::Error:
        return NewState == EGameLiftServerState::Initializing ||
            NewState == EGameLiftServerState::Shutdown;

    case EGameLiftServerState::Shutdown:
        return false; // Terminal state

    default:
        return false;
    }
}

void AShooterGameMode::HandleStateTransition(EGameLiftServerState OldState, EGameLiftServerState NewState)
{
    // Handle state-specific actions
    switch (NewState)
    {
    case EGameLiftServerState::Ready:
        UE_LOG(GameServerLog, Log, TEXT("Server is ready to host game sessions"));
        break;

    case EGameLiftServerState::InSession:
        ServerStats.TotalSessionsHosted++;
        break;

    case EGameLiftServerState::Error:
        UE_LOG(GameServerLog, Error, TEXT("Server entered error state. Last error: %s"), *LastErrorMessage);
        break;

    case EGameLiftServerState::Shutdown:
        if (ServerConfig.bAutoShutdownOnTerminate)
        {
            UE_LOG(GameServerLog, Log, TEXT("Requesting engine shutdown..."));
            FGenericPlatformMisc::RequestExit(false);
        }
        break;

    default:
        break;
    }
}

// GameLift Callbacks
#if WITH_GAMELIFT
void AShooterGameMode::HandleGameSessionStart(const Aws::GameLift::Server::Model::GameSession& GameSession)
{
#if WITH_GAMELIFT
    FScopeLock Lock(&SessionLock);

    UE_LOG(GameServerLog, Log, TEXT("Received game session activation request"));

    TransitionToState(EGameLiftServerState::ActivatingSession);

    // Extract session information
    CurrentGameSessionId = FString(GameSession.GetGameSessionId());
    MaxPlayers = GameSession.GetMaximumPlayerSessionCount();

    // Parse game properties
    auto Properties = GameSession.GetGameProperties();
    for (const auto& Property : Properties)
    {
        FString Key = FString(Property.GetKey());
        FString Value = FString(Property.GetValue());
        GameSessionProperties.Add(Key, Value);

        if (ServerConfig.bEnableDetailedLogging)
        {
            UE_LOG(GameServerLog, Log, TEXT("Game Property: %s = %s"), *Key, *Value);
        }
    }

    // Validate session properties
    if (!ValidateGameSessionProperties(GameSessionProperties))
    {
        UE_LOG(GameServerLog, Error, TEXT("Invalid game session properties"));
        TransitionToState(EGameLiftServerState::Ready);
        return;
    }

    // Prepare the game world
    PrepareGameWorld(GameSessionProperties);

    // Check if world is ready
    if (!IsGameWorldReady())
    {
        UE_LOG(GameServerLog, Error, TEXT("Game world not ready for session activation"));
        TransitionToState(EGameLiftServerState::Ready);
        return;
    }

    // Activate the game session
    FGameLiftGenericOutcome ActivateOutcome = GameLiftModule->ActivateGameSession();

    if (ActivateOutcome.IsSuccess())
    {
        bIsGameSessionActive = true;
        CurrentPlayerCount = 0;
        TransitionToState(EGameLiftServerState::InSession);

        UE_LOG(GameServerLog, Log, TEXT("Game session activated successfully: %s"), *CurrentGameSessionId);

        // Notify blueprints
        OnGameSessionActivated.Broadcast(CurrentGameSessionId);

        // Call virtual function for game-specific logic
        OnGameSessionStarted(CurrentGameSessionId);
    }
    else
    {
        FGameLiftError Error = ActivateOutcome.GetError();
        UE_LOG(GameServerLog, Error, TEXT("Failed to activate game session: %s"), *Error.m_errorMessage);
        TransitionToState(EGameLiftServerState::Ready);
    }
#endif
}
#endif

#if WITH_GAMELIFT
void AShooterGameMode::HandleProcessTerminate()
{
#if WITH_GAMELIFT
    UE_LOG(GameServerLog, Warning, TEXT("Received termination request from GameLift"));

    bIsTerminating = true;
    TransitionToState(EGameLiftServerState::Terminating);

    // Save logs
    SaveServerLogs();

    // Clean up active session if needed
    if (bIsGameSessionActive)
    {
        CleanupGameSession();
    }

    // Notify GameLift we're shutting down
    FGameLiftGenericOutcome ProcessEndingOutcome = GameLiftModule->ProcessEnding();
    if (!ProcessEndingOutcome.IsSuccess())
    {
        FGameLiftError Error = ProcessEndingOutcome.GetError();
        UE_LOG(GameServerLog, Error, TEXT("ProcessEnding failed: %s"), *Error.m_errorMessage);
    }

    // Destroy SDK
    FGameLiftGenericOutcome DestroyOutcome = GameLiftModule->Destroy();
    if (!DestroyOutcome.IsSuccess())
    {
        FGameLiftError Error = DestroyOutcome.GetError();
        UE_LOG(GameServerLog, Error, TEXT("SDK Destroy failed: %s"), *Error.m_errorMessage);
    }

    TransitionToState(EGameLiftServerState::Shutdown);
#endif
}
#endif

#if WITH_GAMELIFT
bool AShooterGameMode::HandleHealthCheck()
{
    FScopeLock Lock(&StateLock);

    bool bIsHealthy = true;
    FString HealthDetails;

    // Don't report healthy during error or shutdown states
    if (ServerState == EGameLiftServerState::Error ||
        ServerState == EGameLiftServerState::Shutdown ||
        ServerState == EGameLiftServerState::Terminating)
    {
        bIsHealthy = false;
        HealthDetails = TEXT("Server in unhealthy state");
    }
    else
    {
        // Check memory health
        if (!CheckMemoryHealth())
        {
            bIsHealthy = false;
            HealthDetails += TEXT("High memory usage; ");
        }

        // Check game loop health
        if (!CheckGameLoopHealth())
        {
            bIsHealthy = false;
            HealthDetails += TEXT("Game loop stalled; ");
        }

        // Perform custom health checks
        if (!PerformCustomHealthCheck())
        {
            bIsHealthy = false;
            HealthDetails += TEXT("Custom health check failed; ");
        }
    }

    // Update statistics
    ServerStats.LastHealthCheckTime = FDateTime::Now();
    if (!bIsHealthy)
    {
        ServerStats.ConsecutiveHealthCheckFailures++;
        UE_LOG(GameServerLog, Warning, TEXT("Health check failed: %s"), *HealthDetails);
    }
    else
    {
        ServerStats.ConsecutiveHealthCheckFailures = 0;
        if (ServerConfig.bEnableDetailedLogging)
        {
            UE_LOG(GameServerLog, Verbose, TEXT("Health check passed"));
        }
    }

    // Broadcast health check result
    OnHealthCheckPerformed.Broadcast(bIsHealthy, HealthDetails);

    return bIsHealthy;
}
#endif

#if WITH_GAMELIFT
void AShooterGameMode::HandleGameSessionUpdate(const Aws::GameLift::Server::Model::UpdateGameSession& UpdateGameSession)
{
#if WITH_GAMELIFT
    UE_LOG(GameServerLog, Log, TEXT("Received game session update"));

    // Handle backfill ticket updates
    FString UpdateReason = FString(UpdateGameSession.GetUpdateReason());

    if (UpdateReason == TEXT("MATCHMAKING_DATA_UPDATED"))
    {
        // Handle matchmaking updates
        FString MatchmakingData = FString(UpdateGameSession.GetGameSession().GetMatchmakerData());
        if (ServerConfig.bEnableDetailedLogging)
        {
            UE_LOG(GameServerLog, Log, TEXT("Matchmaking data updated"));
        }
    }
#endif
}
#endif

// Health Monitoring
void AShooterGameMode::PerformHealthCheck()
{
#if WITH_GAMELIFT
    HandleHealthCheck();
#endif
}

void AShooterGameMode::UpdateServerStatistics()
{
    // Update tick rate
    if (TickCounter > 0)
    {
        float AverageTickTime = TickTimeAccumulator / TickCounter;
        float TickRate = 1.0f / FMath::Max(AverageTickTime, 0.001f);

        RecentTickRates.Add(TickRate);
        if (RecentTickRates.Num() > MAX_TICK_RATE_SAMPLES)
        {
            RecentTickRates.RemoveAt(0);
        }

        // Calculate average tick rate
        float TotalTickRate = 0.0f;
        for (float Rate : RecentTickRates)
        {
            TotalTickRate += Rate;
        }
        ServerStats.AverageTickRate = TotalTickRate / RecentTickRates.Num();

        // Reset counters
        TickTimeAccumulator = 0.0f;
        TickCounter = 0;
    }

    // Update memory usage
    const FPlatformMemoryStats MemStats = FPlatformMemory::GetStats();
    ServerStats.CurrentMemoryUsagePercent = (float)(MemStats.UsedPhysical) / (float)(MemStats.TotalPhysical) * 100.0f;

    // Record metrics
    RecordHealthMetric(TEXT("TickRate"), ServerStats.AverageTickRate);
    RecordHealthMetric(TEXT("MemoryUsage"), ServerStats.CurrentMemoryUsagePercent);
    RecordHealthMetric(TEXT("PlayerCount"), CurrentPlayerCount);
}

bool AShooterGameMode::CheckMemoryHealth()
{
    const FPlatformMemoryStats MemStats = FPlatformMemory::GetStats();
    float MemoryUsagePercent = (float)(MemStats.UsedPhysical) / (float)(MemStats.TotalPhysical) * 100.0f;

    if (MemoryUsagePercent > ServerConfig.MaxMemoryUsagePercent)
    {
        UE_LOG(GameServerLog, Warning, TEXT("High memory usage: %.2f%% (threshold: %.2f%%)"),
            MemoryUsagePercent, ServerConfig.MaxMemoryUsagePercent);
        return false;
    }

    return true;
}

bool AShooterGameMode::CheckGameLoopHealth()
{
    float CurrentTime = GetWorld()->GetTimeSeconds();
    float TimeSinceLastTick = CurrentTime - LastTickTime;

    if (TimeSinceLastTick > ServerConfig.MaxGameLoopStallSeconds)
    {
        UE_LOG(GameServerLog, Warning, TEXT("Game loop stall detected: %.2f seconds since last tick"),
            TimeSinceLastTick);
        return false;
    }

    return true;
}

void AShooterGameMode::RecordHealthMetric(const FString& MetricName, float Value)
{
    // This is where you would send metrics to CloudWatch or your monitoring system
    if (ServerConfig.bEnableDetailedLogging)
    {
        UE_LOG(GameServerLog, VeryVerbose, TEXT("Metric: %s = %.2f"), *MetricName, Value);
    }
}

// Player Management
void AShooterGameMode::PreLogin(const FString& Options, const FString& Address,
    const FUniqueNetIdRepl& UniqueId, FString& ErrorMessage)
{
    Super::PreLogin(Options, Address, UniqueId, ErrorMessage);

#if WITH_GAMELIFT
    if (!bIsGameSessionActive)
    {
        ErrorMessage = TEXT("No active game session");
        UE_LOG(GameServerLog, Warning, TEXT("Player connection rejected: %s"), *ErrorMessage);
        return;
    }

    // Extract player session ID from options
    FString PlayerSessionId;
    if (!FParse::Value(*Options, TEXT("PlayerSessionId="), PlayerSessionId))
    {
        ErrorMessage = TEXT("Missing PlayerSessionId");
        UE_LOG(GameServerLog, Warning, TEXT("Player connection rejected: %s"), *ErrorMessage);
        return;
    }

    // Validate with GameLift
    if (!AcceptPlayerSession(PlayerSessionId))
    {
        ErrorMessage = TEXT("Invalid PlayerSessionId");
        UE_LOG(GameServerLog, Warning, TEXT("Player connection rejected: %s"), *ErrorMessage);
        return;
    }
#endif
}

APlayerController* AShooterGameMode::Login(UPlayer* NewPlayer, ENetRole InRemoteRole,
    const FString& Portal, const FString& Options,
    const FUniqueNetIdRepl& UniqueId, FString& ErrorMessage)
{
    APlayerController* NewPlayerController = Super::Login(NewPlayer, InRemoteRole, Portal, Options, UniqueId, ErrorMessage);

    if (NewPlayerController)
    {
        FScopeLock Lock(&PlayerLock);

        // Extract player session ID
        FString PlayerSessionId;
        FParse::Value(*Options, TEXT("PlayerSessionId="), PlayerSessionId);

        if (!PlayerSessionId.IsEmpty())
        {
            PlayerSessions.Add(PlayerSessionId, NewPlayerController);
            CurrentPlayerCount++;
            ServerStats.TotalPlayersConnected++;

            UE_LOG(GameServerLog, Log, TEXT("Player joined: %s (Total: %d/%d)"),
                *PlayerSessionId, CurrentPlayerCount, MaxPlayers);

            OnPlayerJoinedSession.Broadcast(PlayerSessionId);
        }
    }

    return NewPlayerController;
}

void AShooterGameMode::Logout(AController* Exiting)
{
    if (APlayerController* PC = Cast<APlayerController>(Exiting))
    {
        FScopeLock Lock(&PlayerLock);

        // Find and remove player session
        FString PlayerSessionId;
        for (auto& Pair : PlayerSessions)
        {
            if (Pair.Value == PC)
            {
                PlayerSessionId = Pair.Key;
                PlayerSessions.Remove(PlayerSessionId);
                break;
            }
        }

        if (!PlayerSessionId.IsEmpty())
        {
            RemovePlayerSession(PlayerSessionId);
            CurrentPlayerCount = FMath::Max(0, CurrentPlayerCount - 1);

            UE_LOG(GameServerLog, Log, TEXT("Player left: %s (Remaining: %d/%d)"),
                *PlayerSessionId, CurrentPlayerCount, MaxPlayers);

            OnPlayerLeftSession.Broadcast(PlayerSessionId);
        }
    }

    Super::Logout(Exiting);
}

bool AShooterGameMode::AcceptPlayerSession(const FString& PlayerSessionId)
{
#if WITH_GAMELIFT
    if (!bIsGameSessionActive || !GameLiftModule)
    {
        return false;
    }

    FGameLiftGenericOutcome Outcome = GameLiftModule->AcceptPlayerSession(TCHAR_TO_UTF8(*PlayerSessionId));

    if (!Outcome.IsSuccess())
    {
        FGameLiftError Error = Outcome.GetError();
        UE_LOG(GameServerLog, Error, TEXT("AcceptPlayerSession failed for %s: %s"),
            *PlayerSessionId, *Error.m_errorMessage);
        return false;
    }

    return true;
#else
    return true;
#endif
}

bool AShooterGameMode::RemovePlayerSession(const FString& PlayerSessionId)
{
#if WITH_GAMELIFT
    if (!bIsGameSessionActive || !GameLiftModule)
    {
        return false;
    }

    FGameLiftGenericOutcome Outcome = GameLiftModule->RemovePlayerSession(TCHAR_TO_UTF8(*PlayerSessionId));

    if (!Outcome.IsSuccess())
    {
        FGameLiftError Error = Outcome.GetError();
        UE_LOG(GameServerLog, Error, TEXT("RemovePlayerSession failed for %s: %s"),
            *PlayerSessionId, *Error.m_errorMessage);
        return false;
    }

    return true;
#else
    return true;
#endif
}

void AShooterGameMode::UpdatePlayerSessionCreationPolicy(bool bAcceptingNewPlayers)
{
#if WITH_GAMELIFT
    if (!bIsGameSessionActive || !GameLiftModule)
    {
        return;
    }

    Aws::GameLift::Server::Model::PlayerSessionCreationPolicy Policy = bAcceptingNewPlayers ?
        Aws::GameLift::Server::Model::PlayerSessionCreationPolicy::ACCEPT_ALL :
        Aws::GameLift::Server::Model::PlayerSessionCreationPolicy::DENY_ALL;

    FGameLiftGenericOutcome Outcome = GameLiftModule->UpdatePlayerSessionCreationPolicy(Policy);

    if (!Outcome.IsSuccess())
    {
        FGameLiftError Error = Outcome.GetError();
        UE_LOG(GameServerLog, Error, TEXT("UpdatePlayerSessionCreationPolicy failed: %s"), *Error.m_errorMessage);
    }
    else
    {
        UE_LOG(GameServerLog, Log, TEXT("Player session creation policy updated: %s"),
            bAcceptingNewPlayers ? TEXT("ACCEPT_ALL") : TEXT("DENY_ALL"));
    }
#endif
}

void AShooterGameMode::RequestGameSessionTermination()
{
#if WITH_GAMELIFT
    if (!bIsGameSessionActive || !GameLiftModule)
    {
        return;
    }

    UE_LOG(GameServerLog, Log, TEXT("Requesting game session termination"));

    // Clean up the session
    CleanupGameSession();

    // Notify GameLift
    FGameLiftGenericOutcome Outcome = GameLiftModule->TerminateGameSession();

    if (!Outcome.IsSuccess())
    {
        FGameLiftError Error = Outcome.GetError();
        UE_LOG(GameServerLog, Error, TEXT("TerminateGameSession failed: %s"), *Error.m_errorMessage);
    }

    // Transition back to ready state
    TransitionToState(EGameLiftServerState::Ready);
#endif
}

// Cleanup
void AShooterGameMode::ShutdownGameLift()
{
#if WITH_GAMELIFT
    if (!GameLiftModule)
    {
        return;
    }

    UE_LOG(GameServerLog, Log, TEXT("Shutting down GameLift integration"));

    // Clean up active session
    if (bIsGameSessionActive)
    {
        CleanupGameSession();
    }

    // Notify GameLift if not already terminating
    if (!bIsTerminating && bIsGameLiftInitialized)
    {
        GameLiftModule->ProcessEnding();
        GameLiftModule->Destroy();
    }

    bIsGameLiftInitialized = false;
    GameLiftModule = nullptr;
#endif
}

void AShooterGameMode::CleanupGameSession()
{
    FScopeLock Lock(&SessionLock);

    if (bIsGameSessionActive)
    {
        UE_LOG(GameServerLog, Log, TEXT("Cleaning up game session: %s"), *CurrentGameSessionId);

        // Notify blueprints
        OnGameSessionTerminated.Broadcast(TEXT("Session ended"));

        // Call virtual function
        OnGameSessionEnded(TEXT("Session cleanup"));

        // Reset session state
        bIsGameSessionActive = false;
        CurrentGameSessionId.Empty();
        CurrentPlayerCount = 0;
        MaxPlayers = 0;
        GameSessionProperties.Empty();
        PlayerSessions.Empty();
    }
}

void AShooterGameMode::SaveServerLogs()
{
    // Implement log saving if needed
    UE_LOG(GameServerLog, Log, TEXT("Saving server logs..."));
}

// Virtual function implementations (to be overridden by game-specific code)
bool AShooterGameMode::ValidateGameSessionProperties(const TMap<FString, FString>& Properties)
{
    // Default implementation accepts all properties
    return true;
}

void AShooterGameMode::PrepareGameWorld(const TMap<FString, FString>& Properties)
{
    // Default implementation does nothing
    // Override this to set up your game world based on session properties
}

bool AShooterGameMode::IsGameWorldReady() const
{
    // Default implementation always returns true
    return true;
}

void AShooterGameMode::OnGameSessionStarted(const FString& SessionId)
{
    // Default implementation does nothing
    // Override this to perform game-specific session initialization
}

void AShooterGameMode::OnGameSessionEnded(const FString& Reason)
{
    // Default implementation does nothing
    // Override this to perform game-specific session cleanup
}

bool AShooterGameMode::PerformCustomHealthCheck()
{
    // Default implementation always returns true
    // Override this to implement game-specific health checks
    return true;
}
