/**
 * Scheduled Apex job that expires Signature_Request__c records
 * whose Token_Expiry__c has passed while still in Pending status.
 *
 * Schedule: Daily at 01:00 AM org time (see scheduleDaily()).
 *
 * Bulkification:
 *  - Processes up to 200 records per execution (SOQL LIMIT in selector).
 *  - Uses a single update DML and a single bulk audit insert.
 *  - If more than 200 records need expiry, the next daily run handles them.
 *    For orgs with high volume, lower the schedule interval or chain jobs.
 *
 * Deployment:
 *  Execute in Developer Console after deployment:
 *    ESignExpiryScheduler.scheduleDaily();
 */
public class ESignExpiryScheduler implements Schedulable {

    // ─────────────────────────────────────────────────────────────────────────
    // EXECUTE
    // ─────────────────────────────────────────────────────────────────────────

    public void execute(SchedulableContext ctx) {
        List<Signature_Request__c> toExpire = ESignRequestSelector.findExpiredPending();

        if (toExpire.isEmpty()) return;

        // Collect audit events first (before update clears values we need)
        List<Signature_Audit__c> auditEvents = new List<Signature_Audit__c>();

        for (Signature_Request__c req : toExpire) {
            req.Status__c = 'Expired';
            auditEvents.add(buildExpiryAudit(req));
        }

        update toExpire;
        ESignAuditService.logBulk(auditEvents);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCHEDULE HELPER
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Schedules this job to run daily at 01:00 AM.
     * Call once after deployment via Execute Anonymous.
     */
    public static String scheduleDaily() {
        // Abort any existing instance first to prevent duplicates
        abortExistingJob('ESign Daily Expiry Job');
        return System.schedule(
            'ESign Daily Expiry Job',
            '0 0 1 * * ?',
            new ESignExpiryScheduler()
        );
    }

    /**
     * Schedules for test/sandbox use with an immediate 1-minute delay.
     */
    public static String scheduleForTesting() {
        Datetime nextMinute = Datetime.now().addMinutes(1);
        String cron = nextMinute.second() + ' '
                    + nextMinute.minute() + ' '
                    + nextMinute.hour()   + ' '
                    + nextMinute.day()    + ' '
                    + nextMinute.month()  + ' ? '
                    + nextMinute.year();
        return System.schedule('ESign Expiry Job - Test', cron, new ESignExpiryScheduler());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INTERNAL
    // ─────────────────────────────────────────────────────────────────────────

    private static Signature_Audit__c buildExpiryAudit(Signature_Request__c req) {
        return new Signature_Audit__c(
            Signature_Request__c = req.Id,
            Event_Type__c        = 'Expired',
            Event_Timestamp__c   = DateTime.now(),
            Actor_Email__c       = req.Recipient_Email__c,
            Token__c             = ESignTokenService.maskToken(req.Secure_Token__c),
            Source_System__c     = 'Scheduler',
            Event_Detail__c      = JSON.serialize(new Map<String, Object>{
                'expiredAt'       => String.valueOf(req.Token_Expiry__c),
                'schedulerRunAt'  => String.valueOf(DateTime.now())
            })
        );
    }

    private static void abortExistingJob(String jobName) {
        List<CronTrigger> existing = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
            AND   State NOT IN ('COMPLETE','DELETED','ERROR')
            LIMIT 5
        ];
        for (CronTrigger ct : existing) {
            System.abortJob(ct.Id);
        }
    }
}
