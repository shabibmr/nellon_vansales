# India commercial norms for software customization quotes (Zoho Books project)

Note: sources are mostly secondary (compliance blogs, agency/vendor marketing, tenders). Research done 2026-10-14 via search summaries; few pages fetched in full. No CBIC primary text was retrieved. Verify tax points with a CA.

## GST rate and SAC code; export vs domestic

### Takeaway
Custom software development is a taxable service at 18% GST domestically, commonly under SAC 998314 (some sources disagree on exact SAC mapping). Exports meeting all Section 2(6) IGST conditions are zero-rated (LUT, no IGST).

### Cited Findings
- Several sources list SAC 998314 for custom software, web and app development, domestic GST 18%; one says 18% applies across the board so the code rarely changes the tax — [Xflowpay](https://www.xflowpay.com/blog/gst-on-software-services); [Clevercoins 2026 guide](https://clevercoins.org/?p=3950)
- Sources conflict on SAC for SaaS/hosting (998314 vs 998315 for hosting/IT infrastructure) — [Tally Solutions](https://tallysolutions.com/gst/gst-software-saas-exports-international-clients/); [Incorpx](https://www.incorpx.io/blog/saas-business-gst-guide-india)
- Exports of software services are zero-rated under IGST Act s.16, ITC still allowed; all five conditions of s.2(6) IGST Act must be met or the supply is domestic at 18% — [Tally Solutions](https://tallysolutions.com/gst/gst-software-saas-exports-international-clients/); [Patron Accounting](https://www.patronaccounting.com/blog/gst-on-it-software-services-export)
- Exporters can supply under a Letter of Undertaking (annual) without paying IGST, or pay IGST and claim refund — [Patron Accounting](https://www.patronaccounting.com/blog/gst-on-saas-exports-lut)
- Software on physical media is goods (HSN 8523), not a service — [Tally Solutions](https://tallysolutions.com/gst/gst-software-saas-exports-international-clients/)

### Inferences
- A domestic Indian client (Zoho Books customer in India) is billed 18% GST (CGST+SGST or IGST) on top of the quote; state the quote as exclusive of GST.

### Gaps
- No primary CBIC/notification 11/2017 text retrieved; SAC 998314 vs others unresolved by primary source.

## TDS (194J / 194C)

### Takeaway
Technical-service fees: 194J at 2% (since 1 Apr 2020); professional services 10%; contract-for-work 194C 1% (individual/HUF) / 2% (others). Classification of software development is arguable but the deductor liability difference is small.

### Cited Findings
- Finance Act 2020 cut 194J rate from 10% to 2% for fees for technical services (other than professional) from 1 Apr 2020 — [Taxbuddy](https://www.taxbuddy.com/blog/tds-194c-vs-194j-what-s-the-difference); [VJM Global](https://www.vjmglobal.com/blog/tds-professional-fee-technical-fee)
- 194C is 1% for individual/HUF payees, 194J 2%; software could fall under either depending on service vs contract for work — [Taxbuddy](https://www.taxbuddy.com/blog/tds-rate-under-section-194c-for-individuals-vs-tds-rate-under-section-194j-for-professional-services)
- Commonly cited threshold Rs 30,000/yr under 194J; 20% if no PAN — [BankBazaar](https://11estates.bankbazaar.com/tax/section-194j-tds-on-professional-technical-fee.html)
- Single secondary source claims Budget 2024 moved professional services to strictly 194J from 1 Oct 2024 (unverified) — [Taxbuddy](https://www.taxbuddy.com/blog/section-194j-tds-on-professional-technical-fee-vs-section-194c-tds-on-contractor-payments)

### Inferences
- Quote should note TDS will be deducted by client; cash receipt is net of 2% (plus GST not subject to TDS if shown separately - not verified here).

### Gaps
- No authoritative ruling on software development classification; the 2024/new Income Tax Act 2025 section renumbering effects not checked.

## Payment milestones, validity

### Takeaway
Private vendors commonly take 20-30% advance with staged milestones; government tenders use 10-25% advances. No source confirmed 50% as a norm.

### Cited Findings
- Private vendor schedule: 20% advance, then 30%, 40%, 10% — [Prakity](https://prakity.com/payment-terms)
- Odisha govt RFP allows mobilization advance up to 25% — [Odisha RFP corrigendum](https://odisha.gov.in/sites/default/files/2024-02/Corrigendum-03_13.02.2024_RFP-24015.pdf)
- Govt example: 15% at 75% completion, 15% UAT, 15% security testing, 15% go-live, balance 10% in quarterly 5% post handover — [DAY-NULM corrigendum](https://qcin.org/wp-content/uploads/2024/10/Corrigendum-1_DAY-NULM.pdf)
- Zoho partners split fixed fees into milestones: discovery/config, migration, training, go-live — [Aaxonix](https://aaxonix.com/resources/zoho-implementation-partner-cost-india/)
- Quote validity in Indian tenders: 30 days (IIT Kanpur software enquiry), >=40 days (GBPUAT), 90 days (ICFRE) — [IITK](https://iitk.ac.in/new/hindi/data/tender/file/IITK_DESIGN_VCL_2013-14_003.pdf); [GBPUAT](https://www.gbpuat.ac.in/tendernotice/12.02.2019_SAP_Software.pdf); [ICFRE](https://www.icfre.org/tender/tender85.pdf)
- Under s.5 Indian Contract Act a proposal can be revoked before acceptance; estimate vs firm quotation distinction — [Petpooja glossary](https://blog.petpooja.com/glossary/quotation/)

### Gaps
- Private-sector validity norm (30 days is typical inference only); no source for 50% advance.

## AMC / support and hourly rates

### Takeaway
Annual maintenance rule of thumb is 15-20% (up to 25%) of build cost; Zoho partner retainers Rs 15-40k/month; partner day rates Rs 3,500-12,000.

### Cited Findings
- AMC 15-20%/yr in Indian govt/PSU software contracts (secondary summary of TenderDekho guide) — [echai.ventures](https://echai.ventures/gtm/from/tenderdekho)
- Maintenance 15-25% of build cost per year; 2026 DACH benchmark median 24% yr1; 10-16% for quiet internal apps (non-India, vendor blog) — [Edana](https://edana.ch/?p=44898); [Wavect](https://wavect.io/blog/software-maintenance-cost-benchmark-dach-saas/)
- Indian Zoho partner day rate Rs 3,500-12,000; India partner $20-45/hr; support retainer Rs 15,000-40,000/month; boutique full implementation Rs 75,000-3,50,000 incl. training and go-live review; Digiwah Rs 35,000 (5-user) to Rs 4L+ — [Aaxonix](https://aaxonix.com/resources/zoho-implementation-partner-cost-india/); [RaftLabs](https://www.raftlabs.com/blog/top-zoho-development-companies); [Digiwah](https://digiwah.com/zoho/)
- Freelancer.in Zoho Books setup bids averaged about Rs 1,036/hr; a Zoho Books invoice-column job averaged Rs 8,346 total (open bids, not contracted) — [Freelancer.in](https://www.freelancer.in/projects/zoho-creator/zoho-books-setup-40441969); [Freelancer.in](https://www.freelancer.in/projects/zoho/zoho-book-invoice-customization)
- India Fiverr Zoho customization freelancer $30/hr — [Fiverr](https://www.fiverr.com/amans2030)

### Gaps
- No itemised UAT/training/handover prices found (bundled in fees); no explicit change-request rate clauses found; no India-specific out-of-scope hourly benchmark.

## Hosting (small Python + MariaDB app)

### Takeaway
2 vCPU/4GB Indian VPS ranges from about Rs 880-950 to Rs 3,600 per month; budget-end providers dominate low prices.

### Cited Findings
- Inservers 2 vCPU/4GB/40GB NVMe Rs 880/mo — [GBNodes 2026](https://gbnodes.host/blogs/cheap-vps-india-2026/)
- RupeeCloud Nano 2 vCPU/4GB Rs 949/mo excl. 18% GST — [iTechGuides](https://www.itechguides.com/products/rupeecloud-vps/)
- NetSpaceIndia 2 vCPU/4GB Rs 3,583/mo incl. taxes (Mumbai) — [WhTop](https://www.whtop.com/plans/netspaceindia.com/154259)
- Hostinger India VPS starts ~Rs 199-249 on 24-month prepay, renewal ~Rs 600-700 (spec tier unstated); DigitalOcean Bangalore ~Rs 590 (spec unstated) — [GBNodes](https://gbnodes.host/blogs/cheap-vps-india-2026/); [Techplained](https://www.techplained.com/cheapest-vps-india)
- MilesWeb Windows 2 vCPU/8GB Rs 1,499/mo — [MilesWeb](https://milesweb.in/hosting/vps-hosting/price)

### Inferences
- Budget Rs 1,000-3,500/month (plus 18% GST, backups) for hosting; affiliate/review sources so verify on provider pages.

### Gaps
- No official DigitalOcean/Lightsail Mumbai INR price retrieved.

## Fixed/value pricing vs hourly; AI-accelerated work; estimate discounting

### Takeaway
Only agency opinion pieces: fixed-scope/value pricing is advocated for AI-assisted delivery; no survey data on Indian adoption or on man-day-vs-actual discounts.

### Cited Findings
- Agency blog argues hourly pricing hands AI productivity gain to clients and recommends fixed-scope value pricing, retainers with caps, productized services — [VibeCoder](https://blog.vibecoder.me/scoping-pricing-ai-assisted-agency-projects)
- Indian agency guide: AI has not lowered rates; cites July 2025 METR study (experienced devs ~19% slower with AI); fixed-price for tight scope, T&M for uncertainty — [IndiaNIC](https://www.indianic.com/resources/cost-to-hire-a-dev-agency-2026)
- Cosmoxyn advertises fixed price, fixed scope; Indian AI deployment 3-25 lakh+ (2026) — [GoodFirms](https://www.goodfirms.co/company/cosmoxyn); [BuildFastWithAI](https://www.buildfastwithai.com/blogs/ai-deployment-cost-india)

### Gaps
- No evidence on typical discount between quoted man-days and actual effort, nor contingency % norms; no 2025 survey of Indian agency pricing shifts.
