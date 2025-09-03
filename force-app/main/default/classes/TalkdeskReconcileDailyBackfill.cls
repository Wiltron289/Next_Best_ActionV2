public without sharing class TalkdeskReconcileDailyBackfill implements Schedulable {
    public void execute(SchedulableContext sc) {
        // Find all queues completed YESTERDAY (full day), unlinked, with a dialed number
        Date target = Date.today().addDays(-1);
        Datetime startDt = Datetime.newInstance(target, Time.newInstance(0, 0, 0, 0));
        Datetime endDt = Datetime.newInstance(target, Time.newInstance(23, 59, 59, 999));

        List<Id> queueIds = new List<Id>();
        for (NBA_Queue__c q : [
            SELECT Id
            FROM NBA_Queue__c
            WHERE Completed_Date__c >= :startDt AND Completed_Date__c <= :endDt
              AND Number_Dialed__c != null
              AND Talkdesk_Activity__c = null
            ORDER BY Completed_Date__c DESC
            LIMIT 10000
        ]) {
            queueIds.add(q.Id);
        }

        if (queueIds.isEmpty()) return;

        Integer chunkSize = 200;
        Integer jobsEnqueued = 0;
        Datetime nowTs = System.now();
        for (Integer i = 0; i < queueIds.size(); i += chunkSize) {
            Integer endIdx = Math.min(i + chunkSize, queueIds.size());
            List<Id> sub = new List<Id>();
            for (Integer j = i; j < endIdx; j++) sub.add(queueIds[j]);
            try {
                List<NBA_Queue__c> stamps = new List<NBA_Queue__c>();
                for (Id idVal : sub) stamps.add(new NBA_Queue__c(Id = idVal, Last_Reconcile_Enqueue__c = nowTs));
                if (!stamps.isEmpty()) update stamps;
            } catch (Exception ignore) {}
            System.enqueueJob(new TalkdeskReconcileDailyBackfill.ReconcileChunk(sub));
            jobsEnqueued++;
        }
    }

    public class ReconcileChunk implements Queueable {
        private List<Id> queueIds;

        public ReconcileChunk(List<Id> queueIds) {
            this.queueIds = (queueIds == null) ? new List<Id>() : new List<Id>(queueIds);
        }

        public void execute(QueueableContext qc) {
            if (queueIds.isEmpty()) return;

            List<NBA_Queue__c> queues = [
                SELECT Id, Number_Dialed__c, Completed_Date__c, Sales_Rep__c, Talkdesk_Activity__c
                FROM NBA_Queue__c
                WHERE Id IN :queueIds
            ];
            if (queues.isEmpty()) return;

            Set<String> phones = new Set<String>();
            Map<String, List<NBA_Queue__c>> phoneToQueues = new Map<String, List<NBA_Queue__c>>();
            Datetime minStart = null;
            Datetime maxEnd = null;
            Integer windowMinutes = 40;

            for (NBA_Queue__c q : queues) {
                if (q.Completed_Date__c == null || String.isBlank(q.Number_Dialed__c) || q.Talkdesk_Activity__c != null) continue;
                String digits = q.Number_Dialed__c.replaceAll('[^0-9]', '');
                if (String.isBlank(digits)) continue;
                if (digits.length() == 10) digits = '1' + digits;
                String e164 = '+' + digits;
                phones.add(e164);
                if (!phoneToQueues.containsKey(e164)) phoneToQueues.put(e164, new List<NBA_Queue__c>());
                phoneToQueues.get(e164).add(q);

                Datetime startWindow = q.Completed_Date__c.addMinutes(-windowMinutes);
                Datetime endWindow = q.Completed_Date__c.addMinutes(windowMinutes);
                if (minStart == null || startWindow < minStart) minStart = startWindow;
                if (maxEnd == null || endWindow > maxEnd) maxEnd = endWindow;
            }

            if (phones.isEmpty() || minStart == null || maxEnd == null) return;

            Set<Id> allowedUserIds = TalkdeskAllowedUserRefresher.getAllowedUserIds();

            List<talkdesk__Talkdesk_Activity__c> activities;
            if (allowedUserIds == null || allowedUserIds.isEmpty()) {
                activities = [
                    SELECT Id, CreatedDate, talkdesk__Contact_Phone__c, talkdesk__Talkdesk_Activity_Type__c, talkdesk__User__c
                    FROM talkdesk__Talkdesk_Activity__c
                    WHERE talkdesk__Talkdesk_Activity_Type__c = 'Interaction'
                      AND talkdesk__Contact_Phone__c != null
                      AND CreatedDate >= :minStart
                      AND CreatedDate <= :maxEnd
                    ORDER BY CreatedDate DESC
                ];
            } else {
                activities = [
                    SELECT Id, CreatedDate, talkdesk__Contact_Phone__c, talkdesk__Talkdesk_Activity_Type__c, talkdesk__User__c
                    FROM talkdesk__Talkdesk_Activity__c
                    WHERE talkdesk__Talkdesk_Activity_Type__c = 'Interaction'
                      AND talkdesk__Contact_Phone__c != null
                      AND CreatedDate >= :minStart
                      AND CreatedDate <= :maxEnd
                      AND talkdesk__User__c IN :allowedUserIds
                    ORDER BY CreatedDate DESC
                ];
            }

            if (activities.isEmpty()) return;

            Map<String, List<talkdesk__Talkdesk_Activity__c>> phoneToActivities = new Map<String, List<talkdesk__Talkdesk_Activity__c>>();
            for (talkdesk__Talkdesk_Activity__c a : activities) {
                String digits = a.talkdesk__Contact_Phone__c == null ? null : a.talkdesk__Contact_Phone__c.replaceAll('[^0-9]', '');
                if (String.isBlank(digits)) continue;
                if (digits.length() == 10) digits = '1' + digits;
                String e164 = '+' + digits;
                if (!phones.contains(e164)) continue;
                if (!phoneToActivities.containsKey(e164)) phoneToActivities.put(e164, new List<talkdesk__Talkdesk_Activity__c>());
                phoneToActivities.get(e164).add(a);
            }

            if (phoneToActivities.isEmpty()) return;

            List<NBA_Queue__c> updates = new List<NBA_Queue__c>();
            Set<Id> usedActivityIds = new Set<Id>();
            for (String phone : phoneToQueues.keySet()) {
                List<NBA_Queue__c> qs = phoneToQueues.get(phone);
                List<talkdesk__Talkdesk_Activity__c> actsForPhone = phoneToActivities.get(phone);
                if (actsForPhone == null) continue;
                for (NBA_Queue__c q : qs) {
                    talkdesk__Talkdesk_Activity__c best = null;
                    Long bestDelta = 999999999999L;
                    Datetime winStart = q.Completed_Date__c.addMinutes(-windowMinutes);
                    Datetime winEnd = q.Completed_Date__c.addMinutes(windowMinutes);
                    for (talkdesk__Talkdesk_Activity__c a : actsForPhone) {
                        if (usedActivityIds.contains(a.Id)) continue;
                        if (a.CreatedDate < winStart || a.CreatedDate > winEnd) continue;
                        if (a.talkdesk__User__c != q.Sales_Rep__c) continue;
                        Long delta = Math.abs(a.CreatedDate.getTime() - q.Completed_Date__c.getTime());
                        if (delta < bestDelta) {
                            bestDelta = delta;
                            best = a;
                        }
                    }
                    if (best != null) {
                        updates.add(new NBA_Queue__c(Id = q.Id, Talkdesk_Activity__c = best.Id));
                        usedActivityIds.add(best.Id);
                    }
                }
            }

            if (!updates.isEmpty()) update updates;
        }
    }
}

