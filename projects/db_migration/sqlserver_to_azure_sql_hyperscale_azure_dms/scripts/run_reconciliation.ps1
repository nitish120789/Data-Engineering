<#
Run reconciliation snapshots and compare for SQL Server -> Azure SQL Hyperscale (Azure DMS)
#>

param(
    [Parameter(Mandatory = $true)][string]$SourceServer,
    [Parameter(Mandatory = $true)][string]$TargetServer,
    [Parameter(Mandatory = $true)][string]$Database,
    [Parameter(Mandatory = $true)][string]$LinkedServerToSource,
    [Parameter(Mandatory = $false)][string]$RunId = ([guid]::NewGuid().ToString()),
    [Parameter(Mandatory = $false)][string]$ScriptPath = "scripts/exhaustive_reconciliation_and_hashing.sql",
    [Parameter(Mandatory = $false)][string]$LogDir = "logs"
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw 'sqlcmd not found. Install SQL Server command-line tools.'
}

if (-not (Test-Path $ScriptPath)) {
    throw "Script not found: $ScriptPath"
}

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

Write-Host "Using run_id: $RunId" -ForegroundColor Cyan

$sourceOut = Join-Path $LogDir "recon_source_${RunId}.log"
$targetOut = Join-Path $LogDir "recon_target_${RunId}.log"

Write-Host 'Capturing SOURCE snapshot...' -ForegroundColor Yellow
sqlcmd -S $SourceServer -d $Database -E -v RUN_ID="$RunId" ROLE="SOURCE" LINKED_SERVER="" SOURCE_DB="" -i $ScriptPath -o $sourceOut
if ($LASTEXITCODE -ne 0) {
    throw 'SOURCE reconciliation snapshot failed.'
}

Write-Host 'Capturing TARGET snapshot and running compare...' -ForegroundColor Yellow
sqlcmd -S $TargetServer -d $Database -G -v RUN_ID="$RunId" ROLE="TARGET" LINKED_SERVER="$LinkedServerToSource" SOURCE_DB="$Database" -i $ScriptPath -o $targetOut
if ($LASTEXITCODE -ne 0) {
    throw 'TARGET reconciliation snapshot/compare failed.'
}

Write-Host "Completed. Logs:" -ForegroundColor Green
Write-Host "- $sourceOut"
Write-Host "- $targetOut"
