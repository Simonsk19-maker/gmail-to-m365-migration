<#
  05-Complete-Migration.ps1
  RUN ON: any Windows PC, as a Microsoft 365 admin.
  RUN WHEN: the users have switched to their Microsoft 365 mailbox and
  you've told them to stop using Gmail (or set Gmail to forward new mail
  to the new address - see the README).

  Personal Gmail isn't "moved" like a company domain (gmail.com stays
  with Google, there's no MX record to change), so finishing up means:
    1. One last catch-up sync, then complete the batch (stops syncing).
    2. Remove the finished batch.
  Needs -IReallyMeanIt, because after this new Gmail mail is no longer copied.
#>

param(
    [Parameter(Mandatory)][string]$BatchName,
    [switch]$IReallyMeanIt
)

if (-not $IReallyMeanIt) {
    Write-Host "This completes batch '$BatchName' - Microsoft 365 will STOP copying new Gmail mail for these users."
    Write-Host "Before running for real, confirm:"
    Write-Host "  [ ] 04-Monitor-Migration.ps1 shows every user as Synced (none Failed)"
    Write-Host "  [ ] Users can see their old mail in Outlook and are now using the new mailbox"
    Write-Host "  [ ] Users have set up Gmail forwarding to their new address, OR know Gmail is no longer used"
    Write-Host "  [ ] Contacts have been imported (06-Import-Contacts.ps1) and calendars handled (README)"
    Write-Host ""
    Write-Host "Then re-run with -IReallyMeanIt."
    exit 0
}

Connect-ExchangeOnline -ShowBanner:$false

Write-Host "=== Completing batch '$BatchName' (final sync, then stop) ==="
Complete-MigrationBatch -Identity $BatchName -Confirm:$false

do {
    Start-Sleep -Seconds 60
    $status = (Get-MigrationBatch -Identity $BatchName).Status
    Write-Host "  $(Get-Date -Format 'HH:mm') batch status: $status"
} while ("$status" -match "Completing|Syncing|Starting")

Get-MigrationUser -BatchId $BatchName | Select-Object Identity, Status | Format-Table -AutoSize

if ("$status" -match "Completed") {
    $remove = Read-Host "Batch completed. Remove it now? (Y/N)"
    if ($remove -match '^[Yy]') {
        Remove-MigrationBatch -Identity $BatchName -Confirm:$false
        Write-Host "Batch removed." -ForegroundColor Green
    }
}
else {
    Write-Host "Batch finished with status '$status' - check 04-Monitor-Migration.ps1 before removing it." -ForegroundColor Yellow
}

Disconnect-ExchangeOnline -Confirm:$false
Write-Host ""
Write-Host "Last steps:"
Write-Host "  - DELETE Config\users.csv (it holds the Gmail app passwords)"
Write-Host "  - Ask each user to REVOKE the app password: myaccount.google.com/apppasswords"
