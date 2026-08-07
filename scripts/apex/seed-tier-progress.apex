// ============================================================
// seed-tier-progress.apex
// ------------------------------------------------------------
// Seeds one Account with a Tier__c progression and a spread of
// Tier_List_Item__c requirements, so the tierProgressRing LWC
// has three partly-filled concentric arcs to render in a fresh
// scratch org or sandbox.
//
// Run with:
//   sf apex run --file scripts/apex/seed-tier-progress.apex \
//       --target-org <your-org-alias>
//
// PREREQUISITES:
//   1. Tier__c and Tier_List_Item__c deployed
//   2. Tier_Progress_User permission set assigned, or run as an
//      admin with modify-all
//
// IDEMPOTENCY:
//   Looks up the Account and Tier by name and reuses them, and
//   deletes any existing child items before reinserting, so
//   re-running gives the same result rather than duplicates.
//
// ============================================================

final String ACCOUNT_NAME = 'Northwind Treasury';
final String TIER_NAME    = 'Northwind Treasury - Gold';

// ---- Account ----
List<Account> accounts = [SELECT Id FROM Account WHERE Name = :ACCOUNT_NAME LIMIT 1];
Account acct;
if (accounts.isEmpty()) {
    acct = new Account(Name = ACCOUNT_NAME);
    insert acct;
    System.debug('Created Account ' + ACCOUNT_NAME);
} else {
    acct = accounts[0];
    System.debug('Reusing Account ' + ACCOUNT_NAME);
}

// ---- Tier ----
List<Tier__c> tiers = [SELECT Id FROM Tier__c WHERE Name = :TIER_NAME LIMIT 1];
Tier__c tier;
if (tiers.isEmpty()) {
    tier = new Tier__c(Name = TIER_NAME);
} else {
    tier = tiers[0];
}
tier.Account__c      = acct.Id;
tier.Current_Tier__c = 'Silver';
tier.Next_Tier__c    = 'Gold';
tier.Status__c       = 'In Progress';
tier.Target_Date__c  = Date.today().addDays(75);
upsert tier;
System.debug('Tier ready: ' + tier.Id);

// ---- Clear any previous run's items ----
List<Tier_List_Item__c> existing = [
    SELECT Id FROM Tier_List_Item__c WHERE Tier__c = :tier.Id
];
if (!existing.isEmpty()) {
    delete existing;
    System.debug('Removed ' + existing.size() + ' item(s) from a previous run');
}

// ---- Requirements ----
// Three categories become three concentric arcs, outermost first:
// Adoption, Engagement, Advocacy. Weights are relative to each other.
List<Tier_List_Item__c> items = new List<Tier_List_Item__c>{

    // --- Adoption ---
    new Tier_List_Item__c(
        Name = 'Seats activated',
        Tier__c = tier.Id, Category__c = 'Adoption', Sequence__c = 10,
        Measure_Type__c = 'Numeric', Current_Value__c = 340, Target_Value__c = 500,
        Unit__c = 'seats', Weight__c = 3,
        How_To_Complete__c = 'Run the bulk provisioning job for the Treasury Ops org.'
    ),
    new Tier_List_Item__c(
        Name = 'Email-to-Case AI resolver live in production',
        Tier__c = tier.Id, Category__c = 'Adoption', Sequence__c = 20,
        Measure_Type__c = 'Checkbox', Completed__c = true, Weight__c = 2
    ),
    new Tier_List_Item__c(
        Name = 'Cases auto-resolved this quarter',
        Tier__c = tier.Id, Category__c = 'Adoption', Sequence__c = 30,
        Measure_Type__c = 'Numeric', Current_Value__c = 1120, Target_Value__c = 2000,
        Unit__c = 'cases', Weight__c = 2,
        How_To_Complete__c = 'Lower the Stage 2 confidence threshold once accuracy holds above 95%.'
    ),

    // --- Engagement ---
    new Tier_List_Item__c(
        Name = 'Quarterly business review held',
        Tier__c = tier.Id, Category__c = 'Engagement', Sequence__c = 40,
        Measure_Type__c = 'Checkbox', Completed__c = true, Weight__c = 2
    ),
    new Tier_List_Item__c(
        Name = 'Executive sponsor named',
        Tier__c = tier.Id, Category__c = 'Engagement', Sequence__c = 50,
        Measure_Type__c = 'Checkbox', Completed__c = false, Weight__c = 2,
        How_To_Complete__c = 'Confirm the COO as sponsor at the next steering committee.'
    ),
    new Tier_List_Item__c(
        Name = 'Support tickets responded to within SLA',
        Tier__c = tier.Id, Category__c = 'Engagement', Sequence__c = 60,
        Measure_Type__c = 'Numeric', Current_Value__c = 92, Target_Value__c = 95,
        Unit__c = '%', Weight__c = 1,
        How_To_Complete__c = 'Three points of SLA headroom left - tighten first-touch routing.'
    ),

    // --- Advocacy ---
    new Tier_List_Item__c(
        Name = 'Reference call completed',
        Tier__c = tier.Id, Category__c = 'Advocacy', Sequence__c = 70,
        Measure_Type__c = 'Checkbox', Completed__c = false, Weight__c = 2,
        How_To_Complete__c = 'Legal sign-off is the blocker - chase the MSA amendment.'
    ),
    new Tier_List_Item__c(
        Name = 'Case study published',
        Tier__c = tier.Id, Category__c = 'Advocacy', Sequence__c = 80,
        Measure_Type__c = 'Checkbox', Completed__c = false, Weight__c = 1,
        How_To_Complete__c = 'Draft is with comms; needs approved metrics from the CFO one-pager.'
    ),
    new Tier_List_Item__c(
        Name = 'Community answers contributed',
        Tier__c = tier.Id, Category__c = 'Advocacy', Sequence__c = 90,
        Measure_Type__c = 'Numeric', Current_Value__c = 6, Target_Value__c = 10,
        Unit__c = 'answers', Weight__c = 1,
        How_To_Complete__c = 'Four more answers from the Treasury Ops admins.'
    )
};

insert items;
System.debug('Inserted ' + items.size() + ' tier list item(s)');

// ---- Report what the ring will show ----
// Roll-ups recalculate asynchronously, so compute the same figures the
// LWC computes rather than reading Progress_Percent__c straight back.
Decimal totalWeight = 0;
Decimal earned      = 0;
Integer outstanding = 0;
for (Tier_List_Item__c i : [
    SELECT Weight__c, Progress_Percent__c, Is_Complete__c
    FROM Tier_List_Item__c WHERE Tier__c = :tier.Id
]) {
    Decimal w = i.Weight__c == null ? 1 : i.Weight__c;
    totalWeight += w;
    earned      += w * i.Progress_Percent__c / 100;
    if (!i.Is_Complete__c) {
        outstanding++;
    }
}

System.debug('----------------------------------------');
System.debug('Tier      : ' + TIER_NAME);
System.debug('Account   : ' + ACCOUNT_NAME + ' (' + acct.Id + ')');
System.debug('Ring shows: ' +
    (totalWeight > 0 ? (earned / totalWeight * 100).setScale(1) : 0) + '%');
System.debug('Outstanding: ' + outstanding + ' of ' + items.size() + ' requirements');
System.debug('Open the Account or Tier record page to see the ring.');
System.debug('----------------------------------------');
