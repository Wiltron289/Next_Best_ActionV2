# NBA Queue "Not Surfaced" Criteria

## Overview
This document explains the criteria that determine when NBA Queue items are **not surfaced** (filtered out) from the queue display. These criteria help ensure sales reps only see relevant, actionable items.

## Hard Blocks (Apply to ALL Action Types)
These criteria **always exclude** items, regardless of action type or status:

### 1. Opportunity Stage Blocks
- **Closed Won - Pending Implementation**
- **Closed Lost** 
- **Ran Payroll**

*Rationale: These opportunities are no longer active sales opportunities.*

## Soft Blocks (Apply ONLY to Call-Based Actions)
These criteria only apply to actions containing "Call" or "Payroll" in the Action_Type__c field:

### 1. Already Called Today
- **Field**: `Opportunity.Last_Call_Date_Time__c`
- **Logic**: If last call was today, skip call actions
- **Exception**: In Progress items can still be completed

### 2. Future Follow-Up Date Set
- **Field**: `Opportunity.Future_Follow_Up_Date__c` 
- **Logic**: If future follow-up date > today, skip call actions
- **Exception**: In Progress items can still be completed

### 3. Future Meeting Scheduled
- **Logic**: If opportunity has an Event starting > 15 minutes from now, skip call actions
- **Exception**: In Progress items can still be completed

### 4. Account Payroll Status
- **Field**: `Account.Payroll_Status__c`
- **Values**: "Pending", "Processing", "Paid"
- **Logic**: Skip call actions for accounts in these payroll statuses
- **Exception**: In Progress items can still be completed

## Action Type Specific Behavior

### Call Actions (Including Payroll)
- **Subject to**: All hard blocks + all soft blocks
- **Examples**: "Call", "Payroll Opportunity Call", "Payroll Prospecting Call"

### Email Actions
- **Subject to**: Only hard blocks
- **Not subject to**: Soft blocks (can be surfaced even if called today, etc.)

### Event Actions  
- **Subject to**: Only hard blocks
- **Not subject to**: Soft blocks (urgent events should always be shown)

## In Progress Override
Items with `Status__c = 'In Progress'` bypass **all soft blocks** to allow reps to complete their work, regardless of action type.

## Debugging
Check debug logs for skip reasons:
- `Skipping item due to Opportunity stage (hard block)`
- `Skipping call item due to last call being today`
- `Skipping call item due to future follow-up date`
- `Skipping call item due to future scheduled Event`
- `Skipping call item due to payroll status`