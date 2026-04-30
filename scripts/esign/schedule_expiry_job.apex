/**
 * Execute this in Developer Console → Execute Anonymous
 * after deploying SF-eSign to schedule the nightly expiry job.
 *
 * Run only once per org. The abortExistingJob() call inside
 * ESignExpiryScheduler.scheduleDaily() prevents duplicates.
 */
String jobId = ESignExpiryScheduler.scheduleDaily();
System.debug('ESign expiry job scheduled. CronTrigger Id: ' + jobId);
