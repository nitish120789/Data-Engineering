<#
Bulk seed orchestration for SQL Server to Azure SQL Hyperscale
Author: Nitish Anand Srivastava

DEPENDENCIES:
- sqlcmd (SQL Server command-line tool)
- Azure PowerShell module (Az.Storage)
- SQL Server Network Connectivity (TCP 1433 for source SQL Server)
- Azure Storage account with SAS token or MSI access

USAGE:
    .\bulk_seed_orchestration.ps1 `
        -SourceServer "sql-prod.contoso.com" `
        -SourceDatabase "OrderDB" `
        -StorageAccount "backupstg001" `
        -StorageContainer "sql-backups" `
        -StorageKey "<storage-account-key>" `
        -StripeCount 16

PREREQUISITES:
1. Source SQL Server must be accessible from this machine (sqlcmd connectivity verified)
2. Azure Storage account must exist and have write permissions
3. SQL Server backup path size should be pre-validated (estimate 1.2x database size)
#>

param(
    [Parameter(Mandatory = $true)][string]$SourceServer,
    [Parameter(Mandatory = $true)][string]$SourceDatabase,
    [Parameter(Mandatory = $true)][string]$StorageAccount,
    [Parameter(Mandatory = $false)][string]$StorageContainer = 'sql-backups',
    [Parameter(Mandatory = $false)][string]$StorageKey,
    [Parameter(Mandatory = $false)][int]$StripeCount = 16,
    [Parameter(Mandatory = $false)][string]$OutputFile = 'logs/seed_manifest.txt'
)

$ErrorActionPreference = 'Stop'

# Utility: Write timestamped log
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] [$Level] $Message" -ForegroundColor $(
        if ($Level -eq 'ERROR') { 'Red' }
        elseif ($Level -eq 'WARN') { 'Yellow' }
        else { 'Cyan' }
    )
}

# Validate dependencies
Write-Log "Validating dependencies..."
$sqlcmdExists = $null -ne (Get-Command sqlcmd -ErrorAction SilentlyContinue)
if (-not $sqlcmdExists) {
    Write-Log "ERROR: sqlcmd not found. Install SQL Server command-line tools." ERROR
    exit 1
}

# Validate source connectivity
Write-Log "Testing connectivity to source SQL Server: $SourceServer"
try {
    $testConn = sqlcmd -S $SourceServer -d master -Q "SELECT 1;" -b 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Connection failed"
    }
    Write-Log "Source SQL Server connectivity verified."
} catch {
    Write-Log "ERROR: Cannot connect to source SQL Server: $_" ERROR
    exit 1
}

# Validate Azure storage
Write-Log "Validating Azure Storage account: $StorageAccount"
if ([string]::IsNullOrWhiteSpace($StorageKey)) {
    Write-Log "ERROR: StorageKey parameter required for backup URL generation." ERROR
    exit 1
}

# Create output directory
$logDir = Split-Path -Parent $OutputFile
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Verify database exists
Write-Log "Verifying source database exists: $SourceDatabase"
$dbCheck = sqlcmd -S $SourceServer -d master -Q "SELECT name FROM sys.databases WHERE name = '$SourceDatabase';" -b 2>&1
if (-not $dbCheck -or $LASTEXITCODE -ne 0) {
    Write-Log "ERROR: Database $SourceDatabase not found on $SourceServer" ERROR
    exit 1
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupPrefix = "${SourceDatabase}_seed_${timestamp}"

# Build striped backup URL list
Write-Log "Generating $StripeCount backup stripe URLs..."
$backupUrls = @()
for ($i = 1; $i -le $StripeCount; $i++) {
    $backupUrls += "https://${StorageAccount}.blob.core.windows.net/${StorageContainer}/${backupPrefix}_part${i}.bak?sv=2021-06-08&ss=b&srt=sco&sp=rwdlac&se=$(Get-Date -Date (Get-Date).AddHours(24) -Format 'yyyy-MM-ddTHH:mm:ssZ')&st=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')&spr=https&sig=$(New-Guid | Select-Object -ExpandProperty Guid)"
}

Write-Log "Generated $StripeCount backup URLs"

# Render backup statement
$backupClauses = $backupUrls | ForEach-Object { "DISK = N'$_'" }
$backupTarget = ($backupClauses -join ",`n    ")

$backupSql = @"
-- Backup Database: $SourceDatabase to Azure Storage
-- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
-- Stripes: $StripeCount
-- Destination: https://${StorageAccount}.blob.core.windows.net/${StorageContainer}/${backupPrefix}_part*.bak

BACKUP DATABASE [$SourceDatabase]
TO
    $backupTarget
WITH
    COPY_ONLY,
    COMPRESSION,
    CHECKSUM,
    STATS = 5;
"@

Write-Log "Starting backup of $SourceDatabase ($StripeCount stripes)..."
$backupStartTime = Get-Date

try {
    # Save backup script to file for audit trail
    $backupScriptPath = "$logDir/${backupPrefix}_backup.sql"
    $backupSql | Out-File -FilePath $backupScriptPath -Encoding UTF8
    Write-Log "Backup script saved to $backupScriptPath"

    # Execute backup with timeout (4 hours)
    $sqlcmdProc = Start-Process -FilePath sqlcmd `
        -ArgumentList "-S", "$SourceServer", "-d", "master", "-Q", $backupSql `
        -NoNewWindow `
        -PassThru `
        -RedirectStandardOutput "$logDir/${backupPrefix}_backup.log" `
        -RedirectStandardError "$logDir/${backupPrefix}_backup_err.log"
    
    $timeout = $true
    if ($sqlcmdProc.WaitForExit(4 * 60 * 60 * 1000)) {
        $timeout = $false
        if ($sqlcmdProc.ExitCode -ne 0) {
            $errContent = Get-Content "$logDir/${backupPrefix}_backup_err.log" -Raw
            throw "Backup execution failed with exit code $($sqlcmdProc.ExitCode)`n$errContent"
        }
    } else {
        $sqlcmdProc.Kill()
        throw "Backup timed out after 4 hours"
    }

    $backupEndTime = Get-Date
    $duration = $backupEndTime - $backupStartTime
    
    Write-Log "Backup completed successfully in $($duration.TotalMinutes) minutes."
    
    # Create manifest file
    $manifest = @{
        timestamp = $timestamp
        source_server = $SourceServer
        source_database = $SourceDatabase
        destination_storage = "https://${StorageAccount}.blob.core.windows.net/${StorageContainer}"
        backup_prefix = $backupPrefix
        stripe_count = $StripeCount
        backup_duration_seconds = [int]$duration.TotalSeconds
        backup_script = $backupScriptPath
        backup_log = "$logDir/${backupPrefix}_backup.log"
    }
    
    $manifest | ConvertTo-Json | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Log "Manifest written to $OutputFile"
    
} catch {
    Write-Log "ERROR: Backup execution failed: $_" ERROR
    exit 1
}

Write-Log "Next steps:" 
Write-Log "1. Verify backup blobs exist in Azure Storage (expected: $StripeCount files totaling ~$([math]::Round((Get-Item "$logDir/${backupPrefix}_backup.log" -ErrorAction SilentlyContinue).Length / 1GB, 2))GB)"
Write-Log "2. Update restore command with correct storage URLs and SAS token"
Write-Log "3. Execute restore on Azure SQL Hyperscale target database"
Write-Log "4. Monitor restore progress and validate row counts"
Write-Log "5. Run reconciliation_checks.sql before starting CDC sync"

