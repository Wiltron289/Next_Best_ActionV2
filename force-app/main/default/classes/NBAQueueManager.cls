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
                Opportunity__c = oppId,
                Sales_Rep__c = salesRepId
            );
            queueItems.add(item);
        }
        
        // Assign to users
        assignQueueItems(queueItems);
        insert queueItems;
        
        // Event publishing removed
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
                       Account__r.Phone, Account__r.Last_Web_Usage_Timestamp__c, Account__r.Payroll_Status__c, Account__r.Last_Progression_Time__c,
                       Account__r.Check_Console_Link__c, Account__r.Admin_Link__c, Account__r.Reactive_Admin_Link__c, Account__r.Time_Zone__c,
                       Action_Type__c, Priority_Score__c, Subject__c, Description__c, Due_Date__c, Status__c, CreatedDate,
                        Company_Age_Days__c, Action_Context__c, Snoozed_Until__c,
                       Opportunity__c, Opportunity__r.Name, Opportunity__r.Source__c, Opportunity__r.StageName, 
                       Opportunity__r.Primary_Contact__c, Opportunity__r.Primary_Contact__r.Name, Opportunity__r.Primary_Contact__r.Email, 
                       Opportunity__r.Primary_Contact__r.Phone, Opportunity__r.Primary_Contact__r.MobilePhone, Opportunity__r.Primary_Contact__r.OtherPhone,
                       Opportunity__r.Payroll_Buyer_Stage__c, Opportunity__r.Implementation_Status__c, Opportunity__r.Account_Product_Switcher_Data__c,
                       Opportunity__r.Account_Current_Payroll__c, Opportunity__r.Last_Call_Date_Time__c, Opportunity__r.Future_Follow_Up_Date__c, Opportunity__r.Next_Step_Date__c, Opportunity__r.Time_Zone__c,
                       Lead__c, Lead__r.Name, Lead__r.Email, Lead__r.Phone, Lead__r.MobilePhone, Lead__r.LeadSource, Lead__r.Status,
                       Start_Time__c, Event_Id__c,
                       Payroll_Buyer_Stage__c, Rep_Notes__c, Close_Date__c,
                       Current_Payroll_Provider__c, Best_Time_to_Call__c, Best_Number_to_Call__c, Best_Person_to_Call__c, Best_Person_to_Call__r.Name, Best_Person_to_Call__r.Phone, Best_Person_to_Call__r.MobilePhone, Best_Person_to_Call__r.OtherPhone, Best_Person_to_Call__r.Secondary_Phone_Number__c, Best_Person_to_Call__r.Email,
                       Sales_Rep__c, First_Viewed_Date__c, Actioned_Date__c, Last_Viewed_Date__c, Priority_Multiplier_Applied__c, Person_Called__c,
                       Break_Preferences_Engaged__c, Department_Management_Engaged__c, Geofencing_Engaged__c, Hiring_Engaged__c, Hrdocs_Engaged__c,
                       Manager_Log_Engaged__c, Messaging_Engaged__c, Mobile_Time_Tracking_Engaged__c, Oam_Activity__c, Overtime_Preferences_Engaged__c,
                        Scheduling_Engaged__c, Shift_Notes_Engaged__c, Shift_Trades_Engaged__c, Time_Offs_Engaged__c, Time_Tracking_Engaged__c,
                        Implementation_Project__c, Implementation_Project__r.Name,
                        Call_Script__c, Meeting_Disposition__c, Meeting_Notes__c
                FROM NBA_Queue__c 
                WHERE Sales_Rep__c = :userId
                AND Status__c IN ('Pending', 'In Progress', 'Snoozed')
                AND (Status__c != 'Snoozed' OR Snoozed_Until__c <= :System.now())
                ORDER BY Status__c ASC, Priority_Score__c DESC, Due_Date__c ASC
            ];
            
            System.debug('Pending and In Progress NBA_Queue__c records for user: ' + items.size());
            
            if (!items.isEmpty()) {
                // Preload blocked opportunities with future events to avoid per-record queries
                Set<Id> oppIds = new Set<Id>();
                for (NBA_Queue__c item : items) if (item.Opportunity__c != null) oppIds.add(item.Opportunity__c);
                Set<Id> blockedOppIds = getOpportunitiesBlockedByFutureEvents(oppIds);
                // Filter out items that should be skipped
                List<NBA_Queue__c> filteredItems = new List<NBA_Queue__c>();
                
                for(NBA_Queue__c item : items) {
                    String reason = getSkipReason(item, blockedOppIds);
                    if (reason != null) {
                        System.debug('Skipping item ' + item.Id + ' due to: ' + reason);
                        // Removed per-item DML to avoid DML limit during filtering
                        // Not_Surfaced_Reasons__c can be populated via a separate async job if needed
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
                    
                    NBA_Queue__c selectedItem = filteredItems[0];
                    
                    // Update last viewed date when item is served to user
                    updateItemLastViewedDate(selectedItem);
                    
                    System.debug('Returning item: ' + selectedItem.Id + ' - ' + selectedItem.Subject__c);
                    
                    // Note: Contact information will be handled in the LWC by querying OpportunityContactRole directly
                    // This avoids the need to add virtual fields to the NBA_Queue__c object
                    return selectedItem;
                } else {
                    System.debug('No items remain after filtering');
                    return null;
                }
            } else {
                System.debug('No pending or in progress items found for user');
            }
            
            return null;
            
        } catch (Exception e) {
            System.debug('ERROR in getNextQueueItem: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving queue items: ' + e.getMessage());
        }
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
                       Account__r.Phone, Account__r.Last_Web_Usage_Timestamp__c, Account__r.Payroll_Status__c, Account__r.Last_Progression_Time__c,
                       Account__r.Check_Console_Link__c, Account__r.Admin_Link__c, Account__r.Reactive_Admin_Link__c, Account__r.Time_Zone__c,
                       Action_Type__c, Priority_Score__c, Subject__c, Description__c, Due_Date__c, Status__c, CreatedDate,
                       Company_Age_Days__c, Action_Context__c, Snoozed_Until__c,
                       Opportunity__c, Opportunity__r.Name, Opportunity__r.Source__c, Opportunity__r.StageName, 
                       Opportunity__r.Primary_Contact__c, Opportunity__r.Primary_Contact__r.Name, Opportunity__r.Primary_Contact__r.Email, 
                       Opportunity__r.Primary_Contact__r.Phone, Opportunity__r.Primary_Contact__r.MobilePhone, Opportunity__r.Primary_Contact__r.OtherPhone,
                       Opportunity__r.Payroll_Buyer_Stage__c, Opportunity__r.Implementation_Status__c, Opportunity__r.Account_Product_Switcher_Data__c,
                       Opportunity__r.Account_Current_Payroll__c, Opportunity__r.Last_Call_Date_Time__c, Opportunity__r.Future_Follow_Up_Date__c, Opportunity__r.Next_Step_Date__c, Opportunity__r.Time_Zone__c, Opportunity__r.Description,
                       Lead__c, Lead__r.Name, Lead__r.Email, Lead__r.Phone, Lead__r.MobilePhone, Lead__r.LeadSource, Lead__r.Status,
                       Start_Time__c, Event_Id__c, Email_Message_Id__c,
                       Payroll_Buyer_Stage__c, Rep_Notes__c, Close_Date__c,
                       Current_Payroll_Provider__c, Best_Time_to_Call__c, Best_Number_to_Call__c, Best_Person_to_Call__c, Best_Person_to_Call__r.Name, Best_Person_to_Call__r.Phone, Best_Person_to_Call__r.MobilePhone, Best_Person_to_Call__r.OtherPhone, Best_Person_to_Call__r.Secondary_Phone_Number__c, Best_Person_to_Call__r.Email,
                       Sales_Rep__c, First_Viewed_Date__c, Actioned_Date__c, Last_Viewed_Date__c, Priority_Multiplier_Applied__c, Person_Called__c,
                       Break_Preferences_Engaged__c, Department_Management_Engaged__c, Geofencing_Engaged__c, Hiring_Engaged__c, Hrdocs_Engaged__c,
                       Manager_Log_Engaged__c, Messaging_Engaged__c, Mobile_Time_Tracking_Engaged__c, Oam_Activity__c, Overtime_Preferences_Engaged__c,
                        Scheduling_Engaged__c, Shift_Notes_Engaged__c, Shift_Trades_Engaged__c, Time_Offs_Engaged__c, Time_Tracking_Engaged__c,
                        Implementation_Project__c, Implementation_Project__r.Name,
                        Call_Script__c, Meeting_Disposition__c, Meeting_Notes__c
                FROM NBA_Queue__c 
                WHERE Sales_Rep__c = :userId
                AND Status__c IN ('Pending', 'In Progress', 'Snoozed')
                AND (Status__c != 'Snoozed' OR Snoozed_Until__c <= :System.now())
                ORDER BY Status__c ASC, Priority_Score__c DESC, Due_Date__c ASC
            ];
            
            System.debug('Pending and In Progress NBA_Queue__c records for user: ' + items.size());
            
            if (!items.isEmpty()) {
                // Preload blocked opportunities with future events to avoid per-record queries
                Set<Id> oppIds = new Set<Id>();
                for (NBA_Queue__c item : items) if (item.Opportunity__c != null) oppIds.add(item.Opportunity__c);
                Set<Id> blockedOppIds = getOpportunitiesBlockedByFutureEvents(oppIds);
                // Filter out items that should be skipped
                List<NBA_Queue__c> filteredItems = new List<NBA_Queue__c>();
                
                for(NBA_Queue__c item : items) {
                    String reason = getSkipReason(item, blockedOppIds);
                    if (reason != null) {
                        // Removed per-item DML to avoid DML limit during filtering
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
                    
                    // Clear not surfaced reasons and update last viewed date when served
                    try { update new NBA_Queue__c(Id = selectedItem.Id, Not_Surfaced_Reasons__c = null); } catch (Exception e) {}
                    updateItemLastViewedDate(selectedItem);
                    
                    System.debug('Returning item: ' + selectedItem.Id + ' - ' + selectedItem.Subject__c);
                    
                    result.put('queueItem', selectedItem);
                    result.put('originalScore', selectedItem.Priority_Score__c);
                    result.put('adjustedScore', scoreDetails.get('adjustedScore'));
                    result.put('webUsageMultiplier', scoreDetails.get('webUsageMultiplier'));
                    result.put('bestTimeMultiplier', scoreDetails.get('bestTimeMultiplier'));
                    result.put('progressionMultiplier', scoreDetails.get('progressionMultiplier'));
                    result.put('webUsageApplied', scoreDetails.get('webUsageApplied'));
                    result.put('bestTimeApplied', scoreDetails.get('bestTimeApplied'));
                    result.put('progressionApplied', scoreDetails.get('progressionApplied'));
                    result.put('multiplierDescription', scoreDetails.get('multiplierDescription'));
                    
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

    @AuraEnabled
    public static void saveFutureFollowUp(Id queueItemId, Date futureFollowUpDate, String futureFollowUpReason) {
        if (queueItemId == null) return;
        NBA_Queue__c qi = [SELECT Id, Opportunity__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
        if (qi.Opportunity__c == null) return;
        Opportunity opp = [SELECT Id, StageName FROM Opportunity WHERE Id = :qi.Opportunity__c LIMIT 1];
        try {
            if (futureFollowUpDate != null) {
                opp.put('Future_Follow_Up_Date__c', futureFollowUpDate);
            }
            if (String.isNotBlank(futureFollowUpReason)) {
                opp.put('Future_Follow_Up_Reason__c', futureFollowUpReason);
            }
            // Ensure stage is updated to Future Follow-Up
            try {
                opp.StageName = 'Future Follow-Up';
            } catch (Exception eInner) {
                // ignore if stage value not present in org
            }
        } catch (Exception e) {
            // Defensive in case fields don't exist in org
        }
        update opp;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getFutureFollowUpReasons() {
        List<String> out = new List<String>();
        try {
            Schema.DescribeFieldResult dfr = Opportunity.Future_Follow_Up_Reason__c.getDescribe();
            for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                if (pe.isActive()) {
                    out.add(pe.getLabel());
                }
            }
        } catch (Exception e) {
            // field not present or not accessible
        }
        return out;
    }

    // Activities fetcher for widget Activity tab (upcoming + last 90 days)
    @AuraEnabled(cacheable=true)
    public static Map<String, List<Map<String, Object>>> getActivities(Id recordId) {
        Map<String, List<Map<String, Object>>> out = new Map<String, List<Map<String, Object>>>();
        out.put('upcoming', new List<Map<String, Object>>());
        out.put('past', new List<Map<String, Object>>());
        if (recordId == null) return out;
        Date today = Date.today();
        Date ninetyDaysAgo = today.addDays(-90);
        // Build context: include related Account and Contacts for Opportunities, Contacts for Accounts, Lead itself for Leads
        Set<Id> whatIds = new Set<Id>();
        Set<Id> whoIds = new Set<Id>();
        String prefix = String.valueOf(recordId).left(3);
        if (prefix == '006') { // Opportunity
            // Base strictly on Opportunity: WhatId = Opportunity; include Opp Contacts via OCR as WhoIds
            whatIds.add(recordId);
            try {
                for (OpportunityContactRole ocr : [SELECT ContactId FROM OpportunityContactRole WHERE OpportunityId = :recordId AND ContactId != null LIMIT 200]) {
                    whoIds.add(ocr.ContactId);
                }
            } catch (Exception e) {}
        } else if (prefix == '001') { // Account
            whatIds.add(recordId);
            for (Contact c : [SELECT Id FROM Contact WHERE AccountId = :recordId LIMIT 500]) {
                whoIds.add(c.Id);
            }
        } else if (prefix == '00Q') { // Lead
            whoIds.add(recordId);
            whatIds.add(recordId); // defensive, in case of WhatId usage
        } else {
            // Fallback: use as both What and Who
            whatIds.add(recordId);
            whoIds.add(recordId);
        }

        // Upcoming Tasks (not completed, due today or future)
        for (Task t : [SELECT Id, Subject, ActivityDate, Status
                       FROM Task
                       WHERE ((WhatId IN :whatIds) OR (WhoId IN :whoIds))
                       AND Status != 'Completed'
                       AND ActivityDate >= :today
                       ORDER BY ActivityDate ASC
                       LIMIT 300]) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('type', 'Task');
            row.put('id', (String)t.Id);
            row.put('subject', t.Subject);
            row.put('date', t.ActivityDate);
            row.put('status', t.Status);
            out.get('upcoming').add(row);
        }
        // Upcoming Events
        for (Event e : [SELECT Id, Subject, StartDateTime, EndDateTime
                        FROM Event
                        WHERE ((WhatId IN :whatIds) OR (WhoId IN :whoIds))
                        AND StartDateTime >= :DateTime.newInstance(today, Time.newInstance(0,0,0,0))
                        ORDER BY StartDateTime ASC
                        LIMIT 300]) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('type', 'Event');
            row.put('id', (String)e.Id);
            row.put('subject', e.Subject);
            row.put('start', e.StartDateTime);
            row.put('end', e.EndDateTime);
            out.get('upcoming').add(row);
        }
        // Past Tasks within last 90 days
        for (Task t2 : [SELECT Id, Subject, ActivityDate, Status
                        FROM Task
                        WHERE ((WhatId IN :whatIds) OR (WhoId IN :whoIds))
                        AND ActivityDate >= :ninetyDaysAgo
                        AND ActivityDate < :today
                        ORDER BY ActivityDate DESC
                        LIMIT 300]) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('type', 'Task');
            row.put('id', (String)t2.Id);
            row.put('subject', t2.Subject);
            row.put('date', t2.ActivityDate);
            row.put('status', t2.Status);
            out.get('past').add(row);
        }
        // Past Events within last 90 days
        for (Event e2 : [SELECT Id, Subject, StartDateTime, EndDateTime
                         FROM Event
                         WHERE ((WhatId IN :whatIds) OR (WhoId IN :whoIds))
                         AND StartDateTime >= :DateTime.newInstance(ninetyDaysAgo, Time.newInstance(0,0,0,0))
                         AND StartDateTime < :DateTime.newInstance(today, Time.newInstance(0,0,0,0))
                         ORDER BY StartDateTime DESC
                         LIMIT 300]) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('type', 'Event');
            row.put('id', (String)e2.Id);
            row.put('subject', e2.Subject);
            row.put('start', e2.StartDateTime);
            row.put('end', e2.EndDateTime);
            out.get('past').add(row);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> listNotSurfacedItems(Id userId, Integer limitSize) {
        try {
            Integer lim = (limitSize == null || limitSize <= 0) ? 50 : limitSize;
            // Pull candidate items similar to next-item query
            List<NBA_Queue__c> items = [
                SELECT Id, Account__c, Account__r.Name,
                       Opportunity__c, Opportunity__r.Name, Opportunity__r.StageName,
                       Status__c, Priority_Score__c, Subject__c, Action_Type__c,
                       Snoozed_Until__c, Account__r.Payroll_Status__c,
                       Opportunity__r.Last_Call_Date_Time__c, Opportunity__r.Future_Follow_Up_Date__c, Opportunity__r.Next_Step_Date__c
                FROM NBA_Queue__c
                WHERE Sales_Rep__c = :userId
                AND Status__c IN ('Pending', 'Snoozed')
                AND (Status__c != 'Snoozed' OR Snoozed_Until__c <= :System.now())
                ORDER BY Priority_Score__c DESC, Due_Date__c ASC
                LIMIT :lim
            ];

            Set<Id> oppIds = new Set<Id>();
            for (NBA_Queue__c item : items) if (item.Opportunity__c != null) oppIds.add(item.Opportunity__c);
            Set<Id> blockedOppIds = getOpportunitiesBlockedByFutureEvents(oppIds);

            List<Map<String, Object>> out = new List<Map<String, Object>>();
            for (NBA_Queue__c i : items) {
                String reason = getSkipReason(i, blockedOppIds);
                if (reason != null) {
                    Map<String, Object> row = new Map<String, Object>();
                    row.put('id', (String)i.Id);
                    row.put('subject', i.Subject__c);
                    row.put('reason', reason);
                    row.put('actionType', i.Action_Type__c);
                    row.put('priority', i.Priority_Score__c);
                    row.put('accountId', i.Account__c);
                    row.put('accountName', i.Account__r != null ? i.Account__r.Name : null);
                    row.put('opportunityId', i.Opportunity__c);
                    row.put('opportunityName', i.Opportunity__r != null ? i.Opportunity__r.Name : null);
                    out.add(row);
                }
            }
            return out;
        } catch (Exception e) {
            throw new AuraHandledException('Error listing not-surfaced items: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> getUpNextItem(Id userId, Id excludeQueueItemId) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            // Pull candidate items with the same fields and filters used for next item selection
            List<NBA_Queue__c> items = [
                SELECT Id, Account__c, Account__r.Name, Account__r.Employee_Count__c, Account__r.Company_Age_in_Days__c,
                       Account__r.Use_Case_Payroll__c, Account__r.Use_Case_Scheduling__c, Account__r.Use_Case_Time_Tracking__c,
                       Account__r.Phone, Account__r.Last_Web_Usage_Timestamp__c, Account__r.Payroll_Status__c, Account__r.Last_Progression_Time__c,
                       Account__r.Check_Console_Link__c, Account__r.Admin_Link__c, Account__r.Reactive_Admin_Link__c, Account__r.Time_Zone__c,
                       Action_Type__c, Priority_Score__c, Subject__c, Description__c, Due_Date__c, Status__c, CreatedDate,
                       Company_Age_Days__c, Action_Context__c, Snoozed_Until__c, Start_Time__c,
                       Opportunity__c, Opportunity__r.Name, Opportunity__r.StageName, 
                       Opportunity__r.Payroll_Buyer_Stage__c, Opportunity__r.Implementation_Status__c, Opportunity__r.Account_Product_Switcher_Data__c,
                       Opportunity__r.Account_Current_Payroll__c, Opportunity__r.Last_Call_Date_Time__c, Opportunity__r.Future_Follow_Up_Date__c, Opportunity__r.Next_Step_Date__c, Opportunity__r.Time_Zone__c, Opportunity__r.Description,
                       Lead__c, Lead__r.Name, Lead__r.Email, Lead__r.Phone, Lead__r.MobilePhone, Lead__r.LeadSource, Lead__r.Status,
                       Payroll_Buyer_Stage__c, Rep_Notes__c, Close_Date__c,
                       Current_Payroll_Provider__c, Best_Time_to_Call__c, Best_Number_to_Call__c, Best_Person_to_Call__c, Best_Person_to_Call__r.Name, Best_Person_to_Call__r.Phone, Best_Person_to_Call__r.MobilePhone, Best_Person_to_Call__r.OtherPhone, Best_Person_to_Call__r.Secondary_Phone_Number__c, Best_Person_to_Call__r.Email,
                       Sales_Rep__c, First_Viewed_Date__c, Actioned_Date__c, Last_Viewed_Date__c, Priority_Multiplier_Applied__c, Person_Called__c,
                       Break_Preferences_Engaged__c, Department_Management_Engaged__c, Geofencing_Engaged__c, Hiring_Engaged__c, Hrdocs_Engaged__c,
                       Manager_Log_Engaged__c, Messaging_Engaged__c, Mobile_Time_Tracking_Engaged__c, Oam_Activity__c, Overtime_Preferences_Engaged__c,
                       Scheduling_Engaged__c, Shift_Notes_Engaged__c, Shift_Trades_Engaged__c, Time_Offs_Engaged__c, Time_Tracking_Engaged__c,
                       Implementation_Project__c, Implementation_Project__r.Name,
                       Call_Script__c
                FROM NBA_Queue__c 
                WHERE Sales_Rep__c = :userId
                AND Status__c IN ('Pending', 'In Progress', 'Snoozed')
                AND (Status__c != 'Snoozed' OR Snoozed_Until__c <= :System.now())
                ORDER BY Status__c ASC, Priority_Score__c DESC, Due_Date__c ASC
            ];

            if (items.isEmpty()) {
                result.put('upNext', null);
                return result;
            }

            // Preload blocked opportunities with future events to avoid per-record queries
            Set<Id> oppIds = new Set<Id>();
            for (NBA_Queue__c item : items) if (item.Opportunity__c != null) oppIds.add(item.Opportunity__c);
            Set<Id> blockedOppIds = getOpportunitiesBlockedByFutureEvents(oppIds);

            // Apply same filtering rules as main queue
            List<NBA_Queue__c> filteredItems = new List<NBA_Queue__c>();
            for (NBA_Queue__c item : items) {
                String skipReason = getSkipReason(item, blockedOppIds);
                if (skipReason != null) {
                    System.debug('Up Next: Skipping item ' + item.Id + ' due to: ' + skipReason);
                    continue;
                }
                filteredItems.add(item);
            }

            System.debug('Up Next: Total items after filtering: ' + filteredItems.size());
            for (NBA_Queue__c item : filteredItems) {
                System.debug('Up Next: Filtered item ' + item.Id + ' - Priority: ' + item.Priority_Score__c + ' - Subject: ' + item.Subject__c);
            }

            if (filteredItems.isEmpty()) {
                System.debug('Up Next: No eligible items found');
                result.put('upNext', null);
                return result;
            }

            // Sort by adjusted priority using the same comparator
            filteredItems.sort(new PriorityScoreComparator());

            // Pick the first item that is not the currently displayed one
            NBA_Queue__c nextItem = null;
            for (NBA_Queue__c item : filteredItems) {
                System.debug('Up Next: Checking item ' + item.Id + ' (exclude: ' + excludeQueueItemId + ')');
                if (excludeQueueItemId == null || item.Id != excludeQueueItemId) {
                    nextItem = item;
                    System.debug('Up Next: Selected item ' + item.Id + ' as up next');
                    break;
                } else {
                    System.debug('Up Next: Skipping item ' + item.Id + ' because it matches excludeQueueItemId');
                }
            }

            result.put('upNext', nextItem);
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving up-next item: ' + e.getMessage());
        }
    }
    
    // Helper method to calculate adjusted priority score
    private static Decimal calculateAdjustedPriorityScore(NBA_Queue__c item) {
        Map<String, Object> details = calculateAdjustedPriorityScoreWithDetails(item);
        return (Decimal) details.get('adjustedScore');
    }
    
    // Custom comparator class to sort by status first (In Progress prioritized), then by adjusted priority score, then by creation date
    public class PriorityScoreComparator implements Comparator<NBA_Queue__c> {
        public Integer compare(NBA_Queue__c item1, NBA_Queue__c item2) {
            // First, prioritize Event action types with Start_Time__c within 7 minutes (absolute priority)
            Boolean item1IsUrgentEvent = isUrgentEvent(item1);
            Boolean item2IsUrgentEvent = isUrgentEvent(item2);
            
            if (item1IsUrgentEvent && !item2IsUrgentEvent) {
                return -1; // Urgent Event comes first
            }
            if (!item1IsUrgentEvent && item2IsUrgentEvent) {
                return 1; // Non-urgent comes after urgent Event
            }
            
            // Second, prioritize In Progress items over Pending items
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
            
            // If priority scores are equal, sort by creation date (most recent first)
            if (item1.CreatedDate > item2.CreatedDate) return -1; // More recent first
            if (item1.CreatedDate < item2.CreatedDate) return 1;
            
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

    @AuraEnabled(cacheable=true)
    public static Id getAccountIdForOpportunity(Id opportunityId) {
        try {
            if (opportunityId == null) return null;
            Opportunity o = [SELECT AccountId FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
            return o != null ? o.AccountId : null;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving Account for Opportunity: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> getAccountPrimaryContact(Id accountId) {
        try {
            Map<String, Object> result = new Map<String, Object>();
            if (accountId == null) {
                return result;
            }
            List<Account> accounts = [
                SELECT Id, Primary_Contact__c, Primary_Contact__r.Name, Primary_Contact__r.Email,
                       Primary_Contact__r.Phone, Primary_Contact__r.MobilePhone
                FROM Account
                WHERE Id = :accountId AND Primary_Contact__c != null
                LIMIT 1
            ];
            if (!accounts.isEmpty()) {
                Account acc = accounts[0];
                result.put('contactId', acc.Primary_Contact__c);
                result.put('contactName', acc.Primary_Contact__r.Name);
                result.put('contactEmail', acc.Primary_Contact__r.Email);
                result.put('contactPhone', acc.Primary_Contact__r.Phone != null ? acc.Primary_Contact__r.Phone : acc.Primary_Contact__r.MobilePhone);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving account primary contact: ' + e.getMessage());
        }
    }

    // Consolidated contact + phone resolver for a single round trip
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> resolvePrimaryContactForQueueItem(Id queueItemId) {
        Map<String, Object> result = new Map<String, Object>();
        if (queueItemId == null) {
            return result;
        }
        try {
            NBA_Queue__c qi = [
                SELECT Id,
                       Best_Person_to_Call__c,
                       Best_Person_to_Call__r.Name,
                       Best_Person_to_Call__r.Email,
                       Best_Person_to_Call__r.Phone,
                       Best_Person_to_Call__r.MobilePhone,
                       Best_Person_to_Call__r.OtherPhone,
                       Best_Person_to_Call__r.Secondary_Phone_Number__c,
                       Best_Number_to_Call__c,
                       Opportunity__c,
                       Opportunity__r.StageName,
                       Opportunity__r.Primary_Contact__c,
                       Opportunity__r.Primary_Contact__r.Name,
                       Opportunity__r.Primary_Contact__r.Email,
                       Opportunity__r.Primary_Contact__r.Phone,
                       Opportunity__r.Primary_Contact__r.MobilePhone,
                       Opportunity__r.Primary_Contact__r.OtherPhone,
                       Opportunity__r.Primary_Contact__r.Secondary_Phone_Number__c,
                       Account__c,
                       Account__r.Phone,
                       Account__r.Primary_Contact__c,
                       Account__r.Primary_Contact__r.Name,
                       Account__r.Primary_Contact__r.Email,
                       Account__r.Primary_Contact__r.Phone,
                       Account__r.Primary_Contact__r.MobilePhone,
                       Account__r.Primary_Contact__r.OtherPhone,
                       Account__r.Primary_Contact__r.Secondary_Phone_Number__c
                FROM NBA_Queue__c
                WHERE Id = :queueItemId
                LIMIT 1
            ];

            String stage = (qi.Opportunity__r != null) ? qi.Opportunity__r.StageName : null;
            Boolean isEarlyOppStage = (stage != null && (stage == 'New Opportunity' || stage == 'Attempted'));

            // Decide which person we should use and which phone to return
            Id contactId;
            String contactName;
            String contactEmail;
            String phone = null;
            String phoneSource = null;

            // 1) Opportunity present
            if (qi.Opportunity__c != null) {
                if (isEarlyOppStage && qi.Best_Person_to_Call__c != null) {
                    // Early stage: prefer NBA Best Person/Number when specified
                    contactId = qi.Best_Person_to_Call__c;
                    contactName = qi.Best_Person_to_Call__r != null ? qi.Best_Person_to_Call__r.Name : null;
                    contactEmail = qi.Best_Person_to_Call__r != null ? qi.Best_Person_to_Call__r.Email : null;
                    // Prefer explicit Best_Number_to_Call__c; fall back to person's phone
                    if (qi.Best_Number_to_Call__c != null) {
                        phone = normalizePhone(qi.Best_Number_to_Call__c);
                        phoneSource = 'NBA_Best_Number_to_Call__c';
                    }
                    if (phone == null && qi.Best_Person_to_Call__r != null) {
                        phone = normalizePhone(qi.Best_Person_to_Call__r.Phone != null ? qi.Best_Person_to_Call__r.Phone : qi.Best_Person_to_Call__r.MobilePhone);
                        phoneSource = 'NBA_Best_Person_to_Call__r';
                    }
                } else {
                    // Other stages: use Opportunity primary contact
                    contactId = qi.Opportunity__r != null ? qi.Opportunity__r.Primary_Contact__c : null;
                    contactName = (qi.Opportunity__r != null && qi.Opportunity__r.Primary_Contact__r != null) ? qi.Opportunity__r.Primary_Contact__r.Name : null;
                    contactEmail = (qi.Opportunity__r != null && qi.Opportunity__r.Primary_Contact__r != null) ? qi.Opportunity__r.Primary_Contact__r.Email : null;
                    if (qi.Opportunity__r != null && qi.Opportunity__r.Primary_Contact__r != null) {
                        phone = normalizePhone(qi.Opportunity__r.Primary_Contact__r.Phone != null ? qi.Opportunity__r.Primary_Contact__r.Phone : qi.Opportunity__r.Primary_Contact__r.MobilePhone);
                        phoneSource = 'Opportunity.Primary_Contact__r';
                    }
                }
            } else {
                // No opportunity: prefer NBA Best Person/Number if present
                if (qi.Best_Person_to_Call__c != null) {
                    contactId = qi.Best_Person_to_Call__c;
                    contactName = qi.Best_Person_to_Call__r != null ? qi.Best_Person_to_Call__r.Name : null;
                    contactEmail = qi.Best_Person_to_Call__r != null ? qi.Best_Person_to_Call__r.Email : null;
                    if (qi.Best_Number_to_Call__c != null) {
                        phone = normalizePhone(qi.Best_Number_to_Call__c);
                        phoneSource = 'NBA_Best_Number_to_Call__c';
                    }
                    if (phone == null && qi.Best_Person_to_Call__r != null) {
                        phone = normalizePhone(qi.Best_Person_to_Call__r.Phone != null ? qi.Best_Person_to_Call__r.Phone : qi.Best_Person_to_Call__r.MobilePhone);
                        phoneSource = 'NBA_Best_Person_to_Call__r';
                    }
                }
                // Fallback to Account primary contact
                if (contactId == null && qi.Account__r != null) {
                    contactId = qi.Account__r.Primary_Contact__c;
                    contactName = qi.Account__r.Primary_Contact__r != null ? qi.Account__r.Primary_Contact__r.Name : null;
                    contactEmail = qi.Account__r.Primary_Contact__r != null ? qi.Account__r.Primary_Contact__r.Email : null;
                    if (qi.Account__r.Primary_Contact__r != null) {
                        phone = normalizePhone(qi.Account__r.Primary_Contact__r.Phone != null ? qi.Account__r.Primary_Contact__r.Phone : qi.Account__r.Primary_Contact__r.MobilePhone);
                        phoneSource = 'Account.Primary_Contact__r';
                    }
                }
            }

            // Final fallback to Account.Phone if needed
            if (phone == null && qi.Account__r != null && qi.Account__r.Phone != null) {
                phone = normalizePhone(qi.Account__r.Phone);
                phoneSource = 'Account.Phone';
            }

            if (contactId != null) result.put('contactId', (String)contactId);
            if (contactName != null) result.put('contactName', contactName);
            if (contactEmail != null) result.put('contactEmail', contactEmail);
            if (phone != null) result.put('contactPhone', phone);
            if (phoneSource != null) result.put('phoneSource', phoneSource);

            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error resolving contact/phone: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Id getQueueBestPerson(Id queueItemId) {
        try {
            if (queueItemId == null) return null;
            NBA_Queue__c qi = [SELECT Best_Person_to_Call__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
            return qi != null ? qi.Best_Person_to_Call__c : null;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving Best Person to Call: ' + e.getMessage());
        }
    }

    // Helper: normalize raw phone to E.164 when possible (assumes US if 10 digits)
    private static String normalizePhone(String raw) {
        if (raw == null) return null;
        String digits = raw.replaceAll('[^0-9]', '');
        if (digits == null || digits == '') return null;
        if (digits.length() == 10) digits = '1' + digits;
        return '+' + digits;
    }

    @AuraEnabled
    public static void markOpportunityCallTimes(Id opportunityId) {
        if (opportunityId == null) return;
        try {
            Opportunity opp = [SELECT Id, First_Call_Date_Time__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
            Datetime nowTs = System.now();
            opp.Last_Call_Date_Time__c = nowTs;
            if (opp.First_Call_Date_Time__c == null) {
                opp.First_Call_Date_Time__c = nowTs;
            }
            update opp;
        } catch (Exception e) {
            // Swallow to avoid blocking the UI/dial in case of FLS or other issues
            System.debug('Error updating Opportunity call times: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void sendQueueEmail(Id queueItemId, String toAddress, String subject, String htmlBody) {
        if (queueItemId == null) {
            throw new AuraHandledException('Queue item id is required');
        }
        if (String.isBlank(toAddress)) {
            throw new AuraHandledException('To address is required');
        }
        try {
            NBA_Queue__c qi = [SELECT Id, Opportunity__c, Account__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ toAddress });
            mail.setSaveAsActivity(true);
            if (qi.Opportunity__c != null) {
                mail.setWhatId(qi.Opportunity__c);
            } else if (qi.Account__c != null) {
                mail.setWhatId(qi.Account__c);
            }
            mail.setSubject(subject == null ? '' : subject);
            if (!String.isBlank(htmlBody)) {
                mail.setHtmlBody(htmlBody);
            } else {
                mail.setPlainTextBody('');
            }
            Messaging.SendEmailResult[] r = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            // If send succeeds, move item to Accepted/Completed as needed
            if (r != null && r.size() > 0 && r[0].isSuccess()) {
                NBA_Queue__c forUpdate = [SELECT Id, Status__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
                forUpdate.Status__c = 'Accepted';
                update forUpdate;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error sending email: ' + e.getMessage());
        }
    }

    // Email template support for inline composer
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> listEmailTemplates(String searchText) {
        List<Map<String, String>> out = new List<Map<String, String>>();
        String likeExpr = (searchText == null || searchText.trim() == '') ? null : '%' + searchText.trim() + '%';
        List<EmailTemplate> temps = likeExpr == null ?
            [SELECT Id, Name FROM EmailTemplate WHERE IsActive = true ORDER BY Name LIMIT 200] :
            [SELECT Id, Name FROM EmailTemplate WHERE IsActive = true AND Name LIKE :likeExpr ORDER BY Name LIMIT 200];
        for (EmailTemplate t : temps) {
            Map<String, String> row = new Map<String, String>();
            row.put('id', (String)t.Id);
            row.put('name', t.Name);
            out.add(row);
        }
        return out;
    }

    // Helper: ensure text fits in a field by trimming from the start (keeps most recent notes)
    @TestVisible private static String truncateFromStart(String input, Integer maxLen) {
        if (input == null) return null;
        if (maxLen == null || maxLen <= 0) return input;
        if (input.length() <= maxLen) return input;
        return input.substring(input.length() - maxLen);
    }

    // Note: We intentionally avoid server-side render calls to keep compatibility; we send using setTemplateId instead

    @AuraEnabled
    public static void sendQueueEmailWithTemplate(Id queueItemId, Id templateId, Id whoId, Id whatId, String subjectOverride) {
        if (queueItemId == null) throw new AuraHandledException('Queue item id is required');
        if (templateId == null) throw new AuraHandledException('Template id is required');
        if (whoId == null) throw new AuraHandledException('A Contact or Lead (whoId) is required to use a template');
        try {
            NBA_Queue__c qi = [SELECT Id FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTemplateId(templateId);
            mail.setTargetObjectId(whoId);
            if (whatId != null) mail.setWhatId(whatId);
            mail.setSaveAsActivity(true);
            if (subjectOverride != null) mail.setSubject(subjectOverride);
            Messaging.SendEmailResult[] r = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            if (r != null && r.size() > 0 && r[0].isSuccess()) {
                NBA_Queue__c forUpdate = new NBA_Queue__c(Id = queueItemId, Status__c = 'Accepted');
                update forUpdate;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error sending templated email: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void updateQueueItem(Id queueItemId, String bestPersonToCall, String bestNumberToCall, String personCalled, String numberDialed) {
        try {
            System.debug('=== updateQueueItem Apex Debug ===');
            System.debug('queueItemId: ' + queueItemId);
            System.debug('bestPersonToCall: ' + bestPersonToCall);
            System.debug('bestNumberToCall: ' + bestNumberToCall);
            System.debug('personCalled: ' + personCalled);
            System.debug('numberDialed: ' + numberDialed);
            
            NBA_Queue__c queueItem = new NBA_Queue__c(Id = queueItemId);
            
            // Only update Best fields if they are provided (not null)
            if (bestPersonToCall != null && String.isNotBlank(bestPersonToCall)) {
                queueItem.Best_Person_to_Call__c = bestPersonToCall;
                System.debug('Setting Best_Person_to_Call__c to: ' + bestPersonToCall);
            }
            if (bestNumberToCall != null && String.isNotBlank(bestNumberToCall)) {
                queueItem.Best_Number_to_Call__c = bestNumberToCall;
                System.debug('Setting Best_Number_to_Call__c to: ' + bestNumberToCall);
            }
            if (String.isNotBlank(personCalled)) {
                queueItem.Person_Called__c = personCalled;
                System.debug('Setting Person_Called__c to: ' + personCalled);
            }
            if (String.isNotBlank(numberDialed)) {
                queueItem.Number_Dialed__c = numberDialed;
                System.debug('Setting Number_Dialed__c to: ' + numberDialed);
            }
            
            update queueItem;
            System.debug('Queue item updated successfully: ' + queueItemId);
        } catch (Exception e) {
            System.debug('Error updating queue item: ' + e.getMessage());
            throw new AuraHandledException('Error updating queue item: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String acceptAction(Id queueItemId, String additionalNotes) {
        try {
            System.debug('=== acceptAction Debug ===');
            System.debug('Queue Item ID: ' + queueItemId);
            System.debug('Additional Notes: ' + additionalNotes);
            
            NBA_Queue__c queueItem = [SELECT Id, Account__c, Account__r.Payroll_Status__c, Account__r.Last_Web_Usage_Timestamp__c,
                                             Subject__c, Description__c, Due_Date__c, Action_Type__c,
                                             Priority_Score__c, Sales_Rep__c, Opportunity__c, Lead__c, Best_Time_to_Call__c, Best_Number_to_Call__c, Person_Called__c, Number_Dialed__c
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
                    LIMIT 1
                ];
                if (!opportunities.isEmpty() && opportunities[0].Primary_Contact__c != null) {
                    whoId = opportunities[0].Primary_Contact__c;
                    System.debug('Primary Contact found: ' + whoId);
                } else {
                    System.debug('No primary contact found for opportunity: ' + queueItem.Opportunity__c);
                }
            } else if (queueItem.Lead__c != null) {
                whoId = queueItem.Lead__c;
                System.debug('Lead WhoId set: ' + whoId);
            }
            
            // Use Sales_Rep__c directly
            Id taskOwnerId = queueItem.Sales_Rep__c;
            
            // Determine dialed number (normalize to E.164 when possible)
            String dialed = null;
            try {
                // 1) Prefer explicit Best_Number_to_Call__c when present
                if (queueItem.Best_Number_to_Call__c != null) {
                    String digits = queueItem.Best_Number_to_Call__c.replaceAll('[^0-9]', '');
                    if (digits != null && digits != '') {
                        if (digits.length() == 10) digits = '1' + digits; // assume US default
                        dialed = '+' + digits;
                    }
                }
                // 2) Fallback to Opportunity Primary Contact phone
                if (dialed == null && queueItem.Opportunity__c != null) {
                    Opportunity o = [SELECT Primary_Contact__r.Phone, Primary_Contact__r.MobilePhone FROM Opportunity WHERE Id = :queueItem.Opportunity__c LIMIT 1];
                    String raw = (o.Primary_Contact__r != null && o.Primary_Contact__r.Phone != null) ? o.Primary_Contact__r.Phone : (o.Primary_Contact__r != null ? o.Primary_Contact__r.MobilePhone : null);
                    if (raw != null) {
                        String digits = raw.replaceAll('[^0-9]', '');
                        if (digits != null && digits != '') {
                            if (digits.length() == 10) digits = '1' + digits;
                            dialed = '+' + digits;
                        }
                    }
                }
                // 2b) Fallback to Lead phone when present
                if (dialed == null && queueItem.Lead__c != null) {
                    Lead l = [SELECT Phone, MobilePhone FROM Lead WHERE Id = :queueItem.Lead__c LIMIT 1];
                    String rawLead = (l.Phone != null) ? l.Phone : l.MobilePhone;
                    if (rawLead != null) {
                        String d2 = rawLead.replaceAll('[^0-9]', '');
                        if (d2 != null && d2 != '') {
                            if (d2.length() == 10) d2 = '1' + d2;
                            dialed = '+' + d2;
                        }
                    }
                }
                // 3) Fallback to Account Primary Contact or Account phone
                if (dialed == null && queueItem.Account__c != null) {
                    Account a = [SELECT Primary_Contact__r.Phone, Primary_Contact__r.MobilePhone, Phone FROM Account WHERE Id = :queueItem.Account__c LIMIT 1];
                    String raw = (a.Primary_Contact__r != null && a.Primary_Contact__r.Phone != null) ? a.Primary_Contact__r.Phone : (a.Primary_Contact__r != null && a.Primary_Contact__r.MobilePhone != null ? a.Primary_Contact__r.MobilePhone : a.Phone);
                    if (raw != null) {
                        String digits = raw.replaceAll('[^0-9]', '');
                        if (digits != null && digits != '') {
                            if (digits.length() == 10) digits = '1' + digits;
                            dialed = '+' + digits;
                        }
                    }
                }
                // Best-effort pre-insert stamp of dialed number (non-blocking)
                // Only update if Number_Dialed__c is not already set by user selection
                try {
                    if (dialed != null && String.isBlank(queueItem.Number_Dialed__c)) {
                        System.debug('Setting Number_Dialed__c from extracted phone: ' + dialed);
                        update new NBA_Queue__c(Id = queueItem.Id, Number_Dialed__c = dialed);
                    } else if (String.isNotBlank(queueItem.Number_Dialed__c)) {
                        System.debug('Number_Dialed__c already set by user selection: ' + queueItem.Number_Dialed__c + ', skipping overwrite');
                    }
                } catch (Exception ePre) {
                    System.debug('Pre-insert dialed update skipped: ' + ePre.getMessage());
                }
            } catch (Exception e) {}

            // Task creation moved to saveCallDisposition method
            // Task will be created only when call disposition is saved (status = 'Accepted')
            
            // Non-blocking: best-effort stamp dialed number after Task insert
            // Only update if Number_Dialed__c is not already set by user selection
            try {
                if (dialed != null && String.isBlank(queueItem.Number_Dialed__c)) {
                    System.debug('Setting Number_Dialed__c from extracted phone (post-insert): ' + dialed);
                    update new NBA_Queue__c(Id = queueItem.Id, Number_Dialed__c = dialed);
                } else if (String.isNotBlank(queueItem.Number_Dialed__c)) {
                    System.debug('Number_Dialed__c already set by user selection (post-insert): ' + queueItem.Number_Dialed__c + ', skipping overwrite');
                }
            } catch (Exception e2) {
                System.debug('Dialed number update failed (non-blocking): ' + e2.getMessage());
            }
            
            // Update queue item status and actioned date
            queueItem.Status__c = 'In Progress';
            queueItem.Actioned_Date__c = System.now();
            update queueItem;
            System.debug('Queue item updated successfully');
            
            // Publish platform event for real-time updates
            // Event publishing removed
            
            // Task will be created when call disposition is saved
            return 'Task will be created on disposition save';
            
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
        queueItem.Completed_Date__c = System.now(); // Set completed date when dismissed
        update queueItem;
        
        // Publish platform event for real-time updates
        // Event publishing removed
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
    public static void cancelCallDisposition(Id queueItemId) {
        // Revert the NBA Queue record status back to "Pending" when disposition is cancelled
        NBA_Queue__c queueItem = [SELECT Id, Status__c, Sales_Rep__c, Completed_Date__c, Actioned_Date__c FROM NBA_Queue__c WHERE Id = :queueItemId];
        queueItem.Status__c = 'Pending';
        queueItem.Completed_Date__c = null; // Clear completed date when reverting to pending
        queueItem.Actioned_Date__c = null; // Clear actioned date when reverting to pending
        update queueItem;
        
        // Publish platform event for real-time updates
        // Event publishing removed
    }
    
    @AuraEnabled
    public static void updateCallDispositionWithQueueId(Id queueItemId, String disposition, String callNotes) {
        // Get the queue item details for task creation
        NBA_Queue__c queueItem = [SELECT Id, Account__c, Account__r.Payroll_Status__c, Account__r.Last_Web_Usage_Timestamp__c,
                                         Subject__c, Description__c, Due_Date__c, Action_Type__c,
                                         Priority_Score__c, Sales_Rep__c, Opportunity__c, Lead__c, Best_Time_to_Call__c, Best_Number_to_Call__c, Person_Called__c
                                  FROM NBA_Queue__c 
                                  WHERE Id = :queueItemId];
        
        // Get primary contact from Opportunity
        Id whoId = null;
        if (queueItem.Opportunity__c != null) {
            List<Opportunity> opportunities = [
                SELECT Primary_Contact__c 
                FROM Opportunity 
                WHERE Id = :queueItem.Opportunity__c
                LIMIT 1
            ];
            if (!opportunities.isEmpty() && opportunities[0].Primary_Contact__c != null) {
                whoId = opportunities[0].Primary_Contact__c;
            }
        } else if (queueItem.Lead__c != null) {
            whoId = queueItem.Lead__c;
        }
        
        // Use Sales_Rep__c directly
        Id taskOwnerId = queueItem.Sales_Rep__c;
        
        // Build task description with disposition and notes
        String taskDescription = buildTaskDescription(queueItem, '');
        if (String.isNotBlank(disposition)) {
            taskDescription += '\n\nCall Disposition: ' + disposition;
        }
        if (String.isNotBlank(callNotes)) {
            taskDescription += '\n\nCall Notes: ' + callNotes;
        }
        
        // Create new Task
        Task newTask = new Task(
            Subject = 'Next Best Action: ' + queueItem.Action_Type__c,
            Description = taskDescription,
            WhatId = (whoId == null) ? (queueItem.Opportunity__c != null ? queueItem.Opportunity__c : queueItem.Account__c) : (queueItem.Lead__c != null ? null : (queueItem.Opportunity__c != null ? queueItem.Opportunity__c : queueItem.Account__c)),
            WhoId = whoId,
            OwnerId = taskOwnerId,
            ActivityDate = Date.today(),
            Status = 'Completed',  // Mark as completed when disposition is saved
            Priority = mapPriorityToTask(queueItem.Priority_Score__c),
            CallDisposition = disposition
        );
        
        insert newTask;
        System.debug('Task created successfully: ' + newTask.Id);
        
        // Get additional fields needed for queue item update
        NBA_Queue__c queueItemForUpdate = [SELECT Id, Rep_Notes__c, Call_Disposition__c, Status__c, Completed_Date__c, Opportunity__c, Lead__c,
                                                 Priority_Score__c, Account__c, Account__r.Payroll_Status__c, Account__r.Last_Web_Usage_Timestamp__c, Account__r.Last_Progression_Time__c, 
                                                  Best_Time_to_Call__c, Next_Step_Date__c, Next_Steps__c
                                          FROM NBA_Queue__c WHERE Id = :queueItemId];
        
        // Update Rep_Notes__c with call notes
        if (String.isNotBlank(callNotes)) {
            String existingNotes = queueItemForUpdate.Rep_Notes__c != null ? queueItemForUpdate.Rep_Notes__c : '';
            String combined = existingNotes + '\n\nCall Notes: ' + callNotes;
            queueItemForUpdate.Rep_Notes__c = truncateFromStart(combined, 32768);
        }
        
        // Update Call_Disposition__c with disposition
        if (String.isNotBlank(disposition)) {
            queueItemForUpdate.Call_Disposition__c = disposition;
        }
        
        // Calculate priority score details to set multiplier indicator when action is completed
        Map<String, Object> scoreDetails = calculateAdjustedPriorityScoreWithDetails(queueItemForUpdate);
        String multiplierDescription = (String) scoreDetails.get('multiplierDescription');
        
        // Update status to "Accepted", set completed date, and set multiplier indicator when disposition is saved
        queueItemForUpdate.Status__c = 'Accepted';
        queueItemForUpdate.Completed_Date__c = System.now();
        queueItemForUpdate.Priority_Multiplier_Applied__c = multiplierDescription;
        
        update queueItemForUpdate;
        System.debug('Queue item completed with multiplier: ' + multiplierDescription);
        
        // Update related Opportunity fields upon acceptance (Last/First Call timestamps and Description)
        if (queueItemForUpdate.Opportunity__c != null) {
            try {
                Opportunity opp = [SELECT Id, Description, First_Call_Date_Time__c, Last_Call_Date_Time__c FROM Opportunity WHERE Id = :queueItemForUpdate.Opportunity__c];
                // Stamp Last Call now; seed First Call once
                Datetime nowTs = System.now();
                opp.Last_Call_Date_Time__c = nowTs;
                if (opp.First_Call_Date_Time__c == null) {
                    opp.First_Call_Date_Time__c = nowTs;
                }
                // Prepend newest call notes (if provided) to Description
                if (String.isNotBlank(callNotes)) {
                    String currentDescription = opp.Description != null ? opp.Description : '';
                    String timestamp = DateTime.now().format('MM/dd/yyyy HH:mm:ss');
                    String newCallNotes = '--- Call Notes (' + timestamp + ') ---\n' + callNotes;
                    opp.Description = String.isBlank(currentDescription)
                        ? newCallNotes
                        : newCallNotes + '\n\n' + currentDescription;
                }
                update opp;
            } catch (Exception e) {
                System.debug('Error updating Opportunity on acceptance: ' + e.getMessage());
            }
        } else if (queueItemForUpdate.Lead__c != null) {
            try {
                Lead l = [SELECT Id, Description FROM Lead WHERE Id = :queueItemForUpdate.Lead__c LIMIT 1];
                if (String.isNotBlank(callNotes)) {
                    String currentDescription = l.Description != null ? l.Description : '';
                    String timestamp = DateTime.now().format('MM/dd/yyyy HH:mm:ss');
                    String newCallNotes = '--- Call Notes (' + timestamp + ') ---\n' + callNotes;
                    l.Description = String.isBlank(currentDescription) ? newCallNotes : newCallNotes + '\n\n' + currentDescription;
                }
                update l;
            } catch (Exception e) {
                System.debug('Error updating Lead on acceptance: ' + e.getMessage());
            }
        }
    }

    // New: Update call disposition with option to finalize the NBA Queue item later (two-phase submit)
    @AuraEnabled
    public static void updateCallDispositionWithQueueIdOptions(Id queueItemId, String disposition, String callNotes, Boolean finalize) {
        // Get the queue item details for task creation
        NBA_Queue__c queueItem = [SELECT Id, Account__c, Account__r.Payroll_Status__c, Account__r.Last_Web_Usage_Timestamp__c,
                                         Subject__c, Description__c, Due_Date__c, Action_Type__c,
                                         Priority_Score__c, Sales_Rep__c, Opportunity__c, Lead__c, Best_Time_to_Call__c, Best_Number_to_Call__c, Person_Called__c
                                  FROM NBA_Queue__c 
                                  WHERE Id = :queueItemId];
        
        // Get primary contact from Opportunity
        Id whoId = null;
        if (queueItem.Opportunity__c != null) {
            List<Opportunity> opportunities = [
                SELECT Primary_Contact__c 
                FROM Opportunity 
                WHERE Id = :queueItem.Opportunity__c
                LIMIT 1
            ];
            if (!opportunities.isEmpty() && opportunities[0].Primary_Contact__c != null) {
                whoId = opportunities[0].Primary_Contact__c;
            }
        } else if (queueItem.Lead__c != null) {
            whoId = queueItem.Lead__c;
        }
        
        // Use Sales_Rep__c directly
        Id taskOwnerId = queueItem.Sales_Rep__c;
        
        // Build task description with disposition and notes
        String taskDescription = buildTaskDescription(queueItem, '');
        if (String.isNotBlank(disposition)) {
            taskDescription += '\n\nCall Disposition: ' + disposition;
        }
        if (String.isNotBlank(callNotes)) {
            taskDescription += '\n\nCall Notes: ' + callNotes;
        }
        
        // Create new Task
        Task newTask = new Task(
            Subject = 'Next Best Action: ' + queueItem.Action_Type__c,
            Description = taskDescription,
            WhatId = (whoId == null) ? (queueItem.Opportunity__c != null ? queueItem.Opportunity__c : queueItem.Account__c) : (queueItem.Lead__c != null ? null : (queueItem.Opportunity__c != null ? queueItem.Opportunity__c : queueItem.Account__c)),
            WhoId = whoId,
            OwnerId = taskOwnerId,
            ActivityDate = Date.today(),
            Status = 'Completed',  // Mark as completed when disposition is saved
            Priority = mapPriorityToTask(queueItem.Priority_Score__c),
            CallDisposition = disposition
        );
        
        insert newTask;
        System.debug('Task created successfully: ' + newTask.Id);

        // Get additional fields needed for queue item update
        NBA_Queue__c queueItemForUpdate = [SELECT Id, Rep_Notes__c, Call_Disposition__c, Status__c, Completed_Date__c, Opportunity__c, Lead__c,
                                                 Priority_Score__c, Account__c, Account__r.Payroll_Status__c, Account__r.Last_Web_Usage_Timestamp__c, Account__r.Last_Progression_Time__c, 
                                                  Best_Time_to_Call__c, Next_Step_Date__c, Next_Steps__c
                                          FROM NBA_Queue__c WHERE Id = :queueItemId];

        if (String.isNotBlank(callNotes)) {
            String existingNotes = queueItemForUpdate.Rep_Notes__c != null ? queueItemForUpdate.Rep_Notes__c : '';
            String combined = existingNotes + '\n\nCall Notes: ' + callNotes;
            queueItemForUpdate.Rep_Notes__c = truncateFromStart(combined, 32768);
        }
        if (String.isNotBlank(disposition)) {
            queueItemForUpdate.Call_Disposition__c = disposition;
        }

        // Calculate multiplier description for when we later finalize
        Map<String, Object> scoreDetails = calculateAdjustedPriorityScoreWithDetails(queueItemForUpdate);
        String multiplierDescription = (String) scoreDetails.get('multiplierDescription');

        // If finalize requested, mark Accepted/Completed; else leave In Progress
        if (finalize == true) {
            queueItemForUpdate.Status__c = 'Accepted';
            queueItemForUpdate.Completed_Date__c = System.now();
            queueItemForUpdate.Priority_Multiplier_Applied__c = multiplierDescription;
        }
        update queueItemForUpdate;

        // Update related Opportunity fields upon acceptance only when finalizing
        if (finalize == true && queueItemForUpdate.Opportunity__c != null) {
            try {
                Opportunity opp = [SELECT Id, Description, First_Call_Date_Time__c, Last_Call_Date_Time__c FROM Opportunity WHERE Id = :queueItemForUpdate.Opportunity__c];
                Datetime nowTs = System.now();
                opp.Last_Call_Date_Time__c = nowTs;
                if (opp.First_Call_Date_Time__c == null) {
                    opp.First_Call_Date_Time__c = nowTs;
                }
                if (String.isNotBlank(callNotes)) {
                    String currentDescription = opp.Description != null ? opp.Description : '';
                    String timestamp = DateTime.now().format('MM/dd/yyyy HH:mm:ss');
                    String newCallNotes = '--- Call Notes (' + timestamp + ') ---\n' + callNotes;
                    opp.Description = String.isBlank(currentDescription)
                        ? newCallNotes
                        : newCallNotes + '\n\n' + currentDescription;
                }
                update opp;
            } catch (Exception e) {
                System.debug('Error updating Opportunity on acceptance (options): ' + e.getMessage());
            }
        } else if (finalize == true && queueItemForUpdate.Lead__c != null) {
            try {
                Lead l = [SELECT Id, Description FROM Lead WHERE Id = :queueItemForUpdate.Lead__c LIMIT 1];
                if (String.isNotBlank(callNotes)) {
                    String currentDescription = l.Description != null ? l.Description : '';
                    String timestamp = DateTime.now().format('MM/dd/yyyy HH:mm:ss');
                    String newCallNotes = '--- Call Notes (' + timestamp + ') ---\n' + callNotes;
                    l.Description = String.isBlank(currentDescription) ? newCallNotes : newCallNotes + '\n\n' + currentDescription;
                }
                update l;
            } catch (Exception e) {
                System.debug('Error updating Lead on acceptance (options): ' + e.getMessage());
            }
        }
    }

    // New: Finalize an NBA Queue item (mark Accepted and stamp Completed_Date__c)
    @AuraEnabled
    public static void finalizeQueueItem(Id queueItemId) {
        if (queueItemId == null) return;
        NBA_Queue__c qi = [SELECT Id, Status__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
        qi.Status__c = 'Accepted';
        qi.Completed_Date__c = System.now();
        update qi;
    }

    @AuraEnabled
    public static void saveNextStepsWithLead(Id queueItemId, Date nextStepDate, String nextSteps, String newOpportunityStage, String newLeadStatus) {
        // Update NBA Queue and related Opportunity with next steps and stage
        NBA_Queue__c queueItem = [SELECT Id, Opportunity__c, Lead__c FROM NBA_Queue__c WHERE Id = :queueItemId];

        if (nextStepDate != null) {
            queueItem.Next_Step_Date__c = nextStepDate;
        }
        if (String.isNotBlank(nextSteps)) {
            queueItem.Next_Steps__c = nextSteps;
        }
        update queueItem;

        if (queueItem.Opportunity__c != null) {
            Opportunity opp = [SELECT Id, NextStep, StageName FROM Opportunity WHERE Id = :queueItem.Opportunity__c];
            // Conditionally set custom date field if it exists in the org
            try {
                if (nextStepDate != null) {
                    Map<String, Schema.SObjectField> fmap = Schema.getGlobalDescribe().get('Opportunity').getDescribe().fields.getMap();
                    if (fmap.containsKey('Next_Step_Date__c')) {
                        opp.put('Next_Step_Date__c', nextStepDate);
                    }
                }
            } catch (Exception e) {}
            if (String.isNotBlank(nextSteps)) {
                opp.NextStep = nextSteps;
            }
            if (String.isNotBlank(newOpportunityStage)) {
                opp.StageName = newOpportunityStage;
            }
            update opp;
        } else {
            // Lead path
            try {
                Id leadId = (Id) queueItem.get('Lead__c');
                if (leadId != null) {
                    Lead l = [SELECT Id, Status FROM Lead WHERE Id = :leadId LIMIT 1];
                    // Apply Next Step fields if present
                    try {
                        Map<String, Schema.SObjectField> fmap = Schema.getGlobalDescribe().get('Lead').getDescribe().fields.getMap();
                        if (nextStepDate != null && fmap.containsKey('Next_Step_Date__c')) l.put('Next_Step_Date__c', nextStepDate);
                        if (String.isNotBlank(nextSteps) && fmap.containsKey('Next_Step__c')) l.put('Next_Step__c', nextSteps);
                    } catch (Exception e2) {}
                    if (String.isNotBlank(newLeadStatus)) l.Status = newLeadStatus;
                    update l;
                }
            } catch (Exception e) {}
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getOpportunityStageNames() {
        Schema.DescribeFieldResult dfr = Opportunity.StageName.getDescribe();
        List<String> stages = new List<String>();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) {
                // Return the picklist values (not labels) so they match Opportunity.StageName
                stages.add(pe.getValue());
            }
        }
        return stages;
    }
    
    @AuraEnabled
    public static void snoozeQueueItem(Id queueItemId, String category, Datetime scheduledDateTime, Integer snoozeHours) {
        if (queueItemId == null || String.isBlank(category)) {
            throw new AuraHandledException('Missing required snooze inputs');
        }
        NBA_Queue__c item = [SELECT Id, Status__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
        Datetime snoozeUntil;
        if (category == 'Call Scheduled' && scheduledDateTime != null) {
            snoozeUntil = scheduledDateTime.addMinutes(-15);
        } else if (category == 'Time Zone' && snoozeHours != null) {
            snoozeUntil = System.now().addHours(snoozeHours);
        }
        if (snoozeUntil == null) {
            throw new AuraHandledException('Invalid snooze parameters');
        }
        item.Status__c = 'Snoozed';
        item.Snoozed_Until__c = snoozeUntil;
        update item;
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

    // Return a human-readable reason why an item should be skipped; null if eligible
    @TestVisible private static String getSkipReason(NBA_Queue__c item, Set<Id> blockedOppIds) {
        // 1) Hard blocks: these always exclude, even if the item is In Progress
        if (item.Opportunity__c != null && item.Opportunity__r != null && item.Opportunity__r.StageName != null) {
            String stage = item.Opportunity__r.StageName.toLowerCase();
            if (stage == 'closed won - pending implementation' || 
                stage == 'closed lost' || 
                stage == 'ran payroll') {
                System.debug('Skipping item due to Opportunity stage (hard block): ' + item.Opportunity__r.StageName);
                return 'Opportunity stage is ' + item.Opportunity__r.StageName;
            }
        }

        // 2) Allow In Progress items to bypass the remaining (soft) exclusions so reps can complete work
        if (item.Status__c == 'In Progress') {
            System.debug('Item is In Progress - bypassing soft exclusions to allow completion');
            return null;
        }
        
        // 3) Check if this is a call-based action (soft blocks only apply to calls)
        Boolean isCallAction = item.Action_Type__c != null && 
                              (item.Action_Type__c.toLowerCase().contains('call') || 
                               item.Action_Type__c.toLowerCase().contains('payroll'));
        
        // 4) Soft blocks only apply to call-based actions
        if (isCallAction) {
            // Skip if Opportunity Last_Call_Date_Time__c is within the last 48 hours
            if (item.Opportunity__c != null && item.Opportunity__r != null && item.Opportunity__r.Last_Call_Date_Time__c != null) {
                DateTime lastCallTime = item.Opportunity__r.Last_Call_Date_Time__c;
                DateTime fortyEightHoursAgo = DateTime.now().addHours(-48);
                
                if (lastCallTime >= fortyEightHoursAgo) {
                    System.debug('Skipping call item due to last call being within 48 hours: ' + lastCallTime);
                    return 'Already called within 48 hours';
                }
            }
            
            // Skip if Opportunity Future_Follow_Up_Date__c is in the future
            if (item.Opportunity__c != null && item.Opportunity__r != null && item.Opportunity__r.Future_Follow_Up_Date__c != null) {
                Date futureFollowUpDate = item.Opportunity__r.Future_Follow_Up_Date__c;
                Date today = Date.today();
                
                if (futureFollowUpDate > today) {
                    System.debug('Skipping call item due to future follow-up date: ' + futureFollowUpDate);
                    return 'Future follow-up date is set to ' + String.valueOf(futureFollowUpDate);
                }
            }
            
            // Skip if Opportunity Next_Step_Date__c is in the future
            if (item.Opportunity__c != null && item.Opportunity__r != null && item.Opportunity__r.Next_Step_Date__c != null) {
                Date nextStepDate = item.Opportunity__r.Next_Step_Date__c;
                Date today = Date.today();
                
                if (nextStepDate > today) {
                    System.debug('Skipping call item due to future next step date: ' + nextStepDate);
                    return 'Next step date is set to ' + String.valueOf(nextStepDate);
                }
            }
            
            // Skip if this opportunity has a future Event beyond the 15-minute window
            if (item.Opportunity__c != null && blockedOppIds != null && blockedOppIds.contains(item.Opportunity__c)) {
                System.debug('Skipping call item due to future scheduled Event > 15 minutes for Opp: ' + item.Opportunity__c);
                return 'Future meeting scheduled (>15 minutes)';
            }
            
            // Skip if Account Payroll_Status__c contains specific values
            if (item.Account__r != null && item.Account__r.Payroll_Status__c != null) {
                String payrollStatus = item.Account__r.Payroll_Status__c.toLowerCase();
                if (payrollStatus == 'pending' || 
                    payrollStatus == 'processing' || 
                    payrollStatus == 'paid') {
                    System.debug('Skipping call item due to payroll status: ' + item.Account__r.Payroll_Status__c);
                    return 'Account is in payroll status: ' + item.Account__r.Payroll_Status__c;
                }
            }
        }
        
        return null;
    }

    // Helper: get Opportunity IDs that have an Event starting later than now + 15 minutes
    @TestVisible private static Set<Id> getOpportunitiesBlockedByFutureEvents(Set<Id> opportunityIds) {
        Set<Id> blocked = new Set<Id>();
        if (opportunityIds == null || opportunityIds.isEmpty()) return blocked;
        // Query Events in bulk; use grouping to keep it efficient
        for (AggregateResult ar : [
            SELECT WhatId wid, MIN(StartDateTime) minStart
            FROM Event
            WHERE WhatId IN :opportunityIds AND IsDeleted = false AND StartDateTime > :System.now()
            GROUP BY WhatId
        ]) {
            Id wid = (Id) ar.get('wid');
            Datetime minStart = (Datetime) ar.get('minStart');
            if (minStart != null && minStart > System.now().addMinutes(120)) {
                blocked.add(wid);
            }
        }
        return blocked;
    }



    // Helper method to calculate adjusted priority score and return details
    private static Map<String, Object> calculateAdjustedPriorityScoreWithDetails(NBA_Queue__c item) {
        // Get multiplier configuration from metadata
        NBA_Multiplier_Config__mdt config = getMultiplierConfig();
        
        Decimal adjustedScore = item.Priority_Score__c != null ? item.Priority_Score__c : 0;
        Boolean webUsageApplied = false;
        Boolean bestTimeApplied = false;
        Boolean progressionApplied = false;
        Decimal webUsageMultiplier = 1;
        Decimal bestTimeMultiplier = 1;
        Decimal progressionMultiplier = 1;

        // Check if Last_Web_Usage_Timestamp__c is within the configured hours OF TODAY
        if (item.Account__r.Last_Web_Usage_Timestamp__c != null) {
            DateTime webUsageTime = item.Account__r.Last_Web_Usage_Timestamp__c;
            DateTime today = DateTime.now().date();
            DateTime hoursAgo = DateTime.now().addHours(-Integer.valueOf(config.Web_Usage_Hours__c));
            
            // Only apply if web usage was today AND within the configured hours
            if (webUsageTime.date() == today && webUsageTime >= hoursAgo) {
                adjustedScore = adjustedScore * config.Web_Usage_Multiplier__c;
                webUsageApplied = true;
                webUsageMultiplier = config.Web_Usage_Multiplier__c;
                System.debug('Applied ' + config.Web_Usage_Multiplier__c + 'x multiplier for recent web usage today. Original: ' + item.Priority_Score__c + ', Adjusted: ' + adjustedScore);
            }
        }
        
        // Check if Best_Time_to_Call__c is within the configured time window
        if (item.Best_Time_to_Call__c != null) {
            Time bestTime = item.Best_Time_to_Call__c.time();
            DateTime now = DateTime.now();
            Time currentTime = Time.newInstance(now.hour(), now.minute(), now.second(), 0);
            
            // Convert to minutes for easier comparison
            Integer bestTimeMinutes = bestTime.hour() * 60 + bestTime.minute();
            Integer currentTimeMinutes = currentTime.hour() * 60 + currentTime.minute();
            
            // Check if best time is within the configured minutes tolerance
            Integer timeDifference = Math.abs(bestTimeMinutes - currentTimeMinutes);
            if (timeDifference <= Integer.valueOf(config.Best_Time_Minutes__c)) {
                adjustedScore = adjustedScore * config.Best_Time_Multiplier__c;
                bestTimeApplied = true;
                bestTimeMultiplier = config.Best_Time_Multiplier__c;
                System.debug('Applied ' + config.Best_Time_Multiplier__c + 'x multiplier for best time to call. Original: ' + item.Priority_Score__c + ', Adjusted: ' + adjustedScore);
            }
        }
        
        // Progression recency multiplier based on Account.Last_Progression_Time__c with configurable tiers
        String progressionDescription = '';
        if (item.Account__r != null && item.Account__r.Last_Progression_Time__c != null) {
            Datetime lastProg = item.Account__r.Last_Progression_Time__c;
            Datetime tier1DaysAgo = Datetime.now().addDays(-Integer.valueOf(config.Progression_Tier1_Days__c));
            Datetime tier2DaysAgo = Datetime.now().addDays(-Integer.valueOf(config.Progression_Tier2_Days__c));
            
            // Apply highest applicable tier (most recent progression gets highest multiplier)
            if (lastProg >= tier1DaysAgo) {
                adjustedScore = adjustedScore * config.Progression_Tier1_Multiplier__c;
                progressionApplied = true;
                progressionMultiplier = config.Progression_Tier1_Multiplier__c;
                progressionDescription = config.Progression_Tier1_Description__c;
                System.debug('Applied Tier 1 progression multiplier: ' + config.Progression_Tier1_Multiplier__c + 'x');
            } else if (lastProg >= tier2DaysAgo) {
                adjustedScore = adjustedScore * config.Progression_Tier2_Multiplier__c;
                progressionApplied = true;
                progressionMultiplier = config.Progression_Tier2_Multiplier__c;
                progressionDescription = config.Progression_Tier2_Description__c;
                System.debug('Applied Tier 2 progression multiplier: ' + config.Progression_Tier2_Multiplier__c + 'x');
            }
        }
        
        Map<String, Object> details = new Map<String, Object>();
        details.put('adjustedScore', adjustedScore);
        details.put('webUsageApplied', webUsageApplied);
        details.put('bestTimeApplied', bestTimeApplied);
        details.put('progressionApplied', progressionApplied);
        details.put('webUsageMultiplier', webUsageMultiplier);
        details.put('bestTimeMultiplier', bestTimeMultiplier);
        details.put('progressionMultiplier', progressionMultiplier);
        
        // Build multiplier description using dynamic descriptions from metadata
        List<String> appliedMultipliers = new List<String>();
        if (webUsageApplied) {
            appliedMultipliers.add(config.Web_Usage_Description__c);
        }
        if (bestTimeApplied) {
            appliedMultipliers.add(config.Best_Time_Description__c);
        }
        if (progressionApplied) {
            appliedMultipliers.add(progressionDescription);
        }
        String multiplierDescription = appliedMultipliers.isEmpty() ? 'None' : String.join(appliedMultipliers, ', ');
        details.put('multiplierDescription', multiplierDescription);
        
        return details;
    }
    
    // Helper method to get multiplier configuration from metadata
    private static NBA_Multiplier_Config__mdt getMultiplierConfig() {
        try {
            NBA_Multiplier_Config__mdt config = [
                SELECT Web_Usage_Multiplier__c, Web_Usage_Hours__c, Web_Usage_Description__c,
                       Best_Time_Multiplier__c, Best_Time_Minutes__c, Best_Time_Description__c,
                       Progression_Tier1_Multiplier__c, Progression_Tier1_Days__c, Progression_Tier1_Description__c,
                       Progression_Tier2_Multiplier__c, Progression_Tier2_Days__c, Progression_Tier2_Description__c
                FROM NBA_Multiplier_Config__mdt 
                WHERE Is_Active__c = true 
                LIMIT 1
            ];
            return config;
        } catch (QueryException e) {
            System.debug('No active multiplier configuration found, using defaults');
            // Return a default configuration if none is found
            return new NBA_Multiplier_Config__mdt(
                Web_Usage_Multiplier__c = 1.25,
                Web_Usage_Hours__c = 1,
                Web_Usage_Description__c = 'Web Usage (1.25x) - Last 1 hour',
                Best_Time_Multiplier__c = 1.2,
                Best_Time_Minutes__c = 30,
                Best_Time_Description__c = 'Best Time (1.2x) - ±30 minutes',
                Progression_Tier1_Multiplier__c = 1.5,
                Progression_Tier1_Days__c = 7,
                Progression_Tier1_Description__c = 'Progression (1.5x) - Last 7 days',
                Progression_Tier2_Multiplier__c = 1.2,
                Progression_Tier2_Days__c = 30,
                Progression_Tier2_Description__c = 'Progression (1.2x) - Last 30 days'
            );
        }
    }

    // Helper method to update last viewed date when item is served
    private static void updateItemLastViewedDate(NBA_Queue__c item) {
        try {
            // Query the record fresh to avoid DML issues
            NBA_Queue__c itemToUpdate = [SELECT Id, Last_Viewed_Date__c FROM NBA_Queue__c WHERE Id = :item.Id];
            itemToUpdate.Last_Viewed_Date__c = System.now();
            
            update itemToUpdate;
            System.debug('Updated last viewed date for item ' + item.Id + ': Last Viewed = ' + itemToUpdate.Last_Viewed_Date__c);
        } catch (Exception e) {
            System.debug('Error updating last viewed date: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getLeadStatusNames() {
        List<String> out = new List<String>();
        try {
            Schema.DescribeFieldResult dfr = Lead.Status.getDescribe();
            for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                if (pe.isActive()) out.add(pe.getValue());
            }
        } catch (Exception e) {}
        return out;
    }

    @AuraEnabled
    public static void saveNextSteps(Id queueItemId, Date nextStepDate, String nextSteps, String newOpportunityStage) {
        saveNextStepsWithLead(queueItemId, nextStepDate, nextSteps, newOpportunityStage, null);
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getAccountContacts(Id accountId) {
        List<Map<String, Object>> contacts = new List<Map<String, Object>>();
        
        if (accountId == null) {
            return contacts;
        }
        
        try {
            List<Contact> accountContacts = [
                SELECT Id, Name, Phone, MobilePhone, OtherPhone, Secondary_Phone_Number__c, Email, Title, Department
                FROM Contact 
                WHERE AccountId = :accountId 
                AND (Phone != null OR MobilePhone != null OR OtherPhone != null OR Secondary_Phone_Number__c != null)
                ORDER BY Name
                LIMIT 50
            ];
            
            for (Contact contact : accountContacts) {
                Map<String, Object> contactMap = new Map<String, Object>();
                contactMap.put('id', contact.Id);
                contactMap.put('name', contact.Name);
                contactMap.put('phone', contact.Phone);
                contactMap.put('mobilePhone', contact.MobilePhone);
                contactMap.put('otherPhone', contact.OtherPhone);
                contactMap.put('secondaryPhone', contact.Secondary_Phone_Number__c);
                contactMap.put('email', contact.Email);
                contactMap.put('title', contact.Title);
                contactMap.put('department', contact.Department);
                contacts.add(contactMap);
            }
        } catch (Exception e) {
            System.debug('Error fetching account contacts: ' + e.getMessage());
        }
        
        return contacts;
    }

    // Helper method to check if an item is an urgent event (within 7 minutes)
    private static Boolean isUrgentEvent(NBA_Queue__c item) {
        if (item.Action_Type__c != 'Event' || item.Start_Time__c == null) {
            return false;
        }
        
        DateTime now = System.now();
        DateTime eventTime = item.Start_Time__c;
        Long minutesDifference = (eventTime.getTime() - now.getTime()) / (1000 * 60);
        
        // Event is urgent if it's starting within 7 minutes
        return minutesDifference >= 0 && minutesDifference <= 7;
    }

    @AuraEnabled
    public static Map<String, Object> handleEmailAccept(Id queueItemId) {
        try {
            // Update the queue item status to In Progress
            NBA_Queue__c queueItem = new NBA_Queue__c(
                Id = queueItemId,
                Status__c = 'In Progress',
                First_Viewed_Date__c = System.now()
            );
            update queueItem;
            
            // Get the related opportunity and email message for navigation
            NBA_Queue__c updatedItem = [SELECT Id, Opportunity__c, Email_Message_Id__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
            
            Map<String, Object> result = new Map<String, Object>();
            result.put('success', true);
            result.put('opportunityId', updatedItem.Opportunity__c);
            result.put('actionType', 'Email');
            result.put('emailMessageId', updatedItem.Email_Message_Id__c);
            
            System.debug('Email action accepted for queue item: ' + queueItemId);
            return result;
        } catch (Exception e) {
            System.debug('Error accepting email action: ' + e.getMessage());
            throw new AuraHandledException('Error accepting email action: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> handleEventAccept(Id queueItemId) {
        try {
            // Update the queue item status to In Progress
            NBA_Queue__c queueItem = new NBA_Queue__c(
                Id = queueItemId,
                Status__c = 'In Progress',
                First_Viewed_Date__c = System.now()
            );
            update queueItem;
            
            // Get the related opportunity and event for navigation
            NBA_Queue__c updatedItem = [SELECT Id, Opportunity__c, Start_Time__c, Event_Id__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
            
            Map<String, Object> result = new Map<String, Object>();
            result.put('success', true);
            result.put('opportunityId', updatedItem.Opportunity__c);
            result.put('actionType', 'Event');
            result.put('startTime', updatedItem.Start_Time__c);
            result.put('eventId', updatedItem.Event_Id__c);
            
            System.debug('Event action accepted for queue item: ' + queueItemId);
            return result;
        } catch (Exception e) {
            System.debug('Error accepting event action: ' + e.getMessage());
            throw new AuraHandledException('Error accepting event action: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveMeetingDisposition(Id queueItemId, String meetingDisposition, String meetingNotes) {
        try {
            // Get current Rep_Notes__c to append meeting notes
            NBA_Queue__c existingItem = [SELECT Id, Rep_Notes__c, Opportunity__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
            
            String updatedRepNotes = existingItem.Rep_Notes__c != null ? existingItem.Rep_Notes__c : '';
            
            // Add meeting notes to Rep_Notes__c with date and disposition
            if (String.isNotBlank(meetingNotes)) {
                String meetingEntry = '\n\nMeeting Notes (' + System.now().format('MM/dd/yyyy HH:mm') + '):\n';
                meetingEntry += 'Disposition: ' + meetingDisposition + '\n';
                meetingEntry += 'Notes: ' + meetingNotes;
                updatedRepNotes += meetingEntry;
            }
            
            NBA_Queue__c queueItem = new NBA_Queue__c(
                Id = queueItemId,
                Meeting_Disposition__c = meetingDisposition,
                Rep_Notes__c = truncateFromStart(updatedRepNotes, 32768),
                Status__c = 'Accepted',
                Actioned_Date__c = System.now()
            );
            update queueItem;
            
            // If there's a related opportunity, update it with meeting notes (same format as call notes)
            if (existingItem.Opportunity__c != null && String.isNotBlank(meetingNotes)) {
                Opportunity existingOpp = [SELECT Id, Description FROM Opportunity WHERE Id = :existingItem.Opportunity__c LIMIT 1];
                String updatedDescription = existingOpp.Description != null ? existingOpp.Description : '';
                updatedDescription += '\n\nMeeting Notes: ' + meetingNotes;
                
                Opportunity opp = new Opportunity(
                    Id = existingItem.Opportunity__c,
                    Description = updatedDescription
                );
                update opp;
            }
            
            System.debug('Meeting disposition saved for queue item: ' + queueItemId);
        } catch (Exception e) {
            System.debug('Error saving meeting disposition: ' + e.getMessage());
            throw new AuraHandledException('Error saving meeting disposition: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void completeEmailAction(Id queueItemId) {
        try {
            NBA_Queue__c queueItem = new NBA_Queue__c(
                Id = queueItemId,
                Status__c = 'Accepted',
                Actioned_Date__c = System.now()
            );
            update queueItem;
            
            System.debug('Email action completed for queue item: ' + queueItemId);
        } catch (Exception e) {
            System.debug('Error completing email action: ' + e.getMessage());
            throw new AuraHandledException('Error completing email action: ' + e.getMessage());
        }
    }

}