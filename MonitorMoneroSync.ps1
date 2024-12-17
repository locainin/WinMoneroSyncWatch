param (
    [string]$LogFilePath,
    [string]$StallLogFilePath
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
        LogFilePath      = $LogFilePath
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
if ($savedConfig -ne $null) {
    if (-not $LogFilePath) { $LogFilePath = $savedConfig.LogFilePath }
    if (-not $StallLogFilePath) { $StallLogFilePath = $savedConfig.StallLogFilePath }
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

# Function to log and notify about stalled sync
function NotifyStalledSync {
    param (
        [int]$CurrentHeight,
        [int]$BlocksRemaining
    )
    if ($CurrentHeight -eq 0) { $CurrentHeight = "Unknown" }
    $stalledMessage = "Syncing has stalled at height $CurrentHeight with $BlocksRemaining blocks remaining."
    Write-Host $stalledMessage -ForegroundColor Red
    Add-Content -Path $StallLogFilePath -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - $stalledMessage"
}

# Function to monitor Monero sync logs and notify if stalled
function MonitorMoneroSync {
    $previousHeight = 0  # Track the last sync height
    $previousSyncPercentage = -1  # Track the last sync percentage
    $lastHeightUpdateTime = Get-Date  # Track the last time the height updated
    $fullySynced = $false           # Track if we've completed the initial full sync

    Get-Content $LogFilePath -Wait | ForEach-Object {
        $line = $_

        # Check for the Monero "synchronized" confirmation line
        if ($line -match 'You are now synchronized with the network') {
            $fullySynced = $true
            Write-Host "`nFully Synced! Your Monero node is now up-to-date with the network." -ForegroundColor Green
            Write-Host "Switching to monitoring mode to watch for new blocks..." -ForegroundColor Cyan
            $lastHeightUpdateTime = Get-Date
        }

        # If not fully synced, check for sync progress
        if (-not $fullySynced -and $line -match 'Synced (\d+)/(\d+) \((\d+)%, (\d+) left.*estimated ([\d\.]+) (\w+) left\)') {
            $currentHeight = [int]$Matches[1]
            $totalHeight = [int]$Matches[2]
            $syncPercentage = [int]$Matches[3]
            $blocksRemaining = [int]$Matches[4]
            $estimatedTimeLeft = [double]$Matches[5]
            $timeUnit = $Matches[6]

            # If height has not changed since the last update, consider the sync as stalled
            if ($currentHeight -eq $previousHeight) {
                NotifyStalledSync $currentHeight $blocksRemaining
            } else {
                $previousHeight = $currentHeight
            }

            # Only display the new percentage if it's increased
            if ($syncPercentage -gt $previousSyncPercentage) {
                Write-Host -NoNewline ("[ $syncPercentage% ] ") -ForegroundColor Green
                Write-Host -NoNewline ("Height: $currentHeight / $totalHeight - Remaining: $blocksRemaining blocks ") -ForegroundColor Red
                Write-Host ("- ETA: $estimatedTimeLeft $timeUnit") -ForegroundColor Cyan
                $previousSyncPercentage = $syncPercentage  # Update the previous sync percentage    
            }

            # Update the last height update time
            $lastHeightUpdateTime = Get-Date
        }

        # Monitoring mode: Watch for new blocks arriving (fully synced mode)
        if ($fullySynced -and $line -match 'Synced (\d+)/(\d+)') {
            $currentHeight = [int]$Matches[1]
            $totalHeight = [int]$Matches[2]
            Write-Host "New block detected: Height $currentHeight / $totalHeight" -ForegroundColor Green
            $lastHeightUpdateTime = Get-Date  # Reset monitoring time
        }
    }
}

# Run the monitoring function
MonitorMoneroSync
