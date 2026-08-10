import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getTierProgress from '@salesforce/apex/TierProgressController.getTierProgress';

/**
 * Ring geometry, in the 200x200 user space of the SVG viewBox.
 * OUTER_RADIUS + STROKE_WIDTH / 2 has to stay under 100 or the outermost
 * arc gets clipped by the viewBox edge.
 */
const OUTER_RADIUS = 86;
const RING_PITCH = 21;
const STROKE_WIDTH = 15;

/** Colours for the concentric category arcs, outermost first. */
const CATEGORY_COLORS = {
    // Partner ladder
    Adoption: '#0176d3',
    Engagement: '#2e844a',
    Advocacy: '#9050e9',
    // Brokerage and Dealer ladders. Deliberately the same three hues in the
    // same order — a tier only ever uses one family, so reusing them keeps
    // the outermost arc reading as "the big one" whichever programme it is.
    Production: '#0176d3',
    Compliance: '#2e844a',
    Relationship: '#9050e9',
    // Commercial Banking ladder reuses Compliance, so its own two follow on
    Implementation: '#0176d3',
    Integration: '#9050e9',
    Other: '#fe9339',
    General: '#0176d3'
};
const FALLBACK_COLORS = ['#0176d3', '#2e844a', '#9050e9', '#fe9339'];

/** Single-ring colour when the tier has no categories, keyed on the next tier. */
const TIER_COLORS = {
    // Partner
    Bronze: '#a45c2b',
    Silver: '#7d8b96',
    Gold: '#c4952b',
    Platinum: '#4a7b8c',
    Diamond: '#0d9dda',
    // Brokerage — producer recognition levels, cool through to gold
    'Registered Rep': '#7d8b96',
    Producer: '#0176d3',
    'Premier Producer': '#5867e8',
    "President's Council": '#9050e9',
    "Chairman's Circle": '#c4952b',
    // Dealer — indirect lending statuses, same climb
    'Approved Dealer': '#7d8b96',
    'Preferred Dealer': '#2e844a',
    'Premier Dealer': '#0176d3',
    'Elite Dealer': '#9050e9',
    "President's Club": '#c4952b',
    // Commercial Banking - treasury onboarding stages
    Applicant: '#7d8b96',
    Onboarding: '#0176d3',
    'Treasury Live': '#2e844a'
};
const DEFAULT_TIER_COLOR = '#0176d3';

export default class TierProgressRing extends LightningElement {
    @api recordId;

    /** App Builder configuration. */
    @api cardTitle;
    @api hideOutstanding = false;
    @api maxOutstanding = 0;

    progress;
    errorMessage = '';
    isLoading = true;

    // Arcs are drawn empty on the first paint and filled on the next frame,
    // so the CSS transition on stroke-dashoffset has something to animate
    // from. Without this the ring simply appears at its final value.
    animate = false;

    /** Category currently filtering the outstanding list, or '' for none. */
    activeCategory = '';

    _wiredResult;
    _animationQueued = false;

    @wire(getTierProgress, { recordId: '$recordId' })
    wiredProgress(result) {
        this._wiredResult = result;
        const { data, error } = result;

        if (data !== undefined || error) {
            this.isLoading = false;
        }
        if (error) {
            this.progress = undefined;
            this.errorMessage = this.extractError(error);
            return;
        }
        if (data !== undefined) {
            this.progress = data === null ? undefined : data;
            this.errorMessage = '';
            this.activeCategory = '';
            // Replay the sweep whenever fresh numbers arrive.
            this.animate = false;
            this._animationQueued = false;
        }
    }

    renderedCallback() {
        if (this._animationQueued || this.animate || !this.progress) {
            return;
        }
        this._animationQueued = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            this.animate = true;
        });
    }

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------

    get isEmpty() {
        return !this.progress;
    }

    get resolvedTitle() {
        return this.cardTitle || 'Tier Progress';
    }

    get showStatusBadge() {
        return Boolean(this.progress && this.progress.status);
    }

    get statusBadgeClass() {
        const status = this.progress && this.progress.status;
        if (status === 'Achieved') return 'slds-theme_success';
        if (status === 'At Risk') return 'slds-theme_warning';
        return '';
    }

    // ------------------------------------------------------------------
    // Ring geometry
    // ------------------------------------------------------------------

    get displayRings() {
        const rings = (this.progress && this.progress.rings) || [];
        return rings.map((ring, index) => {
            const radius = OUTER_RADIUS - index * RING_PITCH;
            const circumference = 2 * Math.PI * radius;
            const actual = this.clampPercent(ring.percent);
            const drawn = this.animate ? actual : 0;
            const color = this.colorForRing(ring.key, index);

            // Dim the arcs that are not the active filter, so the ring
            // itself shows what the list below is scoped to.
            const isActive = this.activeCategory !== '' && this.coversActive(ring);
            const dimmed = this.activeCategory !== '' && !isActive;

            return {
                key: ring.key,
                trackKey: `${ring.key}-track`,
                label: ring.label,
                color,
                radius,
                strokeWidth: STROKE_WIDTH,
                circumference: circumference.toFixed(2),
                dashOffset: (circumference * (1 - drawn / 100)).toFixed(2),
                percentLabel: `${Math.round(actual)}%`,
                countLabel: `${ring.itemsComplete} of ${ring.itemsTotal} done`,
                swatchStyle: `background-color: ${color};`,
                arcStyle: dimmed ? 'opacity: 0.25;' : '',
                isActive,
                legendClass: isActive ? 'legend__row legend__row_active' : 'legend__row',
                filterHint: isActive
                    ? `Showing ${ring.label} only. Click to show everything.`
                    : `Show only ${ring.label} requirements`
            };
        });
    }

    colorForRing(key, index) {
        // A tier with no categories draws one arc, coloured for the tier
        // being chased — that is the headline number, so it gets the
        // headline colour.
        if (key === 'overall') {
            return (
                (this.progress && this.progress.ringColor) ||
                TIER_COLORS[this.progress && this.progress.nextTier] ||
                DEFAULT_TIER_COLOR
            );
        }
        return (
            CATEGORY_COLORS[key] || FALLBACK_COLORS[index % FALLBACK_COLORS.length]
        );
    }

    get showLegend() {
        const rings = (this.progress && this.progress.rings) || [];
        return rings.length > 1;
    }

    get percentLabel() {
        return `${Math.round(this.clampPercent(this.progress && this.progress.percentComplete))}%`;
    }

    get ringAriaLabel() {
        if (!this.progress) return 'Tier progress';
        const pct = Math.round(this.clampPercent(this.progress.percentComplete));
        const target = this.progress.nextTier || 'the next tier';
        return `${pct} percent of the way to ${target}. ${this.completionSummary}`;
    }

    // ------------------------------------------------------------------
    // Header copy
    // ------------------------------------------------------------------

    get currentTierLabel() {
        return (this.progress && this.progress.currentTier) || 'Unranked';
    }

    get nextTierLabel() {
        return (this.progress && this.progress.nextTier) || 'Next tier';
    }

    get completionSummary() {
        if (!this.progress) return '';
        const { itemsComplete = 0, itemsTotal = 0, subjectName } = this.progress;
        const base = `${itemsComplete} of ${itemsTotal} requirements complete`;
        return subjectName ? `${subjectName} · ${base}` : base;
    }

    get targetDateLabel() {
        const raw = this.progress && this.progress.targetDate;
        if (!raw) return '';
        // Apex Date arrives as a plain yyyy-mm-dd string with no zone. Split
        // it rather than letting Date parse it as UTC midnight, which shifts
        // the day backwards for anyone west of Greenwich.
        const [year, month, day] = raw.split('-').map(Number);
        if (!year || !month || !day) return '';
        return new Date(year, month - 1, day).toLocaleDateString(undefined, {
            year: 'numeric',
            month: 'short',
            day: 'numeric'
        });
    }

    // ------------------------------------------------------------------
    // Outstanding list
    // ------------------------------------------------------------------

    get showOutstanding() {
        return !this.hideOutstanding;
    }

    get outstandingItems() {
        return (this.progress && this.progress.outstanding) || [];
    }

    get hasOutstanding() {
        return this.outstandingItems.length > 0;
    }

    /** Categories folded into a ring — usually one, more for a merged arc. */
    categoriesFor(ringKey) {
        const ring = ((this.progress && this.progress.rings) || []).find(
            (r) => r.key === ringKey
        );
        return (ring && ring.categories) || [];
    }

    coversActive(ring) {
        return (ring.categories || []).includes(this.activeCategory);
    }

    get filteredOutstanding() {
        if (!this.activeCategory) return this.outstandingItems;
        return this.outstandingItems.filter(
            (item) => item.category === this.activeCategory
        );
    }

    get hasVisibleOutstanding() {
        return this.visibleOutstanding.length > 0;
    }

    get visibleOutstanding() {
        const limit = Number(this.maxOutstanding) || 0;
        const source = this.filteredOutstanding;
        const items = limit > 0 ? source.slice(0, limit) : source;

        return items.map((item) => {
            const pct = this.clampPercent(item.percent);
            const color = this.colorForCategory(item.category);
            return {
                ...item,
                percentLabel: `${Math.round(pct)}%`,
                ariaValue: Math.round(pct),
                barStyle: `width: ${pct}%; background-color: ${color};`,
                chipStyle: `border-color: ${color}; color: ${color};`
            };
        });
    }

    colorForCategory(category) {
        if (!category) return DEFAULT_TIER_COLOR;
        if (CATEGORY_COLORS[category]) return CATEGORY_COLORS[category];
        const rings = (this.progress && this.progress.rings) || [];
        const index = rings.findIndex((ring) => ring.key === category);
        return FALLBACK_COLORS[(index < 0 ? 0 : index) % FALLBACK_COLORS.length];
    }

    get outstandingHeading() {
        const count = this.filteredOutstanding.length;
        const scope = this.activeCategory ? `${this.activeCategory} ` : '';
        if (count === 0) return this.activeCategory ? `${this.activeCategory} — all done` : 'Outstanding';
        return count === 1
            ? `1 ${scope}requirement outstanding`
            : `${count} ${scope}requirements outstanding`;
    }

    get hiddenOutstandingLabel() {
        const limit = Number(this.maxOutstanding) || 0;
        const hidden = limit > 0 ? this.filteredOutstanding.length - limit : 0;
        if (hidden <= 0) return '';
        return hidden === 1 ? '1 more not shown' : `${hidden} more not shown`;
    }

    get allClearMessage() {
        const next = this.progress && this.progress.nextTier;
        return next
            ? `Everything is done — ${next} is unlocked.`
            : 'Everything is done.';
    }

    // ------------------------------------------------------------------
    // Actions
    // ------------------------------------------------------------------

    /**
     * Toggles the filter. Fired by both the arcs and the legend rows, so the
     * two stay in step. An 'overall' ring covers everything, so it has
     * nothing to filter down to.
     */
    handleRingClick(event) {
        const key = event.currentTarget.dataset.category;
        if (!key || key === 'overall') return;

        const categories = this.categoriesFor(key);
        if (!categories.length) return;

        // A merged "Other" arc covers several categories; filtering picks the
        // first, which is the only one a single click can mean unambiguously.
        const target = categories[0];
        this.activeCategory = this.activeCategory === target ? '' : target;
    }

    handleClearFilter() {
        this.activeCategory = '';
    }

    handleRefresh() {
        if (!this._wiredResult) return;
        this.isLoading = true;
        refreshApex(this._wiredResult).finally(() => {
            this.isLoading = false;
        });
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    clampPercent(value) {
        const num = Number(value);
        if (!Number.isFinite(num)) return 0;
        return Math.min(100, Math.max(0, num));
    }

    extractError(err) {
        if (!err) return 'Unknown error';
        if (typeof err === 'string') return err;
        if (err.body && err.body.message) return err.body.message;
        if (Array.isArray(err.body) && err.body.length && err.body[0].message) {
            return err.body[0].message;
        }
        if (err.message) return err.message;
        return 'Could not load tier progress.';
    }
}
