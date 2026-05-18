/**
 * Returns sample drop history for a dental practice.
 * Flags stale Oral-B iO sampling (over 2 years ago) — a key demo talking point.
 * Ported unchanged from poh-pilot (Order_Item__c schema is preserved).
 */
public with sharing class POHGetSamplingHistory {

    public class Request {
        @InvocableVariable(label='Account ID' required=true)
        public String accountId;
    }

    public class Response {
        @InvocableVariable(label='Sample History Summary')
        public String sampleHistorySummary;
    }

    @InvocableMethod(
        label='POH Get Sampling History'
        description='Returns Sample Drop Order_Item__c records for the past 24 months. Flags last iO sample date and stale status (over 2 years = re-sample opportunity).'
        category='P&G Sales Companion'
    )
    public static List<Response> getSamplingHistory(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) return results;

        for (Request req : requests) {
            Response res = new Response();
            res.sampleHistorySummary = buildSummary(req.accountId);
            results.add(res);
        }
        return results;
    }

    private static String buildSummary(String accountId) {
        if (String.isBlank(accountId)) return 'No account ID provided.';

        Date cutoff24Mo = Date.today().addDays(-730);

        List<Order_Item__c> samples = [
            SELECT Id, Product_Name__c, Product_Family__c, Quantity__c,
                   Order_Date__c, Product__r.Name, Product__r.Family
            FROM Order_Item__c
            WHERE Account__c = :accountId
            AND Ship_Plan_Type__c = 'Sample Drop'
            AND Order_Date__c >= :cutoff24Mo
            ORDER BY Order_Date__c DESC
        ];

        if (samples.isEmpty()) {
            return 'No sample drops recorded in the past 24 months.';
        }

        List<String> lines = new List<String>();
        lines.add('SAMPLE DROPS — Past 24 Months (' + samples.size() + ' records):');

        Date lastIODate = null;

        for (Order_Item__c s : samples) {
            String productName = String.isNotBlank(s.Product_Name__c) ? s.Product_Name__c
                : (s.Product__r != null && String.isNotBlank(s.Product__r.Name) ? s.Product__r.Name : 'Unknown Product');
            String family  = String.isNotBlank(s.Product_Family__c) ? s.Product_Family__c : 'Other';
            String qty     = s.Quantity__c != null ? String.valueOf(s.Quantity__c.intValue()) : '?';
            String dateStr = s.Order_Date__c != null ? s.Order_Date__c.format() : 'Unknown date';

            lines.add('  - ' + dateStr + ': ' + productName + ' ×' + qty + ' (' + family + ')');

            if (family == 'Power' && s.Order_Date__c != null) {
                if (lastIODate == null || s.Order_Date__c > lastIODate) {
                    lastIODate = s.Order_Date__c;
                }
            }
        }

        lines.add('');
        if (lastIODate != null) {
            Integer daysSince = lastIODate.daysBetween(Date.today());
            Boolean isStale = daysSince > 730;
            lines.add('Last Oral-B iO Sample: ' + lastIODate.format() + ' (' + daysSince + ' days ago)');
            if (isStale) {
                lines.add('WARNING — iO sample is STALE (over 2 years ago). Re-sample any hygienists hired since then.');
            } else {
                lines.add('iO sample recency: OK (within 2 years)');
            }
        } else {
            lines.add('Last Oral-B iO Sample: Not found in sample drop records.');
            lines.add('WARNING — iO has not been sampled in the recorded window. Consider a fresh iO drop.');
        }

        return String.join(lines, '\n');
    }
}
