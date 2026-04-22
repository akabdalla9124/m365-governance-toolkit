<#
.SYNOPSIS
    Audits all SharePoint Online sites and flags governance issues.

.DESCRIPTION
    Scans every site collection in the tenant and checks for common governance
    problems: missing secondary owner, external sharing enabled, storage over
    threshold, and no activity in the past N days. Exports findings to CSV.

.PARAMETER TenantName
    Your tenant name (the part before .sharepoint.com).

.PARAMETER InactiveDaysThreshold
    Number of days without activity before a site is flagged. Default: 90.

.PARAMETER StorageWarningGB
    Storage threshold (GB) above which a site is flagged. Default: 25.

.PARAMETER OutputPath
    Path for the CSV output file.

.EXAMPLE
    .\Get-SiteGovernanceReport.ps1 `
        -TenantName "contoso" `
        -OutputPath ".\reports\site-governance-2025-01-15.csv"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string] $TenantName,
    [int]    $InactiveDaysThreshold = 90,
    [int]    $StorageWarningGB      = 25,
    [string] $OutputPath = ".\reports\site-governance-$(Get-Date -Format 'yyyy-MM-dd').csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$reportDir = Split-Path $OutputPath
if ($reportDir -and -not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }

#region -- Connect ------------------------------------------------------------
Write-Host "Connecting to SharePoint Online..." -ForegroundColor Cyan
Connect-SPOService -Url "https://$TenantName-admin.sharepoint.com"
Connect-PnPOnline -Url "https://$TenantName.sharepoint.com" -Interactive
#endregion

#region -- Get sites ----------------------------------------------------------
Write-Host "Fetching all site collections..." -ForegroundColor Cyan
$sites = Get-SPOSite -Limit All -IncludePersonalSite $false
Write-Host "  Found $($sites.Count) sites." -ForegroundColor Green
#endregion

#region -- Audit each site ----------------------------------------------------
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$cutoffDate = (Get-Date).AddDays(-$InactiveDaysThreshold)
$counter = 0

foreach ($site in $sites) {
    $counter++
    Write-Progress -Activity "Auditing sites" -Status "$counter / $($sites.Count): $($site.Url)" -PercentComplete (($counter / $sites.Count) * 100)

    $flags = [System.Collections.Generic.List[string]]::new()

    # Ownership check
    $owners = @()
    try {
        Connect-PnPOnline -Url $site.Url -Interactive
        $ownerGroup = Get-PnPGroup -AssociatedOwnerGroup -ErrorAction SilentlyContinue
        if ($ownerGroup) {
            $owners = Get-PnPGroupMember -Group $ownerGroup | Where-Object { $_.LoginName -notlike "*spo-grid*" }
        }
    } catch { }

    $primaryOwner   = if ($owners.Count -gt 0) { $owners[0].Email } else { "None" }
    $secondaryOwner = if ($owners.Count -gt 1) { $owners[1].Email } else { "None" }

    if ($owners.Count -lt 2) { $flags.Add("NO_SECONDARY_OWNER") }

    # External sharing
    if ($site.SharingCapability -ne 'Disabled') {
        $flags.Add("EXTERNAL_SHARING_ENABLED:$($site.SharingCapability)")
    }

    # Storage
    $storageGB = [math]::Round($site.StorageUsageCurrent / 1024, 2)
    if ($storageGB -gt $StorageWarningGB) {
        $flags.Add("STORAGE_OVER_${StorageWarningGB}GB")
    }

    # Activity
    $lastActivity = $site.LastContentModifiedDate
    if ($lastActivity -lt $cutoffDate) {
        $daysSince = [int]((Get-Date) - $lastActivity).TotalDays
        $flags.Add("INACTIVE_${daysSince}_DAYS")
    }

    $results.Add([PSCustomObject]@{
        SiteUrl              = $site.Url
        Title                = $site.Title
        Template             = $site.Template
        PrimaryOwner         = $primaryOwner
        SecondaryOwner       = $secondaryOwner
        ExternalSharing      = $site.SharingCapability
        StorageUsedGB        = $storageGB
        StorageLimitGB       = [math]::Round($site.StorageQuota / 1024, 0)
        LastActivityDate     = $lastActivity.ToString("yyyy-MM-dd")
        DaysSinceActivity    = [int]((Get-Date) - $lastActivity).TotalDays
        Flags                = ($flags -join "; ")
        HasIssues            = ($flags.Count -gt 0).ToString()
    })
}

Write-Progress -Activity "Auditing sites" -Completed
#endregion

#region -- Export -------------------------------------------------------------
$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

$flaggedCount = ($results | Where-Object { $_.HasIssues -eq 'True' }).Count
Write-Host ""
Write-Host "Governance report complete." -ForegroundColor Green
Write-Host "  Total sites:    $($results.Count)"
Write-Host "  Sites flagged:  $flaggedCount"
Write-Host "  Report saved:   $OutputPath"
#endregion
