<#
.SYNOPSIS
    Interactive demo of the M365 Governance Toolkit — no M365 tenant required.

.DESCRIPTION
    Simulates a full governance audit run against a fictional Contoso tenant
    using mock data. Demonstrates what each script does, what the console output
    looks like, and what gets written to the report CSVs.

    Run this to see the toolkit in action without any credentials or connections.

.EXAMPLE
    .\demo\Demo-Toolkit.ps1
#>

$ErrorActionPreference = 'Continue'

function Write-Banner {
    param([string]$Title)
    $line = '-' * 60
    Write-Host ""
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host "  [$Step] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-OK   { param([string]$m) Write-Host "  [OK]  $m" -ForegroundColor Green }
function Write-Flag { param([string]$m) Write-Host "  [!!]  $m" -ForegroundColor Red }
function Write-Warn { param([string]$m) Write-Host "  [>>]  $m" -ForegroundColor Yellow }
function Write-Info { param([string]$m) Write-Host "        $m" -ForegroundColor Gray }

$outputDir = Join-Path $PSScriptRoot "..\sample-outputs"
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }

# ─────────────────────────────────────────────────────────────────────────────
# MOCK DATA
# ─────────────────────────────────────────────────────────────────────────────

$mockUsers = @(
    @{ DisplayName='Sarah Chen';      UPN='s.chen@contoso.com';      Dept='Finance';    Manager='j.miller@contoso.com'; License='E3' },
    @{ DisplayName='Marcus Williams'; UPN='m.williams@contoso.com';  Dept='Operations'; Manager='j.miller@contoso.com'; License='E3' },
    @{ DisplayName='Priya Patel';     UPN='p.patel@contoso.com';     Dept='IT';         Manager='a.jones@contoso.com';  License='E5' },
    @{ DisplayName='James Okafor';    UPN='j.okafor@contoso.com';    Dept='HR';         Manager='a.jones@contoso.com';  License='E3' }
)

$mockSites = @(
    @{ Url='https://contoso.sharepoint.com/sites/finance';       Title='Finance';           PrimaryOwner='s.chen@contoso.com';    SecondaryOwner='j.miller@contoso.com'; Sharing='Disabled';                      StorageGB=4.2;  LastActivity=(Get-Date).AddDays(-12);  },
    @{ Url='https://contoso.sharepoint.com/sites/operations';    Title='Operations';        PrimaryOwner='m.williams@contoso.com'; SecondaryOwner='';                     Sharing='ExternalUserSharingOnly';       StorageGB=18.7; LastActivity=(Get-Date).AddDays(-45);  },
    @{ Url='https://contoso.sharepoint.com/sites/hr-policies';   Title='HR Policies';       PrimaryOwner='j.okafor@contoso.com';  SecondaryOwner='p.patel@contoso.com';  Sharing='Disabled';                      StorageGB=2.1;  LastActivity=(Get-Date).AddDays(-8);   },
    @{ Url='https://contoso.sharepoint.com/sites/it-projects';   Title='IT Projects';       PrimaryOwner='p.patel@contoso.com';   SecondaryOwner='a.jones@contoso.com';  Sharing='Disabled';                      StorageGB=31.4; LastActivity=(Get-Date).AddDays(-22);  },
    @{ Url='https://contoso.sharepoint.com/sites/old-marketing'; Title='Marketing Archive'; PrimaryOwner='';                      SecondaryOwner='';                     Sharing='ExternalUserAndGuestSharing';   StorageGB=8.9;  LastActivity=(Get-Date).AddDays(-142); },
    @{ Url='https://contoso.sharepoint.com/sites/legal';         Title='Legal';             PrimaryOwner='d.ross@contoso.com';   SecondaryOwner='';                     Sharing='Disabled';                      StorageGB=11.2; LastActivity=(Get-Date).AddDays(-67);  }
)

$mockTeams = @(
    @{ Name='FIN-Budget Planning 2025'; Owner='s.chen@contoso.com';    Members=8;  LastActivity=(Get-Date).AddDays(-5);   NamingOK=$true  },
    @{ Name='OPS-Logistics Q1';         Owner='m.williams@contoso.com'; Members=14; LastActivity=(Get-Date).AddDays(-18);  NamingOK=$true  },
    @{ Name='Random project stuff';     Owner='';                       Members=3;  LastActivity=(Get-Date).AddDays(-112); NamingOK=$false },
    @{ Name='HR-Onboarding Templates';  Owner='j.okafor@contoso.com';  Members=6;  LastActivity=(Get-Date).AddDays(-9);   NamingOK=$true  },
    @{ Name='IT Infra Team';            Owner='p.patel@contoso.com';   Members=5;  LastActivity=(Get-Date).AddDays(-33);  NamingOK=$false },
    @{ Name='2022 Holiday Party';       Owner='';                       Members=0;  LastActivity=(Get-Date).AddDays(-487); NamingOK=$false }
)

$mockPermissions = @(
    @{ Site='Finance';       Group='Finance Owners';   Principal='s.chen@contoso.com';        Role='Full Control'; External=$false },
    @{ Site='Finance';       Group='Finance Members';  Principal='m.williams@contoso.com';    Role='Edit';         External=$false },
    @{ Site='Finance';       Group='Finance Members';  Principal='j.miller@contoso.com';      Role='Edit';         External=$false },
    @{ Site='Operations';    Group='Ops Members';      Principal='vendor_bob#EXT#@contoso.com'; Role='Edit';       External=$true  },
    @{ Site='Operations';    Group='Ops Members';      Principal='supplier_acme#EXT#@contoso.com'; Role='Read';    External=$true  },
    @{ Site='HR Policies';   Group='HR Owners';        Principal='j.okafor@contoso.com';      Role='Full Control'; External=$false },
    @{ Site='IT Projects';   Group='IT Members';       Principal='p.patel@contoso.com';       Role='Full Control'; External=$false },
    @{ Site='IT Projects';   Group='IT Members';       Principal='contractor_dev#EXT#@contoso.com'; Role='Edit'; External=$true  },
    @{ Site='Legal';         Group='Legal Owners';     Principal='d.ross@contoso.com';        Role='Full Control'; External=$false }
)


# ─────────────────────────────────────────────────────────────────────────────
# DEMO 1 — User Onboarding
# ─────────────────────────────────────────────────────────────────────────────
Write-Banner "DEMO 1 of 5  --  New-UserOnboarding.ps1  [DRY RUN]"
Write-Host "  Command:" -ForegroundColor White
Write-Host "  .\scripts\New-UserOnboarding.ps1 -FirstName Sarah -LastName Chen -Department Finance" -ForegroundColor DarkGray
Write-Host "      -Manager j.miller@contoso.com -LicenseSku E3" -ForegroundColor DarkGray
Write-Host "      -SharePointSiteUrl https://contoso.sharepoint.com/sites/finance" -ForegroundColor DarkGray
Write-Host "      -TeamsTeamName 'FIN-Budget Planning 2025'" -ForegroundColor DarkGray
Write-Host ""

$newUser = $mockUsers[0]
Write-Step '1/5' "Connecting to Microsoft Graph, SharePoint, Teams..."
Start-Sleep -Milliseconds 600
Write-OK "Connected."

Write-Step '2/5' "Creating user account..."
Start-Sleep -Milliseconds 800
Write-OK "Created: $($newUser.UPN)"
Write-Info "Display name:  $($newUser.DisplayName)"
Write-Info "Department:    $($newUser.Dept)"
Write-Info "Manager:       $($newUser.Manager)"
Write-Info "Temp password: Onboard@7823!  (must change at first login)"

Write-Step '3/5' "Assigning license: $($newUser.License)..."
Start-Sleep -Milliseconds 500
Write-OK "Microsoft 365 E3 license assigned."

Write-Step '4/5' "Adding to SharePoint site: Finance Members group..."
Start-Sleep -Milliseconds 400
Write-OK "Added to Finance Members group."

Write-Step '5/5' "Adding to Teams team: FIN-Budget Planning 2025..."
Start-Sleep -Milliseconds 400
Write-OK "Added as Member."

Write-Host ""
Write-Host "  Onboarding complete for $($newUser.DisplayName)." -ForegroundColor Green


# ─────────────────────────────────────────────────────────────────────────────
# DEMO 2 — Site Governance Report
# ─────────────────────────────────────────────────────────────────────────────
Write-Banner "DEMO 2 of 5  --  Get-SiteGovernanceReport.ps1"

Write-Step 'CONNECT' "Connecting to SharePoint Online tenant: contoso..."
Start-Sleep -Milliseconds 600
Write-OK "Connected."
Write-Step 'FETCH'   "Found $($mockSites.Count) site collections. Auditing..."
Write-Host ""

$siteResults = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($site in $mockSites) {
    $flags = @()
    if (-not $site.SecondaryOwner) { $flags += 'NO_SECONDARY_OWNER' }
    if ($site.Sharing -ne 'Disabled') { $flags += "EXTERNAL_SHARING:$($site.Sharing)" }
    if ($site.StorageGB -gt 25) { $flags += 'STORAGE_OVER_25GB' }
    $daysSince = [int]((Get-Date) - $site.LastActivity).TotalDays
    if ($daysSince -gt 90) { $flags += "INACTIVE_${daysSince}_DAYS" }

    $hasIssues = $flags.Count -gt 0
    $flagStr   = if ($flags.Count -gt 0) { $flags -join '; ' } else { '' }

    if ($hasIssues) {
        Write-Flag "$($site.Title.PadRight(22)) $flagStr"
    } else {
        Write-OK   "$($site.Title)"
    }

    $siteResults.Add([PSCustomObject]@{
        SiteUrl          = $site.Url
        Title            = $site.Title
        PrimaryOwner     = $site.PrimaryOwner
        SecondaryOwner   = $site.SecondaryOwner
        ExternalSharing  = $site.Sharing
        StorageUsedGB    = $site.StorageGB
        StorageLimitGB   = 25
        LastActivityDate = $site.LastActivity.ToString('yyyy-MM-dd')
        DaysSinceActivity = [int]((Get-Date) - $site.LastActivity).TotalDays
        Flags            = $flagStr
        HasIssues        = $hasIssues
    })
}

$reportPath = Join-Path $outputDir "site-governance-report-sample.csv"
$siteResults | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8

$flagged = ($siteResults | Where-Object HasIssues).Count
Write-Host ""
Write-OK "Report saved: sample-outputs/site-governance-report-sample.csv"
Write-Warn "$flagged of $($mockSites.Count) sites have governance issues."


# ─────────────────────────────────────────────────────────────────────────────
# DEMO 3 — Access Review
# ─────────────────────────────────────────────────────────────────────────────
Write-Banner "DEMO 3 of 5  --  Get-AccessReview.ps1"

Write-Step 'CONNECT' "Connecting to SharePoint Online..."
Start-Sleep -Milliseconds 500
Write-OK "Connected."
Write-Step 'SCAN'    "Scanning permissions across $($mockSites.Count) sites..."
Write-Host ""

$accessResults = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($perm in $mockPermissions) {
    if ($perm.External) {
        Write-Flag "EXTERNAL USER  $($perm.Principal.PadRight(42)) [$($perm.Role)]  on $($perm.Site)"
    } else {
        Write-Info "               $($perm.Principal.PadRight(42)) [$($perm.Role)]  on $($perm.Site)"
    }

    $accessResults.Add([PSCustomObject]@{
        SiteTitle      = $perm.Site
        GroupName      = $perm.Group
        RoleDefinition = $perm.Role
        PrincipalName  = $perm.Principal
        LoginName      = $perm.Principal
        IsExternal     = $perm.External
        ReviewDate     = (Get-Date -Format 'yyyy-MM-dd')
        ReviewStatus   = 'Pending'
    })
}

$accessPath = Join-Path $outputDir "access-review-sample.csv"
$accessResults | Export-Csv -Path $accessPath -NoTypeInformation -Encoding UTF8

$extCount = ($accessResults | Where-Object IsExternal).Count
Write-Host ""
Write-OK "Report saved: sample-outputs/access-review-sample.csv"
Write-Flag "$extCount external/guest users found with active site access -- flagged for review."


# ─────────────────────────────────────────────────────────────────────────────
# DEMO 4 — Teams Lifecycle
# ─────────────────────────────────────────────────────────────────────────────
Write-Banner "DEMO 4 of 5  --  Set-TeamsLifecyclePolicy.ps1"

Write-Step 'CONNECT' "Connecting to Microsoft Teams..."
Start-Sleep -Milliseconds 500
Write-OK "Connected. Found $($mockTeams.Count) teams."
Write-Host ""

$teamsResults = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($team in $mockTeams) {
    $flags = @()
    if (-not $team.Owner) { $flags += 'NO_OWNER' }
    if ($team.Members -eq 0) { $flags += 'NO_MEMBERS' }
    if (-not $team.NamingOK) { $flags += 'NAMING_VIOLATION' }
    $daysSince = [int]((Get-Date) - $team.LastActivity).TotalDays
    if ($daysSince -gt 90) { $flags += "INACTIVE_${daysSince}_DAYS" }

    $hasIssues = $flags.Count -gt 0
    $flagStr   = if ($flags.Count -gt 0) { $flags -join '; ' } else { '' }

    if ($hasIssues) {
        Write-Flag "$($team.Name.PadRight(32)) $flagStr"
    } else {
        Write-OK   $team.Name
    }

    $teamsResults.Add([PSCustomObject]@{
        DisplayName       = $team.Name
        Owners            = $team.Owner
        OwnerCount        = if ($team.Owner) { 1 } else { 0 }
        MemberCount       = $team.Members
        LastActivityDate  = $team.LastActivity.ToString('yyyy-MM-dd')
        DaysSinceActivity = $daysSince
        NamingViolation   = (-not $team.NamingOK)
        Flags             = $flagStr
        HasIssues         = $hasIssues
        Action            = 'Pending Review'
    })
}

$teamsPath = Join-Path $outputDir "teams-lifecycle-sample.csv"
$teamsResults | Export-Csv -Path $teamsPath -NoTypeInformation -Encoding UTF8

$flaggedTeams = ($teamsResults | Where-Object HasIssues).Count
Write-Host ""
Write-OK "Report saved: sample-outputs/teams-lifecycle-sample.csv"
Write-Warn "$flaggedTeams of $($mockTeams.Count) teams flagged for review."


# ─────────────────────────────────────────────────────────────────────────────
# DEMO 5 — Offboarding
# ─────────────────────────────────────────────────────────────────────────────
Write-Banner "DEMO 5 of 5  --  Remove-UserOffboarding.ps1  [DRY RUN]"
Write-Host "  Command:" -ForegroundColor White
Write-Host "  .\scripts\Remove-UserOffboarding.ps1 -UserPrincipalName m.williams@contoso.com" -ForegroundColor DarkGray
Write-Host "      -OneDriveTransferTo j.miller@contoso.com -ArchiveMailbox `$true" -ForegroundColor DarkGray
Write-Host ""

$leavingUser = $mockUsers[1]
Write-Step 'CONNECT'  "Connecting to Microsoft 365 services..."
Start-Sleep -Milliseconds 600
Write-OK "Connected."
Write-Step 'VALIDATE' "Target user: $($leavingUser.DisplayName) ($($leavingUser.UPN))"
Write-Step 'SESSIONS' "Revoking all active sign-in sessions..."
Start-Sleep -Milliseconds 500
Write-OK "All sessions revoked. User is now signed out of all devices."
Write-Step 'GROUPS'   "Removing from Microsoft 365 groups and Teams..."
Start-Sleep -Milliseconds 700
Write-OK "Removed from 4 groups: OPS-Logistics Q1, Operations Members, All Staff, FIN-Budget Planning 2025."
Write-Step 'ONEDRIVE' "Transferring OneDrive to j.miller@contoso.com..."
Start-Sleep -Milliseconds 600
Write-OK "OneDrive ownership transferred: /sites/m_williams_contoso_com/"
Write-Step 'MAILBOX'  "Converting mailbox to shared mailbox..."
Start-Sleep -Milliseconds 500
Write-OK "Mailbox converted. Full access granted to j.miller@contoso.com."
Write-Step 'LICENSES' "Removing Microsoft 365 E3 license..."
Start-Sleep -Milliseconds 400
Write-OK "1 license removed."
Write-Step 'DISABLE'  "Disabling account..."
Start-Sleep -Milliseconds 300
Write-OK "Account disabled."

Write-Host ""
Write-Host "  Offboarding complete for $($leavingUser.DisplayName)." -ForegroundColor Green
Write-Info "Audit log saved to: .\logs\offboarding-$(Get-Date -Format 'yyyy-MM-dd-HHmm').log"


# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
Write-Banner "DEMO COMPLETE -- Summary"
Write-Host "  Reports generated in sample-outputs/:" -ForegroundColor White
Write-Host "    site-governance-report-sample.csv   -- $($siteResults.Count) sites, $flagged flagged" -ForegroundColor Gray
Write-Host "    access-review-sample.csv            -- $($accessResults.Count) permission entries, $extCount external users" -ForegroundColor Gray
Write-Host "    teams-lifecycle-sample.csv          -- $($teamsResults.Count) teams, $flaggedTeams flagged" -ForegroundColor Gray
Write-Host ""
Write-Host "  To run against a real tenant, use the scripts in scripts/ with valid M365 credentials." -ForegroundColor DarkCyan
Write-Host "  Each script supports -WhatIf for a safe preview before making any changes." -ForegroundColor DarkCyan
Write-Host ""
