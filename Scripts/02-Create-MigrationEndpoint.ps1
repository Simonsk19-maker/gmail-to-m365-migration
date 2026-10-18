<#
  02-Create-MigrationEndpoint.ps1
  RUN ON: any Windows PC, as a Microsoft 365 admin.
  RUN WHEN: once, after 01-Check-Prerequisites.ps1 shows no problems.

  Creates an IMAP "migration endpoint" in Exchange Online that points at
  Gmail (imap.gmail.com, port 993, SSL). This is Microsoft's own built-in
  IMAP migration - the script just sets it up correctly. Safe to re-run:
  if the endpoint already exists it's left alone.
#>

param(
    [string]$EndpointName = "Gmail-IMAP",
    [int]$MaxConcurrentMigrations = 20
)

Connect-ExchangeOnline -ShowBanner:$false

$existing = Get-MigrationEndpoint -Identity $EndpointName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Endpoint '$EndpointName' already exists ($($existing.RemoteServer):$($existing.Port)). Nothing to do." -ForegroundColor Green
}
else {
    New-MigrationEndpoint -IMAP -Name $EndpointName -RemoteServer imap.gmail.com -Port 993 -Security Ssl `
        -MaxConcurrentMigrations $MaxConcurrentMigrations -MaxConcurrentIncrementalSyncs ([math]::Min($MaxConcurrentMigrations, 10)) | Out-Null
    Write-Host "Created migration endpoint '$EndpointName' -> imap.gmail.com:993 (SSL)." -ForegroundColor Green
}

Get-MigrationEndpoint -Identity $EndpointName | Format-List Identity, EndpointType, RemoteServer, Port, Security, MaxConcurrentMigrations
Disconnect-ExchangeOnline -Confirm:$false
Write-Host "Next: 03-Start-MigrationBatch.ps1"
