/**
 * Invocable action for the PostVisitLogger subagent.
 * Sequenced AFTER LogOfficeVisitAction and UpsertVisitContactsAction.
 * Creates EventRelation records to link attendee Contacts to the visit Event.
 * Exits cleanly with a no-op response when no contactIds are provided —
 * this keeps the planner happy when attendees were not mentioned.
 */
public with sharing class LinkVisitAttendeesAction {

    public class Request {
        @InvocableVariable(label='Event ID' description='Id of the Event created by LogOfficeVisitAction' required=true)
        public String eventId;

        @InvocableVariable(label='Contact IDs' description='Ids of the Contacts resolved by UpsertVisitContactsAction. Pass empty list to skip linking.')
        public List<String> contactIds;
    }

    public class Response {
        @InvocableVariable(label='Count Linked') public Integer count;
        @InvocableVariable(label='Summary')      public String summary;
        @InvocableVariable(label='Success')      public Boolean isSuccess;
        @InvocableVariable(label='Error Message') public String errorMessage;
    }

    /**
     * Bulk-inserts EventRelation records linking contacts to the Event.
     * Safe to call with an empty contactIds list — returns a zero-count success.
     *
     * @param requests List of Request from the agent planner.
     * @return List of Response with the count of relations created.
     */
    @InvocableMethod(
        label='Link Visit Attendees'
        description='Links Contacts as invitees on the Office Visit Event. Must be called AFTER Log Office Visit and Upsert Visit Contacts. Pass the eventId from Log Office Visit and the contactIds from Upsert Visit Contacts.'
        category='P&G Sales Companion'
    )
    public static List<Response> link(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            try {
                if (req.contactIds == null || req.contactIds.isEmpty()) {
                    responses.add(emptyResponse());
                    continue;
                }
                responses.add(createRelations(req));
            } catch (Exception ex) {
                System.debug('LinkVisitAttendeesAction failed: ' + ex.getMessage() + ' | ' + ex.getStackTraceString());
                responses.add(buildError(ex));
            }
        }

        return responses;
    }

    private static Response createRelations(Request req) {
        List<EventRelation> relations = new List<EventRelation>();
        for (String contactId : req.contactIds) {
            if (String.isNotBlank(contactId)) {
                relations.add(new EventRelation(
                    EventId    = req.eventId,
                    RelationId = contactId,
                    IsInvitee  = true
                ));
            }
        }

        if (relations.isEmpty()) {
            return emptyResponse();
        }

        insert relations;

        Response r = new Response();
        r.count     = relations.size();
        r.summary   = 'Linked ' + relations.size() + ' attendee(s) to the visit Event.';
        r.isSuccess = true;
        return r;
    }

    private static Response emptyResponse() {
        Response r = new Response();
        r.count     = 0;
        r.summary   = 'No attendees to link.';
        r.isSuccess = true;
        return r;
    }

    private static Response buildError(Exception ex) {
        Response r = new Response();
        r.isSuccess    = false;
        r.errorMessage = 'Unable to link attendees to the visit. The visit was still saved. Please try again or contact your admin.';
        r.summary      = r.errorMessage;
        r.count        = 0;
        return r;
    }
}
