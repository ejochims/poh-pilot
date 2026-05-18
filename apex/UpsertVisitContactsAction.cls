/**
 * Invocable action for the PostVisitLogger subagent.
 * Resolves attendee first names to existing Contacts on the Account, or creates
 * stub records for anyone new. Returns the resolved Contact Ids for
 * LinkVisitAttendeesAction.
 *
 * Resolution logic (per name):
 *   1 first-name match on Account Contacts → use it
 *   2+ matches → take the first, flag in summary
 *   0 matches  → create stub Contact with LastName "(Unknown)"
 */
public with sharing class UpsertVisitContactsAction {

    public class Request {
        @InvocableVariable(label='Account ID' description='Salesforce Account Id resolved by IdentifyRecordByName' required=true)
        public String accountId;

        @InvocableVariable(label='Attendees' description='First names of people the rep saw. The action matches by first name against existing contacts and creates stubs for anyone new.')
        public List<String> attendees;
    }

    public class Response {
        @InvocableVariable(label='Contact IDs')         public List<String> contactIds;
        @InvocableVariable(label='Resolution Summary')  public String resolutionSummary;
        @InvocableVariable(label='Success')             public Boolean isSuccess;
        @InvocableVariable(label='Error Message')       public String errorMessage;
    }

    /**
     * Resolves or creates Contacts for everyone the rep mentioned attending.
     * Returns empty contactIds (not an error) when no attendees were provided.
     *
     * @param requests List of Request from the agent planner.
     * @return List of Response with resolved contactIds and a human-readable summary.
     */
    @InvocableMethod(
        label='Upsert Visit Contacts'
        description='Finds or creates Contacts for everyone the rep mentions seeing during a visit. Call ONLY when the rep names specific people they met. Do NOT call when no attendees are mentioned.'
        category='P&G Sales Companion'
    )
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            try {
                if (req.attendees == null || req.attendees.isEmpty()) {
                    responses.add(emptyResponse());
                    continue;
                }
                responses.add(resolveAttendees(req));
            } catch (Exception ex) {
                System.debug('UpsertVisitContactsAction failed: ' + ex.getMessage() + ' | ' + ex.getStackTraceString());
                responses.add(buildError(ex));
            }
        }

        return responses;
    }

    private static Response resolveAttendees(Request req) {
        List<Contact> existingContacts = [
            SELECT Id, FirstName, LastName
            FROM Contact
            WHERE AccountId = :req.accountId
            WITH USER_MODE
        ];

        // Build first-name map: real contacts first so they win over stubs on collision.
        Map<String, List<Contact>> byFirstName = new Map<String, List<Contact>>();
        for (Contact c : existingContacts) {
            if ('(Unknown)'.equals(c.LastName)) continue; // stubs in second pass
            String key = c.FirstName != null ? c.FirstName.toLowerCase() : '';
            if (!byFirstName.containsKey(key)) byFirstName.put(key, new List<Contact>());
            byFirstName.get(key).add(c);
        }
        for (Contact c : existingContacts) {
            if (!'(Unknown)'.equals(c.LastName)) continue; // real contacts already added
            String key = c.FirstName != null ? c.FirstName.toLowerCase() : '';
            if (!byFirstName.containsKey(key)) byFirstName.put(key, new List<Contact>());
            byFirstName.get(key).add(c);
        }

        List<String> resolvedIds  = new List<String>();
        List<String> summaryParts = new List<String>();
        List<Contact> toCreate    = new List<Contact>();

        for (String name : req.attendees) {
            if (String.isBlank(name)) continue;
            // Strip pipe characters that lightning__textType list encoding can append
            String cleanName = name.trim().replaceAll('\\|', '').trim();
            if (String.isBlank(cleanName)) continue;
            String key = cleanName.toLowerCase();
            List<Contact> matches = byFirstName.get(key);

            if (matches != null && !matches.isEmpty()) {
                resolvedIds.add(matches[0].Id);
                String displayName = matches[0].FirstName + ' ' + matches[0].LastName;
                summaryParts.add('linked ' + displayName + (matches.size() > 1 ? ' (first of multiple matches)' : ''));
            } else {
                toCreate.add(new Contact(
                    AccountId = req.accountId,
                    FirstName = cleanName,
                    LastName  = '(Unknown)',
                    OwnerId   = UserInfo.getUserId()
                ));
            }
        }

        if (!toCreate.isEmpty()) {
            insert toCreate;
            for (Contact c : toCreate) {
                resolvedIds.add(c.Id);
                summaryParts.add('created ' + c.FirstName + ' (Unknown) as new contact');
            }
        }

        Response r = new Response();
        r.contactIds        = resolvedIds;
        r.resolutionSummary = summaryParts.isEmpty() ? 'No attendees resolved.' : String.join(summaryParts, '; ') + '.';
        r.isSuccess         = true;
        return r;
    }

    private static Response emptyResponse() {
        Response r = new Response();
        r.contactIds        = new List<String>();
        r.resolutionSummary = 'No attendees recorded.';
        r.isSuccess         = true;
        return r;
    }

    private static Response buildError(Exception ex) {
        Response r = new Response();
        r.isSuccess         = false;
        r.errorMessage      = 'Unable to resolve attendees. Please try again or contact your admin.';
        r.resolutionSummary = r.errorMessage;
        r.contactIds        = new List<String>();
        return r;
    }
}
