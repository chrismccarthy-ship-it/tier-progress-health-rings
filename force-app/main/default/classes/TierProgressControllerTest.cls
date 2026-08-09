/**
 * TierProgressControllerTest
 * --------------------------------------------------------------------
 * Covers the weighted maths, the category-to-ring grouping, the
 * outstanding list copy, and every record-resolution branch.
 *
 * The most load-bearing assertion here is testApexMirrorsFormulaField:
 * TierProgressController.itemPercent() deliberately duplicates the
 * Progress_Percent__c formula so the ring never waits on a roll-up.
 * If someone edits one and not the other, that test fails.
 */
@isTest
private class TierProgressControllerTest {

    // ------------------------------------------------------------------
    // Fixtures
    // ------------------------------------------------------------------

    private static Account newAccount() {
        Account a = new Account(Name = 'Tiering Test Co');
        insert a;
        return a;
    }

    private static Tier__c newTier(Id accountId, String status) {
        Tier__c t = new Tier__c(
            Name          = 'Tiering Test Co to Gold',
            Account__c    = accountId,
            Current_Tier__c = 'Silver',
            Next_Tier__c  = 'Gold',
            Status__c     = status,
            Target_Date__c = Date.today().addDays(90)
        );
        insert t;
        return t;
    }

    private static Tier_List_Item__c checkboxItem(
        Id tierId, String name, String category, Decimal weight, Boolean done
    ) {
        return new Tier_List_Item__c(
            Name           = name,
            Tier__c        = tierId,
            Category__c    = category,
            Measure_Type__c = 'Checkbox',
            Completed__c   = done,
            Weight__c      = weight
        );
    }

    private static Tier_List_Item__c numericItem(
        Id tierId, String name, String category, Decimal weight,
        Decimal current, Decimal target, String unit
    ) {
        return new Tier_List_Item__c(
            Name           = name,
            Tier__c        = tierId,
            Category__c    = category,
            Measure_Type__c = 'Numeric',
            Current_Value__c = current,
            Target_Value__c  = target,
            Unit__c        = unit,
            Weight__c      = weight
        );
    }

    // ------------------------------------------------------------------
    // Percentage maths
    // ------------------------------------------------------------------

    @isTest
    static void testWeightedPercentageAcrossMixedItems() {
        Account a = newAccount();
        Tier__c t = newTier(a.Id, 'In Progress');

        insert new List<Tier_List_Item__c>{
            // weight 3, fully done         → earns 3
            checkboxItem(t.Id, 'Sign the renewal', 'Adoption', 3, true),
            // weight 1, not done           → earns 0
            checkboxItem(t.Id, 'Name an exec sponsor', 'Adoption', 1, false),
            // weight 2, 25 of 100          → earns 0.5
            numericItem(t.Id, 'Licences activated', 'Adoption', 2, 25, 100, 'licences')
        };
        // 3.5 earned out of 6 weight = 58.333… → 58.3
        Test.startTest();
        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(t.Id);
        Test.stopTest();

        System.assertNotEquals(null, p, 'Expected progress for a Tier id');
        System.assertEquals(58.3, p.percentComplete, 'Weighted percentage is wrong');
        System.assertEquals(3, p.itemsTotal, 'Wrong item total');
        System.assertEquals(1, p.itemsComplete, 'Only the renewal is complete');
        System.assertEquals(2, p.itemsOutstanding, 'Two items are outstanding');
        System.assertEquals(2, p.outstanding.size(), 'Outstanding list size mismatch');
    }

    @isTest
    static void testEverythingCompleteReadsAsOneHundred() {
        Account a = newAccount();
        Tier__c t = newTier(a.Id, 'In Progress');

        insert new List<Tier_List_Item__c>{
            checkboxItem(t.Id, 'Sign the renewal', 'Adoption', 2, true),
            // Over-delivering caps at 100 rather than pushing the ring past full.
            numericItem(t.Id, 'Licences activated', 'Adoption', 1, 250, 100, 'licences')
        };

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(t.Id);

        System.assertEquals(100.0, p.percentComplete, 'Over-delivery should cap at 100');
        System.assertEquals(0, p.itemsOutstanding, 'Nothing should be outstanding');
        System.assert(p.outstanding.isEmpty(), 'Outstanding list should be empty');
    }

    @isTest
    static void testTierWithNoItemsIsZeroNotAnError() {
        Account a = newAccount();
        Tier__c t = newTier(a.Id, 'In Progress');

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(t.Id);

        System.assertEquals(0.0, p.percentComplete, 'An empty tier is 0%, not a divide-by-zero');
        System.assertEquals(0, p.itemsTotal, 'No items expected');
        System.assertEquals(1, p.rings.size(), 'Should still render a single empty ring');
        System.assertEquals('overall', p.rings[0].key, 'Empty tier renders the overall ring');
    }

    @isTest
    static void testNumericItemWithNoTargetEarnsNothing() {
        Account a = newAccount();
        Tier__c t = newTier(a.Id, 'In Progress');

        insert numericItem(t.Id, 'Unbounded metric', 'Adoption', 1, 40, null, 'cases');

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(t.Id);

        System.assertEquals(0.0, p.percentComplete, 'No target means no credit');
        System.assertEquals(1, p.outstanding.size(), 'Item is outstanding');
        System.assertEquals('No target set', p.outstanding[0].remaining,
            'Should say the target is missing rather than showing a bogus fraction');
    }

    /**
     * The controller mirrors the Progress_Percent__c formula in Apex so the
     * ring is accurate before roll-ups recalculate. This pins the two together.
     */
    @isTest
    static void testApexMirrorsFormulaField() {
        Account a = newAccount();
        Tier__c t = newTier(a.Id, 'In Progress');

        insert new List<Tier_List_Item__c>{
            checkboxItem(t.Id, 'Unticked checkbox', 'Adoption', 1, false),
            numericItem(t.Id, 'Third of the way', 'Adoption', 1, 1, 3, 'things'),
            numericItem(t.Id, 'Two thirds', 'Adoption', 1, 2, 3, 'things'),
            numericItem(t.Id, 'Zero so far', 'Adoption', 1, 0, 10, 'things')
        };

        Map<Id, Decimal> formulaByItem = new Map<Id, Decimal>();
        for (Tier_List_Item__c row : [
            SELECT Id, Progress_Percent__c FROM Tier_List_Item__c WHERE Tier__c = :t.Id
        ]) {
            formulaByItem.put(row.Id, row.Progress_Percent__c.setScale(1, System.RoundingMode.HALF_UP));
        }

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(t.Id);

        System.assertEquals(4, p.outstanding.size(), 'All four items are incomplete');
        for (TierProgressController.OutstandingItem item : p.outstanding) {
            System.assertEquals(
                formulaByItem.get(item.id), item.percent,
                'Apex and the Progress_Percent__c formula disagree for ' + item.label);
        }
    }

    // ------------------------------------------------------------------
    // Rings
    // ------------------------------------------------------------------

    @isTest
    static void testOneCategoryCollapsesToASingleOverallRing() {
        Account a = newAccount();
        Tier__c t = newTier(a.Id, 'In Progress');

        insert new List<Tier_List_Item__c>{
            checkboxItem(t.Id, 'First', 'Adoption', 1, true),
            checkboxItem(t.Id, 'Second', 'Adoption', 1, false)
        };

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(t.Id);

        System.assertEquals(1, p.rings.size(), 'A lone category should not get its own arc');
        System.assertEquals('overall', p.rings[0].key, 'Expected the overall ring');
        System.assertEquals('Overall', p.rings[0].label, 'Expected the overall label');
        System.assertEquals(50.0, p.rings[0].percent, 'Overall ring percentage is wrong');
        System.assertEquals(2, p.rings[0].itemsTotal, 'Ring should count both items');
        System.assertEquals(1, p.rings[0].itemsComplete, 'One item is complete');
    }

    @isTest
    static void testCategoriesBecomeConcentricRingsInOrder() {
        Account a = newAccount();
        Tier__c t = newTier(a.Id, 'In Progress');

        insert new List<Tier_List_Item__c>{
            // Inserted out of order on purpose — ring order is canonical,
            // not insertion order.
            checkboxItem(t.Id, 'Reference call', 'Advocacy', 1, false),
            checkboxItem(t.Id, 'QBR attended', 'Engagement', 1, true),
            checkboxItem(t.Id, 'Licences live', 'Adoption', 1, true),
            checkboxItem(t.Id, 'Community post', 'Advocacy', 1, true)
        };

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(t.Id);

        System.assertEquals(3, p.rings.size(), 'One ring per category expected');
        System.assertEquals('Adoption', p.rings[0].key, 'Adoption is the outermost ring');
        System.assertEquals('Engagement', p.rings[1].key, 'Engagement is the middle ring');
        System.assertEquals('Advocacy', p.rings[2].key, 'Advocacy is the innermost ring');

        System.assertEquals(100.0, p.rings[0].percent, 'Adoption is fully done');
        System.assertEquals(100.0, p.rings[1].percent, 'Engagement is fully done');
        System.assertEquals(50.0, p.rings[2].percent, 'Advocacy is half done');
        System.assertEquals(2, p.rings[2].itemsTotal, 'Advocacy holds two items');
        System.assertEquals(1, p.rings[2].itemsComplete, 'One Advocacy item is done');

        System.assertEquals(75.0, p.percentComplete, 'Overall is 3 of 4 equal-weight items');
    }

    // ------------------------------------------------------------------
    // Outstanding copy
    // ------------------------------------------------------------------

    @isTest
    static void testOutstandingCopyStatesWhatIsLeft() {
        Account a = newAccount();
        Tier__c t = newTier(a.Id, 'In Progress');

        Tier_List_Item__c numeric = numericItem(
            t.Id, 'Cases deflected', 'Adoption', 1, 3, 10, 'cases');
        numeric.Sequence__c = 1;
        numeric.How_To_Complete__c = 'Route more cases through the AI resolver.';

        Tier_List_Item__c box = checkboxItem(
            t.Id, 'Nominate an exec sponsor', 'Engagement', 1, false);
        box.Sequence__c = 2;

        insert new List<Tier_List_Item__c>{ numeric, box };

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(t.Id);

        System.assertEquals(2, p.outstanding.size(), 'Both items are outstanding');

        TierProgressController.OutstandingItem first = p.outstanding[0];
        System.assertEquals('Cases deflected', first.label, 'Sequence should order the list');
        System.assertEquals('3 of 10 cases · 7 cases to go', first.remaining,
            'Numeric copy should spell out the gap');
        System.assertEquals(30.0, first.percent, 'Numeric item is 30% done');
        System.assertEquals('Route more cases through the AI resolver.', first.howToComplete,
            'Guidance should pass through');

        TierProgressController.OutstandingItem second = p.outstanding[1];
        System.assertEquals('Not started yet', second.remaining,
            'Checkbox copy should read as not started');
    }

    @isTest
    static void testFractionalValuesDropTrailingZeros() {
        Account a = newAccount();
        Tier__c t = newTier(a.Id, 'In Progress');

        insert numericItem(t.Id, 'CSAT', 'Adoption', 1, 4.25, 4.50, 'points');

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(t.Id);

        System.assertEquals('4.25 of 4.5 points · 0.25 points to go',
            p.outstanding[0].remaining, 'Numbers should print without padding zeros');
    }

    // ------------------------------------------------------------------
    // Record resolution
    // ------------------------------------------------------------------

    @isTest
    static void testResolvesFromAnAccountRecordPage() {
        Account a = newAccount();
        Tier__c t = newTier(a.Id, 'In Progress');
        insert checkboxItem(t.Id, 'Only item', 'Adoption', 1, true);

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(a.Id);

        System.assertNotEquals(null, p, 'Account should resolve to its live tier');
        System.assertEquals(t.Id, p.tierId, 'Wrong tier resolved');
        System.assertEquals('Tiering Test Co', p.subjectName, 'Account name should come through');
        System.assertEquals('Silver', p.currentTier, 'Current tier should come through');
        System.assertEquals('Gold', p.nextTier, 'Next tier should come through');
        System.assertEquals(Date.today().addDays(90), p.targetDate, 'Target date should come through');
    }

    @isTest
    static void testAccountPrefersTheTierStillInProgress() {
        Account a = newAccount();

        Tier__c achieved = newTier(a.Id, 'Achieved');
        achieved.Name = 'Old climb';
        update achieved;

        Tier__c live = newTier(a.Id, 'In Progress');

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(a.Id);

        System.assertEquals(live.Id, p.tierId,
            'The in-progress tier should win over the achieved one');
    }

    @isTest
    static void testAccountFallsBackToAnAchievedTier() {
        Account a = newAccount();
        Tier__c achieved = newTier(a.Id, 'Achieved');

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(a.Id);

        System.assertNotEquals(null, p, 'A finished climb should still render');
        System.assertEquals(achieved.Id, p.tierId, 'Wrong tier resolved');
    }

    @isTest
    static void testAccountWithNoTierReturnsNullForTheEmptyState() {
        Account a = newAccount();

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(a.Id);

        System.assertEquals(null, p,
            'No tier should be an empty state in the LWC, not an error toast');
    }

    @isTest
    static void testUnrelatedRecordRendersEmptyStateRatherThanThrowing() {
        // A well-formed 15-character Case id with nothing tracked against it.
        // The ring can now sit on any object, so this is an empty state.
        Id caseId = Id.valueOf('500000000000000');

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(caseId);

        System.assertEquals(null, p,
            'An unrelated record should render the empty state, not throw');
    }

    @isTest
    static void testNullRecordIdThrows() {
        Boolean threw = false;

        try {
            TierProgressController.getTierProgress(null);
        } catch (AuraHandledException expected) {
            threw = true;
        }

        System.assert(threw, 'Expected an AuraHandledException for a null id');
    }

    // ------------------------------------------------------------------
    // Resolution across Contact and the generic pointer
    // ------------------------------------------------------------------

    @isTest
    static void testResolvesFromAContactRecordPage() {
        Account a = newAccount();
        Contact c = new Contact(LastName = 'Partner Person', AccountId = a.Id);
        insert c;

        Tier__c t = new Tier__c(
            Name = 'Partner Person to Gold',
            Contact__c = c.Id,
            Current_Tier__c = 'Silver',
            Next_Tier__c = 'Gold',
            Status__c = 'In Progress'
        );
        insert t;
        insert checkboxItem(t.Id, 'Only item', 'Adoption', 1, false);

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(c.Id);

        System.assertNotEquals(null, p, 'A Contact should resolve its own tier');
        System.assertEquals(t.Id, p.tierId, 'Wrong tier resolved');
        System.assertEquals('Partner Person', p.subjectName,
            'Contact name should come through as the subject');
    }

    @isTest
    static void testContactWithoutItsOwnTierInheritsTheAccountTier() {
        Account a = newAccount();
        Tier__c accountTier = newTier(a.Id, 'In Progress');
        insert checkboxItem(accountTier.Id, 'Only item', 'Adoption', 1, false);

        Contact c = new Contact(LastName = 'Partner Person', AccountId = a.Id);
        insert c;

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(c.Id);

        System.assertNotEquals(null, p,
            'A partner contact should fall back to its account tier');
        System.assertEquals(accountTier.Id, p.tierId, 'Wrong tier resolved');
    }

    @isTest
    static void testContactPrefersItsOwnTierOverTheAccountTier() {
        Account a = newAccount();
        Tier__c accountTier = newTier(a.Id, 'In Progress');

        Contact c = new Contact(LastName = 'Partner Person', AccountId = a.Id);
        insert c;
        Tier__c contactTier = new Tier__c(
            Name = 'Partner Person to Gold',
            Contact__c = c.Id,
            Next_Tier__c = 'Gold',
            Status__c = 'In Progress'
        );
        insert contactTier;

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(c.Id);

        System.assertEquals(contactTier.Id, p.tierId,
            'The contact own tier should win over the account fallback');
    }

    /**
     * The generic pointer is what lets the ring sit on the standard Partner
     * object, PRM records, or any custom object without a lookup per object.
     * A Case stands in for "some other object" here.
     */
    @isTest
    static void testResolvesFromTheGenericRelatedRecordPointer() {
        Case c = new Case(Subject = 'Stands in for a partner record');
        insert c;

        Tier__c t = new Tier__c(
            Name = 'Generic pointer tier',
            Related_Record_Id__c = c.Id,
            Next_Tier__c = 'Gold',
            Status__c = 'In Progress'
        );
        insert t;
        insert checkboxItem(t.Id, 'Only item', 'Adoption', 1, true);

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(c.Id);

        System.assertNotEquals(null, p,
            'The generic pointer should resolve from an arbitrary object');
        System.assertEquals(t.Id, p.tierId, 'Wrong tier resolved');
        System.assertEquals(100.0, p.percentComplete, 'Percentage should still compute');
    }

    @isTest
    static void testGenericPointerMatchesAFifteenCharacterId() {
        Case c = new Case(Subject = 'Fifteen character id');
        insert c;

        Tier__c t = new Tier__c(
            Name = 'Fifteen char pointer',
            Related_Record_Id__c = String.valueOf(c.Id).substring(0, 15),
            Next_Tier__c = 'Gold',
            Status__c = 'In Progress'
        );
        insert t;

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(c.Id);

        System.assertNotEquals(null, p,
            'A hand-typed 15 character id should still match');
        System.assertEquals(t.Id, p.tierId, 'Wrong tier resolved');
    }

    @isTest
    static void testBlankPointerDoesNotMatchEveryRecord() {
        // Regression guard: an empty id set must match nothing rather than
        // matching every Tier whose Related_Record_Id__c is blank.
        Account a = newAccount();
        Tier__c unrelated = newTier(a.Id, 'In Progress');
        System.assertNotEquals(null, unrelated.Id, 'Fixture should exist');

        Case c = new Case(Subject = 'Nothing points at me');
        insert c;

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(c.Id);

        System.assertEquals(null, p,
            'A tier with a blank pointer must not match an unrelated record');
    }

    // ------------------------------------------------------------------
    // Ring colour override
    // ------------------------------------------------------------------

    @isTest
    static void testRingColourOverrideIsNormalised() {
        Account a = newAccount();
        Tier__c t = newTier(a.Id, 'In Progress');
        t.Ring_Color__c = 'D4A017';
        update t;

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(t.Id);

        System.assertEquals('#d4a017', p.ringColor,
            'A bare hex should gain its # and be lowercased');
    }

    @isTest
    static void testGarbageRingColourIsDropped() {
        Account a = newAccount();
        Tier__c t = newTier(a.Id, 'In Progress');
        t.Ring_Color__c = 'red';
        update t;

        TierProgressController.TierProgress p =
            TierProgressController.getTierProgress(t.Id);

        System.assertEquals(null, p.ringColor,
            'Anything that is not a 6-digit hex should fall back to the tier colour');
    }
}
