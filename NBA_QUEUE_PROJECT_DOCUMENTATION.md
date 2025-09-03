# NBA Queue Project Documentation

## Project Overview

The NBA (Next Best Action) Queue is a Salesforce Lightning Web Component (LWC) system designed to help sales representatives prioritize and manage customer interactions. The system automatically generates queue items based on account data and machine learning models, then presents them to sales reps in a prioritized order with contextual information.

## What's New (Current Release)

- Object sharing for `NBA_Queue__c` is now Public Read/Write to reduce access issues.
- Permission set (`NBA_Queue_User`) cleaned up: removed duplicate FLS entries, removed FLS on required fields, and corrected references to `inov8__PMT_Project__c`.
- Added fields on `NBA_Queue__c`:
  - `Number_Dialed__c` (stores the normalized phone number actually dialed on Accept)
  - `Talkdesk_Activity__c` (lookup to `talkdesk__Talkdesk_Activity__c`)
- Talkdesk linking implemented with two triggers:
  - `TalkdeskActivityLinker` (after insert on `talkdesk__Talkdesk_Activity__c`) – links recent activities to NBA items by phone within 20 minutes and matching `Sales_Rep__c` to `talkdesk__User__c`.
  - `NBAQueueBacklink` (after update on `NBA_Queue__c`) – links when the NBA item completes first and the activity arrives later.
- Added allowlist for Talkdesk users via List Custom Setting `Allowed_Talkdesk_User__c` and `TalkdeskAllowedUserRefresher` (Schedulable) to refresh daily; both triggers filter by this allowlist when populated.
- LWC updates to `nbaQueueWidget`:
  - Added Up Next tab showing the next action preview.
  - Added countdown timer to next auto-refresh.
  - Sticky Accept/Dismiss section reduced ~15% and made scrollable.
  - Dismiss action uses a fixed 3-hour snooze (dynamic selector removed).
  - Stage selector defaults to the Opportunity’s current stage.
  - Selecting "Closed Won - Pending Implementation" or "Closed Lost" launches a screen flow and does not update the stage from the widget.
  - Flow launches use direct `/flow/...` URLs; flows include a `flowRedirect` screen component to return to the NBA app.
- `nbaQueueConsolePage` updated to include `Opportunity.First_PayDay__c` in Record Details (Payroll section).
- `flowRedirect` LWC added for reliable navigation back to the app from screen flows.
- Removed obsolete `projectInitiationHost` LWC and all references.

## System Architecture

### Core Components

#### 1. **NBA_Queue__c Custom Object**
- **Purpose**: Stores queue items that represent recommended actions for sales reps
- **Key Fields**:
  - `Account__c` - Related account
  - `Opportunity__c` - Related opportunity (if applicable)
  - `Sales_Rep__c` - Assigned sales representative
  - `Action_Type__c` - Type of action (Call, Email, Meeting, Follow_Up)
  - `Priority_Score__c` - ML-generated priority score (0-100)
  - `Status__c` - Current status (Pending, Accepted, Dismissed)
  - `Due_Date__c` - Calculated due date based on action type
  - `Model_Reason__c` - AI/ML reasoning for the recommendation
  - `Model_Version__c` - Version of the ML model used

#### 2. **NBAQueueManager.cls (Apex Controller)**
- **Purpose**: Core business logic for queue management
- **Key Methods**:
  - `processQueueItems()` - Creates new queue items from external data
  - `getNextQueueItem()` - Retrieves the highest priority item for a user
  - `getUpNextItem()` - Gets the next best item excluding the current one (for Up Next)
  - `acceptAction()` - Initiates calling workflow, sets `Number_Dialed__c`, marks item In Progress
  - `finalizeQueueItem()` - Completes the two-phase submit and marks as completed
  - `dismissAction()` - Marks item as snoozed/dismissed per reason
  - `updateCallDispositionWithQueueId()` - Saves disposition; conditionally updates Opportunity stage (skips when launching flows)
  - `getOpportunityStageNames()` - Returns picklist values (not labels) for correct LWC defaulting

#### 3. **nbaQueueWidget (Lightning Web Component)**
- **Purpose**: User interface for sales reps to view and act on queue items
- **Features**:
  - Real-time queue item display with countdown to next refresh
  - Accept/Snooze/Dismiss actions with compact sticky footer
  - Call disposition tracking with stage defaulting
  - Contact information display
  - Product usage visualization
  - Up Next tab (preview of the next action)
  - Manual refresh capability

#### 4. **NBAQueueEventPublisher.cls**
- **Purpose**: Publishes platform events for real-time updates
- **Events**:
  - `NBA_Queue_Update__e` - New queue items
  - Item status updates

#### 5. **Talkdesk Linking (Triggers + Custom Setting)**
- `TalkdeskActivityLinker.trigger` – Links `talkdesk__Talkdesk_Activity__c` inserts to recent NBA items by normalized phone, within a 20-minute window, matching `Sales_Rep__c` to `talkdesk__User__c`, and optionally filtered by allowlist.
- `NBAQueueBacklink.trigger` – Links NBA items on completion or when `Number_Dialed__c` is set post-completion, looking back 20 minutes for matching activities.
- `Allowed_Talkdesk_User__c` (List Custom Setting) – Stores allowed user Ids used to reduce query scope.
- `TalkdeskAllowedUserRefresher` – Schedulable Apex to refresh allowlist daily.

#### 6. **Flow Redirect**
- `flowRedirect` LWC – Light-weight Flow screen component that navigates users back to the NBA app (`/lightning/n/Next_Best_Action`) or a target URL when a Flow finishes.

## Data Flow

### 1. **Queue Item Creation**
```
External System → NBAQueueManager.processQueueItems() → NBA_Queue__c Records
```

**Input Data**:
- Account ID
- Action Type
- Priority Score (0-100)
- Model Reason
- Account Name
- Payroll Provider

**Processing**:
- Finds related Opportunity
- Assigns to Account Owner
- Calculates due date based on action type
- Sets status to "Pending"

### 2. **Queue Item Retrieval**
```
Sales Rep → nbaQueueWidget → NBAQueueManager.getNextQueueItem() → Filtered Results
```

**Filtering Logic**:
- Only "Pending" status items
- Assigned to current user
- Applies disqualification rules

### 3. **Action Processing**
```
Sales Rep Action → nbaQueueWidget → NBAQueueManager → Two-Phase Submit + Status Update
```

## Special Rules and Business Logic

### 1. **Queue Item Disqualification Rules**

Records are automatically filtered out if:

#### **Opportunity Stage Restrictions**
- `'Closed Won - Pending Implementation'`
- `'Closed Lost'`
- `'Ran Payroll'`

#### **Recent Activity Restrictions**
- Opportunity `Last_Call_Date_Time__c` is today
- Prevents duplicate calls on the same day

#### **Payroll Status Restrictions**
- Account `Payroll_Status__c` is:
  - `'pending'`
  - `'processing'`
  - `'paid'`
- Avoids interrupting active payroll processing

### 2. **Priority Score Adjustments**

Base priority scores are modified by real-time factors:

#### **Recent Web Usage Multiplier (1.25x)**
- Applied if `Last_Web_Usage_Timestamp__c` is within the last hour
- Indicates active customer engagement

#### **Best Time to Call Multiplier (1.2x)**
- Applied if `Best_Time_to_Call__c` is within current hour (±30 minutes)
- Optimizes call timing for better success rates

### 3. **Due Date Calculation**

Due dates are automatically calculated based on action type:
- **Call**: Today + 1 day
- **Email**: Today + 2 days
- **Meeting**: Today + 7 days
- **Follow_Up**: Today + 3 days
- **Default**: Today + 5 days

### 4. **Task Creation Rules**

When a queue item is accepted:
- Item status moves to "In Progress"; `Number_Dialed__c` is recorded when dialing starts.
- Disposition modal opens; on save, `finalizeQueueItem()` completes the item and writes back fields.
- Opportunity `StageName` may update except when "Closed Won - Pending Implementation" or "Closed Lost" are selected – in those cases a Flow launches and handles stage changes.

## User Interface Features

### 1. **Widget Display**
- **Header**: "Next Best Action" with refresh button and countdown timer
- **Main Content**: Action description with account/opportunity link
- **Badges**: Employee count, company age, product usage indicators
- **Tabs**: Contact Info, Product Usage, Up Next
- **Footer**: Accept and Dismiss/Snooze (sticky, compact, scrollable)

### 2. **Modal Dialogs**
- **Dismiss/Snooze Modal**: Fixed 3-hour snooze option and dismiss reasons
- **Call Disposition Modal**: Disposition type, phone number called, stage update (defaults), notes, next steps
- **Compact Design**: Minimal white space, Homebase branding

### 3. **Real-time Updates**
- Platform events for live updates
- Automatic refresh on status changes
- Manual refresh capability

## Integration Points

### 1. **External Data Sources**
- Machine learning models for priority scoring
- Account and opportunity data
- Product usage analytics
- Contact information

### 2. **Salesforce Objects**
- **Account**: Company information, payroll status
- **Opportunity**: Sales pipeline data
- **Contact**: Primary contact information
- **Task**: Action tracking
- **Platform Events**: Real-time communication
- `talkdesk__Talkdesk_Activity__c`: External call activity linking (managed package)

### 3. **Custom Fields**
- Implementation project lookup (`inov8__PMT_Project__c`)
- Product engagement flags (14 different features)
- Best contact information
- Model metadata
- `Number_Dialed__c` (NBA Queue)
- `Talkdesk_Activity__c` (NBA Queue → Talkdesk Activity lookup)

## Deployment and Configuration

### 1. **Deployment Order**
1. Custom objects and fields
2. Apex classes
3. Lightning Web Components
4. Static resources (fonts)
5. Permission sets and sharing rules

### 2. **Required Setup**
- NBA_Queue__c object with all custom fields
- Set `NBA_Queue__c` sharingModel to Public Read/Write
- Platform events for real-time updates
- Permission sets for user access
- Lightning App Builder configuration
- Install Talkdesk for Salesforce package (for Activity object) if not already present
- Create and schedule `TalkdeskAllowedUserRefresher` (optional but recommended)

### 3. **Branding**
- Homebase color scheme (#7e3dd4, #1e0b3a)
- Plus Jakarta Sans font family
- Modern UI with rounded corners and shadows
- Responsive design for mobile compatibility

## Error Handling and Logging

### 1. **Debug Logging**
- Comprehensive debug statements in Apex
- User context tracking
- Priority score calculation details
- Filtering rule application

### 2. **Exception Handling**
- AuraHandledException for user-facing errors
- Graceful fallbacks for missing data
- Validation for required fields

### 3. **Data Validation**
- Null checks for optional fields
- Status validation for state transitions
- User permission verification

## Performance Considerations

### 1. **Query Optimization**
- Selective field queries
- Proper indexing on key fields
- Batch processing for large datasets
- Triggers limit linking scope by:
  - 20-minute window on Created/Completed timestamps
  - Normalized phone number equality
  - Optional allowlist of Talkdesk users

### 2. **Real-time Updates**
- Platform events for scalability
- Efficient event publishing
- Minimal UI updates

### 3. **Caching**
- Client-side caching of queue items
- Efficient re-rendering
- Optimized component lifecycle

## Future Enhancements

### 1. **Potential Improvements**
- Advanced ML model integration
- Predictive analytics
- Automated follow-up scheduling
- Integration with external CRM systems

### 2. **Scalability Features**
- Batch processing for large queues
- Advanced filtering options
- Customizable priority algorithms
- Multi-language support

---

*This documentation covers the current state of the NBA Queue project as deployed. For technical implementation details, refer to the individual component files and their associated metadata.* 