// POH Demo Data Seeding Script
// Run once against POHDemo org to populate Omega, Inc. with realistic POH data

// ─── 0. Omega Inc Account ───────────────────────────────────────────────────
Account omega = [SELECT Id FROM Account WHERE Name = 'Omega, Inc.' LIMIT 1];
omega.put('Practice_Specialty__c', 'GP');
omega.put('Number_of_DDS__c', 2);
omega.put('Number_of_RDH__c', 3);
omega.put('Dispenses_Power__c', true);
omega.put('Dispenses_Manual__c', true);
omega.put('Recommends_Power__c', false);
omega.put('Recommends_Manual__c', true);
omega.put('Last_iO_Sample_Date__c', Date.newInstance(2022, 2, 23));
omega.put('Competitor_Brands_Seen__c', 'Sonicare');
omega.put('AI_Sales_Companion_Recommendation__c',
    'This GP practice has 2 DDS and 3 RDH and currently dispenses BOTH Oral-B Power and Manual brushes. ' +
    'They recommend Manual but not Power. iO was last sampled in February 2022 (over 3 years ago). ' +
    'RECOMMENDED ACTIONS: (1) Discuss white space promo for Oral-B iO — consider new hygienists who never received a sample. ' +
    '(2) Attempt a Teach & Learn to sell in Oral-B iO power recommendation. ' +
    '(3) Competitor Sonicare seen dispensing — address Oral-B clinical comparison. ' +
    '(4) If no power conversion in 2 visits, reduce visit frequency and focus on manual ship plan consistency.'
);
update omega;

// ─── 1. Product2 catalog ────────────────────────────────────────────────────
Set<String> existingProdNames = new Set<String>();
for(Product2 p : [SELECT Name FROM Product2 WHERE Name LIKE 'Oral-B%' OR Name LIKE 'Crest%']) {
    existingProdNames.add(p.Name);
}
List<Product2> products = new List<Product2>();
Map<String,String[]> prodDefs = new Map<String,String[]>{
    'Oral-B iO Series 9' => new String[]{'Power','Flagship power toothbrush with AI-powered brushing recognition'},
    'Oral-B Pro 1000' => new String[]{'Power','Entry-level power toothbrush, cross-action head'},
    'Oral-B Deep Clean Manual' => new String[]{'Manual','Deep clean bristle technology manual brush'},
    'Oral-B Gum Care Compact' => new String[]{'Manual','Compact head for sensitive gum tissue'},
    'Oral-B Sensitive 35' => new String[]{'Manual','Extra-soft 35-tuft manual brush for sensitivity'},
    'Crest Gum Detoxify' => new String[]{'Toothpaste','Neutralizes harmful plaque bacteria even around the gumline'},
    'Crest 3DWhite Brilliance' => new String[]{'Toothpaste','Whitening toothpaste with advanced whitening formula'},
    'Oral-B Glide Deep Clean Floss' => new String[]{'Floss','Silky smooth floss with a light coating of natural wax'}
};
for(String nm : prodDefs.keySet()) {
    if(!existingProdNames.contains(nm)) {
        products.add(new Product2(Name=nm, Family=prodDefs.get(nm)[0], IsActive=true, Description=prodDefs.get(nm)[1]));
    }
}
if(!products.isEmpty()) insert products;

Map<String, Id> prodMap = new Map<String, Id>();
for(Product2 p : [SELECT Id, Name FROM Product2 WHERE Name LIKE 'Oral-B%' OR Name LIKE 'Crest%']) {
    prodMap.put(p.Name, p.Id);
}

// ─── 2. Contacts ─────────────────────────────────────────────────────────────
// Delete existing POH contacts for idempotency
List<Contact> existingContacts = [SELECT Id FROM Contact WHERE AccountId = :omega.Id AND Email LIKE '%omegadental.example.com'];
if(!existingContacts.isEmpty()) delete existingContacts;

List<Contact> contacts = new List<Contact>{
    new Contact(FirstName='Megan', LastName='Harper', Title='RDH', AccountId=omega.Id, Email='megan.harper@omegadental.example.com'),
    new Contact(FirstName='Kristy', LastName='Simmons', Title='RDH', AccountId=omega.Id, Email='kristy.simmons@omegadental.example.com'),
    new Contact(FirstName='Julie', LastName='Chen', Title='RDH', AccountId=omega.Id, Email='julie.chen@omegadental.example.com'),
    new Contact(FirstName='Dr. Sarah', LastName='Omega', Title='DDS', AccountId=omega.Id, Email='dr.omega@omegadental.example.com'),
    new Contact(FirstName='Dr. Marcus', LastName='Reyes', Title='DDS', AccountId=omega.Id, Email='dr.reyes@omegadental.example.com')
};
insert contacts;

// ─── 3. Events (sales calls) ─────────────────────────────────────────────────
// Delete existing POH events for idempotency
List<Event> existingEvents = [SELECT Id FROM Event WHERE WhatId = :omega.Id AND Subject LIKE 'Sales Call%'];
if(!existingEvents.isEmpty()) delete existingEvents;

List<Event> events = new List<Event>();

// Visit 1 — ~12 months ago
Event e1 = new Event();
e1.Subject = 'Sales Call — Omega, Inc.';
e1.WhatId = omega.Id;
e1.WhoId = contacts[0].Id;
e1.StartDateTime = DateTime.newInstance(Date.today().addDays(-362), Time.newInstance(9,0,0,0));
e1.EndDateTime = DateTime.newInstance(Date.today().addDays(-362), Time.newInstance(9,30,0,0));
e1.put('Logged_via_Agentforce__c', false);
e1.put('Samples_Left_Summary__c', '6 tubes Crest Gum Detoxify');
e1.put('Visit_Notes__c', 'Introduced Crest Gum Detoxify. Megan receptive. Left 6 tubes. No competitive brands visible.');
events.add(e1);

// Visit 2 — ~9 months ago
Event e2 = new Event();
e2.Subject = 'Sales Call — Omega, Inc.';
e2.WhatId = omega.Id;
e2.WhoId = contacts[1].Id;
e2.StartDateTime = DateTime.newInstance(Date.today().addDays(-275), Time.newInstance(14,0,0,0));
e2.EndDateTime = DateTime.newInstance(Date.today().addDays(-275), Time.newInstance(14,20,0,0));
e2.put('Logged_via_Agentforce__c', false);
e2.put('Samples_Left_Summary__c', '12 tubes Crest 3DWhite Brilliance');
e2.put('Visit_Notes__c', 'Reviewed whitening with Kristy and Dr. Omega. Left 12 tubes 3DWhite Brilliance. Practice does whitening case presentations monthly. Sonicare display spotted near checkout.');
events.add(e2);

// Visit 3 — ~6 months ago
Event e3 = new Event();
e3.Subject = 'Sales Call — Omega, Inc.';
e3.WhatId = omega.Id;
e3.WhoId = contacts[2].Id;
e3.StartDateTime = DateTime.newInstance(Date.today().addDays(-178), Time.newInstance(10,30,0,0));
e3.EndDateTime = DateTime.newInstance(Date.today().addDays(-178), Time.newInstance(10,50,0,0));
e3.put('Logged_via_Agentforce__c', false);
e3.put('Samples_Left_Summary__c', '8 tubes Crest Gum Detoxify');
e3.put('Visit_Notes__c', 'Hygiene protocol with Julie and Dr. Reyes. Both interested in Gum Detoxify for perio patients. Left 8 tubes. Julie flagged old iO battery issues — good re-sample opportunity.');
events.add(e3);

// Visit 4 — last visit, ~3 months ago
Event e4 = new Event();
e4.Subject = 'Sales Call — Omega, Inc.';
e4.WhatId = omega.Id;
e4.WhoId = contacts[0].Id;
e4.StartDateTime = DateTime.newInstance(Date.today().addDays(-91), Time.newInstance(13,0,0,0));
e4.EndDateTime = DateTime.newInstance(Date.today().addDays(-91), Time.newInstance(13,30,0,0));
e4.put('Logged_via_Agentforce__c', false);
e4.put('Samples_Left_Summary__c', '12 tubes Crest Gum Detoxify, 1 Oral-B iO Series 9 white box sample');
e4.put('Visit_Notes__c', 'Met Megan, Kristy, Dr. Reyes. Whitespace promo discussed — Sonicare $99. Left 12 Gum Detoxify + 1 iO white box. Dr. Reyes to try iO. Now 4 hygienists. Follow-up: Teach & Learn for new hygienist Julie.');
events.add(e4);

insert events;

// ─── 4. Order Items — past 12 months (Manual Ship Plan) ──────────────────────
// Delete existing Order Items for idempotency
List<SObject> existingOI = Database.query('SELECT Id FROM Order_Item__c WHERE Account__c = \'' + omega.Id + '\'');
if(!existingOI.isEmpty()) delete existingOI;

List<SObject> orderItems = new List<SObject>();

// Inline helper — creates an Order_Item__c SObject dynamically
SObjectType oiType = Schema.getGlobalDescribe().get('Order_Item__c');

// Manual Ship Plan deliveries (quarterly cadence, past 12 months)
List<String[]> shipPlanProducts = new List<String[]>{
    new String[]{'Oral-B Deep Clean Manual','Manual','936','Manual Ship Plan'},
    new String[]{'Oral-B Gum Care Compact','Manual','936','Manual Ship Plan'},
    new String[]{'Oral-B Sensitive 35','Manual','936','Manual Ship Plan'},
    new String[]{'Crest Gum Detoxify','Toothpaste','480','Manual Ship Plan'},
    new String[]{'Crest 3DWhite Brilliance','Toothpaste','120','Manual Ship Plan'},
    new String[]{'Oral-B Glide Deep Clean Floss','Floss','480','Manual Ship Plan'}
};

for(Integer q = 3; q >= 0; q--) {
    Date d = Date.today().addDays(-(90 * q + 30));
    for(String[] sp : shipPlanProducts) {
        SObject r = oiType.newSObject();
        r.put('Account__c', omega.Id);
        if(prodMap.containsKey(sp[0])) r.put('Product__c', prodMap.get(sp[0]));
        r.put('Product_Name__c', sp[0]);
        r.put('Product_Family__c', sp[1]);
        r.put('Quantity__c', Integer.valueOf(sp[2]));
        r.put('Order_Date__c', d);
        r.put('Ship_Plan_Type__c', sp[3]);
        orderItems.add(r);
    }
}

// One-time order (iO units, 6 months ago)
SObject oiOneTime = oiType.newSObject();
oiOneTime.put('Account__c', omega.Id);
if(prodMap.containsKey('Oral-B iO Series 9')) oiOneTime.put('Product__c', prodMap.get('Oral-B iO Series 9'));
oiOneTime.put('Product_Name__c', 'Oral-B iO Series 9');
oiOneTime.put('Product_Family__c', 'Power');
oiOneTime.put('Quantity__c', 2);
oiOneTime.put('Order_Date__c', Date.today().addDays(-185));
oiOneTime.put('Ship_Plan_Type__c', 'One-Time');
orderItems.add(oiOneTime);

// Sample drops tied to last visit
SObject sample1 = oiType.newSObject();
sample1.put('Account__c', omega.Id);
if(prodMap.containsKey('Oral-B iO Series 9')) sample1.put('Product__c', prodMap.get('Oral-B iO Series 9'));
sample1.put('Product_Name__c', 'Oral-B iO Series 9');
sample1.put('Product_Family__c', 'Power');
sample1.put('Quantity__c', 1);
sample1.put('Order_Date__c', Date.today().addDays(-91));
sample1.put('Ship_Plan_Type__c', 'Sample Drop');
orderItems.add(sample1);

SObject sample2 = oiType.newSObject();
sample2.put('Account__c', omega.Id);
if(prodMap.containsKey('Crest Gum Detoxify')) sample2.put('Product__c', prodMap.get('Crest Gum Detoxify'));
sample2.put('Product_Name__c', 'Crest Gum Detoxify');
sample2.put('Product_Family__c', 'Toothpaste');
sample2.put('Quantity__c', 12);
sample2.put('Order_Date__c', Date.today().addDays(-91));
sample2.put('Ship_Plan_Type__c', 'Sample Drop');
orderItems.add(sample2);

// Future ship plan (next 12 months, quarterly)
for(Integer q = 1; q <= 4; q++) {
    Date d = Date.today().addDays(90 * q);
    for(String[] sp : shipPlanProducts) {
        SObject r = oiType.newSObject();
        r.put('Account__c', omega.Id);
        if(prodMap.containsKey(sp[0])) r.put('Product__c', prodMap.get(sp[0]));
        r.put('Product_Name__c', sp[0]);
        r.put('Product_Family__c', sp[1]);
        r.put('Quantity__c', Integer.valueOf(sp[2]));
        r.put('Order_Date__c', d);
        r.put('Ship_Plan_Type__c', sp[3]);
        orderItems.add(r);
    }
}

insert orderItems;

System.debug('=== POH Demo Seed Complete ===');
System.debug('Account updated: ' + omega.Id);
System.debug('Products created: ' + products.size());
System.debug('Contacts created: ' + contacts.size());
System.debug('Events created: ' + events.size());
System.debug('Order Items created: ' + orderItems.size());
