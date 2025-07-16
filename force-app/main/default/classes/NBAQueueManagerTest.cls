@IsTest
public class NBAQueueManagerTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account',
            Type = 'Prospect'
        );
        insert testAccount;
        
        // Create test user
        User testUser = [SELECT Id FROM User WHERE IsActive = true AND Profile.Name = 'System Administrator' LIMIT 1];
        
        // Update account owner
        testAccount.OwnerId = testUser.Id;
        update testAccount;
    }
    
    @IsTest
    static void testProcessQueueItems() {
        Account testAccount = [SELECT Id, Name FROM Account LIMIT 1];
        
        List<NBAQueueManager.QueueRequest> requests = new List<NBAQueueManager.QueueRequest>();
        
        NBAQueueManager.QueueRequest req = new NBAQueueManager.QueueRequest();
        req.accountId = testAccount.Id;
        req.actionType = 'Call';
        req.priorityScore = 85.5;
        req.modelReason = 'High value prospect with recent activity';
        req.modelVersion = 'v1.0';
        req.accountName = testAccount.Name;
        requests.add(req);
        
        Test.startTest();
        NBAQueueManager.processQueueItems(requests);
        Test.stopTest();
        
        List<NBA_Queue__c> createdItems = [SELECT Id, Account__c, Action_Type__c, Priority_Score__c, 
                                          Status__c, Subject__c FROM NBA_Queue__c];
        
        System.assertEquals(1, createdItems.size(), 'Should create one queue item');
        System.assertEquals(testAccount.Id, createdItems[0].Account__c, 'Should link to correct account');
        System.assertEquals('Call', createdItems[0].Action_Type__c, 'Should set correct action type');
        System.assertEquals(85.5, createdItems[0].Priority_Score__c, 'Should set correct priority score');
        System.assertEquals('Pending', createdItems[0].Status__c, 'Should set status to Pending');
    }
    
    @IsTest
    static void testAcceptAction() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Meeting',
            Priority_Score__c = 90.0,
            Subject__c = 'Test Meeting Action',
            Description__c = 'Test description',
            Status__c = 'Pending',
            Due_Date__c = Date.today().addDays(7)
        );
        insert queueItem;
        
        Test.startTest();
        String taskId = NBAQueueManager.acceptAction(queueItem.Id, 'Additional notes for task');
        Test.stopTest();
        
        // Verify task ID was returned
        System.assertNotEquals(null, taskId, 'Should return task ID');
        
        // Verify queue item status updated
        NBA_Queue__c updatedItem = [SELECT Status__c FROM NBA_Queue__c WHERE Id = :queueItem.Id];
        System.assertEquals('Accepted', updatedItem.Status__c, 'Queue item should be marked as Accepted');
        
        // Verify task created
        List<Task> createdTasks = [SELECT Id, Subject, WhatId, OwnerId, Status 
                                  FROM Task WHERE WhatId = :testAccount.Id AND Subject LIKE '%Meeting%'];
        
        System.assertEquals(1, createdTasks.size(), 'Should create one task');
        Task createdTask = createdTasks[0];
        System.assertEquals('Next Best Action: Meeting', createdTask.Subject, 'Task should have correct subject');
        System.assertEquals(testAccount.Id, createdTask.WhatId, 'Task should link to correct account');
        System.assertEquals(testUser.Id, createdTask.OwnerId, 'Task should be owned by correct user');
        System.assertEquals('Completed', createdTask.Status, 'Task should be marked as completed');
    }
    
    @IsTest
    static void testDismissAction() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Follow_Up',
            Priority_Score__c = 65.0,
            Subject__c = 'Test Follow Up Action',
            Description__c = 'Original description',
            Status__c = 'Pending'
        );
        insert queueItem;
        
        Test.startTest();
        NBAQueueManager.dismissAction(queueItem.Id, 'Not relevant at this time');
        Test.stopTest();
        
        // Verify queue item status and dismissed reason updated
        NBA_Queue__c updatedItem = [SELECT Status__c, Dismissed_Reason__c FROM NBA_Queue__c WHERE Id = :queueItem.Id];
        System.assertEquals('Dismissed', updatedItem.Status__c, 'Queue item should be marked as Dismissed');
        System.assertEquals('Not relevant at this time', updatedItem.Dismissed_Reason__c, 'Dismissed reason should be set');
    }
    
    @IsTest
    static void testMarkAsViewed() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 80.0,
            Status__c = 'Pending'
        );
        insert queueItem;
        Test.startTest();
        NBAQueueManager.markAsViewed(queueItem.Id);
        Test.stopTest();
        NBA_Queue__c updated = [SELECT First_Viewed_Date__c FROM NBA_Queue__c WHERE Id = :queueItem.Id];
        System.assertNotEquals(null, updated.First_Viewed_Date__c, 'First_Viewed_Date__c should be set');
    }

    @IsTest
    static void testGetNextQueueItem() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 80.0,
            Status__c = 'Pending'
        );
        insert queueItem;
        Test.startTest();
        NBA_Queue__c result = NBAQueueManager.getNextQueueItem(testUser.Id);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Should return a queue item');
        System.assertEquals(queueItem.Id, result.Id, 'Should return the correct queue item');
    }

    @IsTest
    static void testGetNextQueueItemWithDetails() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 80.0,
            Status__c = 'Pending'
        );
        insert queueItem;
        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(testUser.Id);
        Test.stopTest();
        System.assert(result.containsKey('queueItem'), 'Result should contain queueItem');
        System.assertNotEquals(null, result.get('queueItem'), 'queueItem should not be null');
    }

    @IsTest
    static void testUpdateCallDisposition() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        Task testTask = new Task(
            Subject = 'Test Call Task',
            WhatId = testAccount.Id,
            OwnerId = testUser.Id,
            Status = 'Completed'
        );
        insert testTask;
        Test.startTest();
        NBAQueueManager.updateCallDisposition(testTask.Id, 'Completed', 'Left voicemail');
        Test.stopTest();
        Task updatedTask = [SELECT CallDisposition, Description FROM Task WHERE Id = :testTask.Id];
        System.assertEquals('Completed', updatedTask.CallDisposition, 'Call disposition should be updated');
        System.assert(updatedTask.Description.contains('Call Notes: Left voicemail'), 'Description should include call notes');
    }

    @IsTest
    static void testShouldSkipQueueItem() {
        // This indirectly tests the filtering logic by using getNextQueueItemWithDetails
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 80.0,
            Status__c = 'Pending'
        );
        insert queueItem;
        // Set status to Dismissed to ensure it is filtered out
        queueItem.Status__c = 'Dismissed';
        update queueItem;
        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(testUser.Id);
        Test.stopTest();
        System.assertEquals(null, result.get('queueItem'), 'Dismissed items should be filtered out');
    }

    @IsTest
    static void testGetNextQueueItemNoResults() {
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        Test.startTest();
        NBA_Queue__c result = NBAQueueManager.getNextQueueItem(testUser.Id);
        Test.stopTest();
        System.assertEquals(null, result, 'Should return null when no queue items exist');
    }

    @IsTest
    static void testGetNextQueueItemWithDetailsNoResults() {
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(testUser.Id);
        Test.stopTest();
        System.assertEquals(null, result.get('queueItem'), 'Should return null when no queue items exist');
    }

    @IsTest
    static void testMarkAsViewedAlreadyViewed() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 80.0,
            Status__c = 'Pending',
            First_Viewed_Date__c = System.now().addHours(-1)
        );
        insert queueItem;
        DateTime originalViewDate = queueItem.First_Viewed_Date__c;
        Test.startTest();
        NBAQueueManager.markAsViewed(queueItem.Id);
        Test.stopTest();
        NBA_Queue__c updated = [SELECT First_Viewed_Date__c FROM NBA_Queue__c WHERE Id = :queueItem.Id];
        System.assertEquals(originalViewDate, updated.First_Viewed_Date__c, 'First_Viewed_Date__c should not change if already set');
    }

    @IsTest
    static void testAcceptActionWithOpportunity() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        
        // Create test opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Source__c = 'Inbound Call'
        );
        insert testOpp;
        
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Opportunity__c = testOpp.Id,
            Action_Type__c = 'Meeting',
            Priority_Score__c = 90.0,
            Subject__c = 'Test Meeting Action',
            Description__c = 'Test description',
            Status__c = 'Pending',
            Due_Date__c = Date.today().addDays(7)
        );
        insert queueItem;
        
        Test.startTest();
        String taskId = NBAQueueManager.acceptAction(queueItem.Id, 'Additional notes for task');
        Test.stopTest();
        
        System.assertNotEquals(null, taskId, 'Should return task ID');
        NBA_Queue__c updatedItem = [SELECT Status__c FROM NBA_Queue__c WHERE Id = :queueItem.Id];
        System.assertEquals('Accepted', updatedItem.Status__c, 'Queue item should be marked as Accepted');
    }

    @IsTest
    static void testUpdateCallDispositionNoNotes() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        Task testTask = new Task(
            Subject = 'Test Call Task',
            WhatId = testAccount.Id,
            OwnerId = testUser.Id,
            Status = 'Completed'
        );
        insert testTask;
        Test.startTest();
        NBAQueueManager.updateCallDisposition(testTask.Id, 'Completed', '');
        Test.stopTest();
        Task updatedTask = [SELECT CallDisposition, Description FROM Task WHERE Id = :testTask.Id];
        System.assertEquals('Completed', updatedTask.CallDisposition, 'Call disposition should be updated');
        System.assertEquals(null, updatedTask.Description, 'Description should remain null when no notes provided');
    }

    @IsTest
    static void testMarkAsViewedInvalidId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            NBAQueueManager.markAsViewed('a00XXXXXXXXXXXX'); // Non-existent ID
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Exception should be thrown for invalid ID');
    }

    @IsTest
    static void testAcceptActionInvalidId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            NBAQueueManager.acceptAction('a00XXXXXXXXXXXX', 'notes');
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Exception should be thrown for invalid ID');
    }

    @IsTest
    static void testDismissActionInvalidId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            NBAQueueManager.dismissAction('a00XXXXXXXXXXXX', 'reason');
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Exception should be thrown for invalid ID');
    }

    @IsTest
    static void testUpdateCallDispositionInvalidId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            NBAQueueManager.updateCallDisposition('00TXXXXXXXXXXXX', 'Completed', 'notes');
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Exception should be thrown for invalid ID');
    }

    @IsTest
    static void testShouldSkipQueueItemOpportunityStage() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        Contact testContact = new Contact(FirstName = 'Test', LastName = 'Contact', AccountId = testAccount.Id);
        insert testContact;
        Opportunity testOpp = new Opportunity(
            Name = 'Closed Won Opp',
            AccountId = testAccount.Id,
            StageName = 'Closed Won - Pending Implementation',
            CloseDate = Date.today().addDays(30),
            Source__c = 'Inbound Call',
            Primary_Contact__c = testContact.Id
        );
        insert testOpp;
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Opportunity__c = testOpp.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 80.0,
            Status__c = 'Pending'
        );
        insert queueItem;
        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(testUser.Id);
        Test.stopTest();
        System.assertEquals(null, result.get('queueItem'), 'Should skip item with closed won stage');
    }

    @IsTest
    static void testShouldSkipQueueItemLastCallToday() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        Opportunity testOpp = new Opportunity(
            Name = 'Opp with Call Today',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Source__c = 'Inbound Call',
            Last_Call_Date_Time__c = System.now()
        );
        insert testOpp;
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Opportunity__c = testOpp.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 80.0,
            Status__c = 'Pending'
        );
        insert queueItem;
        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(testUser.Id);
        Test.stopTest();
        System.assertEquals(null, result.get('queueItem'), 'Should skip item with last call today');
    }

    @IsTest
    static void testShouldSkipQueueItemPayrollStatus() {
        Account testAccount = new Account(
            Name = 'Payroll Pending',
            Type = 'Prospect',
            Payroll_Status__c = 'Pending'
        );
        insert testAccount;
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 80.0,
            Status__c = 'Pending'
        );
        insert queueItem;
        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(testUser.Id);
        Test.stopTest();
        System.assertEquals(null, result.get('queueItem'), 'Should skip item with payroll status pending');
    }

    @IsTest
    static void testBuildTaskDescriptionAndMapPriority() {
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Description__c = 'desc',
            Priority_Score__c = 85.0
        );
        String descriptionText = NBAQueueManager.buildTaskDescription(queueItem, 'notes');
        System.assert(descriptionText.contains('desc'), 'Should include original description');
        System.assert(descriptionText.contains('notes'), 'Should include additional notes');
        System.assert(descriptionText.contains('Priority: 85'), 'Should include priority');
        System.assertEquals('High', NBAQueueManager.mapPriorityToTask(85.0));
        System.assertEquals('Normal', NBAQueueManager.mapPriorityToTask(65.0));
        System.assertEquals('Low', NBAQueueManager.mapPriorityToTask(40.0));
    }

    @IsTest
    static void testShouldSkipQueueItemClosedLost() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        Contact testContact = new Contact(FirstName = 'Test', LastName = 'Contact', AccountId = testAccount.Id);
        insert testContact;
        Opportunity testOpp = new Opportunity(
            Name = 'Closed Lost Opp',
            AccountId = testAccount.Id,
            StageName = 'Closed Lost',
            CloseDate = Date.today().addDays(30),
            Source__c = 'Inbound Call',
            Primary_Contact__c = testContact.Id,
            Loss_Reason__c = 'Competition'
        );
        insert testOpp;
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Opportunity__c = testOpp.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 80.0,
            Status__c = 'Pending'
        );
        insert queueItem;
        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(testUser.Id);
        Test.stopTest();
        System.assertEquals(null, result.get('queueItem'), 'Should skip item with closed lost stage');
    }

    @IsTest
    static void testShouldSkipQueueItemRanPayroll() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        Contact testContact = new Contact(FirstName = 'Test', LastName = 'Contact', AccountId = testAccount.Id);
        insert testContact;
        Opportunity testOpp = new Opportunity(
            Name = 'Ran Payroll Opp',
            AccountId = testAccount.Id,
            StageName = 'Ran Payroll',
            CloseDate = Date.today().addDays(30),
            Source__c = 'Inbound Call',
            Primary_Contact__c = testContact.Id
        );
        insert testOpp;
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Opportunity__c = testOpp.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 80.0,
            Status__c = 'Pending'
        );
        insert queueItem;
        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(testUser.Id);
        Test.stopTest();
        System.assertEquals(null, result.get('queueItem'), 'Should skip item with ran payroll stage');
    }

    @IsTest
    static void testShouldSkipQueueItemPayrollStatusProcessing() {
        Account testAccount = new Account(
            Name = 'Payroll Processing',
            Type = 'Prospect',
            Payroll_Status__c = 'Processing'
        );
        insert testAccount;
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 80.0,
            Status__c = 'Pending'
        );
        insert queueItem;
        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(testUser.Id);
        Test.stopTest();
        System.assertEquals(null, result.get('queueItem'), 'Should skip item with payroll status processing');
    }

    @IsTest
    static void testShouldSkipQueueItemPayrollStatusPaid() {
        Account testAccount = new Account(
            Name = 'Payroll Paid',
            Type = 'Prospect',
            Payroll_Status__c = 'Paid'
        );
        insert testAccount;
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 80.0,
            Status__c = 'Pending'
        );
        insert queueItem;
        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(testUser.Id);
        Test.stopTest();
        System.assertEquals(null, result.get('queueItem'), 'Should skip item with payroll status paid');
    }

    @IsTest
    static void testGetNextQueueItemWithDetailsNoUserItems() {
        User testUser = [SELECT Id FROM User WHERE IsActive = true AND Id != :UserInfo.getUserId() LIMIT 1];
        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(testUser.Id);
        Test.stopTest();
        System.assertEquals(null, result.get('queueItem'), 'Should return null when user has no queue items');
    }

    @IsTest
    static void testGetNextQueueItemNoUserItems() {
        User testUser = [SELECT Id FROM User WHERE IsActive = true AND Id != :UserInfo.getUserId() LIMIT 1];
        Test.startTest();
        NBA_Queue__c result = NBAQueueManager.getNextQueueItem(testUser.Id);
        Test.stopTest();
        System.assertEquals(null, result, 'Should return null when user has no queue items');
    }

    @IsTest
    static void testProcessQueueItemsDirect() {
        Account testAccount = [SELECT Id, Name FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        NBAQueueManager.QueueRequest req = new NBAQueueManager.QueueRequest();
        req.accountId = testAccount.Id;
        req.actionType = 'Call';
        req.priorityScore = 55.5;
        req.modelReason = 'Test reason';
        req.modelVersion = 'v2.0';
        req.accountName = testAccount.Name;
        req.mostRecentPayrollProvider = 'ADP';
        List<NBAQueueManager.QueueRequest> requests = new List<NBAQueueManager.QueueRequest>{req};
        Test.startTest();
        NBAQueueManager.processQueueItems(requests);
        Test.stopTest();
        List<NBA_Queue__c> items = [SELECT Id, Account__c, Action_Type__c, Priority_Score__c, Status__c, Model_Reason__c, Model_Version__c, Most_Recent_Payroll_Provider__c FROM NBA_Queue__c WHERE Account__c = :testAccount.Id AND Action_Type__c = 'Call'];
        System.assert(items.size() > 0, 'Should create at least one NBA_Queue__c record');
        System.assertEquals('Test reason', items[0].Model_Reason__c, 'Should set model reason');
        System.assertEquals('v2.0', items[0].Model_Version__c, 'Should set model version');
        System.assertEquals('ADP', items[0].Most_Recent_Payroll_Provider__c, 'Should set payroll provider');
    }

    @IsTest
    static void testProcessQueueItemsEmptyList() {
        List<NBAQueueManager.QueueRequest> requests = new List<NBAQueueManager.QueueRequest>();
        Test.startTest();
        NBAQueueManager.processQueueItems(requests);
        Test.stopTest();
        // Should not throw an exception and should complete successfully
        System.assertEquals(0, requests.size(), 'Empty list should remain empty');
    }

    @IsTest
    static void testGetNextQueueItemWithDetailsExceptionHandling() {
        // Test with a user that doesn't exist to trigger exception handling
        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails('005000000000000'); // Non-existent user ID
        Test.stopTest();
        // Should return null for non-existent user
        System.assertEquals(null, result.get('queueItem'), 'Should return null for non-existent user ID');
    }

    @IsTest
    static void testProcessQueueItemsWithOpportunity() {
        Account testAccount = [SELECT Id, Name FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        
        // Create test opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opp for Process',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Source__c = 'Inbound Call'
        );
        insert testOpp;
        
        NBAQueueManager.QueueRequest req = new NBAQueueManager.QueueRequest();
        req.accountId = testAccount.Id;
        req.actionType = 'Email';
        req.priorityScore = 75.0;
        req.modelReason = 'Test reason with opportunity';
        req.modelVersion = 'v3.0';
        req.accountName = testAccount.Name;
        req.mostRecentPayrollProvider = 'Gusto';
        List<NBAQueueManager.QueueRequest> requests = new List<NBAQueueManager.QueueRequest>{req};
        
        Test.startTest();
        NBAQueueManager.processQueueItems(requests);
        Test.stopTest();
        
        List<NBA_Queue__c> items = [SELECT Id, Account__c, Opportunity__c, Action_Type__c, Priority_Score__c, Status__c FROM NBA_Queue__c WHERE Account__c = :testAccount.Id AND Action_Type__c = 'Email'];
        System.assert(items.size() > 0, 'Should create NBA_Queue__c record with opportunity');
        System.assertEquals(testOpp.Id, items[0].Opportunity__c, 'Should link to the opportunity');
    }
}