/**
 * Invocable action for the PostVisitLogger subagent.
 * Updates intelligence fields on the dental practice Account.
 * Only non-null inputs are applied — the planner can omit any field
 * that was not mentioned, and no DML is issued if nothing changed.
 */
public with sharing class UpdateAccountAttributesAction {

    public class Request {
        @InvocableVariable(label='Account ID' description='Salesforce Account Id resolved by IdentifyRecordByName' required=true)
        public String accountId;

        // Demographics
        @InvocableVariable(label='Number of Dentists')          public Integer numberOfDentists;
        @InvocableVariable(label='Number of Hygienists')        public Integer numberOfHygienists;
        @InvocableVariable(label='Number of Ortho/Pedo')        public Integer numberOfOrthoPedo;
        @InvocableVariable(label='Number of Weekly Patients')   public Integer numberOfWeeklyPatients;

        // Office Dispense multi-selects
        @InvocableVariable(label='Office Dispense Power')        public String officeDispensePower;
        @InvocableVariable(label='Office Dispense Manual')       public String officeDispenseManual;
        @InvocableVariable(label='Office Dispense Paste')        public String officeDispensePaste;
        @InvocableVariable(label='Office Dispense Whitening')    public String officeDispenseWhitening;
        @InvocableVariable(label='Office Dispense Waterflosser') public String officeDispenseWaterflosser;

        // Office Recommends multi-selects
        @InvocableVariable(label='Office Recommends Whitening')    public String officeRecommendsWhitening;
        @InvocableVariable(label='Office Recommends Waterflosser') public String officeRecommendsWaterflosser;

        // Ship Plan
        @InvocableVariable(label='Ship Plan Status')  public String shipPlanStatus;
        @InvocableVariable(label='Ship Plan Product') public String shipPlanProduct;
        @InvocableVariable(label='Ship Plan Cadence') public String shipPlanCadence;

        // Briefing fields
        @InvocableVariable(label='Practice Specialty')     public String practiceSpecialty;
        @InvocableVariable(label='Competitor Brands Seen') public String competitorBrandsSeen;

        @InvocableVariable(label='Replace Multi-selects' description='When true, overwrites existing multi-select values. When false (default), appends new values to existing selections.')
        public Boolean replaceMulitSelect;
    }

    public class Response {
        @InvocableVariable(label='Changed Fields') public List<String> changedFields;
        @InvocableVariable(label='Summary')        public String summary;
        @InvocableVariable(label='Success')        public Boolean isSuccess;
        @InvocableVariable(label='Error Message')  public String errorMessage;
    }

    @InvocableMethod(
        label='Update Account Attributes'
        description='Update intelligence about the dental practice itself — dentist count, what the office dispenses, ship plan status, weekly patient volume. Call ONLY when the rep states a CHANGE or NEW data point about the office. Do NOT call when the rep is restating known information or describing what was discussed in a visit.'
        category='P&G Sales Companion'
    )
    public static List<Response> updateAttributes(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            try {
                responses.add(applyUpdates(req));
            } catch (Exception ex) {
                System.debug('UpdateAccountAttributesAction failed: ' + ex.getMessage() + ' | ' + ex.getStackTraceString());
                responses.add(buildError(ex));
            }
        }
        return responses;
    }

    private static Response applyUpdates(Request req) {
        List<String> changedFields = new List<String>();
        Account account = new Account(Id = (Id) req.accountId);
        Boolean replace = req.replaceMulitSelect == true;

        Account existing = null;
        if (!replace && hasMultiSelectInput(req)) {
            existing = [
                SELECT Office_Dispense_Power__c, Office_Dispense_Manual__c,
                       Office_Dispense_Paste__c, Office_Dispense_Whitening__c,
                       Office_Dispense_Waterflosser__c,
                       Office_Recommends_Whitening__c, Office_Recommends_Waterflosser__c
                FROM Account
                WHERE Id = :req.accountId
                LIMIT 1
            ];
        }

        // Demographics
        if (req.numberOfDentists != null) {
            account.Number_of_Dentists__c = req.numberOfDentists;
            changedFields.add('Number of Dentists → ' + req.numberOfDentists);
        }
        if (req.numberOfHygienists != null) {
            account.Number_of_Hygienists__c = req.numberOfHygienists;
            changedFields.add('Number of Hygienists → ' + req.numberOfHygienists);
        }
        if (req.numberOfOrthoPedo != null) {
            account.Number_of_Ortho_Pedo__c = req.numberOfOrthoPedo;
            changedFields.add('Number of Ortho/Pedo → ' + req.numberOfOrthoPedo);
        }
        if (req.numberOfWeeklyPatients != null) {
            account.Number_of_Weekly_Patients__c = req.numberOfWeeklyPatients;
            changedFields.add('Weekly Patients → ' + req.numberOfWeeklyPatients);
        }

        // Office Dispense multi-selects
        if (String.isNotBlank(req.officeDispensePower)) {
            account.Office_Dispense_Power__c = mergeMultiSelect(existing?.Office_Dispense_Power__c, req.officeDispensePower, replace);
            changedFields.add('Office Dispense Power');
        }
        if (String.isNotBlank(req.officeDispenseManual)) {
            account.Office_Dispense_Manual__c = mergeMultiSelect(existing?.Office_Dispense_Manual__c, req.officeDispenseManual, replace);
            changedFields.add('Office Dispense Manual');
        }
        if (String.isNotBlank(req.officeDispensePaste)) {
            account.Office_Dispense_Paste__c = mergeMultiSelect(existing?.Office_Dispense_Paste__c, req.officeDispensePaste, replace);
            changedFields.add('Office Dispense Paste');
        }
        if (String.isNotBlank(req.officeDispenseWhitening)) {
            account.Office_Dispense_Whitening__c = mergeMultiSelect(existing?.Office_Dispense_Whitening__c, req.officeDispenseWhitening, replace);
            changedFields.add('Office Dispense Whitening');
        }
        if (String.isNotBlank(req.officeDispenseWaterflosser)) {
            account.Office_Dispense_Waterflosser__c = mergeMultiSelect(existing?.Office_Dispense_Waterflosser__c, req.officeDispenseWaterflosser, replace);
            changedFields.add('Office Dispense Waterflosser');
        }

        // Office Recommends multi-selects
        if (String.isNotBlank(req.officeRecommendsWhitening)) {
            account.Office_Recommends_Whitening__c = mergeMultiSelect(existing?.Office_Recommends_Whitening__c, req.officeRecommendsWhitening, replace);
            changedFields.add('Office Recommends Whitening');
        }
        if (String.isNotBlank(req.officeRecommendsWaterflosser)) {
            account.Office_Recommends_Waterflosser__c = mergeMultiSelect(existing?.Office_Recommends_Waterflosser__c, req.officeRecommendsWaterflosser, replace);
            changedFields.add('Office Recommends Waterflosser');
        }

        // Ship Plan
        if (String.isNotBlank(req.shipPlanStatus)) {
            account.Ship_Plan_Status__c = req.shipPlanStatus;
            changedFields.add('Ship Plan Status → ' + req.shipPlanStatus);
        }
        if (String.isNotBlank(req.shipPlanProduct)) {
            account.Ship_Plan_Product__c = req.shipPlanProduct;
            changedFields.add('Ship Plan Product → ' + req.shipPlanProduct);
        }
        if (String.isNotBlank(req.shipPlanCadence)) {
            account.Ship_Plan_Cadence__c = req.shipPlanCadence;
            changedFields.add('Ship Plan Cadence → ' + req.shipPlanCadence);
        }

        // Briefing fields
        if (String.isNotBlank(req.practiceSpecialty)) {
            account.Practice_Specialty__c = req.practiceSpecialty;
            changedFields.add('Practice Specialty → ' + req.practiceSpecialty);
        }
        if (String.isNotBlank(req.competitorBrandsSeen)) {
            account.Competitor_Brands_Seen__c = req.competitorBrandsSeen;
            changedFields.add('Competitor Brands Seen');
        }

        if (changedFields.isEmpty()) {
            Response r = new Response();
            r.changedFields = new List<String>();
            r.summary       = 'No account attributes to update.';
            r.isSuccess     = true;
            return r;
        }

        update account;

        Response r = new Response();
        r.changedFields = changedFields;
        r.summary       = 'Updated ' + changedFields.size() + ' field(s): ' + String.join(changedFields, ', ') + '.';
        r.isSuccess     = true;
        return r;
    }

    private static Boolean hasMultiSelectInput(Request req) {
        return String.isNotBlank(req.officeDispensePower)       ||
               String.isNotBlank(req.officeDispenseManual)      ||
               String.isNotBlank(req.officeDispensePaste)       ||
               String.isNotBlank(req.officeDispenseWhitening)   ||
               String.isNotBlank(req.officeDispenseWaterflosser)||
               String.isNotBlank(req.officeRecommendsWhitening) ||
               String.isNotBlank(req.officeRecommendsWaterflosser);
    }

    private static String mergeMultiSelect(String existing, String incoming, Boolean replace) {
        if (replace || String.isBlank(existing)) return incoming;
        Set<String> merged = new Set<String>(existing.split(';'));
        merged.addAll(incoming.split(';'));
        List<String> sorted = new List<String>(merged);
        sorted.sort();
        return String.join(sorted, ';');
    }

    private static Response buildError(Exception ex) {
        Response r = new Response();
        r.isSuccess    = false;
        r.errorMessage = 'Unable to update account attributes. Please try again or contact your admin.';
        r.summary      = r.errorMessage;
        r.changedFields = new List<String>();
        return r;
    }
}
