public with sharing class POHGetAccountBrief {

    public class Request {
        @InvocableVariable(label='Account ID' required=true)
        public String accountId;
    }

    public class Response {
        @InvocableVariable(label='Account Name')
        public String accountName;

        @InvocableVariable(label='Account Data Summary')
        public String accountData;
    }

    @InvocableMethod(label='POH Get Account Brief' description='Fetches practice profile: name, address, specialty, DDS/RDH counts, dispensing/recommending flags, competitor brands, last iO sample date, and AI Sales Companion recommendation.')
    public static List<Response> getAccountBrief(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) return results;

        Set<Id> accountIds = new Set<Id>();
        for (Request r : requests) {
            if (String.isNotBlank(r.accountId)) {
                accountIds.add((Id) r.accountId);
            }
        }

        Map<Id, Account> accountMap = new Map<Id, Account>([
            SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode,
                   Phone, Website,
                   Practice_Specialty__c,
                   Number_of_DDS__c, Number_of_RDH__c,
                   Dispenses_Power__c, Dispenses_Manual__c,
                   Recommends_Power__c, Recommends_Manual__c,
                   Competitor_Brands_Seen__c,
                   Last_iO_Sample_Date__c,
                   AI_Sales_Companion_Recommendation__c
            FROM Account
            WHERE Id IN :accountIds
        ]);

        for (Request req : requests) {
            Response res = new Response();
            Account acct = accountMap.get((Id) req.accountId);
            if (acct == null) {
                res.accountName = 'Unknown Account';
                res.accountData = 'Account not found.';
                results.add(res);
                continue;
            }

            res.accountName = acct.Name;

            List<String> lines = new List<String>();

            // Address
            List<String> addrParts = new List<String>();
            if (String.isNotBlank(acct.BillingStreet))      addrParts.add(acct.BillingStreet);
            if (String.isNotBlank(acct.BillingCity))        addrParts.add(acct.BillingCity);
            if (String.isNotBlank(acct.BillingState))       addrParts.add(acct.BillingState);
            if (String.isNotBlank(acct.BillingPostalCode))  addrParts.add(acct.BillingPostalCode);
            lines.add('Address: ' + (addrParts.isEmpty() ? 'Not on file' : String.join(addrParts, ', ')));

            // Practice profile
            lines.add('Specialty: ' + (acct.Practice_Specialty__c != null ? acct.Practice_Specialty__c : 'Not set'));
            lines.add('Dentists (DDS): ' + (acct.Number_of_DDS__c != null ? String.valueOf(acct.Number_of_DDS__c.intValue()) : 'Not set'));
            lines.add('Hygienists (RDH): ' + (acct.Number_of_RDH__c != null ? String.valueOf(acct.Number_of_RDH__c.intValue()) : 'Not set'));

            // Dispensing / recommending
            String dispenses = buildDispenseRecommendLine(acct.Dispenses_Power__c, acct.Dispenses_Manual__c);
            String recommends = buildDispenseRecommendLine(acct.Recommends_Power__c, acct.Recommends_Manual__c);
            lines.add('Dispenses: ' + dispenses);
            lines.add('Recommends: ' + recommends);

            // Competitors
            String comp = String.isNotBlank(acct.Competitor_Brands_Seen__c) ? acct.Competitor_Brands_Seen__c : 'None recorded';
            lines.add('Competitor Brands Seen: ' + comp);

            // iO sample
            String ioDate = acct.Last_iO_Sample_Date__c != null
                ? acct.Last_iO_Sample_Date__c.format()
                : 'Never recorded';
            lines.add('Last iO Sample Date: ' + ioDate);

            // AI recommendation
            String aiRec = String.isNotBlank(acct.AI_Sales_Companion_Recommendation__c)
                ? acct.AI_Sales_Companion_Recommendation__c
                : 'No recommendation available.';
            lines.add('AI Sales Companion Recommendation: ' + aiRec);

            res.accountData = String.join(lines, '\n');
            results.add(res);
        }

        return results;
    }

    private static String buildDispenseRecommendLine(Boolean power, Boolean manual) {
        List<String> items = new List<String>();
        if (power == true)  items.add('Oral-B Power');
        if (manual == true) items.add('Oral-B Manual');
        return items.isEmpty() ? 'Neither Power nor Manual' : String.join(items, ', ');
    }
}
