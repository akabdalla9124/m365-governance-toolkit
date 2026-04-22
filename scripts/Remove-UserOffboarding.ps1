<#
.SYNOPSIS
    Cleanly offboards a Microsoft 365 user.

.DESCRIPTION
    Revokes all active sessions, removes the user from all SharePoint and Teams
    groups, transfers OneDrive content ownership, converts the mailbox to shared
    (for mail continuity), removes licenses, and disables the account.

    All actions are logged to a timestamped file for audit purposes.

.PARAMETER UserPrincipalName
    UPN of the user being offboarded.

.PARAMETER OneDriveTransferTo
    UPN of the user who will receive ownership of the departing user's OneDrive.

.PARAMETER ArchiveMailbox
    If true, converts the mailbox to a shared mailbox instead of deleting it.

.PARAMETER LogPath
    Path to write the audit log. Defaults to .\logs\offboarding-<date>.log

.EXAMPLE
    .\Remove-UserOffboarding.ps1 `
        -UserPrincipalName "jane.smith@contoso.com" `
        -OneDriveTransferTo "john.doe@contoso.com" `
        -ArchiveMailbox $true
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)] [string] $UserPrincipalName,
    [Parameter(Mandatory)] [string] $OneDriveTransferTo,
    [bool]   $ArchiveMailbox = $true,
    [string] $LogPath = ".\logs\offboarding-$(Get-Date -Format 'yyyy-MM-dd-HHmm').log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logDir = Split-Path $LogPath
if ($logDir -and -not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

function Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Write-Host $line -ForegroundColor $(if ($Level -eq 'ERROR') { 'Red' } elseif ($Level -eq 'WARN') { 'Yellow' } else { 'White' })
    Add-Content -Path $LogPath -Value $line
}

#region -- Connect ------------------------------------------------------------
Log "Connecting to Microsoft 365 services..."
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All", "GroupMember.ReadWrite.All"
Connect-ExchangeOnline -ShowBanner:$false
Connect-MicrosoftTeams
Connect-SPOService -Url "https://$(((Get-MgDomain | Where-Object IsDefault).Id).Split('.')[0])-admin.sharepoint.com"
#endregion

#region -- Validate user ------------------------------------------------------
$user = Get-MgUser -Filter "userPrincipalName eq '$UserPrincipalName'" -Property Id,DisplayName,UserPrincipalName
if (-not $user) { throw "User '$UserPrincipalName' not found." }
Log "Target user: $($user.DisplayName) ($UserPrincipalName)"
#endregion

#region -- Revoke sessions ----------------------------------------------------
Log "Revoking all active sessions..."
Revoke-MgUserSignInSession -UserId $user.Id | Out-Null
Log "Sessions revoked."
#endregion

#region -- Remove from all groups ---------------------------------------------
Log "Removing from all Microsoft 365 groups and Teams..."
$groups = Get-MgUserMemberOf -UserId $user.Id -All
foreach ($group in $groups) {
    try {
        Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $user.Id
        Log "  Removed from group: $($group.AdditionalProperties.displayName)"
    } catch {
        Log "  Could not remove from group $($group.AdditionalProperties.displayName): $_" 'WARN'
    }
}
#endregion

#region -- Transfer OneDrive --------------------------------------------------
Log "Transferring OneDrive to $OneDriveTransferTo..."
$oneDriveSite = Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Owner -eq '$UserPrincipalName'" |
    Where-Object { $_.Url -like "*/personal/*" } |
    Select-Object -First 1

if ($oneDriveSite) {
    Set-SPOSite -Identity $oneDriveSite.Url -Owner $OneDriveTransferTo
    Log "  OneDrive transferred: $($oneDriveSite.Url)"
} else {
    Log "  No OneDrive site found for user." 'WARN'
}
#endregion

#region -- Archive mailbox ----------------------------------------------------
if ($ArchiveMailbox) {
    Log "Converting mailbox to shared mailbox..."
    Set-Mailbox -Identity $UserPrincipalName -Type Shared
    Add-MailboxPermission -Identity $UserPrincipalName -User $OneDriveTransferTo -AccessRights FullAccess -InheritanceType All | Out-Null
    Log "  Mailbox converted to shared. Access granted to $OneDriveTransferTo."
}
#endregion

#region -- Remove licenses ----------------------------------------------------
Log "Removing licenses..."
$assignedLicenses = (Get-MgUserLicenseDetail -UserId $user.Id).SkuId
if ($assignedLicenses) {
    Set-MgUserLicense -UserId $user.Id -RemoveLicenses $assignedLicenses -AddLicenses @()
    Log "  Removed $($assignedLicenses.Count) license(s)."
} else {
    Log "  No licenses found." 'WARN'
}
#endregion

#region -- Disable account ----------------------------------------------------
Log "Disabling account..."
Update-MgUser -UserId $user.Id -AccountEnabled:$false
Log "Account disabled."
#endregion

Log "Offboarding complete for $($user.DisplayName). Audit log: $LogPath"
