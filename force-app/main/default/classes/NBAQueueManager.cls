public class NBAQueueManager {
    
    // Wrapper classes for invocable methods
    public class QueueRequest {
        @InvocableVariable(required=true)
        public String accountId;
        
        @InvocableVariable(required=true)
        public String actionType;
        
        @InvocableVariable(required=true)
        public Decimal priorityScore;
        
        @InvocableVariable(required=false)
        public String modelReason;
        
        @InvocableVariable(required=false)
        public String modelVersion;
        
        @InvocableVariable(required=false)
        public String accountName;
        
        @InvocableVariable(required=false)
        public String mostRecentPayrollProvider;
    }
    
    @InvocableMethod(label='Process NBA Queue Items')
    public static void processQueueItems(List<QueueRequest> requests) {
        List<NBA_Queue__c> queueItems = new List<NBA_Queue__c>();
        Map<Id, Id> oppOwnerMap = new Map<Id, Id>();
        Set<Id> oppIds = new Set<Id>();
        for (QueueRequest req : requests) {
            if (req.accountId != null) {
                // Try to find related Opportunity for this Account
                List<Opportunity> opps = [SELECT Id, OwnerId FROM Opportunity WHERE AccountId = :req.accountId LIMIT 1];
                if (!opps.isEmpty()) {
                    oppOwnerMap.put(opps[0].Id, opps[0].OwnerId);
                    oppIds.add(opps[0].Id);
                }
            }
        }
        for(QueueRequest req : requests) {
            Id salesRepId = null;
            Id oppId = null;
            if (req.accountId != null) {
                List<Opportunity> opps = [SELECT Id, OwnerId FROM Opportunity WHERE AccountId = :req.accountId LIMIT 1];
                if (!opps.isEmpty()) {
                    oppId = opps[0].Id;
                    salesRepId = opps[0].OwnerId;
                }
            }
            NBA_Queue__c item = new NBA_Queue__c(
                Account__c = req.accountId,
                Action_Type__c = req.actionType,
                Priority_Score__c = req.priorityScore,
                Subject__c = generateSubject(req.actionType, req.accountName),
                Description__c = req.modelReason,
                Due_Date__c = calculateDueDate(req.actionType),
                Status__c = 'Pending',
                Model_Reason__c = req.modelReason,
                Model_Version__c = req.modelVersion,
                Opportunity__c = oppId,
                Sales_Rep__c = salesRepId,
                Most_Recent_Payroll_Provider__c = req.mostRecentPayrollProvider
            );
            queueItems.add(item);
        }
        
        // Assign to users
        assignQueueItems(queueItems);
        insert queueItems;
        
        // Publish platform events for real-time updates
        NBAQueueEventPublisher.publishQueueUpdate(queueItems, 'New');
    }
    
    private static void assignQueueItems(List<NBA_Queue__c> items) {
        // Get account owners for assignment
        Set<Id> accountIds = new Set<Id>();
        for(NBA_Queue__c item : items) {
            accountIds.add(item.Account__c);
        }
        
        Map<Id, Id> accountOwnerMap = new Map<Id, Id>();
        for(Account acc : [SELECT Id, OwnerId FROM Account WHERE Id IN :accountIds]) {
            accountOwnerMap.put(acc.Id, acc.OwnerId);
        }
        
        // No longer needed - using Sales_Rep__c directly
        // Assignment logic is handled in processQueueItems method
    }
    
    private static String generateSubject(String actionType, String accountName) {
        if(String.isBlank(accountName)) {
            return 'NBA: ' + actionType;
        }
        return 'NBA: ' + actionType + ' - ' + accountName;
    }
    
    private static Date calculateDueDate(String actionType) {
        Date today = Date.today();
        
        switch on actionType {
            when 'Call' {
                return today.addDays(1);
            }
            when 'Email' {
                return today.addDays(2);
            }
            when 'Meeting' {
                return today.addDays(7);
            }
            when 'Follow_Up' {
                return today.addDays(3);
            }
            when else {
                return today.addDays(5);
            }
        }
    }
    
    @AuraEnabled
    public static NBA_Queue__c getNextQueueItem(Id userId) {
        // Debug logging
        System.debug('=== NBA Queue Debug ===');
        System.debug('User ID requesting queue items: ' + userId);
        System.debug('Current user context: ' + UserInfo.getUserId());
        System.debug('Current user name: ' + UserInfo.getName());
        
        try {
            // First, let's check if there are any NBA_Queue__c records at all for this user
            List<NBA_Queue__c> allUserItems = [
                SELECT Id, Account__c, Sales_Rep__c, Status__c, Action_Type__c, Subject__c
                FROM NBA_Queue__c 
                WHERE Sales_Rep__c = :userId
            ];
            System.debug('Total NBA_Queue__c records for user: ' + allUserItems.size());
            
            // Log each record for debugging
            for(NBA_Queue__c item : allUserItems) {
                System.debug('Record ID: ' + item.Id + 
                           ', Sales_Rep__c: ' + item.Sales_Rep__c + 
                           ', Status__c: ' + item.Status__c);
            }
            
            // Now get the pending items with additional fields for priority calculation
            List<NBA_Queue__c> items = [
                SELECT Id, Account__c, Account__r.Name, Account__r.Employee_Count__c, Account__r.Company_Age_in_Days__c,
                       Account__r.Use_Case_Payroll__c, Account__r.Use_Case_Scheduling__c, Account__r.Use_Case_Time_Tracking__c,
                       Account__r.Phone, Account__r.Last_Web_Usage_Timestamp__c, Account__r.Payroll_Status__c,
                       Action_Type__c, Priority_Score__c, Subject__c, Description__c, Due_Date__c, Model_Reason__c, Status__c,
                       Company_Age_Days__c, Active_Employees__c, Feature_Usage__c, Contact_Name__c, Contact_Phone__c, Action_Context__c,
                       Opportunity__c, Opportunity__r.Name, Opportunity__r.Source__c, Opportunity__r.StageName, 
                       Opportunity__r.Payroll_Buyer_Stage__c, Opportunity__r.Implementation_Status__c, Opportunity__r.Account_Product_Switcher_Data__c,
                       Opportunity__r.Account_Current_Payroll__c, Opportunity__r.Last_Call_Date_Time__c,
                       Opportunity_Stage__c, Opportunity_Source__c, Payroll_Buyer_Stage__c, Rep_Notes__c, Close_Date__c, Inception_Switcher__c,
                       Current_Payroll_Provider__c, Last_Call_Date__c, Best_Time_to_Call__c, Best_Number_to_Call__c, Best_Person_to_Call__c, Best_Person_to_Call__r.Name, Best_Person_to_Call__r.Phone, Best_Person_to_Call__r.Email,
                       Sales_Rep__c, First_Viewed_Date__c, Actioned_Date__c,
                       Break_Preferences_Engaged__c, Department_Management_Engaged__c, Geofencing_Engaged__c, Hiring_Engaged__c, Hrdocs_Engaged__c,
                       Manager_Log_Engaged__c, Messaging_Engaged__c, Mobile_Time_Tracking_Engaged__c, Oam_Activity__c, Overtime_Preferences_Engaged__c,
                       Scheduling_Engaged__c, Shift_Notes_Engaged__c, Shift_Trades_Engaged__c, Time_Offs_Engaged__c, Time_Tracking_Engaged__c,
                       Most_Recent_Payroll_Provider__c, Implementation_Project__c, Implementation_Project__r.Name
                FROM NBA_Queue__c 
                WHERE Sales_Rep__c = :userId
                AND Status__c = 'Pending'
                ORDER BY Priority_Score__c DESC, Due_Date__c ASC
            ];
            
            System.debug('Pending NBA_Queue__c records for user: ' + items.size());
            
            if (!items.isEmpty()) {
                // Filter out items that should be skipped
                List<NBA_Queue__c> filteredItems = new List<NBA_Queue__c>();
                
                for(NBA_Queue__c item : items) {
                    if (shouldSkipQueueItem(item)) {
                        System.debug('Skipping item ' + item.Id + ' due to filtering rules');
                        continue;
                    }
                    filteredItems.add(item);
                }
                
                System.debug('Items after filtering: ' + filteredItems.size());
                
                if (!filteredItems.isEmpty()) {
                    // Calculate adjusted priority scores and sort by the adjusted score
                    for(NBA_Queue__c item : filteredItems) {
                        Decimal adjustedScore = calculateAdjustedPriorityScore(item);
                        System.debug('Item: ' + item.Id + ' - Original Score: ' + item.Priority_Score__c + ' - Adjusted Score: ' + adjustedScore);
                    }
                    
                    // Sort by adjusted priority score (highest first)
                    filteredItems.sort(new PriorityScoreComparator());
                    
                    System.debug('Returning item: ' + filteredItems[0].Id + ' - ' + filteredItems[0].Subject__c);
                    
                    // Note: Contact information will be handled in the LWC by querying OpportunityContactRole directly
                    // This avoids the need to add virtual fields to the NBA_Queue__c object
                    return filteredItems[0];
                } else {
                    System.debug('No items remain after filtering');
                    return null;
                }
            } else {
                System.debug('No pending items found for user');
            }
            
            return null;
            
        } catch (Exception e) {
            System.debug('ERROR in getNextQueueItem: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving queue items: ' + e.getMessage());
        }
    }
    
    // Helper method to calculate adjusted priority score
    private static Decimal calculateAdjustedPriorityScore(NBA_Queue__c item) {
        Map<String, Object> details = calculateAdjustedPriorityScoreWithDetails(item);
        return (Decimal) details.get('adjustedScore');
    }
    
    // Custom comparator class to sort by status first (In Progress prioritized), then by adjusted priority score
    public class PriorityScoreComparator implements Comparator<NBA_Queue__c> {
        public Integer compare(NBA_Queue__c item1, NBA_Queue__c item2) {
            // First, prioritize In Progress items over Pending items
            if (item1.Status__c == 'In Progress' && item2.Status__c == 'Pending') {
                return -1; // In Progress comes first
            }
            if (item1.Status__c == 'Pending' && item2.Status__c == 'In Progress') {
                return 1; // Pending comes after In Progress
            }
            
            // If both items have the same status, sort by adjusted priority score
            Decimal score1 = calculateAdjustedPriorityScore(item1);
            Decimal score2 = calculateAdjustedPriorityScore(item2);
            
            if (score1 > score2) return -1; // Higher score first
            if (score1 < score2) return 1;
            return 0;
        }
    }
    
    @AuraEnabled
    public static void markAsViewed(Id queueItemId) {
        try {
            NBA_Queue__c queueItem = [SELECT Id, First_Viewed_Date__c FROM NBA_Queue__c WHERE Id = :queueItemId];
            
            // Only update if First_Viewed_Date__c is null (first time viewing)
            if (queueItem.First_Viewed_Date__c == null) {
                queueItem.First_Viewed_Date__c = System.now();
                update queueItem;
            }
        } catch(Exception e) {
            throw new AuraHandledException('Error marking as viewed: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String getAccountPhoneNumber(Id accountId) {
        try {
            Account acc = [SELECT Id, Phone FROM Account WHERE Id = :accountId LIMIT 1];
            return acc.Phone;
        } catch(Exception e) {
            throw new AuraHandledException('Error retrieving phone number: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> getOpportunityPrimaryContact(Id opportunityId) {
        try {
            Map<String, Object> result = new Map<String, Object>();
            
            if (opportunityId == null) {
                System.debug('Opportunity ID is null, returning empty result');
                return result;
            }
            
            System.debug('Querying Opportunity for Primary_Contact__c for Opportunity ID: ' + opportunityId);
            
            List<Opportunity> opportunities = [
                SELECT Id, Primary_Contact__c, Primary_Contact__r.Name, Primary_Contact__r.Email, 
                       Primary_Contact__r.Phone, Primary_Contact__r.MobilePhone
                FROM Opportunity 
                WHERE Id = :opportunityId 
                AND Primary_Contact__c != null
                LIMIT 1
            ];
            
            System.debug('Found ' + opportunities.size() + ' opportunities with primary contact');
            
            if (!opportunities.isEmpty()) {
                Opportunity opp = opportunities[0];
                System.debug('Primary contact details:');
                System.debug('  Contact ID: ' + opp.Primary_Contact__c);
                System.debug('  Contact Name: ' + opp.Primary_Contact__r.Name);
                System.debug('  Contact Email: ' + opp.Primary_Contact__r.Email);
                System.debug('  Contact Phone: ' + opp.Primary_Contact__r.Phone);
                System.debug('  Contact Mobile: ' + opp.Primary_Contact__r.MobilePhone);
                
                result.put('contactId', opp.Primary_Contact__c);
                result.put('contactName', opp.Primary_Contact__r.Name);
                result.put('contactEmail', opp.Primary_Contact__r.Email);
                result.put('contactPhone', opp.Primary_Contact__r.Phone != null ? opp.Primary_Contact__r.Phone : opp.Primary_Contact__r.MobilePhone);
                
                System.debug('Returning result: ' + result);
            } else {
                System.debug('No primary contact found for Opportunity: ' + opportunityId);
            }
            
            return result;
        } catch(Exception e) {
            System.debug('ERROR in getOpportunityPrimaryContact: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving opportunity primary contact: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String acceptAction(Id queueItemId, String additionalNotes) {
        try {
            System.debug('=== acceptAction Debug ===');
            System.debug('Queue Item ID: ' + queueItemId);
            System.debug('Additional Notes: ' + additionalNotes);
            
            NBA_Queue__c queueItem = [SELECT Id, Account__c, Subject__c, Description__c, 
                                             Due_Date__c, Action_Type__c,
                                             Priority_Score__c, Sales_Rep__c, Opportunity__c
                                      FROM NBA_Queue__c 
                                      WHERE Id = :queueItemId];
            
            System.debug('Queue Item found: ' + queueItem.Id);
            System.debug('Account: ' + queueItem.Account__c);
            System.debug('Opportunity: ' + queueItem.Opportunity__c);
            System.debug('Sales Rep: ' + queueItem.Sales_Rep__c);
            
            // Get primary contact from Opportunity
            Id whoId = null;
            if (queueItem.Opportunity__c != null) {
                List<Opportunity> opportunities = [
                    SELECT Primary_Contact__c 
                    FROM Opportunity 
                    WHERE Id = :queueItem.Opportunity__c 
                    AND Primary_Contact__c != null
                    LIMIT 1
                ];
                if (!opportunities.isEmpty()) {
                    whoId = opportunities[0].Primary_Contact__c;
                    System.debug('Primary Contact found: ' + whoId);
                }
            }
            
            // Use Sales_Rep__c directly
            Id taskOwnerId = queueItem.Sales_Rep__c;
            
            // Create standard Task
            Task newTask = new Task(
                Subject = 'Next Best Action: ' + queueItem.Action_Type__c,
                Description = buildTaskDescription(queueItem, additionalNotes),
                WhatId = queueItem.Opportunity__c != null ? queueItem.Opportunity__c : queueItem.Account__c,
                WhoId = whoId,
                OwnerId = taskOwnerId,
                ActivityDate = queueItem.Due_Date__c,
                Status = 'Completed',  // Mark as completed when accepted
                Priority = mapPriorityToTask(queueItem.Priority_Score__c)
            );
            
            System.debug('Task to be created: ' + newTask);
            
            insert newTask;
            System.debug('Task created successfully: ' + newTask.Id);
            
            // Update queue item status to "In Progress" and actioned date
            queueItem.Status__c = 'In Progress';
            queueItem.Actioned_Date__c = System.now();
            update queueItem;
            System.debug('Queue item updated successfully');
            
            // Publish platform event for real-time updates
            NBAQueueEventPublisher.publishItemStatusUpdate(queueItem.Id, taskOwnerId, 'Updated');
            
            // Return task ID for call disposition tracking
            return newTask.Id;
            
        } catch (Exception e) {
            System.debug('Error in acceptAction: ' + e.getMessage());
            System.debug('Error stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error accepting action: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void dismissAction(Id queueItemId, String dismissalReason) {
        NBA_Queue__c queueItem = [SELECT Id, Description__c, Sales_Rep__c FROM NBA_Queue__c WHERE Id = :queueItemId];
        
        queueItem.Status__c = 'Dismissed';
        queueItem.Dismissed_Reason__c = dismissalReason;
        queueItem.Actioned_Date__c = System.now();
        update queueItem;
        
        // Publish platform event for real-time updates
        NBAQueueEventPublisher.publishItemStatusUpdate(queueItem.Id, queueItem.Sales_Rep__c, 'Updated');
    }
    
    @AuraEnabled
    public static void updateCallDisposition(Id taskId, String disposition, String callNotes) {
        Task callTask = [SELECT Id, Description, CallDisposition FROM Task WHERE Id = :taskId];
        
        // Update CallDisposition field on Task
        if (String.isNotBlank(disposition)) {
            callTask.CallDisposition = disposition;
        }
        
        // Add call disposition and notes to description
        String existingDescription = callTask.Description != null ? callTask.Description : '';
        String updatedDescription = existingDescription;
        
        if (String.isNotBlank(disposition)) {
            updatedDescription += '\n\nCall Disposition: ' + disposition;
        }
        
        if (String.isNotBlank(callNotes)) {
            updatedDescription += '\n\nCall Notes: ' + callNotes;
        }
        
        callTask.Description = updatedDescription;
        update callTask;
    }
    
    @AuraEnabled
    public static void updateCallDispositionWithQueueId(Id taskId, Id queueItemId, String disposition, String callNotes) {
        // Update the task
        Task callTask = [SELECT Id, Description, CallDisposition FROM Task WHERE Id = :taskId];
        
        // Update CallDisposition field on Task
        if (String.isNotBlank(disposition)) {
            callTask.CallDisposition = disposition;
        }
        
        // Add call disposition and notes to description
        String existingDescription = callTask.Description != null ? callTask.Description : '';
        String updatedDescription = existingDescription;
        
        if (String.isNotBlank(disposition)) {
            updatedDescription += '\n\nCall Disposition: ' + disposition;
        }
        
        if (String.isNotBlank(callNotes)) {
            updatedDescription += '\n\nCall Notes: ' + callNotes;
        }
        
        callTask.Description = updatedDescription;
        update callTask;
        
        // Update the NBA Queue record with the disposition and notes
        NBA_Queue__c queueItem = [SELECT Id, Rep_Notes__c, Call_Disposition__c, Status__c, Completed_Date__c, Opportunity__c FROM NBA_Queue__c WHERE Id = :queueItemId];
        
        // Update Rep_Notes__c with call notes
        if (String.isNotBlank(callNotes)) {
            String existingNotes = queueItem.Rep_Notes__c != null ? queueItem.Rep_Notes__c : '';
            queueItem.Rep_Notes__c = existingNotes + '\n\nCall Notes: ' + callNotes;
        }
        
        // Update Call_Disposition__c with disposition
        if (String.isNotBlank(disposition)) {
            queueItem.Call_Disposition__c = disposition;
        }
        
        // Update status to "Accepted" and set completed date when disposition is saved
        queueItem.Status__c = 'Accepted';
        queueItem.Completed_Date__c = System.now();
        
        update queueItem;
        
        // Update the Opportunity Description field if there's a related opportunity
        if (queueItem.Opportunity__c != null && String.isNotBlank(callNotes)) {
            try {
                Opportunity opp = [SELECT Id, Description FROM Opportunity WHERE Id = :queueItem.Opportunity__c];
                
                // Append call notes to existing description on a new line
                String currentDescription = opp.Description != null ? opp.Description : '';
                String timestamp = DateTime.now().format('MM/dd/yyyy HH:mm:ss');
                String newCallNotes = '\n\n--- Call Notes (' + timestamp + ') ---\n' + callNotes;
                
                opp.Description = currentDescription + newCallNotes;
                update opp;
                System.debug('Updated Opportunity Description for ID: ' + opp.Id + ' - Appended call notes');
            } catch (Exception e) {
                System.debug('Error updating Opportunity Description: ' + e.getMessage());
            }
        }
    }
    
    @AuraEnabled
    public static void cancelCallDisposition(Id queueItemId) {
        // Revert the NBA Queue record status back to "Pending" when disposition is cancelled
        NBA_Queue__c queueItem = [SELECT Id, Status__c, Sales_Rep__c, Completed_Date__c FROM NBA_Queue__c WHERE Id = :queueItemId];
        queueItem.Status__c = 'Pending';
        queueItem.Completed_Date__c = null; // Clear completed date when reverting to pending
        update queueItem;
        
        // Publish platform event for real-time updates
        NBAQueueEventPublisher.publishItemStatusUpdate(queueItem.Id, queueItem.Sales_Rep__c, 'Updated');
    }
    
    @TestVisible private static String buildTaskDescription(NBA_Queue__c queueItem, String additionalNotes) {
        String description = queueItem.Description__c != null ? queueItem.Description__c : '';
        
        if(String.isNotBlank(additionalNotes)) {
            description += '\n\nAdditional Notes: ' + additionalNotes;
        }
        
        description += '\n\nGenerated from NBA Queue (Priority: ' + queueItem.Priority_Score__c + ')';
        
        return description;
    }
    
    @TestVisible private static String mapPriorityToTask(Decimal priorityScore) {
        if(priorityScore >= 80) {
            return 'High';
        } else if(priorityScore >= 60) {
            return 'Normal';
        } else {
            return 'Low';
        }
    }

    // Helper method to determine if a queue item should be skipped based on filtering rules
    private static Boolean shouldSkipQueueItem(NBA_Queue__c item) {
        // Skip if Opportunity Stage is one of the specified stages
        if (item.Opportunity__c != null && item.Opportunity__r.StageName != null) {
            String stage = item.Opportunity__r.StageName.toLowerCase();
            if (stage == 'closed won - pending implementation' || 
                stage == 'closed lost' || 
                stage == 'ran payroll') {
                System.debug('Skipping item due to Opportunity stage: ' + item.Opportunity__r.StageName);
                return true;
            }
        }
        
        // Skip if Opportunity Last_Call_Date_Time__c is today
        if (item.Opportunity__c != null && item.Opportunity__r.Last_Call_Date_Time__c != null) {
            DateTime lastCallTime = item.Opportunity__r.Last_Call_Date_Time__c;
            Date today = Date.today();
            Date lastCallDate = lastCallTime.date();
            
            if (lastCallDate == today) {
                System.debug('Skipping item due to last call being today: ' + lastCallTime);
                return true;
            }
        }
        
        // Skip if Account Payroll_Status__c contains specific values
        if (item.Account__r.Payroll_Status__c != null) {
            String payrollStatus = item.Account__r.Payroll_Status__c.toLowerCase();
            if (payrollStatus == 'pending' || 
                payrollStatus == 'processing' || 
                payrollStatus == 'paid') {
                System.debug('Skipping item due to payroll status: ' + item.Account__r.Payroll_Status__c);
                return true;
            }
        }
        
        return false;
    }

    @AuraEnabled
    public static Map<String, Object> getNextQueueItemWithDetails(Id userId) {
        // Debug logging
        System.debug('=== NBA Queue Debug ===');
        System.debug('User ID requesting queue items: ' + userId);
        System.debug('Current user context: ' + UserInfo.getUserId());
        System.debug('Current user name: ' + UserInfo.getName());
        
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            // First, let's check if there are any NBA_Queue__c records at all for this user
            List<NBA_Queue__c> allUserItems = [
                SELECT Id, Account__c, Sales_Rep__c, Status__c, Action_Type__c, Subject__c
                FROM NBA_Queue__c 
                WHERE Sales_Rep__c = :userId
            ];
            System.debug('Total NBA_Queue__c records for user: ' + allUserItems.size());
            
            // Log each record for debugging
            for(NBA_Queue__c item : allUserItems) {
                System.debug('Record ID: ' + item.Id + 
                           ', Sales_Rep__c: ' + item.Sales_Rep__c + 
                           ', Status__c: ' + item.Status__c);
            }
            
            // Now get the pending and in progress items with additional fields for priority calculation
            List<NBA_Queue__c> items = [
                SELECT Id, Account__c, Account__r.Name, Account__r.Employee_Count__c, Account__r.Company_Age_in_Days__c,
                       Account__r.Use_Case_Payroll__c, Account__r.Use_Case_Scheduling__c, Account__r.Use_Case_Time_Tracking__c,
                       Account__r.Phone, Account__r.Last_Web_Usage_Timestamp__c, Account__r.Payroll_Status__c,
                       Action_Type__c, Priority_Score__c, Subject__c, Description__c, Due_Date__c, Model_Reason__c, Status__c,
                       Company_Age_Days__c, Active_Employees__c, Feature_Usage__c, Contact_Name__c, Contact_Phone__c, Action_Context__c,
                       Opportunity__c, Opportunity__r.Name, Opportunity__r.Source__c, Opportunity__r.StageName, 
                       Opportunity__r.Payroll_Buyer_Stage__c, Opportunity__r.Implementation_Status__c, Opportunity__r.Account_Product_Switcher_Data__c,
                       Opportunity__r.Account_Current_Payroll__c, Opportunity__r.Last_Call_Date_Time__c, Opportunity__r.Description,
                       Opportunity_Stage__c, Opportunity_Source__c, Payroll_Buyer_Stage__c, Rep_Notes__c, Close_Date__c, Inception_Switcher__c,
                       Current_Payroll_Provider__c, Last_Call_Date__c, Best_Time_to_Call__c, Best_Number_to_Call__c, Best_Person_to_Call__c, Best_Person_to_Call__r.Name, Best_Person_to_Call__r.Phone, Best_Person_to_Call__r.Email,
                       Sales_Rep__c, First_Viewed_Date__c, Actioned_Date__c,
                       Break_Preferences_Engaged__c, Department_Management_Engaged__c, Geofencing_Engaged__c, Hiring_Engaged__c, Hrdocs_Engaged__c,
                       Manager_Log_Engaged__c, Messaging_Engaged__c, Mobile_Time_Tracking_Engaged__c, Oam_Activity__c, Overtime_Preferences_Engaged__c,
                       Scheduling_Engaged__c, Shift_Notes_Engaged__c, Shift_Trades_Engaged__c, Time_Offs_Engaged__c, Time_Tracking_Engaged__c,
                       Most_Recent_Payroll_Provider__c, Implementation_Project__c, Implementation_Project__r.Name
                FROM NBA_Queue__c 
                WHERE Sales_Rep__c = :userId
                AND Status__c IN ('Pending', 'In Progress')
                ORDER BY Status__c ASC, Priority_Score__c DESC, Due_Date__c ASC
            ];
            
            System.debug('Pending NBA_Queue__c records for user: ' + items.size());
            
            if (!items.isEmpty()) {
                // Filter out items that should be skipped
                List<NBA_Queue__c> filteredItems = new List<NBA_Queue__c>();
                
                for(NBA_Queue__c item : items) {
                    if (shouldSkipQueueItem(item)) {
                        System.debug('Skipping item ' + item.Id + ' due to filtering rules');
                        continue;
                    }
                    filteredItems.add(item);
                }
                
                System.debug('Items after filtering: ' + filteredItems.size());
                
                if (!filteredItems.isEmpty()) {
                    // Calculate adjusted priority scores and sort by the adjusted score
                    for(NBA_Queue__c item : filteredItems) {
                        Map<String, Object> scoreDetails = calculateAdjustedPriorityScoreWithDetails(item);
                        System.debug('Item: ' + item.Id + ' - Status: ' + item.Status__c + ' - Original Score: ' + item.Priority_Score__c + ' - Adjusted Score: ' + scoreDetails.get('adjustedScore'));
                    }
                    
                    // Sort by adjusted priority score (highest first)
                    filteredItems.sort(new PriorityScoreComparator());
                    
                    NBA_Queue__c selectedItem = filteredItems[0];
                    Map<String, Object> scoreDetails = calculateAdjustedPriorityScoreWithDetails(selectedItem);
                    
                    System.debug('Returning item: ' + selectedItem.Id + ' - ' + selectedItem.Subject__c);
                    
                    result.put('queueItem', selectedItem);
                    result.put('originalScore', selectedItem.Priority_Score__c);
                    result.put('adjustedScore', scoreDetails.get('adjustedScore'));
                    result.put('webUsageMultiplier', scoreDetails.get('webUsageMultiplier'));
                    result.put('bestTimeMultiplier', scoreDetails.get('bestTimeMultiplier'));
                    result.put('webUsageApplied', scoreDetails.get('webUsageApplied'));
                    result.put('bestTimeApplied', scoreDetails.get('bestTimeApplied'));
                    
                    // Note: Contact information will be handled in the LWC by querying OpportunityContactRole directly
                    // This avoids the need to add virtual fields to the NBA_Queue__c object
                } else {
                    System.debug('No items remain after filtering');
                    result.put('queueItem', null);
                }
            } else {
                System.debug('No pending or in progress items found for user');
                result.put('queueItem', null);
            }
            
            return result;
            
        } catch (Exception e) {
            System.debug('ERROR in getNextQueueItemWithDetails: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving queue items: ' + e.getMessage());
        }
    }

    // Helper method to calculate adjusted priority score and return details
    private static Map<String, Object> calculateAdjustedPriorityScoreWithDetails(NBA_Queue__c item) {
        Decimal adjustedScore = item.Priority_Score__c != null ? item.Priority_Score__c : 0;
        Boolean webUsageApplied = false;
        Boolean bestTimeApplied = false;
        Decimal webUsageMultiplier = 1;
        Decimal bestTimeMultiplier = 1;

        // Check if Last_Web_Usage_Timestamp__c is within the last hour
        if (item.Account__r.Last_Web_Usage_Timestamp__c != null) {
            DateTime webUsageTime = item.Account__r.Last_Web_Usage_Timestamp__c;
            DateTime oneHourAgo = DateTime.now().addHours(-1);
            
            if (webUsageTime >= oneHourAgo) {
                adjustedScore = adjustedScore * 1.25;
                webUsageApplied = true;
                webUsageMultiplier = 1.25;
                System.debug('Applied 1.25x multiplier for recent web usage. Original: ' + item.Priority_Score__c + ', Adjusted: ' + adjustedScore);
            }
        }
        
        // Check if Best_Time_to_Call__c is within the current hour
        if (item.Best_Time_to_Call__c != null) {
            Time bestTime = item.Best_Time_to_Call__c.time();
            DateTime now = DateTime.now();
            Time currentTime = Time.newInstance(now.hour(), now.minute(), now.second(), 0);
            
            // Convert to minutes for easier comparison
            Integer bestTimeMinutes = bestTime.hour() * 60 + bestTime.minute();
            Integer currentTimeMinutes = currentTime.hour() * 60 + currentTime.minute();
            
            // Check if best time is within the current hour (within 30 minutes)
            Integer timeDifference = Math.abs(bestTimeMinutes - currentTimeMinutes);
            if (timeDifference <= 30) {
                adjustedScore = adjustedScore * 1.2;
                bestTimeApplied = true;
                bestTimeMultiplier = 1.2;
                System.debug('Applied 1.2x multiplier for best time to call. Original: ' + item.Priority_Score__c + ', Adjusted: ' + adjustedScore);
            }
        }
        
        Map<String, Object> details = new Map<String, Object>();
        details.put('adjustedScore', adjustedScore);
        details.put('webUsageApplied', webUsageApplied);
        details.put('bestTimeApplied', bestTimeApplied);
        details.put('webUsageMultiplier', webUsageMultiplier);
        details.put('bestTimeMultiplier', bestTimeMultiplier);
        return details;
    }


}