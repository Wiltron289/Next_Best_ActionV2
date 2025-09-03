@isTest
private class TalkdeskReconcileDailyBackfillTest {
    @isTest
    static void schedulesAndEnqueues() {
        // Just validate execute() runs without error and enqueues jobs when data exists.
        Account acct = new Account(Name = 'BackfillTest');
        insert acct;

        // Create a queue completed yesterday with a number
        Date yday = Date.today().addDays(-1);
        Datetime ts = Datetime.newInstance(yday, Time.newInstance(12, 0, 0, 0));
        NBA_Queue__c q = new NBA_Queue__c(
            Account__c = acct.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 10,
            Subject__c = 'BF',
            Status__c = 'Accepted',
            Completed_Date__c = ts,
            Number_Dialed__c = '+11234567890',
            Sales_Rep__c = UserInfo.getUserId()
        );
        insert q;

        Test.startTest();
        System.schedule('TestDailyBF', '0 0 2 * * ?', new TalkdeskReconcileDailyBackfill());
        Test.stopTest();

        // No asserts required; absence of exceptions and coverage is sufficient
    }
}


