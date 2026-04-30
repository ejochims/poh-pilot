public with sharing class POHGetVisitHistory {

    public class Request {
        @InvocableVariable(label='Account ID' required=true)
        public String accountId;

        @InvocableVariable(label='Lookback Days' required=true description='Number of days to look back. 365 = last 12 months, 90 = recent.')
        public Integer lookbackDays;
    }

    public class Response {
        @InvocableVariable(label='Visit History Summary')
        public String visitHistorySummary;
    }

    @InvocableMethod(label='POH Get Visit History' description='Returns ALL Events linked to the Account within the lookback window. No row cap. Returns visit count, last visit date, attendees, and notes.')
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
            SELECT Id, Subject, StartDateTime, EndDateTime, Description,
                   Visit_Notes__c, Samples_Left_Summary__c, WhoId
            FROM Event
            WHERE WhatId = :accountId
            AND StartDateTime >= :cutoffDT
            ORDER BY StartDateTime DESC
        ];

        if (events.isEmpty()) {
            return 'No visits recorded in the past ' + lookbackDays + ' days.';
        }

        // Collect all WhoIds to look up contact names
        Set<Id> contactIds = new Set<Id>();
        for (Event e : events) {
            if (e.WhoId != null) contactIds.add(e.WhoId);
        }

        // Also look up additional attendees via EventRelation
        Map<Id, List<Id>> eventToExtraContacts = new Map<Id, List<Id>>();
        Set<Id> eventIds = new Set<Id>();
        for (Event e : events) eventIds.add(e.Id);

        List<EventRelation> relations = [
            SELECT EventId, RelationId
            FROM EventRelation
            WHERE EventId IN :eventIds
            AND IsInvitee = true
            AND RelationId != null
        ];
        for (EventRelation er : relations) {
            if (!eventToExtraContacts.containsKey(er.EventId)) {
                eventToExtraContacts.put(er.EventId, new List<Id>());
            }
            eventToExtraContacts.get(er.EventId).add(er.RelationId);
            contactIds.add(er.RelationId);
        }

        // Look up contact names
        Map<Id, Contact> contactMap = new Map<Id, Contact>([
            SELECT Id, FirstName, LastName, Title
            FROM Contact
            WHERE Id IN :contactIds
        ]);

        List<String> lines = new List<String>();
        lines.add('Total visits in window: ' + events.size());
        lines.add('Lookback window: past ' + lookbackDays + ' days (since ' + cutoffDate.format() + ')');
        lines.add('');

        Event latest = events[0];
        lines.add('MOST RECENT VISIT:');
        lines.add('  Date: ' + (latest.StartDateTime != null ? latest.StartDateTime.format() : 'Unknown'));
        lines.add('  Duration: ' + formatDuration(latest.StartDateTime, latest.EndDateTime));

        // Build attendee list for most recent visit
        List<String> attendees = new List<String>();
        if (latest.WhoId != null && contactMap.containsKey(latest.WhoId)) {
            Contact c = contactMap.get(latest.WhoId);
            String n = c.FirstName + ' ' + c.LastName;
            if (String.isNotBlank(c.Title)) n += ' (' + c.Title + ')';
            attendees.add(n);
        }
        if (eventToExtraContacts.containsKey(latest.Id)) {
            for (Id cId : eventToExtraContacts.get(latest.Id)) {
                if (contactMap.containsKey(cId)) {
                    Contact c = contactMap.get(cId);
                    String n = c.FirstName + ' ' + c.LastName;
                    if (String.isNotBlank(c.Title)) n += ' (' + c.Title + ')';
                    attendees.add(n);
                }
            }
        }
        lines.add('  Attendees: ' + (attendees.isEmpty() ? 'None recorded' : String.join(attendees, ', ')));

        String notes = String.isNotBlank(latest.Visit_Notes__c) ? latest.Visit_Notes__c
                     : (String.isNotBlank(latest.Description) ? latest.Description : 'No notes recorded.');
        lines.add('  Notes: ' + notes);
        if (String.isNotBlank(latest.Samples_Left_Summary__c)) {
            lines.add('  Samples left: ' + latest.Samples_Left_Summary__c);
        }

        if (events.size() > 1) {
            lines.add('');
            lines.add('PREVIOUS VISITS (' + (events.size() - 1) + '):');
            for (Integer i = 1; i < events.size(); i++) {
                Event e = events[i];
                String visitDate = e.StartDateTime != null ? e.StartDateTime.format() : 'Unknown date';
                String visitNotes = String.isNotBlank(e.Visit_Notes__c) ? e.Visit_Notes__c
                                  : (String.isNotBlank(e.Description) ? e.Description : '');
                String visitLine = '  - ' + visitDate;
                if (String.isNotBlank(visitNotes)) visitLine += ': ' + visitNotes.abbreviate(120);
                lines.add(visitLine);
            }
        }

        return String.join(lines, '\n');
    }

    private static String formatDuration(DateTime startDT, DateTime endDT) {
        if (startDT == null) return 'Unknown';
        if (endDT == null) return startDT.format();
        Long diffMs = endDT.getTime() - startDT.getTime();
        Integer minutes = (Integer)(diffMs / 60000);
        return startDT.format() + ' to ' + endDT.format() + ' (' + minutes + ' min)';
    }
}
