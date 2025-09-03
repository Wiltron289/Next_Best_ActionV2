// Schedule the daily Talkdesk reconcile backfill at 2:00 AM org time
String jobName = 'Talkdesk_Reconcile_Daily_Backfill';
String cron = '0 0 2 * * ?'; // 2:00 AM daily

// Unschedule any prior job with the same name
for (CronTrigger ct : [SELECT Id, State, CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name = :jobName]) {
    System.abortJob(ct.Id);
}

System.schedule(jobName, cron, new TalkdeskReconcileDailyBackfill());
System.debug('Scheduled ' + jobName + ' with cron: ' + cron);
