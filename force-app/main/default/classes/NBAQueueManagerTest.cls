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
    static void testMarkAsViewed() {
        NBA_Queue__c item = [SELECT Id FROM NBA_Queue__c WHERE Status__c = 'Pending' LIMIT 1];

        Test.startTest();
        NBAQueueManager.markAsViewed(item.Id);
        Test.stopTest();

        NBA_Queue__c updated = [SELECT First_Viewed_Date__c FROM NBA_Queue__c WHERE Id = :item.Id];
        System.assertNotEquals(null, updated.First_Viewed_Date__c, 'First_Viewed_Date__c should be set');
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
}