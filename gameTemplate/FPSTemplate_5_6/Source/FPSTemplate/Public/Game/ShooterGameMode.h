// Fill out your copyright notice in the Description page of Project Settings.

#pragma once

#include "CoreMinimal.h"
#include "Game/ShooterGameModeBase.h"
#include "TimeManager.h"
#include "ShooterGameMode.generated.h"

#if WITH_GAMELIFT
#include "GameLiftServerSDK.h"
#include "GameLiftServerSDKModels.h"
#endif

struct FProcessParameters;
namespace Aws {
    namespace GameLift {
        namespace Server {
            namespace Model {
                class GameSession;
                class UpdateGameSession;
            }
        }
    }
}

DECLARE_LOG_CATEGORY_EXTERN(GameServerLog, Log, All);

// Delegate declarations for Blueprint integration
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnGameSessionActivated, const FString&, SessionId);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnGameSessionTerminated, const FString&, Reason);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnPlayerJoinedSession, const FString&, PlayerId);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnPlayerLeftSession, const FString&, PlayerId);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FOnHealthCheckPerformed, bool, bIsHealthy, const FString&, Details);

/**
 * Server state for GameLift integration
 */
UENUM(BlueprintType)
enum class EGameLiftServerState : uint8
{
    Uninitialized    UMETA(DisplayName = "Uninitialized"),
    Initializing     UMETA(DisplayName = "Initializing"),
    Ready           UMETA(DisplayName = "Ready"),
    ActivatingSession UMETA(DisplayName = "Activating Session"),
    InSession       UMETA(DisplayName = "In Session"),
    Terminating     UMETA(DisplayName = "Terminating"),
    Error           UMETA(DisplayName = "Error"),
    Shutdown        UMETA(DisplayName = "Shutdown")
};

/**
 * Configuration for GameLift server
 */
USTRUCT(BlueprintType)
struct FGameLiftServerConfig
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GameLift Config")
    int32 ServerPort = 7777;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GameLift Config")
    int32 MaxRetryAttempts = 3;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GameLift Config")
    float RetryDelaySeconds = 1.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GameLift Config")
    float RetryBackoffMultiplier = 2.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GameLift Config")
    float HealthCheckIntervalSeconds = 60.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GameLift Config")
    float MaxMemoryUsagePercent = 90.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GameLift Config")
    float MaxGameLoopStallSeconds = 5.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GameLift Config")
    bool bEnableDetailedLogging = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GameLift Config")
    bool bAutoShutdownOnTerminate = true;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GameLift Config")
    FString LogDirectory = TEXT("GameLiftUnrealApp/Saved/Logs/");

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GameLift Config")
    TArray<FString> AdditionalLogFiles;
};

/**
 * Runtime statistics for monitoring
 */
USTRUCT(BlueprintType)
struct FGameLiftServerStats
{
    GENERATED_BODY()

    UPROPERTY(BlueprintReadOnly, Category = "GameLift Stats")
    int32 TotalSessionsHosted = 0;

    UPROPERTY(BlueprintReadOnly, Category = "GameLift Stats")
    int32 TotalPlayersConnected = 0;

    UPROPERTY(BlueprintReadOnly, Category = "GameLift Stats")
    float CurrentMemoryUsagePercent = 0.0f;

    UPROPERTY(BlueprintReadOnly, Category = "GameLift Stats")
    float AverageTickRate = 0.0f;

    UPROPERTY(BlueprintReadOnly, Category = "GameLift Stats")
    FDateTime ServerStartTime;

    UPROPERTY(BlueprintReadOnly, Category = "GameLift Stats")
    FDateTime LastHealthCheckTime;

    UPROPERTY(BlueprintReadOnly, Category = "GameLift Stats")
    int32 ConsecutiveHealthCheckFailures = 0;
};


/**
 * 
 */
UCLASS()
class FPSTEMPLATE_API AShooterGameMode : public AShooterGameModeBase
{
	GENERATED_BODY()
	
public:
	AShooterGameMode();
    
    // Blueprint Events
    UPROPERTY(BlueprintAssignable, Category = "GameLift Events")
    FOnGameSessionActivated OnGameSessionActivated;

    UPROPERTY(BlueprintAssignable, Category = "GameLift Events")
    FOnGameSessionTerminated OnGameSessionTerminated;

    UPROPERTY(BlueprintAssignable, Category = "GameLift Events")
    FOnPlayerJoinedSession OnPlayerJoinedSession;

    UPROPERTY(BlueprintAssignable, Category = "GameLift Events")
    FOnPlayerLeftSession OnPlayerLeftSession;

    UPROPERTY(BlueprintAssignable, Category = "GameLift Events")
    FOnHealthCheckPerformed OnHealthCheckPerformed;

    // Blueprint callable functions
    UFUNCTION(BlueprintCallable, Category = "GameLift")
    EGameLiftServerState GetServerState() const { return ServerState; }

    UFUNCTION(BlueprintCallable, Category = "GameLift")
    bool IsGameSessionActive() const { return bIsGameSessionActive; }

    UFUNCTION(BlueprintCallable, Category = "GameLift")
    FString GetCurrentGameSessionId() const { return CurrentGameSessionId; }

    UFUNCTION(BlueprintCallable, Category = "GameLift")
    int32 GetCurrentPlayerCount() const { return CurrentPlayerCount; }

    UFUNCTION(BlueprintCallable, Category = "GameLift")
    int32 GetMaxPlayers() const { return MaxPlayers; }

    UFUNCTION(BlueprintCallable, Category = "GameLift")
    FGameLiftServerStats GetServerStats() const { return ServerStats; }

    UFUNCTION(BlueprintCallable, Category = "GameLift")
    bool AcceptPlayerSession(const FString& PlayerSessionId);

    UFUNCTION(BlueprintCallable, Category = "GameLift")
    bool RemovePlayerSession(const FString& PlayerSessionId);

    UFUNCTION(BlueprintCallable, Category = "GameLift")
    void UpdatePlayerSessionCreationPolicy(bool bAcceptingNewPlayers);

    UFUNCTION(BlueprintCallable, Category = "GameLift")
    void RequestGameSessionTermination();

protected:
    // Engine overrides
    virtual void BeginPlay() override;
    virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
    virtual void Tick(float DeltaSeconds) override;

    // Player connection handling
    virtual void PreLogin(const FString& Options, const FString& Address, const FUniqueNetIdRepl& UniqueId, FString& ErrorMessage) override;
    virtual APlayerController* Login(UPlayer* NewPlayer, ENetRole InRemoteRole, const FString& Portal, const FString& Options, const FUniqueNetIdRepl& UniqueId, FString& ErrorMessage) override;
    virtual void Logout(AController* Exiting) override;

    // Virtual functions for game-specific implementation
    virtual bool ValidateGameSessionProperties(const TMap<FString, FString>& Properties);
    virtual void PrepareGameWorld(const TMap<FString, FString>& Properties);
    virtual bool IsGameWorldReady() const;
    virtual void OnGameSessionStarted(const FString& SessionId);
    virtual void OnGameSessionEnded(const FString& Reason);
    virtual bool PerformCustomHealthCheck();

    // Configuration
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "GameLift Config")
    FGameLiftServerConfig ServerConfig;

private:
    // GameLift initialization
#if WITH_GAMELIFT
    void InitGameLift();
    void InitGameLiftWithRetry(int32 AttemptNumber = 0);
    void SetupGameLiftCallbacks();
    void ParseGameLiftAnywhereParameters(struct FServerParameters& OutParams);
    bool ValidateServerConfiguration();
#endif
    void ParseCommandLineArguments();

    // State management
    void TransitionToState(EGameLiftServerState NewState);
    bool CanTransitionToState(EGameLiftServerState NewState) const;
    void HandleStateTransition(EGameLiftServerState OldState, EGameLiftServerState NewState);

    // GameLift callbacks
#if WITH_GAMELIFT
    void HandleGameSessionStart(const Aws::GameLift::Server::Model::GameSession& GameSession);
    void HandleProcessTerminate();
    bool HandleHealthCheck();
    void HandleGameSessionUpdate(const Aws::GameLift::Server::Model::UpdateGameSession& UpdateGameSession);
#endif

    // Health monitoring
    void PerformHealthCheck();
    void UpdateServerStatistics();
    bool CheckMemoryHealth();
    bool CheckGameLoopHealth();
    void RecordHealthMetric(const FString& MetricName, float Value);

    // Cleanup
    void ShutdownGameLift();
    void CleanupGameSession();
    void SaveServerLogs();

    // Timer handles
    FTimerHandle HealthCheckTimerHandle;
    FTimerHandle StatisticsUpdateTimerHandle;
    FTimerHandle RetryInitTimerHandle;

    // Thread safety
    mutable FCriticalSection StateLock;
    mutable FCriticalSection SessionLock;
    mutable FCriticalSection PlayerLock;

    // State variables
    EGameLiftServerState ServerState;
    bool bIsGameLiftInitialized;
    bool bIsGameSessionActive;
    bool bIsTerminating;
    bool bIsAnywhereFleet;

    // Session management
    FString CurrentGameSessionId;
    int32 CurrentPlayerCount;
    int32 MaxPlayers;
    TMap<FString, FString> GameSessionProperties;
    TMap<FString, APlayerController*> PlayerSessions;

    // Statistics and monitoring
    FGameLiftServerStats ServerStats;
    float LastTickTime;
    float TickTimeAccumulator;
    int32 TickCounter;
    TArray<float> RecentTickRates;

    // GameLift SDK
#if WITH_GAMELIFT
    TSharedPtr<FProcessParameters> ProcessParameters;
    class FGameLiftServerSDKModule* GameLiftModule;
#endif

    // Error tracking
    FString LastErrorMessage;
    int32 ConsecutiveInitFailures;
    FDateTime LastInitAttemptTime;

    // Constants
    static constexpr int32 MAX_TICK_RATE_SAMPLES = 60;
    static constexpr float TICK_RATE_UPDATE_INTERVAL = 1.0f;
	
};
