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
    Adoption: '#0176d3',
    Engagement: '#2e844a',
    Advocacy: '#9050e9',
    Other: '#fe9339',
    General: '#0176d3'
};
const FALLBACK_COLORS = ['#0176d3', '#2e844a', '#9050e9', '#fe9339'];

/** Single-ring colour when the tier has no categories, keyed on the next tier. */
const TIER_COLORS = {
    Bronze: '#a45c2b',
    Silver: '#7d8b96',
    Gold: '#c4952b',
    Platinum: '#4a7b8c',
    Diamond: '#0d9dda'
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
                swatchStyle: `background-color: ${color};`
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
        const { itemsComplete = 0, itemsTotal = 0, accountName } = this.progress;
        const base = `${itemsComplete} of ${itemsTotal} requirements complete`;
        return accountName ? `${accountName} · ${base}` : base;
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

    get visibleOutstanding() {
        const limit = Number(this.maxOutstanding) || 0;
        const items =
            limit > 0 ? this.outstandingItems.slice(0, limit) : this.outstandingItems;

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
        const count = this.outstandingItems.length;
        if (count === 0) return 'Outstanding';
        return count === 1 ? '1 requirement outstanding' : `${count} requirements outstanding`;
    }

    get hiddenOutstandingLabel() {
        const limit = Number(this.maxOutstanding) || 0;
        const hidden = limit > 0 ? this.outstandingItems.length - limit : 0;
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
