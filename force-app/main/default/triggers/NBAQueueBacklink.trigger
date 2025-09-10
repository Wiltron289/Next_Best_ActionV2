trigger NBAQueueBacklink on NBA_Queue__c (after update) {
    // Identify queue items that just got completed (Completed_Date__c transitioned from null to value)
    // Only act at completion time; ignore subsequent Number_Dialed__c changes
    List<NBA_Queue__c> justCompleted = new List<NBA_Queue__c>();
    for (Integer i = 0; i < Trigger.new.size(); i++) {
        NBA_Queue__c newRec = Trigger.new[i];
        NBA_Queue__c oldRec = Trigger.old[i];
        Boolean completedNow = (newRec.Completed_Date__c != null && oldRec.Completed_Date__c == null);
        if (completedNow && newRec.Talkdesk_Activity__c == null && String.isNotBlank(newRec.Number_Dialed__c)) {
            justCompleted.add(newRec);
        }
    }

    if (justCompleted.isEmpty()) return;

    // Build normalized phone map and compute a time window spanning the batch
    Set<String> dialedSet = new Set<String>();
    Map<String, List<NBA_Queue__c>> phoneToQueues = new Map<String, List<NBA_Queue__c>>();
    Datetime minCompleted = null;
    Datetime maxCompletedPlusWindow = null;

    for (NBA_Queue__c q : justCompleted) {
        String digits = q.Number_Dialed__c == null ? null : q.Number_Dialed__c.replaceAll('[^0-9]', '');
        if (String.isBlank(digits)) continue;
        if (digits.length() == 10) digits = '1' + digits;
        String e164 = '+' + digits;
        dialedSet.add(e164);

        if (!phoneToQueues.containsKey(e164)) phoneToQueues.put(e164, new List<NBA_Queue__c>());
        phoneToQueues.get(e164).add(q);

        if (minCompleted == null || q.Completed_Date__c < minCompleted) {
            minCompleted = q.Completed_Date__c;
        }
        Datetime plusWindow = q.Completed_Date__c.addMinutes(40);
        if (maxCompletedPlusWindow == null || plusWindow > maxCompletedPlusWindow) {
            maxCompletedPlusWindow = plusWindow;
        }
    }

    // Expand the time window to include activities before completion
    if (minCompleted != null) {
        minCompleted = minCompleted.addMinutes(-40);
    }

    if (dialedSet.isEmpty() || minCompleted == null || maxCompletedPlusWindow == null) return;

    // Query Talkdesk activities within the combined time window and build phone map
    Set<Id> allowedUserIds = TalkdeskAllowedUserRefresher.getAllowedUserIds();
    Map<String, List<talkdesk__Talkdesk_Activity__c>> phoneToActivities = new Map<String, List<talkdesk__Talkdesk_Activity__c>>();
    List<talkdesk__Talkdesk_Activity__c> acts;
    if (allowedUserIds == null || allowedUserIds.isEmpty()) {
        acts = [
            SELECT Id, CreatedDate, talkdesk__Contact_Phone__c, talkdesk__Talkdesk_Activity_Type__c, talkdesk__User__c,
                   User_Role_Name__c
            FROM talkdesk__Talkdesk_Activity__c
            WHERE talkdesk__Talkdesk_Activity_Type__c = 'Interaction'
              AND talkdesk__Contact_Phone__c != null
              AND CreatedDate >= :minCompleted
              AND CreatedDate <= :maxCompletedPlusWindow
            ORDER BY CreatedDate DESC
        ];
    } else {
        acts = [
            SELECT Id, CreatedDate, talkdesk__Contact_Phone__c, talkdesk__Talkdesk_Activity_Type__c, talkdesk__User__c,
                   User_Role_Name__c
            FROM talkdesk__Talkdesk_Activity__c
            WHERE talkdesk__Talkdesk_Activity_Type__c = 'Interaction'
              AND talkdesk__Contact_Phone__c != null
              AND CreatedDate >= :minCompleted
              AND CreatedDate <= :maxCompletedPlusWindow
              AND talkdesk__User__c IN :allowedUserIds
            ORDER BY CreatedDate DESC
        ];
    }
    for (talkdesk__Talkdesk_Activity__c tda : acts) {
        // No role formula check; allowlist already enforced above

        String digits = tda.talkdesk__Contact_Phone__c.replaceAll('[^0-9]', '');
        if (digits.length() == 10) digits = '1' + digits;
        String e164 = '+' + digits;
        if (!dialedSet.contains(e164)) continue;
        if (!phoneToActivities.containsKey(e164)) phoneToActivities.put(e164, new List<talkdesk__Talkdesk_Activity__c>());
        phoneToActivities.get(e164).add(tda);
    }

    if (phoneToActivities.isEmpty()) return;

    // For each phone, link the closest activity within 20 minutes after completion; ensure each activity is used once
    List<NBA_Queue__c> toUpdate = new List<NBA_Queue__c>();
    Set<Id> usedActivityIds = new Set<Id>();
    for (String phone : phoneToQueues.keySet()) {
        List<NBA_Queue__c> queues = phoneToQueues.get(phone);
        List<talkdesk__Talkdesk_Activity__c> acts = phoneToActivities.get(phone);
        if (acts == null || acts.isEmpty()) continue;

        for (NBA_Queue__c q : queues) {
            talkdesk__Talkdesk_Activity__c best = null;
            Long bestDelta = 999999999999L;
            Datetime windowStart = q.Completed_Date__c.addMinutes(-40);
            Datetime windowEnd = q.Completed_Date__c.addMinutes(40);
            for (talkdesk__Talkdesk_Activity__c a : acts) {
                if (usedActivityIds.contains(a.Id)) continue;
                if (a.CreatedDate >= windowStart && a.CreatedDate <= windowEnd && a.talkdesk__User__c == q.Sales_Rep__c) {
                    Long delta = a.CreatedDate.getTime() - q.Completed_Date__c.getTime();
                    if (delta < 0) delta = -delta;
                    if (delta < bestDelta) {
                        bestDelta = delta;
                        best = a;
                    }
                }
            }
            if (best != null) {
                toUpdate.add(new NBA_Queue__c(Id = q.Id, Talkdesk_Activity__c = best.Id));
                usedActivityIds.add(best.Id);
            }
        }
    }

    if (!toUpdate.isEmpty()) update toUpdate;

    // Async reconciliation: enqueue a job to re-scan within +/- 20 minutes around completion
    try {
        List<Id> ids = new List<Id>();
        for (NBA_Queue__c q : justCompleted) ids.add(q.Id);
        if (!ids.isEmpty()) {
            System.enqueueJob(new TalkdeskReconcileDailyBackfill.ReconcileChunk(ids));
            try {
                // Stamp enqueue time for visibility
                List<NBA_Queue__c> stamps = new List<NBA_Queue__c>();
                Datetime nowTs = System.now();
                for (Id idVal : ids) stamps.add(new NBA_Queue__c(Id = idVal, Last_Reconcile_Enqueue__c = nowTs));
                update stamps;
            } catch (Exception ignore) {}
        }
    } catch (Exception e) {
        // swallow; best-effort only
    }
}


