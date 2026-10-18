<#
  06-Import-Contacts.ps1
  RUN ON: any Windows PC.
  RUN AS: the USER whose contacts these are (they sign in with their own
  Microsoft 365 account). IMAP only copies email, so contacts are done here.

  STEP 1 - the user exports their Google contacts:
    contacts.google.com > Export > choose "Google CSV" (or "Outlook CSV")
    > Export. Save the file somewhere on this PC.

  STEP 2 - run this script:
    .\06-Import-Contacts.ps1 -CsvPath "C:\Users\Jane\Downloads\contacts.csv"

  Adds each contact to the user's Outlook contacts through Microsoft Graph.
  Contacts whose email address is already in Outlook are SKIPPED, so it's
  safe to run twice. Use -WhatIf to see what would be imported first.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CsvPath
)

$LogDir = "$PSScriptRoot\..\Logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogPath = "$LogDir\06-contacts-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
function Write-Log { param([string]$m, [string]$c = "White") Add-Content $LogPath $m; Write-Host $m -ForegroundColor $c }

if (-not (Test-Path $CsvPath)) { Write-Error "Contacts file not found: $CsvPath"; exit 1 }

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    $answer = Read-Host "The Microsoft.Graph.Authentication module isn't installed. Install it now for the current user? (Y/N)"
    if ($answer -notmatch '^[Yy]') { exit 1 }
    Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
}

# Google CSV (new + old layouts) and Outlook CSV use different column names.
function Get-Field {
    param($Row, [string[]]$Names)
    foreach ($n in $Names) {
        $p = $Row.PSObject.Properties[$n]
        if ($p -and "$($p.Value)".Trim()) { return "$($p.Value)".Trim() }
    }
    return $null
}

$rows = @(Import-Csv $CsvPath)
Write-Log "Read $($rows.Count) contact(s) from $CsvPath"

Connect-MgGraph -Scopes "Contacts.ReadWrite" -NoWelcome
$me = (Get-MgContext).Account
Write-Log "Signed in as $me - contacts will go into THIS mailbox." "Cyan"

# Existing email addresses, so we don't create duplicates
$existing = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
$uri = "v1.0/me/contacts?`$select=emailAddresses&`$top=999"
while ($uri) {
    $page = Invoke-MgGraphRequest -Method GET -Uri $uri
    foreach ($c in $page.value) { foreach ($e in $c.emailAddresses) { [void]$existing.Add($e.address) } }
    $uri = $page.'@odata.nextLink'
}
Write-Log "$($existing.Count) email address(es) already in Outlook contacts."

$added = 0; $skipped = 0; $failed = 0
foreach ($r in $rows) {
    $first = Get-Field $r "First Name", "Given Name"
    $last = Get-Field $r "Last Name", "Family Name"
    $display = Get-Field $r "Name", "File As", "Display Name"
    if (-not $display) { $display = ("$first $last").Trim() }

    $emails = @()
    foreach ($col in "E-mail 1 - Value", "E-mail 2 - Value", "E-mail 3 - Value", "E-mail Address", "E-mail 2 Address", "E-mail 3 Address") {
        $v = Get-Field $r $col
        # Google puts several addresses in one cell separated by " ::: "
        if ($v) { $emails += ($v -split '\s*:::\s*' | Where-Object { $_ -match '@' }) }
    }
    $emails = $emails | Select-Object -Unique -First 3

    $mobile = Get-Field $r "Mobile Phone", "Phone 1 - Value"
    $work = Get-Field $r "Business Phone", "Phone 2 - Value"
    $company = Get-Field $r "Company", "Organization Name", "Organization 1 - Name"
    $title = Get-Field $r "Job Title", "Organization Title", "Organization 1 - Title"
    $notes = Get-Field $r "Notes"

    if (-not $display -and -not $emails) { $skipped++; continue }
    if ($emails | Where-Object { $existing.Contains($_) }) {
        Write-Log "  skip (already in Outlook): $display <$($emails -join ', ')>" "DarkGray"; $skipped++; continue
    }

    $body = @{ displayName = $display }
    if ($first) { $body.givenName = $first }
    if ($last) { $body.surname = $last }
    if ($emails) { $body.emailAddresses = @($emails | ForEach-Object { @{ address = $_; name = $display } }) }
    if ($mobile) { $body.mobilePhone = ($mobile -split '\s*:::\s*')[0] }
    if ($work) { $body.businessPhones = @(($work -split '\s*:::\s*')[0]) }
    if ($company) { $body.companyName = $company }
    if ($title) { $body.jobTitle = $title }
    if ($notes) { $body.personalNotes = $notes }

    if ($PSCmdlet.ShouldProcess($display, "Add Outlook contact")) {
        try {
            Invoke-MgGraphRequest -Method POST -Uri "v1.0/me/contacts" -Body ($body | ConvertTo-Json -Depth 4) -ContentType "application/json" | Out-Null
            $emails | ForEach-Object { [void]$existing.Add($_) }
            $added++
        }
        catch { Write-Log "  FAILED: $display - $($_.Exception.Message)" "Red"; $failed++ }
    }
}

Disconnect-MgGraph | Out-Null
Write-Log "Done: $added added, $skipped skipped (duplicates/empty), $failed failed. Log: $LogPath" "Green"
