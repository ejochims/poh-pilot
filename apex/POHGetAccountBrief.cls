/**
 * Fetches the dental practice profile for the Pre-Call Brief.
 * Updated from poh-pilot to read the multi-select dispense/recommend schema
 * and the expanded demographic fields introduced for the P&G Sales Companion.
 */
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

    @InvocableMethod(
        label='POH Get Account Brief'
        description='Fetches practice profile: name, address, specialty, dentist/hygienist counts, multi-select dispense and recommend categories, ship plan, competitor brands, last iO sample date, and AI Sales Companion recommendation.'
        category='P&G Sales Companion'
    )
    public static List<Response> getAccountBrief(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) return results;

        Set<Id> accountIds = new Set<Id>();
        for (Request r : requests) {
            if (String.isNotBlank(r.accountId)) {
                accountIds.add((Id) r.accountId);
            }
        }

        Map<Id, Account> accountsById = new Map<Id, Account>([
            SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode,
                   Phone, Website,
                   Practice_Specialty__c,
                   Number_of_Dentists__c, Number_of_Hygienists__c,
                   Number_of_Ortho_Pedo__c, Number_of_Weekly_Patients__c,
                   Office_Dispense_Power__c, Office_Dispense_Manual__c,
                   Office_Dispense_Paste__c, Office_Dispense_Whitening__c,
                   Office_Dispense_Waterflosser__c,
                   Office_Recommends_Whitening__c, Office_Recommends_Waterflosser__c,
                   Ship_Plan_Status__c, Ship_Plan_Product__c, Ship_Plan_Cadence__c,
                   Competitor_Brands_Seen__c,
                   Last_iO_Sample_Date__c,
                   AI_Sales_Companion_Recommendation__c
            FROM Account
            WHERE Id IN :accountIds
        ]);

        for (Request req : requests) {
            Response res = new Response();
            Account acct = accountsById.get((Id) req.accountId);

            if (acct == null) {
                res.accountName = 'Unknown Account';
                res.accountData = 'Account not found.';
                results.add(res);
                continue;
            }

            res.accountName = acct.Name;
            res.accountData  = buildAccountProfile(acct);
            results.add(res);
        }

        return results;
    }

    private static String buildAccountProfile(Account acct) {
        List<String> lines = new List<String>();

        // Address
        List<String> addrParts = new List<String>();
        if (String.isNotBlank(acct.BillingStreet))     addrParts.add(acct.BillingStreet);
        if (String.isNotBlank(acct.BillingCity))       addrParts.add(acct.BillingCity);
        if (String.isNotBlank(acct.BillingState))      addrParts.add(acct.BillingState);
        if (String.isNotBlank(acct.BillingPostalCode)) addrParts.add(acct.BillingPostalCode);
        lines.add('Address: ' + (addrParts.isEmpty() ? 'Not on file' : String.join(addrParts, ', ')));

        lines.add('Specialty: ' + (String.isNotBlank(acct.Practice_Specialty__c) ? acct.Practice_Specialty__c : 'Not set'));

        // Demographics
        lines.add('Dentists (DDS): '     + (acct.Number_of_Dentists__c    != null ? String.valueOf(acct.Number_of_Dentists__c.intValue())    : 'Not set'));
        lines.add('Hygienists (RDH): '   + (acct.Number_of_Hygienists__c  != null ? String.valueOf(acct.Number_of_Hygienists__c.intValue())  : 'Not set'));
        lines.add('Ortho/Pedo staff: '   + (acct.Number_of_Ortho_Pedo__c  != null ? String.valueOf(acct.Number_of_Ortho_Pedo__c.intValue())  : 'Not set'));
        lines.add('Weekly patients: '    + (acct.Number_of_Weekly_Patients__c != null ? String.valueOf(acct.Number_of_Weekly_Patients__c.intValue()) : 'Not set'));

        // Office Dispense
        lines.add('Office Dispenses (Power Brush): '   + formatMultiSelect(acct.Office_Dispense_Power__c));
        lines.add('Office Dispenses (Manual Brush): '  + formatMultiSelect(acct.Office_Dispense_Manual__c));
        lines.add('Office Dispenses (Toothpaste): '    + formatMultiSelect(acct.Office_Dispense_Paste__c));
        lines.add('Office Dispenses (Whitening): '     + formatMultiSelect(acct.Office_Dispense_Whitening__c));
        lines.add('Office Dispenses (Waterflosser): '  + formatMultiSelect(acct.Office_Dispense_Waterflosser__c));

        // Office Recommends
        lines.add('Office Recommends (Whitening): '    + formatMultiSelect(acct.Office_Recommends_Whitening__c));
        lines.add('Office Recommends (Waterflosser): ' + formatMultiSelect(acct.Office_Recommends_Waterflosser__c));

        // Ship Plan
        String shipStatus  = String.isNotBlank(acct.Ship_Plan_Status__c)  ? acct.Ship_Plan_Status__c  : 'Not enrolled';
        String shipProduct = String.isNotBlank(acct.Ship_Plan_Product__c) ? acct.Ship_Plan_Product__c : 'N/A';
        String shipCadence = String.isNotBlank(acct.Ship_Plan_Cadence__c) ? acct.Ship_Plan_Cadence__c : 'N/A';
        lines.add('Ship Plan: ' + shipStatus + ' — ' + shipProduct + ' at ' + shipCadence);

        // Competitors & iO
        lines.add('Competitor Brands Seen: ' + (String.isNotBlank(acct.Competitor_Brands_Seen__c) ? acct.Competitor_Brands_Seen__c : 'None recorded'));
        lines.add('Last iO Sample Date: ' + (acct.Last_iO_Sample_Date__c != null ? acct.Last_iO_Sample_Date__c.format() : 'Never recorded'));

        // AI recommendation
        String aiRec = String.isNotBlank(acct.AI_Sales_Companion_Recommendation__c)
            ? acct.AI_Sales_Companion_Recommendation__c
            : 'No recommendation available.';
        lines.add('AI Sales Companion Recommendation: ' + aiRec);

        return String.join(lines, '\n');
    }

    private static String formatMultiSelect(String rawValue) {
        if (String.isBlank(rawValue)) return 'Not set';
        List<String> trimmed = new List<String>();
        for (String v : rawValue.split(';')) {
            trimmed.add(v.trim());
        }
        return String.join(trimmed, ', ');
    }
}
