# NBA Queue - Not Surfaced Criteria

## Overview
The NBA Queue system uses sophisticated filtering logic to determine when items should **NOT** be shown to sales reps. This ensures reps only see actionable, appropriate items while respecting customer timing and business rules.

## Hard Blocks (Always Exclude)
These criteria **always** prevent an item from being surfaced, regardless of status:

### Opportunity Stage Restrictions
- `'Closed Won - Pending Implementation'`
- `'Closed Lost'`
- `'Ran Payroll'`

### Account Payroll Status Restrictions
- `'pending'`
- `'processing'`
- `'paid'`

## Soft Blocks (Bypassed for In Progress Items)
These criteria prevent surfacing **unless** the item is already "In Progress":

### Recent Call Activity
- **Already called today**: If `Opportunity.Last_Call_Date_Time__c` is today
- **Reason**: Prevents duplicate calls on the same day

### Future Follow-up Scheduling
- **Future follow-up date set**: If `Opportunity.Future_Follow_Up_Date__c` is in the future
- **Reason**: Respects scheduled follow-up timing

### Future Meeting Conflicts
- **Scheduled events**: If there's a future Event scheduled more than 15 minutes from now
- **Reason**: Avoids interrupting scheduled meetings

## Special Status Handling

### In Progress Items
- Items with `Status__c = 'In Progress'` **bypass all soft blocks**
- This allows reps to complete work they've already started
- Only hard blocks (stage/payroll status) still apply

### Snoozed Items
- Items with `Status__c = 'Snoozed'` are only shown if `Snoozed_Until__c <= now()`
- This respects the snooze timing

## Business Logic Summary

| **Criteria** | **Business Reason** | **Impact** |
|--------------|-------------------|------------|
| **Closed Stages** | Customer already converted or lost | Prevents wasted effort |
| **Payroll Status** | Customer actively using service | Avoids interrupting service |
| **Called Today** | Already contacted today | Prevents harassment |
| **Future Follow-up** | Respects scheduled timing | Maintains professional cadence |
| **Future Meetings** | Avoids double-booking | Prevents conflicts |

## Common Debug Messages
The system logs the specific reason for each skipped item:
- `"Opportunity stage is Closed Lost"`
- `"Already called today"`
- `"Future follow-up date is set to 2024-01-15"`
- `"Future meeting scheduled (>15 minutes)"`
- `"Account is in payroll status: processing"`

---
*This filtering ensures sales reps only see actionable, appropriate items while maintaining professional customer engagement standards.*
