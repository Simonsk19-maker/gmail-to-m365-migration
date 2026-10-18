<#
  03-Start-MigrationBatch.ps1
  RUN ON: any Windows PC, as a Microsoft 365 admin.
  RUN WHEN: after the endpoint exists (stage 2). No downtime - people
  keep using Gmail normally while this copies in the background.

  Starts a migration batch for everyone in Config\users.csv. Microsoft 365
  copies their Gmail mail (with folders/labels) into their new mailbox,
  then keeps doing a catch-up sync about every 24 hours until you
  complete the batch (stage 5).

  GMAIL LABEL GOTCHA: in IMAP, Gmail shows every email in "All Mail" AND
  in each of its labels. Copying "All Mail" too would create duplicates,
  so these Gmail system folders are skipped by default:
    [Gmail]/All Mail, [Gmail]/Important, [Gmail]/Starred, [Gmail]/Spam, [Gmail]/Trash
  Use -IncludeAllMail if a user keeps mail ONLY in "All Mail" (archived,
  no labels) - otherwise those archived emails won't come across.

  LIMITS (Microsoft's): up to 500,000 items per mailbox, 35 MB max per
  message. Only email is copied over IMAP - for contacts use stage 6,
  for calendars see the README.
#>

param(
    [string]$CsvPath = "$PSScriptRoot\..\Config\users.csv",
    [string]$EndpointName = "Gmail-IMAP",
    [string]$BatchName = "Gmail-$(Get-Date -Format 'yyyyMMdd-HHmm')",
    [string]$NotifyEmail,          # optional: admin email to get Microsoft's status reports
    [switch]$IncludeAllMail
)

if (-not (Test-Path $CsvPath)) { Write-Error "users.csv not found at $CsvPath"; exit 1 }

$exclude = @("[Gmail]/Spam", "[Gmail]/Trash", "[Gmail]/Important", "[Gmail]/Starred")
if (-not $IncludeAllMail) { $exclude += "[Gmail]/All Mail" }

# Microsoft wants the app password without spaces - clean a temporary copy of the CSV
$users = Import-Csv $CsvPath | ForEach-Object {
    [pscustomobject]@{ EmailAddress = $_.EmailAddress.Trim(); UserName = $_.UserName.Trim(); Password = ($_.Password -replace '\s', '') }
}
$csvBytes = [System.Text.Encoding]::UTF8.GetBytes(($users | ConvertTo-Csv -NoTypeInformation | Out-String))

Connect-ExchangeOnline -ShowBanner:$false

if (-not (Get-MigrationEndpoint -Identity $EndpointName -ErrorAction SilentlyContinue)) {
    Write-Error "Endpoint '$EndpointName' not found - run 02-Create-MigrationEndpoint.ps1 first."
    exit 1
}

$params = @{
    Name           = $BatchName
    SourceEndpoint = $EndpointName
    CSVData        = $csvBytes
    ExcludeFolders = $exclude
    AutoStart      = $true
}
if ($NotifyEmail) { $params.NotificationEmails = $NotifyEmail }

New-MigrationBatch @params | Out-Null
Write-Host "Started batch '$BatchName' for $(@($users).Count) user(s)." -ForegroundColor Green
Write-Host "Skipping folders: $($exclude -join ', ')"
Get-MigrationBatch -Identity $BatchName | Format-List Identity, Status, TotalCount

Disconnect-ExchangeOnline -Confirm:$false
Write-Host ""
Write-Host "The app passwords are now stored inside Microsoft 365 for the batch."
Write-Host "Keep Config\users.csv somewhere safe until the migration is complete, then DELETE it."
Write-Host "Watch progress with: 04-Monitor-Migration.ps1 -BatchName '$BatchName'"
