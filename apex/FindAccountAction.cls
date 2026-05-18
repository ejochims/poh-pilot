/**
 * Resolves a dental practice name to its Salesforce Account ID.
 * Wraps SOQL fuzzy matching for use as an Agentforce invocable action,
 * replacing standardInvocableAction://IdentifyRecordByName which fails
 * during GenAiFunctionDefinition creation in this org.
 */
public with sharing class FindAccountAction {

    @InvocableMethod(
        label='Find Account by Name'
        description='Resolves a dental practice name to its Salesforce Account ID using name-based search'
        category='Sales Companion'
    )
    public static List<Output> findAccount(List<Input> inputs) {
        System.debug('FindAccountAction.findAccount() enter — name: ' + inputs[0].accountName);
        Input req = inputs[0];
        Output out = new Output();

        try {
            String searchTerm = '%' + req.accountName.trim() + '%';
            List<Account> matches = [
                SELECT Id, Name
                FROM Account
                WHERE Name LIKE :searchTerm
                ORDER BY Name
                LIMIT 5
            ];

            if (matches.isEmpty()) {
                out.accountId = '';
                out.accountName = '';
                out.matchCount = 0;
                out.candidateNames = new List<String>();
                out.isSuccess = true;
            } else {
                out.accountId = matches[0].Id;
                out.accountName = matches[0].Name;
                out.matchCount = matches.size();
                List<String> names = new List<String>();
                for (Account a : matches) { names.add(a.Name); }
                out.candidateNames = names;
                out.isSuccess = true;
            }
            System.debug('FindAccountAction.findAccount() exit — matched: ' + out.matchCount);
        } catch (Exception ex) {
            System.debug('FindAccountAction.findAccount() error: ' + ex.getMessage());
            out.accountId = '';
            out.accountName = '';
            out.matchCount = 0;
            out.candidateNames = new List<String>();
            out.isSuccess = false;
            out.errorMessage = ex.getMessage();
        }

        return new List<Output>{ out };
    }

    public class Input {
        @InvocableVariable(label='Account Name' description='Dental practice name as spoken by the rep' required=true)
        public String accountName;
    }

    public class Output {
        @InvocableVariable(label='Account ID' description='Salesforce Account ID of the best match')
        public String accountId;

        @InvocableVariable(label='Account Name' description='Full Salesforce name of the matched account')
        public String accountName;

        @InvocableVariable(label='Match Count' description='Number of accounts matched by the name search')
        public Integer matchCount;

        @InvocableVariable(label='Candidate Names' description='Names of all matching accounts (up to 5) for disambiguation')
        public List<String> candidateNames;

        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }
}
