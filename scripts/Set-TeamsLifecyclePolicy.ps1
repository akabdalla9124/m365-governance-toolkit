<#
.SYNOPSIS
    Audits all Teams in the tenant for lifecycle compliance issues.

.DESCRIPTION
    Scans every Team and flags: no owner, inactive for N+ days, naming policy
    violations, and no members. Optionally sends renewal notification emails to
    team owners so they can confirm the team is still needed.

    Run monthly or quarterly as part of a governance review cycle.

.PARAMETER InactiveDaysThreshold
    Days without any channel message activity before a team is flagged as inactive.
    Default: 90.

.PARAMETER NamingPattern
    Regex pattern that team display names must match. Teams that don't match are
    flagged. Leave empty to skip naming validation.

.PARAMETER SendRenewalEmails
    If true, sends an email to each flagged team's owners asking them to confirm
    the team is still active. Requires Exchange Online connection.

.PARAMETER OutputPath
    Path for the CSV output file.

.EXAMPLE
    .\Set-TeamsLifecyclePolicy.ps1 `
        -InactiveDaysThreshold 90 `
        -NamingPattern "^[A-Z]{2,5}-" `
        -SendRenewalEmails $true `
        -OutputPath ".\reports\teams-lifecycle-2025-01-15.csv"
#>

[CmdletBinding()]
param (
    [int]    $InactiveDaysThreshold = 90,
    [string] $NamingPattern         = "",
    [bool]   $SendRenewalEmails     = $false,
    [string] $OutputPath = ".\reports\teams-lifecycle-$(Get-Date -Format 'yyyy-MM-dd').csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$reportDir = Split-Path $OutputPath
if ($reportDir -and -not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }

#region -- Connect ------------------------------------------------------------
Write-Host "Connecting to Microsoft Teams and Graph..." -ForegroundColor Cyan
Connect-MicrosoftTeams
Connect-MgGraph -Scopes "Team.ReadBasic.All", "TeamMember.Read.All", "Reports.Read.All"
if ($SendRenewalEmails) { Connect-ExchangeOnline -ShowBanner:$false }
#endregion

#region -- Get all teams ------------------------------------------------------
Write-Host "Fetching all Teams..." -ForegroundColor Cyan
$teams = Get-Team
Write-Host "  Found $($teams.Count) teams." -ForegroundColor Green
#endregion

$results    = [System.Collections.Generic.List[PSCustomObject]]::new()
$cutoffDate = (Get-Date).AddDays(-$InactiveDaysThreshold)
$counter    = 0

foreach ($team in $teams) {
    $counter++
    Write-Progress -Activity "Auditing Teams" -Status "$counter / $($teams.Count): $($team.DisplayName)" -PercentComplete (($counter / $teams.Count) * 100)

    $flags   = [System.Collections.Generic.List[string]]::new()
    $owners  = @()
    $members = @()

    # Owners and members
    try {
        $owners  = Get-TeamUser -GroupId $team.GroupId -Role Owner  -ErrorAction SilentlyContinue
        $members = Get-TeamUser -GroupId $team.GroupId -Role Member -ErrorAction SilentlyContinue
    } catch { }

    if ($owners.Count -eq 0)  { $flags.Add("NO_OWNER") }
    if ($members.Count -eq 0) { $flags.Add("NO_MEMBERS") }

    # Naming policy
    if ($NamingPattern -and $team.DisplayName -notmatch $NamingPattern) {
        $flags.Add("NAMING_VIOLATION")
    }

    # Activity — use Graph activity report (90-day window available)
    $lastActivity = $null
    try {
        $activityReport = Get-MgReportTeamActivityDetail -Period "D90" -ErrorAction SilentlyContinue |
            Where-Object { $_.TeamId -eq $team.GroupId } |
            Select-Object -First 1
        if ($activityReport) {
            $lastActivity = [datetime]$activityReport.LastActivityDate
        }
    } catch { }

    $daysSince = if ($lastActivity) { [int]((Get-Date) - $lastActivity).TotalDays } else { $null }
    if (-not $lastActivity -or $lastActivity -lt $cutoffDate) {
        $flags.Add("INACTIVE$(if ($daysSince) { "_${daysSince}_DAYS" } else { '_UNKNOWN' })")
    }

    # Archive status
    $isArchived = $team.Archived

    $results.Add([PSCustomObject]@{
        TeamId            = $team.GroupId
        DisplayName       = $team.DisplayName
        Description       = $team.Description
        Visibility        = $team.Visibility
        IsArchived        = $isArchived
        OwnerCount        = $owners.Count
        Owners            = ($owners.User -join "; ")
        MemberCount       = $members.Count
        LastActivityDate  = if ($lastActivity) { $lastActivity.ToString("yyyy-MM-dd") } else { "Unknown" }
        DaysSinceActivity = $daysSince
        NamingViolation   = ($NamingPattern -and $team.DisplayName -notmatch $NamingPattern)
        Flags             = ($flags -join "; ")
        HasIssues         = ($flags.Count -gt 0)
        ReviewDate        = (Get-Date -Format "yyyy-MM-dd")
        Action            = "Pending Review"
    })

    # Send renewal email if flagged and owners exist
    if ($SendRenewalEmails -and $flags.Count -gt 0 -and $owners.Count -gt 0) {
        foreach ($owner in $owners) {
            try {
                Send-MailMessage -To $owner.User `
                    -Subject "Action Required: Review Teams team '$($team.DisplayName)'" `
                    -Body @"
Hi,

As part of our Microsoft Teams governance review, the team '$($team.DisplayName)' has been flagged for the following reason(s):

$($flags -join "`n")

Please take one of the following actions within 14 days:
  - Confirm the team is active and still needed (reply to this email)
  - Archive the team if it is no longer in use
  - Delete the team if it should be removed

If no action is taken, the team will be automatically archived.

This is an automated message from the M365 Governance team.
"@ `
                    -SmtpServer "smtp.office365.com" `
                    -UseSsl `
                    -Port 587
            } catch {
                Write-Warning "Could not send renewal email to $($owner.User): $_"
            }
        }
    }
}

Write-Progress -Activity "Auditing Teams" -Completed

$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

$flaggedCount = ($results | Where-Object { $_.HasIssues }).Count
Write-Host ""
Write-Host "Teams lifecycle audit complete." -ForegroundColor Green
Write-Host "  Total teams:   $($results.Count)"
Write-Host "  Teams flagged: $flaggedCount"
Write-Host "  Report saved:  $OutputPath"
