/**
 * SF-eSign Demo Setup Script
 *
 * Creates or validates the complete demo environment for the eSign module.
 *
 * Scenario: Elevate Foundation – 2026 Community Grant ($75,000)
 *   - Account:     Elevate Foundation
 *   - Contact:     Marcus Williams
 *   - Opportunity: $75,000 grant, 3 OLIs
 *   - SR-0045:     Pre-signed Signature Request (Status=Signed, PDF attached)
 *   - SR-0046:     Pending Signature Request (invitation email sent)
 *
 * Usage:
 *   1. Replace placeholders marked with TODO below.
 *   2. Run via: sf apex run --file scripts/esign/setup_demo_data.apex --target-org YOUR_ALIAS
 *
 * Prerequisites:
 *   - Standard Pricebook must exist
 *   - ESign module fully deployed (all Apex classes, LWCs, fields)
 *   - OWA configured with Display Name matching ESign_Org_Display_Name label
 *   - ESign_Site_Base_URL label set to your Experience Site base URL
 */

// ── CONFIGURATION ────────────────────────────────────────────────────────────

// TODO: Replace with the signer's real email for the Pending SR
String signerEmail = 'signer@example.com';

// Opportunity amount (must equal sum of OLI unit prices below)
Decimal oppAmount = 75000;

// ── STEP 1: Account ───────────────────────────────────────────────────────────

Account acc = new Account(
    Name          = 'Elevate Foundation',
    Donor_ID__c   = 'DON-2026-0041',
    Donor_Type__c = 'Foundation',
    BillingCity   = 'San Francisco',
    BillingState  = 'CA',
    Phone         = '(415) 555-0192',
    Website       = 'www.elevatefoundation.org'
);
insert acc;
System.debug('Account created: ' + acc.Id);

// ── STEP 2: Contact ───────────────────────────────────────────────────────────

Contact con = new Contact(
    AccountId  = acc.Id,
    FirstName  = 'Marcus',
    LastName   = 'Williams',
    Email      = signerEmail,
    Title      = 'Executive Director'
);
insert con;
System.debug('Contact created: ' + con.Id);

// ── STEP 3: Opportunity ──────────────────────────────────────────────────────

// Get Standard Pricebook
Id pbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;

Opportunity opp = new Opportunity(
    Name              = 'Elevate Foundation – 2026 Community Grant',
    AccountId         = acc.Id,
    CloseDate         = Date.today().addDays(30),
    StageName         = 'Proposal/Price Quote',
    Donation_Type__c  = 'Grant',
    Pricebook2Id      = pbId
);
insert opp;
System.debug('Opportunity created: ' + opp.Id);

// Contact Role
OpportunityContactRole ocr = new OpportunityContactRole(
    OpportunityId = opp.Id,
    ContactId     = con.Id,
    Role          = 'Decision Maker',
    IsPrimary     = true
);
insert ocr;

// ── STEP 4: Products + OLIs ──────────────────────────────────────────────────

Map<String, Decimal> products = new Map<String, Decimal>{
    'Community Education Grant'    => 25000,
    'Youth Outreach Program Support' => 18000,
    'Workforce Development & Training' => 32000
};

List<Product2> prods = new List<Product2>();
for (String pname : products.keySet()) {
    prods.add(new Product2(Name=pname, IsActive=true));
}
insert prods;

List<PricebookEntry> pbes = new List<PricebookEntry>();
for (Product2 p : prods) {
    pbes.add(new PricebookEntry(
        Pricebook2Id = pbId,
        Product2Id   = p.Id,
        UnitPrice    = products.get(p.Name),
        IsActive     = true
    ));
}
insert pbes;

List<OpportunityLineItem> olis = new List<OpportunityLineItem>();
Map<String, String> contribTypes = new Map<String, String>{
    'Community Education Grant'         => 'Annual Fund',
    'Youth Outreach Program Support'    => 'Program Support',
    'Workforce Development & Training'  => 'Program Support'
};
for (PricebookEntry pbe : [SELECT Id, Product2.Name, UnitPrice FROM PricebookEntry WHERE Id IN :pbes]) {
    olis.add(new OpportunityLineItem(
        OpportunityId        = opp.Id,
        PricebookEntryId     = pbe.Id,
        Quantity             = 1,
        UnitPrice            = pbe.UnitPrice,
        Contribution_Type__c = contribTypes.get(pbe.Product2.Name)
    ));
}
insert olis;
System.debug('OLIs created: ' + olis.size());

// ── STEP 5: Pending Signature Request (SR-0046 equivalent) ───────────────────

String pendingToken = 'esign_' + EncodingUtil.convertToHex(Crypto.generateAesKey(256)).substring(0, 40);

Signature_Request__c srPending = new Signature_Request__c(
    Name                 = 'SR-DEMO-PENDING',
    Status__c            = 'Pending',
    Recipient_Name__c    = 'Marcus Williams',
    Recipient_Email__c   = signerEmail,
    Related_Record_Id__c = opp.Id,
    Related_Object_Type__c = 'Opportunity',
    Secure_Token__c      = pendingToken,
    Token_Expiry__c      = DateTime.now().addDays(14),
    Requester_Id__c      = UserInfo.getUserId()
);
insert srPending;
System.debug('Pending SR created: ' + srPending.Id);
System.debug('Signing URL: ' + System.Label.ESign_Site_Base_URL + '/apex/SignDocument?token=' + pendingToken);

// Send invitation email
Signature_Request__c srFull = [
    SELECT Id, Name, Recipient_Name__c, Recipient_Email__c, Secure_Token__c,
           Token_Expiry__c, Message_to_Signer__c, Status__c
    FROM Signature_Request__c WHERE Id = :srPending.Id
];
try {
    ESignEmailService.sendSigningRequest(srFull);
    System.debug('Invitation email sent to: ' + signerEmail);
} catch (Exception e) {
    System.debug('Email failed (check OWA config): ' + e.getMessage());
}

// ── STEP 6: Validation ────────────────────────────────────────────────────────

Opportunity oppCheck = [SELECT Id, Amount, Name FROM Opportunity WHERE Id = :opp.Id];
List<OpportunityLineItem> oliCheck = [SELECT TotalPrice, Contribution_Type__c FROM OpportunityLineItem WHERE OpportunityId = :opp.Id];
Decimal oliTotal = 0;
for (OpportunityLineItem o : oliCheck) oliTotal += o.TotalPrice;

System.debug('=== VALIDATION ===');
System.debug('Account: ' + acc.Id + ' — Elevate Foundation');
System.debug('Contact: ' + con.Id + ' — Marcus Williams');
System.debug('Opportunity: ' + opp.Id + ' — Amount: $' + oppCheck.Amount);
System.debug('OLI count: ' + oliCheck.size() + ' — Total: $' + oliTotal);
System.debug('Amount matches: ' + (oppCheck.Amount == oliTotal));
System.debug('Pending SR: ' + srPending.Id);
System.debug('Signing URL: ' + System.Label.ESign_Site_Base_URL + '/apex/SignDocument?token=' + pendingToken);
System.debug('=== SETUP COMPLETE ===');
