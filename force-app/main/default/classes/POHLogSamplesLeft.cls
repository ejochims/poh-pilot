public with sharing class POHLogSamplesLeft {

    public class Request {
        @InvocableVariable(label='Account ID' required=true)
        public String accountId;

        @InvocableVariable(label='Samples Summary' required=true description='Natural language description of samples left (e.g., "12 tubes Crest Gum Detoxify, 2 Oral-B iO Series 9")')
        public String samplesSummary;

        @InvocableVariable(label='Visit Date' description='ISO datetime of the visit — used as Order_Date__c on the sample records.')
        public String visitDate;
    }

    public class Response {
        @InvocableVariable(label='Samples Logged Summary')
        public String samplesLoggedSummary;
    }

    @InvocableMethod(label='POH Log Samples Left' description='Creates Order_Item__c records with Ship_Plan_Type__c = Sample Drop for each product and quantity mentioned. Updates Last_iO_Sample_Date__c on Account if iO samples were dropped.')
    public static List<Response> logSamplesLeft(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) return results;

        for (Request req : requests) {
            Response res = new Response();
            try {
                createSampleRecords(req, res);
            } catch (Exception e) {
                res.samplesLoggedSummary = 'Error logging samples: ' + e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    private static void createSampleRecords(Request req, Response res) {
        if (String.isBlank(req.accountId) || String.isBlank(req.samplesSummary)) {
            res.samplesLoggedSummary = 'No account ID or samples summary provided.';
            return;
        }

        Date visitDateVal = Date.today();
        if (String.isNotBlank(req.visitDate)) {
            try {
                DateTime parsed = (DateTime) JSON.deserialize('"' + req.visitDate + '"', DateTime.class);
                visitDateVal = parsed.date();
            } catch (Exception e) {
                // keep today
            }
        }

        // Parse the natural language samples summary
        // Expects patterns like: "12 tubes Crest Gum Detoxify, 2 Oral-B iO Series 9"
        List<ParsedSample> parsedSamples = parseSamplesSummary(req.samplesSummary);

        if (parsedSamples.isEmpty()) {
            // Create one generic record with the full summary text
            Order_Item__c genericRec = new Order_Item__c();
            genericRec.Account__c = (Id) req.accountId;
            genericRec.Ship_Plan_Type__c = 'Sample Drop';
            genericRec.Order_Date__c = visitDateVal;
            genericRec.Product_Name__c = req.samplesSummary.abbreviate(255);
            genericRec.Quantity__c = 1;
            genericRec.Product_Family__c = 'Other';
            insert genericRec;
            res.samplesLoggedSummary = 'Sample drop recorded: ' + req.samplesSummary;
            return;
        }

        List<Order_Item__c> records = new List<Order_Item__c>();
        Boolean hasIOSample = false;

        for (ParsedSample ps : parsedSamples) {
            Order_Item__c rec = new Order_Item__c();
            rec.Account__c = (Id) req.accountId;
            rec.Ship_Plan_Type__c = 'Sample Drop';
            rec.Order_Date__c = visitDateVal;
            rec.Product_Name__c = ps.productName.abbreviate(255);
            rec.Quantity__c = ps.quantity;

            // Classify family
            String lower = ps.productName.toLowerCase();
            if (lower.contains('io') || lower.contains('oral-b i') || lower.contains('power') || lower.contains('electric')) {
                rec.Product_Family__c = 'Power';
                hasIOSample = true;
            } else if (lower.contains('paste') || lower.contains('gum') || lower.contains('crest') || lower.contains('whitening') || lower.contains('colgate')) {
                rec.Product_Family__c = 'Toothpaste';
            } else if (lower.contains('floss') || lower.contains('flosser')) {
                rec.Product_Family__c = 'Floss';
            } else if (lower.contains('brush') || lower.contains('manual') || lower.contains('oral-b')) {
                rec.Product_Family__c = 'Manual';
            } else {
                rec.Product_Family__c = 'Other';
            }

            records.add(rec);
        }

        insert records;

        // Update Account's Last_iO_Sample_Date__c if iO was dropped
        if (hasIOSample) {
            Account acct = new Account(Id = (Id) req.accountId);
            acct.Last_iO_Sample_Date__c = visitDateVal;
            update acct;
        }

        List<String> confParts = new List<String>();
        for (ParsedSample ps : parsedSamples) {
            confParts.add(ps.quantity.intValue() + ' x ' + ps.productName);
        }
        res.samplesLoggedSummary = 'Sample drop recorded: ' + String.join(confParts, ', ')
            + (hasIOSample ? '. Last_iO_Sample_Date__c updated.' : '') + '.';
    }

    private static List<ParsedSample> parseSamplesSummary(String summaryText) {
        List<ParsedSample> results = new List<ParsedSample>();
        if (String.isBlank(summaryText)) return results;

        // Split on commas or "and" to get individual items
        List<String> segments = summaryText.split('[,]|\\band\\b');

        for (String segment : segments) {
            segment = segment.trim();
            if (String.isBlank(segment)) continue;

            // Try to extract leading number followed by product name
            // Pattern: "12 tubes Crest Gum Detoxify" or "2 Oral-B iO" or "1 CS ..."
            Matcher m = Pattern.compile('^(\\d+)\\s+(?:tubes?|boxes?|packs?|samples?|cs|box|units?)?\\s*(.+)$').matcher(segment.toLowerCase());
            if (m.matches()) {
                ParsedSample ps = new ParsedSample();
                ps.quantity = Decimal.valueOf(m.group(1));
                // Restore original casing from segment
                String productRaw = segment.replaceFirst('^\\d+\\s+(?:tubes?|boxes?|packs?|samples?|cs|box|units?)?\\s*', '').trim();
                ps.productName = String.isNotBlank(productRaw) ? productRaw : segment;
                results.add(ps);
            } else {
                // No quantity found — treat as 1 unit
                ParsedSample ps = new ParsedSample();
                ps.quantity = 1;
                ps.productName = segment;
                results.add(ps);
            }
        }

        return results;
    }

    private class ParsedSample {
        public Decimal quantity;
        public String productName;
    }
}
