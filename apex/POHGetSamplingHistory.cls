public with sharing class POHGetSamplingHistory {

    public class Request {
        @InvocableVariable(label='Account ID' required=true)
        public String accountId;
    }

    public class Response {
        @InvocableVariable(label='Sample History Summary')
        public String sampleHistorySummary;
    }

    @InvocableMethod(label='POH Get Sampling History' description='Returns sample drop Order_Item__c records for the past 24 months grouped by product. Flags last iO sample date and stale status (over 2 years).')
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
        Map<String, Date> lastSampleByProduct = new Map<String, Date>();

        for (Order_Item__c s : samples) {
            String productName = String.isNotBlank(s.Product_Name__c) ? s.Product_Name__c
                : (s.Product__r != null && String.isNotBlank(s.Product__r.Name) ? s.Product__r.Name : 'Unknown Product');
            String family = String.isNotBlank(s.Product_Family__c) ? s.Product_Family__c : 'Other';
            String qty = s.Quantity__c != null ? String.valueOf(s.Quantity__c.intValue()) : '?';
            String dateStr = s.Order_Date__c != null ? s.Order_Date__c.format() : 'Unknown date';

            lines.add('  - ' + dateStr + ': ' + productName + ' x' + qty + ' (' + family + ')');

            // Track last sample per product
            if (!lastSampleByProduct.containsKey(productName) && s.Order_Date__c != null) {
                lastSampleByProduct.put(productName, s.Order_Date__c);
            }

            // Track last iO sample (Power family)
            if (family == 'Power' && s.Order_Date__c != null) {
                if (lastIODate == null || s.Order_Date__c > lastIODate) {
                    lastIODate = s.Order_Date__c;
                }
            }
        }

        // iO sample recency
        lines.add('');
        if (lastIODate != null) {
            Integer daysSince = lastIODate.daysBetween(Date.today());
            Boolean isStale = daysSince > 730;
            lines.add('Last Oral-B iO Sample: ' + lastIODate.format() + ' (' + daysSince + ' days ago)');
            if (isStale) {
                lines.add('WARNING — iO sample is STALE (over 2 years ago). Recommend re-sampling any hygienists hired since then or reps whose iO battery may no longer hold charge.');
            } else {
                lines.add('iO sample recency: OK (within 2 years)');
            }
        } else {
            lines.add('Last Oral-B iO Sample: Not found in sample drop records (check Last_iO_Sample_Date__c field).');
            lines.add('WARNING — iO has not been sampled in the recorded window. Consider a fresh iO drop.');
        }

        return String.join(lines, '\n');
    }
}
