---
name: RentLedger Mobile
colors:
  surface: '#f8f9ff'
  surface-dim: '#cbdbf5'
  surface-bright: '#f8f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#eff4ff'
  surface-container: '#e5eeff'
  surface-container-high: '#dce9ff'
  surface-container-highest: '#d3e4fe'
  on-surface: '#0b1c30'
  on-surface-variant: '#3d4a42'
  inverse-surface: '#213145'
  inverse-on-surface: '#eaf1ff'
  outline: '#6d7a72'
  outline-variant: '#bccac0'
  surface-tint: '#006c4a'
  primary: '#006948'
  on-primary: '#ffffff'
  primary-container: '#00855d'
  on-primary-container: '#f5fff7'
  inverse-primary: '#68dba9'
  secondary: '#565e74'
  on-secondary: '#ffffff'
  secondary-container: '#dae2fd'
  on-secondary-container: '#5c647a'
  tertiary: '#825100'
  on-tertiary: '#ffffff'
  tertiary-container: '#a36700'
  on-tertiary-container: '#fffbff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#85f8c4'
  primary-fixed-dim: '#68dba9'
  on-primary-fixed: '#002114'
  on-primary-fixed-variant: '#005137'
  secondary-fixed: '#dae2fd'
  secondary-fixed-dim: '#bec6e0'
  on-secondary-fixed: '#131b2e'
  on-secondary-fixed-variant: '#3f465c'
  tertiary-fixed: '#ffddb8'
  tertiary-fixed-dim: '#ffb95f'
  on-tertiary-fixed: '#2a1700'
  on-tertiary-fixed-variant: '#653e00'
  background: '#f8f9ff'
  on-background: '#0b1c30'
  surface-variant: '#d3e4fe'
typography:
  headline-xl:
    fontFamily: Plus Jakarta Sans
    fontSize: 36px
    fontWeight: '800'
    lineHeight: 44px
    letterSpacing: -0.03em
  headline-xl-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 28px
    fontWeight: '800'
    lineHeight: 34px
    letterSpacing: -0.025em
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 30px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 20px
    fontWeight: '700'
    lineHeight: 26px
    letterSpacing: -0.015em
  headline-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '600'
    lineHeight: 22px
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: -0.005em
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0em
  body-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0.005em
  label-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 18px
    letterSpacing: 0.01em
  label-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 10px
    fontWeight: '700'
    lineHeight: 12px
    letterSpacing: 0.04em
  data-metric:
    fontFamily: Plus Jakarta Sans
    fontSize: 22px
    fontWeight: '800'
    lineHeight: 26px
    letterSpacing: -0.02em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

The design system establishes a high-precision, executive-grade operational environment tailored for high-capital equipment rental managers, logistics coordinators, and inventory operators. The brand embodies trust, absolute fiscal clarity, and field-tested reliability. It rejects toy-like consumer aesthetics in favor of a modern corporate aesthetic fused with tactile micro-depth: structural slate surfaces, surgically precise micro-borders, and high-visibility status telemetry.

The UI elicits an immediate sense of control, audit-readiness, and operational momentum. Typography and data presentation prioritize zero-latency scanning under varying field lighting conditions, while interactive surfaces employ subtle tactile shifts that reassure the user across rental dispatch, return intake, deposit verification, and asset tracking workflows.

## Colors

The palette leverages a foundational deep slate hierarchy to frame vibrant, meaning-driven status tokens.

- **Primary (`#059669` / `#10B981` Emerald Mint & Vibrant Teal):** Signifies financial security, cleared deposits, active healthy contracts, and primary system confirmation. Used for primary CTAs, validated ledger states, and liquidity indicators.
- **Secondary (`#0F172A` / `#1E293B` Deep Slate Navy & Charcoal):** Provides structural authority. Applied to navigation headers, high-contrast parent framing, primary typography, and persistent bottom bars.
- **Tertiary (`#F59E0B` / `#D97706` Amber):** Serves as an operational alert for pending handovers, overdue return schedules, and conditional deposit holds.
- **Neutrals (`#F8FAFC`, `#FFFFFF`, `#F1F5F9`, `#E2E8F0`, `#64748B`):** Form crisp, layered card architecture, structural micro-borders, and secondary metric labels.
- **Semantic Error (`#EF4444`):** Reserved strictly for damaged asset reporting, failed payments, and breach of rental terms.

## Typography

Plus Jakarta Sans is utilized across all typographic levels to unite contemporary geometric curves with high-legibility tabular forms essential for serial numbers, daily rental rates, and currency values.

- **Headlines:** Set tightly tracked with heavier weights (`700` and `800`) to anchor dense dashboards and status overviews.
- **Numbers & Metrics:** Large currency quantities and stock counts utilize `data-metric` or `headline-lg` with tabular lining figures enabled by default to prevent vertical layout jitter during live updates.
- **Labels & Badges:** Uppercase and title-case labels use increased letter spacing (`0.02em` to `0.04em`) to preserve legibility at micro sizes on inventory condition tags.

## Layout & Spacing

The layout is built upon an 8pt-rooted rhythm with 4pt baseline snap for high-density components.

- **Mobile Viewport (default):** A 4-column fluid layout with a mandatory `margin` of `1rem` (16px) and an inner column `gutter` of `0.75rem` (12px). Outer margins ensure comfortable one-handed edge reach on handheld devices.
- **Tablet & Split-Screen:** Shifts to an 8-column layout with `margin: 1.5rem` and `gutter: 1rem` for dual-pane list-detail workflows (e.g., equipment catalog on the left, booking ledger on the right).
- **Component Padding Scale:**
  - `space-xs` (4px): Inner badge padding, icon-to-text micro gaps.
  - `space-sm` (8px): Stack gap inside inventory list rows, horizontal button padding for compact items.
  - `space-md` (16px): Card internal padding, form input field heights, layout separators.
  - `space-lg` (24px): Metric block separation, modal header padding.
  - `space-xl` (32px): Terminal screen bottoms, safe area offsets above fixed navigation bars.

## Elevation & Depth

Visual hierarchy combines low-contrast micro-borders with focused ambient shadows rather than harsh drop-shadows.

- **Level 0 (Canvas Base):** Background color `#F8FAFC`. Zero elevation, zero shadow.
- **Level 1 (Cards, Metric Surfaces, List Rows):** Pure white background (`#FFFFFF`), bounded by a subtle `1px` border of `#E2E8F0`. Shadow: `0 1px 3px 0 rgba(15, 23, 42, 0.04), 0 1px 2px -1px rgba(15, 23, 42, 0.02)`.
- **Level 2 (Dropdowns, Segmented Popovers):** Background `#FFFFFF`, border `1px` solid `#CBD5E1`. Shadow: `0 4px 6px -1px rgba(15, 23, 42, 0.08), 0 2px 4px -2px rgba(15, 23, 42, 0.04)`.
- **Level 3 (Tactile FAB, Drawers, Modals):** Primary FAB in `#059669` or `#0F172A`. Elevated via an ambient tinted shadow: `0 10px 15px -3px rgba(5, 150, 105, 0.25), 0 4px 6px -4px rgba(5, 150, 105, 0.2)`. Modals use `#0F172A` at 40% alpha backdrop blur.
- **Micro-Border Rule:** No card or elevated element exists without a structural `1px` border to safeguard legibility against bright direct sunlight.

## Shapes

The design system employs a roundedness level of `2`, yielding controlled, modern architectural silhouettes.

- **Cards & Data Panels:** Default radius of `0.75rem` (12px) to `1rem` (16px) (`rounded-lg`), delivering a clean frame for complex data without excessive bubble curvature.
- **Input Fields & Action Controls:** Standardized to `0.5rem` (8px) (`rounded-md`) for immediate tap affordance and alignment with keyboard layouts.
- **Status Badges & Pill Chips:** Full pill radius (`9999px`) to immediately distinguish analytical state metadata from clickable card containers.
- **Floating Action Buttons (FAB):** Spherical circle or high-radius capsule (`9999px`) to emphasize spontaneous global actions (e.g., "Scan QR Asset", "New Rental Agreement").

## Components

### Buttons
- **Primary:** Filled emerald (`#059669`), hover/pressed state `#047857`, label `#FFFFFF` in `label-lg`. Micro-shadow with emerald tint. Height 48px for finger-first targets.
- **Secondary:** Deep slate navy (`#0F172A`), pressed `#1E293B`, label `#FFFFFF`. Used for document exports, status transitions, and check-in closures.
- **Outline / Ghost:** Background transparent, border `1px` solid `#E2E8F0`, label `#1E293B`. Pressed background `#F1F5F9`.

### Chips & Pill Badges
- **Status Badges:** Compact capsule shape (`padding: 2px 8px`).
  - *Active / Paid:* Emerald tint (`#ECFDF5`), text `#065F46`, border `1px` solid `#A7F3D0`.
  - *Pending / Overdue Return:* Amber tint (`#FFFBEB`), text `#92400E`, border `1px` solid `#FDE68A`.
  - *In Maintenance / Reserved:* Slate tint (`#F1F5F9`), text `#334155`, border `1px` solid `#CBD5E1`.
- **Filter Chips:** Height 32px, border `1px` solid `#E2E8F0`, surface `#FFFFFF`. When selected: surface `#0F172A`, text `#FFFFFF`, border `#0F172A`.

### Lists & Inventory Rows
- Each row uses a clean `#FFFFFF` container or separated `#F8FAFC` dividers, featuring an asset thumbnail (rounded-md), serial code, title in `headline-sm`, and right-aligned rental price per day. Swipe actions reveal check-out/check-in quick toggles.

### Inputs & Form Fields
- Height 48px, background `#FFFFFF`, border `1px` solid `#CBD5E1`, text `#0F172A` with `#94A3B8` placeholder. Focused state introduces a crisp `2px` ring in `#059669` and border `#059669`. Label in `label-md` seated above the input.

### Checkboxes & Radios
- Size 20x20px with `rounded` (4px) for checkboxes and circle for radios. Active fill in `#059669` with white check/dot icon. Inactive border `1.5px` solid `#94A3B8`.

### Financial Metric Cards
- Surface `#FFFFFF`, border `1px` solid `#E2E8F0`, padding `1rem`. Top metadata row displays the metric label (`label-md`) and an indicator icon. Central display uses `data-metric` in deep slate navy (`#0F172A`), flanked by a micro-pill indicating percentage change or deposit totals.

### Sleek Bottom Navigation Bar
- Grounded in high-density surface `#0F172A` or pure `#FFFFFF` with top border `1px` solid `#E2E8F0`. 64px height with safe area inset. Active tab uses `#059669` glyph and 4px indicator pill; inactive tab uses `#64748B`.