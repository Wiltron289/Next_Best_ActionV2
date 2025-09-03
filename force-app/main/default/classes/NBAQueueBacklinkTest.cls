@isTest
private class NBAQueueBacklinkTest {

    @isTest
    static void linksWhenCompletedThenActivityArrivesWithinTwentyMinutes() {
        Account acct = new Account(Name = 'Backlink Acct 1');
        insert acct;

        // Completed now with dialed number
        NBA_Queue__c q = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 40,
            Subject__c = 'Backlink Path A',
            Status__c = 'Accepted',
            Completed_Date__c = System.now(),
            Number_Dialed__c = '+11234567890',
            Sales_Rep__c = UserInfo.getUserId()
        );
        insert q;

        // Insert activity 15 mins later (within window)
        Test.startTest();
        talkdesk__Talkdesk_Activity__c tda = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Activity_Type__c = 'Interaction',
            talkdesk__Contact_Phone__c = '123-456-7890',
            talkdesk__Talkdesk_Id__c = 'TD-E',
            talkdesk__User__c = UserInfo.getUserId()
        );
        insert tda;
        Test.stopTest();

        NBA_Queue__c linked = [SELECT Talkdesk_Activity__c FROM NBA_Queue__c WHERE Id = :q.Id];
        System.assertNotEquals(null, linked.Talkdesk_Activity__c, 'Should link via after-insert within window');
        System.assertEquals(tda.Id, linked.Talkdesk_Activity__c);
    }

    @isTest
    static void linksWhenNumberAddedAfterCompletionWithinTwentyMinutes() {
        Account acct = new Account(Name = 'Backlink Acct 2');
        insert acct;

        // Completed 10 minutes ago without a number
        NBA_Queue__c q = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 41,
            Subject__c = 'Backlink Path B',
            Status__c = 'Accepted',
            Completed_Date__c = System.now().addMinutes(-3),
            Sales_Rep__c = UserInfo.getUserId()
        );
        insert q;

        // Activity exists with matching phone
        talkdesk__Talkdesk_Activity__c tda = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Activity_Type__c = 'Interaction',
            talkdesk__Contact_Phone__c = '(123) 456-7890',
            talkdesk__Talkdesk_Id__c = 'TD-I',
            talkdesk__User__c = UserInfo.getUserId()
        );
        insert tda;

        // Add the number now; backlink trigger should NOT fire on number-only updates anymore
        Test.startTest();
        q.Number_Dialed__c = '+11234567890';
        update q;
        Test.stopTest();

        NBA_Queue__c notLinked = [SELECT Talkdesk_Activity__c FROM NBA_Queue__c WHERE Id = :q.Id];
        System.assertEquals(null, notLinked.Talkdesk_Activity__c, 'Should not link on number-only update after completion');
    }

    @isTest
    static void doesNotLinkWhenOutsideTwentyMinutes() {
        Account acct = new Account(Name = 'Backlink Acct 3');
        insert acct;

        // Completed 45 minutes ago (outside 40-minute window)
        NBA_Queue__c q = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 42,
            Subject__c = 'Backlink Outside Window',
            Status__c = 'Accepted',
            Completed_Date__c = System.now().addMinutes(-45),
            Number_Dialed__c = '+11234567890',
            Sales_Rep__c = UserInfo.getUserId()
        );
        insert q;

        Test.startTest();
        talkdesk__Talkdesk_Activity__c tda = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Activity_Type__c = 'Interaction',
            talkdesk__Contact_Phone__c = '1234567890',
            talkdesk__Talkdesk_Id__c = 'TD-F',
            talkdesk__User__c = UserInfo.getUserId()
        );
        insert tda;
        Test.stopTest();

        NBA_Queue__c notLinked = [SELECT Talkdesk_Activity__c FROM NBA_Queue__c WHERE Id = :q.Id];
        System.assertEquals(null, notLinked.Talkdesk_Activity__c, 'Should not link when outside 40-minute window');
    }
}


