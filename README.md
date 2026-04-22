# M365 Governance Toolkit

A PowerShell-based toolkit for administering and governing Microsoft 365 environments — SharePoint Online, Microsoft Teams, OneDrive for Business, and Exchange. Built from real operational experience managing multi-site M365 deployments.

---

## What This Does

Most M365 admin work falls into four categories: **provisioning**, **governance**, **auditing**, and **lifecycle management**. This toolkit covers all four with scripts you can run directly against any M365 tenant (with the right permissions).

| Script | Category | What It Does |
|--------|----------|--------------|
| `New-UserOnboarding.ps1` | Provisioning | Creates user, assigns licenses, adds to SharePoint/Teams groups |
| `Remove-UserOffboarding.ps1` | Lifecycle | Revokes access, transfers OneDrive, archives mailbox, removes licenses |
| `Get-SiteGovernanceReport.ps1` | Auditing | Audits all SharePoint sites for ownership gaps, external sharing, storage |
| `Get-AccessReview.ps1` | Auditing | Exports all site/group permissions to CSV for compliance review |
| `New-SharePointSiteProvisioning.ps1` | Provisioning | Spins up governed SharePoint sites from a standard template |
| `Set-TeamsLifecyclePolicy.ps1` | Governance | Flags inactive Teams, enforces naming policy, identifies ownerless teams |

---

## Prerequisites

Install the required PowerShell modules:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
Install-Module PnP.PowerShell -Scope CurrentUser
Install-Module MicrosoftTeams -Scope CurrentUser
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

### Permissions Required

| Task | Required Role |
|------|--------------|
| User provisioning / offboarding | User Administrator, License Administrator |
| SharePoint governance | SharePoint Administrator |
| Teams lifecycle | Teams Administrator |
| Exchange archiving | Exchange Administrator |

---

## Scripts

### 1. New-UserOnboarding.ps1

Provisions a new M365 user end-to-end: account creation, license assignment, SharePoint group membership, and Teams channel access.

```powershell
.\New-UserOnboarding.ps1 `
  -FirstName "Jane" `
  -LastName "Smith" `
  -Department "Operations" `
  -Manager "john.doe@contoso.com" `
  -LicenseSku "ENTERPRISEPREMIUM" `
  -SharePointSiteUrl "https://contoso.sharepoint.com/sites/Operations" `
  -TeamsTeamName "Operations Team"
```

---

### 2. Remove-UserOffboarding.ps1

Clean, auditable offboarding: revokes sessions, transfers OneDrive, converts mailbox to shared, removes from all groups, removes licenses, disables account.

```powershell
.\Remove-UserOffboarding.ps1 `
  -UserPrincipalName "jane.smith@contoso.com" `
  -OneDriveTransferTo "john.doe@contoso.com" `
  -ArchiveMailbox $true
```

---

### 3. Get-SiteGovernanceReport.ps1

Scans every SharePoint site and flags governance issues: missing secondary owner, external sharing enabled, storage over threshold, no activity in 90+ days.

```powershell
.\Get-SiteGovernanceReport.ps1 `
  -TenantName "contoso" `
  -OutputPath ".\reports\site-governance-$(Get-Date -Format 'yyyy-MM-dd').csv"
```

**Output columns:** SiteUrl, Title, PrimaryOwner, SecondaryOwner, ExternalSharing, StorageUsedGB, LastActivityDate, Flags

---

### 4. Get-AccessReview.ps1

Exports all SharePoint site permissions — including group memberships and guest/external users — to CSV. Designed for periodic compliance access reviews.

```powershell
.\Get-AccessReview.ps1 `
  -TenantName "contoso" `
  -IncludeExternalUsers $true `
  -OutputPath ".\reports\access-review-$(Get-Date -Format 'yyyy-MM-dd').csv"
```

---

### 5. New-SharePointSiteProvisioning.ps1

Creates a new SharePoint site from a governance-compliant template: sets sharing policy, requires two owners, applies default document library structure, and registers the site in the site directory list.

```powershell
.\New-SharePointSiteProvisioning.ps1 `
  -SiteTitle "HR Operations" `
  -SiteAlias "hr-operations" `
  -PrimaryOwner "jane.smith@contoso.com" `
  -SecondaryOwner "john.doe@contoso.com" `
  -Template "TeamSite" `
  -ExternalSharingPolicy "Disabled"
```

---

### 6. Set-TeamsLifecyclePolicy.ps1

Audits all Teams in the tenant: flags teams with no messages in 90+ days, no owner, or names that violate naming policy. Outputs a report and optionally sends renewal notification emails to team owners.

```powershell
.\Set-TeamsLifecyclePolicy.ps1 `
  -InactiveDaysThreshold 90 `
  -NamingPattern "^[A-Z]{2,4}-[A-Za-z\s]+" `
  -SendRenewalEmails $true `
  -OutputPath ".\reports\teams-lifecycle-$(Get-Date -Format 'yyyy-MM-dd').csv"
```

---

## Power Automate

See [`power-automate/`](./power-automate/) for a documented employee onboarding flow that integrates with SharePoint, Teams, and Exchange — built as a complement to the PowerShell scripts for event-driven automation.

---

## Folder Structure

```
m365-governance-toolkit/
├── README.md
├── scripts/
│   ├── New-UserOnboarding.ps1
│   ├── Remove-UserOffboarding.ps1
│   ├── Get-SiteGovernanceReport.ps1
│   ├── Get-AccessReview.ps1
│   ├── New-SharePointSiteProvisioning.ps1
│   └── Set-TeamsLifecyclePolicy.ps1
├── power-automate/
│   ├── README.md
│   └── employee-onboarding-flow.json
└── templates/
    └── site-governance-template.json
```

---

## Background

Built from 4+ years of hands-on M365 administration across a multi-site franchise operation. The governance gaps these scripts address — ownerless sites, stale external sharing, incomplete offboarding — are the ones that cause the most real-world compliance and security problems in mid-size M365 tenants.
