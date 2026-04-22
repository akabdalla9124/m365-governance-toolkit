<#
.SYNOPSIS
    Provisions a governance-compliant SharePoint Online site from a standard template.

.DESCRIPTION
    Creates a new SharePoint site with governance settings applied from the start:
    external sharing disabled by default, two required owners, standard document
    library structure, and registration in the tenant site directory list.

    Prevents the most common governance drift problem: sites created ad-hoc with
    no ownership structure or sharing policy.

.PARAMETER SiteTitle
    Display name for the new site.

.PARAMETER SiteAlias
    URL alias (no spaces). Used to build the site URL.

.PARAMETER PrimaryOwner
    UPN of the primary site owner.

.PARAMETER SecondaryOwner
    UPN of the secondary site owner. Required — sites with a single owner are
    a governance risk when that person leaves.

.PARAMETER Template
    Site template. Accepts: TeamSite, CommunicationSite. Default: TeamSite.

.PARAMETER ExternalSharingPolicy
    External sharing level. Accepts: Disabled, ExistingExternalUserSharingOnly,
    ExternalUserSharingOnly, ExternalUserAndGuestSharing. Default: Disabled.

.EXAMPLE
    .\New-SharePointSiteProvisioning.ps1 `
        -SiteTitle "HR Operations" `
        -SiteAlias "hr-operations" `
        -PrimaryOwner "jane.smith@contoso.com" `
        -SecondaryOwner "john.doe@contoso.com" `
        -Template "TeamSite" `
        -ExternalSharingPolicy "Disabled"
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)] [string] $SiteTitle,
    [Parameter(Mandatory)] [string] $SiteAlias,
    [Parameter(Mandatory)] [string] $PrimaryOwner,
    [Parameter(Mandatory)] [string] $SecondaryOwner,
    [ValidateSet("TeamSite","CommunicationSite")]
    [string] $Template = "TeamSite",
    [ValidateSet("Disabled","ExistingExternalUserSharingOnly","ExternalUserSharingOnly","ExternalUserAndGuestSharing")]
    [string] $ExternalSharingPolicy = "Disabled"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region -- Connect ------------------------------------------------------------
Write-Host "Connecting to SharePoint Online..." -ForegroundColor Cyan
$tenantDomain = (Connect-MgGraph -Scopes "Sites.FullControl.All" | Out-Null; (Get-MgDomain | Where-Object IsDefault).Id)
$adminUrl     = "https://$($tenantDomain.Split('.')[0])-admin.sharepoint.com"
$tenantUrl    = "https://$($tenantDomain.Split('.')[0]).sharepoint.com"

Connect-SPOService -Url $adminUrl
Connect-PnPOnline -Url $tenantUrl -Interactive
#endregion

#region -- Create site --------------------------------------------------------
$siteUrl = "$tenantUrl/sites/$SiteAlias"
Write-Host "Creating site: $siteUrl" -ForegroundColor Cyan

if ($Template -eq "TeamSite") {
    New-PnPSite -Type TeamSite `
        -Title $SiteTitle `
        -Alias $SiteAlias `
        -Owner $PrimaryOwner `
        -IsPublic:$false
} else {
    New-PnPSite -Type CommunicationSite `
        -Title $SiteTitle `
        -Url $siteUrl `
        -Owner $PrimaryOwner
}

# Brief wait for provisioning
Start-Sleep -Seconds 30
Write-Host "  Site created: $siteUrl" -ForegroundColor Green
#endregion

#region -- Apply governance settings -----------------------------------------
Write-Host "Applying governance settings..." -ForegroundColor Cyan

Set-SPOSite -Identity $siteUrl `
    -SharingCapability $ExternalSharingPolicy `
    -StorageQuota 25600 `
    -DisableCompanyWideSharingLinks "Disabled"

Write-Host "  External sharing: $ExternalSharingPolicy"
Write-Host "  Storage quota: 25 GB"
#endregion

#region -- Add secondary owner ------------------------------------------------
Write-Host "Adding secondary owner: $SecondaryOwner" -ForegroundColor Cyan
Connect-PnPOnline -Url $siteUrl -Interactive

$ownerGroup = Get-PnPGroup -AssociatedOwnerGroup
Add-PnPGroupMember -Group $ownerGroup -LoginName $SecondaryOwner
Write-Host "  Secondary owner added." -ForegroundColor Green
#endregion

#region -- Create default document library structure -------------------------
Write-Host "Setting up default document library structure..." -ForegroundColor Cyan

$folders = @("General", "Policies and Procedures", "Templates", "Archive")
foreach ($folder in $folders) {
    Add-PnPFolder -Name $folder -Folder "Shared Documents" -ErrorAction SilentlyContinue
    Write-Host "  Created folder: $folder"
}
#endregion

#region -- Register in site directory ----------------------------------------
Write-Host "Registering in site directory..." -ForegroundColor Cyan

$directoryList = "Site Directory"
try {
    $list = Get-PnPList -Identity $directoryList -ErrorAction Stop
    Add-PnPListItem -List $list -Values @{
        Title        = $SiteTitle
        SiteURL      = $siteUrl
        PrimaryOwner = $PrimaryOwner
        SecondaryOwner = $SecondaryOwner
        Template     = $Template
        CreatedDate  = (Get-Date -Format "yyyy-MM-dd")
    } | Out-Null
    Write-Host "  Registered in site directory." -ForegroundColor Green
} catch {
    Write-Warning "  Site directory list not found — skipping registration. Create a 'Site Directory' list at the root site to enable this."
}
#endregion

Write-Host ""
Write-Host "Site provisioning complete." -ForegroundColor Green
Write-Host "  URL:             $siteUrl"
Write-Host "  Primary Owner:   $PrimaryOwner"
Write-Host "  Secondary Owner: $SecondaryOwner"
Write-Host "  External Sharing: $ExternalSharingPolicy"
