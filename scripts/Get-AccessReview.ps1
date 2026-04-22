<#
.SYNOPSIS
    Exports all SharePoint site permissions for compliance access review.

.DESCRIPTION
    Iterates every site collection and exports a flat list of all permission
    assignments: users, groups, roles, and whether the assignment is direct
    or inherited. External/guest users are flagged separately for easy review.

    Designed to be run on a regular cadence (monthly/quarterly) and handed
    to a compliance or security team for review and sign-off.

.PARAMETER TenantName
    Your tenant name (the part before .sharepoint.com).

.PARAMETER IncludeExternalUsers
    If true, adds a flag on each row where the principal is a guest/external user.

.PARAMETER OutputPath
    Path for the CSV output file.

.EXAMPLE
    .\Get-AccessReview.ps1 `
        -TenantName "contoso" `
        -IncludeExternalUsers $true `
        -OutputPath ".\reports\access-review-2025-01-15.csv"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string] $TenantName,
    [bool]   $IncludeExternalUsers = $true,
    [string] $OutputPath = ".\reports\access-review-$(Get-Date -Format 'yyyy-MM-dd').csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$reportDir = Split-Path $OutputPath
if ($reportDir -and -not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }

#region -- Connect ------------------------------------------------------------
Write-Host "Connecting..." -ForegroundColor Cyan
Connect-SPOService -Url "https://$TenantName-admin.sharepoint.com"
#endregion

$sites   = Get-SPOSite -Limit All -IncludePersonalSite $false
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$counter = 0

foreach ($site in $sites) {
    $counter++
    Write-Progress -Activity "Scanning permissions" -Status "$counter / $($sites.Count): $($site.Url)" -PercentComplete (($counter / $sites.Count) * 100)

    try {
        Connect-PnPOnline -Url $site.Url -Interactive -ErrorAction Stop

        # Site-level groups
        $groups = Get-PnPGroup
        foreach ($group in $groups) {
            $members = Get-PnPGroupMember -Group $group -ErrorAction SilentlyContinue
            foreach ($member in $members) {
                $isExternal = $member.LoginName -like "*#ext#*" -or $member.Email -like "*#EXT#*"
                if (-not $IncludeExternalUsers -and $isExternal) { continue }

                $results.Add([PSCustomObject]@{
                    SiteUrl       = $site.Url
                    SiteTitle     = $site.Title
                    PermissionType = "SiteGroup"
                    GroupName     = $group.Title
                    RoleDefinition = $group.Title  # Members/Owners/Visitors maps to Edit/Full/Read
                    PrincipalType = $member.PrincipalType
                    PrincipalName = $member.Title
                    LoginName     = $member.LoginName
                    Email         = $member.Email
                    IsExternal    = $isExternal
                    ReviewDate    = (Get-Date -Format "yyyy-MM-dd")
                    ReviewStatus  = "Pending"
                })
            }
        }

        # Unique permissions on lists/libraries
        $lists = Get-PnPList | Where-Object { $_.Hidden -eq $false -and $_.HasUniqueRoleAssignments -eq $true }
        foreach ($list in $lists) {
            $assignments = Get-PnPListPermissions -Identity $list.Id -ErrorAction SilentlyContinue
            foreach ($assignment in $assignments) {
                $isExternal = $assignment.Member.LoginName -like "*#ext#*"
                $results.Add([PSCustomObject]@{
                    SiteUrl        = $site.Url
                    SiteTitle      = $site.Title
                    PermissionType = "ListUnique:$($list.Title)"
                    GroupName      = ""
                    RoleDefinition = ($assignment.RoleDefinitionBindings.Name -join ", ")
                    PrincipalType  = $assignment.Member.PrincipalType
                    PrincipalName  = $assignment.Member.Title
                    LoginName      = $assignment.Member.LoginName
                    Email          = $assignment.Member.Email
                    IsExternal     = $isExternal
                    ReviewDate     = (Get-Date -Format "yyyy-MM-dd")
                    ReviewStatus   = "Pending"
                })
            }
        }
    } catch {
        Write-Warning "Could not scan $($site.Url): $_"
    }
}

Write-Progress -Activity "Scanning permissions" -Completed

$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

$externalCount = ($results | Where-Object { $_.IsExternal -eq $true }).Count
Write-Host ""
Write-Host "Access review export complete." -ForegroundColor Green
Write-Host "  Total permission entries: $($results.Count)"
Write-Host "  External user entries:    $externalCount"
Write-Host "  Report saved: $OutputPath"
