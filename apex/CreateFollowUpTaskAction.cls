/**
 * Invocable action for the PostVisitLogger subagent.
 * Creates a follow-up Task on the Account, owned by the running user.
 */
public with sharing class CreateFollowUpTaskAction {

    private static final Integer DEFAULT_DUE_IN_DAYS = 7;
    private static final String  DEFAULT_PRIORITY    = 'Normal';

    public class Request {
        @InvocableVariable(label='Account ID' description='Salesforce Account Id resolved by IdentifyRecordByName' required=true)
        public String accountId;

        @InvocableVariable(label='Subject' description='Task subject line, e.g. Schedule Teach & Learn for new hygienist' required=true)
        public String subject;

        @InvocableVariable(label='Description' description='Additional context for the task, if the rep provided it.')
        public String description;

        @InvocableVariable(label='Due In Days' description='Days from today until the task is due. Defaults to 7.')
        public Integer dueInDays;

        @InvocableVariable(label='Priority' description='Normal (default), High, or Low.')
        public String priority;
    }

    public class Response {
        @InvocableVariable(label='Task ID')       public String taskId;
        @InvocableVariable(label='Summary')       public String summary;
        @InvocableVariable(label='Success')       public Boolean isSuccess;
        @InvocableVariable(label='Error Message') public String errorMessage;
    }

    /**
     * Creates a follow-up Task linked to the Account.
     *
     * @param requests List of Request from the agent planner.
     * @return List of Response with taskId and a human-readable summary.
     */
    @InvocableMethod(
        label='Create Follow-Up Task'
        description='Creates a follow-up Task on the Account for the rep. Call when the rep explicitly mentions a next step, follow-up, or action item that needs tracking. Do NOT call unless a concrete follow-up is stated.'
        category='P&G Sales Companion'
    )
    public static List<Response> create(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            try {
                Task followUp = buildTask(req);
                insert followUp;
                responses.add(buildSuccess(followUp, req));
            } catch (Exception ex) {
                System.debug('CreateFollowUpTaskAction failed: ' + ex.getMessage() + ' | ' + ex.getStackTraceString());
                responses.add(buildError(ex));
            }
        }

        return responses;
    }

    private static Task buildTask(Request req) {
        Integer dueDays = req.dueInDays != null && req.dueInDays > 0 ? req.dueInDays : DEFAULT_DUE_IN_DAYS;
        String taskPriority = String.isNotBlank(req.priority) ? req.priority : DEFAULT_PRIORITY;

        Task followUp = new Task(
            WhatId      = req.accountId,
            OwnerId     = UserInfo.getUserId(),
            Subject     = req.subject,
            Status      = 'Not Started',
            Priority    = taskPriority,
            ActivityDate = Date.today().addDays(dueDays)
        );

        if (String.isNotBlank(req.description)) {
            followUp.Description = req.description;
        }

        return followUp;
    }

    private static Response buildSuccess(Task followUp, Request req) {
        Response r = new Response();
        r.taskId    = followUp.Id;
        r.summary   = 'Created follow-up task "' + req.subject + '", due ' + followUp.ActivityDate.format() + '.';
        r.isSuccess = true;
        return r;
    }

    private static Response buildError(Exception ex) {
        Response r = new Response();
        r.isSuccess    = false;
        r.errorMessage = 'Unable to create the follow-up task. Please try again or contact your admin.';
        r.summary      = r.errorMessage;
        return r;
    }
}
