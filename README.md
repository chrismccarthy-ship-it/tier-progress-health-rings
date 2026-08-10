# tier-progress-health-rings

A Watch-Health-style progress ring for Salesforce. It shows how far an
Account is from its next tier and — the part that actually gets used —
exactly what is still outstanding to get there.

```
        ╭──────────────╮      74%  to Premier Producer
      ╭─┤  Production  ├─╮
     ╭┤ ╭┤ Compliance ├╮ ├╮   Producer → Premier Producer
     ││ ││Relationship││ ││   Meridian Wealth Partners
     ││ ││            ││ ││   2 of 9 requirements complete
     ││ ╰╯            ╰╯ ││   Target date: 7 Dec 2026
     ╰┤                  ├╯
      ╰──────────────────╯    ● Production    78%   0 of 3 done
                              ● Compliance    69%   1 of 3 done
                              ● Relationship  74%   1 of 3 done
        ─────────────────────────────────────────────────
        7 REQUIREMENTS OUTSTANDING
        Assets under management                       77%
        ████████████████████████████░░░░░░░░░░░░░░░░░░░░░
        [Production]  385 of 500 $M · 115 $M to go
        Three institutional mandates in final diligence
        would close most of the gap.
```

Click any arc — or any legend row — to filter the list to that category.


Self-contained SFDX project — no managed packages, no external services,
no dependencies beyond a standard Salesforce org with Accounts.

## Data model

Two custom objects joined by a master-detail relationship:

| Object | Purpose |
|---|---|
| `Tier__c` | One record's climb from `Current_Tier__c` to `Next_Tier__c` |
| `Tier_List_Item__c` | A single weighted requirement on that climb |

### Tier programmes

`Program__c` says which ladder a record climbs. All four share one picklist
for the level, and the `Level_Matches_Program` validation rule stops a
Dealer tier being pointed at a Partner level.

| Programme | Levels, low to high |
|---|---|
| **Partner** | Silver → Gold → Platinum → Diamond |
| **Brokerage** | Registered Rep → Producer → Premier Producer → President's Council → Chairman's Circle |
| **Dealer** | Approved Dealer → Preferred Dealer → Premier Dealer → Elite Dealer → President's Club |
| **Commercial Banking** | Applicant → Onboarding → Treasury Live |

Brokerage uses the producer-recognition language common to broker-dealers
and wealth managers, keyed on production and AUM. Dealer uses indirect auto
lending statuses, the kind a captive lender runs for franchise dealers
against funded contracts, look-to-book and floor plan performance.

Commercial Banking is a different shape from the other three — a sequence
of onboarding gates rather than a metrics climb. It shows that the same
ring works for a journey: the arcs become phases, and "what is still
outstanding" becomes the implementation checklist.

Categories follow the programme, three per family so the ring always
resolves to three arcs:

| Programme | Categories |
|---|---|
| Partner | Adoption / Engagement / Advocacy |
| Brokerage, Dealer | Production / Compliance / Relationship |
| Commercial Banking | Compliance / Implementation / Integration |

Adding another programme means three edits: a `Program__c` value, its
levels on `Current_Tier__c` and `Next_Tier__c`, and a branch in the
validation rule. Both the rule's error message and its description are
capped at 255 characters, which is tighter than it looks once a fourth
ladder is spelled out. Colours for new levels go in `TIER_COLORS` at the top of
`tierProgressRing.js`; a level with no entry falls back to the default blue.

### Attaching a tier

A `Tier__c` attaches to whatever the climb belongs to, three ways:

| Field | Covers |
|---|---|
| `Account__c` | Accounts, Person Accounts and partner accounts — all one object |
| `Contact__c` | Contacts, including partner contacts |
| `Related_Record_Id__c` | Everything else: the standard `Partner` object, PRM records such as `PartnerFundClaim`, or any custom object. Paste the record id in and the ring resolves from that record's page with no schema change. |

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
distinct category becomes one concentric ring, outermost first in the order
set by `CATEGORY_ORDER` in `TierProgressController`. A tier only ever draws
from its own programme's family, so the two families never compete for ring
slots. Put every item in one category (or none) and it collapses to a
single ring, which reads better than one lonely arc.

Three arcs is the ceiling. A fourth would close over the percentage in the
middle, so anything past the third category (including the `General`
bucket that items with a blank `Category__c` fall into) folds into the
innermost arc and is relabelled **Other**.

Arcs sweep from empty on load via a `stroke-dashoffset` transition, and
hold still under `prefers-reduced-motion`.

The overall percentage sits **beside** the rings rather than inside them.
Three arcs leave a hole barely wider than the number itself, and the
"to *tier*" caption never fitted at all.

Clicking an arc, or its legend row, filters the outstanding list to that
category; the other arcs dim so the ring shows what the list is scoped to.
Clicking again clears it, as does **Show all**. The legend rows are real
buttons, so the filter is reachable from the keyboard — the arcs are a
convenience on top, not the only way in.

Colours come from **SLDS global styling hooks** with light-theme fallbacks,
not from `prefers-color-scheme`. Lightning Experience renders its own theme
regardless of the operating system setting, so a `prefers-color-scheme`
block turns the text light on a white card for every user whose OS is in
dark mode. Styling hooks follow Salesforce instead, which also means the
component picks up SLDS 2 dark mode for free wherever an org enables it.

## Placing the component

The component is not restricted to particular objects, so it appears in
App Builder on **every** record page. It reads `recordId` and resolves in
this order, most specific first:

1. **A `Tier__c` id** — renders that record.
2. **`Account__c` / `Contact__c`** — the typed lookups. A Person Account is
   one entity with two ids, so a tier recorded against either side surfaces
   on both its Account page and its Contact page.
3. **`Related_Record_Id__c`** — the generic pointer, matched against both
   the 15 and 18 character forms of the id.
4. **A Contact's Account** — a Contact with no tier of its own falls back
   to its Account's, which is what a partner contact under a partner
   account normally wants.

At each step it prefers the tier where `Status__c != 'Achieved'`, falling
back to the most recent so a finished climb still renders. A record with
nothing tracked against it renders an empty state rather than an error.

Person Account support is queried dynamically on purpose: `IsPersonAccount`
and `PersonContactId` only exist once Person Accounts are enabled, and a
static reference would stop the class compiling in orgs that have not
turned them on. The package deploys either way.

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
│   └── TierProgressControllerTest    25 tests
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

# 2. Seed one worked example of each programme
sf apex run --file scripts/apex/seed-tier-programs.apex --target-org <alias>
```

That creates three Accounts, each with a partly-complete climb:

| Account | Programme | Climb | Sample requirements |
|---|---|---|---|
| Meridian Wealth Partners | Brokerage | Producer → Premier Producer | AUM, net new assets, Reg BI attestations, firm element CE, client retention |
| Coastal Auto Group | Dealer | Preferred → Premier Dealer | Funded contracts, look-to-book, floor plan utilisation, chargeback rate, CSI, F&I penetration |
| Northwind Treasury | Partner | Gold → Platinum | Seats activated, certified admins, QBR, exec sponsor, reference call |

Then drop **Tier Progress Ring** onto any of those Account record pages in
App Builder.

`seed-tier-progress.apex` is still there and seeds the Partner example on
its own if that is all you need.

`seed-techco-onboarding.apex` seeds a fourth example — a Commercial Banking
treasury onboarding — but targets a specific Account **by record id**, so
it only works in the org that record lives in. Change `ACCOUNT_ID` at the
top before running it elsewhere. It looks the Account up rather than
creating one, and stops with a clear message if the id does not resolve.

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
- **Attach to another object** — set `Related_Record_Id__c` to the record
  id; no schema or code change needed. Add a dedicated lookup only if you
  want the referential integrity and report joins that come with one.
- **Feeding values automatically** — `Current_Value__c` is a plain number
  field, so a scheduled Flow, batch job, or Data Cloud calculated insight
  can write to it and the ring follows.

## Licence

MIT — see [LICENSE](LICENSE).
