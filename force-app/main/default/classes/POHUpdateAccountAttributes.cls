public with sharing class POHUpdateAccountAttributes {

    public class Request {
        @InvocableVariable(label='Account ID' required=true)
        public String accountId;

        @InvocableVariable(label='Dispenses Power' description='"true" or "false" — whether the practice dispenses Oral-B Power brushes')
        public String dispensesPower;

        @InvocableVariable(label='Dispenses Manual' description='"true" or "false" — whether the practice dispenses Oral-B Manual brushes')
        public String dispensesManual;

        @InvocableVariable(label='Recommends Power' description='"true" or "false" — whether the practice recommends Oral-B Power brushes')
        public String recommendsPower;

        @InvocableVariable(label='Recommends Manual' description='"true" or "false" — whether the practice recommends Oral-B Manual brushes')
        public String recommendsManual;

        @InvocableVariable(label='Competitor Brands' description='Semicolon-separated competitor brands observed (e.g., Sonicare;Colgate)')
        public String competitorBrands;

        @InvocableVariable(label='Number of DDS' description='Updated count of dentists at the practice')
        public String numDDS;

        @InvocableVariable(label='Number of RDH' description='Updated count of registered dental hygienists at the practice')
        public String numRDH;
    }

    public class Response {
        @InvocableVariable(label='Update Summary')
        public String updateSummary;
    }

    @InvocableMethod(label='POH Update Account Attributes' description='Updates Account custom fields the rep observed during the visit: dispensing/recommending status, DDS/RDH counts, competitor brands.')
    public static List<Response> updateAccountAttributes(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) return results;

        for (Request req : requests) {
            Response res = new Response();
            try {
                updateAccount(req, res);
            } catch (Exception e) {
                res.updateSummary = 'Error updating account: ' + e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    private static void updateAccount(Request req, Response res) {
        if (String.isBlank(req.accountId)) {
            res.updateSummary = 'No account ID provided.';
            return;
        }

        Account acct = new Account(Id = (Id) req.accountId);
        List<String> updatedFields = new List<String>();

        if (String.isNotBlank(req.dispensesPower)) {
            acct.Dispenses_Power__c = req.dispensesPower.toLowerCase() == 'true';
            updatedFields.add('Dispenses Power = ' + acct.Dispenses_Power__c);
        }
        if (String.isNotBlank(req.dispensesManual)) {
            acct.Dispenses_Manual__c = req.dispensesManual.toLowerCase() == 'true';
            updatedFields.add('Dispenses Manual = ' + acct.Dispenses_Manual__c);
        }
        if (String.isNotBlank(req.recommendsPower)) {
            acct.Recommends_Power__c = req.recommendsPower.toLowerCase() == 'true';
            updatedFields.add('Recommends Power = ' + acct.Recommends_Power__c);
        }
        if (String.isNotBlank(req.recommendsManual)) {
            acct.Recommends_Manual__c = req.recommendsManual.toLowerCase() == 'true';
            updatedFields.add('Recommends Manual = ' + acct.Recommends_Manual__c);
        }
        if (String.isNotBlank(req.competitorBrands)) {
            // Input is semicolon-separated; convert to multi-select picklist format (semicolon)
            acct.Competitor_Brands_Seen__c = req.competitorBrands.replace(';', ';');
            updatedFields.add('Competitor Brands = ' + req.competitorBrands);
        }
        if (String.isNotBlank(req.numDDS)) {
            try {
                acct.Number_of_DDS__c = Decimal.valueOf(req.numDDS.trim());
                updatedFields.add('Number of DDS = ' + req.numDDS);
            } catch (Exception e) { /* skip if unparseable */ }
        }
        if (String.isNotBlank(req.numRDH)) {
            try {
                acct.Number_of_RDH__c = Decimal.valueOf(req.numRDH.trim());
                updatedFields.add('Number of RDH = ' + req.numRDH);
            } catch (Exception e) { /* skip if unparseable */ }
        }

        if (updatedFields.isEmpty()) {
            res.updateSummary = 'No account attribute changes detected — nothing updated.';
            return;
        }

        update acct;
        res.updateSummary = 'Account updated: ' + String.join(updatedFields, ', ') + '.';
    }
}
