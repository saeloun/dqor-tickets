# Running Event Ticketing + Payouts for Conferences in India — Compliance & Payments Research

Research date: July 2026. Laws and thresholds cited below change frequently (GST notifications, RBI circulars, NPCI guidelines) — treat exact percentages/dates as "true as of mid-2026" and re-verify before hard-coding them into product logic.

---

## 0. Executive summary

A platform that (a) sells tickets on behalf of many independent conference organizers, (b) collects the money itself, and (c) later settles it to each organizer's bank account is legally a **marketplace / e-commerce operator (ECO)** under both GST and Income Tax law, and its money-collection function is regulated by RBI as **payment aggregation**. That triggers four separate compliance regimes simultaneously:

1. **GST** — SAC 998596 admission services, place-of-supply-at-venue rules, mandatory ECO registration, and 0.5% TCS under Section 52.
2. **Income Tax** — 0.1% TDS under Section 194‑O on every rupee paid to an organizer.
3. **RBI Payment & Settlement Systems Act** — you cannot collect customer money into your own current account and later pay it out to organizers unless you (or your payment partner) hold a **Payment Aggregator (PA) authorisation**, and the funds must sit in a regulated escrow account.
4. **RBI card tokenisation / DPSS rules** — you cannot store raw card numbers, and increasingly cannot rely on manual-VPA UPI Collect for mobile checkout.

**Recommended architecture (detailed in §7):** Don't try to become an RBI-licensed Payment Aggregator. Instead ride on an already-authorised PA (Razorpay is used as the reference implementation throughout this doc because the org already has an MCP integration for it) and use **Razorpay Route** to create one **Linked Account** per organizer, so ticket money is split to the organizer at the transaction/transfer level inside Razorpay's own escrow, not inside your bank account. Use **RazorpayX Payouts** (bank/VPA) for anything Route can't cleanly express — irregular sponsorship payouts, refund top-ups, ad-hoc vendor payments. Auto-deduct 194‑O TDS and Section 52 GST TCS at the platform level before crediting organizers, and make the **organizer** (not the platform) issue the GST tax invoice to each ticket buyer, since the organizer is the actual legal supplier of the "admission to conference" service.

---

## 1. GST on event tickets

### 1.1 SAC code(s)

| SAC | Description | GST rate |
|---|---|---|
| **998596** | "Events, exhibitions, conventions and trade shows organisation and assistance services" — the standard code for conference/exhibition admission, registration fees, delegate passes, sponsorship-linked exhibitor packages | **18%** |
| 998599 / 9985 | "Other support services n.e.c." — used for a platform's own booking/convenience/service fee charged to the organizer (a B2B intermediary/support service, distinct from the admission itself) | 18% |
| 999599 / 9996 | Recreational, cultural & sporting admission (concerts, sporting events, amusement) — only relevant if the event has an entertainment/sporting component ticketed separately | 18% (see exceptions below) |

**Important 2025 carve-outs to know about, even if they don't apply to a typical professional/tech conference:**
- Under the **GST 2.0** rate rationalisation (effective 22 Sept 2025), admission to **IPL-style matches, casinos, race-club betting, lotteries and "sporting events" classed as actionable claims** was moved into a new **40%** demerit-goods slab (up from 28%). This does *not* apply to ordinary business conferences/trade shows, which stay in the 18% (998596) bucket — but flag it if a customer ever runs a ticketed sporting/entertainment side-event.
- **Recognised sporting events** (per a national/international sports federation) are **GST-exempt** if admission is ≤₹500 per person (Notification 12/2017-CT(Rate), Entry 68) — again a niche case, not typical conferences.

For a standard professional conference, **998596 at 18%** is the number to hard-code as the default, with CGST+SGST or IGST split depending on place of supply (§1.2).

Sources: [SAC 998596 – Credlix](https://www.credlix.com/hsn-code/998596), [GST on Event Management – Cleartax](https://cleartax.in/s/gst-on-event-management), [GST on conference/exhibition – TaxGuru](https://taxguru.in/goods-and-service-tax/gst-conference-exhibition-services-delegates-exhibitors.html), [GST Council 40% on IPL/casinos – PL India](https://www.plindia.com/news/gst-council-40-percent-tax-ipl-tickets-casinos-lotteries-betting-sept-22/), [Sporting event exemption ≤₹500 – CAclubindia](https://www.caclubindia.com/articles/new-gst-on-sporting-event-exemption-for-lowpriced-tickets-54106.asp)

### 1.2 Place of supply → CGST+SGST vs IGST

For "services by way of admission to … educational, scientific, cultural, artistic, sporting, entertainment or similar events" the place of supply is **not** the buyer's location and **not** the supplier's registered address — it is **the location where the event is actually held**:

- **Section 12(6), IGST Act** — domestic transactions (organizer and event both in India): POS = venue location.
- **Section 12(7)** — *organisation of* an event (event-management/exhibition-organiser services to an organizer/sponsor) also fixed to the venue's state, with apportionment rules if the event spans multiple states/UTs.
- **Section 13(5)** — cross-border (supplier or recipient outside India, e.g., a foreign speaker or an overseas sponsor): POS is still the venue location.

**Practical consequence:**
- If the organizer's GST registration is in the *same state* as the venue → charge **CGST + SGST**.
- If the organizer is registered in a different state than the venue (or not registered in the venue's state at all) → this is where most conference platforms get it wrong. GST is due in the **venue's state**, so:
  - If the organizer already holds a regular GST registration in the venue's state → CGST+SGST of that state.
  - If not, and the organizer is only doing a one-off event there → they generally need a **Casual Taxable Person (CTP) registration** in that state (Section 27, CGST Act), which requires an **advance tax deposit** based on estimated turnover, is valid up to 90 days (extendable), and cannot use the Composition Scheme. This is a common trap for touring/multi-city conference organizers and should be a checklist item during organizer onboarding on the platform.
  - A buyer located in a third state (say, Delhi buying a ticket to a Bangalore conference) still gets a **CGST+SGST(Karnataka)** invoice, not IGST — this surprises many B2C ticket buyers/finance teams and is worth stating clearly on the invoice/receipt.

Sources: [POS admission events s.12(6)/12(7) – TaxTMI](https://www.taxtmi.com/manuals?id=2469), [POS cross-border events s.13(5) – TaxTMI](https://www.taxtmi.com/manuals?id=2481), [Casual Taxable Person for exhibitions/trade fairs – Taxscan](https://www.taxscan.in/top-stories/casual-taxable-person-under-gst-registration-traps-for-exhibitions-and-trade-fairs-1448130), [CTP registration & advance tax – RegisterKaro](https://www.registerkaro.in/post/casual-taxable-person-gst-rules-registration)

### 1.3 Tax-inclusive pricing

There is no Legal-Metrology "MRP" rule for services/tickets (MRP inclusive-of-tax labelling is a *packaged-goods* concept under the Legal Metrology (Packaged Commodities) Rules, 2011 and doesn't literally apply to event admission). In practice, however:
- Indian consumer-facing pricing convention (and the Consumer Protection Act's prohibition on undisclosed/deceptive pricing) means the price shown to a **B2C buyer at checkout should be the final, tax-inclusive price** — GST should not be sprung on the buyer as a surprise line item after they've committed to a price.
- The **tax invoice itself must still show the breakup** (taxable value + CGST/SGST or IGST amount + rate) even when the checkout price was quoted inclusive — this is a Rule 46 requirement (§1.4), not optional even for round-number inclusive pricing.
- Recommended pattern: display "₹X all-inclusive," back-calculate taxable value = X ÷ 1.18, and print both the inclusive total and the tax breakup on the invoice.

Sources: [MRP inclusive of GST – IndiaFilings](https://www.indiafilings.com/learn/gst-on-mrp-products), [MRP & Legal Metrology vis-à-vis GST – TaxTMI](https://www.taxtmi.com/article/detailed?id=15118)

### 1.4 Mandatory GST tax-invoice fields (Rule 46, CGST Rules 2017)

A valid tax invoice needs (non-exhaustive, but these are the ones that actually get checked in audits / block ITC for the buyer if missing):

1. "Tax Invoice" heading
2. Supplier's (organizer's) legal name, address, **GSTIN**
3. A **consecutive serial number**, unique per financial year, max 16 characters
4. Date of issue
5. Recipient's name, address, and **GSTIN** (if registered — e.g., a company buying a corporate group registration) or "unregistered" for a normal consumer buying a personal ticket
6. **Place of supply** (state name + code) — mandatory, and per §1.2 this is the venue's state, not the buyer's
7. **HSN/SAC code** (998596)
8. Description of service ("Conference registration — [Event name], [dates]")
9. Quantity (N/A for services, but ticket count is good practice)
10. Taxable value
11. GST rate (18%)
12. Tax amount split by type: **CGST + SGST**, or **IGST**, shown separately (never a single blended "GST" line)
13. Signature / digital signature of the supplier (for e-invoices, the signed QR + IRN takes this role — see §1.6)

Penalty for a materially deficient invoice: up to ₹25,000 per invoice under Section 122 CGST Act, and the **buyer loses ITC** on that invoice if a mandatory field is wrong — significant if the buyer is a corporate delegate expensing/claiming input credit on the registration fee.

Sources: [Rule 46 checklist – GimBooks](https://www.gimbooks.com/blog/gst-invoice-mandatory-fields-rule-46-checklist/), [Tax invoice requirements s.31 & Rule 46 – TaxGuru](https://taxguru.in/goods-and-service-tax/tax-invoice-requirements-section-31-cgst-act-gst-rule-46.html)

### 1.5 Advance / early-bird ticket sales trigger GST immediately

Unlike goods, **services attract GST at the time of advance receipt**, not just at the time of the event/final invoice (time-of-supply rule: earliest of invoice date or payment receipt date). Since a conference ticket is a *service* (admission), every early-bird or pre-registration payment is GST-liable the moment it's collected:

- The organizer (or platform on the organizer's behalf) must issue a **Receipt Voucher** under **Rule 50, CGST Rules** at the time advance payment is received, containing: supplier/recipient details, a consecutive serial number, date, description, advance amount, applicable rate/tax amount, place of supply, RCM applicability flag, and signature.
- The GST from that receipt voucher must be reported/paid in the return period in which the advance was received — you cannot defer it to the month the conference actually happens.
- At the time the final tax invoice is issued (on/before the event), the advance is adjusted against the invoice value so GST isn't double-counted.

This has direct product implications: the platform's ticketing checkout flow needs to generate a **receipt voucher** (not just an order confirmation) for every advance/early-bird sale, and GST liability for the organizer's GSTR-1/3B accrues on sale date, not event date.

Sources: [Advance receipts & receipt vouchers – Cleartax](https://cleartax.in/s/advance-received-under-gst), [GST on advance for services – TaxGuru](https://taxguru.in/goods-and-service-tax/gst-advance-services-tax-payable-work-begins.html)

### 1.6 GSTIN validation

A GSTIN is 15 characters: `SS PPPPPPPPPP E Z C`
- **SS** (2): State code
- **PPPPPPPPPP** (10): the entity's PAN
- **E** (1): entity/registration-number-within-state sequence
- **Z** (1): fixed literal "Z"
- **C** (1): **check character**, computed with a **Luhn mod-36 algorithm** over the preceding 14 characters (each char mapped to a 0–35 value, alternating ×1/×2 weighting, values summed, and the checksum chosen so the total is a multiple of 36). This catches essentially all single-character typos and most transpositions — validate it client-side before hitting the government GSTIN-verify API, and always additionally verify status ("Active") server-side via the GST Common Portal / a GSTIN-verification API before onboarding an organizer, since format validity ≠ registration validity.

Sources: [GSTIN checksum algorithm – GitHub srikanthlogic/gstin-validator](https://github.com/srikanthlogic/gstin-validator), [Decoding the checksum digit – Medium](https://medium.com/@dhananjaygokhale/decoding-gst-number-checksum-digit-1ef2c8c53ad6)

### 1.7 E-invoicing (IRP / IRN)

- **Current mandatory threshold: aggregate turnover > ₹5 crore** (any of the years from FY 2017-18 onward), effective since 1 Aug 2023. A proposal to lower this to **₹2 crore from 1 Oct 2025** has been discussed at GST Council but **has not been formally notified as of mid-2026** — treat ₹5 crore as the live threshold and monitor for a lowering notification.
- **E-invoicing (IRN generation via the IRP) only applies to B2B, export and government-supply invoices.** GST law explicitly **excludes B2C transactions** from the IRN requirement — and even carves out specific consumer-facing categories (passenger transport tickets, multiplex movie tickets) as exempt regardless of turnover, reflecting the general policy that IRN exists for ITC-matching between businesses, not consumer receipts.
- **Consequence for a ticketing platform:** the overwhelming majority of ticket sales (an individual buying their own conference pass) are **B2C and do not need an IRN**, *even if the organizer's turnover is well above ₹5 crore*. IRN only becomes mandatory for the subset of sales that are genuinely **B2B — e.g., a company buying 20 seats and needing the invoice issued to its own GSTIN** for ITC — where the organizer's aggregate turnover exceeds the threshold.
- A **separate, unrelated obligation** — a **Dynamic QR code on B2C invoices** — applies only to suppliers with turnover **> ₹500 crore** (Notification 14/2020-CT). This is a UPI-payment-linked QR for the buyer to pay via, not an e-invoicing/IRN requirement, and is irrelevant to almost every conference organizer.
- **Bottom line for small/mid conferences:** most organizers on a ticketing platform will need **neither** IRN e-invoicing nor Dynamic-QR B2C compliance. Build the capability to route B2B group-registration invoices through an IRP integration (e.g., via ClearTax/Razorpay-style e-invoicing APIs) as an opt-in feature for organizers who cross ₹5 crore turnover and sell corporate blocks, rather than a universal requirement.

Sources: [E-invoice limit guide – Gimbooks](https://www.gimbooks.com/blog/e-invoice-limit-in-india/), [₹5cr still current, ₹2cr not yet notified – multiple 2026 sources], [E-invoicing excludes B2C, movie/transport tickets exempt – various], [Dynamic QR B2C >₹500cr – GSTZen](https://gstzen.in/b2c-invoice/b2c-qr-code.html), [Notification 14/2020-CT clarification – CAclubindia](https://www.caclubindia.com/articles/clarification-applicability-dynamic-qr-code-b2c-invoices-compliance-notification-142020-ct-21st-march-2020-44100.asp)

### 1.8 RCM (reverse charge) edge cases relevant to conferences

- **Sponsorship services** — historically fully under RCM (Notification 13/2017-CT(Rate), Entry 4): if a sponsor pays an organizer for branding/sponsorship, GST was payable by the *recipient* (the organizer) under reverse charge whenever the sponsor was a body corporate or partnership firm. **This changed 16 Jan 2025 (Notification 07/2025-CT(Rate)):**
  - Sponsorship supplied **by a body corporate** → moved to **forward charge** (the sponsoring company now charges and remits GST itself, like a normal supply).
  - Sponsorship supplied **by a non-body-corporate** (individual, unregistered entity, unincorporated association) → **still RCM**, i.e. the organizer receiving the sponsorship must self-assess and pay the GST.
  - **Product implication:** if the platform also facilitates sponsorship payments (not just ticket sales), it needs to know the sponsor's entity type to determine who is liable for the GST, and must not assume the organizer is always liable post-Jan-2025.
- **Import of services** — if a conference pays an overseas keynote speaker/vendor directly (no Indian GST registration on their end), the **organizer** is liable to self-invoice and pay IGST under RCM (Section 5(3), IGST Act) on that import of service.
- **Renting from unregistered venue owners** — the old blanket Section 9(4) RCM (any purchase from an unregistered supplier) has long been suspended/scoped down to a narrow real-estate-construction use case; it generally does **not** apply to ordinary venue rental from an unregistered landlord anymore, so this is a smaller risk than it used to be, but worth a quick check per state if the venue owner is unregistered.

Sources: [Sponsorship RCM amendment Jan 2025 – Cashflo](https://www.cashflo.io/magazine/gst-rcm-not-applicable-for-sponsorship-services-provided-by-a-body-corporate-notification-issued), [Sponsorship services RCM/exemptions – TaxGuru](https://taxguru.in/goods-and-service-tax/gst-sponsorship-services-rcm-exemptions.html)

### 1.9 GST registration mandatory for the platform (and nuances for organizers)

- **The platform itself, as an "Electronic Commerce Operator" (ECO), must register for GST in every state it operates from, with no turnover threshold exemption** — Section 24(x), CGST Act, is a compulsory-registration category regardless of revenue.
- **Organizers (suppliers) selling *through* the platform generally also fall under compulsory registration** (Section 24(ix)) *unless* they qualify for the **Notification 65/2017-CT** carve-out: suppliers of **services** (not goods) through an ECO required to collect TCS are exempt from mandatory registration if their own aggregate turnover is below ₹20 lakh (₹10 lakh for special-category states) — **provided their service isn't one of the Section 9(5) categories** (cab, hotel-below-threshold, housekeeping, restaurant — none of which include "conference admission," so this carve-out generally *does* apply to small/first-time organizers).
- **Practical tension:** Section 52 TCS mechanics (§4.2) are built around registered suppliers with a GSTIN to credit the TCS against in GSTR-2. An organizer who is legitimately unregistered under the Notification 65/2017 exemption creates friction for TCS credit and invoice GSTIN population. **Recommendation:** even though small organizers *can* stay unregistered, strongly encourage (or require) every organizer on the platform to hold a GSTIN before their first payout — it avoids this TCS-credit dead-end, lets them issue proper Rule 46 invoices, and is a one-time onboarding cost against recurring reconciliation pain.

Sources: [Compulsory registration s.24 – Tax2win](https://tax2win.in/guide/compulsory-registration-gst-act-section-24), [Notification 65/2017 exemption – StudyCafe](https://studycafe.in/cgst-notification-no-652017-exempts-suppliers-e-commerce-platform-registration-15948.html), [s.9(5) vs s.52 – Cashflo](https://www.cashflo.io/magazine/section-9-5-vs-section-52-of-cgst-act-e-commerce-operators)

---

## 2. UPI

### 2.1 Collect vs Intent

- **UPI Intent**: the merchant app deep-links directly into the buyer's chosen UPI app (GPay/PhonePe/Paytm/etc.), pre-filling the payee VPA and amount; buyer just authenticates. Works on mobile web/app where an installed UPI app can be launched.
- **UPI Collect**: the merchant sends a payment *request* to a VPA the buyer manually types in; the buyer approves it from within their UPI app after receiving a notification. Historically necessary for desktop/laptop checkout (no app to deep-link into) and for typed-VPA flows.
- **Success-rate gap**: Intent typically converts 10–15 points higher (92–95% vs Collect's lower rates) because it removes manual VPA-typing errors and notification-delivery latency.
- **Regulatory direction**: NPCI guidance (effective ~Feb 2026) is actively phasing out manual-VPA UPI Collect for P2M (person-to-merchant) transactions on mobile, pushing merchants toward **Intent on mobile** and **QR-based Collect on desktop**. **Build checkout to default to Intent on mobile and a QR code on desktop**; don't rely on a manual "enter your UPI ID" Collect box as the primary mobile flow going forward.

Sources: [UPI Intent vs Collect success rates – Razorpay](https://razorpay.com/blog/upi-intent-vs-collect-success-rates/), [UPI Collect deprecation – Cashfree](https://www.cashfree.com/docs/payments/manage/payment-methods/upi-collect)

### 2.2 Static vs dynamic UPI QR

- **Static QR**: one fixed code per merchant VPA; buyer types in the amount themselves. Fine for a donation box or a small merchant, but gives you **no automatic order↔payment mapping** — terrible for a ticketing checkout where you need to know exactly which order got paid.
- **Dynamic QR**: generated per-transaction, amount pre-filled, expires after use or a TTL, and is trivially reconcilable against the specific order/invoice (Razorpay's QR-code API supports embedding invoice metadata — invoice number, date, GSTIN — directly in the dynamic QR for GST-compliant B2C receipts).
- **Recommendation**: always use **dynamic QR** (or Intent) for ticket checkout; reserve static QR only for things like a generic "buy me a coffee"/sponsor-booth donation stand where amount variability and lack of reconciliation don't matter.

Sources: [Static vs dynamic QR – Mintoak](https://www.mintoak.com/blog/Understanding-Dynamic-vs-Static-QR-Codes-How-They-Differ-and-What-They-Offer), [Dynamic QR for B2C GST invoices – Razorpay](https://razorpay.com/blog/how-to-generate-gst-dynamic-qr-codes-with-razorpay/)

### 2.3 Routing UPI payments directly to an organizer's own VPA/bank — should you?

Technically possible (generate a UPI QR/Intent request that pays straight into the organizer's own VPA, bypassing the platform entirely), but **not recommended as the primary model** for a multi-organizer marketplace, because:
- The **platform loses visibility and control** of the money at the moment of payment — no ability to hold, refund centrally, deduct the platform's own commission, or apply 194‑O TDS / Section 52 TCS deductions before the organizer receives funds (both are legally the *platform's* obligation to withhold, not something you can do after the money has already left).
- **Reconciliation and refund handling become the organizer's problem**, not the platform's — defeats the point of running a shared ticketing product.
- It **is** a legitimate lightweight model for a "pure booking engine that never touches money" product (you just list events and hand off to the organizer's own payment page) — but that's a fundamentally different product than "collects revenue and settles to organizers," which is what this doc is scoped for.

For the target model (platform collects, then settles), route the money through **Razorpay Route** or **RazorpayX Payouts** instead (§3), not directly to the organizer's raw VPA/bank account outside the payment aggregator's ledger.

---

## 3. Organizer / sponsor payouts — Razorpay Route & RazorpayX

### 3.1 Why you need an authorised Payment Aggregator (PA) in the loop at all

Under the **RBI "Guidelines on Regulation of Payment Aggregators and Payment Gateways" (2020, updated since)**, any non-bank entity that **collects funds from customers on behalf of merchants and later settles those funds** is a Payment Aggregator and must hold an **RBI Certificate of Authorisation** — minimum ₹25 crore net worth, PCI-DSS certification, data-localisation compliance, ~4–6 month approval process. Operating unauthorised is a violation of the **Payment and Settlement Systems Act, 2007**.

A marketplace that runs its own checkout, takes customer money into its own bank account, and periodically pays organizers **is doing payment aggregation** by definition — even though ticketing is its "real" business. RBI explicitly requires marketplaces that also want to touch money to **separate their marketplace and PA operations**, and either get their own PA authorisation or use a licensed PA's infrastructure so the money never legally sits under the platform's own unregulated control.

**This is the single most important architectural constraint in this whole document**: build on top of an already-authorised PA (Razorpay, Cashfree, PayU, etc.) using their marketplace-split product, rather than collecting into your own current account and disbursing manually. Funds must move through the PA's RBI-mandated **escrow account**, with settlement timelines the PA is bound to (e.g., settlement to the merchant/linked account within a prescribed number of days, and the escrow account may only be debited for a specific whitelist of permitted purposes: payments to merchants, refunds, commission to intermediaries, etc.).

Sources: [RBI PA guidelines net worth/PCI-DSS – KDP Accountants](https://kdpaccountants.com/blogs/rbi-payment-aggregator-license-india-2025-guide), [Escrow account & settlement timelines – VJM Global](https://www.vjmglobal.com/blog/payment-aggregators-and-payment-gateways-guidelines-on-settlement-and-escrow-account-management-and-other-instructions), [PA authorisation mandatory – Finlaw](https://finlaw.in/blog/how-to-get-a-payment-aggregator-license-from-reserve-bank-of-india-rbi)

### 3.2 Razorpay Route — marketplace split settlement

- **Linked Account**: a sub-entity created *under* the platform's Razorpay merchant account, one per organizer, each with its own `account_id`. It has its own KYC (business name, business type/category, PAN, bank account **in the business's own name**, contact email/phone).
- **Transfers**: for any payment collected on the platform's primary account, you create **Transfer** objects that route a defined portion of that specific payment to one or more Linked Accounts — e.g., 90% to the organizer's linked account, 10% retained as platform commission, all within the same transaction, auditable per-order.
- **Settlement delay**: you can configure a custom hold period per Linked Account (e.g., T+2, T+7) before Razorpay actually settles the split amount to the organizer's real bank account — useful for holding a buffer against chargebacks/refunds on a specific event before fully releasing funds to a new/unproven organizer.
- **Refunds/reversals**: Linked Accounts can view their own reversals/settlements and are the natural point at which a refund on a specific ticket order is clawed back from the organizer's split.
- **Why this is the right shape for a ticketing marketplace**: it keeps money attribution at the level of the individual transaction (this ticket's ₹X belongs to this organizer), rather than pooling everything into the platform's balance and later trying to reconstruct who's owed what.

Sources: [Razorpay Route overview – Razorpay Docs](https://razorpay.com/docs/route/), [Linked Accounts – Razorpay Docs](https://razorpay.com/docs/payments/route/linked-account/), [Route integration guide/KYC – Razorpay Docs](https://razorpay.com/docs/payments/route/integration-guide/?preferred-country=US)

### 3.3 RazorpayX Payouts — the complementary disbursement rail

Where Route expresses "who owns which slice of this specific payment," **RazorpayX Payouts** is a general-purpose disbursement API for pushing money *out* of a RazorpayX current/business account to any external party:
- **Fund Account types**: `bank_account` (NEFT/IMPS/RTGS) or `vpa` (straight to a UPI ID).
- Useful for cases Route doesn't cleanly cover: **sponsorship payouts** that aren't tied to a single ticket transaction, ad-hoc reimbursements, refund top-ups when the Route-held balance is insufficient, or bulk vendor/speaker payments.
- Also exposes **Account Validation APIs** (penny-drop-style validation of a bank account or VPA before you pay it) — use this at organizer-onboarding time to confirm the bank details they've submitted are real and match the KYC name, before the first payout ever goes out.
- RazorpayX Business Banking+ also offers **automatic TDS computation and payment** (relevant directly to §4.1 below) — TDS is deducted and challan-paid on a schedule (e.g., 4th of the following month), with Form 16A generated per vendor/organizer from the dashboard.

Sources: [Payout APIs – Razorpay Docs](https://razorpay.com/docs/api/x/payouts/), [Fund Account APIs – Razorpay Docs](https://razorpay.com/docs/api/x/fund-accounts/), [Automatic TDS – Razorpay Docs](https://razorpay.com/docs/x/tax-payments/automatic-tds/)

### 3.4 KYC for organizers (Linked Accounts) and sponsors

Minimum KYC set typically required to activate a Linked Account / payout beneficiary:
- Legal business/entity name (min length enforced, e.g. 4 chars)
- Business type & category (proprietorship, partnership, private limited, trust/society for non-profit conference bodies, etc.) and sub-category
- PAN (business or individual, depending on entity type)
- Bank account **in the name of the business/entity being paid** — not a personal account of an employee, which is a common failure mode for informal/first-time organizers
- Contact email + phone
- For higher-risk/larger-volume organizers, expect the PA to ask for additional documents per business type (GSTIN, incorporation certificate, address proof, etc.) — Razorpay publishes a business-type-specific KYC document matrix.

**Sponsorship payments** ride the exact same rails (Route transfer or RazorpayX payout) as ticket settlements — from a payments-infra point of view a sponsor's payment to an organizer is just another inbound transaction that needs to be split/settled the same way, with the GST/RCM nuance from §1.8 layered on top.

Sources: [KYC Documents for Business Types – Razorpay Docs](https://razorpay.com/docs/payments/business-types-kyc-documents/?preferred-country=US), [Sub-merchant onboarding KYC requirements – Razorpay](https://razorpay.com/docs/build/browser/assets/images/Razorpay_Sub-Merchant_Onboarding_KYC_Requirements_and_User_Communications.xlsx)

---

## 4. Saved cards / tokenization

### 4.1 The RBI Card-on-File Tokenisation (CoFT) mandate

- Effective **1 October 2022** (after deadline extensions from the original Jan 2022 date), **merchants, payment aggregators/gateways, and acquiring banks in India are prohibited from storing actual card numbers, CVV, or expiry dates** on their own servers for online transactions. Only **card-issuing banks and card networks** (Visa/Mastercard/RuPay) may retain real card data.
- **Card-on-File Tokenisation (CoFT)** is the RBI-sanctioned replacement: the real card number is swapped for a **network token** — a surrogate value with no exploitable mathematical relationship to the real PAN — generated and managed by the card network/issuer, one token per (card, merchant) pair.
- **A narrow settlement exception** exists: card data may be held for up to **4 days, or until settlement — whichever is earlier** — purely to complete an in-flight transaction, not for future reuse.
- **Tokenisation requires explicit customer consent plus an Additional Factor of Authentication (AFA)** (the same 2FA/OTP flow used on the original transaction) before a card can be saved as a token — you cannot silently tokenise a card on a customer's behalf.

### 4.2 How Razorpay and Stripe implement this for Indian cardholders

- **Razorpay TokenHQ / Optimizer**: acts as a **Token Requestor**, connecting the merchant to the card networks/issuing banks to create and manage network tokens on the merchant's behalf; reports >99% token-creation success rate across networks. Also supports **CVV-less repeat checkout** for tokenised cards, since the network token flow doesn't require re-entering CVV on every use in supported scenarios.
- **Stripe (India network tokenisation)**: Stripe acts as a compliant card vault, tokenising India-issued cards via 3DS-authenticated Setup/Payment Intents, and using network tokens (not raw PANs) for both one-off and recurring charges. Stripe explicitly **does not offer "tokenisation-as-a-service"** — i.e., you can't get a raw token back to store on your own infrastructure; the token stays inside Stripe's vault and you reference it by a Stripe-side ID.

**Product implication**: for a conference platform, saved-card support (e.g., "save my card for next year's early-bird") is entirely feasible and RBI-compliant, but must go through the PA's tokenisation product (Razorpay TokenHQ or Stripe's network-token flow) — never build or reuse your own card-storage table, even encrypted, for anything beyond the ≤4-day settlement window.

Sources: [RBI CoFT mandate & Oct 2022 deadline – SISA/Federal Bank/Ground Labs](https://www.sisainfosec.com/blogs/rbi-tokenization-circular-update-the-what-why-and-how/), [Razorpay TokenHQ – Razorpay Blog](https://razorpay.com/blog/razorpay-token-hq-card-tokenisation-solution/), [Consent + AFA requirement – Razorpay Docs](https://razorpay.com/docs/payments/optimizer/tokenisation/), [Stripe India network tokenisation FAQ](https://support.stripe.com/questions/india-network-tokenization-faqs-and-upcoming-stripe-solutions), [Stripe cannot provide raw tokens to store – Stripe support](https://support.stripe.com/questions/guide-for-saving-cards-in-india)

---

## 5. TDS / TCS for a marketplace collecting on behalf of organizers

This is the area with the most direct P&L and settlement-waterfall impact — **two separate withholdings**, one under Income Tax and one under GST, both landing on the platform as the "operator."

### 5.1 Income Tax — Section 194‑O TDS

- Applies because the platform is an **"e-commerce operator"** facilitating sale of services (ticket admission) through its **"digital or electronic facility"** on behalf of **"e-commerce participants"** (the organizers).
- **Current rate: 0.1%** of the **gross amount** paid/credited to the organizer (this includes the full ticket price, not just the platform's commission) — reduced from the original 1% effective **1 October 2024**.
- **Applies to the full invoice/gross value** — product price plus any convenience/booking fee bundled into what the buyer paid, not just the platform's cut.
- **Small-organizer exemption**: **resident individuals/HUFs** with **gross sales ≤ ₹5 lakh in the financial year** are exempt from 194‑O TDS — **provided they've furnished PAN/Aadhaar** to the platform. All other entity types (companies, firms, trusts) have **no turnover-based exemption** — 194‑O applies from rupee one.
- **No-PAN penalty rate**: if the organizer hasn't furnished a valid PAN, TDS jumps to **5%** instead of 0.1%.
- **Mechanics**: the platform withholds this before crediting the organizer (i.e., it comes out of the Route/payout amount, not billed separately), deposits it with the government, and issues **Form 16A** to each organizer as TDS proof (organizer then claims credit against their own income-tax liability).
- **Case-law nuance worth knowing**: a platform is only the "operator" liable for 194‑O if it actually **owns/operates/manages** the digital facility — a party that merely subscribes to/uses someone else's system (e.g., a travel agent using an airline's reservation system) is not itself liable (*Riya Travel* ruling). For a ticketing platform that builds and runs its own checkout, this exception doesn't help you — you are squarely the operator.

Sources: [194‑O overview & rate history – Terra Insight](https://www.terra-insight.com/insights/section-194o-tds-0-1-percent-current-rate-history-india/), [₹5L individual/HUF exemption, 5% no-PAN – multiple 2026 sources], [Riya Travel case – ClearTax](https://cleartax.in/s/section-194o), [Razorpay 194-O automation – Razorpay/RazorpayX](https://razorpay.com/learn/section-194o-tds-for-e-commerce-businesses/)

### 5.2 GST — Section 52 TCS

- Every **e-commerce operator** that collects the consideration for a taxable supply made *through* it by another supplier must **collect tax at source (TCS)** and deposit it with the government.
- **Current rate: 0.5%** of the **net value of taxable supplies** (i.e., net of returns/cancellations) — reduced from 1% effective **10 July 2024**. Structured as **0.25% CGST + 0.25% SGST** for intra-state, or **0.5% IGST** for inter-state.
- **Filing**: the ECO reports and remits collected TCS via **GSTR-8**, due by the **10th of the following month**.
- **Organizer's credit**: the organizer sees the TCS credited to their **electronic cash ledger** and must accept/reconcile it via the **"TDS and TCS Credit Receivable"** function on the GST portal to actually use it against their output liability.
- **Practical friction with unregistered organizers**: TCS credit mechanics assume the supplier has a GSTIN to credit against. Combined with the Notification 65/2017 registration exemption (§1.9), an unregistered small organizer creates a genuine reconciliation gap — reinforce the "get a GSTIN before your first payout" onboarding requirement from §1.9 to avoid this.
- **Distinct from Section 9(5)**: conference/event admission is **not** one of the services (cab, hotel-below-threshold, housekeeping, restaurant) where the ECO itself becomes deemed-supplier and pays the *full* GST as if it made the supply. For ticketing, the organizer remains the supplier of record and the platform's GST obligation is limited to the **1% TCS withholding + its own commission invoice's GST** — a materially lighter compliance load than, say, running a food-delivery or cab marketplace.

Sources: [Section 52 TCS rate & mechanics – GSTHero](https://gsthero.com/blog/tcs-on-gst-for-e-commerce-operators-applicability-and-rates/), [0.5% rate from July 2024 – Patron Accounting](https://www.patronaccounting.com/blog/tcs-section-52-ecommerce-gst-explained), [s.9(5) vs s.52 scope – Cashflo](https://www.cashflo.io/magazine/section-9-5-vs-section-52-of-cgst-act-e-commerce-operators)

### 5.3 Combined settlement waterfall (what actually happens to ₹1,000 of ticket revenue)

For a ₹1,000 (GST-inclusive) ticket sold by an organizer registered in the venue's own state:

1. Buyer pays ₹1,000 via UPI/card → lands in the PA's escrow account against the platform's merchant ID.
2. Taxable value = ₹1,000 ÷ 1.18 ≈ **₹847.46**; CGST + SGST @9%+9% ≈ **₹152.54** — this GST liability belongs to the **organizer**, who must remit it via their own GSTR-3B (the platform doesn't pay this on the organizer's behalf, it just doesn't touch it).
3. Platform's own commission (say 5% + GST on the commission, invoiced by the platform to the organizer) is netted out — e.g., ₹50 + ₹9 GST = ₹59, retained by the platform.
4. **Section 52 TCS (0.5% of net taxable value)** ≈ ₹847.46 × 0.5% ≈ **₹4.24** — withheld by the platform, remitted via GSTR-8, credited to the organizer's cash ledger.
5. **Section 194‑O TDS (0.1% of gross ₹1,000)** = **₹1.00** — withheld by the platform, deposited, Form 16A issued to the organizer.
6. **Net amount actually settled to the organizer's Route Linked Account / bank**: ₹1,000 − ₹59 (platform commission) − ₹4.24 (TCS) − ₹1.00 (TDS) ≈ **₹935.76** — and the organizer separately owes ₹152.54 in GST to the government out of what they've now received (TCS/TDS withheld are *advance credits* against their liabilities, not a reduction of their GST due).

Build the settlement/payout ledger to show organizers this full breakdown line-by-line — "gross sale → platform fee → TCS → TDS → net payout, plus GST liability you still owe separately" — otherwise reconciliation support tickets will dominate.

---

## 6. Recommended end-to-end architecture

1. **Payments infra**: build on an RBI-authorised PA (Razorpay, given existing tooling) — never collect funds into the platform's own bank account as the primary flow. Use **Razorpay Route** with one **Linked Account per organizer** for ticket-sale settlement; use **RazorpayX Payouts** (bank or VPA) for sponsorship and irregular disbursements.
2. **Checkout**: default to **UPI Intent** on mobile, **dynamic UPI QR** on desktop, cards with **network-tokenised** save-for-later via the PA's tokenisation product (Razorpay TokenHQ/Optimizer or Stripe's India network-token flow). No manual-VPA Collect as the primary mobile path (aligns with the NPCI 2026 direction).
3. **Organizer onboarding**: collect PAN + bank-account-in-business-name + (strongly encourage/require) GSTIN even where Notification 65/2017 would technically exempt a small organizer, plus entity type (individual/proprietorship/company/trust/society) to correctly determine Section 9(5)/RCM/TDS-exemption treatment. Run Account Validation (penny-drop) before the first payout. Flag at listing-creation time if the event's venue state differs from the organizer's registered GST state, and prompt for Casual Taxable Person registration guidance if so.
4. **Invoicing**: the **organizer**, not the platform, is the legal supplier and invoice-issuer for the ticket (SAC 998596, 18%, CGST+SGST/IGST determined by venue location per §1.2). The **platform** separately invoices the **organizer** (B2B) for its own commission (SAC 998599, 18%). Generate a **Rule 50 receipt voucher** at the moment of every advance/early-bird sale, and a full Rule 46 tax invoice by/at the event. Route B2B group-registration invoices through an IRP e-invoicing integration only for organizers who both (a) exceed the ₹5 crore turnover threshold and (b) are invoicing a business GSTIN — most B2C ticket sales need no IRN at all.
5. **Withholding**: auto-deduct **0.1% Section 194‑O TDS** (gross) and **0.5% Section 52 GST TCS** (net taxable value) at time of settlement, before crediting the organizer's Linked Account; file GSTR-8 monthly and issue Form 16A; expose a transparent per-order settlement breakdown to organizers (§5.3).
6. **Sponsorship**: route through the same Route/Payout rails; determine GST treatment (forward charge if sponsor is a body corporate post-Jan-2025, RCM on the organizer otherwise) based on sponsor entity type captured at deal-creation time.
7. **Compliance monitoring**: the ₹5cr→₹2cr e-invoicing threshold change, GST rate-slab reclassifications (post GST 2.0), and NPCI's UPI Collect phase-out are all live/moving targets — build these as configuration values (not hard-coded constants) and review quarterly against fresh GST Council/RBI/NPCI notifications.

---

## 7. Open risks / things to re-verify before shipping

- **E-invoicing threshold**: confirm current live threshold (₹5cr vs a possible ₹2cr change) at implementation time — this was actively moving as of the research date.
- **TDS/TCS rate changes**: both 194‑O (0.1%) and Section 52 TCS (0.5%) have been cut once already in the last two years; re-check current rates before hard-coding.
- **NPCI UPI Collect restrictions**: the "Feb 2026" P2M Collect phase-out referenced in trade press should be confirmed against an actual NPCI circular before you remove Collect-flow support entirely — trade-press dates for NPCI mandates sometimes slip.
- **PA authorisation risk**: if the platform ever wants to hold funds for materially longer than the PA's settlement cycle (e.g., to fund escrow-style "money-back guarantees" beyond normal refund windows), that likely needs its own legal review — don't assume Route/Payouts cover every custom fund-holding pattern.
- **GST 2.0 slab volatility**: the Sept 2025 rate rationalisation (5%/18%/40%) is recent; watch for further reclassification of "events/entertainment" SAC codes, since the Council has shown willingness to move whole categories between slabs with short notice.
