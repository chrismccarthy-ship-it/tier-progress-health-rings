/**
 * TierProgressController
 * --------------------------------------------------------------------
 * @AuraEnabled controller behind the tierProgressRing LWC.
 *
 * Resolves a Tier__c record from whatever record page the component is
 * sitting on, then returns everything the ring needs in one shape:
 *
 *   • the weighted completion percentage toward the next tier
 *   • one ring per Category__c (the concentric Apple-Health-style arcs)
 *   • the still-outstanding Tier_List_Item__c rows, each with a
 *     human-readable statement of what is left to do
 *
 * The percentages are recomputed here from the child rows rather than
 * read off Tier__c.Progress_Percent__c. That roll-up is a genuine field
 * and is fine for reports, but roll-up summaries recalculate
 * asynchronously — recomputing means the ring is never a beat behind the
 * checkbox the user just ticked.
 */
public with sharing class TierProgressController {

    /** Rings render outermost-first in this order; anything else follows alphabetically. */
    private static final List<String> CATEGORY_ORDER = new List<String>{
        // Partner ladder, then the Brokerage / Dealer ladder. A given tier
        // only uses one family, so the two never compete for ring slots.
        'Adoption', 'Engagement', 'Advocacy',
        'Production', 'Compliance', 'Relationship',
        'Implementation', 'Integration'
    };

    /**
     * The LWC draws arcs at radius 86, 65 and 44 in a 200-unit box. A fourth
     * would close over the percentage in the middle, so extra categories —
     * including the General bucket that blank Category__c values fall into —
     * fold into the innermost arc instead.
     */
    private static final Integer MAX_RINGS = 3;

    private static final String UNCATEGORISED = 'General';

    // ------------------------------------------------------------------
    // Wire shapes
    // ------------------------------------------------------------------

    public class RingData {
        @AuraEnabled public String  key;
        @AuraEnabled public String  label;
        @AuraEnabled public Decimal percent;
        @AuraEnabled public Integer itemsTotal;
        @AuraEnabled public Integer itemsComplete;
        /** Every category folded into this arc. Usually one; more when
            categories past MAX_RINGS merge into the innermost. */
        @AuraEnabled public List<String> categories;
    }

    public class OutstandingItem {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  label;
        @AuraEnabled public String  category;
        @AuraEnabled public Decimal percent;
        @AuraEnabled public String  remaining;
        @AuraEnabled public String  howToComplete;
        @AuraEnabled public Decimal weight;
    }

    public class TierProgress {
        @AuraEnabled public Id      tierId;
        @AuraEnabled public String  tierName;
        @AuraEnabled public String  subjectName;
        @AuraEnabled public String  currentTier;
        @AuraEnabled public String  nextTier;
        @AuraEnabled public String  status;
        @AuraEnabled public Date    targetDate;
        @AuraEnabled public String  ringColor;
        @AuraEnabled public Decimal percentComplete;
        @AuraEnabled public Integer itemsTotal;
        @AuraEnabled public Integer itemsComplete;
        @AuraEnabled public Integer itemsOutstanding;
        @AuraEnabled public List<RingData>        rings;
        @AuraEnabled public List<OutstandingItem> outstanding;
    }

    // ------------------------------------------------------------------
    // Entry point
    // ------------------------------------------------------------------

    /**
     * @param recordId Any record the ring is sitting on — a Tier__c, an
     *                 Account (including a Person Account or a partner
     *                 account), a Contact, or anything pointed at by
     *                 Related_Record_Id__c.
     * @return null when nothing is tracked against that record — the LWC
     *         renders an empty state rather than an error for that case.
     */
    @AuraEnabled(cacheable=true)
    public static TierProgress getTierProgress(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('No record id was supplied to the tier ring.');
        }

        Id tierId = resolveTierId(recordId);
        if (tierId == null) {
            return null;
        }

        List<Tier__c> tiers = [
            SELECT Id, Name,
                   Account__c, Account__r.Name,
                   Contact__c, Contact__r.Name,
                   Related_Record_Id__c,
                   Current_Tier__c, Next_Tier__c, Status__c,
                   Target_Date__c, Ring_Color__c
            FROM Tier__c
            WHERE Id = :tierId
            WITH USER_MODE
            LIMIT 1
        ];
        if (tiers.isEmpty()) {
            return null;
        }
        Tier__c tier = tiers[0];

        List<Tier_List_Item__c> items = [
            SELECT Id, Name, Category__c, Measure_Type__c, Completed__c,
                   Current_Value__c, Target_Value__c, Unit__c,
                   Weight__c, Sequence__c, How_To_Complete__c
            FROM Tier_List_Item__c
            WHERE Tier__c = :tierId
            WITH USER_MODE
            ORDER BY Sequence__c ASC NULLS LAST, Name ASC
        ];

        return build(tier, items);
    }

    // ------------------------------------------------------------------
    // Resolution
    // ------------------------------------------------------------------

    /**
     * Works out which Tier__c to render from whatever record page the
     * component was dropped onto.
     *
     * Resolution runs most-specific first:
     *   1. A Tier__c id is used directly.
     *   2. Account__c / Contact__c, the typed lookups. A Person Account is
     *      one entity with two ids, so a tier recorded against either side
     *      surfaces on both pages.
     *   3. Related_Record_Id__c, the generic pointer — this is what lets the
     *      ring sit on the standard Partner object, PRM records, or any
     *      custom object without a lookup field per object.
     *   4. For a Contact with no tier of its own, its Account's tier. A
     *      partner contact under a partner account normally wants to see
     *      the partner's progress.
     *
     * @return null when nothing matches, so the LWC shows an empty state
     *         rather than an error.
     */
    private static Id resolveTierId(Id recordId) {
        String sobjectName = recordId.getSObjectType().getDescribe().getName();

        if (sobjectName == 'Tier__c') {
            return recordId;
        }

        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        String idText = String.valueOf(recordId);
        Set<String> relatedIds = new Set<String>{ idText, idText.substring(0, 15) };

        if (sobjectName == 'Account') {
            accountIds.add(recordId);
            Id personContact = personContactIdFor(recordId);
            if (personContact != null) {
                contactIds.add(personContact);
            }
        } else if (sobjectName == 'Contact') {
            contactIds.add(recordId);
        }

        Id match = findTier(accountIds, contactIds, relatedIds);
        if (match != null) {
            return match;
        }

        if (sobjectName == 'Contact') {
            List<Contact> parents = [
                SELECT AccountId FROM Contact WHERE Id = :recordId WITH USER_MODE LIMIT 1
            ];
            if (!parents.isEmpty() && parents[0].AccountId != null) {
                return findTier(
                    new Set<Id>{ parents[0].AccountId },
                    new Set<Id>(),
                    new Set<String>());
            }
        }

        return null;
    }

    /**
     * Prefers the tier still being climbed; falls back to the most recent so
     * a finished climb still renders instead of an empty state.
     *
     * Empty sets match nothing in SOQL, which is what makes it safe to pass
     * the unused ones through rather than branching per caller.
     */
    private static Id findTier(
        Set<Id> accountIds, Set<Id> contactIds, Set<String> relatedIds
    ) {
        if (accountIds.isEmpty() && contactIds.isEmpty() && relatedIds.isEmpty()) {
            return null;
        }

        List<Tier__c> live = [
            SELECT Id
            FROM Tier__c
            WHERE (Account__c IN :accountIds
                   OR Contact__c IN :contactIds
                   OR Related_Record_Id__c IN :relatedIds)
              AND Status__c != 'Achieved'
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!live.isEmpty()) {
            return live[0].Id;
        }

        List<Tier__c> newest = [
            SELECT Id
            FROM Tier__c
            WHERE (Account__c IN :accountIds
                   OR Contact__c IN :contactIds
                   OR Related_Record_Id__c IN :relatedIds)
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return newest.isEmpty() ? null : newest[0].Id;
    }

    /**
     * The contact id behind a Person Account, or null.
     *
     * Queried dynamically on purpose: IsPersonAccount and PersonContactId
     * only exist once Person Accounts are enabled, and a static reference
     * would stop this class compiling in every org that has not turned
     * them on.
     */
    private static Id personContactIdFor(Id accountId) {
        if (!Schema.SObjectType.Account.fields.getMap().containsKey('ispersonaccount')) {
            return null;
        }
        try {
            List<SObject> rows = Database.queryWithBinds(
                'SELECT PersonContactId FROM Account ' +
                'WHERE Id = :accountId AND IsPersonAccount = true LIMIT 1',
                new Map<String, Object>{ 'accountId' => accountId },
                AccessLevel.USER_MODE);
            return rows.isEmpty() ? null : (Id) rows[0].get('PersonContactId');
        } catch (Exception ignored) {
            return null;
        }
    }

    // ------------------------------------------------------------------
    // Assembly
    // ------------------------------------------------------------------

    private static TierProgress build(Tier__c tier, List<Tier_List_Item__c> items) {
        TierProgress p = new TierProgress();
        p.tierId      = tier.Id;
        p.tierName    = tier.Name;
        p.subjectName = tier.Account__r != null ? tier.Account__r.Name
                      : tier.Contact__r != null ? tier.Contact__r.Name
                      : null;
        p.currentTier = tier.Current_Tier__c;
        p.nextTier    = tier.Next_Tier__c;
        p.status      = tier.Status__c;
        p.targetDate  = tier.Target_Date__c;
        p.ringColor   = normaliseHex(tier.Ring_Color__c);
        p.rings       = new List<RingData>();
        p.outstanding = new List<OutstandingItem>();

        p.itemsTotal      = items.size();
        p.itemsComplete   = 0;
        p.itemsOutstanding = 0;

        // Category buckets, insertion-ordered so ring order stays stable.
        Map<String, Decimal> earnedByCategory = new Map<String, Decimal>();
        Map<String, Decimal> weightByCategory = new Map<String, Decimal>();
        Map<String, Integer> totalByCategory  = new Map<String, Integer>();
        Map<String, Integer> doneByCategory   = new Map<String, Integer>();

        Decimal totalWeight  = 0;
        Decimal earnedWeight = 0;

        for (Tier_List_Item__c item : items) {
            Decimal weight  = item.Weight__c == null ? 1 : item.Weight__c;
            if (weight < 0) {
                weight = 0;
            }
            Decimal percent = itemPercent(item);
            Boolean done    = percent >= 100;

            totalWeight  += weight;
            earnedWeight += weight * percent / 100;

            String category = String.isBlank(item.Category__c) ? UNCATEGORISED : item.Category__c;
            if (!weightByCategory.containsKey(category)) {
                weightByCategory.put(category, 0);
                earnedByCategory.put(category, 0);
                totalByCategory.put(category, 0);
                doneByCategory.put(category, 0);
            }
            weightByCategory.put(category, weightByCategory.get(category) + weight);
            earnedByCategory.put(category, earnedByCategory.get(category) + (weight * percent / 100));
            totalByCategory.put(category, totalByCategory.get(category) + 1);

            if (done) {
                p.itemsComplete++;
                doneByCategory.put(category, doneByCategory.get(category) + 1);
            } else {
                p.itemsOutstanding++;
                OutstandingItem o = new OutstandingItem();
                o.id            = item.Id;
                o.label         = item.Name;
                o.category      = category;
                o.percent       = round1(percent);
                o.remaining     = remainingText(item);
                o.howToComplete = item.How_To_Complete__c;
                o.weight        = weight;
                p.outstanding.add(o);
            }
        }

        p.percentComplete = totalWeight > 0
            ? round1(earnedWeight / totalWeight * 100)
            : 0;

        p.rings = buildRings(
            weightByCategory, earnedByCategory, totalByCategory, doneByCategory, p.percentComplete);

        return p;
    }

    /**
     * One ring per category. A tier whose items are all uncategorised — or
     * that only uses one category — collapses to a single overall ring,
     * which reads better than one lonely arc labelled "Adoption".
     */
    private static List<RingData> buildRings(
        Map<String, Decimal> weightByCategory,
        Map<String, Decimal> earnedByCategory,
        Map<String, Integer> totalByCategory,
        Map<String, Integer> doneByCategory,
        Decimal overallPercent
    ) {
        List<RingData> rings = new List<RingData>();
        List<String> categories = sortCategories(weightByCategory.keySet());

        if (categories.size() <= 1) {
            RingData overall = new RingData();
            overall.key           = 'overall';
            overall.label         = 'Overall';
            overall.percent       = overallPercent;
            overall.itemsTotal    = 0;
            overall.itemsComplete = 0;
            overall.categories    = new List<String>(categories);
            for (String category : categories) {
                overall.itemsTotal    += totalByCategory.get(category);
                overall.itemsComplete += doneByCategory.get(category);
            }
            rings.add(overall);
            return rings;
        }

        // Slot i is the i-th arc from the outside in. Categories past the
        // last slot fold into it so their items still count for something
        // visually, rather than vanishing off the bottom of the ring.
        List<Decimal> slotWeight = new List<Decimal>();
        List<Decimal> slotEarned = new List<Decimal>();

        for (Integer i = 0; i < categories.size(); i++) {
            String category = categories[i];
            Integer slot = i < MAX_RINGS ? i : MAX_RINGS - 1;

            if (slot == rings.size()) {
                RingData ring = new RingData();
                ring.key           = category;
                ring.label         = category;
                ring.percent       = 0;
                ring.itemsTotal    = 0;
                ring.itemsComplete = 0;
                ring.categories    = new List<String>();
                rings.add(ring);
                slotWeight.add(0);
                slotEarned.add(0);
            } else {
                // Something was already in this slot, so it is no longer a
                // single named category.
                rings[slot].key   = 'other';
                rings[slot].label = 'Other';
            }

            RingData target = rings[slot];
            target.categories.add(category);
            target.itemsTotal    += totalByCategory.get(category);
            target.itemsComplete += doneByCategory.get(category);
            slotWeight.set(slot, slotWeight[slot] + weightByCategory.get(category));
            slotEarned.set(slot, slotEarned[slot] + earnedByCategory.get(category));
        }

        for (Integer i = 0; i < rings.size(); i++) {
            rings[i].percent = slotWeight[i] > 0
                ? round1(slotEarned[i] / slotWeight[i] * 100)
                : 0;
        }

        return rings;
    }

    private static List<String> sortCategories(Set<String> keys) {
        List<String> ordered = new List<String>();
        for (String known : CATEGORY_ORDER) {
            if (keys.contains(known)) {
                ordered.add(known);
            }
        }
        List<String> rest = new List<String>();
        for (String key : keys) {
            if (!CATEGORY_ORDER.contains(key)) {
                rest.add(key);
            }
        }
        rest.sort();
        ordered.addAll(rest);
        return ordered;
    }

    // ------------------------------------------------------------------
    // Per-item maths and copy
    // ------------------------------------------------------------------

    /**
     * Mirrors the Progress_Percent__c formula field. Kept in sync by hand;
     * TierProgressControllerTest asserts the two agree.
     */
    private static Decimal itemPercent(Tier_List_Item__c item) {
        if (item.Measure_Type__c == 'Numeric') {
            Decimal target = item.Target_Value__c;
            if (target == null || target <= 0) {
                return 0;
            }
            Decimal current = item.Current_Value__c == null ? 0 : item.Current_Value__c;
            if (current <= 0) {
                return 0;
            }
            Decimal percent = current / target * 100;
            return percent > 100 ? 100 : percent;
        }
        return item.Completed__c == true ? 100 : 0;
    }

    /** "3 of 10 tickets · 7 to go", or "Not started yet" for checkbox items. */
    private static String remainingText(Tier_List_Item__c item) {
        if (item.Measure_Type__c != 'Numeric') {
            return 'Not started yet';
        }

        Decimal target = item.Target_Value__c;
        if (target == null || target <= 0) {
            return 'No target set';
        }
        Decimal current = item.Current_Value__c == null ? 0 : item.Current_Value__c;
        String unit = String.isBlank(item.Unit__c) ? '' : ' ' + item.Unit__c.trim();

        String text = fmt(current) + ' of ' + fmt(target) + unit;
        Decimal gap = target - current;
        if (gap > 0) {
            text += ' · ' + fmt(gap) + unit + ' to go';
        }
        return text;
    }

    private static String fmt(Decimal value) {
        if (value == null) {
            return '0';
        }
        return value.setScale(2, System.RoundingMode.HALF_UP)
                    .stripTrailingZeros()
                    .toPlainString();
    }

    private static Decimal round1(Decimal value) {
        return value == null ? 0 : value.setScale(1, System.RoundingMode.HALF_UP);
    }

    /** Accepts "D4A017" or "#d4a017"; rejects anything that is not a 6-digit hex. */
    private static String normaliseHex(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String hex = raw.trim();
        if (!hex.startsWith('#')) {
            hex = '#' + hex;
        }
        return Pattern.matches('^#[0-9a-fA-F]{6}$', hex) ? hex.toLowerCase() : null;
    }
}
