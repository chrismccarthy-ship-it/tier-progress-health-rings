// ============================================================
// seed-techco-onboarding.apex
// ------------------------------------------------------------
// Seeds the Commercial Banking onboarding climb for Techco.
//
//   Techco   Onboarding -> Treasury Live
//            Compliance     KYC packet, credit review, master agreements
//            Implementation platform provisioning, project team
//            Integration    SFTP profile, SSH keys, delivery window
//
// Kept separate from seed-tier-programs.apex on purpose: this one
// targets a specific Account by record id, so it only makes sense
// in the org that record lives in. The other script matches on
// name and creates what it needs, so it runs anywhere.
//
// Run with:
//   sf apex run --file scripts/apex/seed-techco-onboarding.apex \
//       --target-org <your-org-alias>
//
// IDEMPOTENCY:
//   The Tier is matched by name and reused; child items are
//   deleted and reinserted. Safe to re-run.
//
// ============================================================

final Id ACCOUNT_ID = '001Kh00001yqwmEIAQ';
final String TIER_NAME = 'Techco - Treasury Live';

// ---- Account ------------------------------------------------
// Looked up rather than created. If the id is wrong we stop here
// rather than quietly seeding a tier against nothing.

List<Account> accounts = [SELECT Id, Name FROM Account WHERE Id = :ACCOUNT_ID];
if (accounts.isEmpty()) {
    System.debug(LoggingLevel.ERROR,
        'No Account found with id ' + ACCOUNT_ID + '. Nothing was created. ' +
        'Check the id is right for this org and re-run.');
    return;
}
System.debug('Account: ' + accounts[0].Name + ' (' + accounts[0].Id + ')');

// ---- Tier ---------------------------------------------------

List<Tier__c> existingTiers = [SELECT Id FROM Tier__c WHERE Name = :TIER_NAME LIMIT 1];
Tier__c tier = existingTiers.isEmpty() ? new Tier__c() : existingTiers[0];
tier.Name            = TIER_NAME;
tier.Account__c      = ACCOUNT_ID;
tier.Program__c      = 'Commercial Banking';
tier.Current_Tier__c = 'Onboarding';
tier.Next_Tier__c    = 'Treasury Live';
tier.Status__c       = 'In Progress';
tier.Target_Date__c  = Date.today().addDays(45);
upsert tier;
System.debug('Tier ready: ' + tier.Id);

// ---- Clear previous children --------------------------------

List<Tier_List_Item__c> stale = [SELECT Id FROM Tier_List_Item__c WHERE Tier__c = :tier.Id];
if (!stale.isEmpty()) {
    delete stale;
    System.debug('Removed ' + stale.size() + ' item(s) from a previous run');
}

// ---- Requirements -------------------------------------------
// Sequence numbers follow the real order of the journey: the five
// commercial bank onboarding gates first, then the three treasury
// management prerequisites that only matter once the account exists.

List<Tier_List_Item__c> items = new List<Tier_List_Item__c>{

    // ---------------------------------------------------------
    // COMMERCIAL BANK ONBOARDING - approvals and paper
    // ---------------------------------------------------------

    new Tier_List_Item__c(
        Name = 'Submit core KYC packet',
        Tier__c = tier.Id, Category__c = 'Compliance',
        Sequence__c = 10, Weight__c = 2,
        Measure_Type__c = 'Checkbox', Completed__c = true,
        How_To_Complete__c = 'LLC details and signer IDs with the relationship manager for Know Your Customer screening.'
    ),
    new Tier_List_Item__c(
        Name = 'Undergo credit review',
        Tier__c = tier.Id, Category__c = 'Compliance',
        Sequence__c = 20, Weight__c = 3,
        Measure_Type__c = 'Checkbox', Completed__c = true,
        How_To_Complete__c = 'Bank assesses credit risk against the proposed ACH and remote deposit capture velocity limits.'
    ),
    new Tier_List_Item__c(
        Name = 'Execute master agreements',
        Tier__c = tier.Id, Category__c = 'Compliance',
        Sequence__c = 30, Weight__c = 3,
        Measure_Type__c = 'Checkbox', Completed__c = false,
        How_To_Complete__c = 'Authorised signers still to execute the master commercial banking agreement and the treasury addendums.'
    ),

    // ---------------------------------------------------------
    // COMMERCIAL BANK ONBOARDING - standing the platform up
    // ---------------------------------------------------------

    new Tier_List_Item__c(
        Name = 'Provision and test the platform',
        Tier__c = tier.Id, Category__c = 'Implementation',
        Sequence__c = 40, Weight__c = 2,
        Measure_Type__c = 'Numeric', Current_Value__c = 2, Target_Value__c = 5,
        Unit__c = 'test files',
        How_To_Complete__c = 'Administrators have credentials and hardware tokens; three test transaction files still to pass.'
    ),
    new Tier_List_Item__c(
        Name = 'Align project resources',
        Tier__c = tier.Id, Category__c = 'Implementation',
        Sequence__c = 50, Weight__c = 1,
        Measure_Type__c = 'Checkbox', Completed__c = true,
        How_To_Complete__c = 'Customer implementation team named and third parties identified.'
    ),

    // ---------------------------------------------------------
    // TREASURY MANAGEMENT - file transmission prerequisites
    // ---------------------------------------------------------

    new Tier_List_Item__c(
        Name = 'Direct File Transmission profile provisioned',
        Tier__c = tier.Id, Category__c = 'Integration',
        Sequence__c = 60, Weight__c = 2,
        Measure_Type__c = 'Checkbox', Completed__c = false,
        How_To_Complete__c = 'Relationship manager must provision this separately from the standard web UI profile.'
    ),
    new Tier_List_Item__c(
        Name = 'SFTP key exchange complete',
        Tier__c = tier.Id, Category__c = 'Integration',
        Sequence__c = 70, Weight__c = 2,
        Measure_Type__c = 'Checkbox', Completed__c = false,
        How_To_Complete__c = 'Generate the SSH key pair in the ERP and send the public key to the bank SFTP administrator.'
    ),
    new Tier_List_Item__c(
        Name = 'File delivery window agreed',
        Tier__c = tier.Id, Category__c = 'Integration',
        Sequence__c = 80, Weight__c = 1,
        Measure_Type__c = 'Checkbox', Completed__c = false,
        How_To_Complete__c = 'Set the end-of-day and intra-day drop times so files land before the ERP batch sync runs.'
    )
};

insert items;
System.debug('Inserted ' + items.size() + ' tier list item(s)');

// ---- Report what the ring will show -------------------------
// Roll-ups recalculate asynchronously, so compute the same figures
// the LWC computes rather than reading Progress_Percent__c back.

Decimal totalWeight = 0;
Decimal earned      = 0;
Integer outstanding = 0;
Map<String, Decimal> weightByCategory = new Map<String, Decimal>();
Map<String, Decimal> earnedByCategory = new Map<String, Decimal>();

for (Tier_List_Item__c i : [
    SELECT Category__c, Weight__c, Progress_Percent__c, Is_Complete__c
    FROM Tier_List_Item__c WHERE Tier__c = :tier.Id
]) {
    Decimal w = i.Weight__c == null ? 1 : i.Weight__c;
    Decimal e = w * i.Progress_Percent__c / 100;
    totalWeight += w;
    earned      += e;
    if (!i.Is_Complete__c) {
        outstanding++;
    }
    String c = String.isBlank(i.Category__c) ? 'General' : i.Category__c;
    weightByCategory.put(c, (weightByCategory.containsKey(c) ? weightByCategory.get(c) : 0) + w);
    earnedByCategory.put(c, (earnedByCategory.containsKey(c) ? earnedByCategory.get(c) : 0) + e);
}

System.debug('--------------------------------------------------');
System.debug('Techco: Onboarding -> Treasury Live');
System.debug('Ring: ' + (totalWeight > 0 ? (earned / totalWeight * 100).setScale(1) : 0) + '%');
for (String c : new List<String>{ 'Compliance', 'Implementation', 'Integration' }) {
    if (weightByCategory.containsKey(c)) {
        System.debug('  ' + c + ': ' +
            (earnedByCategory.get(c) / weightByCategory.get(c) * 100).setScale(1) + '%');
    }
}
System.debug('Outstanding: ' + outstanding + ' of ' + items.size());
System.debug('Open the Techco Account record page to see the ring.');
System.debug('--------------------------------------------------');
