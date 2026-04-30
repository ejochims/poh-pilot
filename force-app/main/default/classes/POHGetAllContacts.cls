public with sharing class POHGetAllContacts {

    public class Request {
        @InvocableVariable(label='Account ID' required=true)
        public String accountId;
    }

    public class Response {
        @InvocableVariable(label='Contact List Summary')
        public String contactListSummary;

        @InvocableVariable(label='Total Contacts')
        public String totalContacts;
    }

    @InvocableMethod(label='POH Get All Contacts' description='Returns ALL contacts on the Account with no row cap. Includes full name, title, phone, email, and last modified date. Flags duplicate first names.')
    public static List<Response> getAllContacts(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) return results;

        for (Request req : requests) {
            Response res = new Response();
            buildSummary(req.accountId, res);
            results.add(res);
        }
        return results;
    }

    private static void buildSummary(String accountId, Response res) {
        if (String.isBlank(accountId)) {
            res.contactListSummary = 'No account ID provided.';
            res.totalContacts = '0';
            return;
        }

        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Title, Phone, Email, LastModifiedDate
            FROM Contact
            WHERE AccountId = :accountId
            ORDER BY LastModifiedDate DESC
        ];

        res.totalContacts = String.valueOf(contacts.size());

        if (contacts.isEmpty()) {
            res.contactListSummary = 'No contacts found on this account.';
            return;
        }

        // Find duplicate first names
        Map<String, Integer> firstNameCount = new Map<String, Integer>();
        for (Contact c : contacts) {
            String fn = String.isNotBlank(c.FirstName) ? c.FirstName.toLowerCase() : '';
            Integer cnt = firstNameCount.containsKey(fn) ? firstNameCount.get(fn) : 0;
            firstNameCount.put(fn, cnt + 1);
        }

        List<String> lines = new List<String>();
        lines.add('ALL CONTACTS (' + contacts.size() + ' total):');

        for (Contact c : contacts) {
            String fn = String.isNotBlank(c.FirstName) ? c.FirstName.toLowerCase() : '';
            Boolean isDup = firstNameCount.containsKey(fn) && firstNameCount.get(fn) > 1;

            String line = '  - ' + c.FirstName + ' ' + c.LastName;
            if (String.isNotBlank(c.Title))  line += ' | ' + c.Title;
            if (String.isNotBlank(c.Phone))  line += ' | ' + c.Phone;
            if (String.isNotBlank(c.Email))  line += ' | ' + c.Email;
            line += ' | Last modified: ' + c.LastModifiedDate.format();
            if (isDup) line += ' [DUPLICATE FIRST NAME]';

            lines.add(line);
        }

        res.contactListSummary = String.join(lines, '\n');
    }
}
