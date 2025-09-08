@isTest
public class NBAQueueManagerTest {

    @testSetup
    static void setupData() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];

        Account acct = new Account(Name = 'Test Account', Phone = '123-456-7890');
        insert acct;

        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            AccountId = acct.Id,
            OwnerId = salesRep.Id,
            Source__c = 'Outbound'
        );
        insert opp;

        Contact contact = new Contact(
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'jane.doe@example.com',
            Phone = '1234567890',
            AccountId = acct.Id
        );
        insert contact;

        opp.Primary_Contact__c = contact.Id;
        update opp;

        // Create NBA item with proper status for testing
        NBA_Queue__c item = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 50,
            Subject__c = 'NBA: Call - Test Account',
            Status__c = 'Pending',
            Sales_Rep__c = salesRep.Id,
            Opportunity__c = opp.Id
        );
        insert item;
    }

    @isTest
    static void testProcessQueueItems() {
        Account acct = [SELECT Id, Name FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity WHERE AccountId = :acct.Id LIMIT 1];

        NBAQueueManager.QueueRequest req = new NBAQueueManager.QueueRequest();
        req.accountId = acct.Id;
        req.actionType = 'Call';
        req.priorityScore = 80;
        req.modelReason = 'Test reason';
        req.modelVersion = 'v1';
        req.accountName = acct.Name;
        req.mostRecentPayrollProvider = 'Gusto';

        Test.startTest();
        NBAQueueManager.processQueueItems(new List<NBAQueueManager.QueueRequest>{ req });
        Test.stopTest();

        List<NBA_Queue__c> created = [SELECT Id, Status__c, Subject__c FROM NBA_Queue__c WHERE Account__c = :acct.Id];
        System.assert(!created.isEmpty(), 'NBA_Queue__c record should be created');
        System.assertEquals('Pending', created[0].Status__c);
    }

    @isTest
    static void testGetNextQueueItem() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];

        Test.startTest();
        NBA_Queue__c item = NBAQueueManager.getNextQueueItem(salesRep.Id);
        Test.stopTest();

        System.assertNotEquals(null, item, 'Should return an NBA queue item');
    }

    @isTest
    static void testAcceptAction() {
        NBA_Queue__c item = [SELECT Id, Opportunity__c FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];

        Test.startTest();
        String taskId = NBAQueueManager.acceptAction(item.Id, 'Some extra context');
        Test.stopTest();

        Task t = [SELECT Id, Description FROM Task WHERE Id = :taskId];
        System.assert(t != null, 'Task should have been created');
        System.assert(t.Description.contains('Additional Notes'), 'Description should include extra notes');
    }

    @isTest
    static void testDismissAction() {
        NBA_Queue__c item = [SELECT Id FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];

        Test.startTest();
        NBAQueueManager.dismissAction(item.Id, 'No longer relevant');
        Test.stopTest();

        NBA_Queue__c updated = [SELECT Id, Status__c, Dismissed_Reason__c FROM NBA_Queue__c WHERE Id = :item.Id];
        System.assertEquals('Dismissed', updated.Status__c);
        System.assertEquals('No longer relevant', updated.Dismissed_Reason__c);
    }
    
    @isTest
    static void testSkipQueueItemWithFutureFollowUpDate() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        Account acct = [SELECT Id FROM Account LIMIT 1];
        
        // Create opportunity with future follow-up date
        Opportunity oppWithFutureDate = new Opportunity(
            Name = 'Future Follow Up Opp',
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            AccountId = acct.Id,
            OwnerId = salesRep.Id,
            Source__c = 'Outbound',
            Future_Follow_Up_Date__c = Date.today().addDays(7) // Future date
        );
        insert oppWithFutureDate;
        
        // Create NBA item for this opportunity
        NBA_Queue__c futureItem = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 90, // High priority
            Subject__c = 'NBA: Call - Future Follow Up',
            Status__c = 'Pending',
            Sales_Rep__c = salesRep.Id,
            Opportunity__c = oppWithFutureDate.Id
        );
        insert futureItem;
        
        Test.startTest();
        NBA_Queue__c result = NBAQueueManager.getNextQueueItem(salesRep.Id);
        Test.stopTest();
        
        // Should return the original item, not the future follow-up item
        System.assertNotEquals(futureItem.Id, result.Id, 'Should not return item with future follow-up date');
    }

    @isTest
    static void testMarkAsViewed() {
        NBA_Queue__c item = [SELECT Id FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];

        Test.startTest();
        NBAQueueManager.markAsViewed(item.Id);
        Test.stopTest();

        NBA_Queue__c updated = [SELECT First_Viewed_Date__c FROM NBA_Queue__c WHERE Id = :item.Id];
        System.assertNotEquals(null, updated.First_Viewed_Date__c, 'First_Viewed_Date__c should be set');
    }

    @isTest
    static void testUpdateCallDisposition() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        
        Task testTask = new Task(
            Subject = 'Test Call Task',
            WhatId = acct.Id,
            OwnerId = salesRep.Id,
            Status = 'Completed'
        );
        insert testTask;

        Test.startTest();
        NBAQueueManager.updateCallDisposition(testTask.Id, 'Connected - DM', 'Left voicemail');
        Test.stopTest();

        Task updatedTask = [SELECT CallDisposition, Description FROM Task WHERE Id = :testTask.Id];
        System.assertEquals('Connected - DM', updatedTask.CallDisposition, 'Call disposition should be updated');
        System.assert(updatedTask.Description.contains('Call Notes: Left voicemail'), 'Description should include call notes');
    }

    @isTest
    static void testGetNextQueueItemWithDetails() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];

        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(salesRep.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.get('queueItem'), 'Should return a queue item');
    }

    @isTest
    static void testExceptionHandling() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            NBAQueueManager.markAsViewed('a000000000000000'); // Invalid ID
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Exception should be thrown for invalid ID');
    }

    @isTest
    static void testBuildTaskDescription() {
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Description__c = 'Original description',
            Priority_Score__c = 85.0
        );

        Test.startTest();
        String description = NBAQueueManager.buildTaskDescription(queueItem, 'Additional notes');
        Test.stopTest();

        System.assert(description.contains('Original description'), 'Should include original description');
        System.assert(description.contains('Additional Notes: Additional notes'), 'Should include additional notes');
        System.assert(description.contains('Priority: 85'), 'Should include priority');
    }

    @isTest
    static void testMapPriorityToTask() {
        Test.startTest();
        String highPriority = NBAQueueManager.mapPriorityToTask(85.0);
        String normalPriority = NBAQueueManager.mapPriorityToTask(75.0);
        String lowPriority = NBAQueueManager.mapPriorityToTask(45.0);
        Test.stopTest();

        System.assertEquals('High', highPriority, '85.0 should be High priority');
        System.assertEquals('Normal', normalPriority, '75.0 should be Normal priority');
        System.assertEquals('Low', lowPriority, '45.0 should be Low priority');
    }

    @isTest
    static void testCalculateDueDate() {
        Account acct = [SELECT Id, Name FROM Account LIMIT 1];

        NBAQueueManager.QueueRequest req = new NBAQueueManager.QueueRequest();
        req.accountId = acct.Id;
        req.actionType = 'Call';
        req.priorityScore = 85.0;
        req.modelReason = 'Test reason for due date';
        req.modelVersion = 'v1.0';
        req.accountName = acct.Name;

        List<NBAQueueManager.QueueRequest> requests = new List<NBAQueueManager.QueueRequest>{req};

        Test.startTest();
        NBAQueueManager.processQueueItems(requests);
        Test.stopTest();

        // Get the most recently created Call item (should be the one we just created)
        List<NBA_Queue__c> createdItems = [SELECT Id, Due_Date__c, Action_Type__c FROM NBA_Queue__c WHERE Account__c = :acct.Id AND Action_Type__c = 'Call' ORDER BY CreatedDate DESC LIMIT 1];
        System.assert(!createdItems.isEmpty(), 'Should create at least one queue item');
        System.assertEquals(Date.today().addDays(1), createdItems[0].Due_Date__c, 'Call should be due in 1 day');
    }

    @isTest
    static void testGenerateSubject() {
        Account acct = [SELECT Id, Name FROM Account LIMIT 1];

        NBAQueueManager.QueueRequest req = new NBAQueueManager.QueueRequest();
        req.accountId = acct.Id;
        req.actionType = 'Email';
        req.priorityScore = 75.0;
        req.modelReason = 'Test reason for subject';
        req.modelVersion = 'v1.0';
        req.accountName = acct.Name;

        List<NBAQueueManager.QueueRequest> requests = new List<NBAQueueManager.QueueRequest>{req};

        Test.startTest();
        NBAQueueManager.processQueueItems(requests);
        Test.stopTest();

        // Get the most recently created Email item (should be the one we just created)
        List<NBA_Queue__c> createdItems = [SELECT Id, Subject__c FROM NBA_Queue__c WHERE Account__c = :acct.Id AND Action_Type__c = 'Email' ORDER BY CreatedDate DESC LIMIT 1];
        System.assert(!createdItems.isEmpty(), 'Should create at least one queue item');
        System.assertEquals('NBA: Email - ' + acct.Name, createdItems[0].Subject__c, 'Should include account name in subject');
    }

    @isTest
    static void testGetUpNextItemExcludesCurrent() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        Account acct = [SELECT Id FROM Account LIMIT 1];

        // Create two pending items with different priorities
        NBA_Queue__c firstItem = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 100,
            Subject__c = 'NBA: UpNext First',
            Status__c = 'Pending',
            Sales_Rep__c = salesRep.Id
        );
        NBA_Queue__c secondItem = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 90,
            Subject__c = 'NBA: UpNext Second',
            Status__c = 'Pending',
            Sales_Rep__c = salesRep.Id
        );
        insert new List<NBA_Queue__c>{ firstItem, secondItem };

        Test.startTest();
        Map<String, Object> upNext = NBAQueueManager.getUpNextItem(salesRep.Id, firstItem.Id);
        Test.stopTest();

        NBA_Queue__c nextItem = (NBA_Queue__c) upNext.get('upNext');
        System.assertNotEquals(null, nextItem, 'Should return an up next item');
        System.assertEquals(secondItem.Id, nextItem.Id, 'Up next should exclude the current item');
    }

    @isTest
    static void testFinalizeQueueItemSetsAccepted() {
        NBA_Queue__c item = [SELECT Id, Status__c FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];
        Test.startTest();
        NBAQueueManager.finalizeQueueItem(item.Id);
        Test.stopTest();
        NBA_Queue__c updated = [SELECT Status__c, Completed_Date__c FROM NBA_Queue__c WHERE Id = :item.Id];
        System.assertEquals('Accepted', updated.Status__c);
        System.assertNotEquals(null, updated.Completed_Date__c);
    }

    @isTest
    static void testGetOpportunityPrimaryContactNull() {
        Test.startTest();
        Map<String, Object> res = NBAQueueManager.getOpportunityPrimaryContact(null);
        Test.stopTest();
        System.assertEquals(true, res.isEmpty(), 'Null input should return empty result');
    }

    @isTest
    static void testGetAccountPrimaryContactNoPrimary() {
        Account a = new Account(Name = 'No Primary');
        insert a;
        Test.startTest();
        Map<String, Object> res = NBAQueueManager.getAccountPrimaryContact(a.Id);
        Test.stopTest();
        System.assertEquals(true, res.isEmpty(), 'No primary contact should return empty');
    }

    @isTest
    static void testGetOpportunityStageNamesNotEmpty() {
        Test.startTest();
        List<String> stages = NBAQueueManager.getOpportunityStageNames();
        Test.stopTest();
        System.assert(stages != null && stages.size() > 0, 'Stage list should not be empty');
    }

    @isTest
    static void testSendQueueEmailWithTemplateValidation() {
        NBA_Queue__c item = [SELECT Id FROM NBA_Queue__c LIMIT 1];
        Boolean threw = false;
        Test.startTest();
        try {
            NBAQueueManager.sendQueueEmailWithTemplate(item.Id, null, null, null, null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should validate required inputs');
    }

    @isTest
    static void testSkipDueToStageClosedLost() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Opportunity closedLost = new Opportunity(
            Name = 'Closed Lost Opp', StageName = 'Closed Lost', CloseDate = Date.today(), AccountId = acct.Id, OwnerId = salesRep.Id,
            Source__c = 'Outbound', Loss_Reason__c = 'Other'
        );
        insert closedLost;
        NBA_Queue__c skipItem = new NBA_Queue__c(
            Account__c = acct.Id, Action_Type__c = 'Call', Priority_Score__c = 50, Subject__c = 'Skip Stage', Status__c = 'Pending', Sales_Rep__c = salesRep.Id, Opportunity__c = closedLost.Id
        );
        // Also create a valid item that should be served
        NBA_Queue__c okItem = new NBA_Queue__c(
            Account__c = acct.Id, Action_Type__c = 'Call', Priority_Score__c = 40, Subject__c = 'OK', Status__c = 'Pending', Sales_Rep__c = salesRep.Id
        );
        insert new List<NBA_Queue__c>{ skipItem, okItem };
        Test.startTest();
        NBA_Queue__c nextItem = NBAQueueManager.getNextQueueItem(salesRep.Id);
        Test.stopTest();
        System.assertNotEquals(skipItem.Id, nextItem.Id, 'Should not serve Closed Lost opportunity item');
    }

    @isTest
    static void testSkipDueToPayrollStatus() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        Account acct = new Account(Name='Payroll Pending', Payroll_Status__c = 'Pending');
        insert acct;
        Opportunity opp = new Opportunity(Name='Opp P', StageName='Qualification', CloseDate=Date.today().addDays(5), AccountId=acct.Id, OwnerId=salesRep.Id, Source__c='Outbound');
        insert opp;
        NBA_Queue__c skipItem = new NBA_Queue__c(Account__c=acct.Id, Action_Type__c='Call', Priority_Score__c=60, Subject__c='Skip Payroll', Status__c='Pending', Sales_Rep__c=salesRep.Id, Opportunity__c=opp.Id);
        // Valid item
        Account acct2 = new Account(Name='OK');
        insert acct2;
        NBA_Queue__c okItem = new NBA_Queue__c(Account__c=acct2.Id, Action_Type__c='Call', Priority_Score__c=55, Subject__c='OK2', Status__c='Pending', Sales_Rep__c=salesRep.Id);
        insert new List<NBA_Queue__c>{ skipItem, okItem };
        Test.startTest();
        NBA_Queue__c nextItem = NBAQueueManager.getNextQueueItem(salesRep.Id);
        Test.stopTest();
        System.assertEquals(okItem.Id, nextItem.Id, 'Item with payroll pending should be skipped');
    }

    @isTest
    static void testAssignQueueItems() {
        Account acct = [SELECT Id, Name FROM Account LIMIT 1];

        NBAQueueManager.QueueRequest req = new NBAQueueManager.QueueRequest();
        req.accountId = acct.Id;
        req.actionType = 'Meeting';
        req.priorityScore = 90.0;
        req.modelReason = 'Test assignQueueItems';
        req.modelVersion = 'v1.0';
        req.accountName = acct.Name;

        List<NBAQueueManager.QueueRequest> requests = new List<NBAQueueManager.QueueRequest>{req};

        Test.startTest();
        NBAQueueManager.processQueueItems(requests);
        Test.stopTest();

        List<NBA_Queue__c> createdItems = [SELECT Id FROM NBA_Queue__c WHERE Account__c = :acct.Id];
        System.assert(!createdItems.isEmpty(), 'Should create queue items');
    }

    // Test new "In Progress" status functionality
    @isTest
    static void testAcceptActionSetsInProgressStatus() {
        NBA_Queue__c item = [SELECT Id, Status__c, Actioned_Date__c FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];
        
        System.assertEquals('Pending', item.Status__c, 'Initial status should be Pending');
        System.assertEquals(null, item.Actioned_Date__c, 'Actioned_Date__c should be null initially');

        Test.startTest();
        String taskId = NBAQueueManager.acceptAction(item.Id, 'Test notes');
        Test.stopTest();

        NBA_Queue__c updated = [SELECT Id, Status__c, Actioned_Date__c FROM NBA_Queue__c WHERE Id = :item.Id];
        System.assertEquals('In Progress', updated.Status__c, 'Status should be set to In Progress');
        System.assertNotEquals(null, updated.Actioned_Date__c, 'Actioned_Date__c should be set when going to In Progress');
    }

    // Test that "In Progress" items are prioritized in queue
    @isTest
    static void testInProgressItemsArePrioritized() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity WHERE AccountId = :acct.Id LIMIT 1];

        // Create a second NBA item with higher priority but Pending status
        NBA_Queue__c highPriorityPending = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 90, // Higher priority
            Subject__c = 'NBA: High Priority Call',
            Status__c = 'Pending',
            Sales_Rep__c = salesRep.Id,
            Opportunity__c = opp.Id
        );
        insert highPriorityPending;

        // Accept the first item to make it "In Progress"
        NBA_Queue__c firstItem = [SELECT Id FROM NBA_Queue__c WHERE Status__c = 'Pending' AND Priority_Score__c = 50 LIMIT 1];
        NBAQueueManager.acceptAction(firstItem.Id, 'Test');

        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(salesRep.Id);
        Test.stopTest();

        NBA_Queue__c returnedItem = (NBA_Queue__c) result.get('queueItem');
        System.assertEquals('In Progress', returnedItem.Status__c, 'Should return In Progress item even if there are higher priority Pending items');
    }

    // Test call disposition completion sets status to "Accepted" and sets Completed_Date__c
    @isTest
    static void testCallDispositionCompletesToAccepted() {
        NBA_Queue__c item = [SELECT Id, Status__c, Completed_Date__c, Opportunity__c FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];

        // First accept the action to set it to "In Progress"
        NBAQueueManager.acceptAction(item.Id, 'Test notes');
        
        // Verify it's now "In Progress"
        NBA_Queue__c inProgress = [SELECT Id, Status__c, Completed_Date__c FROM NBA_Queue__c WHERE Id = :item.Id];
        System.assertEquals('In Progress', inProgress.Status__c, 'Should be In Progress after accept');
        System.assertEquals(null, inProgress.Completed_Date__c, 'Completed_Date__c should be null while In Progress');

        // Create a task for the call
        Task callTask = new Task(
            Subject = 'Test Call',
            WhatId = item.Opportunity__c,
            Status = 'Completed'
        );
        insert callTask;

        Test.startTest();
        NBAQueueManager.updateCallDispositionWithQueueId(
            callTask.Id,
            item.Id,
            'Connected - DM',
            'Great conversation, they are interested'
        );
        Test.stopTest();

        NBA_Queue__c completed = [SELECT Id, Status__c, Completed_Date__c, Call_Disposition__c, Rep_Notes__c FROM NBA_Queue__c WHERE Id = :item.Id];
        System.assertEquals('Accepted', completed.Status__c, 'Status should be set to Accepted after disposition');
        System.assertNotEquals(null, completed.Completed_Date__c, 'Completed_Date__c should be set when going to Accepted');
        System.assertEquals('Connected - DM', completed.Call_Disposition__c, 'Call disposition should be saved');
        System.assert(completed.Rep_Notes__c.contains('Call Notes: Great conversation'), 'Rep notes should include call notes');
    }

    // Test Opportunity Description append functionality
    @isTest
    static void testOpportunityDescriptionIsAppended() {
        NBA_Queue__c item = [SELECT Id, Opportunity__c FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];
        Opportunity opp = [SELECT Id, Description FROM Opportunity WHERE Id = :item.Opportunity__c];
        
        // Set initial description
        opp.Description = 'Initial opportunity description';
        update opp;

        // Accept and complete the action
        NBAQueueManager.acceptAction(item.Id, 'Test notes');
        
        Task callTask = new Task(
            Subject = 'Test Call',
            WhatId = item.Opportunity__c,
            Status = 'Completed'
        );
        insert callTask;

        Test.startTest();
        NBAQueueManager.updateCallDispositionWithQueueId(
            callTask.Id,
            item.Id,
            'Connected - DM',
            'New call notes from this conversation'
        );
        Test.stopTest();

        Opportunity updatedOpp = [SELECT Id, Description FROM Opportunity WHERE Id = :opp.Id];
        System.assert(updatedOpp.Description.contains('Initial opportunity description'), 'Should preserve original description');
        System.assert(updatedOpp.Description.contains('--- Call Notes'), 'Should include call notes separator');
        System.assert(updatedOpp.Description.contains('New call notes from this conversation'), 'Should include new call notes');
    }

    // Test cancel call disposition functionality
    @isTest
    static void testCancelCallDisposition() {
        NBA_Queue__c item = [SELECT Id, Status__c, Completed_Date__c FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];
        
        // Accept the action to set it to "In Progress"
        NBAQueueManager.acceptAction(item.Id, 'Test notes');
        
        // Verify it's "In Progress"
        NBA_Queue__c inProgress = [SELECT Id, Status__c, Completed_Date__c FROM NBA_Queue__c WHERE Id = :item.Id];
        System.assertEquals('In Progress', inProgress.Status__c, 'Should be In Progress after accept');

        Test.startTest();
        NBAQueueManager.cancelCallDisposition(item.Id);
        Test.stopTest();

        NBA_Queue__c cancelled = [SELECT Id, Status__c, Completed_Date__c FROM NBA_Queue__c WHERE Id = :item.Id];
        System.assertEquals('Pending', cancelled.Status__c, 'Status should revert to Pending when cancelled');
        System.assertEquals(null, cancelled.Completed_Date__c, 'Completed_Date__c should be cleared when cancelled');
    }

    // Test that getNextQueueItemWithDetails includes Opportunity Description
    @isTest
    static void testGetNextQueueItemWithDetailsIncludesOpportunityDescription() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        // Set opportunity description
        opp.Description = 'Test opportunity description for pre-population';
        update opp;

        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(salesRep.Id);
        Test.stopTest();

        NBA_Queue__c returnedItem = (NBA_Queue__c) result.get('queueItem');
        System.assertNotEquals(null, returnedItem, 'Should return a queue item');
        System.assertNotEquals(null, returnedItem.Opportunity__r, 'Should include opportunity relationship');
        System.assertEquals('Test opportunity description for pre-population', returnedItem.Opportunity__r.Description, 'Should include opportunity description');
    }

    // Test edge case: Opportunity with no description
    @isTest
    static void testOpportunityWithNoDescription() {
        NBA_Queue__c item = [SELECT Id, Opportunity__c FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];
        Opportunity opp = [SELECT Id, Description FROM Opportunity WHERE Id = :item.Opportunity__c];
        
        // Clear description
        opp.Description = null;
        update opp;

        // Accept and complete the action
        NBAQueueManager.acceptAction(item.Id, 'Test notes');
        
        Task callTask = new Task(
            Subject = 'Test Call',
            WhatId = item.Opportunity__c,
            Status = 'Completed'
        );
        insert callTask;

        Test.startTest();
        NBAQueueManager.updateCallDispositionWithQueueId(
            callTask.Id,
            item.Id,
            'Connected - DM',
            'Call notes when no previous description'
        );
        Test.stopTest();

        Opportunity updatedOpp = [SELECT Id, Description FROM Opportunity WHERE Id = :opp.Id];
        System.assert(updatedOpp.Description.contains('--- Call Notes'), 'Should include call notes separator');
        System.assert(updatedOpp.Description.contains('Call notes when no previous description'), 'Should include new call notes');
    }

    // Test edge case: NBA Queue item without opportunity
    @isTest
    static void testNBAQueueItemWithoutOpportunity() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        Account acct = [SELECT Id FROM Account LIMIT 1];

        // Create NBA item without opportunity
        NBA_Queue__c itemWithoutOpp = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 75,
            Subject__c = 'NBA: Call - No Opportunity',
            Status__c = 'Pending',
            Sales_Rep__c = salesRep.Id
            // No Opportunity__c field
        );
        insert itemWithoutOpp;

        // Accept the action
        NBAQueueManager.acceptAction(itemWithoutOpp.Id, 'Test notes');
        
        Task callTask = new Task(
            Subject = 'Test Call',
            WhatId = acct.Id,
            Status = 'Completed'
        );
        insert callTask;

        Test.startTest();
        NBAQueueManager.updateCallDispositionWithQueueId(
            callTask.Id,
            itemWithoutOpp.Id,
            'Connected - DM',
            'Call notes for item without opportunity'
        );
        Test.stopTest();

        // Should not throw an error and should complete successfully
        NBA_Queue__c completed = [SELECT Id, Status__c, Call_Disposition__c FROM NBA_Queue__c WHERE Id = :itemWithoutOpp.Id];
        System.assertEquals('Accepted', completed.Status__c, 'Should complete successfully even without opportunity');
        System.assertEquals('Connected - DM', completed.Call_Disposition__c, 'Call disposition should be saved');
    }

    @isTest
    static void testUpdateCallDispositionWithQueueId() {
        NBA_Queue__c item = [SELECT Id, Account__c, Sales_Rep__c FROM NBA_Queue__c WHERE Status__c != 'Dismissed' LIMIT 1];

        Task t = new Task(
            Subject = 'Test Call',
            WhatId = item.Account__c,
            OwnerId = item.Sales_Rep__c,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal'
        );
        insert t;

        Test.startTest();
        NBAQueueManager.updateCallDispositionWithQueueId(
            t.Id,
            item.Id,
            'Connected - DM',
            'Good convo, they are interested'
        );
        Test.stopTest();

        Task updated = [SELECT Id, CallDisposition, Description FROM Task WHERE Id = :t.Id];
        NBA_Queue__c updatedItem = [SELECT Id, Call_Disposition__c, Rep_Notes__c FROM NBA_Queue__c WHERE Id = :item.Id];

        System.assertEquals('Connected - DM', updated.CallDisposition);
        System.assert(updated.Description.contains('Call Notes'), 'Task description should include call notes');
        System.assertEquals('Connected - DM', updatedItem.Call_Disposition__c);
    }
    


    @isTest
    static void testGetAccountPhoneNumber() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        String phoneNumber = NBAQueueManager.getAccountPhoneNumber(acct.Id);
        Test.stopTest();

        System.assertEquals('123-456-7890', phoneNumber, 'Should return correct phone number');
    }

    @isTest
    static void testGetOpportunityPrimaryContact() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getOpportunityPrimaryContact(opp.Id);
        Test.stopTest();

        System.assert(result.containsKey('contactId'), 'Should contain contactId');
        System.assertNotEquals(null, result.get('contactId'), 'Should return contact ID');
    }
    
    @isTest
    static void testLastViewedDateUpdate() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        NBA_Queue__c item = [SELECT Id, Last_Viewed_Date__c, Priority_Multiplier_Applied__c FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];
        
        // Verify initial state
        System.assertEquals(null, item.Last_Viewed_Date__c, 'Last viewed date should be null initially');
        System.assertEquals(null, item.Priority_Multiplier_Applied__c, 'Priority multiplier should be null initially');
        
        Test.startTest();
        NBA_Queue__c returnedItem = NBAQueueManager.getNextQueueItem(salesRep.Id);
        Test.stopTest();
        
        // Verify last viewed date was updated but multiplier not set yet
        NBA_Queue__c updatedItem = [SELECT Id, Last_Viewed_Date__c, Priority_Multiplier_Applied__c FROM NBA_Queue__c WHERE Id = :item.Id];
        System.assertNotEquals(null, updatedItem.Last_Viewed_Date__c, 'Last viewed date should be set');
        System.assertEquals(null, updatedItem.Priority_Multiplier_Applied__c, 'Priority multiplier should not be set until accepted');
    }
    
    @isTest
    static void testLastViewedDateUpdateWithDetails() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        NBA_Queue__c item = [SELECT Id, Last_Viewed_Date__c, Priority_Multiplier_Applied__c FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];
        
        // Verify initial state
        System.assertEquals(null, item.Last_Viewed_Date__c, 'Last viewed date should be null initially');
        System.assertEquals(null, item.Priority_Multiplier_Applied__c, 'Priority multiplier should be null initially');
        
        Test.startTest();
        Map<String, Object> result = NBAQueueManager.getNextQueueItemWithDetails(salesRep.Id);
        Test.stopTest();
        
        // Verify last viewed date was updated but multiplier not set yet
        NBA_Queue__c updatedItem = [SELECT Id, Last_Viewed_Date__c, Priority_Multiplier_Applied__c FROM NBA_Queue__c WHERE Id = :item.Id];
        System.assertNotEquals(null, updatedItem.Last_Viewed_Date__c, 'Last viewed date should be set');
        System.assertEquals(null, updatedItem.Priority_Multiplier_Applied__c, 'Priority multiplier should not be set until accepted');
        
        // Verify result contains the item
        System.assertNotEquals(null, result.get('queueItem'), 'Should return a queue item');
    }
    
    @isTest
    static void testMultipleLastViewedDateUpdates() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        NBA_Queue__c item = [SELECT Id, Last_Viewed_Date__c FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];
        
        Test.startTest();
        // Call getNextQueueItem multiple times
        NBA_Queue__c returnedItem1 = NBAQueueManager.getNextQueueItem(salesRep.Id);
        NBA_Queue__c returnedItem2 = NBAQueueManager.getNextQueueItem(salesRep.Id);
        NBA_Queue__c returnedItem3 = NBAQueueManager.getNextQueueItem(salesRep.Id);
        Test.stopTest();
        
        // Verify last viewed date was updated (should be the most recent timestamp)
        NBA_Queue__c updatedItem = [SELECT Id, Last_Viewed_Date__c FROM NBA_Queue__c WHERE Id = :item.Id];
        System.assertNotEquals(null, updatedItem.Last_Viewed_Date__c, 'Last viewed date should be set');
    }
    
    @isTest
    static void testPriorityMultiplierDescription() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        Account acct = [SELECT Id FROM Account LIMIT 1];
        
        // Create an item with recent web usage to trigger multiplier
        NBA_Queue__c itemWithWebUsage = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 80,
            Subject__c = 'NBA: Call - Web Usage Test',
            Status__c = 'Pending',
            Sales_Rep__c = salesRep.Id
        );
        insert itemWithWebUsage;
        
        // Update account to have recent web usage
        acct.Last_Web_Usage_Timestamp__c = DateTime.now().addMinutes(-30); // Within last hour
        update acct;
        
        Test.startTest();
        NBA_Queue__c returnedItem = NBAQueueManager.getNextQueueItem(salesRep.Id);
        Test.stopTest();
        
        // Verify multiplier description was NOT set (only set when action is completed)
        NBA_Queue__c updatedItem = [SELECT Id, Priority_Multiplier_Applied__c FROM NBA_Queue__c WHERE Id = :itemWithWebUsage.Id];
        System.assertEquals(null, updatedItem.Priority_Multiplier_Applied__c, 'Multiplier should not be set when item is served');
    }
    
    @isTest
    static void testMultiplierSetOnCompletedAction() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        Account acct = [SELECT Id FROM Account LIMIT 1];
        
        // Create an item with recent web usage to trigger multiplier
        NBA_Queue__c itemWithWebUsage = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 100, // High priority to ensure it's returned
            Subject__c = 'NBA: Call - Web Usage Test',
            Status__c = 'Pending',
            Sales_Rep__c = salesRep.Id
        );
        insert itemWithWebUsage;
        
        // Update account to have recent web usage and ensure it doesn't have problematic status
        acct.Last_Web_Usage_Timestamp__c = DateTime.now().addMinutes(-30); // Within last hour
        acct.Payroll_Status__c = 'Active'; // Ensure it's not 'pending', 'processing', or 'paid'
        update acct;
        
        Test.startTest();
        // First, serve the item (should update last viewed date but not set multiplier)
        NBA_Queue__c servedItem = NBAQueueManager.getNextQueueItem(salesRep.Id);
        
        // Verify we got a result
        System.assertNotEquals(null, servedItem, 'Should return a queue item');
        
        // Verify last viewed date updated but multiplier not set
        NBA_Queue__c beforeAccept = [SELECT Id, Last_Viewed_Date__c, Priority_Multiplier_Applied__c FROM NBA_Queue__c WHERE Id = :servedItem.Id];
        System.assertNotEquals(null, beforeAccept.Last_Viewed_Date__c, 'Last viewed date should be set');
        System.assertEquals(null, beforeAccept.Priority_Multiplier_Applied__c, 'Multiplier should not be set yet');
        
        // Now accept the action (should NOT set the multiplier yet)
        String taskId = NBAQueueManager.acceptAction(servedItem.Id, 'Test notes');
        
        // Verify multiplier was NOT set when action was accepted
        NBA_Queue__c afterAccept = [SELECT Id, Priority_Multiplier_Applied__c, Status__c FROM NBA_Queue__c WHERE Id = :servedItem.Id];
        System.assertEquals(null, afterAccept.Priority_Multiplier_Applied__c, 'Multiplier should not be set when action is accepted');
        System.assertEquals('In Progress', afterAccept.Status__c, 'Status should be In Progress');
        
        // Now complete the action (should set the multiplier)
        NBAQueueManager.updateCallDispositionWithQueueId(taskId, servedItem.Id, 'Connected - DM', 'Test call notes');
        Test.stopTest();
        
        // Verify multiplier was set when action was completed
        NBA_Queue__c afterComplete = [SELECT Id, Priority_Multiplier_Applied__c, Status__c FROM NBA_Queue__c WHERE Id = :servedItem.Id];
        System.assert(afterComplete.Priority_Multiplier_Applied__c.contains('Web Usage (1.25x)'), 'Should set multiplier when action is completed');
        System.assertEquals('Accepted', afterComplete.Status__c, 'Status should be Accepted');
    }
    
    @isTest
    static void testInProgressItemsNotAffectedByExclusionLogic() {
        User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity WHERE AccountId = :acct.Id LIMIT 1];
        
        // Create an NBA Queue item that's In Progress
        NBA_Queue__c inProgressItem = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 100,
            Subject__c = 'NBA: Call - In Progress Test',
            Status__c = 'In Progress',
            Sales_Rep__c = salesRep.Id,
            Opportunity__c = opp.Id
        );
        insert inProgressItem;
        
        Test.startTest();
        // Update the opportunity to trigger exclusion logic (set last call to today)
        opp.Last_Call_Date_Time__c = DateTime.now();
        update opp;
        
        // Try to get the next queue item - the In Progress item should still be returned
        // even though the opportunity now has a last call date of today
        NBA_Queue__c returnedItem = NBAQueueManager.getNextQueueItem(salesRep.Id);
        Test.stopTest();
        
        // The In Progress item should still be available despite the exclusion logic
        System.assertNotEquals(null, returnedItem, 'In Progress item should not be excluded by opportunity updates');
        System.assertEquals(inProgressItem.Id, returnedItem.Id, 'Should return the In Progress item');
        System.assertEquals('In Progress', returnedItem.Status__c, 'Item should remain In Progress');
    }

	// New: Event blocking logic tests
	@isTest
	static void testEventBlockingSkipsFutureEvent() {
		User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
		Account acct = [SELECT Id FROM Account LIMIT 1];

		// Create a new Opp and NBA item that should be blocked by a future Event (> 15 min)
		Opportunity oppFuture = new Opportunity(
			Name = 'Opp - Future Event',
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(10),
			AccountId = acct.Id,
			OwnerId = salesRep.Id,
			Source__c = 'Outbound'
		);
		insert oppFuture;

		NBA_Queue__c blockedItem = new NBA_Queue__c(
			Account__c = acct.Id,
			Action_Type__c = 'Call',
			Priority_Score__c = 100,
			Subject__c = 'NBA: Call - Future Event Block',
			Status__c = 'Pending',
			Sales_Rep__c = salesRep.Id,
			Opportunity__c = oppFuture.Id
		);
		insert blockedItem;

		// Create a future Event > 15 minutes from now
		Datetime startTs = System.now().addHours(3);
		Event ev = new Event(
			Subject = 'Future Meeting',
			StartDateTime = startTs,
			EndDateTime = startTs.addMinutes(30),
			WhatId = oppFuture.Id
		);
		insert ev;

		Test.startTest();
		NBA_Queue__c nextItem = NBAQueueManager.getNextQueueItem(salesRep.Id);
		Test.stopTest();

		// Should not serve the blocked item
		System.assertNotEquals(blockedItem.Id, nextItem.Id, 'Item with future Event >15 min should be skipped');
	}

	@isTest
	static void testEventBlockingAllowsWithin15Min() {
		User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
		Account acct = [SELECT Id FROM Account LIMIT 1];

		Opportunity oppSoon = new Opportunity(
			Name = 'Opp - Event Soon',
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(5),
			AccountId = acct.Id,
			OwnerId = salesRep.Id,
			Source__c = 'Outbound'
		);
		insert oppSoon;

		NBA_Queue__c soonItem = new NBA_Queue__c(
			Account__c = acct.Id,
			Action_Type__c = 'Call',
			Priority_Score__c = 95,
			Subject__c = 'NBA: Call - Event Soon',
			Status__c = 'Pending',
			Sales_Rep__c = salesRep.Id,
			Opportunity__c = oppSoon.Id
		);
		insert soonItem;

		// Event starts within 10 minutes (should be eligible)
		Datetime startTs = System.now().addMinutes(10);
		insert new Event(Subject='Soon Meeting', StartDateTime=startTs, EndDateTime=startTs.addMinutes(30), WhatId=oppSoon.Id);

		Test.startTest();
		NBA_Queue__c nextItem = NBAQueueManager.getNextQueueItem(salesRep.Id);
		Test.stopTest();

		System.assertEquals(soonItem.Id, nextItem.Id, 'Item with event within 15 minutes should be eligible');
	}

	// New: Snooze tests
	@isTest
	static void testSnoozeCallScheduled() {
		NBA_Queue__c item = [SELECT Id FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];
		Datetime scheduled = System.now().addHours(4);
		Test.startTest();
		NBAQueueManager.snoozeQueueItem(item.Id, 'Call Scheduled', scheduled, null);
		Test.stopTest();
		NBA_Queue__c updated = [SELECT Status__c, Snoozed_Until__c FROM NBA_Queue__c WHERE Id = :item.Id];
		System.assertEquals('Snoozed', updated.Status__c);
		System.assertEquals(scheduled.addMinutes(-15), updated.Snoozed_Until__c, 'Should snooze until 15 minutes before scheduled time');
	}

	@isTest
	static void testSnoozeTimeZoneThreeHours() {
		NBA_Queue__c item = [SELECT Id FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];
		Test.startTest();
		NBAQueueManager.snoozeQueueItem(item.Id, 'Time Zone', null, 3);
		Test.stopTest();
		NBA_Queue__c updated = [SELECT Status__c, Snoozed_Until__c FROM NBA_Queue__c WHERE Id = :item.Id];
		System.assertEquals('Snoozed', updated.Status__c);
		System.assert(updated.Snoozed_Until__c >= System.now().addHours(3).addMinutes(-1), 'Snoozed until should be ~3 hours ahead');
	}

	// New: Call time stamps helper
	@isTest
	static void testMarkOpportunityCallTimes() {
		Opportunity opp = [SELECT Id, First_Call_Date_Time__c, Last_Call_Date_Time__c FROM Opportunity LIMIT 1];
		// First invocation
		Test.startTest();
		NBAQueueManager.markOpportunityCallTimes(opp.Id);
		Test.stopTest();
		Opportunity after = [SELECT First_Call_Date_Time__c, Last_Call_Date_Time__c FROM Opportunity WHERE Id = :opp.Id];
		System.assertNotEquals(null, after.Last_Call_Date_Time__c, 'Last call should be set');
		System.assertNotEquals(null, after.First_Call_Date_Time__c, 'First call should be seeded on first run');
		Datetime first = after.First_Call_Date_Time__c;
		// Second invocation (outside a second Test.startTest block)
		NBAQueueManager.markOpportunityCallTimes(opp.Id);
		Opportunity after2 = [SELECT First_Call_Date_Time__c, Last_Call_Date_Time__c FROM Opportunity WHERE Id = :opp.Id];
		System.assertEquals(first, after2.First_Call_Date_Time__c, 'First call should not change once set');
	}

	// New: Next steps + stage write-back
	@isTest
	static void testSaveNextStepsAndStage() {
		NBA_Queue__c item = [SELECT Id, Opportunity__c FROM NBA_Queue__c WHERE Status__c != 'Dismissed' LIMIT 1];
		Date nextDate = Date.today().addDays(5);
		String steps = 'Send follow-up proposal';
		String stage = 'Proposal/Price Quote';
		Test.startTest();
		NBAQueueManager.saveNextSteps(item.Id, nextDate, steps, stage);
		Test.stopTest();
		NBA_Queue__c qi = [SELECT Next_Step_Date__c, Next_Steps__c FROM NBA_Queue__c WHERE Id = :item.Id];
		System.assertEquals(nextDate, qi.Next_Step_Date__c);
		System.assertEquals(steps, qi.Next_Steps__c);
		Opportunity opp = [SELECT NextStep, StageName FROM Opportunity WHERE Id = :item.Opportunity__c];
		System.assertEquals(steps, opp.NextStep);
		System.assertEquals(stage, opp.StageName);
	}

	// New: Email send sets Accepted
	@isTest
	static void testSendQueueEmailSetsAccepted() {
		NBA_Queue__c item = [SELECT Id, Status__c, Account__c, Opportunity__c FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];
		String toAddr = 'test@example.com';
		Test.startTest();
		NBAQueueManager.sendQueueEmail(item.Id, toAddr, 'Subject', '<p>Body</p>');
		Test.stopTest();
		NBA_Queue__c updated = [SELECT Status__c FROM NBA_Queue__c WHERE Id = :item.Id];
		System.assertEquals('Accepted', updated.Status__c, 'Email send should mark item Accepted');
	}

	@isTest
	static void testListNotSurfacedItemsReturnsPayrollReason() {
		User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
		// Create an account in a blocked payroll status
		Account acct = new Account(Name='NS Payroll Pending Acct', Payroll_Status__c='Pending');
		insert acct;
		// Create a pending NBA item for this user and account
		NBA_Queue__c ns = new NBA_Queue__c(
			Account__c = acct.Id,
			Action_Type__c = 'Call',
			Priority_Score__c = 10,
			Subject__c = 'NS Payroll Pending',
			Status__c = 'Pending',
			Sales_Rep__c = salesRep.Id
		);
		insert ns;
		Test.startTest();
		List<Map<String, Object>> rows = NBAQueueManager.listNotSurfacedItems(salesRep.Id, 25);
		Test.stopTest();
		Boolean found = false;
		for (Map<String, Object> r : rows) {
			if ((String)r.get('subject') == 'NS Payroll Pending') {
				found = true;
				System.assertNotEquals(null, r.get('reason'), 'Reason should be populated');
			}
		}
		System.assert(found, 'Should include the not-surfaced item with a reason');
	}

	// New coverage for helper methods added during Mogli integration
	@isTest
	static void testGetAccountIdForOpportunity() {
		Opportunity opp = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
		Test.startTest();
		Id accId = NBAQueueManager.getAccountIdForOpportunity(opp.Id);
		Test.stopTest();
		System.assertEquals(opp.AccountId, accId, 'Should return the AccountId for the Opportunity');
	}

	@isTest
	static void testGetQueueBestPerson() {
		// Create a contact and queue item with Best_Person_to_Call__c
		Account acct = new Account(Name='Best Person Test');
		insert acct;
		Contact c = new Contact(FirstName='Best', LastName='Person', AccountId=acct.Id);
		insert c;
		User salesRep = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
		NBA_Queue__c qi = new NBA_Queue__c(
			Account__c = acct.Id,
			Action_Type__c = 'Call',
			Priority_Score__c = 10,
			Subject__c = 'Has Best Person',
			Status__c = 'Pending',
			Sales_Rep__c = salesRep.Id,
			Best_Person_to_Call__c = c.Id
		);
		insert qi;

		Test.startTest();
		Id best = NBAQueueManager.getQueueBestPerson(qi.Id);
		Test.stopTest();
		System.assertEquals(c.Id, best, 'Should return Best_Person_to_Call__c value');
	}
    @isTest
    static void testGetLeadStatusNamesNotEmpty() {
        Test.startTest();
        List<String> statuses = NBAQueueManager.getLeadStatusNames();
        Test.stopTest();
        System.assert(statuses != null, 'Lead status list should not be null');
    }

    @isTest
    static void testSaveFutureFollowUpSetsStageAndFields() {
        User rep = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        Account a = new Account(Name='FFU A'); insert a;
        Opportunity o = new Opportunity(Name='FFU Opp', StageName='Qualification', CloseDate=Date.today().addDays(10), AccountId=a.Id, OwnerId=rep.Id, Source__c='Outbound');
        insert o;
        NBA_Queue__c qi = new NBA_Queue__c(Account__c=a.Id, Action_Type__c='Call', Priority_Score__c=10, Subject__c='FFU', Status__c='Pending', Sales_Rep__c=rep.Id, Opportunity__c=o.Id);
        insert qi;

        Date ffuDate = Date.today().addDays(30);
        String ffuReason = 'Call back next month';
        Test.startTest();
        NBAQueueManager.saveFutureFollowUp(qi.Id, ffuDate, ffuReason);
        Test.stopTest();
        Opportunity after = [SELECT StageName, Future_Follow_Up_Date__c, Future_Follow_Up_Reason__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(ffuDate, after.Future_Follow_Up_Date__c);
        System.assertEquals(ffuReason, after.Future_Follow_Up_Reason__c);
        System.assert(after.StageName != null, 'Stage should be non-null');
    }

    @isTest
    static void testGetFutureFollowUpReasonsDoesNotError() {
        Test.startTest();
        List<String> reasons = NBAQueueManager.getFutureFollowUpReasons();
        Test.stopTest();
        System.assert(reasons != null, 'Should return a list (possibly empty)');
    }

    @isTest
    static void testLeadOnlyAcceptAndSaveNextSteps() {
        User rep = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        Lead l = new Lead(FirstName='Lead', LastName='Only', Company='ACME', Phone='1112223333', Status='Open - Not Contacted');
        insert l;
        NBA_Queue__c qi = new NBA_Queue__c(Action_Type__c='Call', Priority_Score__c=77, Subject__c='Lead Action', Status__c='Pending', Sales_Rep__c=rep.Id, Lead__c=l.Id);
        insert qi;

        Test.startTest();
        String taskId = NBAQueueManager.acceptAction(qi.Id, 'Lead notes');
        Test.stopTest();
        Task t = [SELECT Id, WhoId, WhatId, ActivityDate FROM Task WHERE Id = :taskId];
        System.assertEquals(l.Id, t.WhoId, 'WhoId should be Lead');
        System.assertEquals(null, t.WhatId, 'WhatId should be null for Lead');
        System.assertEquals(Date.today(), t.ActivityDate, 'ActivityDate should be today');

        Date nextDate = Date.today().addDays(2);
        Test.startTest();
        NBAQueueManager.saveNextStepsWithLead(qi.Id, nextDate, 'Follow up lead', null, 'Working - Contacted');
        Test.stopTest();
        Lead afterLead = [SELECT Status, Next_Step__c, Next_Step_Date__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Working - Contacted', afterLead.Status);
        System.assertEquals('Follow up lead', afterLead.Next_Step__c);
        System.assertEquals(nextDate, afterLead.Next_Step_Date__c);
    }

    @isTest
    static void testGetActivitiesForOpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        insert new Task(Subject='Past Task', WhatId=opp.Id, Status='Completed', ActivityDate=Date.today().addDays(-1));
        insert new Task(Subject='Upcoming Task', WhatId=opp.Id, Status='Not Started', ActivityDate=Date.today().addDays(1));
        Datetime startTs = System.now().addDays(1);
        insert new Event(Subject='Upcoming Event', WhatId=opp.Id, StartDateTime=startTs, EndDateTime=startTs.addHours(1));

        Test.startTest();
        Map<String, List<Map<String, Object>>> act = NBAQueueManager.getActivities(opp.Id);
        Test.stopTest();
        System.assert(act != null && act.containsKey('upcoming') && act.containsKey('past'), 'Should return upcoming and past');
    }
}