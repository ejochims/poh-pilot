/**
 * Returns the past visit history for a dental practice.
 * Reads Visit_Notes__c, Samples_Left_Count__c, and Samples_Left_Product__c
 * from Event custom fields, falling back to Description for legacy records.
 */
public with sharing class POHGetVisitHistory {

    public class Request {
        @InvocableVariable(label='Account ID' required=true)
        public String accountId;

        @InvocableVariable(label='Lookback Days' required=true description='Number of days to look back. 365 = last 12 months.')
        public Integer lookbackDays;
    }

    public class Response {
        @InvocableVariable(label='Visit History Summary')
        public String visitHistorySummary;
    }

    @InvocableMethod(
        label='POH Get Visit History'
        description='Returns Events on the Account within the lookback window including attendees, duration, and visit notes from Description.'
        category='P&G Sales Companion'
    )
    public static List<Response> getVisitHistory(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) return results;

        for (Request req : requests) {
            Response res = new Response();
            res.visitHistorySummary = buildSummary(req.accountId, req.lookbackDays != null ? req.lookbackDays : 365);
            results.add(res);
        }
        return results;
    }

    private static String buildSummary(String accountId, Integer lookbackDays) {
        if (String.isBlank(accountId)) return 'No account ID provided.';

        Date cutoffDate = Date.today().addDays(-lookbackDays);
        DateTime cutoffDT = DateTime.newInstance(cutoffDate, Time.newInstance(0, 0, 0, 0));

        List<Event> events = [
            SELECT Id, Subject, Type, StartDateTime, EndDateTime,
                   Visit_Notes__c, Samples_Left_Count__c, Samples_Left_Product__c, Prescheduled__c,
                   Description
            FROM Event
            WHERE WhatId = :accountId
            AND StartDateTime >= :cutoffDT
            ORDER BY StartDateTime DESC
        ];

        if (events.isEmpty()) {
            return 'No visits recorded in the past ' + lookbackDays + ' days.';
        }

        // Collect all event Ids for attendee lookup
        Set<Id> eventIds = new Set<Id>();
        for (Event e : events) eventIds.add(e.Id);

        Map<Id, List<Id>> contactIdsByEventId = new Map<Id, List<Id>>();
        Set<Id> allContactIds = new Set<Id>();

        List<EventRelation> relations = [
            SELECT EventId, RelationId
            FROM EventRelation
            WHERE EventId IN :eventIds
            AND IsInvitee = true
            AND RelationId != null
        ];
        for (EventRelation er : relations) {
            if (!contactIdsByEventId.containsKey(er.EventId)) {
                contactIdsByEventId.put(er.EventId, new List<Id>());
            }
            contactIdsByEventId.get(er.EventId).add(er.RelationId);
            allContactIds.add(er.RelationId);
        }

        Map<Id, Contact> contactsById = new Map<Id, Contact>([
            SELECT Id, FirstName, LastName, Title
            FROM Contact
            WHERE Id IN :allContactIds
        ]);

        List<String> lines = new List<String>();
        lines.add('Total visits in window: ' + events.size());
        lines.add('Lookback window: past ' + lookbackDays + ' days (since ' + cutoffDate.format() + ')');
        lines.add('');

        Event latest = events[0];
        lines.add('MOST RECENT VISIT:');
        lines.add('  Date/Duration: ' + formatDuration(latest.StartDateTime, latest.EndDateTime));
        if (String.isNotBlank(latest.Type)) {
            lines.add('  Type: ' + latest.Type);
        }

        List<String> attendeeNames = buildAttendeeNames(latest.Id, contactIdsByEventId, contactsById);
        lines.add('  Attendees: ' + (attendeeNames.isEmpty() ? 'None recorded' : String.join(attendeeNames, ', ')));

        String notes = String.isNotBlank(latest.Visit_Notes__c) ? latest.Visit_Notes__c
                     : String.isNotBlank(latest.Description)   ? latest.Description
                     : 'No notes recorded.';
        lines.add('  Notes: ' + notes);
        if (latest.Samples_Left_Count__c != null || String.isNotBlank(latest.Samples_Left_Product__c)) {
            String samples = latest.Samples_Left_Count__c != null ? String.valueOf(latest.Samples_Left_Count__c.intValue()) + ' units' : '';
            if (String.isNotBlank(latest.Samples_Left_Product__c)) samples += (String.isNotBlank(samples) ? ' of ' : '') + latest.Samples_Left_Product__c;
            lines.add('  Samples left: ' + samples);
        }

        if (events.size() > 1) {
            lines.add('');
            lines.add('PREVIOUS VISITS (' + (events.size() - 1) + '):');
            for (Integer i = 1; i < events.size(); i++) {
                Event e = events[i];
                String visitDate = e.StartDateTime != null ? e.StartDateTime.format() : 'Unknown date';
                String visitType = String.isNotBlank(e.Type) ? e.Type : '';
                List<String> prevAttendees = buildAttendeeNames(e.Id, contactIdsByEventId, contactsById);
                String visitLine = '  - ' + visitDate;
                if (String.isNotBlank(visitType)) visitLine += ' [' + visitType + ']';
                if (!prevAttendees.isEmpty()) visitLine += ' — ' + String.join(prevAttendees, ', ');
                String visitNotes = String.isNotBlank(e.Visit_Notes__c) ? e.Visit_Notes__c : e.Description;
                if (String.isNotBlank(visitNotes)) visitLine += ': ' + visitNotes.abbreviate(120);
                if (e.Samples_Left_Count__c != null && String.isNotBlank(e.Samples_Left_Product__c)) {
                    visitLine += ' [Samples: ' + e.Samples_Left_Count__c.intValue() + ' x ' + e.Samples_Left_Product__c + ']';
                }
                lines.add(visitLine);
            }
        }

        return String.join(lines, '\n');
    }

    private static List<String> buildAttendeeNames(Id eventId, Map<Id, List<Id>> contactIdsByEventId, Map<Id, Contact> contactsById) {
        List<String> names = new List<String>();
        List<Id> contactIds = contactIdsByEventId.get(eventId);
        if (contactIds == null) return names;

        for (Id contactId : contactIds) {
            Contact c = contactsById.get(contactId);
            if (c != null) {
                String name = c.FirstName + ' ' + c.LastName;
                if (String.isNotBlank(c.Title)) name += ' (' + c.Title + ')';
                names.add(name);
            }
        }
        return names;
    }

    private static String formatDuration(DateTime startDT, DateTime endDT) {
        if (startDT == null) return 'Unknown';
        if (endDT == null) return startDT.format();
        Long diffMs = endDT.getTime() - startDT.getTime();
        Integer minutes = (Integer)(diffMs / 60000);
        return startDT.format() + ' (' + minutes + ' min)';
    }
}
