/**
 * Invocable action for the PostVisitLogger subagent.
 * Creates an Office Visit Event on the given Account with all supplied details.
 * Fields not supplied by the rep default to sensible values so the planner
 * never needs to ask for data the rep didn't volunteer.
 */
public with sharing class LogOfficeVisitAction {

    private static final Integer DEFAULT_DURATION_MINUTES = 20;
    private static final String DEFAULT_EVENT_TYPE       = 'Face to Face';
    private static final String OFFICE_VISIT_RT_NAME     = 'Office_Visit';

    /**
     * Inputs accepted from the agent planner.
     * Only accountId is required — every other field has a safe default.
     */
    public class Request {
        @InvocableVariable(label='Account ID' description='Salesforce Account Id resolved by IdentifyRecordByName' required=true)
        public String accountId;

        @InvocableVariable(label='Start Date/Time' description='Visit start time in UTC. Defaults to now() when omitted.')
        public Datetime startDateTime;

        @InvocableVariable(label='End Date/Time' description='Visit end time in UTC. Defaults to start + 20 min when omitted.')
        public Datetime endDateTime;

        @InvocableVariable(label='Event Type' description='Face to Face or Teach & Learn. Defaults to Face to Face.')
        public String eventType;

        @InvocableVariable(label='Visit Notes' description='Full narrative of what was discussed during the visit.')
        public String visitNotes;

        @InvocableVariable(label='Samples Left — Count' description='Number of sample units left at the office.')
        public Integer samplesLeftCount;

        @InvocableVariable(label='Samples Left — Product' description='Product name of samples left, e.g. Crest Gum Detoxify.')
        public String samplesLeftProduct;

        @InvocableVariable(label='Prescheduled' description='True if the visit was booked in advance.')
        public Boolean prescheduled;
    }

    /**
     * Response returned to the agent planner.
     * Always includes a human-readable summary the agent can relay to the rep.
     */
    public class Response {
        @InvocableVariable(label='Event ID') public String eventId;
        @InvocableVariable(label='Summary')  public String summary;
        @InvocableVariable(label='Success')  public Boolean isSuccess;
        @InvocableVariable(label='Error Message') public String errorMessage;
    }

    /**
     * Creates an Office Visit Event for the given Account.
     * All optional inputs default gracefully — the planner can call this
     * with just an accountId and get a valid Event.
     *
     * @param requests List of Request; one request per agent invocation.
     * @return List of Response with eventId, summary, and success flag.
     */
    @InvocableMethod(
        label='Log Office Visit'
        description='Creates an Office Visit Event on an Account. Call when the rep says they visited or just left a dental practice. Do NOT call when the rep is only updating account attributes without a visit occurring.'
        category='P&G Sales Companion'
    )
    public static List<Response> log(List<Request> requests) {
        List<Response> responses = new List<Response>();

        Id officeVisitRtId = resolveOfficeVisitRecordTypeId();

        for (Request req : requests) {
            try {
                Event visit = buildEvent(req, officeVisitRtId);
                insert visit;
                responses.add(buildSuccess(visit, req));
            } catch (Exception ex) {
                System.debug('LogOfficeVisitAction failed: ' + ex.getMessage() + ' | ' + ex.getStackTraceString());
                responses.add(buildError(ex));
            }
        }

        return responses;
    }

    private static Event buildEvent(Request req, Id recordTypeId) {
        Datetime startDt = req.startDateTime != null ? req.startDateTime : Datetime.now();
        Datetime endDt   = req.endDateTime   != null ? req.endDateTime   : startDt.addMinutes(DEFAULT_DURATION_MINUTES);
        String   evtType = String.isNotBlank(req.eventType) ? req.eventType : DEFAULT_EVENT_TYPE;

        Event visit = new Event(
            WhatId        = req.accountId,
            OwnerId       = UserInfo.getUserId(),
            StartDateTime = startDt,
            EndDateTime   = endDt,
            Type          = evtType,
            Subject       = 'Office Visit — ' + evtType
        );

        if (String.isNotBlank(req.visitNotes)) {
            visit.Visit_Notes__c = req.visitNotes;
            visit.Description    = req.visitNotes;
        }
        if (req.samplesLeftCount != null)              visit.Samples_Left_Count__c   = req.samplesLeftCount;
        if (String.isNotBlank(req.samplesLeftProduct)) visit.Samples_Left_Product__c = req.samplesLeftProduct;
        if (req.prescheduled != null)                  visit.Prescheduled__c         = req.prescheduled;

        if (recordTypeId != null) {
            visit.RecordTypeId = recordTypeId;
        }

        return visit;
    }

    private static Id resolveOfficeVisitRecordTypeId() {
        Map<String, RecordTypeInfo> rtInfoMap = Event.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByDeveloperName();
        RecordTypeInfo rtInfo = rtInfoMap.get(OFFICE_VISIT_RT_NAME);
        return rtInfo != null && rtInfo.isAvailable() ? rtInfo.getRecordTypeId() : null;
    }

    private static Response buildSuccess(Event visit, Request req) {
        Integer durationMins = (Integer) (visit.StartDateTime.getTime() != visit.EndDateTime.getTime()
            ? (visit.EndDateTime.getTime() - visit.StartDateTime.getTime()) / 60000
            : DEFAULT_DURATION_MINUTES);

        String summary = 'Logged a ' + durationMins + '-minute '
            + visit.Type + ' visit on ' + visit.StartDateTime.format('MM/dd/yyyy h:mm a') + '.';
        if (req.samplesLeftCount != null && String.isNotBlank(req.samplesLeftProduct)) {
            summary += ' Left ' + req.samplesLeftCount + ' units of ' + req.samplesLeftProduct + '.';
        }

        Response r = new Response();
        r.eventId   = visit.Id;
        r.summary   = summary;
        r.isSuccess = true;
        return r;
    }

    private static Response buildError(Exception ex) {
        Response r = new Response();
        r.isSuccess    = false;
        r.errorMessage = 'Unable to log the visit. Please try again or contact your admin.';
        r.summary      = r.errorMessage;
        return r;
    }
}
