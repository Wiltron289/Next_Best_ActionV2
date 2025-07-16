# NBA Queue Project

A Salesforce Lightning Web Component (LWC) widget that displays "Next Best Action" records for sales representatives. The widget shows NBA records filtered by the current user and provides functionality to accept or dismiss actions.

## Features

- **Next Best Action Display**: Shows the highest priority NBA record for the current sales rep
- **Opportunity Integration**: Displays related Opportunity information including stage, source, and field values
- **Activity Timeline**: Shows recent activities (Tasks and Events) for the related Opportunity
- **Accept Action**: Creates a Task and shows call disposition modal for call actions
- **Dismiss Action**: Allows users to dismiss actions with a reason
- **Real-time Updates**: Auto-refreshes every 30 seconds
- **Responsive Design**: Modern UI with tabs for details and activity

## Components

### NBA Queue Widget (`nbaQueueWidget`)
- **Location**: `force-app/main/default/lwc/nbaQueueWidget/`
- **Purpose**: Main widget component that displays NBA records
- **Features**:
  - Displays Account and Opportunity information
  - Shows badges for employees, company age, and use cases
  - Opportunity details tab with field values from related Opportunity
  - Activity tab showing recent Tasks and Events
  - Accept/Skip buttons with proper workflows

### NBA Queue Manager (`NBAQueueManager`)
- **Location**: `force-app/main/default/classes/NBAQueueManager.cls`
- **Purpose**: Apex controller for NBA queue operations
- **Key Methods**:
  - `getNextQueueItem()`: Gets the next NBA record for a user
  - `acceptAction()`: Accepts an NBA action and creates a Task
  - `dismissAction()`: Dismisses an NBA action with reason
  - `getOpportunityActivities()`: Gets recent activities for an Opportunity
  - `updateCallDisposition()`: Updates call disposition and notes

### NBA Queue Event Publisher (`NBAQueueEventPublisher`)
- **Location**: `force-app/main/default/classes/NBAQueueEventPublisher.cls`
- **Purpose**: Publishes platform events for real-time updates

## Custom Object: NBA_Queue__c

### Key Fields
- `Account__c`: Lookup to Account
- `Opportunity__c`: Lookup to Opportunity
- `Sales_Rep__c`: Lookup to User (Sales Rep)
- `Action_Type__c`: Picklist (Call, Email, Meeting, etc.)
- `Priority_Score__c`: Number (0-100)
- `Status__c`: Picklist (Pending, Accepted, Dismissed)
- `Dismissed_Reason__c`: Long Text Area (reason for dismissal)
- `Model_Reason__c`: Text Area (AI-generated reason)
- `Due_Date__c`: Date
- `Subject__c`: Text

## Setup Instructions

1. **Deploy the project**:
   ```bash
   ./deploy.sh your-org-alias
   ```

2. **Add the widget to Lightning pages**:
   - Edit a Lightning page
   - Add the "NBA Queue Widget" component
   - Configure the panel height if needed

3. **Set up NBA records**:
   - Use the sample CSV file: `nba_queue_varied_sample.csv`
   - Import via Data Loader or similar tool

## Sample Data

The project includes a sample CSV file (`nba_queue_varied_sample.csv`) with example NBA records for testing.

## External Integration

The `samples/` directory contains example code for integrating external ML models with the NBA Queue system:

- `external_integration.py`: Python script demonstrating how to push recommendations from external priority models to Salesforce
- `requirements.txt`: Python dependencies for the integration script

## Dependencies

- Salesforce Lightning Web Components
- Platform Events (for real-time updates)
- Standard Task and Event objects (for activity tracking)

## Browser Support

- Modern browsers supporting ES6+
- Salesforce Lightning Experience
- Mobile responsive design
