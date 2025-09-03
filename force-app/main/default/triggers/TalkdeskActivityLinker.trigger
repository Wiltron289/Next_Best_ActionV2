trigger TalkdeskActivityLinker on talkdesk__Talkdesk_Activity__c (after insert) {
    // Collect candidate phone numbers from inserted activities
    Set<String> phones = new Set<String>();
    for (talkdesk__Talkdesk_Activity__c tda : Trigger.new) {
        if (tda.talkdesk__Talkdesk_Activity_Type__c == 'Interaction' 
            && String.isNotBlank(tda.talkdesk__Contact_Phone__c)) {
            String digits = tda.talkdesk__Contact_Phone__c.replaceAll('[^0-9]', '');
            if (digits.length() == 10) digits = '1' + digits;
            phones.add('+' + digits);
        }
    }
    if (phones.isEmpty()) return;

    // Load allowed user ids (active Sales/System role), reduce scope
    Set<Id> allowedUserIds = TalkdeskAllowedUserRefresher.getAllowedUserIds();

    // Only link to queue items completed within the last 20 minutes
    Datetime fortyMinutesAgo = System.now().addMinutes(-40);

    // Query NBA Queue records completed recently with matching Number_Dialed__c
    Map<String, List<NBA_Queue__c>> phoneToQueues = new Map<String, List<NBA_Queue__c>>();
    List<NBA_Queue__c> qes;
    if (allowedUserIds == null || allowedUserIds.isEmpty()) {
        qes = [
            SELECT Id, Number_Dialed__c, Completed_Date__c, Talkdesk_Activity__c, Sales_Rep__c
            FROM NBA_Queue__c
            WHERE Completed_Date__c != null AND Completed_Date__c >= :fortyMinutesAgo
              AND Number_Dialed__c IN :phones
              AND Talkdesk_Activity__c = null
        ];
    } else {
        qes = [
            SELECT Id, Number_Dialed__c, Completed_Date__c, Talkdesk_Activity__c, Sales_Rep__c
            FROM NBA_Queue__c
            WHERE Completed_Date__c != null AND Completed_Date__c >= :fortyMinutesAgo
              AND Number_Dialed__c IN :phones
              AND Talkdesk_Activity__c = null
              AND Sales_Rep__c IN :allowedUserIds
        ];
    }
    for (NBA_Queue__c q : qes) {
        List<NBA_Queue__c> listForPhone = phoneToQueues.get(q.Number_Dialed__c);
        if (listForPhone == null) {
            listForPhone = new List<NBA_Queue__c>();
            phoneToQueues.put(q.Number_Dialed__c, listForPhone);
        }
        listForPhone.add(q);
    }

    if (phoneToQueues.isEmpty()) return;

    List<NBA_Queue__c> updates = new List<NBA_Queue__c>();
    for (talkdesk__Talkdesk_Activity__c tda : Trigger.new) {
        if (tda.talkdesk__Talkdesk_Activity_Type__c != 'Interaction' || String.isBlank(tda.talkdesk__Contact_Phone__c)) continue;
        String digits = tda.talkdesk__Contact_Phone__c.replaceAll('[^0-9]', '');
        if (digits.length() == 10) digits = '1' + digits;
        String e164 = '+' + digits;
        List<NBA_Queue__c> candidates = phoneToQueues.get(e164);
        if (candidates == null || candidates.isEmpty()) continue;
        for (NBA_Queue__c q : candidates) {
            if (q.Sales_Rep__c == tda.talkdesk__User__c) {
                updates.add(new NBA_Queue__c(Id = q.Id, Talkdesk_Activity__c = tda.Id));
                break; // link one per activity
            }
        }
    }
    if (!updates.isEmpty()) update updates;

    // Fallback: enqueue reconcile for recent phone(s) if we had interaction inserts
    try {
        List<Id> recentQueueIds = new List<Id>();
        if (!phoneToQueues.isEmpty()) {
            // gather up to 50 recent queue ids to minimize load
            for (List<NBA_Queue__c> listForPhone : phoneToQueues.values()) {
                for (NBA_Queue__c q : listForPhone) {
                    if (recentQueueIds.size() >= 50) break;
                    recentQueueIds.add(q.Id);
                }
                if (recentQueueIds.size() >= 50) break;
            }
        }
        if (!recentQueueIds.isEmpty()) System.enqueueJob(new TalkdeskReconcileDailyBackfill.ReconcileChunk(recentQueueIds));
    } catch (Exception e) {
        // best effort only
    }
}


