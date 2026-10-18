# Gmail -> Microsoft 365 Migration (personal Gmail accounts)

Moves **personal @gmail.com** mailboxes into **Microsoft 365 / Exchange Online**
mailboxes using PowerShell. It's built for small businesses moving staff off
personal Gmail and onto proper company email.

It uses **Microsoft's own built-in IMAP migration**. The scripts set it up,
check it, run it and tidy up, so there's no third-party service and no
monthly fee.

> For **Google Workspace** (company) accounts, use Microsoft's Google
> Workspace migration instead. It also moves calendars and contacts.
> This tool is for personal Gmail.

## What moves

| Item | How | Notes |
|---|---|---|
| **Email + folders/labels** | Stages 1-5 (IMAP batch) | Keeps syncing new Gmail mail about every 24h until you finish |
| **Contacts** | Stage 6 (Google CSV export -> Outlook via Microsoft Graph) | Skips duplicates, safe to re-run |
| **Calendar** | Manual, about 2 minutes (see below) | Gmail calendars can't be copied over IMAP |

## Before you start

**Each Gmail user must:**
1. Turn on **2-Step Verification**: myaccount.google.com > Security.
2. Create an **app password** at myaccount.google.com/apppasswords. It's a
   16-letter code. Their normal password won't work.
3. Check **IMAP is on**: Gmail > Settings > See all settings > Forwarding and
   POP/IMAP > Enable IMAP.

**You (the admin):**
- Each user needs a Microsoft 365 account **with an Exchange Online licence**.
- Copy `Config\users.example.csv` to `Config\users.csv` and fill it in:

| EmailAddress | UserName | Password |
|---|---|---|
| their new Microsoft 365 address | their Gmail address | the 16-letter app password |

⚠️ `users.csv` holds **app passwords**. Never email it or commit it (it's in
`.gitignore`). Delete it when you've finished.

## Stages

| # | Script | Changes anything? | What it does |
|---|---|---|---|
| 1 | `01-Check-Prerequisites.ps1` | No | Module, CSV, Gmail reachable, mailboxes exist, **test-logs in to each Gmail** from Microsoft 365 |
| 2 | `02-Create-MigrationEndpoint.ps1` | Yes (once) | Creates the Gmail IMAP endpoint (imap.gmail.com:993 SSL) |
| 3 | `03-Start-MigrationBatch.ps1` | Yes | Starts copying mail. Users keep using Gmail meanwhile |
| 4 | `04-Monitor-Migration.ps1 -BatchName <name> [-Watch]` | No | Progress per user, skipped items, errors, CSV report |
| 5 | `05-Complete-Migration.ps1 -BatchName <name>` | Yes | Final sync, stops syncing, removes the batch. Needs `-IReallyMeanIt` |
| 6 | `06-Import-Contacts.ps1 -CsvPath <file>` | Yes | Run **as the user**. Imports their Google contacts into Outlook |

Run in **PowerShell 7** or Windows PowerShell 5.1, as an Exchange Administrator
(stages 1-5).

## Gmail labels and "All Mail"

Over IMAP, Gmail shows each email in **All Mail** *and* in every label it has.
To avoid duplicates, stage 3 skips `[Gmail]/All Mail`, `Important`, `Starred`,
`Spam` and `Trash`. If someone archives mail without labels, it only lives in
All Mail, so use `-IncludeAllMail` for that user's batch.

## Calendar (manual)

1. In Google Calendar: Settings > **Import & export** > **Export**. This gives a .zip of `.ics` files.
2. In Outlook on the web: Calendar > **Add calendar** > **Upload from file**, then pick the `.ics`.

## Finishing up (personal Gmail)

`gmail.com` stays with Google, so there's no MX record to change. When a user is
ready to switch:
- In Gmail, set **forwarding** to their new address (Settings > Forwarding and
  POP/IMAP), so nothing sent to the old address gets missed.
- Run stage 5, delete `users.csv`, and ask the user to **revoke the app password**.

## Limits (Microsoft's)

- Up to **500,000 items** per mailbox, and **35 MB** max per email.
- Large mailboxes can take a day or more for the first copy.

## Status

Written 2026-10-18. Not yet run on a real migration, so test with one mailbox first.
