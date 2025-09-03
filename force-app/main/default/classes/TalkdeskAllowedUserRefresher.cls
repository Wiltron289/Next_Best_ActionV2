public with sharing class TalkdeskAllowedUserRefresher implements Schedulable {
    public void execute(SchedulableContext sc) {
        refresh();
    }

    @AuraEnabled
    public static void refresh() {
        // Build allowlist: active users with role name containing Sales or System
        Set<Id> allowed = new Set<Id>();
        for (User u : [SELECT Id, IsActive, UserRole.Name FROM User WHERE IsActive = true AND UserRoleId != null]) {
            String rn = u.UserRole != null ? u.UserRole.Name : null;
            if (rn == null) continue;
            String rl = rn.toLowerCase();
            if (rl.contains('sales') || rl.contains('system')) {
                allowed.add(u.Id);
            }
        }
        // Wipe and repopulate the List Custom Setting
        delete [SELECT Id FROM Allowed_Talkdesk_User__c];
        if (!allowed.isEmpty()) {
            List<Allowed_Talkdesk_User__c> rows = new List<Allowed_Talkdesk_User__c>();
            for (Id uid : allowed) {
                Allowed_Talkdesk_User__c row = new Allowed_Talkdesk_User__c();
                row.SetupOwnerId = UserInfo.getOrganizationId();
                row.Name = String.valueOf(uid);
                row.UserId__c = String.valueOf(uid);
                rows.add(row);
            }
            insert rows;
        }
    }

    public static Set<Id> getAllowedUserIds() {
        Set<Id> out = new Set<Id>();
        for (Allowed_Talkdesk_User__c row : [SELECT UserId__c FROM Allowed_Talkdesk_User__c]) {
            if (row.UserId__c != null) out.add((Id) row.UserId__c);
        }
        return out;
    }
}


