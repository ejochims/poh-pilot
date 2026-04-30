public with sharing class POHLogVisitEvent {

    public class Request {
        @InvocableVariable(label='Account ID' required=true)
        public String accountId;

        @InvocableVariable(label='Primary Contact IDs' description='Comma-separated Contact IDs to link to the event.')
        public String primaryContactIds;

        @InvocableVariable(label='Start DateTime' description='ISO datetime string for event start.')
        public String startDateTime;

        @InvocableVariable(label='End DateTime' description='ISO datetime string for event end.')
        public String endDateTime;

        @InvocableVariable(label='Subject')
        public String subject;

        @InvocableVariable(label='Visit Notes')
        public String visitNotes;

        @InvocableVariable(label='Samples Left Summary')
        public String samplesLeftSummary;
    }

    public class Response {
        @InvocableVariable(label='Event ID')
        public String eventId;

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Confirmation Message')
        public String confirmationMessage;
    }

    @InvocableMethod(label='POH Log Visit Event' description='Creates a Salesforce Event for the completed sales visit. Links contacts, sets Visit_Notes__c, Samples_Left_Summary__c, and Logged_via_Agentforce__c = true.')
    public static List<Response> logVisitEvent(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) return results;

        for (Request req : requests) {
            Response res = new Response();
            try {
                createEvent(req, res);
            } catch (Exception e) {
                res.success = false;
                res.confirmationMessage = 'Error logging visit: ' + e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    private static void createEvent(Request req, Response res) {
        // Parse datetimes — fallback to now / now+20min if unparseable
        DateTime startDT = parseDateTime(req.startDateTime);
        DateTime endDT   = parseDateTime(req.endDateTime);
        if (startDT == null) startDT = DateTime.now();
        if (endDT == null)   endDT   = startDT.addMinutes(20);

        String eventSubject = String.isNotBlank(req.subject) ? req.subject : 'Sales Visit';

        Event evt = new Event();
        evt.WhatId        = (Id) req.accountId;
        evt.Subject       = eventSubject;
        evt.StartDateTime = startDT;
        evt.EndDateTime   = endDT;
        evt.DurationInMinutes = (Integer)((endDT.getTime() - startDT.getTime()) / 60000);
        evt.Logged_via_Agentforce__c = true;

        if (String.isNotBlank(req.visitNotes)) {
            // Truncate to 255 chars (TextArea limit)
            evt.Visit_Notes__c = req.visitNotes.abbreviate(255);
            evt.Description    = req.visitNotes;
        }
        if (String.isNotBlank(req.samplesLeftSummary)) {
            evt.Samples_Left_Summary__c = req.samplesLeftSummary.abbreviate(255);
        }

        // Set WhoId to first contact if provided
        List<String> contactIdList = new List<String>();
        if (String.isNotBlank(req.primaryContactIds)) {
            for (String cId : req.primaryContactIds.split(',')) {
                String trimmed = cId.trim();
                if (String.isNotBlank(trimmed)) contactIdList.add(trimmed);
            }
        }
        if (!contactIdList.isEmpty()) {
            evt.WhoId = (Id) contactIdList[0];
        }

        insert evt;

        // Add remaining contacts as EventRelations (invitees)
        if (contactIdList.size() > 1) {
            List<EventRelation> relations = new List<EventRelation>();
            for (Integer i = 1; i < contactIdList.size(); i++) {
                EventRelation er = new EventRelation();
                er.EventId   = evt.Id;
                er.RelationId = (Id) contactIdList[i];
                er.IsInvitee = true;
                relations.add(er);
            }
            if (!relations.isEmpty()) {
                insert relations;
            }
        }

        res.eventId = evt.Id;
        res.success = true;

        // Build confirmation message
        List<String> confParts = new List<String>();
        confParts.add('Visit logged for ' + startDT.format() + ' to ' + endDT.format() + '.');
        if (!contactIdList.isEmpty()) {
            confParts.add(contactIdList.size() + ' contact(s) linked.');
        }
        if (String.isNotBlank(req.visitNotes)) confParts.add('Notes recorded.');
        if (String.isNotBlank(req.samplesLeftSummary)) confParts.add('Samples: ' + req.samplesLeftSummary + '.');
        confParts.add('Logged_via_Agentforce__c = true. Event ID: ' + evt.Id);

        res.confirmationMessage = String.join(confParts, ' ');
    }

    private static DateTime parseDateTime(String dtStr) {
        if (String.isBlank(dtStr)) return null;
        try {
            // Try ISO 8601 format first
            return (DateTime) JSON.deserialize('"' + dtStr + '"', DateTime.class);
        } catch (Exception e) {
            try {
                // Try simple date format
                return DateTime.parse(dtStr);
            } catch (Exception e2) {
                return null;
            }
        }
    }
}
