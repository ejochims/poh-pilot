public with sharing class POHPreCallBriefData {

    public class Request {
        @InvocableVariable(required=true description='Salesforce Account ID for the target dental practice')
        public String accountId;
    }

    public class Response {
        @InvocableVariable
        public String Prompt;
    }

    @InvocableMethod(
        label='POH Get Pre-Call Brief Data'
        description='Consolidated data provider for the POH Pre Call Brief prompt template. Fetches practice profile, 12-month visit history, order and ship plan history, and sampling history in a single call. Returns all data as a structured prompt string.'
    )
    public static List<Response> getBriefData(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) return results;

        for (Request req : requests) {
            Response res = new Response();
            res.Prompt = buildAllData(req.accountId);
            results.add(res);
        }
        return results;
    }

    private static String buildAllData(String accountId) {
        if (String.isBlank(accountId)) return 'No account ID provided.';

        // 1. Practice Profile
        POHGetAccountBrief.Request briefReq = new POHGetAccountBrief.Request();
        briefReq.accountId = accountId;
        List<POHGetAccountBrief.Response> briefResults = POHGetAccountBrief.getAccountBrief(
            new List<POHGetAccountBrief.Request>{ briefReq }
        );
        String accountName = briefResults.isEmpty() ? 'Unknown Account' : briefResults[0].accountName;
        String accountData = briefResults.isEmpty() ? 'Account not found.' : briefResults[0].accountData;

        // 2. Visit History — past 12 months
        POHGetVisitHistory.Request visitReq = new POHGetVisitHistory.Request();
        visitReq.accountId = accountId;
        visitReq.lookbackDays = 365;
        List<POHGetVisitHistory.Response> visitResults = POHGetVisitHistory.getVisitHistory(
            new List<POHGetVisitHistory.Request>{ visitReq }
        );
        String visitData = visitResults.isEmpty() ? 'No visit history available.' : visitResults[0].visitHistorySummary;

        // 3. Order and Ship Plan History
        POHGetOrderHistory.Request orderReq = new POHGetOrderHistory.Request();
        orderReq.accountId = accountId;
        List<POHGetOrderHistory.Response> orderResults = POHGetOrderHistory.getOrderHistory(
            new List<POHGetOrderHistory.Request>{ orderReq }
        );
        String orderData = orderResults.isEmpty() ? 'No order history available.' : orderResults[0].orderHistorySummary;

        // 4. Sampling History — past 24 months
        POHGetSamplingHistory.Request sampleReq = new POHGetSamplingHistory.Request();
        sampleReq.accountId = accountId;
        List<POHGetSamplingHistory.Response> sampleResults = POHGetSamplingHistory.getSamplingHistory(
            new List<POHGetSamplingHistory.Request>{ sampleReq }
        );
        String sampleData = sampleResults.isEmpty() ? 'No sampling history available.' : sampleResults[0].sampleHistorySummary;

        List<String> sections = new List<String>{
            'ACCOUNT: ' + accountName + ' (ID: ' + accountId + ')',
            '',
            '=== PRACTICE PROFILE ===',
            accountData,
            '',
            '=== VISIT HISTORY — PAST 12 MONTHS ===',
            visitData,
            '',
            '=== ORDER AND SHIP PLAN HISTORY ===',
            orderData,
            '',
            '=== SAMPLING HISTORY — PAST 24 MONTHS ===',
            sampleData
        };

        return String.join(sections, '\n');
    }
}
