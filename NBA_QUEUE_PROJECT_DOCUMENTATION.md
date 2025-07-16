# NBA Queue Project Documentation

## Project Overview

The NBA (Next Best Action) Queue is a Salesforce Lightning Web Component (LWC) system designed to help sales representatives prioritize and manage customer interactions. The system automatically generates queue items based on account data and machine learning models, then presents them to sales reps in a prioritized order with contextual information.

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
  - `acceptAction()` - Converts queue item to a Task and marks as accepted
  - `dismissAction()` - Marks item as dismissed with reason
  - `updateCallDisposition()` - Updates call outcomes

#### 3. **nbaQueueWidget (Lightning Web Component)**
- **Purpose**: User interface for sales reps to view and act on queue items
- **Features**:
  - Real-time queue item display
  - Accept/Skip actions
  - Call disposition tracking
  - Contact information display
  - Product usage visualization
  - Manual refresh capability

#### 4. **NBAQueueEventPublisher.cls**
- **Purpose**: Publishes platform events for real-time updates
- **Events**:
  - `NBA_Queue_Update__e` - New queue items
  - Item status updates

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
Sales Rep Action → nbaQueueWidget → NBAQueueManager → Task Creation + Status Update
```

## Special Rules and Business Logic

### 1. **Queue Item Disqualification Rules**

Records are automatically filtered out if:

#### **Opportunity Stage Restrictions**
- `'closed won - pending implementation'`
- `'closed lost'`
- `'ran payroll'`

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
- Creates a standard Salesforce Task
- Sets status to "Completed" immediately
- Links to Opportunity (if available) or Account
- Includes priority mapping (High: ≥80, Normal: ≥60, Low: <60)
- Assigns to the sales rep who accepted it

## User Interface Features

### 1. **Widget Display**
- **Header**: "Next Best Action" with refresh button
- **Main Content**: Action description with account/opportunity link
- **Badges**: Employee count, company age, product usage indicators
- **Tabs**: Opportunity details, Contact info, Product usage
- **Footer**: Skip and Accept buttons (sticky)

### 2. **Modal Dialogs**
- **Dismiss Modal**: Reason for dismissal (required)
- **Call Disposition Modal**: Disposition type and call notes
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

### 3. **Custom Fields**
- Implementation project lookup (`inov8__PMT_Project__c`)
- Product engagement flags (14 different features)
- Best contact information
- Model metadata

## Deployment and Configuration

### 1. **Deployment Order**
1. Custom objects and fields
2. Apex classes
3. Lightning Web Components
4. Static resources (fonts)
5. Permission sets and sharing rules

### 2. **Required Setup**
- NBA_Queue__c object with all custom fields
- Platform events for real-time updates
- Permission sets for user access
- Lightning App Builder configuration

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