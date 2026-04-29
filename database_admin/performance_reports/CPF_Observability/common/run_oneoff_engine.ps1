param(
    [Parameter(Mandatory = $true)]
    [string]$Engine,

    [Parameter(Mandatory = $true)]
    [string]$EngineRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$configFile = Join-Path $EngineRoot 'config/default.env'
$snapshotSql = Join-Path $EngineRoot 'snapshots/snapshot_queries.sql'
$reportBuilder = Join-Path $PSScriptRoot 'report_builder_stub.py'
$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')

$snapshotDir = Join-Path $EngineRoot 'data/snapshots'
$reportDir = Join-Path $EngineRoot 'data/reports'
$logDir = Join-Path $EngineRoot 'logs'
$logFile = Join-Path $logDir 'cpf.log'
$snapshotOut = Join-Path $snapshotDir ("snapshot_{0}.txt" -f $timestamp)
$reportTxt = Join-Path $reportDir ("report_{0}.txt" -f $timestamp)
$reportHtml = Join-Path $reportDir ("report_{0}.html" -f $timestamp)

$snapshotDir, $reportDir, $logDir | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
}

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format s) $Message"
    Add-Content -Path $logFile -Value $line
    Write-Output $Message
}

function Load-Config {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#') -or -not $line.Contains('=')) { return }
        $parts = $line.Split('=', 2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
}

function Add-Section {
    param(
        [string]$Title,
        [scriptblock]$Body
    )

    Add-Content -Path $reportTxt -Value ""
    Add-Content -Path $reportTxt -Value ("## {0}" -f $Title)
    Add-Content -Path $reportTxt -Value ""

    try {
        $output = & $Body 2>&1 | Out-String
        Add-Content -Path $reportTxt -Value $output
    }
    catch {
        Add-Content -Path $reportTxt -Value 'Section unavailable on this server/version or insufficient privileges.'
        Add-Content -Path $reportTxt -Value ""
        Add-Content -Path $logFile -Value ("{0} {1}" -f (Get-Date -Format s), $_.Exception.Message)
    }
}

function Invoke-SqlServerQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [string]$Username,

        [string]$Password,

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [string]$TrustServerCertificate = 'true'
    )

    $args = @('-S', $Server, '-d', $Database, '-W', '-w', '512', '-s', '|', '-Q', "SET NOCOUNT ON; $Query")
    if ($Username -and $Password) {
        $args += @('-U', $Username, '-P', $Password)
    }
    else {
        $args += '-E'
    }

    if ($TrustServerCertificate -eq 'true') {
        $args += '-C'
    }

    & sqlcmd @args
}

function Invoke-MySqlQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerHost,

        [Parameter(Mandatory = $true)]
        [string]$Port,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [string]$Username,

        [string]$Password,

        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    $mysqlCmd = Get-Command mysql -ErrorAction SilentlyContinue
    if ($mysqlCmd) {
        $prevPwd = [System.Environment]::GetEnvironmentVariable('MYSQL_PWD', 'Process')
        if ($Password) {
            [System.Environment]::SetEnvironmentVariable('MYSQL_PWD', $Password, 'Process')
        }

        try {
            $cmdArgs = @('-h', $ServerHost, '-P', $Port, '--connect-timeout=5', '--table', '--column-names', '-e', $Query)
            if ($Username) { $cmdArgs += @('-u', $Username) }
            if ($Database) { $cmdArgs += @('-D', $Database) }

            & mysql @cmdArgs
            return
        }
        finally {
            if ($prevPwd) {
                [System.Environment]::SetEnvironmentVariable('MYSQL_PWD', $prevPwd, 'Process')
            }
            else {
                [System.Environment]::SetEnvironmentVariable('MYSQL_PWD', $null, 'Process')
            }
        }
    }

    # Fallback path when mysql.exe is not installed on the host.
    $managedReadyVar = Get-Variable -Name MySqlManagedReady -Scope Script -ErrorAction SilentlyContinue
    if (-not $managedReadyVar -or -not [bool]$managedReadyVar.Value) {
        $pkgRoot = Join-Path $env:TEMP 'cpf_mysql_managed'
        New-Item -ItemType Directory -Path $pkgRoot -Force | Out-Null

        $packages = @(
            @{ Name = 'MySql.Data'; Version = '8.0.33' },
            @{ Name = 'System.Threading.Tasks.Extensions'; Version = '4.5.4' },
            @{ Name = 'System.Memory'; Version = '4.5.4' },
            @{ Name = 'System.Buffers'; Version = '4.5.1' },
            @{ Name = 'System.Runtime.CompilerServices.Unsafe'; Version = '4.5.3' }
        )

        foreach ($pkg in $packages) {
            $name = $pkg.Name
            $version = $pkg.Version
            $nupkg = Join-Path $pkgRoot ("{0}.{1}.nupkg" -f $name, $version)
            $zip = Join-Path $pkgRoot ("{0}.{1}.zip" -f $name, $version)
            $outDir = Join-Path $pkgRoot ("{0}.{1}" -f $name, $version)
            if (-not (Test-Path $outDir)) {
                if (-not (Test-Path $nupkg)) {
                    $url = "https://www.nuget.org/api/v2/package/{0}/{1}" -f $name, $version
                    Invoke-WebRequest -Uri $url -OutFile $nupkg -UseBasicParsing
                }
                Copy-Item $nupkg $zip -Force
                Expand-Archive -Path $zip -DestinationPath $outDir -Force
            }
        }

        $deps = @(
            (Join-Path $pkgRoot 'System.Runtime.CompilerServices.Unsafe.4.5.3\lib\net461\System.Runtime.CompilerServices.Unsafe.dll'),
            (Join-Path $pkgRoot 'System.Buffers.4.5.1\lib\net461\System.Buffers.dll'),
            (Join-Path $pkgRoot 'System.Memory.4.5.4\lib\net461\System.Memory.dll'),
            (Join-Path $pkgRoot 'System.Threading.Tasks.Extensions.4.5.4\lib\net461\System.Threading.Tasks.Extensions.dll')
        )
        foreach ($dep in $deps) {
            if (Test-Path $dep) {
                try { [System.Reflection.Assembly]::LoadFrom($dep) | Out-Null } catch { }
            }
        }

        $mysqlDll = Join-Path $pkgRoot 'MySql.Data.8.0.33\lib\net462\MySql.Data.dll'
        try {
            Add-Type -Path $mysqlDll -ErrorAction Stop
        }
        catch {
            if (-not ('MySql.Data.MySqlClient.MySqlConnection' -as [type])) {
                throw
            }
        }
        $script:MySqlManagedReady = $true
    }

    $csb = New-Object System.Text.StringBuilder
    [void]$csb.Append("Server=$ServerHost;")
    [void]$csb.Append("Port=$Port;")
    if ($Database) { [void]$csb.Append("Database=$Database;") }
    if ($Username) { [void]$csb.Append("Uid=$Username;") }
    if ($Password) { [void]$csb.Append("Pwd=$Password;") }
    [void]$csb.Append('Connection Timeout=8;Default Command Timeout=120;SslMode=None;')

    $conn = New-Object MySql.Data.MySqlClient.MySqlConnection($csb.ToString())
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        $reader = $cmd.ExecuteReader()
        $output = New-Object System.Collections.Generic.List[string]
        do {
            if ($reader.FieldCount -le 0) { continue }

            $headers = @()
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $headers += $reader.GetName($i)
            }
            $output.Add(($headers -join ' | '))
            $output.Add((@($headers | ForEach-Object { '---' }) -join ' | '))

            $rowCount = 0
            while ($reader.Read()) {
                $row = @()
                for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                    if ($reader.IsDBNull($i)) { $row += 'NULL' }
                    else {
                        $v = $reader.GetValue($i).ToString().Replace("`r", ' ').Replace("`n", ' ')
                        $row += $v
                    }
                }
                $output.Add(($row -join ' | '))
                $rowCount++
            }
            if ($rowCount -eq 0) { $output.Add('(no rows)') }
            $output.Add('')
        } while ($reader.NextResult())

        return ($output -join [Environment]::NewLine)
    }
    finally {
        $conn.Close()
    }
}

function Convert-ReportTextToHtml {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Engine,

        [Parameter(Mandatory = $true)]
        [string]$ReportText
    )

    function Escape-Html {
        param([string]$Value)
        return [System.Net.WebUtility]::HtmlEncode(($Value | Out-String).TrimEnd())
    }

    function Parse-Sections {
        param([string]$Text)

        $sections = New-Object System.Collections.Generic.List[object]
        $title = 'Overview'
        $buffer = New-Object System.Collections.Generic.List[string]

        foreach ($line in ($Text -split "`r?`n")) {
            if ($line.StartsWith('## ')) {
                $sections.Add([pscustomobject]@{ Title = $title; Content = (($buffer -join "`n").Trim()) })
                $title = $line.Substring(3).Trim()
                $buffer = New-Object System.Collections.Generic.List[string]
            }
            else {
                $buffer.Add($line)
            }
        }

        $sections.Add([pscustomobject]@{ Title = $title; Content = (($buffer -join "`n").Trim()) })
        return $sections | Where-Object { $_.Title -or $_.Content }
    }

    function Parse-Blocks {
        param([string]$Content)

        $blocks = New-Object System.Collections.Generic.List[object]
        $parts = [regex]::Split($Content.Trim(), "(?:`r?`n){2,}")
        foreach ($part in $parts) {
            $trimmed = $part.Trim()
            if (-not $trimmed) { continue }

            $lines = $trimmed -split "`r?`n"
            $isTable = $lines.Count -ge 2 -and $lines[0].Contains('|') -and (($lines[1] -replace '[|\s]', '') -match '^-+$')
            if ($isTable) {
                $headers = $lines[0].Split('|') | ForEach-Object { $_.Trim() }
                $rows = New-Object System.Collections.Generic.List[object]
                for ($idx = 2; $idx -lt $lines.Count; $idx++) {
                    if (-not $lines[$idx].Contains('|')) { continue }
                    $cells = $lines[$idx].Split('|') | ForEach-Object { $_.Trim() }
                    if ($cells.Count -eq $headers.Count) {
                        $rows.Add($cells)
                    }
                }
                if ($rows.Count -gt 0) {
                    $blocks.Add([pscustomobject]@{ Type = 'table'; Headers = $headers; Rows = $rows })
                    continue
                }
            }

            $blocks.Add([pscustomobject]@{ Type = 'text'; Content = $trimmed })
        }

        return $blocks
    }

    function Get-SectionSummary {
        param(
            [string]$Title,
            [string]$Content
        )

        $lowerTitle = $Title.ToLowerInvariant()
        $lowerContent = $Content.ToLowerInvariant()
        if ($lowerTitle.Contains('wait') -and -not $lowerTitle.Contains('lock wait')) { return 'Primary wait pressure across tasks, categories, and active chains.' }
        if ($lowerTitle.Contains('statement wait')) { return 'Performance Schema wait events sorted by cumulative wait time - analogous to AWR Top Wait Events.' }
        if ($lowerTitle.Contains('ash') -or $lowerTitle.Contains('active sessions') -or $lowerTitle.Contains('active requests')) { return 'Current workload sample showing in-flight statements, waits, and session state.' }
        if ($lowerTitle.Contains('cpu') -or $lowerTitle.Contains('duration') -or $lowerTitle.Contains('read and write')) { return 'High-cost statements ranked by resource consumption and elapsed impact.' }
        if ($lowerTitle.Contains('rows examined') -or $lowerTitle.Contains('execution count') -or $lowerTitle.Contains('temp disk') -or $lowerTitle.Contains('errors')) { return 'High-cost SQL ranked by a secondary resource or error dimension.' }
        if ($lowerTitle.Contains('lock wait') -or $lowerTitle.Contains('blocking') -or $lowerTitle.Contains('deadlock') -or $lowerTitle.Contains('transaction')) { return 'Concurrency diagnostics: lock waits, deadlocks, blocking chains, and open transactions.' }
        if ($lowerTitle.Contains('buffer pool')) { return 'InnoDB buffer pool utilization, hit ratio, and dirty page pressure.' }
        if ($lowerTitle.Contains('innodb io') -or $lowerTitle.Contains('log pressure')) { return 'InnoDB IO, redo log, and page operation pressure indicators.' }
        if ($lowerTitle.Contains('memory') -or $lowerTitle.Contains('tempdb')) { return 'Memory grant, buffer, and workspace pressure indicators.' }
        if ($lowerTitle.Contains('table io')) { return 'Per-table read/write latency - analogous to AWR Segment IO statistics.' }
        if ($lowerTitle.Contains('wal') -or $lowerTitle.Contains('checkpoint')) { return 'WAL generation and checkpoint behavior indicating write pressure and durability cadence.' }
        if ($lowerTitle.Contains('vacuum') -or $lowerTitle.Contains('analyze')) { return 'Autovacuum and statistics maintenance posture for bloat and planner stability.' }
        if ($lowerTitle.Contains('slot health')) { return 'Replication slot and stream health, including lag and retention risk indicators.' }
        if ($lowerTitle.Contains('sga') -or $lowerTitle.Contains('pga')) { return 'Oracle memory pool sizing and pressure indicators across SGA/PGA components.' }
        if ($lowerTitle.Contains('tablespace')) { return 'Tablespace usage posture and free-space pressure hotspots.' }
        if ($lowerTitle.Contains('undo')) { return 'Undo retention pressure and transaction rollback segment health signals.' }
        if ($lowerTitle.Contains('long operations')) { return 'In-progress long operations useful for runtime bottleneck triage.' }
        if ($lowerTitle.Contains('io') -or $lowerTitle.Contains('log')) { return 'Storage latency, file pressure, and recovery/log utilization signals.' }
        if ($lowerTitle.Contains('replication') -or $lowerTitle.Contains('replica') -or $lowerTitle.Contains('alwayson')) { return 'Replication/availability synchronization and replica health status.' }
        if ($lowerTitle.Contains('binary log')) { return 'Binary log status, GTID state, and log file inventory.' }
        if ($lowerTitle.Contains('query store')) { return 'Plan/runtime history useful for regression and outlier detection.' }
        if ($lowerTitle.Contains('throughput') -or $lowerTitle.Contains('workload')) { return 'Aggregate workload throughput counters since last restart.' }
        if ($lowerTitle.Contains('schema') -or $lowerTitle.Contains('inventory')) { return 'Object inventory, sizing, and storage allocation.' }
        if ($lowerTitle.Contains('user') -or $lowerTitle.Contains('host activity') -or $lowerTitle.Contains('session mix')) { return 'User/host session distribution and activity breakdown.' }
        if ($lowerTitle.Contains('configuration') -or $lowerTitle.Contains('server config')) { return 'Key server configuration parameters affecting performance and durability.' }
        if ($lowerContent.Contains('section unavailable')) { return 'This section could not be collected on the target due to permissions or feature availability.' }
        return 'Detailed engine telemetry captured for this diagnostic slice.'
    }

    $sections = Parse-Sections -Text $ReportText
    $generated = (Get-Date).ToUniversalTime().ToString('o')
    $findings = New-Object System.Collections.Generic.List[string]
    $lowerReport = $ReportText.ToLowerInvariant()
    if ($lowerReport.Contains('section unavailable')) { $findings.Add('Some sections were unavailable due to privileges, feature flags, or engine/version differences.') }
    if ($lowerReport.Contains('deadlock')) { $findings.Add('Deadlock signals were detected; review lock chains and top contending statements.') }
    if ($lowerReport.Contains('innodb_deadlocks') -or $lowerReport.Contains('innodb_row_lock_waits')) { $findings.Add('InnoDB deadlock or row lock wait pressure detected; investigate lock order and transaction scope.') }
    if ($lowerReport.Contains('created_tmp_disk_tables')) { $findings.Add('Temporary disk table usage detected; consider raising tmp_table_size/max_heap_table_size.') }
    if ($lowerReport.Contains('innodb_log_waits')) { $findings.Add('InnoDB log wait pressure present; consider increasing innodb_log_buffer_size.') }
    if ($lowerReport.Contains('select_full_join') -or $lowerReport.Contains('no_index_used')) { $findings.Add('Full-table scan or no-index-used signals present; review query plans and index coverage.') }
    if ($lowerReport.Contains('replication') -or $lowerReport.Contains('replica')) { $findings.Add('Replication data present; validate replica lag and IO/SQL thread state.') }
    if ($lowerReport.Contains('wal_buffers_full') -or $lowerReport.Contains('checkpoints_req')) { $findings.Add('PostgreSQL WAL/checkpoint pressure signals detected; review checkpoint cadence and write bursts.') }
    if ($lowerReport.Contains('n_dead_tup') -or $lowerReport.Contains('autovacuum')) { $findings.Add('Table bloat or autovacuum pressure may be present; inspect dead tuples and vacuum throughput.') }
    if ($lowerReport.Contains('over allocation count') -or $lowerReport.Contains('aggregate pga')) { $findings.Add('Oracle PGA pressure indicators detected; validate memory targets and workarea policy.') }
    if ($lowerReport.Contains('used_percent') -and $lowerReport.Contains('tablespace')) { $findings.Add('Tablespace utilization data present; review high used-percent tablespaces for capacity risk.') }
    if ($lowerReport.Contains('blocking_session_id') -or $lowerReport.Contains('head blocker')) { $findings.Add('Blocking chain data is present; check head blockers, transaction scope, and lock duration.') }
    if ($lowerReport.Contains('memory grants pending') -or $lowerReport.Contains('resource_semaphore')) { $findings.Add('Memory grant pressure indicators are present; inspect grant queues and large query concurrency.') }
    if ($lowerReport.Contains('pageiolatch') -or $lowerReport.Contains('writelog') -or $lowerReport.Contains('io/log')) { $findings.Add('IO or log-write pressure indicators are present; correlate file latency with top read/write statements.') }
    if ($lowerReport.Contains('query store')) { $findings.Add('Query Store data is available; compare runtime outliers and plan regressions against recent change windows.') }
    if ($findings.Count -eq 0) { $findings.Add('No explicit high-risk indicators were auto-detected; validate against workload SLO baselines.') }

    $overviewPairs = @()
    if ($sections.Count -gt 0) {
        foreach ($line in ($sections[0].Content -split "`r?`n")) {
            if ($line -match '^([^:]+):\s+(.+)$') {
                $overviewPairs += ,@($matches[1].Trim(), $matches[2].Trim())
            }
        }
    }

    $tocBuilder = New-Object System.Text.StringBuilder
    $bodyBuilder = New-Object System.Text.StringBuilder
    for ($idx = 0; $idx -lt $sections.Count; $idx++) {
        $section = $sections[$idx]
        $anchor = "sec-$($idx + 1)"
        [void]$tocBuilder.Append("<li><a href='#$anchor'>$(Escape-Html $section.Title)</a></li>")

        $contentBuilder = New-Object System.Text.StringBuilder
        foreach ($block in (Parse-Blocks -Content $section.Content)) {
            if ($block.Type -eq 'text') {
                [void]$contentBuilder.Append("<pre>$(Escape-Html $block.Content)</pre>")
                continue
            }

            $headerHtml = (($block.Headers | ForEach-Object { "<th>$(Escape-Html $_)</th>" }) -join '')
            $rowHtml = New-Object System.Text.StringBuilder
            foreach ($row in $block.Rows) {
                $cellHtml = (($row | ForEach-Object { "<td>$(Escape-Html $_)</td>" }) -join '')
                [void]$rowHtml.Append("<tr>$cellHtml</tr>")
            }
            [void]$contentBuilder.Append("<div class='table-wrap'><table><thead><tr>$headerHtml</tr></thead><tbody>$rowHtml</tbody></table></div>")
        }

        [void]$bodyBuilder.Append(@"
<section id='$anchor' class='card'>
  <div class='section-head'>
    <h3>$(Escape-Html $section.Title)</h3>
    <p>$(Escape-Html (Get-SectionSummary -Title $section.Title -Content $section.Content))</p>
  </div>
  $contentBuilder
</section>
"@)
    }

    $metricHtml = New-Object System.Text.StringBuilder
    if ($overviewPairs.Count -gt 0) {
        foreach ($pair in ($overviewPairs | Select-Object -First 4)) {
            [void]$metricHtml.Append("<div class='metric'><div class='metric-label'>$(Escape-Html $pair[0])</div><div class='metric-value'>$(Escape-Html $pair[1])</div></div>")
        }
    }
    else {
        [void]$metricHtml.Append("<div class='metric'><div class='metric-label'>Engine</div><div class='metric-value'>$(Escape-Html $Engine)</div></div>")
    }

    $findingsHtml = (($findings | ForEach-Object { "<li>$(Escape-Html $_)</li>" }) -join '')
    $unavailableCount = ([regex]::Matches($lowerReport, 'section unavailable')).Count

    return @"
<!doctype html>
<html lang='en'>
<head>
  <meta charset='utf-8' />
  <meta name='viewport' content='width=device-width, initial-scale=1' />
  <title>CPF AWR-Style Report - $(Escape-Html $Engine)</title>
  <style>
    :root { --bg: #f4efe6; --panel: #fffdf8; --panel-strong: #fffaf0; --fg: #172033; --muted: #5f6476; --border: #dfd3bf; --accent: #92400e; --accent-2: #0f766e; --accent-3: #1d4ed8; --shadow: 0 18px 40px rgba(23, 32, 51, 0.08); }
    * { box-sizing: border-box; }
    body { margin: 0; background: radial-gradient(circle at top left, #fff7e8 0, #f4efe6 45%, #ede5d7 100%); color: var(--fg); font-family: Segoe UI, Arial, sans-serif; }
    .wrap { max-width: 1560px; margin: 0 auto; padding: 28px; }
    .hero { background: linear-gradient(135deg, rgba(255, 250, 240, 0.96), rgba(243, 248, 255, 0.96)); border: 1px solid var(--border); border-radius: 22px; padding: 28px; box-shadow: var(--shadow); }
    .hero-grid { display: grid; grid-template-columns: 1.5fr 1fr; gap: 18px; align-items: start; }
    .hero-copy p { margin: 12px 0 0 0; max-width: 70ch; color: var(--muted); line-height: 1.5; }
    .badge { display: inline-flex; align-items: center; gap: 6px; border-radius: 999px; padding: 6px 10px; font-size: 12px; background: #fef3c7; color: #92400e; border: 1px solid #f1d18a; margin-bottom: 10px; }
    h1 { margin: 0 0 10px 0; font-size: 34px; line-height: 1.1; }
    h3 { margin: 0; }
    .meta { color: var(--muted); font-size: 13px; margin-top: 6px; }
    .metric-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
    .metric { background: rgba(255,255,255,0.7); border: 1px solid var(--border); border-radius: 16px; padding: 14px; }
    .metric-label { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.08em; }
    .metric-value { margin-top: 6px; font-weight: 700; font-size: 18px; word-break: break-word; }
    .summary-strip { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; margin-top: 18px; }
    .summary-card { background: var(--panel-strong); border: 1px solid var(--border); border-radius: 14px; padding: 14px; }
    .summary-card strong { display: block; font-size: 24px; margin-top: 6px; }
    .grid { display: grid; grid-template-columns: 320px 1fr; gap: 18px; margin-top: 18px; align-items: start; }
    .sidebar { position: sticky; top: 16px; }
    .card { background: var(--panel); border: 1px solid var(--border); border-radius: 18px; padding: 16px; margin-bottom: 16px; box-shadow: var(--shadow); }
    .section-head { display: flex; justify-content: space-between; align-items: start; gap: 16px; margin-bottom: 14px; }
    .section-head p { margin: 0; color: var(--muted); max-width: 70ch; line-height: 1.45; }
    .table-wrap { overflow-x: auto; border: 1px solid var(--border); border-radius: 14px; background: #fff; margin-bottom: 12px; }
    table { width: 100%; border-collapse: collapse; font-size: 12px; }
    th { background: #f8edd8; color: var(--fg); text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--border); white-space: nowrap; }
    td { padding: 10px 12px; border-bottom: 1px solid #eee3d3; vertical-align: top; }
    tbody tr:nth-child(even) { background: #fffaf1; }
    pre { margin: 0 0 12px 0; white-space: pre-wrap; word-break: break-word; font-family: Consolas, 'Courier New', monospace; font-size: 12px; line-height: 1.45; background: #fff; border: 1px solid var(--border); border-radius: 12px; padding: 12px; }
    a { color: var(--accent-3); text-decoration: none; }
    a:hover { text-decoration: underline; }
    .muted { color: var(--muted); }
    @media (max-width: 1180px) { .hero-grid, .grid, .summary-strip { grid-template-columns: 1fr; } .sidebar { position: static; } }
    @media (max-width: 720px) { .wrap { padding: 16px; } .metric-grid { grid-template-columns: 1fr; } h1 { font-size: 28px; } .section-head { display: block; } .summary-strip { grid-template-columns: 1fr 1fr; } }
  </style>
</head>
<body>
  <div class='wrap'>
    <div class='hero'>
      <div class='hero-grid'>
        <div class='hero-copy'>
          <div class='badge'>AWR / ASH analogue for $(Escape-Html $Engine)</div>
          <h1>CPF Observability Performance Report</h1>
          <div class='meta'>Generated at $(Escape-Html $generated) UTC</div>
          <div class='meta'>Single-run deep diagnostic report with structured DMV, Query Store, IO, wait, memory, concurrency, and availability sections.</div>
          <p>This report is organized to resemble the operator flow of an AWR-style review: start with identity and configuration, move through wait and resource pressure, then inspect active workload, top SQL, contention, storage, and HA state.</p>
        </div>
        <div class='metric-grid'>$metricHtml</div>
      </div>
      <div class='summary-strip'>
        <div class='summary-card'><span class='muted'>Sections</span><strong>$($sections.Count)</strong></div>
        <div class='summary-card'><span class='muted'>Auto Findings</span><strong>$($findings.Count)</strong></div>
        <div class='summary-card'><span class='muted'>Unavailable Sections</span><strong>$unavailableCount</strong></div>
        <div class='summary-card'><span class='muted'>Render Mode</span><strong>Structured HTML</strong></div>
      </div>
    </div>
    <div class='grid'>
      <aside class='sidebar'>
        <div class='card'><h3>Auto Findings</h3><ul>$findingsHtml</ul></div>
        <div class='card'><h3>Recommendations</h3><p>Prioritize sections with elevated wait, lock, IO, memory, or error signals; compare against previous runs and correlate with deployment and traffic changes in the report window.</p></div>
        <div class='card'><h3>Sections</h3><ol>$tocBuilder</ol></div>
      </aside>
      <main>$bodyBuilder</main>
    </div>
  </div>
</body>
</html>
"@
}

function Build-Header {
    param([string]$Target)

    @(
        'CPF Observability AWR-Style Detailed Performance Report',
        "Engine: $Engine",
        "Generated (UTC): $timestamp",
        "Host context: $Target",
        '',
        'Sections marked unavailable indicate missing permissions, feature flags, or version differences.'
    ) | Set-Content -Path $reportTxt
}

Load-Config -Path $configFile

$dbHost = [System.Environment]::GetEnvironmentVariable('DB_HOST', 'Process')
if (-not $dbHost) { $dbHost = '127.0.0.1' }
$dbPort = [System.Environment]::GetEnvironmentVariable('DB_PORT', 'Process')
$dbUser = [System.Environment]::GetEnvironmentVariable('DB_USER', 'Process')
$dbName = [System.Environment]::GetEnvironmentVariable('DB_NAME', 'Process')
$dbPassword = [System.Environment]::GetEnvironmentVariable('DB_PASSWORD', 'Process')

if (-not $dbPort) {
    switch ($Engine) {
        'postgresql' { $dbPort = '5432' }
        'aurora_postgresql' { $dbPort = '5432' }
        'mysql' { $dbPort = '3306' }
        'aurora_mysql' { $dbPort = '3306' }
        'aws_rds' { $dbPort = '3306' }
        'sqlserver' { $dbPort = '1433' }
        'azure_sql_db' { $dbPort = '1433' }
        'oracle' { $dbPort = '1521' }
        'redis' { $dbPort = '6379' }
        'clickhouse' { $dbPort = '9000' }
        'cassandra' { $dbPort = '9042' }
        default { $dbPort = '' }
    }
}

$target = if ($dbName) { "$dbUser@$dbHost`:$dbPort/$dbName" } else { "$dbHost`:$dbPort" }
if (-not $dbUser) { $target = "$dbHost`:$dbPort" }
Build-Header -Target $target

Write-Log "Running one-off snapshot at $timestamp"
Write-Log "Target: $target"

switch ($Engine) {
    'mysql' {
        # Engine-specific vars take priority; DB_HOST/DB_PORT/DB_USER/DB_PASSWORD are generic fallbacks
        $mysqlSpecHost = [System.Environment]::GetEnvironmentVariable('MYSQL_HOST', 'Process')
        if ($mysqlSpecHost) { $dbHost = $mysqlSpecHost }
        elseif (-not $dbHost -or $dbHost -eq '127.0.0.1') {
            $genericHost = [System.Environment]::GetEnvironmentVariable('DB_HOST', 'Process')
            if ($genericHost) { $dbHost = $genericHost } else { $dbHost = '127.0.0.1' }
        }

        $mysqlSpecPort = [System.Environment]::GetEnvironmentVariable('MYSQL_PORT', 'Process')
        if ($mysqlSpecPort) { $dbPort = $mysqlSpecPort }
        elseif (-not $dbPort) { $dbPort = '3306' }

        $mysqlSpecUser = [System.Environment]::GetEnvironmentVariable('MYSQL_USER', 'Process')
        if ($mysqlSpecUser) { $dbUser = $mysqlSpecUser }
        elseif (-not $dbUser) { $dbUser = 'root' }

        $mysqlSpecPwd = [System.Environment]::GetEnvironmentVariable('MYSQL_PASSWORD', 'Process')
        if ($mysqlSpecPwd) { $dbPassword = $mysqlSpecPwd }

        $mysqlSpecDb = [System.Environment]::GetEnvironmentVariable('MYSQL_DATABASE', 'Process')
        if ($mysqlSpecDb) { $dbName = $mysqlSpecDb }
        elseif (-not $dbName) { $dbName = 'performance_schema' }


        Add-Section 'Instance Identity and Version' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT NOW() AS collected_at_utc, @@hostname AS hostname, @@port AS port, @@version AS version, @@version_comment AS flavor, @@read_only AS read_only, @@global.gtid_mode AS gtid_mode" }
        Add-Section 'Server Configuration Key Variables' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SHOW GLOBAL VARIABLES WHERE Variable_name IN ('max_connections','max_allowed_packet','innodb_buffer_pool_size','innodb_buffer_pool_instances','innodb_log_file_size','innodb_log_buffer_size','innodb_flush_method','innodb_flush_log_at_trx_commit','sync_binlog','binlog_format','slow_query_log','long_query_time','table_open_cache','thread_cache_size','wait_timeout','interactive_timeout','transaction_isolation','innodb_io_capacity','innodb_io_capacity_max','innodb_read_io_threads','innodb_write_io_threads','innodb_autoinc_lock_mode')" }
        Add-Section 'Database Inventory and Size' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT table_schema AS db_name, COUNT(*) AS table_count, ROUND(SUM(data_length)/1024/1024,2) AS data_mb, ROUND(SUM(index_length)/1024/1024,2) AS index_mb, ROUND(SUM(data_length+index_length)/1024/1024,2) AS total_mb, ROUND(SUM(data_free)/1024/1024,2) AS free_mb FROM information_schema.tables WHERE table_schema NOT IN ('performance_schema','information_schema','sys','mysql') GROUP BY table_schema ORDER BY total_mb DESC" }
        Add-Section 'Connection Pressure and Session Mix' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SHOW GLOBAL STATUS WHERE Variable_name IN ('Uptime','Threads_running','Threads_connected','Threads_cached','Max_used_connections','Connections','Aborted_connects','Aborted_clients','Connection_errors_max_connections'); SELECT USER, HOST, DB, COMMAND, COUNT(*) AS cnt FROM information_schema.processlist GROUP BY USER, HOST, DB, COMMAND ORDER BY cnt DESC LIMIT 20" }
        Add-Section 'Workload Throughput Counters' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SHOW GLOBAL STATUS WHERE Variable_name IN ('Queries','Questions','Com_select','Com_insert','Com_update','Com_delete','Com_replace','Com_commit','Com_rollback','Com_begin','Slow_queries','Handler_read_key','Handler_read_next','Handler_read_rnd','Handler_read_rnd_next','Select_full_join','Select_scan','Select_range')" }
        Add-Section 'Temporary Objects and Sort Pressure' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SHOW GLOBAL STATUS WHERE Variable_name IN ('Created_tmp_tables','Created_tmp_disk_tables','Created_tmp_files','Sort_rows','Sort_merge_passes','Sort_scan','Sort_range')" }
        Add-Section 'InnoDB Buffer Pool Health' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_buffer_pool_read_requests','Innodb_buffer_pool_reads','Innodb_buffer_pool_pages_total','Innodb_buffer_pool_pages_free','Innodb_buffer_pool_pages_dirty','Innodb_buffer_pool_wait_free','Innodb_buffer_pool_write_requests','Innodb_buffer_pool_pages_flushed'); SELECT ROUND(100*(1 - SUM(IF(VARIABLE_NAME='Innodb_buffer_pool_reads',VARIABLE_VALUE,0)) / NULLIF(SUM(IF(VARIABLE_NAME='Innodb_buffer_pool_read_requests',VARIABLE_VALUE,0)),0)),4) AS buffer_pool_hit_pct FROM performance_schema.global_status WHERE VARIABLE_NAME IN ('Innodb_buffer_pool_reads','Innodb_buffer_pool_read_requests')" }
        Add-Section 'InnoDB IO and Log Pressure' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_data_reads','Innodb_data_writes','Innodb_data_fsyncs','Innodb_data_pending_reads','Innodb_data_pending_writes','Innodb_log_waits','Innodb_log_writes','Innodb_log_write_requests','Innodb_os_log_written','Innodb_os_log_fsyncs','Innodb_pages_read','Innodb_pages_written','Innodb_pages_created','Innodb_rows_read','Innodb_rows_inserted','Innodb_rows_updated','Innodb_rows_deleted')" }
        Add-Section 'Statement Wait Events' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT EVENT_NAME, COUNT_STAR AS wait_count, ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_wait_s, ROUND(AVG_TIMER_WAIT/1000000000,3) AS avg_wait_ms, ROUND(MAX_TIMER_WAIT/1000000000,3) AS max_wait_ms FROM performance_schema.events_waits_summary_global_by_event_name WHERE COUNT_STAR > 0 AND EVENT_NAME NOT LIKE '%idle%' ORDER BY SUM_TIMER_WAIT DESC LIMIT 30" }
        Add-Section 'Lock Wait and Deadlock Counters' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_row_lock_current_waits','Innodb_row_lock_waits','Innodb_row_lock_time','Innodb_row_lock_time_avg','Innodb_row_lock_time_max','Innodb_deadlocks','Table_locks_waited','Table_locks_immediate')" }
        Add-Section 'Active Sessions (ASH Analogue)' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT ID, USER, HOST, DB, COMMAND, TIME, STATE, LEFT(INFO, 320) AS SQL_TEXT FROM information_schema.processlist WHERE COMMAND <> 'Sleep' ORDER BY TIME DESC LIMIT 30" }
        Add-Section 'Active Lock Wait Chains' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT r.trx_id AS waiting_trx_id, b.trx_id AS blocking_trx_id, r.trx_mysql_thread_id AS waiting_thread, b.trx_mysql_thread_id AS blocking_thread, TIMESTAMPDIFF(SECOND, r.trx_started, NOW()) AS waiting_seconds, LEFT(r.trx_query, 240) AS waiting_query, LEFT(b.trx_query, 240) AS blocking_query FROM information_schema.innodb_lock_waits w JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id ORDER BY waiting_seconds DESC LIMIT 20" }
        Add-Section 'Long-Running Transactions' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT trx_id, trx_mysql_thread_id AS thread_id, trx_state, trx_started, TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS age_seconds, trx_rows_locked, trx_rows_modified, LEFT(trx_query, 240) AS sql_text, trx_operation_state, trx_tables_in_use, trx_tables_locked FROM information_schema.innodb_trx ORDER BY trx_started ASC LIMIT 20" }
        Add-Section 'Top SQL by Total Time' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT LEFT(DIGEST_TEXT, 240) AS sql_text, SCHEMA_NAME AS db, COUNT_STAR AS exec_count, ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_s, ROUND(AVG_TIMER_WAIT/1000000000,3) AS avg_ms, ROUND(MAX_TIMER_WAIT/1000000000,3) AS max_ms, SUM_ROWS_EXAMINED AS rows_examined, SUM_NO_INDEX_USED AS no_index_used FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_TIMER_WAIT DESC LIMIT 25" }
        Add-Section 'Top SQL by Execution Count' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT LEFT(DIGEST_TEXT, 240) AS sql_text, SCHEMA_NAME AS db, COUNT_STAR AS exec_count, ROUND(AVG_TIMER_WAIT/1000000000,3) AS avg_ms, SUM_ROWS_EXAMINED AS total_rows_examined, SUM_NO_INDEX_USED AS no_index_used FROM performance_schema.events_statements_summary_by_digest ORDER BY COUNT_STAR DESC LIMIT 25" }
        Add-Section 'Top SQL by Rows Examined' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT LEFT(DIGEST_TEXT, 240) AS sql_text, SCHEMA_NAME AS db, COUNT_STAR AS exec_count, SUM_ROWS_EXAMINED AS total_rows_examined, ROUND(SUM_ROWS_EXAMINED/NULLIF(COUNT_STAR,0),0) AS avg_rows_examined, SUM_NO_INDEX_USED AS no_index_used, ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_s FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_ROWS_EXAMINED DESC LIMIT 25" }
        Add-Section 'Top SQL by Temp Disk Tables' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT LEFT(DIGEST_TEXT, 240) AS sql_text, SCHEMA_NAME AS db, COUNT_STAR AS exec_count, SUM_CREATED_TMP_DISK_TABLES AS tmp_disk_tables, SUM_CREATED_TMP_TABLES AS tmp_tables, ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_s, SUM_SORT_MERGE_PASSES AS sort_merge_passes FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_CREATED_TMP_DISK_TABLES DESC LIMIT 20" }
        Add-Section 'Top SQL by Errors and Warnings' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT LEFT(DIGEST_TEXT, 240) AS sql_text, SCHEMA_NAME AS db, COUNT_STAR AS exec_count, SUM_ERRORS AS total_errors, SUM_WARNINGS AS total_warnings, SUM_ROWS_EXAMINED AS rows_examined FROM performance_schema.events_statements_summary_by_digest WHERE SUM_ERRORS > 0 OR SUM_WARNINGS > 0 ORDER BY SUM_ERRORS DESC, SUM_WARNINGS DESC LIMIT 20" }
        Add-Section 'Table IO Latency' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT OBJECT_SCHEMA AS db, OBJECT_NAME AS table_name, COUNT_READ, COUNT_WRITE, COUNT_FETCH, COUNT_INSERT, COUNT_UPDATE, COUNT_DELETE, ROUND(SUM_TIMER_READ/1000000000000,3) AS total_read_s, ROUND(SUM_TIMER_WRITE/1000000000000,3) AS total_write_s FROM performance_schema.table_io_waits_summary_by_table WHERE OBJECT_SCHEMA NOT IN ('performance_schema','information_schema','sys','mysql') AND (COUNT_READ + COUNT_WRITE) > 0 ORDER BY (SUM_TIMER_READ + SUM_TIMER_WRITE) DESC LIMIT 30" }
        Add-Section 'User and Host Activity Summary' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT USER, HOST, DB, SUM(CASE WHEN COMMAND='Query' THEN 1 ELSE 0 END) AS active_queries, SUM(CASE WHEN COMMAND='Sleep' THEN 1 ELSE 0 END) AS idle_sessions, COUNT(*) AS total_sessions, MAX(TIME) AS max_query_time_s FROM information_schema.processlist GROUP BY USER, HOST, DB ORDER BY total_sessions DESC, active_queries DESC LIMIT 20" }
        Add-Section 'Schema Size and Top Tables' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SELECT table_schema AS db, table_name, engine, table_rows, ROUND(data_length/1024/1024,2) AS data_mb, ROUND(index_length/1024/1024,2) AS index_mb, ROUND((data_length+index_length)/1024/1024,2) AS total_mb, ROUND(data_free/1024/1024,2) AS free_mb FROM information_schema.tables WHERE table_schema NOT IN ('performance_schema','information_schema','sys','mysql') ORDER BY (data_length+index_length) DESC LIMIT 30" }
        Add-Section 'Binary Log and GTID Status' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SHOW MASTER STATUS; SHOW BINARY LOGS" }
        Add-Section 'Replication Status (MySQL 8+)' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SHOW REPLICA STATUS" }
        Add-Section 'Replication Status (MySQL 5.7 Legacy)' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SHOW SLAVE STATUS" }
        Add-Section 'InnoDB Engine Status' { Invoke-MySqlQuery -ServerHost $dbHost -Port $dbPort -Database $dbName -Username $dbUser -Password $dbPassword -Query "SHOW ENGINE INNODB STATUS" }
    }
    'aurora_mysql' { 
        & $PSCommandPath -Engine 'mysql' -EngineRoot $EngineRoot
        exit $LASTEXITCODE
    }
    'aws_rds' {
        & $PSCommandPath -Engine 'mysql' -EngineRoot $EngineRoot
        exit $LASTEXITCODE
    }
    'postgresql' {
        $dbUser = if ($dbUser) { $dbUser } else { 'postgres' }
        $dbName = if ($dbName) { $dbName } else { 'postgres' }
        if ($dbPassword) { $env:PGPASSWORD = $dbPassword }

        Add-Section 'Instance Identity and Version' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT now() AS collected_at_utc, inet_server_addr() AS server_ip, inet_server_port() AS server_port, version();" }
        Add-Section 'Server Configuration Key Parameters' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT name, setting, unit, context, source FROM pg_settings WHERE name IN ('max_connections','shared_buffers','effective_cache_size','work_mem','maintenance_work_mem','wal_level','max_wal_size','checkpoint_timeout','checkpoint_completion_target','random_page_cost','effective_io_concurrency','autovacuum','autovacuum_max_workers','autovacuum_naptime','track_io_timing') ORDER BY name;" }
        Add-Section 'Database Inventory and Size' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT d.datname, pg_catalog.pg_get_userbyid(d.datdba) AS owner, d.datistemplate, d.datallowconn, pg_size_pretty(pg_database_size(d.datname)) AS db_size, s.numbackends FROM pg_database d LEFT JOIN pg_stat_database s ON d.datname = s.datname ORDER BY pg_database_size(d.datname) DESC;" }
        Add-Section 'Connection Pressure and Session Mix' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT now() - pg_postmaster_start_time() AS uptime, (SELECT setting::int FROM pg_settings WHERE name='max_connections') AS max_connections, (SELECT count(*) FROM pg_stat_activity) AS current_connections, (SELECT count(*) FROM pg_stat_activity WHERE state='active') AS active_connections; SELECT usename, application_name, client_addr, state, COUNT(*) AS sessions FROM pg_stat_activity GROUP BY usename, application_name, client_addr, state ORDER BY sessions DESC LIMIT 30;" }
        Add-Section 'Workload Throughput and Transaction Counters' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT datname, xact_commit, xact_rollback, tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted, blks_read, blks_hit, temp_files, temp_bytes, deadlocks FROM pg_stat_database ORDER BY xact_commit + xact_rollback DESC LIMIT 30;" }
        Add-Section 'Temporary Objects and Sort Pressure' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT datname, temp_files, pg_size_pretty(temp_bytes) AS temp_bytes, blk_read_time, blk_write_time FROM pg_stat_database ORDER BY temp_bytes DESC LIMIT 20;" }
        Add-Section 'Buffer Cache and IO Hit Ratios' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT datname, ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_pct, blks_read, blks_hit FROM pg_stat_database ORDER BY cache_hit_pct ASC NULLS LAST;" }
        Add-Section 'WAL and Checkpoint Pressure' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT checkpoints_timed, checkpoints_req, checkpoint_write_time, checkpoint_sync_time, buffers_checkpoint, buffers_clean, maxwritten_clean, buffers_backend, buffers_backend_fsync, buffers_alloc FROM pg_stat_bgwriter; SELECT wal_records, wal_fpi, wal_bytes, wal_buffers_full, stats_reset FROM pg_stat_wal;" }
        Add-Section 'Wait Event Profile' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT wait_event_type, wait_event, COUNT(*) AS session_count FROM pg_stat_activity WHERE wait_event_type IS NOT NULL GROUP BY wait_event_type, wait_event ORDER BY session_count DESC, wait_event_type LIMIT 30;" }
        Add-Section 'Active Sessions (ASH Analogue)' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT pid, usename, datname, application_name, client_addr, backend_type, state, wait_event_type, wait_event, now() - query_start AS duration, LEFT(query, 320) AS query FROM pg_stat_activity WHERE state <> 'idle' ORDER BY duration DESC LIMIT 40;" }
        Add-Section 'Blocking Chains' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT blocked.pid AS blocked_pid, blocker.pid AS blocker_pid, blocked.usename AS blocked_user, blocker.usename AS blocker_user, blocked.wait_event_type AS blocked_wait_type, blocked.wait_event AS blocked_wait_event, now() - blocked.query_start AS blocked_for, LEFT(blocked.query, 220) AS blocked_query, LEFT(blocker.query, 220) AS blocker_query FROM pg_stat_activity blocked JOIN pg_stat_activity blocker ON blocker.pid = ANY(pg_blocking_pids(blocked.pid)) ORDER BY blocked_for DESC LIMIT 30;" }
        Add-Section 'Long-Running Transactions' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT pid, usename, datname, state, now() - xact_start AS xact_age, now() - query_start AS query_age, wait_event_type, wait_event, LEFT(query, 320) AS query FROM pg_stat_activity WHERE xact_start IS NOT NULL ORDER BY xact_start ASC LIMIT 30;" }
        Add-Section 'Top SQL by Total Time' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT queryid, calls, ROUND(total_exec_time::numeric,2) AS total_ms, ROUND(mean_exec_time::numeric,2) AS mean_ms, ROUND(max_exec_time::numeric,2) AS max_ms, rows, LEFT(query, 240) AS query FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 25;" }
        Add-Section 'Top SQL by Execution Count' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT queryid, calls, ROUND(mean_exec_time::numeric,2) AS mean_ms, ROUND(total_exec_time::numeric,2) AS total_ms, LEFT(query, 240) AS query FROM pg_stat_statements ORDER BY calls DESC LIMIT 25;" }
        Add-Section 'Top SQL by Shared Block Reads' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT queryid, calls, shared_blks_read, shared_blks_hit, temp_blks_read, temp_blks_written, ROUND(total_exec_time::numeric,2) AS total_ms, LEFT(query, 240) AS query FROM pg_stat_statements ORDER BY shared_blks_read DESC LIMIT 25;" }
        Add-Section 'Top SQL by Temp Blocks' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT queryid, calls, temp_blks_read, temp_blks_written, ROUND(total_exec_time::numeric,2) AS total_ms, LEFT(query, 240) AS query FROM pg_stat_statements ORDER BY (temp_blks_read + temp_blks_written) DESC LIMIT 20;" }
        Add-Section 'Table IO and Heap/Index Access' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT relname, seq_scan, seq_tup_read, idx_scan, idx_tup_fetch, n_tup_ins, n_tup_upd, n_tup_del, n_dead_tup, vacuum_count, autovacuum_count FROM pg_stat_user_tables ORDER BY (seq_tup_read + idx_tup_fetch) DESC LIMIT 30;" }
        Add-Section 'Index Usage and Bloat Indicators' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT schemaname, relname, indexrelname, idx_scan, idx_tup_read, idx_tup_fetch, pg_size_pretty(pg_relation_size(indexrelid)) AS index_size FROM pg_stat_user_indexes ORDER BY idx_scan ASC, pg_relation_size(indexrelid) DESC LIMIT 30;" }
        Add-Section 'Vacuum and Analyze Health' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum, last_analyze, last_autoanalyze, vacuum_count, autovacuum_count, analyze_count, autoanalyze_count FROM pg_stat_user_tables ORDER BY n_dead_tup DESC NULLS LAST LIMIT 30; SELECT pid, datname, relid::regclass AS relation, phase, heap_blks_total, heap_blks_scanned, heap_blks_vacuumed, index_vacuum_count, max_dead_tuples, num_dead_tuples FROM pg_stat_progress_vacuum;" }
        Add-Section 'Lock Inventory and Contention' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT locktype, mode, granted, COUNT(*) AS lock_count FROM pg_locks GROUP BY locktype, mode, granted ORDER BY lock_count DESC;" }
        Add-Section 'Replication and Slot Health' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT application_name, client_addr, state, sync_state, write_lag, flush_lag, replay_lag, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication; SELECT slot_name, slot_type, active, restart_lsn, wal_status, safe_wal_size FROM pg_replication_slots;" }
    }
    'aurora_postgresql' {
        & $PSCommandPath -Engine 'postgresql' -EngineRoot $EngineRoot
        exit $LASTEXITCODE
    }
    'sqlserver' {
        $dbHost = if ($dbHost) { $dbHost } else { [System.Environment]::GetEnvironmentVariable('SQLSERVER_HOST', 'Process') }
        if (-not $dbHost) { $dbHost = '127.0.0.1' }

        $dbPort = if ($dbPort) { $dbPort } else { [System.Environment]::GetEnvironmentVariable('SQLSERVER_PORT', 'Process') }
        if (-not $dbPort) { $dbPort = '1433' }

        $dbUser = if ($dbUser) { $dbUser } else { [System.Environment]::GetEnvironmentVariable('SQLSERVER_USER', 'Process') }
        $dbPassword = if ($dbPassword) { $dbPassword } else { [System.Environment]::GetEnvironmentVariable('SQLSERVER_PASSWORD', 'Process') }
        $dbName = if ($dbName) { $dbName } else { [System.Environment]::GetEnvironmentVariable('SQLSERVER_DATABASE', 'Process') }
        if (-not $dbName) { $dbName = 'master' }

        $sqlServerTrustCert = [System.Environment]::GetEnvironmentVariable('SQLSERVER_TRUST_CERT', 'Process')
        if (-not $sqlServerTrustCert) { $sqlServerTrustCert = 'true' }

        $server = "$dbHost,$dbPort"
        Add-Section 'Instance Identity and Version' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT GETUTCDATE() AS collected_at_utc, @@SERVERNAME AS server_name, SERVERPROPERTY('MachineName') AS machine_name, SERVERPROPERTY('Edition') AS edition, SERVERPROPERTY('ProductVersion') AS product_version, SERVERPROPERTY('ProductLevel') AS product_level, SERVERPROPERTY('EngineEdition') AS engine_edition, @@VERSION AS version;" }
        Add-Section 'Uptime, Build, and Server Configuration' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT sqlserver_start_time, cpu_count, scheduler_count, hyperthread_ratio, physical_memory_kb/1024 AS physical_memory_mb, committed_kb/1024 AS committed_memory_mb, committed_target_kb/1024 AS committed_target_mb FROM sys.dm_os_sys_info; SELECT name, value_in_use FROM sys.configurations WHERE name IN ('max degree of parallelism','cost threshold for parallelism','max server memory (MB)','min server memory (MB)','optimize for ad hoc workloads','backup compression default','query wait (s)','remote admin connections') ORDER BY name;" }
        Add-Section 'Database Inventory and Recovery Posture' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT d.name, d.state_desc, d.recovery_model_desc, d.compatibility_level, d.log_reuse_wait_desc, d.page_verify_option_desc, d.delayed_durability_desc, d.is_auto_create_stats_on, d.is_auto_update_stats_on, d.snapshot_isolation_state_desc, d.is_read_committed_snapshot_on FROM sys.databases d ORDER BY d.name;" }
        Add-Section 'Connection Pressure and Session Mix' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT COUNT(*) AS current_sessions, SUM(CASE WHEN is_user_process = 1 THEN 1 ELSE 0 END) AS user_sessions, SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) AS running_sessions, SUM(CASE WHEN status = 'sleeping' THEN 1 ELSE 0 END) AS sleeping_sessions, SUM(CASE WHEN open_transaction_count > 0 THEN 1 ELSE 0 END) AS sessions_with_open_txn FROM sys.dm_exec_sessions; SELECT TOP 20 login_name, host_name, program_name, COUNT(*) AS session_count FROM sys.dm_exec_sessions WHERE is_user_process = 1 GROUP BY login_name, host_name, program_name ORDER BY session_count DESC;" }
        Add-Section 'Workload Throughput Counters' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT object_name, counter_name, instance_name, cntr_value FROM sys.dm_os_performance_counters WHERE counter_name IN ('Batch Requests/sec','SQL Compilations/sec','SQL Re-Compilations/sec','User Connections','Processes blocked','Page life expectancy','Memory Grants Pending','Memory Grants Outstanding','Lazy writes/sec','Checkpoint pages/sec','Forwarded Records/sec','Full Scans/sec','Page reads/sec','Page writes/sec') ORDER BY counter_name, instance_name;" }
        Add-Section 'Scheduler and CPU Pressure' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT scheduler_id, cpu_id, status, is_online, current_tasks_count, runnable_tasks_count, current_workers_count, active_workers_count, load_factor, work_queue_count FROM sys.dm_os_schedulers WHERE scheduler_id < 255 ORDER BY runnable_tasks_count DESC, current_tasks_count DESC;" }
        Add-Section 'Memory Grants and Buffer Health' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT TOP 20 request_time, grant_time, requested_memory_kb, granted_memory_kb, ideal_memory_kb, required_memory_kb, wait_time_ms, queue_id, dop, timeout_sec, resource_semaphore_id FROM sys.dm_exec_query_memory_grants ORDER BY requested_memory_kb DESC; SELECT counter_name, cntr_value FROM sys.dm_os_performance_counters WHERE counter_name IN ('Page life expectancy','Buffer cache hit ratio','Target Server Memory (KB)','Total Server Memory (KB)','Free list stalls/sec');" }
        Add-Section 'Waits by Category' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "WITH waits AS ( SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms, CASE WHEN wait_type LIKE 'LCK[_]%' THEN 'Lock' WHEN wait_type LIKE 'PAGEIOLATCH[_]%' OR wait_type LIKE 'IO[_]%' OR wait_type IN ('WRITELOG','LOGBUFFER') THEN 'IO/Log' WHEN wait_type LIKE 'CX%' OR wait_type LIKE 'CXSYNC[_]%' THEN 'Parallelism' WHEN wait_type LIKE 'RESOURCE[_]SEMAPHORE%' OR wait_type LIKE 'MEMORY[_]%' THEN 'Memory' WHEN wait_type LIKE 'SOS[_]SCHEDULER[_]YIELD' OR wait_type LIKE 'THREADPOOL' THEN 'CPU/Scheduler' WHEN wait_type LIKE 'HADR[_]%' THEN 'HADR' WHEN wait_type LIKE 'PAGELATCH[_]%' THEN 'Latch' ELSE 'Other' END AS wait_category FROM sys.dm_os_wait_stats WHERE wait_type NOT IN ('CLR_AUTO_EVENT','CLR_MANUAL_EVENT','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK','SLEEP_SYSTEMTASK','SQLTRACE_BUFFER_FLUSH','WAITFOR','LOGMGR_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT','BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_SEMAPHORE','DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION','ONDEMAND_TASK_QUEUE','FT_IFTS_SCHEDULER_IDLE_WAIT','XE_DISPATCHER_WAIT','XE_DISPATCHER_JOIN','BROKER_EVENTHANDLER','TRACEWRITE','SOS_WORK_DISPATCHER','QDS_PERSIST_TASK_MAIN_LOOP_SLEEP','QDS_ASYNC_QUEUE','SP_SERVER_DIAGNOSTICS_SLEEP') ) SELECT TOP 20 wait_category, wait_type, waiting_tasks_count, CAST(wait_time_ms/1000.0 AS DECIMAL(18,2)) AS wait_s, CAST(signal_wait_time_ms/1000.0 AS DECIMAL(18,2)) AS signal_wait_s FROM waits ORDER BY wait_time_ms DESC;" }
        Add-Section 'Current Waiting Tasks and Wait Chains' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT TOP 30 wt.session_id, wt.exec_context_id, wt.wait_duration_ms, wt.wait_type, wt.blocking_session_id, wt.resource_description, er.status, er.command, DB_NAME(er.database_id) AS database_name, LEFT(txt.text, 320) AS sql_text FROM sys.dm_os_waiting_tasks wt LEFT JOIN sys.dm_exec_requests er ON wt.session_id = er.session_id OUTER APPLY sys.dm_exec_sql_text(er.sql_handle) txt ORDER BY wt.wait_duration_ms DESC;" }
        Add-Section 'Active Requests (ASH Analogue)' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT TOP 40 r.session_id, s.login_name, s.host_name, s.program_name, DB_NAME(r.database_id) AS database_name, r.status, r.command, r.cpu_time, r.total_elapsed_time, r.reads, r.writes, r.logical_reads, r.wait_type, r.wait_time, r.blocking_session_id, r.granted_query_memory, LEFT(txt.text, 320) AS sql_text FROM sys.dm_exec_requests r JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) txt WHERE s.is_user_process = 1 ORDER BY r.total_elapsed_time DESC, r.cpu_time DESC;" }
        Add-Section 'Long-Running Sessions and Open Transactions' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT TOP 25 s.session_id, s.login_name, s.host_name, s.program_name, s.status, s.open_transaction_count, DATEDIFF(SECOND, s.last_request_start_time, GETDATE()) AS seconds_since_request_start, DATEDIFF(SECOND, s.last_request_end_time, GETDATE()) AS seconds_since_request_end, c.client_net_address, c.net_transport, c.encrypt_option, LEFT(txt.text, 320) AS last_sql_text FROM sys.dm_exec_sessions s LEFT JOIN sys.dm_exec_connections c ON s.session_id = c.session_id OUTER APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) txt WHERE s.is_user_process = 1 ORDER BY s.open_transaction_count DESC, seconds_since_request_start DESC;" }
        Add-Section 'Blocking Sessions and Head Blockers' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "WITH waiting AS ( SELECT r.session_id, r.blocking_session_id, r.wait_type, r.wait_time, r.cpu_time, r.logical_reads, DB_NAME(r.database_id) AS database_name, LEFT(t.text, 320) AS sql_text FROM sys.dm_exec_requests r OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t WHERE r.blocking_session_id <> 0 ) SELECT TOP 30 waiting.*, s.login_name, s.host_name, s.program_name FROM waiting LEFT JOIN sys.dm_exec_sessions s ON waiting.session_id = s.session_id ORDER BY wait_time DESC;" }
        Add-Section 'TempDB Usage and Version Store' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT SUM(user_object_reserved_page_count) * 8 AS user_object_kb, SUM(internal_object_reserved_page_count) * 8 AS internal_object_kb, SUM(version_store_reserved_page_count) * 8 AS version_store_kb, SUM(unallocated_extent_page_count) * 8 AS unallocated_kb FROM tempdb.sys.dm_db_file_space_usage; SELECT TOP 20 session_id, user_objects_alloc_page_count * 8 AS user_alloc_kb, internal_objects_alloc_page_count * 8 AS internal_alloc_kb FROM sys.dm_db_session_space_usage ORDER BY (user_objects_alloc_page_count + internal_objects_alloc_page_count) DESC;" }
        Add-Section 'Transaction Log and Recovery Health' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT database_name, recovery_model, log_size_mb, log_space_in_use_percent, status FROM sys.dm_db_log_space_usage lus CROSS APPLY (SELECT DB_NAME() AS current_db_name) x RIGHT JOIN (SELECT name AS database_name, recovery_model_desc AS recovery_model, state_desc AS status FROM sys.databases) d ON d.database_name = DB_NAME(); SELECT database_id, DB_NAME(database_id) AS database_name, total_log_size_mb, active_log_size_mb, log_truncation_holdup_reason FROM sys.dm_db_log_stats(NULL) ORDER BY active_log_size_mb DESC;" }
        Add-Section 'Database IO Stall by File' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT DB_NAME(vfs.database_id) AS db_name, mf.type_desc, mf.file_id, mf.name AS logical_name, mf.physical_name, vfs.num_of_reads, vfs.num_of_writes, vfs.io_stall_read_ms, vfs.io_stall_write_ms, CASE WHEN vfs.num_of_reads = 0 THEN NULL ELSE CAST(vfs.io_stall_read_ms * 1.0 / vfs.num_of_reads AS DECIMAL(18,2)) END AS avg_read_stall_ms, CASE WHEN vfs.num_of_writes = 0 THEN NULL ELSE CAST(vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes AS DECIMAL(18,2)) END AS avg_write_stall_ms, vfs.size_on_disk_bytes / 1048576 AS size_on_disk_mb FROM sys.dm_io_virtual_file_stats(NULL,NULL) vfs JOIN sys.master_files mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id ORDER BY (vfs.io_stall_read_ms + vfs.io_stall_write_ms) DESC;" }
        Add-Section 'Top CPU Statements' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT TOP 25 qs.execution_count, CAST(qs.total_worker_time/1000.0 AS DECIMAL(18,2)) AS total_cpu_ms, CAST(qs.total_worker_time / NULLIF(qs.execution_count,0) / 1000.0 AS DECIMAL(18,2)) AS avg_cpu_ms, CAST(qs.total_elapsed_time/1000.0 AS DECIMAL(18,2)) AS total_elapsed_ms, qs.total_logical_reads, qs.total_logical_writes, qs.max_worker_time/1000.0 AS max_cpu_ms, DB_NAME(COALESCE(txt.dbid, qp.dbid)) AS database_name, LEFT(txt.text, 400) AS sql_text FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) txt OUTER APPLY sys.dm_exec_text_query_plan(qs.plan_handle, qs.statement_start_offset, qs.statement_end_offset) qp ORDER BY qs.total_worker_time DESC;" }
        Add-Section 'Top Duration Statements' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT TOP 25 qs.execution_count, CAST(qs.total_elapsed_time/1000.0 AS DECIMAL(18,2)) AS total_elapsed_ms, CAST(qs.total_elapsed_time / NULLIF(qs.execution_count,0) / 1000.0 AS DECIMAL(18,2)) AS avg_elapsed_ms, CAST(qs.total_worker_time/1000.0 AS DECIMAL(18,2)) AS total_cpu_ms, qs.total_logical_reads, qs.total_logical_writes, qs.max_elapsed_time/1000.0 AS max_elapsed_ms, LEFT(txt.text, 400) AS sql_text FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) txt ORDER BY qs.total_elapsed_time DESC;" }
        Add-Section 'Top Read and Write Statements' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT TOP 20 'reads' AS metric, qs.execution_count, qs.total_logical_reads AS metric_value, CAST(qs.total_worker_time/1000.0 AS DECIMAL(18,2)) AS total_cpu_ms, CAST(qs.total_elapsed_time/1000.0 AS DECIMAL(18,2)) AS total_elapsed_ms, LEFT(txt.text, 320) AS sql_text FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) txt ORDER BY qs.total_logical_reads DESC; SELECT TOP 20 'writes' AS metric, qs.execution_count, qs.total_logical_writes AS metric_value, CAST(qs.total_worker_time/1000.0 AS DECIMAL(18,2)) AS total_cpu_ms, CAST(qs.total_elapsed_time/1000.0 AS DECIMAL(18,2)) AS total_elapsed_ms, LEFT(txt.text, 320) AS sql_text FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) txt ORDER BY qs.total_logical_writes DESC;" }
        Add-Section 'Plan Cache Efficiency and Recompiles' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT objtype, cacheobjtype, COUNT(*) AS plans, SUM(size_in_bytes)/1048576.0 AS size_mb, SUM(usecounts) AS total_usecounts FROM sys.dm_exec_cached_plans GROUP BY objtype, cacheobjtype ORDER BY size_mb DESC; SELECT counter_name, cntr_value FROM sys.dm_os_performance_counters WHERE counter_name IN ('SQL Compilations/sec','SQL Re-Compilations/sec','Cache Hit Ratio','Cache Pages');" }
        Add-Section 'Missing Index Candidates' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT TOP 25 DB_NAME(mid.database_id) AS database_name, OBJECT_NAME(mid.object_id, mid.database_id) AS table_name, migs.user_seeks, migs.user_scans, CAST(migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS DECIMAL(18,2)) AS improvement_measure, mid.equality_columns, mid.inequality_columns, mid.included_columns FROM sys.dm_db_missing_index_group_stats migs JOIN sys.dm_db_missing_index_groups mig ON migs.group_handle = mig.index_group_handle JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle ORDER BY improvement_measure DESC;" }
        Add-Section 'Query Store Regressions and Runtime Outliers' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT actual_state_desc, desired_state_desc, readonly_reason, current_storage_size_mb, max_storage_size_mb, interval_length_minutes FROM sys.database_query_store_options; SELECT TOP 25 qsq.query_id, qsp.plan_id, rs.count_executions, CAST(rs.avg_duration/1000.0 AS DECIMAL(18,2)) AS avg_duration_ms, CAST(rs.max_duration/1000.0 AS DECIMAL(18,2)) AS max_duration_ms, CAST(rs.avg_cpu_time/1000.0 AS DECIMAL(18,2)) AS avg_cpu_ms, CAST(rs.avg_logical_io_reads AS DECIMAL(18,2)) AS avg_logical_reads, LEFT(qt.query_sql_text, 320) AS sql_text FROM sys.query_store_runtime_stats rs JOIN sys.query_store_plan qsp ON rs.plan_id = qsp.plan_id JOIN sys.query_store_query qsq ON qsp.query_id = qsq.query_id JOIN sys.query_store_query_text qt ON qsq.query_text_id = qt.query_text_id ORDER BY rs.avg_duration DESC;" }
        Add-Section 'Deadlock Signals from System Health' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT TOP 10 xed.event_data.value('(event/@timestamp)[1]', 'datetime2') AS event_time_utc, xed.event_data.value('(event/data/value/deadlock/process-list/process/@spid)[1]', 'int') AS victim_spid, xed.event_data.value('count((event/data/value/deadlock/process-list/process))', 'int') AS process_count, xed.event_data.value('count((event/data/value/deadlock/resource-list/*))', 'int') AS resource_count FROM ( SELECT CAST(event_data AS XML) AS event_data FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL) WHERE object_name = 'xml_deadlock_report' ) xed ORDER BY event_time_utc DESC;" }
        Add-Section 'AlwaysOn Replica Health' { Invoke-SqlServerQuery -Server $server -Database $dbName -Username $dbUser -Password $dbPassword -TrustServerCertificate $sqlServerTrustCert -Query "SELECT ag.name AS ag_name, ar.replica_server_name, ars.role_desc, ars.connected_state_desc, ars.operational_state_desc, ars.synchronization_health_desc, ar.availability_mode_desc, ar.failover_mode_desc FROM sys.dm_hadr_availability_replica_states ars JOIN sys.availability_replicas ar ON ars.replica_id = ar.replica_id JOIN sys.availability_groups ag ON ar.group_id = ag.group_id; SELECT DB_NAME(drs.database_id) AS database_name, drs.is_local, drs.synchronization_state_desc, drs.synchronization_health_desc, drs.log_send_queue_size, drs.redo_queue_size, drs.redo_rate, drs.log_send_rate FROM sys.dm_hadr_database_replica_states drs ORDER BY drs.log_send_queue_size DESC, drs.redo_queue_size DESC;" }
    }
    'azure_sql_db' {
        & $PSCommandPath -Engine 'sqlserver' -EngineRoot $EngineRoot
        exit $LASTEXITCODE
    }
    default {
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if ($bash) {
            $linuxRunner = Join-Path $PSScriptRoot 'run_oneoff_engine.sh'
            & $bash.Source $linuxRunner $Engine $EngineRoot
            exit $LASTEXITCODE
        }

        Add-Section 'Engine Support Notice' { "Windows native deep sections are currently implemented for mysql/postgresql/sqlserver families. Install bash (Git Bash/WSL) for full cross-engine detail on Windows." }
    }
}

if (Test-Path $snapshotSql) {
    try {
        Add-Content -Path $snapshotOut -Value (Get-Content $snapshotSql -Raw)
    }
    catch {
        Add-Content -Path $snapshotOut -Value 'Snapshot SQL exists but could not be read.'
    }
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    python $reportBuilder --engine $Engine --input $reportTxt --output $reportHtml | Out-Null
}
elseif (Get-Command py -ErrorAction SilentlyContinue) {
    py $reportBuilder --engine $Engine --input $reportTxt --output $reportHtml | Out-Null
}
else {
    $htmlContent = Convert-ReportTextToHtml -Engine $Engine -ReportText (Get-Content $reportTxt -Raw)
    $htmlContent | Set-Content -Path $reportHtml
}

Write-Log "Snapshot written: $snapshotOut"
Write-Log "Detailed TXT report: $reportTxt"
Write-Log "Detailed HTML report: $reportHtml"

