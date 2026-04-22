<#
.SYNOPSIS
    Provisions a new Microsoft 365 user end-to-end.

.DESCRIPTION
    Creates the user account, assigns a license, adds the user to a SharePoint
    site group, and adds them to a Teams team. Designed for consistent,
    repeatable onboarding across multi-site M365 tenants.

.PARAMETER FirstName
    User's first name.

.PARAMETER LastName
    User's last name.

.PARAMETER Department
    Department name. Used to build the display name and set the department attribute.

.PARAMETER Manager
    UPN of the user's manager (e.g. john.doe@contoso.com).

.PARAMETER LicenseSku
    SKU part number of the license to assign (e.g. ENTERPRISEPREMIUM, SPE_E3).

.PARAMETER SharePointSiteUrl
    Full URL of the SharePoint site to add the user to as a member.

.PARAMETER TeamsTeamName
    Display name of the Teams team to add the user to.

.EXAMPLE
    .\New-UserOnboarding.ps1 `
        -FirstName "Jane" `
        -LastName "Smith" `
        -Department "Operations" `
        -Manager "john.doe@contoso.com" `
        -LicenseSku "ENTERPRISEPREMIUM" `
        -SharePointSiteUrl "https://contoso.sharepoint.com/sites/Operations" `
        -TeamsTeamName "Operations Team"
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)] [string] $FirstName,
    [Parameter(Mandatory)] [string] $LastName,
    [Parameter(Mandatory)] [string] $Department,
    [Parameter(Mandatory)] [string] $Manager,
    [Parameter(Mandatory)] [string] $LicenseSku,
    [Parameter(Mandatory)] [string] $SharePointSiteUrl,
    [Parameter(Mandatory)] [string] $TeamsTeamName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region -- Connect ------------------------------------------------------------
Write-Host "[1/5] Connecting to Microsoft Graph and SharePoint..." -ForegroundColor Cyan

Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All", "GroupMember.ReadWrite.All"
Connect-PnPOnline -Url $SharePointSiteUrl -Interactive
Connect-MicrosoftTeams
#endregion

#region -- Derive values ------------------------------------------------------
$tenantDomain = (Get-MgDomain | Where-Object IsDefault).Id
$upn          = "$($FirstName.ToLower()).$($LastName.ToLower())@$tenantDomain"
$displayName  = "$FirstName $LastName"
$tempPassword = "Onboard@$(Get-Random -Minimum 1000 -Maximum 9999)!"
#endregion

#region -- Create user --------------------------------------------------------
Write-Host "[2/5] Creating user account: $upn" -ForegroundColor Cyan

$passwordProfile = @{
    Password                      = $tempPassword
    ForceChangePasswordNextSignIn = $true
}

$newUser = New-MgUser `
    -DisplayName      $displayName `
    -GivenName        $FirstName `
    -Surname          $LastName `
    -UserPrincipalName $upn `
    -Department       $Department `
    -PasswordProfile  $passwordProfile `
    -AccountEnabled   $true `
    -MailNickname     "$($FirstName.ToLower())$($LastName.ToLower())"

Write-Host "  Created: $($newUser.UserPrincipalName) (ID: $($newUser.Id))" -ForegroundColor Green

# Set manager
$managerObj = Get-MgUser -Filter "userPrincipalName eq '$Manager'"
Set-MgUserManagerByRef -UserId $newUser.Id -BodyParameter @{
    "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($managerObj.Id)"
}
#endregion

#region -- Assign license -----------------------------------------------------
Write-Host "[3/5] Assigning license: $LicenseSku" -ForegroundColor Cyan

$sku = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq $LicenseSku }
if (-not $sku) { throw "License SKU '$LicenseSku' not found in tenant." }

Set-MgUserLicense -UserId $newUser.Id `
    -AddLicenses @{ SkuId = $sku.SkuId } `
    -RemoveLicenses @()

Write-Host "  License assigned." -ForegroundColor Green
#endregion

#region -- Add to SharePoint site ---------------------------------------------
Write-Host "[4/5] Adding to SharePoint site: $SharePointSiteUrl" -ForegroundColor Cyan

Add-PnPGroupMember `
    -LoginName $upn `
    -Group     (Get-PnPGroup | Where-Object { $_.Title -like "*Members*" } | Select-Object -First 1)

Write-Host "  Added to SharePoint Members group." -ForegroundColor Green
#endregion

#region -- Add to Teams -------------------------------------------------------
Write-Host "[5/5] Adding to Teams team: $TeamsTeamName" -ForegroundColor Cyan

$team = Get-Team -DisplayName $TeamsTeamName | Select-Object -First 1
if (-not $team) { throw "Team '$TeamsTeamName' not found." }

Add-TeamUser -GroupId $team.GroupId -User $upn -Role Member

Write-Host "  Added to Teams team." -ForegroundColor Green
#endregion

Write-Host ""
Write-Host "Onboarding complete for $displayName" -ForegroundColor Green
Write-Host "  UPN:           $upn"
Write-Host "  Temp Password: $tempPassword  (user must change at first login)"
Write-Host "  SharePoint:    $SharePointSiteUrl"
Write-Host "  Teams:         $TeamsTeamName"
