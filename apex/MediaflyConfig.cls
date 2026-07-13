/**
 * Environment-specific Mediafly configuration for the P&G Sales Companion
 * Level 1 content-search integration.
 *
 * Values are read from the Mediafly_Config__mdt custom metadata type so the
 * Product Id, Company Code, and API version can differ per environment without
 * code changes and without committing tenant-specific values to source control.
 *
 * Expected custom metadata type: Mediafly_Config__mdt
 *   DeveloperName : 'Default'
 *   Company_Code__c (Text)   — Mediafly company code for the tenant
 *   Product_Id__c   (Text)   — Launchpad productId (UUID) for the environment
 *   Api_Version__c  (Number) — Launchpad API version (defaults to 3)
 *
 * REFERENCE IMPLEMENTATION: create the custom metadata type and a 'Default'
 * record in the target org and populate it from the values Mediafly provides.
 * Never hardcode these values in Apex.
 */
public with sharing class MediaflyConfig {

    private static Mediafly_Config__mdt cached;

    private static Mediafly_Config__mdt setting() {
        if (cached == null) {
            cached = Mediafly_Config__mdt.getInstance('Default');
        }
        return cached;
    }

    public static String companyCode() {
        Mediafly_Config__mdt s = setting();
        return s != null ? s.Company_Code__c : null;
    }

    public static String productId() {
        Mediafly_Config__mdt s = setting();
        return s != null ? s.Product_Id__c : null;
    }

    public static Integer apiVersion() {
        Mediafly_Config__mdt s = setting();
        if (s != null && s.Api_Version__c != null) {
            return Integer.valueOf(s.Api_Version__c);
        }
        return 3;
    }
}
