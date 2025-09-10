# NBA Queue Project

Salesforce Lightning components for surfacing "Next Best Action" (NBA) items to sales reps. The solution now supports both Opportunity- and Lead-based actions, with a console layout that embeds the interactive widget.

## Features (Current)

- **Lead + Opportunity Support**: Actions may relate to a Lead, Opportunity, or Account.
- **Console Page + Widget**: The console page LWC hosts record details; the widget drives Accept/Dismiss and inline flows.
- **Reliable Click-to-Dial**: Accept launches Talkdesk (DOM click + tel: fallback); disposition form opens ~700ms later to avoid race conditions.
- **Disposition + Writebacks**:
  - Opportunities: updates Stage (except when closing flows are launched), Next Steps/Date, and notes.
  - Leads: updates Lead Status, Next Steps/Date, and appends call notes to Lead Description.
- **Up Next + Not Surfaced**: Preview the next item; see why items are filtered out.
- **Auto-Refresh**: Refreshes every 5 minutes (countdown visible in the widget); refresh pauses while forms are open.
- **Mogli Context Refresh**: Mogli Aura wrapper refreshes when the current Lead/Opportunity context changes.
- **Activity Tab**: Shows upcoming and past Tasks/Events (last 90 days) for the primary record, with locale-formatted dates and overdue highlighting.
- **Product Info Tab**: Displays Account-level buttons (Admin Link, Reactive Admin Link, Check Console) using values from corresponding fields.
- **Time Zone Display**: Shows Time Zone information for both Opportunity and Account calls in the Contact Info tab.
- **Enhanced Queue Sorting**: Three-level sorting system: Status → Priority Score → Creation Date (most recent first for tied scores).

## Components

### NBA Queue Console Page (`nbaQueueConsolePage`)
- **Location**: `force-app/main/default/lwc/nbaQueueConsolePage/`
- **Purpose**: Two-column console layout. Left side embeds the widget; right side shows record details (Lead/Opportunity/Account) and an email panel.

### NBA Queue Widget (`nbaQueueWidget`)
- **Location**: `force-app/main/default/lwc/nbaQueueWidget/`
- **Purpose**: Main widget component that displays NBA records
- **Features**:
  - Displays Lead/Opportunity/Account action context and contact info
  - Tabs: Contact Info, Product Info (Account links), Activity, Up Next, Not Surfaced
  - Accept/Skip with call disposition and optional flow launch
  - Inline flow host overlay for closed stages (Project Initiation / Closed Lost)
  - Future Follow-Up stage handling: selecting the “Future Follow-Up” stage shows Future Follow Up Date/Reason inputs, hides Next Step fields, and saves to Opportunity.

### NBA Queue Manager (`NBAQueueManager`)
- **Location**: `force-app/main/default/classes/NBAQueueManager.cls`
- **Purpose**: Apex controller for NBA queue operations
- **Key Methods**:
  - `getNextQueueItemWithDetails()`, `getUpNextItem()`: Retrieves current and next items with filters and scoring
  - `acceptAction()`: Creates Task (WhoId Lead/Contact, WhatId Opp/Account as valid)
  - `dismissAction()`: Snooze/dismiss with reason/category
  - `updateCallDispositionWithQueueId()` and `...Options()`: Saves disposition; can defer finalize for flows
  - `saveNextSteps` / `saveNextStepsWithLead`: Writes Stage or Lead Status and Next Steps/Date
  - `getOpportunityStageNames()`, `getLeadStatusNames()`: Active picklist values for LWCs

### Embedded Flow Host (`embeddedFlowHost`)
- **Location**: `force-app/main/default/lwc/embeddedFlowHost/`
- **Purpose**: Lightweight wrapper around `lightning-flow` to run closing-stage flows inline from the widget.

### Talkdesk Linking
- **Triggers**: `TalkdeskActivityLinker.trigger`, `NBAQueueBacklink.trigger`
- **Schedulable**: `TalkdeskAllowedUserRefresher` to maintain an allowlist

## Custom Object: NBA_Queue__c

### Key Fields
- `Account__c`, `Opportunity__c`, `Lead__c`
- `Sales_Rep__c`
- `Action_Type__c`
- `Priority_Score__c`, `Due_Date__c`, `Subject__c`
- `Status__c` (Pending, Accepted/In Progress, Completed, Dismissed)
- `Snoozed_Until__c`, `Dismissed_Reason__c`
- `Number_Dialed__c`, `Talkdesk_Activity__c`
- `Not_Surfaced_Reasons__c`

## Setup Instructions

1. **Deploy**
   ```bash
   sf project deploy start --source-dir force-app/main/default --target-org <alias>
   ```

2. **Assign Permission Set**
   - `NBA_Queue_User` to all users of the app (includes Lead FLS and required fields)

3. **Add to Lightning App**
   - Add the `nbaQueueConsolePage` to your Lightning app/page (or place the `nbaQueueWidget` directly if preferred)
   - Ensure Talkdesk components are available for click-to-dial

4. (Optional) **Talkdesk allowlist job**
   - Schedule `TalkdeskAllowedUserRefresher` if you use the allowlist

## Refresh & Flows

- Auto-refresh every 5 minutes; countdown is visible; refresh is paused while forms are open.
- Selecting a closing Opportunity stage (Closed Won - Pending Implementation / Closed Lost) launches a flow inline via the widget; the item finalizes on flow completion.
- Selecting the “Future Follow-Up” stage dynamically shows Future Follow Up fields and hides Next Step fields. The comparison is robust to hyphenation (e.g., “Future Follow-Up”).

## Recent Updates

### Version 2.1 (Latest)
- **Time Zone Display**: Added Time Zone field display in Contact Info tab for both Opportunity and Account calls
- **Enhanced Queue Sorting**: Implemented three-level sorting system to handle tied priority scores:
  1. Status (In Progress → Pending)
  2. Priority Score (highest first)
  3. Creation Date (most recent first) - *NEW*
- **Talkdesk Activity Linking Fix**: Fixed NBAQueueBacklink trigger to properly handle activities created before queue completion
- **Field Tracking**: Resolved deployment issues with field tracking history being overwritten

### Version 2.0
- Initial implementation with Lead + Opportunity support
- Console page layout with embedded widget
- Talkdesk integration and activity linking
- Auto-refresh and Mogli context integration

## Notes

- Platform event publisher has been removed; the system relies on periodic refresh and UI events.
- Time Zone fields (`Time_Zone__c`) must exist on both Opportunity and Account objects for proper display.

## Console Field Layout (Opportunity)

- Opportunity Details
  - Name / Stage
  - Close Date / Primary Contact
  - Rep Notes / Current Payroll
- Payroll Details
  - Payroll Buyer Stage / Payroll Risk Level
  - Fed Auth Finish / Bank Connect Finish
  - Pay Sched Finish / Last Progression Time
- Next Steps and Future Follow Up Details
  - Next Step Date / Next Step
  - Future Follow Up Date / Future Follow Up Reason

## Dependencies

- Salesforce Lightning Web Components
- Standard Task and Event objects (for activity tracking)

## Browser Support

- Modern browsers supporting ES6+
- Salesforce Lightning Experience
- Mobile responsive design
