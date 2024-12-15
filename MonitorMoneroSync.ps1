param (
    [string]$LogFilePath,
    [string]$StallLogFilePath,
    [int]$SyncTimeoutInSeconds = 300  # Default: 5 minutes
)

# Path to the configuration file
$configFilePath = "D:\Monero\sync_config.json"

# Function to save configuration
function Save-Config {
    param (
        [string]$LogFilePath,
        [string]$StallLogFilePath
    )

    $config = @{
        LogFilePath     = $LogFilePath
        StallLogFilePath = $StallLogFilePath
    }

    $config | ConvertTo-Json | Set-Content -Path $configFilePath
    Write-Host "Configuration saved to $configFilePath" -ForegroundColor Green
}

# Function to load configuration
function Load-Config {
    if (Test-Path $configFilePath) {
        return Get-Content -Path $configFilePath | ConvertFrom-Json
    }
    return $null
}

# Load saved configuration if it exists
$savedConfig = Load-Config

# Use saved paths if available; otherwise, prompt the user
if ($savedConfig -and (-not $LogFilePath)) {
    $LogFilePath = $savedConfig.LogFilePath
}
if ($savedConfig -and (-not $StallLogFilePath)) {
    $StallLogFilePath = $savedConfig.StallLogFilePath
}

# Prompt user for log file path if not already set
if (-not $LogFilePath) {
    $defaultLogFilePath = "C:\ProgramData\bitmonero\bitmonero.log"
    $LogFilePath = (Read-Host "Enter the path to your Monero log file (default: $defaultLogFilePath)") -replace '^\s+|\s+$'
    if (-not $LogFilePath) {
        $LogFilePath = $defaultLogFilePath
    }
}

# Prompt user for stalled sync log file path if not already set
if (-not $StallLogFilePath) {
    $defaultStallLogFilePath = "C:\ProgramData\bitmonero\bitmonero.log"
    $StallLogFilePath = (Read-Host "Enter the path to save stalled sync logs (default: $defaultStallLogFilePath)") -replace '^\s+|\s+$'
    if (-not $StallLogFilePath) {
        $StallLogFilePath = $defaultStallLogFilePath
    }
}

# Save the paths to the config file for future runs
Save-Config -LogFilePath $LogFilePath -StallLogFilePath $StallLogFilePath

# Validate the log file path exists
if (-Not (Test-Path $LogFilePath -PathType Leaf)) {
    Write-Host "Error: Log file path '$LogFilePath' does not exist. Please check the path and try again." -ForegroundColor Red
    exit
}

# Append default file name if `StallLogFilePath` is a directory
if (Test-Path $StallLogFilePath -PathType Container) {
    $StallLogFilePath = Join-Path -Path $StallLogFilePath -ChildPath "bitmonero.log"
    Write-Host "No file name specified for stalled sync logs. Using default: $StallLogFilePath" -ForegroundColor Yellow
}

# Function to monitor Monero sync logs and notify if stalled
function MonitorMoneroSync {
    $previousSyncPercentage = -1  # Track the last percentage
    $spinnerSymbols = @('|', '/', '-', '\')  # Spinner for dynamic effect
    $spinnerIndex = 0  # Spinner index
    $lastSyncUpdateTime = Get-Date  # Record the time of the last sync progress

    Get-Content $LogFilePath -Wait | ForEach-Object {
        if ($_ -match 'Synced (\d+)/(\d+) \((\d+)%, (\d+) left.*estimated ([\d\.]+) (\w+) left\)') {
            $currentHeight = [int]$Matches[1]
            $totalHeight = [int]$Matches[2]
            $syncPercentage = [int]$Matches[3]
            $blocksRemaining = [int]$Matches[4]
            $estimatedTimeLeft = [double]$Matches[5]
            $timeUnit = $Matches[6]

            # Update the last sync update time
            $lastSyncUpdateTime = Get-Date

            # Only display output if the percentage has increased
            if ($syncPercentage -gt $previousSyncPercentage) {
                $previousSyncPercentage = $syncPercentage
                Write-Host -NoNewline ("$($spinnerSymbols[$spinnerIndex % $spinnerSymbols.Length]) ") -ForegroundColor Yellow
                Write-Host -NoNewline ("[ $syncPercentage% ] ") -ForegroundColor Green
                Write-Host -NoNewline ("Height: $currentHeight / $totalHeight - Remaining: $blocksRemaining blocks ") -ForegroundColor Red
                Write-Host ("- ETA: $estimatedTimeLeft $timeUnit") -ForegroundColor Cyan
                $spinnerIndex++
            }
        }

        # Check if syncing has stalled
        $timeSinceLastUpdate = (Get-Date) - $lastSyncUpdateTime
        if ($timeSinceLastUpdate.TotalSeconds -gt $SyncTimeoutInSeconds) {
            NotifyStalledSync $currentHeight $blocksRemaining
            $lastSyncUpdateTime = Get-Date  # Prevent duplicate notifications
        }
    }
}

# Function to log and notify about stalled sync
function NotifyStalledSync {
    param (
        [int]$CurrentHeight,
        [int]$BlocksRemaining
    )
    $stalledMessage = "Syncing has stalled at height $CurrentHeight with $BlocksRemaining blocks remaining."
    Write-Host $stalledMessage -ForegroundColor Red
    Add-Content -Path $StallLogFilePath -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - $stalledMessage"
}

# Run the monitoring function
MonitorMoneroSync
