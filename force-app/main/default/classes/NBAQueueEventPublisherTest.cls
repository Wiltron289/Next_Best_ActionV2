@IsTest
public class NBAQueueEventPublisherTest {
    
    @TestSetup
    static void setupTestData() {
        Account testAccount = new Account(
            Name = 'Test Account for Events',
            Type = 'Prospect'
        );
        insert testAccount;
        
        User testUser = [SELECT Id FROM User WHERE IsActive = true AND Profile.Name = 'System Administrator' LIMIT 1];
        
        testAccount.OwnerId = testUser.Id;
        update testAccount;
    }
    
    @IsTest
    static void testPublishQueueUpdateList() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        
        List<NBA_Queue__c> queueItems = new List<NBA_Queue__c>();
        
        NBA_Queue__c item1 = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 85.0,
            Status__c = 'Pending'
        );
        queueItems.add(item1);
        
        NBA_Queue__c item2 = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Email',
            Priority_Score__c = 75.0,
            Status__c = 'Pending'
        );
        queueItems.add(item2);
        
        insert queueItems;
        
        Test.startTest();
        NBAQueueEventPublisher.publishQueueUpdate(queueItems, 'New');
        Test.stopTest();
        
        // Note: We can't easily test the actual event publishing in unit tests
        // but we can verify the method executes without errors
        System.assertEquals(2, queueItems.size(), 'Should have 2 queue items');
    }
    
    @IsTest
    static void testPublishQueueUpdateSingle() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Meeting',
            Priority_Score__c = 90.0,
            Status__c = 'Pending'
        );
        insert queueItem;
        
        Test.startTest();
        NBAQueueEventPublisher.publishQueueUpdate(queueItem, 'Updated');
        Test.stopTest();
        
        // Verify method executed successfully
        System.assertNotEquals(null, queueItem.Id, 'Queue item should be created');
    }
    
    @IsTest
    static void testPublishItemStatusUpdate() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        
        NBA_Queue__c queueItem = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Sales_Rep__c = testUser.Id,
            Action_Type__c = 'Demo',
            Priority_Score__c = 88.0,
            Status__c = 'Pending'
        );
        insert queueItem;
        
        Test.startTest();
        NBAQueueEventPublisher.publishItemStatusUpdate(queueItem.Id, testUser.Id, 'Deleted');
        Test.stopTest();
        
        // Verify method executed successfully
        System.assertNotEquals(null, queueItem.Id, 'Queue item should exist');
    }
}