// Abort scheduled CronTriggers and queued async jobs for NBA Queue components
Set<String> jobNames = new Set<String>{
    'Talkdesk Allowed User Refresh',
    'Talkdesk_Reconcile_Daily_Backfill',
    'NBA Queue Manager',
    'TalkdeskActivityLinker',
    'Talkdesk Reconcile Daily Backfill'
};

// Abort CronTriggers by name
for (CronTrigger ct : [SELECT Id, State, CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name IN :jobNames]) {
    try {
        System.abortJob(ct.Id);
        System.debug('Aborted CronTrigger: ' + ct.CronJobDetail.Name + ' (' + ct.Id + ')');
    } catch (Exception e) {
        System.debug('Failed to abort CronTrigger ' + ct.Id + ': ' + e.getMessage());
    }
}

// Abort any queued/processing AsyncApexJob for our classes
Set<String> classNames = new Set<String>{
    'TalkdeskAllowedUserRefresher',
    'TalkdeskReconcileDailyBackfill',
    'TalkdeskReconcileDailyBackfill',
    'NBAQueueManager',
    
};
for (AsyncApexJob j : [SELECT Id, Status, ApexClass.Name FROM AsyncApexJob WHERE Status IN ('Queued','Processing','Preparing') AND ApexClass.Name IN :classNames]) {
    try {
        System.abortJob(j.Id);
        System.debug('Aborted AsyncApexJob for class ' + j.ApexClass.Name + ' (' + j.Id + ')');
    } catch (Exception e) {
        System.debug('Failed to abort AsyncApexJob ' + j.Id + ': ' + e.getMessage());
    }
}
