# Power Automate — Employee Onboarding Flow

## Overview

This flow automates the employee onboarding process end-to-end, triggering when a new hire record is added to a SharePoint list by HR and handling:

1. Welcome email sent to new hire
2. Manager notification with onboarding checklist
3. SharePoint site access granted
4. Teams channel notification to the team
5. IT ticket created for hardware provisioning

---

## Flow Architecture

```
TRIGGER
  └── SharePoint: When item created in "New Hires" list

STEP 1 — Get manager details
  └── Microsoft 365: Get user profile (Manager UPN from list item)

STEP 2 — Send welcome email to new hire
  └── Outlook: Send email
      To: [NewHire_Email]
      Subject: Welcome to the team, [FirstName]!
      Body: Personalized welcome with first-day checklist

STEP 3 — Notify manager
  └── Outlook: Send email
      To: [Manager_Email]
      Subject: Your new team member [FullName] starts [StartDate]
      Body: Manager checklist (system access, desk setup, intro meetings)

STEP 4 — Grant SharePoint access
  └── SharePoint: Grant access to site
      Site: [Department_Site_URL from list item]
      User: [NewHire_Email]
      Role: Contribute

STEP 5 — Post Teams welcome message
  └── Microsoft Teams: Post message in channel
      Team: [Department_Team from list item]
      Channel: General
      Message: "Please welcome [FullName] who is joining us as [JobTitle] on [StartDate]!"

STEP 6 — Create IT provisioning ticket
  └── SharePoint: Create item in "IT Tickets" list
      Title: Hardware Setup — [FullName]
      AssignedTo: IT Admin group
      Priority: High
      DueDate: [StartDate]
      Notes: New hire [FullName] ([Role]) starting [StartDate]. Provision laptop, badge, M365 account.
```

---

## SharePoint Trigger List Schema

The flow triggers on the **New Hires** list. Required columns:

| Column | Type | Description |
|--------|------|-------------|
| Title | Single line | Full name |
| FirstName | Single line | First name |
| Email | Single line | Work email (UPN) |
| StartDate | Date | First day |
| JobTitle | Single line | Job title |
| Department | Single line | Department name |
| Manager | Person | Manager account |
| DepartmentSiteUrl | Hyperlink | SharePoint site URL |
| DepartmentTeam | Single line | Teams team display name |

---

## Setup Instructions

1. Import `employee-onboarding-flow.json` into Power Automate
2. Update the SharePoint site URL to point to your tenant's **New Hires** list
3. Update the IT Tickets list URL in Step 6
4. Update the Teams connection to your tenant
5. Test with a sample list item before going live

---

## Why This Complements the PowerShell Scripts

The PowerShell `New-UserOnboarding.ps1` script handles the technical account provisioning (creating the M365 account, assigning licenses). This Power Automate flow handles the human-facing side — communications, notifications, and task creation — that runs after the account exists.

Together they cover the full onboarding workflow without manual steps.
