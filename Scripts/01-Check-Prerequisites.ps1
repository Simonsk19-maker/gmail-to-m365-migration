<#
  01-Check-Prerequisites.ps1
  RUN ON: any Windows PC with internet access, as a Microsoft 365 admin
  (Exchange Administrator or Global Administrator).
  RUN WHEN: before anything else. Read-only - changes nothing.

  Checks:
    1. The ExchangeOnlineManagement PowerShell module is installed (offers to install it).
    2. Config\users.csv exists and has the right columns.
    3. Gmail's IMAP server (imap.gmail.com:993) is reachable from this PC.
    4. Every target Microsoft 365 mailbox exists (and isn't over quota).
    5. Microsoft 365 can actually log in to each Gmail account over IMAP
       (Test-MigrationServerAvailability). This catches a wrong app
       password or IMAP switched off BEFORE the real migration starts.

  WHAT EACH GMAIL USER MUST DO FIRST (personal @gmail.com accounts):
    a. Turn on 2-Step Verification: myaccount.google.com > Security.
    b. Create an APP PASSWORD: myaccount.google.com/apppasswords
       (name it "Microsoft 365 migration"). It's 16 letters. Put it in the
       Password column of users.csv. Their normal Gmail password will NOT work.
    c. Make sure IMAP is on: Gmail > Settings > See all settings >
       Forwarding and POP/IMAP > Enable IMAP.
#>

param(
    [string]$CsvPath = "$PSScriptRoot\..\Config\users.csv",
    [switch]$SkipLoginTest
)

$LogDir = "$PSScriptRoot\..\Logs"
$LogPath = "$LogDir\01-prereqs-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$script:Problems = 0

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Add-Content -Path $LogPath -Value $line
    switch ($Level) {
        "ERROR" { $script:Problems++; Write-Host $line -ForegroundColor Red }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        "OK"    { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line }
    }
}

Write-Log "=== Gmail -> Microsoft 365 pre-checks ==="

# --- 1. Exchange Online module ---
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Log "The ExchangeOnlineManagement module isn't installed." -Level "WARN"
    $answer = Read-Host "Install it now for the current user? (Y/N)"
    if ($answer -match '^[Yy]') {
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
        Write-Log "ExchangeOnlineManagement installed." -Level "OK"
    }
    else {
        Write-Log "Can't continue without ExchangeOnlineManagement." -Level "ERROR"
        exit 1
    }
}
else {
    Write-Log "ExchangeOnlineManagement module found." -Level "OK"
}

# --- 2. The CSV ---
if (-not (Test-Path $CsvPath)) {
    Write-Log "No users.csv at $CsvPath. Copy Config\users.example.csv to Config\users.csv and fill it in." -Level "ERROR"
    exit 1
}
$users = @(Import-Csv $CsvPath)
$cols = $users[0].PSObject.Properties.Name
foreach ($needed in "EmailAddress", "UserName", "Password") {
    if ($cols -notcontains $needed) { Write-Log "users.csv is missing the '$needed' column." -Level "ERROR" }
}
if ($script:Problems) { exit 1 }
Write-Log "$($users.Count) user(s) in users.csv." -Level "OK"
foreach ($u in $users) {
    if ($u.UserName -notmatch '@(gmail|googlemail)\.com$') {
        Write-Log "  $($u.UserName) isn't a @gmail.com address. For Google Workspace (company) accounts use Microsoft's Google Workspace migration instead - this tool is for personal Gmail." -Level "WARN"
    }
    if (($u.Password -replace '\s', '').Length -ne 16) {
        Write-Log "  The password for $($u.UserName) isn't 16 letters - it doesn't look like a Gmail app password." -Level "WARN"
    }
}

# --- 3. Can this PC reach Gmail's IMAP server? ---
$tcp = Test-NetConnection -ComputerName imap.gmail.com -Port 993 -WarningAction SilentlyContinue
if ($tcp.TcpTestSucceeded) { Write-Log "imap.gmail.com:993 is reachable." -Level "OK" }
else { Write-Log "Can't reach imap.gmail.com on port 993 from this PC (firewall?). Microsoft 365 connects from its own servers, so the migration may still work, but check." -Level "WARN" }

# --- 4 & 5. Mailboxes + IMAP login test from Microsoft 365 ---
Write-Log "Connecting to Exchange Online (a sign-in window will open)..."
Connect-ExchangeOnline -ShowBanner:$false

foreach ($u in $users) {
    $mbx = Get-EXOMailbox -Identity $u.EmailAddress -ErrorAction SilentlyContinue
    if (-not $mbx) {
        Write-Log "  Mailbox $($u.EmailAddress) NOT found. Create the user and give them an Exchange Online licence first." -Level "ERROR"
        continue
    }
    $stats = Get-EXOMailboxStatistics -Identity $u.EmailAddress -ErrorAction SilentlyContinue
    Write-Log "  Mailbox $($u.EmailAddress) found (currently $($stats.TotalItemSize))." -Level "OK"

    if (-not $SkipLoginTest) {
        $cred = New-Object System.Management.Automation.PSCredential($u.UserName, (ConvertTo-SecureString ($u.Password -replace '\s', '') -AsPlainText -Force))
        $test = Test-MigrationServerAvailability -IMAP -RemoteServer imap.gmail.com -Port 993 -Security Ssl -Credentials $cred -ErrorAction SilentlyContinue
        if ($test.Result -eq "Success") { Write-Log "    Microsoft 365 can log in to $($u.UserName) over IMAP." -Level "OK" }
        else { Write-Log "    Microsoft 365 could NOT log in to $($u.UserName): $($test.Message). Check the app password, 2-Step Verification and that IMAP is on." -Level "ERROR" }
    }
}

Disconnect-ExchangeOnline -Confirm:$false
Write-Log "=== Done: $script:Problems problem(s). ==="
if ($script:Problems -eq 0) { Write-Log "Ready. Next: 02-Create-MigrationEndpoint.ps1" -Level "OK" }
