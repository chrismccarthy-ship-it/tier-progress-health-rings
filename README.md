# tier-progress-health-rings

An Apple-Health-style progress ring for Salesforce. It shows how far an
Account is from its next tier and — the part that actually gets used —
exactly what is still outstanding to get there.

```
            ╭───────────────╮
         ╭──┤   Adoption    ├──╮        Silver → Gold
        │  ╭┤  Engagement  ├╮  │        Northwind Treasury
        │  │╭┤  Advocacy  ├╮│  │        2 of 9 requirements complete
        │  ││    ┌────┐    ││  │        Target date: 21 Oct 2026
        │  ││    │ 55%│    ││  │
        │  ││    │ to │    ││  │        ● Adoption    74%  1 of 3 done
        │  ││    │Gold│    ││  │        ● Engagement  59%  1 of 3 done
        │  ╰╯    └────┘    ╰╯  │        ● Advocacy    15%  0 of 3 done
        ╰──────────────────────╯
        ────────────────────────────────────────────────
        7 REQUIREMENTS OUTSTANDING
        Executive sponsor named                      0%
        ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
        [Engagement]  Not started yet
        Confirm the COO as sponsor at the next steering committee.
```

Self-contained SFDX project — no managed packages, no external services,
no dependencies beyond a standard Salesforce org with Accounts.

## Data model

Two custom objects joined by a master-detail relationship:

| Object | Purpose |
|---|---|
| `Tier__c` | One Account's climb from `Current_Tier__c` to `Next_Tier__c` |
| `Tier_List_Item__c` | A single weighted requirement on that climb |

Each item carries a `Weight__c` and reports its own `Progress_Percent__c`,
measured one of two ways:

- **Checkbox** — `Completed__c` is ticked or it isn't. 0 or 100.
- **Numeric** — `Current_Value__c` against `Target_Value__c`, capped at
  100 so over-delivery doesn't push the ring past full. This is what gives
  the arcs partial fill instead of a staircase.

The completion percentage is the weighted mean:

```
Tier__c.Progress_Percent__c = Σ(Weight__c × Progress_Percent__c ÷ 100)
                              ─────────────────────────────────────────  × 100
                                          Σ(Weight__c)
```

Both halves of that are real roll-up summary fields (`Earned_Weight__c`
and `Total_Weight__c`), so tier progress is reportable and dashboard-able
without writing any Apex. `Items_Outstanding__c` counts the incomplete
children the same way.

### Why the percentage is computed twice

`TierProgressController` recomputes the identical figure from the child
rows rather than reading `Progress_Percent__c` off the parent. Roll-up
summaries recalculate asynchronously, so reading the field would leave the
ring a beat behind the checkbox the user just ticked.

`TierProgressControllerTest.testApexMirrorsFormulaField` asserts the Apex
and the formula field agree, so the two can't drift apart silently.

## The rings

`Tier_List_Item__c.Category__c` decides how many arcs are drawn. Each
distinct category becomes one concentric ring — outermost first, in the
order Adoption → Engagement → Advocacy — and the centre always shows the
overall weighted percentage. Put every item in one category (or none) and
it collapses to a single ring, which reads better than one lonely arc.

Three arcs is the ceiling. A fourth would close over the percentage in the
middle, so anything past the third category (including the `General`
bucket that items with a blank `Category__c` fall into) folds into the
innermost arc and is relabelled **Other**.

Arcs sweep from empty on load via a `stroke-dashoffset` transition, and
hold still under `prefers-reduced-motion`.

## Placing the component

`tierProgressRing` reads `recordId` and works out the rest:

- **On a `Tier__c` record page** — renders that record.
- **On an Account record page** — finds that Account's tier where
  `Status__c != 'Achieved'`, falling back to the most recent record so a
  finished climb still renders instead of an empty state.
- **On an Account with no tier at all** — renders an empty state, not an
  error.
- **Anywhere else** — throws with a message naming the object it was
  placed on.

App Builder properties:

| Property | Default | Effect |
|---|---|---|
| Card Title | `Tier Progress` | Heading on the card |
| Hide Outstanding List | `false` | Ring only, no requirement list |
| Max Outstanding Shown | `0` | Cap the rows listed; 0 shows all |

Targets include `lightningCommunity__Page`, so it works in Experience
Cloud as well as internal record pages.

## What's in here

```
force-app/main/default/
├── classes/
│   ├── TierProgressController        @AuraEnabled controller behind the ring
│   └── TierProgressControllerTest    15 tests
│
├── lwc/
│   └── tierProgressRing/             the SVG arcs + outstanding list
│
├── objects/
│   ├── Tier__c/                      progression record + roll-ups
│   └── Tier_List_Item__c/            weighted requirements
│
├── tabs/                             Tier__c, Tier_List_Item__c
└── permissionsets/                   Tier_Progress_User
```

## Deploy

```bash
# Validate first — runs the tests without committing anything
sf project deploy validate \
  --source-dir force-app \
  --test-level RunSpecifiedTests --tests TierProgressControllerTest \
  --target-org <your-org-alias>

# Then commit
sf project deploy start \
  --source-dir force-app \
  --test-level RunSpecifiedTests --tests TierProgressControllerTest \
  --target-org <your-org-alias>
```

## Post-deploy

```bash
# 1. Assign the permission set
sf org assign permset --name Tier_Progress_User --target-org <alias>

# 2. Seed a worked example — one Account, three categories,
#    nine requirements, partly complete
sf apex run --file scripts/apex/seed-tier-progress.apex --target-org <alias>
```

Then drop **Tier Progress Ring** onto the Northwind Treasury Account
Lightning record page in App Builder.

The seed script is idempotent — it reuses the Account and Tier by name and
replaces the child items, so re-running it after edits won't leave
duplicates behind.

## Known schema caveat

`Tier__c.Items_Outstanding__c` is a COUNT roll-up filtered on the
`Is_Complete__c` formula checkbox. If your org rejects a formula field in
roll-up filter criteria, either drop the filter and subtract from a plain
COUNT, or filter on the raw `Completed__c` checkbox instead — accepting
that partially-met Numeric items then count as outstanding until ticked.

Nothing in the LWC depends on this field; it exists for reporting.

## Adapting it

- **Different tier names** — edit the `Current_Tier__c` and `Next_Tier__c`
  picklists, then the `TIER_COLORS` map at the top of `tierProgressRing.js`.
- **Different categories** — edit the `Category__c` picklist, then
  `CATEGORY_ORDER` in `TierProgressController` (ring order) and
  `CATEGORY_COLORS` in the LWC (arc colour).
- **Attach to something other than Account** — swap the `Account__c`
  lookup on `Tier__c` and extend `resolveTierId()` with the new object's
  branch.
- **Feeding values automatically** — `Current_Value__c` is a plain number
  field, so a scheduled Flow, batch job, or Data Cloud calculated insight
  can write to it and the ring follows.

## Licence

MIT — see [LICENSE](LICENSE).
