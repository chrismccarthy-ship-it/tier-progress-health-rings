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

Self-contained SFDX project. No managed packages, no external services, no
dependencies beyond a standard Salesforce org with Accounts.

---

## Contents

- [Quick start](#quick-start)
- [Data model](#data-model)
- [Field reference](#field-reference)
- [Tier programmes](#tier-programmes)
- [The rings](#the-rings)
- [Placing the component](#placing-the-component)
- [Deploying](#deploying)
- [Seeding demo data](#seeding-demo-data)
- [Running the tests](#running-the-tests)
- [Troubleshooting](#troubleshooting)
- [Notes for maintainers](#notes-for-maintainers)
- [Adapting it](#adapting-it)
- [Verification status](#verification-status)

---

## Quick start

```bash
git clone https://github.com/chrismccarthy-ship-it/tier-progress-health-rings
cd tier-progress-health-rings

sf project deploy start --source-dir force-app --target-org <alias>
sf org assign permset --name Tier_Progress_User --target-org <alias>
sf apex run --file scripts/apex/seed-tier-programs.apex --target-org <alias>
```

Then **Setup → Object Manager → Account → Lightning Record Pages**, edit the
page, drag **Tier Progress Ring** onto it, Save and Activate. Open
**Meridian Wealth Partners**, **Coastal Auto Group** or **Northwind
Treasury** to see a ring.

On **PowerShell**, put each command on one line. A trailing `\` is not a
line continuation in PowerShell — it is parsed as part of the argument and
the command fails with `Missing expression after unary operator '--'`. Use a
backtick `` ` `` if you must wrap.

---

## Data model

Two custom objects joined by a master-detail relationship:

| Object | Purpose |
|---|---|
| `Tier__c` | One record's climb from `Current_Tier__c` to `Next_Tier__c` |
| `Tier_List_Item__c` | A single weighted requirement on that climb |

Each item carries a `Weight__c` and reports its own `Progress_Percent__c`,
measured one of two ways:

- **Checkbox** — `Completed__c` is ticked or it isn't. 0 or 100.
- **Numeric** — `Current_Value__c` against `Target_Value__c`, capped at 100
  so over-delivery doesn't push the ring past full. This is what gives the
  arcs partial fill instead of a staircase.

The completion percentage is the weighted mean:

```
Tier__c.Progress_Percent__c = Σ(Weight__c × Progress_Percent__c ÷ 100)
                              ─────────────────────────────────────────  × 100
                                          Σ(Weight__c)
```

Both halves of that are real roll-up summary fields (`Earned_Weight__c` and
`Total_Weight__c`), so tier progress is reportable and dashboard-able
without writing any Apex. `Items_Outstanding__c` counts the incomplete
children the same way.

### Why the percentage is computed twice

`TierProgressController` recomputes the identical figure from the child rows
rather than reading `Progress_Percent__c` off the parent. Roll-up summaries
recalculate asynchronously, so reading the field would leave the ring a beat
behind the checkbox the user just ticked.

`TierProgressControllerTest.testApexMirrorsFormulaField` asserts the Apex and
the formula field agree, so the two can't drift apart silently. If you change
one, that test fails until you change the other.

---

## Field reference

### `Tier__c`

| Field | Type | Notes |
|---|---|---|
| `Name` | Text | Free text, e.g. `Meridian Wealth Partners - Premier Producer` |
| `Account__c` | Lookup(Account) | Accounts, Person Accounts, partner accounts |
| `Contact__c` | Lookup(Contact) | Contacts, including partner contacts |
| `Related_Record_Id__c` | Text(18), External Id | Generic pointer to any other object |
| `Program__c` | Picklist | Partner, Brokerage, Dealer, Commercial Banking |
| `Current_Tier__c` | Picklist | Level held today, plus `Unranked` |
| `Next_Tier__c` | Picklist | Level being climbed toward |
| `Status__c` | Picklist | In Progress, At Risk, Achieved |
| `Ring_Color__c` | Text(7) | Optional hex override, e.g. `#D4A017` |
| `Target_Date__c` | Date | Shown under the ring |
| `Total_Weight__c` | Roll-up SUM | `Σ Weight__c` — the denominator |
| `Earned_Weight__c` | Roll-up SUM | `Σ Weighted_Progress__c` — the numerator |
| `Items_Outstanding__c` | Roll-up COUNT | Children where `Is_Complete__c = false` |
| `Progress_Percent__c` | Formula (Number) | `Earned / Total × 100` |

Validation rule **`Level_Matches_Program`** stops a Dealer tier being pointed
at a Partner level.

### `Tier_List_Item__c`

| Field | Type | Notes |
|---|---|---|
| `Name` | Text | The requirement, e.g. `Assets under management` |
| `Tier__c` | Master-Detail(Tier__c) | Required; reparentable |
| `Category__c` | Picklist | Decides which arc the item lands in |
| `Measure_Type__c` | Picklist | `Checkbox` or `Numeric` |
| `Completed__c` | Checkbox | Used when `Measure_Type__c = Checkbox` |
| `Current_Value__c` | Number(18,2) | Used when `Measure_Type__c = Numeric` |
| `Target_Value__c` | Number(18,2) | Used when `Measure_Type__c = Numeric` |
| `Unit__c` | Text(20) | Suffix in the gap text, e.g. `seats`, `%`, `$M` |
| `Weight__c` | Number(5,2), default 1 | Relative to siblings; 2 counts twice as much as 1 |
| `Sequence__c` | Number(4,0) | Display order; ties fall back to alphabetical |
| `How_To_Complete__c` | Text(255) | One line of guidance shown under the item |
| `Progress_Percent__c` | Formula (Number) | 0–100 for this one item |
| `Is_Complete__c` | Formula (Checkbox) | `Progress_Percent__c >= 100` |
| `Weighted_Progress__c` | Formula (Number) | `Weight × Progress ÷ 100`; rolled up to the parent |

---

## Tier programmes

`Program__c` says which ladder a record climbs. All four share one picklist
for the level.

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

Commercial Banking is a different shape from the other three — a sequence of
onboarding gates rather than a metrics climb. It shows that the same ring
works for a journey: the arcs become phases, and "what is still outstanding"
becomes the implementation checklist.

Categories follow the programme, three per family so the ring always
resolves to three arcs:

| Programme | Categories |
|---|---|
| Partner | Adoption / Engagement / Advocacy |
| Brokerage, Dealer | Production / Compliance / Relationship |
| Commercial Banking | Compliance / Implementation / Integration |

### Adding a fifth programme

Four edits:

1. A new value on `Program__c`.
2. Its levels on **both** `Current_Tier__c` and `Next_Tier__c`.
3. A branch in the `Level_Matches_Program` validation rule.
4. Colours in `TIER_COLORS` at the top of `tierProgressRing.js`. A level
   with no entry falls back to the default blue — cosmetic, not fatal.

If the programme needs new categories, also add them to `Category__c`, to
`CATEGORY_ORDER` in `TierProgressController` (ring order) and to
`CATEGORY_COLORS` in the LWC (arc colour).

**Watch the 255-character cap.** Both the validation rule's `errorMessage`
*and* its `description` are capped at 255 — tighter than it looks once a
fifth ladder is spelled out, and a breach fails the whole deploy. See
[Troubleshooting](#troubleshooting).

---

## The rings

`Tier_List_Item__c.Category__c` decides how many arcs are drawn. Each
distinct category becomes one concentric ring, outermost first in the order
set by `CATEGORY_ORDER` in `TierProgressController`. A tier only ever draws
from its own programme's family, so the families never compete for ring
slots. Put every item in one category (or none) and it collapses to a single
ring, which reads better than one lonely arc.

Three arcs is the ceiling. A fourth would close over the middle of the ring,
so anything past the third category — including the `General` bucket that
items with a blank `Category__c` fall into — folds into the innermost arc
and is relabelled **Other**.

Arcs sweep from empty on load via a `stroke-dashoffset` transition, and hold
still under `prefers-reduced-motion`.

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

---

## Placing the component

The component is not restricted to particular objects, so it appears in App
Builder on **every** record page. It reads `recordId` and resolves in this
order, most specific first:

1. **A `Tier__c` id** — renders that record.
2. **`Account__c` / `Contact__c`** — the typed lookups. A Person Account is
   one entity with two ids, so a tier recorded against either side surfaces
   on both its Account page and its Contact page.
3. **`Related_Record_Id__c`** — the generic pointer, matched against both
   the 15 and 18 character forms of the id.
4. **A Contact's Account** — a Contact with no tier of its own falls back to
   its Account's, which is what a partner contact under a partner account
   normally wants.

At each step it prefers the tier where `Status__c != 'Achieved'`, falling
back to the most recent so a finished climb still renders. A record with
nothing tracked against it renders an empty state rather than an error.

Person Account support is queried dynamically on purpose: `IsPersonAccount`
and `PersonContactId` only exist once Person Accounts are enabled, and a
static reference would stop the class compiling in orgs that have not turned
them on. The package deploys either way.

### App Builder properties

| Property | Default | Effect |
|---|---|---|
| Card Title | `Tier Progress` | Heading on the card |
| Hide Outstanding List | `false` | Ring only, no requirement list |
| Max Outstanding Shown | `0` | Cap the rows listed; 0 shows all |

Targets include `lightningCommunity__Page`, so it works in Experience Cloud
as well as internal record pages.

---

## Deploying

### Authorising an org

```bash
sf org list                              # what is already authorised
sf org login web --alias <alias>         # authorise a new one
```

`sf org login device` was removed from recent CLI versions. The remaining
auth methods are `web`, `jwt`, `sfdx-url` and `access-token`.

### Deploy

```bash
# Validate first — compiles and runs the tests, commits nothing
sf project deploy validate --source-dir force-app \
  --test-level RunSpecifiedTests --tests TierProgressControllerTest \
  --target-org <alias>

# Then commit
sf project deploy start --source-dir force-app \
  --test-level RunSpecifiedTests --tests TierProgressControllerTest \
  --target-org <alias>
```

Omitting the test flags defaults to `NoTestRun` in a sandbox or scratch org.
A validation that skipped tests is **not** eligible for
`sf project deploy quick`, which fails with `CannotQuickDeployError`.

### A deploy is all-or-nothing

If one component fails, the whole transaction rolls back — including the
components that reported success. A run that says `36/37 (97%)` and then
`Status: Failed` has deployed **nothing**. Fix the one failure and redeploy
rather than assuming most of it landed.

### Deploying into an org that holds other source

`manifest/package.xml` lists only this package, so it can go into an org
whose other metadata you would rather not touch:

```bash
sf project deploy start --manifest manifest/package.xml --target-org <alias>
```

Or name the components directly, which also sidesteps any unrelated broken
metadata sitting in the same project directory:

```bash
sf project deploy start \
  --metadata CustomObject:Tier__c --metadata CustomObject:Tier_List_Item__c \
  --metadata ApexClass:TierProgressController \
  --metadata ApexClass:TierProgressControllerTest \
  --metadata LightningComponentBundle:tierProgressRing \
  --metadata CustomTab:Tier__c --metadata CustomTab:Tier_List_Item__c \
  --metadata PermissionSet:Tier_Progress_User \
  --target-org <alias>
```

`CustomObject:` pulls each object's fields, list views and validation rules
with it.

### Post-deploy

```bash
sf org assign permset --name Tier_Progress_User --target-org <alias>
```

The permission set grants both objects, every field, the `TierProgressController`
class and the two tabs. Without it the ring renders its error state.

---

## Seeding demo data

| Script | Portable? | What it creates |
|---|---|---|
| `seed-tier-programs.apex` | **Yes** — matches Accounts by name | Three Accounts, one per programme, 27 requirements |
| `seed-tier-progress.apex` | **Yes** | The Partner example only, if that is all you need |
| `seed-techco-onboarding.apex` | **No** — targets a hard-coded Account id | One Commercial Banking onboarding climb |

```bash
sf apex run --file scripts/apex/seed-tier-programs.apex --target-org <alias>
```

All three are idempotent: Accounts and Tiers are matched and reused, child
items are deleted and reinserted, so re-running after edits leaves no
duplicates.

### What `seed-tier-programs.apex` produces

| Account | Programme | Climb | Ring | Outstanding |
|---|---|---|---|---|
| Meridian Wealth Partners | Brokerage | Producer → Premier Producer | 73.9% | 7 of 9 |
| Coastal Auto Group | Dealer | Preferred → Premier Dealer | 75.0% | 7 of 9 |
| Northwind Treasury | Partner | Gold → Platinum | 55.9% | 7 of 9 |

Coastal Auto Group is seeded `At Risk`, so it exercises the amber status
badge. Its blocker is a chargeback rate of 3.1% against a 2.5% ceiling.

The script prints these figures to the debug log when it finishes, computed
the same way the LWC computes them — so a mismatch between the log and the
rendered ring points at the component, not the data.

### `seed-techco-onboarding.apex`

Targets `ACCOUNT_ID = '001Kh00001yqwmEIAQ'`. Record ids do not travel
between orgs — **change the constant at the top before running it
elsewhere.** It looks the Account up rather than creating one, and stops
with a clear message if the id does not resolve, so a wrong id cannot
quietly seed a tier attached to nothing.

Expected result: **42.5%**, 5 of 8 outstanding — Compliance 62.5%,
Implementation 60%, Integration 0%. The zero is deliberate: none of the
treasury file-transmission work can start before the master agreement is
executed, so the ring shows the blocker rather than burying it.

---

## Running the tests

25 tests covering the weighted maths, category-to-ring grouping, every
record-resolution branch, the outstanding-list copy, hex colour
normalisation, and the programme/level validation rule.

```bash
# As part of a deploy
sf project deploy start --source-dir force-app \
  --test-level RunSpecifiedTests --tests TierProgressControllerTest \
  --target-org <alias>

# Or on their own, once the classes are in the org
sf apex run test --tests TierProgressControllerTest \
  --result-format human --wait 10 --target-org <alias>
```

`sf apex run test` only works **after** a successful deploy. Running it
against an org that has only had a *validation* gives
`INVALID_INPUT: This class name's value is invalid` — the class is not there.

---

## Troubleshooting

### `Validation rule error message cannot be longer than 255 characters`
### `Validation rule description cannot be longer than 255 characters`

Both fields on a `ValidationRule` are capped at 255. Note that a
`CustomField` description allows 1000, so a single limit table across all
metadata types will miss this. Shorten
`Level_Matches_Program.validationRule-meta.xml` and redeploy.

### `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST` running a seed script

Almost always downstream of a failed deploy. The picklist value the script
is setting never landed because something else in the same transaction
failed and rolled everything back. Check the deploy output above it.

### `Didn't understand relationship 'Account' in field path`

`Account__c` is a *custom* lookup, so the parent traversal is `Account__r`,
not `Account`. Applies to `Contact__r` too.

### `Identifier name is reserved: any`

`any` is an Apex reserved word and cannot be a variable name.

### `CannotQuickDeployError`

The validation that produced the job id did not run tests, so it is not
eligible for a quick deploy. Re-validate with `--test-level`, or just run
`sf project deploy start`.

### `InvalidProjectWorkspaceError: ... does not contain a valid Salesforce DX project`

You are not in the directory holding `sfdx-project.json`. `cd` into the
repository root.

### `Missing expression after unary operator '--'` (PowerShell)

A trailing `\` is not a line continuation in PowerShell. Put the command on
one line, or wrap with a backtick `` ` ``.

### `Get-CimInstance : The paging file is too small for this operation`

Not from the deploy. The Salesforce CLI shells out to `Get-CimInstance` for
process detection and Windows refuses because virtual memory is exhausted.
The CLI carries on regardless, so it is noise — but it indicates memory
pressure, and is worth suspecting if a later command dies unexplained.

### Text renders washed out / barely readable

Fixed in this package by using SLDS styling hooks, but worth knowing if you
fork the CSS: `@media (prefers-color-scheme: dark)` follows the *operating
system*, while Lightning Experience renders its own light theme regardless.
On any machine with the OS in dark mode, that combination puts light text on
a white card.

### `Expand-Archive` produces an empty folder (Windows)

PowerShell's `Expand-Archive` has a long-standing habit of skipping
dot-directories such as `.git`, and in some configurations writes nothing at
all under `$HOME`. Use `git clone`, or `tar -xf`, which ships with Windows 10+.

---

## Notes for maintainers

Things that are the way they are for a reason:

- **`Progress_Percent__c` is a Number, not a Percent field.** Percent fields
  are rescaled when referenced from other formulas, which would silently
  break `Weighted_Progress__c`.
- **List views live in `objects/Tier__c/listViews/`**, not inline in the
  object file. Inline works but source tracking then reports
  `returned from org, but not found in the local project` on every retrieve.
- **XML comments cannot contain a double hyphen.** Writing `--source-dir` in
  a comment inside any `-meta.xml` file makes it unparseable.
- **Person Account fields are reached through dynamic SOQL.** A static
  reference to `IsPersonAccount` or `PersonContactId` stops the class
  compiling in orgs without Person Accounts enabled.
- **Empty sets match nothing in SOQL**, which is what makes it safe for
  `findTier` to pass unused id sets through rather than branching per
  caller. Do not "simplify" this to a null comparison — `Field = null`
  matches every row where the field is blank.
- **`RingData.categories`** exists so a merged `Other` arc still filters
  correctly. It is not redundant with `key`.

---

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
- **Reporting** — `Progress_Percent__c` and `Items_Outstanding__c` are real
  fields, so tier progress charts and dashboards need no Apex.

### Known schema caveat

`Tier__c.Items_Outstanding__c` is a COUNT roll-up filtered on the
`Is_Complete__c` formula checkbox. If your org rejects a formula field in
roll-up filter criteria, either drop the filter and subtract from a plain
COUNT, or filter on the raw `Completed__c` checkbox instead — accepting that
partially-met Numeric items then count as outstanding until ticked.

Nothing in the LWC depends on this field; it exists for reporting.

---

## Verification status

Confirmed working in a live org (Salesforce API v67):

- Both custom objects and all 26 fields
- The roll-up summaries, including the formula-checkbox filter on
  `Items_Outstanding__c`
- The `Level_Matches_Program` validation rule
- The weighted arithmetic, matching hand calculation to the decimal
- `seed-tier-programs.apex`, producing the three rings above
- The LWC rendering on an Account record page

Not yet exercised anywhere:

- The 25 Apex tests have never been run against an org
- Contact and `Related_Record_Id__c` resolution have unit tests but no
  live confirmation
- The Person Account branch is untested — it needs an org with Person
  Accounts enabled

---

## Licence

MIT — see [LICENSE](LICENSE).
