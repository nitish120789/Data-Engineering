Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path $scriptDir 'install_client_tools_wsl.sh'

Write-Output 'This helper runs the WSL client-tool installer after WSL is active.'
Write-Output 'Prerequisites:'
Write-Output '1. Reboot after enabling WSL'
Write-Output '2. Initialize a distro (for example Ubuntu)'
Write-Output '3. Ensure the distro can reach the internet'
Write-Output ''

wsl --status | Out-Host
Write-Output ''
Write-Output 'If WSL is active, run:'
Write-Output ("wsl bash -lc 'cd /mnt/c/Users/nitishs.admin/Desktop/repo/database-reliability-engineering/database_admin/performance_reports/CPF_Observability/common && chmod +x install_client_tools_wsl.sh && ./install_client_tools_wsl.sh'")
Write-Output ''
Write-Output ('Installer file: ' + $installer)
