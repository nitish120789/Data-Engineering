<#
Cutover orchestration skeleton for Azure DMS-based SQL Server migration
#>

param(
    [Parameter(Mandatory = $true)][string]$DmsTaskName,
    [Parameter(Mandatory = $true)][string]$LagCheckCommand,
    [Parameter(Mandatory = $true)][string]$FreezeWritesCommand,
    [Parameter(Mandatory = $true)][string]$FinalValidationCommand,
    [Parameter(Mandatory = $true)][string]$SwitchAppCommand,
    [Parameter(Mandatory = $true)][string]$RollbackCommand,
    [Parameter(Mandatory = $false)][int]$MaxWaitSeconds = 3600,
    [Parameter(Mandatory = $false)][int]$PollSeconds = 20
)

$ErrorActionPreference = 'Stop'

function Invoke-Step {
    param([string]$Name, [string]$Command)
    Write-Host "[STEP] $Name" -ForegroundColor Cyan
    Invoke-Expression $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Step failed: $Name"
    }
}

Write-Host "Starting cutover for DMS task: $DmsTaskName" -ForegroundColor Cyan

try {
    Invoke-Step -Name 'Freeze source writes' -Command $FreezeWritesCommand

    Write-Host 'Waiting for DMS lag to drain...' -ForegroundColor Yellow
    $elapsed = 0
    $lagReady = $false

    while ($elapsed -lt $MaxWaitSeconds) {
        Invoke-Expression $LagCheckCommand
        if ($LASTEXITCODE -eq 0) {
            $lagReady = $true
            break
        }

        Start-Sleep -Seconds $PollSeconds
        $elapsed += $PollSeconds
    }

    if (-not $lagReady) {
        throw "DMS lag did not drain within $MaxWaitSeconds seconds"
    }

    Invoke-Step -Name 'Run final reconciliation/validation gate' -Command $FinalValidationCommand
    Invoke-Step -Name 'Switch application to target' -Command $SwitchAppCommand

    Write-Host 'Cutover completed successfully.' -ForegroundColor Green
}
catch {
    Write-Host "Cutover failed: $_" -ForegroundColor Red
    Write-Host 'Executing rollback command...' -ForegroundColor Yellow
    Invoke-Expression $RollbackCommand
    throw
}
