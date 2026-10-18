<#
  04-Monitor-Migration.ps1
  RUN ON: any Windows PC, as a Microsoft 365 admin.
  RUN WHEN: any time after stage 3. Read-only.

  Shows each user's progress: status, items copied, items skipped and
  any error. Saves a CSV report to Logs\. Use -Watch to refresh every
  few minutes until everyone is "Synced".

  "Synced" means the first full copy is done and Microsoft 365 will keep
  catching up new Gmail mail about every 24 hours until stage 5.
#>

param(
    [Parameter(Mandatory)][string]$BatchName,
    [switch]$Watch,
    [int]$RefreshMinutes = 5
)

$LogDir = "$PSScriptRoot\..\Logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

Connect-ExchangeOnline -ShowBanner:$false

do {
    Clear-Host
    $batch = Get-MigrationBatch -Identity $BatchName
    Write-Host "Batch '$BatchName': $($batch.Status)   ($(Get-Date -Format 'HH:mm'))" -ForegroundColor Cyan

    $report = Get-MigrationUser -BatchId $BatchName | ForEach-Object {
        $s = Get-MigrationUserStatistics -Identity $_.Identity
        [pscustomobject]@{
            User          = $_.Identity
            Status        = $s.Status
            ItemsSynced   = $s.SyncedItemCount
            ItemsSkipped  = $s.SkippedItemCount
            LastSync      = $s.LastSuccessfulSyncTimestamp
            Error         = $s.ErrorSummary
        }
    }
    $report | Format-Table -AutoSize
    $report | Export-Csv "$LogDir\04-status-$BatchName.csv" -NoTypeInformation

    $failed = $report | Where-Object { $_.Status -match "Failed" }
    if ($failed) {
        Write-Host "Some users failed. The usual causes are a wrong/expired app password, IMAP switched off in Gmail, or 2-Step Verification removed." -ForegroundColor Yellow
        Write-Host "Fix it, then: Start-MigrationBatch -Identity '$BatchName'  (restarts only the failed users)" -ForegroundColor Yellow
    }
    $skipped = $report | Where-Object { $_.ItemsSkipped -gt 0 }
    if ($skipped) {
        Write-Host "Some items were skipped (usually emails over 35 MB or damaged). Details: Get-MigrationUserStatistics -Identity <user> -IncludeSkippedItems | Select -Expand SkippedItems" -ForegroundColor Yellow
    }

    $allDone = -not ($report | Where-Object { $_.Status -notmatch "Synced|Completed|Failed" })
    if ($Watch -and -not $allDone) { Start-Sleep -Seconds ($RefreshMinutes * 60) }
} while ($Watch -and -not $allDone)

Disconnect-ExchangeOnline -Confirm:$false
Write-Host "Report saved to Logs\04-status-$BatchName.csv"
if ($allDone) { Write-Host "Everyone has finished the first copy. When users are ready to stop using Gmail, run 05-Complete-Migration.ps1." -ForegroundColor Green }
