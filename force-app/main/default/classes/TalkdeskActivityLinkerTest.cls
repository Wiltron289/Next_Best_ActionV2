@isTest
private class TalkdeskActivityLinkerTest {

    @isTest
    static void linksInteractionByPhoneWithinHour() {
        // Arrange: create minimal data
        Account acct = new Account(Name = 'TD Test Acct');
        insert acct;

        // Create a recently completed NBA Queue item with a normalized dialed number
        NBA_Queue__c q = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 50,
            Subject__c = 'NBA: Call - TD Link',
            Status__c = 'Accepted',
            Completed_Date__c = System.now(),
            Number_Dialed__c = '+11234567890',
            Sales_Rep__c = UserInfo.getUserId()
        );
        insert q;

        // Act: insert a Talkdesk Activity with the same phone (unformatted)
        talkdesk__Talkdesk_Activity__c tda = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Activity_Type__c = 'Interaction',
            talkdesk__Contact_Phone__c = '(123) 456-7890',
            talkdesk__Talkdesk_Id__c = 'TD-A',
            talkdesk__User__c = UserInfo.getUserId()
        );
        Test.startTest();
        insert tda;
        Test.stopTest();

        // Assert: queue record is linked to the new Talkdesk Activity
        NBA_Queue__c linked = [SELECT Talkdesk_Activity__c FROM NBA_Queue__c WHERE Id = :q.Id];
        System.assertEquals(tda.Id, linked.Talkdesk_Activity__c, 'Should link the Talkdesk Activity created within 1 hour by phone');
    }

    @isTest
    static void doesNotLinkIfOlderThanOneHour() {
        Account acct = new Account(Name = 'TD Test Acct 2');
        insert acct;

        // Queue item completed > 1 hour ago should not link
        NBA_Queue__c qOld = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 60,
            Subject__c = 'NBA: Call - Old',
            Status__c = 'Accepted',
            Completed_Date__c = System.now().addHours(-2),
            Number_Dialed__c = '+11234567890',
            Sales_Rep__c = UserInfo.getUserId()
        );
        insert qOld;

        talkdesk__Talkdesk_Activity__c tda = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Activity_Type__c = 'Interaction',
            talkdesk__Contact_Phone__c = '123-456-7890',
            talkdesk__Talkdesk_Id__c = 'TD-B',
            talkdesk__User__c = UserInfo.getUserId()
        );
        Test.startTest();
        insert tda;
        Test.stopTest();

        NBA_Queue__c notLinked = [SELECT Talkdesk_Activity__c FROM NBA_Queue__c WHERE Id = :qOld.Id];
        System.assertEquals(null, notLinked.Talkdesk_Activity__c, 'Should not link when queue item completed well beyond window (older than 1 hour)');
    }

    @isTest
    static void linksWhenQueueCompletesAfterActivityExists() {
        Account acct = new Account(Name = 'TD Test Acct 3');
        insert acct;

        // Queue item initially not completed
        NBA_Queue__c q = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 70,
            Subject__c = 'NBA: Call - Backlink',
            Status__c = 'Pending',
            Number_Dialed__c = '+11234567890',
            Sales_Rep__c = UserInfo.getUserId()
        );
        insert q;

        // Activity arrives first
        talkdesk__Talkdesk_Activity__c tda = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Activity_Type__c = 'Interaction',
            talkdesk__Contact_Phone__c = '123-456-7890',
            talkdesk__Talkdesk_Id__c = 'TD-C',
            talkdesk__User__c = UserInfo.getUserId()
        );
        insert tda;

        // Now complete the queue item (fires after update trigger)
        q.Status__c = 'Accepted';
        q.Completed_Date__c = System.now();
        Test.startTest();
        update q;
        Test.stopTest();

        NBA_Queue__c linked = [SELECT Talkdesk_Activity__c FROM NBA_Queue__c WHERE Id = :q.Id];
        System.assertEquals(tda.Id, linked.Talkdesk_Activity__c, 'Should link when queue completes after activity exists');
    }

    @isTest
    static void linksWithinTwentyMinutesWindow() {
        Account acct = new Account(Name = 'TD Test Acct 4');
        insert acct;

        // Queue completed 19 minutes ago (within 20-minute window)
        NBA_Queue__c q = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 55,
            Subject__c = 'NBA: Call - Ten Minute Window',
            Status__c = 'Accepted',
            Completed_Date__c = System.now().addMinutes(-19),
            Number_Dialed__c = '+11234567890',
            Sales_Rep__c = UserInfo.getUserId()
        );
        insert q;

        talkdesk__Talkdesk_Activity__c tda = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Activity_Type__c = 'Interaction',
            talkdesk__Contact_Phone__c = '1234567890',
            talkdesk__Talkdesk_Id__c = 'TD-D',
            talkdesk__User__c = UserInfo.getUserId()
        );
        Test.startTest();
        insert tda;
        Test.stopTest();

        NBA_Queue__c linked = [SELECT Talkdesk_Activity__c FROM NBA_Queue__c WHERE Id = :q.Id];
        System.assertEquals(tda.Id, linked.Talkdesk_Activity__c, 'Should link when activity is within 20 minutes of completion');
    }

    @isTest
    static void doesNotLinkIfPastTwentyMinutesWindow() {
        Account acct = new Account(Name = 'TD Test Acct 5');
        insert acct;

        // Queue completed 41 minutes ago (outside 40-minute window)
        NBA_Queue__c q = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 65,
            Subject__c = 'NBA: Call - Past Window',
            Status__c = 'Accepted',
            Completed_Date__c = System.now().addMinutes(-41),
            Number_Dialed__c = '+11234567890',
            Sales_Rep__c = UserInfo.getUserId()
        );
        insert q;

        talkdesk__Talkdesk_Activity__c tda = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Activity_Type__c = 'Interaction',
            talkdesk__Contact_Phone__c = '(123) 456-7890',
            talkdesk__Talkdesk_Id__c = 'TD-G',
            talkdesk__User__c = UserInfo.getUserId()
        );
        Test.startTest();
        insert tda;
        Test.stopTest();

        NBA_Queue__c notLinked = [SELECT Talkdesk_Activity__c FROM NBA_Queue__c WHERE Id = :q.Id];
        System.assertEquals(null, notLinked.Talkdesk_Activity__c, 'Should not link when activity is outside 40-minute window');
    }

    @isTest
    static void doesNotLinkWhenNumberAddedAfterCompletion() {
        Account acct = new Account(Name = 'TD Test Acct 6');
        insert acct;

        // Queue completed 5 minutes ago, without a dialed number initially
        NBA_Queue__c q = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 75,
            Subject__c = 'NBA: Call - Number Added Post Completion',
            Status__c = 'Accepted',
            Completed_Date__c = System.now().addMinutes(-5),
            Sales_Rep__c = UserInfo.getUserId()
        );
        insert q;

        // Activity already exists within the window
        talkdesk__Talkdesk_Activity__c tda = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Activity_Type__c = 'Interaction',
            talkdesk__Contact_Phone__c = '123-456-7890',
            talkdesk__Talkdesk_Id__c = 'TD-H',
            talkdesk__User__c = UserInfo.getUserId()
        );
        insert tda;

        // Now set the dialed number; backlink trigger no longer fires on number-only update
        q.Number_Dialed__c = '+11234567890';
        Test.startTest();
        update q;
        Test.stopTest();

        NBA_Queue__c notLinked = [SELECT Talkdesk_Activity__c FROM NBA_Queue__c WHERE Id = :q.Id];
        System.assertEquals(null, notLinked.Talkdesk_Activity__c, 'Should not link on number-only update after completion');
    }
}


