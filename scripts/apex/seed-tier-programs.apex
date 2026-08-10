// ============================================================
// seed-tier-programs.apex
// ------------------------------------------------------------
// Seeds one worked example of each of the three tier programs,
// so the ring can be demonstrated against realistic data:
//
//   Brokerage  Meridian Wealth Partners
//              Producer -> Premier Producer
//              AUM, Reg BI attestation, client retention
//
//   Dealer     Coastal Auto Group
//              Preferred Dealer -> Premier Dealer
//              look-to-book, chargeback rate, CSI
//
//   Partner    Northwind Treasury
//              Gold -> Platinum
//              seats, QBR, reference call
//
// Run with:
//   sf apex run --file scripts/apex/seed-tier-programs.apex \
//       --target-org <your-org-alias>
//
// IDEMPOTENCY:
//   Accounts and Tiers are matched by name and reused; child
//   items are deleted and reinserted. Safe to re-run.
//
// ============================================================

// ---- helpers ------------------------------------------------

// Tier_List_Item__c has no unique key, so children are replaced
// wholesale rather than upserted one by one.
Map<String, Id> accountByName = new Map<String, Id>();
Map<String, Id> tierByName    = new Map<String, Id>();

List<String> accountNames = new List<String>{
    'Meridian Wealth Partners', 'Coastal Auto Group', 'Northwind Treasury'
};
for (Account a : [SELECT Id, Name FROM Account WHERE Name IN :accountNames]) {
    accountByName.put(a.Name, a.Id);
}
List<Account> newAccounts = new List<Account>();
for (String name : accountNames) {
    if (!accountByName.containsKey(name)) {
        newAccounts.add(new Account(Name = name));
    }
}
if (!newAccounts.isEmpty()) {
    insert newAccounts;
    for (Account a : newAccounts) {
        accountByName.put(a.Name, a.Id);
    }
}
System.debug('Accounts ready: ' + accountByName.size());

// ---- Tiers --------------------------------------------------

Map<String, Tier__c> wanted = new Map<String, Tier__c>{
    'Meridian Wealth Partners - Premier Producer' => new Tier__c(
        Name            = 'Meridian Wealth Partners - Premier Producer',
        Account__c      = accountByName.get('Meridian Wealth Partners'),
        Program__c      = 'Brokerage',
        Current_Tier__c = 'Producer',
        Next_Tier__c    = 'Premier Producer',
        Status__c       = 'In Progress',
        Target_Date__c  = Date.today().addDays(120)
    ),
    'Coastal Auto Group - Premier Dealer' => new Tier__c(
        Name            = 'Coastal Auto Group - Premier Dealer',
        Account__c      = accountByName.get('Coastal Auto Group'),
        Program__c      = 'Dealer',
        Current_Tier__c = 'Preferred Dealer',
        Next_Tier__c    = 'Premier Dealer',
        Status__c       = 'At Risk',
        Target_Date__c  = Date.today().addDays(60)
    ),
    'Northwind Treasury - Platinum' => new Tier__c(
        Name            = 'Northwind Treasury - Platinum',
        Account__c      = accountByName.get('Northwind Treasury'),
        Program__c      = 'Partner',
        Current_Tier__c = 'Gold',
        Next_Tier__c    = 'Platinum',
        Status__c       = 'In Progress',
        Target_Date__c  = Date.today().addDays(90)
    )
};

for (Tier__c existing : [SELECT Id, Name FROM Tier__c WHERE Name IN :wanted.keySet()]) {
    wanted.get(existing.Name).Id = existing.Id;
}
upsert wanted.values();
for (Tier__c t : wanted.values()) {
    tierByName.put(t.Name, t.Id);
}
System.debug('Tiers ready: ' + tierByName.size());

// ---- Clear previous children --------------------------------

List<Tier_List_Item__c> stale = [
    SELECT Id FROM Tier_List_Item__c WHERE Tier__c IN :tierByName.values()
];
if (!stale.isEmpty()) {
    delete stale;
    System.debug('Removed ' + stale.size() + ' item(s) from a previous run');
}

// ---- Requirements -------------------------------------------

Id brokerage = tierByName.get('Meridian Wealth Partners - Premier Producer');
Id dealer    = tierByName.get('Coastal Auto Group - Premier Dealer');
Id partner   = tierByName.get('Northwind Treasury - Platinum');

List<Tier_List_Item__c> items = new List<Tier_List_Item__c>{

    // =========================================================
    // BROKERAGE - Producer -> Premier Producer
    // Production / Compliance / Relationship
    // =========================================================

    new Tier_List_Item__c(
        Name = 'Assets under management', Tier__c = brokerage,
        Category__c = 'Production', Sequence__c = 10, Weight__c = 3,
        Measure_Type__c = 'Numeric', Current_Value__c = 385, Target_Value__c = 500,
        Unit__c = '$M',
        How_To_Complete__c = 'Three institutional mandates in final diligence would close most of the gap.'
    ),
    new Tier_List_Item__c(
        Name = 'Net new assets this year', Tier__c = brokerage,
        Category__c = 'Production', Sequence__c = 20, Weight__c = 2,
        Measure_Type__c = 'Numeric', Current_Value__c = 62, Target_Value__c = 75,
        Unit__c = '$M',
        How_To_Complete__c = 'Rollover season typically adds $8-10M; the rest needs one mid-market win.'
    ),
    new Tier_List_Item__c(
        Name = 'Registered representatives on the platform', Tier__c = brokerage,
        Category__c = 'Production', Sequence__c = 30, Weight__c = 1,
        Measure_Type__c = 'Numeric', Current_Value__c = 18, Target_Value__c = 25,
        Unit__c = 'reps',
        How_To_Complete__c = 'Seven seats short. Two advisor teams are mid-transition from their prior BD.'
    ),

    new Tier_List_Item__c(
        Name = 'Form ADV annual amendment filed', Tier__c = brokerage,
        Category__c = 'Compliance', Sequence__c = 40, Weight__c = 2,
        Measure_Type__c = 'Checkbox', Completed__c = true
    ),
    new Tier_List_Item__c(
        Name = 'Regulation Best Interest attestations complete', Tier__c = brokerage,
        Category__c = 'Compliance', Sequence__c = 50, Weight__c = 2,
        Measure_Type__c = 'Numeric', Current_Value__c = 18, Target_Value__c = 25,
        Unit__c = 'reps',
        How_To_Complete__c = 'Seven reps still to attest. Compliance sends the second reminder on Friday.'
    ),
    new Tier_List_Item__c(
        Name = 'Firm element continuing education current', Tier__c = brokerage,
        Category__c = 'Compliance', Sequence__c = 60, Weight__c = 1,
        Measure_Type__c = 'Checkbox', Completed__c = false,
        How_To_Complete__c = 'Two principals are past due. Blocks the tier review regardless of production.'
    ),

    new Tier_List_Item__c(
        Name = 'Client retention rate', Tier__c = brokerage,
        Category__c = 'Relationship', Sequence__c = 70, Weight__c = 2,
        Measure_Type__c = 'Numeric', Current_Value__c = 94, Target_Value__c = 96,
        Unit__c = '%',
        How_To_Complete__c = 'Two points short. Attrition is concentrated in accounts under $250k.'
    ),
    new Tier_List_Item__c(
        Name = 'Annual business review held with relationship manager', Tier__c = brokerage,
        Category__c = 'Relationship', Sequence__c = 80, Weight__c = 1,
        Measure_Type__c = 'Checkbox', Completed__c = true
    ),
    new Tier_List_Item__c(
        Name = 'Dedicated service team engaged', Tier__c = brokerage,
        Category__c = 'Relationship', Sequence__c = 90, Weight__c = 1,
        Measure_Type__c = 'Checkbox', Completed__c = false,
        How_To_Complete__c = 'Requires Premier onboarding; schedule once AUM clears $450M.'
    ),

    // =========================================================
    // DEALER - Preferred Dealer -> Premier Dealer
    // Indirect auto lending and floor plan
    // =========================================================

    new Tier_List_Item__c(
        Name = 'Contracts funded, trailing twelve months', Tier__c = dealer,
        Category__c = 'Production', Sequence__c = 10, Weight__c = 3,
        Measure_Type__c = 'Numeric', Current_Value__c = 640, Target_Value__c = 900,
        Unit__c = 'contracts',
        How_To_Complete__c = 'Running roughly 53 a month against the 75 needed to hit the band.'
    ),
    new Tier_List_Item__c(
        Name = 'Look-to-book ratio', Tier__c = dealer,
        Category__c = 'Production', Sequence__c = 20, Weight__c = 2,
        Measure_Type__c = 'Numeric', Current_Value__c = 41, Target_Value__c = 55,
        Unit__c = '%',
        How_To_Complete__c = 'Approvals are not converting. Restructure near-prime deals before resubmitting.'
    ),
    new Tier_List_Item__c(
        Name = 'Floor plan utilisation', Tier__c = dealer,
        Category__c = 'Production', Sequence__c = 30, Weight__c = 1,
        Measure_Type__c = 'Numeric', Current_Value__c = 72, Target_Value__c = 80,
        Unit__c = '%',
        How_To_Complete__c = 'Wholesale line is underused; the spring buy should close this on its own.'
    ),

    new Tier_List_Item__c(
        Name = 'Contract accuracy rate', Tier__c = dealer,
        Category__c = 'Compliance', Sequence__c = 40, Weight__c = 2,
        Measure_Type__c = 'Numeric', Current_Value__c = 96, Target_Value__c = 98,
        Unit__c = '%',
        How_To_Complete__c = 'Most kickbacks are missing proof of insurance in the funding package.'
    ),
    new Tier_List_Item__c(
        Name = 'Chargeback rate within threshold', Tier__c = dealer,
        Category__c = 'Compliance', Sequence__c = 50, Weight__c = 2,
        Measure_Type__c = 'Checkbox', Completed__c = false,
        How_To_Complete__c = 'Running 3.1% against a 2.5% ceiling. Early payoffs on 84-month paper are the driver.'
    ),
    new Tier_List_Item__c(
        Name = 'Curtailment payments current', Tier__c = dealer,
        Category__c = 'Compliance', Sequence__c = 60, Weight__c = 1,
        Measure_Type__c = 'Checkbox', Completed__c = true
    ),

    new Tier_List_Item__c(
        Name = 'Customer Satisfaction Index', Tier__c = dealer,
        Category__c = 'Relationship', Sequence__c = 70, Weight__c = 2,
        Measure_Type__c = 'Numeric', Current_Value__c = 892, Target_Value__c = 920,
        Unit__c = 'points',
        How_To_Complete__c = 'Delivery experience scores are dragging the composite down.'
    ),
    new Tier_List_Item__c(
        Name = 'F&I product penetration', Tier__c = dealer,
        Category__c = 'Relationship', Sequence__c = 80, Weight__c = 1,
        Measure_Type__c = 'Numeric', Current_Value__c = 58, Target_Value__c = 70,
        Unit__c = '%',
        How_To_Complete__c = 'Service contract attach rate is the gap; GAP and tyre-and-wheel are on target.'
    ),
    new Tier_List_Item__c(
        Name = 'Quarterly dealer council attended', Tier__c = dealer,
        Category__c = 'Relationship', Sequence__c = 90, Weight__c = 1,
        Measure_Type__c = 'Checkbox', Completed__c = true
    ),

    // =========================================================
    // PARTNER - Gold -> Platinum
    // =========================================================

    new Tier_List_Item__c(
        Name = 'Seats activated', Tier__c = partner,
        Category__c = 'Adoption', Sequence__c = 10, Weight__c = 3,
        Measure_Type__c = 'Numeric', Current_Value__c = 340, Target_Value__c = 500,
        Unit__c = 'seats',
        How_To_Complete__c = 'Run the bulk provisioning job for the Treasury Ops org.'
    ),
    new Tier_List_Item__c(
        Name = 'Certified administrators on staff', Tier__c = partner,
        Category__c = 'Adoption', Sequence__c = 20, Weight__c = 2,
        Measure_Type__c = 'Numeric', Current_Value__c = 4, Target_Value__c = 6,
        Unit__c = 'certifications',
        How_To_Complete__c = 'Two exams booked for next month.'
    ),
    new Tier_List_Item__c(
        Name = 'Production deployment signed off', Tier__c = partner,
        Category__c = 'Adoption', Sequence__c = 30, Weight__c = 2,
        Measure_Type__c = 'Checkbox', Completed__c = true
    ),

    new Tier_List_Item__c(
        Name = 'Quarterly business review held', Tier__c = partner,
        Category__c = 'Engagement', Sequence__c = 40, Weight__c = 2,
        Measure_Type__c = 'Checkbox', Completed__c = true
    ),
    new Tier_List_Item__c(
        Name = 'Executive sponsor named', Tier__c = partner,
        Category__c = 'Engagement', Sequence__c = 50, Weight__c = 2,
        Measure_Type__c = 'Checkbox', Completed__c = false,
        How_To_Complete__c = 'Confirm the COO as sponsor at the next steering committee.'
    ),
    new Tier_List_Item__c(
        Name = 'Support tickets answered within SLA', Tier__c = partner,
        Category__c = 'Engagement', Sequence__c = 60, Weight__c = 1,
        Measure_Type__c = 'Numeric', Current_Value__c = 92, Target_Value__c = 95,
        Unit__c = '%',
        How_To_Complete__c = 'Three points of headroom left. Tighten first-touch routing.'
    ),

    new Tier_List_Item__c(
        Name = 'Reference call completed', Tier__c = partner,
        Category__c = 'Advocacy', Sequence__c = 70, Weight__c = 2,
        Measure_Type__c = 'Checkbox', Completed__c = false,
        How_To_Complete__c = 'Legal sign-off is the blocker. Chase the MSA amendment.'
    ),
    new Tier_List_Item__c(
        Name = 'Case study published', Tier__c = partner,
        Category__c = 'Advocacy', Sequence__c = 80, Weight__c = 1,
        Measure_Type__c = 'Checkbox', Completed__c = false,
        How_To_Complete__c = 'Draft is with comms; needs approved metrics from finance.'
    ),
    new Tier_List_Item__c(
        Name = 'Community answers contributed', Tier__c = partner,
        Category__c = 'Advocacy', Sequence__c = 90, Weight__c = 1,
        Measure_Type__c = 'Numeric', Current_Value__c = 6, Target_Value__c = 10,
        Unit__c = 'answers',
        How_To_Complete__c = 'Four more from the Treasury Ops admins.'
    )
};

insert items;
System.debug('Inserted ' + items.size() + ' tier list item(s)');

// ---- Report what each ring will show ------------------------
// Roll-ups recalculate asynchronously, so compute the same figures
// the LWC computes rather than reading Progress_Percent__c back.

Map<Id, Decimal> weightByTier = new Map<Id, Decimal>();
Map<Id, Decimal> earnedByTier = new Map<Id, Decimal>();
Map<Id, Integer> openByTier   = new Map<Id, Integer>();

for (Tier_List_Item__c i : [
    SELECT Tier__c, Weight__c, Progress_Percent__c, Is_Complete__c
    FROM Tier_List_Item__c WHERE Tier__c IN :tierByName.values()
]) {
    Decimal w = i.Weight__c == null ? 1 : i.Weight__c;
    weightByTier.put(i.Tier__c, (weightByTier.containsKey(i.Tier__c) ? weightByTier.get(i.Tier__c) : 0) + w);
    earnedByTier.put(i.Tier__c, (earnedByTier.containsKey(i.Tier__c) ? earnedByTier.get(i.Tier__c) : 0)
                                 + (w * i.Progress_Percent__c / 100));
    if (!i.Is_Complete__c) {
        openByTier.put(i.Tier__c, (openByTier.containsKey(i.Tier__c) ? openByTier.get(i.Tier__c) : 0) + 1);
    }
}

System.debug('--------------------------------------------------');
for (Tier__c t : [
    SELECT Id, Name, Program__c, Current_Tier__c, Next_Tier__c
    FROM Tier__c WHERE Id IN :tierByName.values() ORDER BY Program__c
]) {
    Decimal w = weightByTier.containsKey(t.Id) ? weightByTier.get(t.Id) : 0;
    Decimal e = earnedByTier.containsKey(t.Id) ? earnedByTier.get(t.Id) : 0;
    Integer o = openByTier.containsKey(t.Id) ? openByTier.get(t.Id) : 0;
    System.debug(
        t.Program__c + ': ' + t.Current_Tier__c + ' -> ' + t.Next_Tier__c +
        '  ring ' + (w > 0 ? (e / w * 100).setScale(1) : 0) + '%' +
        '  outstanding ' + o);
}
System.debug('Open each Account record page to see its ring.');
System.debug('--------------------------------------------------');
