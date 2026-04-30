public with sharing class POHFindContactsByName {

    public class Request {
        @InvocableVariable(label='Contact First Names' required=true description='Comma-separated first names to look up on the account.')
        public String contactFirstNames;

        @InvocableVariable(label='Account ID' required=true)
        public String accountId;
    }

    public class Response {
        @InvocableVariable(label='Resolved Contact IDs' description='Comma-separated Contact IDs, one per first name. Most recently modified wins on duplicates.')
        public String resolvedContactIds;

        @InvocableVariable(label='Contact Summary' description='Human-readable summary with duplicate warnings for rep review.')
        public String contactSummary;
    }

    @InvocableMethod(label='POH Find Contacts By Name' description='Finds ALL contacts on the Account matching the given first names. No row cap. Selects most-recently-modified on duplicates and surfaces the duplicate to the rep.')
    public static List<Response> findContactsByName(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) return results;

        for (Request req : requests) {
            Response res = new Response();
            buildResponse(req.accountId, req.contactFirstNames, res);
            results.add(res);
        }
        return results;
    }

    private static void buildResponse(String accountId, String firstNamesStr, Response res) {
        if (String.isBlank(accountId) || String.isBlank(firstNamesStr)) {
            res.resolvedContactIds = '';
            res.contactSummary = 'No account or contact names provided.';
            return;
        }

        // Parse the comma-separated first names
        List<String> requestedNames = new List<String>();
        for (String n : firstNamesStr.split(',')) {
            String trimmed = n.trim();
            if (String.isNotBlank(trimmed)) requestedNames.add(trimmed.toLowerCase());
        }

        if (requestedNames.isEmpty()) {
            res.resolvedContactIds = '';
            res.contactSummary = 'No valid contact names parsed.';
            return;
        }

        // Query ALL contacts on the account — no row cap
        List<Contact> allContacts = [
            SELECT Id, FirstName, LastName, Title, LastModifiedDate
            FROM Contact
            WHERE AccountId = :accountId
            ORDER BY LastModifiedDate DESC
        ];

        // Group contacts by lower-case first name
        Map<String, List<Contact>> byFirstName = new Map<String, List<Contact>>();
        for (Contact c : allContacts) {
            String fn = String.isNotBlank(c.FirstName) ? c.FirstName.toLowerCase() : '';
            if (!byFirstName.containsKey(fn)) byFirstName.put(fn, new List<Contact>());
            byFirstName.get(fn).add(c);
        }

        List<String> resolvedIds = new List<String>();
        List<String> summaryLines = new List<String>();
        summaryLines.add('CONTACT RESOLUTION:');

        for (String requestedName : requestedNames) {
            List<Contact> matches = byFirstName.containsKey(requestedName)
                ? byFirstName.get(requestedName) : new List<Contact>();

            if (matches.isEmpty()) {
                summaryLines.add('  ' + requestedName + ': NOT FOUND on account — check spelling or add contact manually.');
            } else if (matches.size() == 1) {
                Contact c = matches[0];
                resolvedIds.add(c.Id);
                String title = String.isNotBlank(c.Title) ? ' (' + c.Title + ')' : '';
                summaryLines.add('  ' + c.FirstName + ' ' + c.LastName + title + ' — resolved.');
            } else {
                // Duplicate — already sorted by LastModifiedDate DESC, so first is most recent
                Contact best = matches[0];
                resolvedIds.add(best.Id);
                String title = String.isNotBlank(best.Title) ? ' (' + best.Title + ')' : '';
                summaryLines.add('  ' + best.FirstName + ' ' + best.LastName + title
                    + ' — DUPLICATE FIRST NAME: ' + matches.size() + ' contacts found. Selected most recently modified (last updated '
                    + best.LastModifiedDate.format() + '). Other matches:');
                for (Integer i = 1; i < matches.size(); i++) {
                    Contact other = matches[i];
                    String otherTitle = String.isNotBlank(other.Title) ? ' (' + other.Title + ')' : '';
                    summaryLines.add('    - ' + other.FirstName + ' ' + other.LastName + otherTitle
                        + ' (last updated ' + other.LastModifiedDate.format() + ')');
                }
                summaryLines.add('  Please confirm the correct ' + best.FirstName + ' was selected.');
            }
        }

        res.resolvedContactIds = String.join(resolvedIds, ',');
        res.contactSummary = String.join(summaryLines, '\n');
    }
}
