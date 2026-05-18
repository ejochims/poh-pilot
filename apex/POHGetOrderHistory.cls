/**
 * Returns past and upcoming Order_Item__c records for a dental practice,
 * grouped by product family and ship plan type.
 * Ported unchanged from poh-pilot (Order_Item__c schema is preserved).
 */
public with sharing class POHGetOrderHistory {

    public class Request {
        @InvocableVariable(label='Account ID' required=true)
        public String accountId;
    }

    public class Response {
        @InvocableVariable(label='Order History Summary')
        public String orderHistorySummary;
    }

    @InvocableMethod(
        label='POH Get Order History'
        description='Returns Order_Item__c records for the Account: past 12 months grouped by product family and ship plan type, plus upcoming planned deliveries. Includes ship plan detection.'
        category='P&G Sales Companion'
    )
    public static List<Response> getOrderHistory(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) return results;

        for (Request req : requests) {
            Response res = new Response();
            res.orderHistorySummary = buildSummary(req.accountId);
            results.add(res);
        }
        return results;
    }

    private static String buildSummary(String accountId) {
        if (String.isBlank(accountId)) return 'No account ID provided.';

        Date pastCutoff   = Date.today().addDays(-365);
        Date futureCutoff = Date.today().addDays(365);

        List<Order_Item__c> allItems = [
            SELECT Id, Product_Name__c, Product_Family__c, Quantity__c,
                   Order_Date__c, Ship_Plan_Type__c, Is_Future_Order__c,
                   Product__r.Name, Product__r.Family
            FROM Order_Item__c
            WHERE Account__c = :accountId
            AND Order_Date__c >= :pastCutoff
            AND Order_Date__c <= :futureCutoff
            ORDER BY Order_Date__c DESC
        ];

        if (allItems.isEmpty()) {
            return 'No order history for this account in the past 12 months or upcoming 12 months.';
        }

        List<Order_Item__c> pastItems   = new List<Order_Item__c>();
        List<Order_Item__c> futureItems = new List<Order_Item__c>();
        for (Order_Item__c oi : allItems) {
            if (oi.Is_Future_Order__c == true) {
                futureItems.add(oi);
            } else {
                pastItems.add(oi);
            }
        }

        List<String> lines = new List<String>();

        lines.add('PAST 12 MONTHS (' + pastItems.size() + ' order records):');
        if (pastItems.isEmpty()) {
            lines.add('  No past orders in the last 12 months.');
        } else {
            Map<String, Map<String, Decimal>> quantityByFamilyAndType = new Map<String, Map<String, Decimal>>();
            for (Order_Item__c oi : pastItems) {
                String family   = String.isNotBlank(oi.Product_Family__c) ? oi.Product_Family__c : 'Other';
                String planType = String.isNotBlank(oi.Ship_Plan_Type__c) ? oi.Ship_Plan_Type__c : 'Unspecified';
                if (!quantityByFamilyAndType.containsKey(family)) {
                    quantityByFamilyAndType.put(family, new Map<String, Decimal>());
                }
                Decimal current = quantityByFamilyAndType.get(family).containsKey(planType)
                    ? quantityByFamilyAndType.get(family).get(planType) : 0;
                quantityByFamilyAndType.get(family).put(planType, current + (oi.Quantity__c != null ? oi.Quantity__c : 0));
            }
            for (String family : quantityByFamilyAndType.keySet()) {
                for (String planType : quantityByFamilyAndType.get(family).keySet()) {
                    Decimal qty = quantityByFamilyAndType.get(family).get(planType);
                    lines.add('  ' + family + ' | ' + planType + ': ' + qty.intValue() + ' units');
                }
            }

            Boolean hasShipPlan = false;
            String shipPlanType = '';
            for (Order_Item__c oi : pastItems) {
                if (oi.Ship_Plan_Type__c == 'Manual Ship Plan' || oi.Ship_Plan_Type__c == 'Auto Ship Plan') {
                    hasShipPlan = true;
                    shipPlanType = oi.Ship_Plan_Type__c;
                    break;
                }
            }
            if (hasShipPlan) {
                lines.add('  Ship Plan Type detected: ' + shipPlanType);
            } else {
                lines.add('  Note: No active ship plan detected — orders appear to be One-Time or manual.');
            }
        }

        lines.add('');
        lines.add('UPCOMING SHIP PLAN ORDERS (' + futureItems.size() + ' records):');
        if (futureItems.isEmpty()) {
            lines.add('  No future ship plan orders on file.');
        } else {
            for (Order_Item__c oi : futureItems) {
                String productName = String.isNotBlank(oi.Product_Name__c) ? oi.Product_Name__c
                    : (oi.Product__r != null && String.isNotBlank(oi.Product__r.Name) ? oi.Product__r.Name : 'Unknown Product');
                String qty       = oi.Quantity__c != null ? String.valueOf(oi.Quantity__c.intValue()) : '0';
                String orderDate = oi.Order_Date__c != null ? oi.Order_Date__c.format() : 'TBD';
                String planType  = String.isNotBlank(oi.Ship_Plan_Type__c) ? oi.Ship_Plan_Type__c : 'Unspecified';
                lines.add('  - ' + orderDate + ': ' + productName + ' ×' + qty + ' (' + planType + ')');
            }
        }

        return String.join(lines, '\n');
    }
}
