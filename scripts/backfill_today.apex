// Backfill Talkdesk linking for NBA Queue items completed today
// Enqueues TalkdeskReconcileJob in chunks and stamps enqueue time

List<Id> queueIds = new List<Id>();
for (NBA_Queue__c q : [
    SELECT Id
    FROM NBA_Queue__c
    WHERE Completed_Date__c = TODAY
      AND Number_Dialed__c != null
      AND Talkdesk_Activity__c = null
    ORDER BY Completed_Date__c DESC
]) {
    queueIds.add(q.Id);
}

if (queueIds.isEmpty()) {
    System.debug('No eligible NBA_Queue__c records found for today.');
} else {
    Integer chunkSize = 200;
    Integer maxJobs = 50;
    Integer jobsEnqueued = 0;
    Datetime nowTs = System.now();

    for (Integer i = 0; i < queueIds.size(); i += chunkSize) {
        if (jobsEnqueued >= maxJobs) break;
        Integer endIdx = Math.min(i + chunkSize, queueIds.size());
        List<Id> sub = new List<Id>();
        for (Integer j = i; j < endIdx; j++) {
            sub.add(queueIds[j]);
        }

        try {
            List<NBA_Queue__c> stamps = new List<NBA_Queue__c>();
            for (Id idVal : sub) stamps.add(new NBA_Queue__c(Id = idVal, Last_Reconcile_Enqueue__c = nowTs));
            if (!stamps.isEmpty()) update stamps;
        } catch (Exception e) {}

        System.enqueueJob(new TalkdeskReconcileDailyBackfill.ReconcileChunk(sub));
        jobsEnqueued++;
    }
    System.debug('Backfill enqueued jobs: ' + jobsEnqueued + ', total records considered: ' + queueIds.size());
}
