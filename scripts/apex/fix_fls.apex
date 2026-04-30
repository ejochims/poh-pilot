// Grant FLS for all POH custom fields to the running user's profile
// by finding the System Administrator profile and enabling Read/Edit on each field
String profileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;

List<FieldPermissions> fps = new List<FieldPermissions>();
List<String> fieldApiNames = new List<String>{
    'Account.Practice_Specialty__c',
    'Account.Number_of_DDS__c',
    'Account.Number_of_RDH__c',
    'Account.Dispenses_Power__c',
    'Account.Dispenses_Manual__c',
    'Account.Recommends_Power__c',
    'Account.Recommends_Manual__c',
    'Account.Competitor_Brands_Seen__c',
    'Account.Last_iO_Sample_Date__c',
    'Account.AI_Sales_Companion_Recommendation__c'
};

// Get the permission set for the profile (or create inline via profile)
// Actually for admin profile, use SetupEntityAccess / PermissionSet approach
// Simpler: query existing field perms and upsert
for(String fn : fieldApiNames) {
    List<FieldPermissions> existing = [SELECT Id, PermissionsEdit, PermissionsRead 
                                       FROM FieldPermissions 
                                       WHERE SobjectType = 'Account' 
                                       AND Field = :fn 
                                       AND ParentId IN (SELECT Id FROM PermissionSet WHERE IsOwnedByProfile = true AND Profile.Name = 'System Administrator')
                                       LIMIT 1];
    if(!existing.isEmpty()) {
        existing[0].PermissionsRead = true;
        existing[0].PermissionsEdit = true;
        fps.add(existing[0]);
    }
}

if(!fps.isEmpty()) {
    update fps;
    System.debug('Updated ' + fps.size() + ' field permissions');
} else {
    System.debug('No field permissions found to update - fields may already be accessible');
}

// Test the field access by querying
try {
    Account a = [SELECT Id, Practice_Specialty__c FROM Account WHERE Name = 'Omega, Inc.' LIMIT 1];
    System.debug('SUCCESS: Practice_Specialty__c accessible: ' + a.get('Practice_Specialty__c'));
} catch(Exception e) {
    System.debug('STILL FAILING: ' + e.getMessage());
}
