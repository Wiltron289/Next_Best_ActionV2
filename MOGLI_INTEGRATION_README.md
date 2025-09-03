# Mogli Conversation Integration with NBA Queue

## Overview
This integration allows the Mogli Conversation View Component to dynamically render in the NBA Queue Console and receive the current Opportunity ID from the NBA app.

## How It Works

### 1. Message Communication
- The NBA Queue Console Page publishes Opportunity context via Lightning Message Service when a queue item loads
- The Mogli Conversation Wrapper subscribes to these messages and updates its display accordingly

### 2. Components

#### Mogli Conversation Wrapper (LWC)
- **Location**: `force-app/main/default/lwc/mogliConversationWrapper/`
- **Purpose**: Wraps the Mogli conversation view and handles Opportunity context
- **Features**:
  - Listens for Opportunity context messages from NBA app
  - Dynamically shows/hides Mogli component based on Opportunity availability
  - Can be used standalone or embedded in other components

#### Mogli Conversation Aura Wrapper
- **Location**: `force-app/main/default/aura/mogliConversationAuraWrapper/`
- **Purpose**: Aura version for use in Classic pages or when LWC is not available
- **Features**:
  - Uses `force:recordData` to get Opportunity ID from NBA Queue record
  - Renders Mogli conversation view when Opportunity is available

### 3. Message Channel
- **Name**: `NBA_OpportunityContext`
- **Purpose**: Publishes the active Opportunity ID from the NBA app
- **Usage**: Automatically used by the NBA Queue Console Page

## Implementation Details

### NBA Console Page Integration
The Mogli component is added to the right panel of the NBA Console Page:

```html
<!-- Mogli Conversation Section -->
<div class="panel-section">
    <div class="panel-banner">
        <div class="panel-banner-title">Conversation History</div>
    </div>
    <div class="mogli-container">
        <c-mogli-conversation-wrapper show-when-no-opportunity="true"></c-mogli-conversation-wrapper>
    </div>
</div>
```

### Dynamic Rendering
The component automatically:
1. Subscribes to Opportunity context messages on initialization
2. Updates the displayed Opportunity ID when messages are received
3. Shows/hides the Mogli conversation view based on Opportunity availability
4. Unsubscribes from messages when the component is destroyed

## Usage

### In NBA Console Page
The component is automatically included and will show conversations for the current queue item's Opportunity.

### As Standalone Component
```html
<c-mogli-conversation-wrapper 
    record-id="a1B1234567890ABC"
    show-when-no-opportunity="true">
</c-mogli-conversation-wrapper>
```

### In Aura Components
```xml
<c:mogliConversationAuraWrapper recordId="{!v.recordId}" />
```

## Configuration

### Properties
- `recordId` (optional): NBA Queue record ID for standalone usage
- `showWhenNoOpportunity` (optional): Whether to show a message when no Opportunity is available

### Styling
The component includes CSS styling for proper display in the console panel:
- Container with background and border
- Minimum height for consistent layout
- Responsive design considerations

## Troubleshooting

### Common Issues
1. **Mogli component not showing**: Check that the Opportunity context message is being published
2. **No conversations displayed**: Verify the Opportunity ID is being passed correctly to Mogli
3. **Styling issues**: Ensure the CSS classes are properly applied

### Debug Steps
1. Check browser console for any JavaScript errors
2. Verify the message channel is working by checking network requests
3. Confirm the Opportunity ID is being received by the wrapper component

## Future Enhancements
- Add conversation filtering options
- Implement conversation search functionality
- Add conversation analytics and reporting
- Support for multiple conversation types
