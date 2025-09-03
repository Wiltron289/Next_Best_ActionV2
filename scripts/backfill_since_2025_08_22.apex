// Backfill Talkdesk linking for NBA Queue items completed from 2025-08-22 to today (inclusive)
// Enqueues TalkdeskReconcileJob in chunks, capped to 50 jobs per run

Date startDate = Date.newInstance(2025, 8, 22);
Date endDate = Date.today();
Integer totalConsidered = 0;
Integer totalJobs = 0;
Integer maxJobs = 50;
Integer chunkSize = 200;
Datetime nowTs = System.now();

for (Date d = startDate; d <= endDate; d = d.addDays(1)) {
    if (totalJobs >= maxJobs) break;
    Datetime dayStart = Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0));
    Datetime dayEnd = dayStart.addDays(1); // exclusive upper bound

    List<Id> queueIds = new List<Id>();
    for (NBA_Queue__c q : [
        SELECT Id
        FROM NBA_Queue__c
        WHERE Completed_Date__c >= :dayStart AND Completed_Date__c < :dayEnd
          AND Number_Dialed__c != null
          AND Talkdesk_Activity__c = null
        ORDER BY Completed_Date__c DESC
        LIMIT 10000
    ]) {
        queueIds.add(q.Id);
    }
    totalConsidered += queueIds.size();

    for (Integer i = 0; i < queueIds.size(); i += chunkSize) {
        if (totalJobs >= maxJobs) break;
        Integer endIdx = Math.min(i + chunkSize, queueIds.size());
        List<Id> sub = new List<Id>();
        for (Integer j = i; j < endIdx; j++) sub.add(queueIds[j]);
        try {
            List<NBA_Queue__c> stamps = new List<NBA_Queue__c>();
            for (Id idVal : sub) stamps.add(new NBA_Queue__c(Id = idVal, Last_Reconcile_Enqueue__c = nowTs));
            if (!stamps.isEmpty()) update stamps;
        } catch (Exception ignore) {}
        System.enqueueJob(new TalkdeskReconcileDailyBackfill.ReconcileChunk(sub));
        totalJobs++;
    }
}
System.debug('Backfill since 2025-08-22: jobs enqueued=' + totalJobs + ', records considered=' + totalConsidered + ', days processed up to=' + endDate);


