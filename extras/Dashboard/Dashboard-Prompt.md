# Koyson Sales Dashboard — Complete Build Prompt

## Role

You are an expert frontend engineer, UI/UX designer, data-visualization engineer, and Zoho Books integration specialist.

Build a **production-quality Koyson Sales Dashboard** inspired by the supplied dashboard reference and designed to work with **Zoho Books** data.

The result should feel like a polished modern analytics application rather than a generic admin dashboard.

---

# 1. Core Objective

Create a highly visual, interactive sales analytics dashboard for Koyson.

The dashboard must allow users to:

- Understand overall sales performance immediately.
- Filter sales data globally.
- Analyze revenue by brand, customer, product, invoice status, salesperson/POC, and credit period.
- Drill down from summary metrics into detailed records.
- Analyze monthly trends.
- Compare periods.
- Analyze average selling price (ASP) trends by product/SKU.
- Export dashboard data.
- Upload source data when required.
- Work smoothly with real Zoho Books data.

The visual hierarchy and information architecture should follow the supplied **Koyson Sales Dashboard** reference as closely as practical.

---

# 2. Technology Constraint

## Frontend

Use ONLY:

- HTML
- CSS
- Vanilla JavaScript

Do **not** use:

- React
- Vue
- Angular
- Flutter
- Dart
- Next.js
- Nuxt
- Svelte
- Any frontend framework

The implementation should be framework-free and easy to host as a static web application.

A charting library may be used if it is loaded appropriately, but the application architecture itself must remain plain HTML/CSS/JavaScript.

Prefer lightweight dependencies.

---

# 3. Important Zoho Books Integration Rule

The dashboard is intended to consume Zoho Books data.

Use Zoho Books APIs for production integration where appropriate.

Relevant Zoho Books entities include:

- Invoices
- Invoice line items
- Customers/Contacts
- Items
- Categories
- Salespersons/POCs
- Payments/credits where required

The invoice data should support fields such as:

- Invoice number
- Customer
- Invoice date
- Due date
- Status
- Payment terms
- Salesperson
- Line items
- Quantity
- Rate
- Discount
- Tax
- Subtotal
- Total
- Payment made
- Credits applied
- Balance
- Exchange rate
- Location
- Custom fields
- Tags

Items/products should support:

- Item name
- SKU
- Brand
- Manufacturer
- Category
- Description
- Rate
- Unit
- Product type
- Status

Categories should support hierarchical product categorization.

## Security

Never expose a Zoho OAuth client secret or other confidential credentials in browser JavaScript.

If authentication/token exchange requires a backend or Zoho-hosted integration layer, keep secrets server-side.

The frontend should consume only the data it is authorized to access.

---

# 4. Dashboard Identity

Use the following branding:

**Koyson Sales Dashboard**

Primary reporting period:

**FY26-27**

Primary currency:

**AED**

Allow the dashboard to support an alternate INR presentation where applicable.

The UI should feel premium, clean, analytical, and business-focused.

Avoid making it look like a generic template.

---

# 5. Overall Layout

Create a responsive application layout with:

1. Left navigation/sidebar
2. Main dashboard content
3. Top header
4. Global filter area
5. KPI section
6. Analytics/chart sections
7. Detailed tables
8. Drill-down areas
9. Export/data controls

Desktop should be the primary experience.

Tablet and mobile must remain usable.

---

# 6. Header

Create a strong top-level header containing:

- Koyson Sales Dashboard title
- Fiscal year indicator
- Current data/source indicator
- Currency selector
- Upload File control
- Theme/color control
- Refresh control
- Download All control

Example source label:

`invoice_clean.xlsx`

Example period:

`FY26-27`

Currency options:

- AED
- INR

---

# 7. Global Filters

Provide a visually prominent filter bar.

Required filters:

### Invoice Status

Options:

- All
- Open
- Overdue
- Partially Paid
- Closed

### Brand

Options:

- All
- Nellon
- Raviya
- Non-Branded

### FY

Options:

- FY25-26
- FY26-27

### Period

Options:

- Full FY
- Q1
- Q2
- Q3
- Q4

### Month

For FY26-27, include:

- Apr 2026
- May 2026
- Jun 2026
- Jul 2026

The implementation should be designed so future months can be added dynamically.

### Period Comparison

Include:

`Compare Period on Period`

This should allow users to compare the selected period against an appropriate previous period.

### Controls

Include:

- Clear filters
- Apply filters
- Filter state indicator
- Optional filter summary

Filters should update all dependent dashboard components consistently.

Do not reload the entire page unnecessarily.

---

# 8. KPI Section

Create prominent KPI cards.

Required KPIs:

1. Net Revenue
2. Invoices
3. Active Customers
4. Avg Order Value
5. Avg Credit Period

Each KPI card should support:

- Main value
- Label
- Optional comparison value
- Percentage change
- Trend indicator
- Context/period label

Use strong typography and excellent number formatting.

Large monetary values should be abbreviated intelligently where appropriate.

Examples:

- AED 6.88M
- AED 2.57M
- 1,284
- 412

---

# 9. Brand Summary Cards

Create brand-level summary cards for:

### Nellon

Reference values:

- Revenue: AED 3.52M
- Revenue share: 51.2%

### Non-Branded

Reference values:

- Revenue: AED 2.57M
- Revenue share: 37.4%

### Raviya

Reference values:

- Revenue: AED 783.3K
- Revenue share: 11.4%

Where useful, show:

- Revenue
- % revenue
- Invoice count
- Line items
- AOV

These are reference values from the supplied dashboard and should be treated as sample/reference presentation data unless the live source produces different values.

---

# 10. Revenue Trend

Create a large revenue trend visualization.

Requirements:

- Monthly timeline
- Stacked revenue by brand
- Revenue values
- Line-items count overlay
- Hover tooltips
- Legend
- Smooth animation
- Responsive resizing

Brand series:

- Nellon
- Non-Branded
- Raviya

The chart should make it easy to understand:

- Growth
- Decline
- Brand contribution
- Monthly seasonality
- Volume vs revenue

Do not overload the chart with unnecessary visual elements.

---

# 11. Month Snapshot

Create a dedicated **Month Snapshot** area covering:

- Apr 2026
- May 2026
- Jun 2026
- Jul 2026

Include:

- Revenue
- Invoice count
- Revenue by brand
- Revenue by invoice status
- Weekly activity
- Top customers
- Top categories
- Credit category breakdown
- POC breakdown

The user should be able to switch between months without rebuilding the entire dashboard.

---

# 12. Revenue by Brand

Create a visual breakdown of revenue by brand.

Reference distribution:

| Brand | Revenue | Share |
|---|---:|---:|
| Nellon | AED 3.52M | 51.2% |
| Non-Branded | AED 2.57M | 37.4% |
| Raviya | AED 783.3K | 11.4% |

Show:

- Donut/pie visualization
- Revenue
- Percentage
- Invoice count
- Line items
- AOV

Hovering or selecting a brand should highlight related dashboard data.

---

# 13. Revenue by Invoice Status

Show revenue distribution by invoice status.

Reference values:

| Status | Revenue |
|---|---:|
| Open | AED 1.49M |
| Overdue | AED 3.00M |
| Partially Paid | AED 70.4K |
| Closed | AED 2.31M |

The visualization should make overdue revenue immediately visible.

Allow status selection to affect relevant dashboard components.

---

# 14. Weekly Activity

Create a weekly sales activity visualization.

Show:

- Revenue
- Invoice count
- Line-item activity where available

Support:

- Hover details
- Date/week labels
- Smooth transitions
- Responsive layout

---

# 15. Top Customers

Create a customer analytics section.

Requirements:

- Top 10 customers initially
- Expandable list/table
- Search
- Customer ranking
- Revenue
- Revenue %
- Invoice count
- Line items
- AOV
- Optional average credit period

Clicking a customer should open a drill-down experience.

Possible drill-down:

- Side drawer
- Detail panel
- Expandable row

Show customer-level invoice/product information without forcing a full page reload.

---

# 16. Top Categories

Create a ranked product-category analysis.

Show:

- Category
- Revenue
- Revenue %
- Quantity
- Line items
- Average line value

Support search/filtering.

---

# 17. Credit Category Breakdown

Create a credit-period analysis.

Reference values:

| Credit Category | Revenue | Share |
|---|---:|---:|
| Cash | AED 4.26M | 61.9% |
| 8–30 days | AED 119.1K | 1.7% |
| 31–60 days | AED 1.71M | 24.8% |
| 61–90 days | AED 790.3K | 11.5% |

Display this as a clean analytical visualization and/or table.

Use credit categories consistently across the dashboard.

---

# 18. POC / Salesperson Breakdown

Create a salesperson/POC performance table.

Columns:

- POC
- Revenue
- % Revenue
- Invoices
- Line Items
- AOV
- AOQ
- Avg Credit Period

Allow:

- Sorting
- Search
- Row selection
- Drill-down

---

# 19. Product Breakdown

Create a detailed product analysis table.

Required controls:

- Search product
- Category filter
- Optional brand filter

Required columns:

- Product
- Category
- Sub Category
- Sub Category 2
- Revenue
- % Revenue
- Line Items
- Quantity
- Avg Line Value
- Top Brand

The table should support:

- Sorting
- Pagination or virtualization where necessary
- Search
- Row expansion
- Product drill-down

---

# 20. Customer × Product Matrix

Create a heatmap-style matrix.

Structure:

- Top 10 master customers as rows
- Top 8 categories/products as columns
- Revenue intensity in each cell

Requirements:

- Heatmap intensity
- Exact value tooltip
- Row hover
- Column hover
- Selected cell state
- Responsive horizontal scrolling when necessary

Below the matrix, show a credit-period breakdown.

The matrix should be highly readable and should not rely solely on color to communicate values.

---

# 21. Credit Period Breakdown

Provide another analytical view showing customer/transaction credit-period behavior.

Use categories such as:

- Cash
- 8–30 days
- 31–60 days
- 61–90 days

Where appropriate, show:

- Revenue
- Invoice count
- Average credit period
- Customer count

---

# 22. ASP Trend

Create an **Average Selling Price (ASP) Trend by Product** section.

Requirements:

- Monthly ASP trend
- Product/category selection
- Category filter
- SKU search
- Multi-select SKU capability
- Select All
- Deselect All

Category options should include:

- All
- Beverages & Dairy
- Cooking Oil & Ghee
- Dry Fruits & Nuts
- Flour & Milling Products
- Meat & Poultry (Frozen)
- Packaging & Consumables
- Pulses & Legumes
- Rice & Grains
- Sauces/Pickles/Condiments
- Snacks
- Spices & Seasonings
- Sugar & Sweeteners
- Uncategorised

The reference dashboard indicates many SKUs may exist, so do not attempt to display hundreds of chips at once.

Use:

`383 more SKUs not shown`

or dynamically calculate the hidden count.

ASP lines should be visually distinguishable and should animate smoothly when SKUs are added or removed.

---

# 23. Recent Invoices / Detailed Data

Include a detailed invoice table where useful.

Possible columns:

- Invoice number
- Customer
- Date
- Due date
- Status
- Salesperson
- Revenue
- Payment made
- Credits applied
- Balance

Support:

- Search
- Sorting
- Status filtering
- Customer filtering
- Drill-down

---

# 24. Data Architecture

Separate the application into logical layers even though the implementation uses vanilla JavaScript.

Suggested structure:

```text
/index.html

/css/
  variables.css
  base.css
  layout.css
  components.css
  dashboard.css
  responsive.css
  animations.css

/js/
  app.js
  state.js
  filters.js
  formatters.js
  data-service.js
  zoho-service.js
  calculations.js
  charts.js
  tables.js
  drilldown.js
  export.js
  animations.js
```

This is a suggested structure, not a requirement to create every file if a simpler architecture is cleaner.

The important requirement is separation of concerns.

---

# 25. State Management

Use a centralized JavaScript state object.

State should include things such as:

- Raw data
- Filtered data
- Selected FY
- Selected period
- Selected month
- Selected brand
- Selected invoice status
- Currency
- Comparison mode
- Search terms
- Selected customer
- Selected product
- Selected category
- Selected SKUs

Changing state should trigger only the components that actually need updating.

Avoid unnecessary full-dashboard re-renders.

---

# 26. Data Processing

Create reusable calculation functions for:

- Net revenue
- Revenue by brand
- Revenue by status
- Invoice count
- Active customers
- AOV
- Average credit period
- Revenue by category
- Revenue by POC
- Revenue by customer
- Quantity
- Line-item count
- ASP
- Period comparison
- Credit-category distribution

Keep calculations independent from DOM rendering.

---

# 27. Number Formatting

Create consistent formatters.

Examples:

- AED 6,879,432
- AED 6.88M
- AED 783.3K
- 1,284
- 51.2%

Use appropriate precision based on metric type.

Do not show unnecessary decimal places.

---

# 28. Animation & Motion System

Animation is an important part of the experience.

The dashboard should feel alive, but **not gimmicky**.

Motion must communicate:

- State changes
- Data changes
- Hierarchy
- Interaction
- Continuity

Do not add animation merely because animation is possible.

---

## 28.1 Motion Principles

Use:

- Fast, subtle, purposeful motion
- Mostly 200–300ms UI transitions
- Smooth easing
- Opacity + transform for most UI movement
- Localized transitions rather than full-page rebuilds

Avoid:

- Excessive bouncing
- Constant pulsing
- Large dramatic movement
- Animation on every tiny element
- Layout-jitter
- Long blocking animations

Default easing:

- `ease-out`
- `ease-in-out`

Do not use bounce as the default motion curve.

---

# 29. Dashboard Entry Animation

When the dashboard first loads:

Animate sections in a deliberate hierarchy.

Suggested sequence:

1. Header
2. Global filters
3. Snapshot controls
4. KPI cards
5. Charts
6. Tables
7. Lower analytics sections

Use:

- Fade
- Small vertical translate
- Subtle stagger

Suggested stagger:

`40–80ms`

Do not make the user wait for the dashboard to become usable.

---

# 30. KPI Animations

KPI numbers should animate from an initial state toward their final values.

Use count-up animations around:

`600–900ms`

Requirements:

- No layout jitter
- Preserve text width where possible
- Animate only when meaningful
- Re-run when filters materially change the KPI

Trend arrows can use subtle opacity/transform changes.

---

# 31. Filter Animations

When filters change:

- Animate the active filter indicator.
- Transition the affected values smoothly.
- Do not blank the entire dashboard.
- Avoid rebuilding every component if only some components changed.
- Use localized loading/skeleton states where data retrieval is asynchronous.

The user should feel that the dashboard is transforming rather than disappearing and reappearing.

---

# 32. Chart Animations

Use chart-specific motion.

### Bar charts

Bars should grow into place.

### Line charts

Lines should draw smoothly.

### Donuts

Donut segments should sweep into position.

### Data updates

When changing filters:

- Prefer smooth transitions.
- Preserve continuity where interpolation is meaningful.
- Use a short crossfade if direct interpolation could visually mislead.

Suggested visualization animation range:

`500–900ms`

Do not restart every chart unnecessarily.

---

# 33. Donut / Segment Interaction

For donut/pie charts:

On hover:

- Slightly emphasize the segment.
- Show tooltip.
- Keep the rest of the chart stable.

On selection:

- Maintain a clear selected state.
- Highlight corresponding cards/table rows where useful.

Avoid dramatic enlargement.

---

# 34. Table Animations

Tables should use subtle motion.

When rows change:

- Fade/slide new rows into view.
- Use limited stagger.

When expanding a row:

- Animate height/content reveal.
- Avoid abrupt jumps.

Do not animate hundreds of rows individually.

For large datasets, animate only visible/initial rows.

---

# 35. Heatmap Animation

For the Customer × Product Matrix:

- Transition cell intensity smoothly.
- Highlight the hovered row.
- Highlight the hovered column.
- Highlight the selected cell.

Keep changes subtle enough that the matrix remains readable.

---

# 36. Search Animation

For customer/product/SKU search:

- Debounce search input.
- Avoid excessive re-rendering.
- Use a subtle result crossfade.
- Keep the interface responsive while typing.

Do not animate every keystroke with expensive effects.

---

# 37. Drill-down Animation

When opening customer/product/invoice details:

Prefer:

- Slide/fade drawer
- Expanding detail panel
- Smooth row expansion

The detail view should feel connected to the selected record.

Do not use a jarring full-page navigation unless necessary.

---

# 38. SKU Chip Animation

For ASP SKU selection:

When a SKU is added:

- Fade/scale in the chip.
- Animate the corresponding chart series into view.

When removed:

- Fade/scale out.
- Remove the corresponding series smoothly.

Do not restart the entire ASP chart unnecessarily.

---

# 39. Loading / Refresh Animation

The refresh icon should rotate **only while data is loading**.

Use skeletons for asynchronous data loading where useful.

Do not show fake loading states for instant local calculations.

---

# 40. Upload / Export Animation

For file upload:

Show states such as:

- Ready
- Reading
- Processing
- Complete
- Error

For export:

Show:

- Preparing
- Exporting
- Complete

Keep these transitions short and informative.

---

# 41. Empty / Error States

Use subtle fade/slide transitions.

Do not use aggressive shake animations.

Examples:

- No matching customers
- No invoices for selected filters
- No ASP data
- API unavailable
- Upload failed

Error messages must be understandable to a normal business user.

---

# 42. Scroll-Based Animation

Use scroll-based section reveals sparingly.

Good use:

- Sections entering the viewport for the first time
- Subtle fade/translate

Avoid:

- Aggressive parallax
- Excessive movement
- Re-triggering animations continuously

Prefer one-time reveals.

---

# 43. Motion Hierarchy

Use these approximate durations:

| Motion Type | Duration |
|---|---:|
| Micro interaction | 100–180ms |
| Component transition | 180–300ms |
| Visualization | 400–900ms |
| Section/page entry | 300–600ms |

Centralize these values as CSS/JS motion tokens.

Example:

```css
--motion-fast: 150ms;
--motion-standard: 250ms;
--motion-slow: 500ms;
```

Centralize easing curves as well.

---

# 44. Reusable Animation Primitives

Create reusable helpers/classes/functions conceptually equivalent to:

- AnimatedMetric
- AnimatedSection
- AnimatedList
- AnimatedListItem
- AnimatedCard
- AnimatedChart
- AnimatedFilter
- AnimatedChip
- AnimatedExpandable
- AnimatedDrawer
- AnimatedNumber
- AnimatedSkeleton
- AnimatedRefresh
- AnimatedStateTransition

These do not need to be framework components.

Implement them as reusable CSS classes and JavaScript functions.

---

# 45. Accessibility — Reduced Motion

Respect:

```css
@media (prefers-reduced-motion: reduce)
```

When reduced motion is enabled:

- Disable large transforms.
- Remove unnecessary stagger.
- Reduce chart animation.
- Avoid count-up effects where appropriate.
- Keep state changes understandable without motion.

The dashboard must remain fully usable.

---

# 46. Performance Requirements

The dashboard may contain many:

- Rows
- Charts
- Products
- Customers
- SKUs
- Data points

Therefore:

- Avoid hundreds of simultaneous animation timers.
- Prefer CSS transitions where possible.
- Prefer `transform` and `opacity`.
- Avoid expensive layout-triggering animations.
- Avoid unnecessary DOM recreation.
- Update only affected components.
- Debounce search.
- Use pagination or virtualization for large tables.
- Lazy-render lower sections where practical.
- Do not animate off-screen content unnecessarily.
- Avoid repeatedly destroying/recreating chart instances if they can be updated.

---

# 47. Responsive Design

Desktop is the primary target.

### Desktop

Use:

- Multi-column analytics
- Wide tables
- Large charts
- Sidebar navigation

### Tablet

- Reduce grid density
- Collapse some columns
- Reduce animation stagger
- Preserve charts and filters

### Mobile

Do not simply shrink the desktop UI.

Instead:

- Stack KPI cards
- Stack charts
- Make tables horizontally scrollable or convert them into compact cards
- Use collapsible filters
- Simplify navigation
- Reduce animation complexity

---

# 48. Visual Design Direction

The visual style should be:

- Premium
- Clean
- Modern
- Analytical
- Professional
- High information density without feeling cluttered

Use:

- Strong spacing system
- Clear card hierarchy
- Soft borders
- Controlled shadows
- Excellent typography
- Strong number hierarchy
- Subtle hover states
- Clear selected states
- Consistent border radii

Do not create a flashy marketing website.

This is a serious business analytics product.

---

# 49. Color System

Use a restrained semantic color system.

Brand colors should be visually distinguishable.

Suggested semantic categories:

- Revenue / positive performance
- Warning
- Overdue
- Paid/closed
- Open
- Neutral
- Brand-specific series

Do not rely on color alone.

Charts, tables, and badges should also use:

- Labels
- Icons where appropriate
- Position
- Typography
- Patterns/secondary indicators if needed

---

# 50. Sidebar

Create a compact professional navigation sidebar.

Possible sections:

- Dashboard
- Sales
- Customers
- Products
- Invoices
- Reports
- Analytics
- Settings

The dashboard page should be clearly selected.

The sidebar should collapse on smaller screens.

---

# 51. Interaction Quality

Every interactive element must provide visual feedback.

Examples:

- Buttons
- Filter controls
- Dropdowns
- Cards
- Chart segments
- Table rows
- Search fields
- Chips
- Expanders

Hover, focus, active, selected, loading, and disabled states should all be considered.

Keyboard navigation should work for important controls.

---

# 52. Export

Provide a `Download All` workflow.

Where appropriate, export:

- Filtered invoice data
- Customer data
- Product data
- POC data
- Summary KPIs
- ASP data

Use sensible filenames.

Example:

`Koyson_Sales_Dashboard_FY26-27.xlsx`

If XLSX generation is not available in the chosen environment, provide CSV export for tabular data.

---

# 53. File Upload

Support uploading a source file such as:

`invoice_clean.xlsx`

The UI should:

1. Accept the file.
2. Validate it.
3. Read the data.
4. Normalize fields.
5. Recalculate metrics.
6. Update the dashboard.
7. Show success/error state.

The UI must clearly indicate when uploaded data is being used.

---

# 54. Data Normalization

Do not assume every source has perfectly consistent values.

Normalize:

- Dates
- Currency
- Invoice statuses
- Brand names
- Category names
- Customer names
- SKU names
- Salesperson names
- Numeric values

Keep raw source data separate from normalized analytics data.

---

# 55. Currency Handling

The dashboard should support:

- AED
- INR

If conversion is used, make the exchange rate explicit.

Do not silently mix currencies.

Every monetary metric must be associated with the selected currency.

---

# 56. Period Comparison

When `Compare Period on Period` is enabled:

Show:

- Current period
- Previous period
- Absolute difference
- Percentage difference

For example:

`AED 6.88M → AED 7.21M`

`+4.8%`

Use subtle visual indicators.

Comparison calculations must use equivalent periods.

---

# 57. Drill-down Behavior

A key goal is to move naturally from:

**Dashboard → Brand → Customer → Invoice → Product**

Examples:

- Click Nellon → dashboard filters to Nellon.
- Click customer → customer detail drawer.
- Click invoice → invoice detail.
- Click product → product analytics.
- Click matrix cell → filtered customer/product view.

Maintain breadcrumb or contextual state where useful.

---

# 58. Component Reuse

Do not create separate one-off implementations for every card/table.

Create reusable rendering functions for:

- KPI cards
- Summary cards
- Badges
- Filters
- Tables
- Empty states
- Tooltips
- Drawers
- Chart containers

This improves maintainability.

---

# 59. Code Quality

Write clean, readable, maintainable JavaScript.

Avoid:

- Giant monolithic functions
- Global variables everywhere
- Repeated formatting logic
- Inline event-handler sprawl
- Duplicate calculations
- Hardcoded DOM manipulation scattered throughout the code

Use clear function boundaries.

Document important business calculations.

---

# 60. Initial Demo Data

For the first implementation, include realistic demo data based on the supplied Koyson dashboard reference.

Use the reference values for presentation where appropriate, including:

- Nellon: AED 3.52M / 51.2%
- Non-Branded: AED 2.57M / 37.4%
- Raviya: AED 783.3K / 11.4%
- Cash: AED 4.26M / 61.9%
- 8–30 days: AED 119.1K / 1.7%
- 31–60 days: AED 1.71M / 24.8%
- 61–90 days: AED 790.3K / 11.5%
- Open: AED 1.49M
- Overdue: AED 3.00M
- Partially Paid: AED 70.4K
- Closed: AED 2.31M

Clearly structure demo data so it can later be replaced by Zoho Books API data.

---

# 61. Implementation Strategy

Build in stages.

## Stage 1 — Shell

Create:

- HTML structure
- Sidebar
- Header
- Filter bar
- Main grid
- Responsive layout

## Stage 2 — KPI + Summary

Implement:

- KPI cards
- Brand summary cards
- Number formatting
- Count-up animation

## Stage 3 — Charts

Implement:

- Revenue trend
- Revenue by brand
- Invoice status
- Weekly activity

## Stage 4 — Tables

Implement:

- Customers
- Categories
- POC
- Products
- Invoices

## Stage 5 — Matrix + ASP

Implement:

- Customer × Product matrix
- Credit breakdown
- ASP trend
- SKU selector

## Stage 6 — Interaction

Implement:

- Global filters
- Search
- Drill-down
- Period comparison
- Dynamic chart updates

## Stage 7 — Data Integration

Implement:

- File upload
- Data normalization
- Zoho Books integration layer
- Loading/error states

## Stage 8 — Export

Implement:

- Download All
- CSV/XLSX where supported

## Stage 9 — Motion Polish

Add:

- Entry animations
- KPI count-up
- Chart transitions
- Filter transitions
- Drill-down transitions
- Hover states
- Loading states
- Reduced-motion handling

## Stage 10 — QA

Test:

- Desktop
- Tablet
- Mobile
- Keyboard navigation
- Reduced motion
- Large datasets
- Empty data
- API errors
- File upload errors
- Filter combinations
- Export

---

# 62. Critical UX Rule

**Do not make the dashboard feel like a page that constantly reloads.**

When the user changes a filter, the dashboard should transform smoothly.

For example:

Bad:

```text
Click filter
→ entire page disappears
→ spinner
→ entire dashboard rebuilds
```

Good:

```text
Click filter
→ filter indicator changes
→ affected KPI values transition
→ charts update smoothly
→ tables update locally
→ unaffected components remain stable
```

---

# 63. Final Visual Goal

The finished application should look like a serious enterprise sales intelligence product.

It should communicate:

**"I can understand Koyson's sales performance in seconds, and investigate the details when I need to."**

Prioritize:

1. Information hierarchy
2. Data clarity
3. Interaction quality
4. Visual polish
5. Performance
6. Maintainability
7. Animation quality
8. Zoho Books integration readiness

Do not sacrifice usability for visual effects.

---

# 64. Acceptance Checklist

Before considering the dashboard complete, verify:

### Layout

- [ ] Sidebar works
- [ ] Header works
- [ ] Filters are clear
- [ ] Dashboard is responsive

### Data

- [ ] KPIs calculate correctly
- [ ] Revenue calculations are correct
- [ ] Brand calculations are correct
- [ ] Invoice statuses are correct
- [ ] Customer metrics are correct
- [ ] Product metrics are correct
- [ ] Credit-period calculations are correct
- [ ] ASP calculations are correct

### Interactions

- [ ] Filters update all dependent components
- [ ] Search works
- [ ] Tables sort
- [ ] Rows can expand
- [ ] Drill-down works
- [ ] SKU selection works
- [ ] Period comparison works

### Animation

- [ ] Initial entry feels polished
- [ ] KPI count-up works
- [ ] Charts animate
- [ ] Filter changes animate
- [ ] Table changes animate
- [ ] Drill-down animates
- [ ] Heatmap transitions smoothly
- [ ] SKU changes animate
- [ ] Refresh animation works
- [ ] Reduced-motion mode works

### Performance

- [ ] No unnecessary full-page rerenders
- [ ] Large tables remain usable
- [ ] Search is debounced
- [ ] Charts do not constantly recreate
- [ ] Animations do not cause noticeable lag

### Accessibility

- [ ] Keyboard navigation works
- [ ] Focus states are visible
- [ ] Important controls have labels
- [ ] Color is not the only information channel
- [ ] Reduced motion is respected

### Integration

- [ ] Zoho credentials are not exposed
- [ ] Data service is separated from UI
- [ ] API failures are handled
- [ ] Loading states are clear
- [ ] File upload works
- [ ] Export works

---

# 65. Final Instruction to the Coding Agent

Do not build a generic dashboard template.

Build the **Koyson Sales Dashboard** as a cohesive product.

Use the supplied dashboard reference to preserve its terminology, analytical structure, filters, metrics, categories, and overall information architecture.

Use **HTML + CSS + vanilla JavaScript only** for the frontend.

Make the interface highly polished with carefully designed motion, but keep animation purposeful and performant.

The final result should be:

- Production-oriented
- Responsive
- Fast
- Accessible
- Maintainable
- Data-driven
- Zoho Books integration-ready
- Visually impressive
- Easy to extend

**Most importantly: make the dashboard feel like one coherent analytical application, not a collection of unrelated widgets.**
