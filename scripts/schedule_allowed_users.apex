// One-time refresh and schedule for Talkdesk allowlist
TalkdeskAllowedUserRefresher.refresh();

String jobName = 'Talkdesk Allowed User Refresh';
String cron = '0 0 2 * * ?'; // daily at 2:00 AM org time

// Remove prior job if exists
try {
    CronTrigger ct = [SELECT Id, CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name = :jobName LIMIT 1];
    System.abortJob(ct.Id);
} catch (Exception e) {
    // ignore if not found
}

System.schedule(jobName, cron, new TalkdeskAllowedUserRefresher());


