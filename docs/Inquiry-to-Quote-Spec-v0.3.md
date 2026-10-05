# Inquiry to quote workflow

Breeze Block Canada | Draft specification v0.3 | October 4 2026

Supersedes v0.2. This revision records confirmed trade and pallet rules, Freightcom rate selection and optional booking, Google Workspace access, and bring your own LLM integration. Commercial defaults below were chosen under Kevin’s instruction to use judgment; they are editable and are not claims about existing store configuration.

This application turns incoming sales emails into organized conversations, reviewed replies, freight priced quotes, and Shopify payment requests. Kevin manages the entire conversation from one queue. Agents prepare work; Kevin controls customer communications and commercial commitments.

## Purpose and boundaries

The first release supports one business, one operator, the existing sales inbox, web form emails, HubSpot, Shopify, and Freightcom or ClickShip. Proposed default scope is Canadian orders in CAD, with English and French replies. International orders and unusual requests enter manual review until their rules are configured.

Shipment booking from the application is in scope if supported by the Freightcom API and account. Returns, refunds, broader fulfillment automation, marketing campaigns, and autonomous customer sends are outside scope. After verified payment, the workflow supports explicit booking and a fulfillment handoff; paid and booked remain separate states.

## Application architecture and technical decisions

### Application surface

Build a private standalone web application, accessible through a bookmarked URL with operator authentication. The main interface will not be embedded in Shopify, Gmail, or HubSpot. Integrations may require app registrations or installations for API authorization, independently of where the UI lives. The domain and hosting provider remain undecided.

The first release serves Breeze Block Canada and one operator, Kevin. A responsive desktop-first interface should remain usable on a phone for reviewing and replying. Multi-tenant SaaS, public app distribution, and full companion extensions are outside the initial scope.

### Selected stack

| Layer | Decision | Purpose |
| --- | --- | --- |
| Application | Ruby on Rails, stable supported release pinned at project initialization | One full-stack application and repository |
| Database | PostgreSQL | Workflow records, quote snapshots, external IDs, and audit history |
| UI | Rails views with Hotwire, Turbo, and Stimulus | Queue, conversation workspace, forms, and progress updates |
| Styling | Tailwind CSS | Consistent responsive layouts |
| Jobs | Active Job with Solid Queue | Parsing, synchronization, rates, PDFs, and external actions |
| Files | Active Storage with private object storage in production | Customer attachments and immutable quote PDFs |
| AI | Configurable LLM integration with operator-supplied credentials and provider adapters | Classification, extraction, drafted replies, and possible acceptance detection |
| Tests | Rails business-rule and integration tests plus browser tests | Verify pricing, approvals, state changes, and failure recovery |
| Deployment | Managed hosting supporting Rails web and worker processes and PostgreSQL | Keep operations manageable for one owner |
| Development | Codex CLI against the local Git repository | Implement and review changes using the selected Rails conventions |

Rails and Solid Queue are confirmed choices. The LLM is a configurable integration, not a fixed provider choice. The first adapter, hosting vendor, object-storage vendor, authentication implementation, and exact Ruby and gem versions remain to be selected. The table records the discussed stack direction; it does not imply those services are provisioned.

### Queue infrastructure

Use Solid Queue for the first release, with a dedicated worker process running the same application code as the web process. Redis and Sidekiq are not initial dependencies. This is a simplification for the expected workload, not a requirement to avoid them permanently.

Configure Solid Queue explicitly for PostgreSQL, including its queue database or connection and migrations. Keep deployment configuration and worker health checks in the repository. Closing the operator's browser must not stop ingestion, background processing, or reconciliation. Local development must also start a worker so the job paths are exercised.

### Workspace layout

- Left: searchable and filterable conversation queue, with status, age, and next action.
- Centre: selected conversation, chronological email history, attachments, and reply editor.
- Right: customer and project details, extracted fields, missing information, and product selections.
- Quote view: line items, pricing evidence, packing inputs, freight options, totals, PDF preview, and revision history.
- Settings: integration status and approved pricing, freight, packing, and quote policies.

Use Turbo updates to refresh queue rows and job status. Add focused Stimulus behaviour where required. React and a separate frontend application are not part of the first release; introduce them only if a concrete interaction warrants the additional complexity.

### Integration boundaries

Keep external services behind small Ruby clients with clear request and response objects. Controllers validate operator input and call workflow services; background jobs invoke those services. Keep pricing, quote validation, and state transitions independent of provider-specific payloads.

| System | Responsibility | Integration approach |
| --- | --- | --- |
| Google Workspace Gmail | Read sales conversations and send approved replies | Internal OAuth app connected to kevin.sherman@breezeblock.ca; send as sales@breezeblock.ca |
| HubSpot | Contacts, companies, deals, and sales status | API client with stored external IDs and retryable synchronization |
| Shopify | Catalog, inventory, draft orders, invoices, and verified payment state | Server-side Admin GraphQL client and verified webhooks where applicable |
| Freightcom | Retrieve freight rates and optionally book shipments | API credentials to be obtained; show three cheapest suitable results; explicit booking confirmation |
| PDF renderer | Render the approved quote snapshot | Generate branded quote PDFs inside Rails; no external PDF service required initially |
| LLM integration | Interpret inquiry content and draft text | Provider adapters, operator-supplied credentials, selected model, capability checks, and schema validation |

API registrations, permissions, credentials, limits, and webhook capabilities must be validated before implementation of each live integration. Native Shopify invoice emails remain sent by Shopify, with their status recorded in the app.

### AI execution and deterministic rules

Do not add a separate Python service or a general autonomous-agent framework for the initial workflow. Ruby can call the model API directly. Classification, extraction, drafting, and acceptance detection are bounded tasks. Validate outputs before updating workflow data; malformed or uncertain results enter review.

Application code owns pricing arithmetic, packing calculations, authorized discounts, quote validity, approval checks, and external write permissions. Model output cannot authorize email sending, change pricing policies, create an invoice send, or bypass review. All AI operations run in jobs with appropriate timeouts and bounded retries.

### Reliability and operations

Use database constraints and locking where needed to enforce one active operation for each reviewed draft or accepted quote version. Solid Queue does not provide exactly-once external effects: stable operation IDs, persisted results, and provider reconciliation remain necessary for email sends, Shopify draft creation, and freight booking.

Deploy web and worker processes together from the same release and manage schema changes deliberately. Provide private file access, encrypted integration credentials, structured logs, visible failed jobs and integration status, and database backups with a documented restore path. Do not expose customer message bodies or credentials in ordinary logs.

### Coding conventions

Maintain an `AGENTS.md` containing the architecture, commands, review rules, and integration boundaries. Pin Ruby and dependency versions and use documentation matching them. Prefer conventional Rails models, controllers, views, jobs, and small service objects over an elaborate framework within the framework.

Agents must run meaningful checks for changes to pricing, approval, duplicate prevention, and external actions, and inspect the UI in a browser when changing its behaviour. Use fake providers in development and automated tests; live emails and payment requests require explicit operator actions.

### First working slice

Start with a running Rails application, PostgreSQL, Solid Queue, operator login, and the queue and conversation screens. Demonstrate an inquiry entering the queue, an editable draft appearing, and the approved reply being sent through a fake email provider. Then connect the real inbox and AI provider behind the same boundaries. This separates proving the workflow from resolving external access.

## Integration access and ownership

### Ownership and environments

Kevin is the administrator or superuser of Google Workspace, Shopify, HubSpot, and the other relevant business accounts. Register integrations under business-owned accounts. The Rails app needs its own authorization; connections in this chat and Codex CLI login do not confer runtime access.

Keep development and production credentials separate. Use fake providers and a Shopify development store for write tests; use provider sandboxes where available. Production sends and bookings require explicit operator actions. Show each integration’s Connected, Needs authorization, Error, or Disabled status, its last successful operation, and a reconnect or credential-rotation action.

### Google Workspace Gmail

- Mailbox: `kevin.sherman@breezeblock.ca`.
- Sales alias and outbound identity: `sales@breezeblock.ca`.
- Web form: Shopify’s current contact form, received through the same mailbox.
- Authentication: internal OAuth application in a Cloud project associated with the Workspace organization; Kevin authorizes his mailbox with offline access.
- Initial Gmail permissions: `gmail.readonly` and `gmail.send`. Store drafts in Rails rather than Gmail; do not request mailbox modification, deletion, or domain-wide delegation for this workflow.

Verify manually that the sales alias is an accepted Gmail Send mail as identity before enabling outbound sends. Configure it in Gmail rather than granting settings-management permissions. Send approved sales replies with the sales From and Reply-To identity and retain thread headers.

Begin with a configurable one-minute polling interval and persistent synchronization cursors; prevent overlapping polls and recover gaps after downtime. Push notifications can be added later. Deduplicate inbound and sent messages using provider IDs.

Discover sales messages using recipient headers and the observed contact-form format, then follow known thread IDs and explicit conversation references. Reply-address and form fields identify the actual customer; notification sender identity alone is insufficient. Replies directly addressed to Kevin and operator replies sent from Gmail must still join tracked sales conversations. Ambiguous unrelated messages enter operator review before import.

Gmail read permission covers the underlying mailbox, not only the alias. Application filtering is a processing boundary, not an OAuth restriction. Do not import or pass unrelated mail to the LLM. A dedicated sales mailbox remains an optional future way to narrow authorization. Avoid deploying an external OAuth app left in Testing as the production background connection because refresh-token expiry can interrupt it.

### HubSpot

Use a business-owned private integration for the current single account, through the supported HubSpot app-registration mechanism. Limit permissions to the needed contact, company, deal, association, and activity operations. Validate the actual scopes and pipeline IDs during setup; never give the app Kevin’s administrator credentials.

The app owns its external references, quote status, and explicitly configured synchronization fields. Preserve manually edited customer data and deal fields unless an approved mapping says otherwise. Store stable IDs and recover failed synchronization without blocking the queue. Public multi-account OAuth distribution is deferred.

### Shopify

Authorize a store-specific app using the currently supported Shopify setup. Use the Admin GraphQL API and verify the exact scopes needed for catalog, inventory, customers, draft orders, orders, and payment observation. App installation for API access does not make the UI a Shopify embedded app.

Validate supported price/discount behaviour, inventory semantics, tax calculation, invoice sending, and event subscriptions in development before production. Do not request refunds or unrelated administration capabilities. Approved invoice emails originate from Shopify; store their status without sending duplicate Gmail messages.

### Freightcom

Kevin currently uses the website and will obtain API credentials. Confirm rate access, pallet support, accessorials, currency, tax and surcharge treatment, rate identifiers/expiry, test facilities, and shipment-booking capability. Compare an API result with a website quote for identical inputs before using it commercially.

Enable rates first; activate booking only after validation. Use separate rate and booking credentials if supported; otherwise enforce action separation in application code. Never assume rate access implies booking access.

### Local quote PDF generation

Generate branded PDFs in Rails from the immutable approved quote snapshot and store them privately with Active Storage. This removes a mandatory external PDF account and transmission of customer details to a PDF service. Select the PDF library during implementation; Invoice Generator remains an optional future integration.

### Bring your own LLM

Treat the LLM like any other integration. Settings allow the operator to configure a supported provider, encrypted credentials, and model. Build a common Ruby interface for classify_inquiry, extract_fields, draft_reply, and detect_acceptance, with provider adapters handling transport and response formats.

Implement one adapter end to end first and keep additional providers pluggable. Do not claim universal compatibility. During setup, run a small synthetic capability test and validate task schemas; structured-output, context limits, and tool support differ by provider. No tools with sending or booking authority are required for the initial bounded tasks.

Keep all credentials server-side, encrypted at rest and excluded from Git and logs. Store provider, requested and returned model identifiers where available, prompt/schema version, usage and cost when available, timestamps, validation status, and errors for each run. Record or reference the relevant input snapshot in protected storage, not ordinary logs. Set configurable token budgets, timeouts, retry limits, and per-connection spending controls where supported.

Switching provider changes future tasks, not historical results or deterministic business rules. Capture the connection/configuration version for each queued task; if it is disabled or revoked, pause and require explicit rerouting. Do not silently fall back to another provider, since this changes where customer data is sent. Send only the relevant sales context; pricing, approval, and external-action authorization remain owned by Rails.

Provider API charges are separate from Codex CLI or ChatGPT subscriptions. The operator supplies runtime credentials. Initial scope is one business and operator; this design does not introduce multi-tenant account isolation or public SaaS distribution.

## Workflow overview

### End to end sequence

- Receive an email from the web form or directly in the sales inbox.
- Parse, categorize, and associate it with a customer conversation and project.
- Create or update a potential lead in HubSpot and prepare any missing information questions.
- Show the draft in the queue; Kevin edits, approves, and sends it.
- Process each customer reply within the same conversation.
- When a quote is requested and its inputs are complete, fetch product pricing and prepare freight inputs.
- Retrieve shipping options, select a service, calculate the quote, and generate its PDF.
- Queue the quote email and attachment for Kevin to review and send.
- Record acceptance of a specific quote version and validate current terms.
- Create a Shopify draft order; Kevin reviews and sends its invoice and payment link through Shopify.

### Core rule

No customer email is sent without Kevin approving the exact content and attachments. Shopify invoice sending is also an explicit action. Automatic CRM updates and preparation jobs are allowed, with visible history and a correction path.

## Intake and conversation handling

### Receive and normalize

Use the inbox provider API and a subscription or polling process. Save the provider message ID, thread ID, sender, recipients, reply address, subject, received time, body, and attachment metadata. Resolve web form customer details from its fields rather than treating the form notification sender as the customer. Provider IDs prevent duplicate intake.

### Agent extraction

Extract intent, language, contact and company, customer type, project name, requested patterns, size, colour, quantities or coverage area, destination, delivery deadline, pickup preference, and delivery requirements. Every extracted field retains its source message, confidence, and whether it was explicitly stated or inferred. Unknown values stay unknown.

Categories: new sales inquiry, quote request, existing quote discussion, samples or technical resources, existing order support, supplier or administration, spam, and uncertain. Uncertain messages enter review. Support requests are routed visibly without automatically creating new sales deals.

### Create or update HubSpot records

Match contacts by normalized email and retain the HubSpot ID. Create a contact only when a usable identity is available. Associate a company when confidently identified; avoid guessing associations from generic email domains. Use a project specific deal for qualified quote opportunities, not a new deal for every message. Proposed qualification: explicit product or project interest with an identifiable contact.

Synchronize category, project summary, next action, owner, and linked quote status. Repeated events update the existing records. An unavailable CRM creates a visible retry task and does not discard the inquiry.

### Draft and continue the conversation

The agent reads the full relevant thread and existing structured fields, then asks only unanswered questions needed for the next step. General inquiries can receive helpful drafts before a complete delivery address is known. Drafts follow the customer language and approved product information; technical claims, discounts, stock promises, and delivery commitments require configured evidence or manual review.

Replies retain email threading headers. Match new subjects using customer and quote references where possible; ambiguous matches enter review. Allow multiple projects per contact and deliberate split or merge actions. Replies sent directly from the inbox must also synchronize into the application.

### Untrusted input

Customer messages and attachments are data, never instructions to the agent to change rules, expose credentials, or send messages. Attachments can be inspected in review; automatic attachment interpretation can be added later.

## Queue and operator experience

### Queue views

Show Needs review, Waiting for customer, Ready to quote, Quote preparing, Quote review, Awaiting acceptance, Accepted awaiting invoice, Awaiting payment, Paid, Ready to book, Booked, and Exceptions. Each row shows customer, company or project, intent, last activity, age, next action, missing information, and estimated deal value when known. Sort actionable work by age and allow search and filtering.

### Conversation workspace

Provide the complete email thread, attachment previews, extracted fields with source evidence, HubSpot links, product selections, quote history, and current draft. Keep internal notes separate from customer copy. The operator can correct fields, recategorize, edit recipients, regenerate a draft, save, send, request a quote, record acceptance, or close the conversation.

### Approval and sending

A send review includes To, CC, subject, body, and exact attachment previews. Sending locks the reviewed draft version. Editing fields that affect a quote marks its PDF and email draft stale and requires recalculation. A newly received customer message invalidates an older pending approval until reviewed.

Only one active send operation may run for a draft version. Save the provider message ID when sending succeeds. On a timeout with an uncertain result, reconcile with the provider before retrying; never blindly send a second copy. Failed sends stay visible with a recoverable status.

### Proposed conversation states

- Received → Needs review or Waiting for information after an approved follow up is sent.
- Ready to quote → Preparing quote → Quote review → Awaiting acceptance after successful sending.
- Acceptance detected → Acceptance review → Accepted → Draft order review → Awaiting payment.
- Verified payment → Paid → Ready to book when goods and shipment details are confirmed; explicit booking → Booked. Rejection or operator action → Closed.
- Any processing stage can enter Exception without losing its previous state or customer history.

Conversation state, draft approval state, and background job state are stored separately. A failed HubSpot sync must not make a successfully sent quote appear unsent. Manual messages and corrections remain possible at every stage.

### Reminders

Flag unanswered inquiries and waiting conversations using configurable timers. Follow up drafts may be suggested, but are not sent automatically. Record last customer response and last operator response separately.

## Commercial policies and packing

### Confirmed trade policy

| Rule | Confirmed decision |
| --- | --- |
| Product discount | 25% off current retail product prices |
| Minimum | Approximately 30 square feet of combined coverage; near or below minimum requires operator judgment |
| Mixed patterns | Accepted |
| Pallet requirement | Full or partial pallet shipping; no requirement to purchase a full pallet |
| Eligible customers | Architects, designers, builders, landscapers, dealers, and trades such as masons |
| Eligibility | Kevin manually approves; agent classification cannot grant a discount |
| Exceptions | Requested project or customer discounts are considered case by case |

Replace the old 60-block minimum with coverage-based qualification. Calculate area from maintained coverage per variant; do not hard-code one unit threshold across sizes. Record approval, approver, time, and any discount exception. Existing approval may be reused for a contact unless revoked, while order minimum eligibility is evaluated for each quote. Mixed size and colour packing compatibility still requires review where unconfirmed.

### Confirmed pallet presets

| Preset | Footprint | Product load height | Pallet height allowance | Submitted total height | Small capacity | Large capacity | Tare allowance |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Half pallet | 40 × 40 inches | 20 inches | 4 inches | 24 inches | 200 units | 52 units | 10 lb |
| Full pallet | 40 × 40 inches | 40 inches | 4 inches | 44 inches | 400 units | 104 units | 10 lb |

Per-pallet submitted weight is the sum of assigned block weights plus 10 lb. Apply the allowance to each pallet, including the partial last pallet. Existing product weights must be located and their units and packaging basis verified. Never send a rate request with missing or guessed product weights.

For one block size, pack into full-capacity pallets and use a half preset for the remaining quantity when it fits; otherwise use a full preset. Do not round the purchased quantity up to fill a pallet. These are editable shipping presets rather than measured guarantees for every load.

For mixed small and large blocks, a proposed capacity estimate is small_count / 400 + large_count / 104 per full pallet; half capacity is 0.5. For example, 100 small plus 26 large estimates a half pallet. This rule has not been physically confirmed: show the suggested allocation and require operator confirmation of mixed packing before rate requests. Show dimensions, counts, and weights for every pallet and allow overrides.

### Configurable commercial defaults

Kevin delegated these defaults rather than specifying them individually. They must be visible and editable in settings and on relevant quotes.

| Area | Initial default |
| --- | --- |
| Customer freight charge | Pass through the selected total carrier charge; no automatic handling charge or markup |
| Rate suitability | Include all required delivery services; compare totals in the quote currency on the same tax basis |
| Liftgate | Include when the customer confirms no unloading equipment; if unknown, obtain confirmation before a firm quote |
| Site type and access | Ask when unknown; do not infer commercial status from a company name |
| Quote validity | 14 calendar days for product pricing, subject to any shorter freight expiry; display both where they differ |
| Freight with no stated expiry | Refresh before converting an accepted quote to a payment invoice, and again before booking |
| Stock | Quote only verified available quantity automatically; shortages and custom lead times enter review |
| Reservation | A quote does not reserve stock; acceptance triggers a stock recheck. No custom reservation mechanism initially |
| Payment | Full payment before shipment booking or release; exceptions require recorded operator approval |
| Manual payment | Verify receipt and record it in Shopify before treating the order as paid |
| Booking | Explicit operator action after verified payment and confirmation that the goods are ready |
| Pickup | Zero freight charge, confirmed pickup instructions, and full payment before release |
| Samples | Separate sample pricing and parcel packing; the 30 sq ft trade minimum does not apply |

Revalidate stock immediately before invoice send and reconcile any inventory issue on payment before booking. Do not imply that paid goods are reserved unless Shopify’s configured inventory behaviour has been verified. Disclose availability subject to confirmation rather than promising unknown lead times.

For samples, use configured sample products/prices and actual parcel dimensions and weights. Do not automatically apply the 25% block discount, waive a sample charge, or use pallet presets. Any trade sample incentive requires an explicit configured rule or approval. If sample packing is missing, route to manual preparation.

Apply taxes using the store’s validated configuration. Shopify totals must match the approved quote before invoice sending. Differences in provider tax treatment must not cause freight tax to be charged twice. Discount or freight exceptions record the original amount, approved amount, reason, and approver.

## Shipment booking

Booking is conditional on verified Freightcom API capability and account authorization. Keep the rate-request and booking actions separate. Until booking access is confirmed, expose manual website handoff and allow an externally obtained booking reference to be recorded.

The booking review shows the paid order, packed goods, origin and destination, contact details, current rate and services, ready date, pickup window, and any provider-required fields. Refresh or validate the chosen rate according to provider rules. If booking cost exceeds the customer’s accepted freight charge, require Kevin to choose whether to absorb the difference or obtain an approved customer adjustment; never automatically charge the customer again.

An explicit Confirm booking action creates one persisted booking operation. Save the provider booking ID, carrier, cost, tracking details, and shipping documents when available. On an uncertain timeout, mark Booking status unknown and reconcile with the provider before retrying. If reconciliation is unavailable, require manual verification. Repeated jobs must not create duplicate bookings.

Use separate shipment states: Not ready, Ready to book, Booking, Booked, Booking failed, and Booking status unknown. Booking does not mean shipped or delivered and does not automatically mark Shopify fulfillment complete. Broader fulfillment and returns remain outside scope.

## Quote preparation and freight pricing

### Minimum quote inputs

Require resolved product variants, quantities, customer pricing eligibility, currency, destination sufficient for reliable freight and tax calculation, delivery or pickup, and any accessorial requirements. Obtain the full delivery address before a firm delivered quote where required by the provider. For freight, confirm residential or commercial location, unloading equipment, liftgate, appointment needs, and access restrictions.

If a customer supplies area rather than count, use maintained coverage data and configured rounding or case rules. Show the calculation and any allowance; do not add waste or round to pallets silently. Ask for clarification when product names or quantities are ambiguous.

### Product pricing and availability

Shopify is the proposed source for variants, SKUs, current retail prices, and available inventory. A maintained policy configuration supplies approved trade discounts, minimums, packing rules, and exceptions. Apply the confirmed trade policy in Commercial policies and packing; commercial exceptions require Kevin’s approval. Save a pricing snapshot, its source, and retrieval time.

Availability is checked separately from price. Insufficient stock, custom products, unclear eligibility, and unsupported requests require Kevin to resolve lead times or terms. A quote does not reserve stock unless a reservation process is explicitly configured.

### Freight input and selection

Build a packing plan from maintained product weights, actual packed pallet dimensions, pallet tare, capacity, and compatibility rules. Product dimensions alone are not shipping dimensions. Store the origin, destination, pickup date if required, package count, total weights, units, and selected delivery services.

Request rates through the confirmed Freightcom account API. ClickShip can remain a manual source until account access and rate parity are verified. Retain provider request and rate IDs, carrier, service, total cost, surcharges, transit estimate, request time, and expiry when supplied. Show the top three cheapest suitable results sorted by comparable total carrier charge. Suggest the cheapest suitable result; Kevin selects or changes the service before sending. If fewer than three suitable results exist, show the available results and explain the shortfall.

If the integration is unavailable or no rate fits, allow Kevin to enter a documented manual freight quote with provider, amount, service, date, and validity. Never substitute a guessed cost or silently omit freight. Rate retrieval does not book transportation.

### Quote calculation

Use deterministic calculations for quantities, discounts, shipping charges, tax, and totals. The agent explains results but cannot invent prices or arithmetic. Keep carrier cost separate from customer freight charge; any markup or handling fee needs an explicit configured rule. Tax treatment and rounding must be validated against the store configuration before firm quotes are sent.

## Quote documents and Shopify payment

### Generate and review the quote

Create a versioned quote record with customer, project, SKUs, quantities, unit prices, discounts, freight, tax treatment, total, currency, availability assumptions, expiry, and commercial terms. Generate a document clearly titled Quote rather than Invoice. Generate a branded quote PDF inside Rails from the validated snapshot. Invoice Generator is an optional future alternative, not a required integration. Store the generated PDF through Active Storage in private object storage for history and retries.

Queue an email containing the PDF and a concise summary. Show the full pricing breakdown and selected freight service to Kevin. Any edit to products, quantities, discount, destination, shipping, or tax produces a new quote version. Sent versions remain immutable. Apply the configurable validity and refresh defaults in Commercial policies and packing, retaining any provider expiry separately.

### Record acceptance

Detect apparent acceptance and show the supporting customer message. Kevin confirms acceptance of the specific sent version; alternatively he may record verbal acceptance with a note and time. Conditional acceptance, a changed quantity, or an unclear quote reference returns to review. Acceptance is not payment.

Before conversion, verify quote validity, stock, destination, freight validity, and agreed pricing. Changed terms require review and, where material, a revised quote and renewed acceptance. Do not silently substitute current Shopify prices for the accepted snapshot.

### Create the Shopify draft order

Create the draft with the correct customer, billing and delivery details, variant IDs, quantities, approved prices or discounts, shipping line, currency, and quote reference. Store its Shopify ID immediately. Ensure the approved commercial totals are reproducible through supported Shopify pricing behaviour; validate this in an integration test.

Compare line items, shipping, taxes, currency, and total with the accepted quote. Any discrepancy blocks invoice sending and enters review. Use a stable conversion key and stored external IDs to prevent duplicate draft orders. If creation times out, reconcile before retrying.

### Send the Shopify invoice and observe payment

Show a final review of the Shopify draft and invoice recipient. Kevin explicitly sends the invoice through Shopify. Record invoice send status and the payment link when available. Synchronize the send into the conversation history without sending a duplicate app email.

Use verified Shopify events plus reconciliation to observe conversion to an order and payment state. An order created with payment pending is not Paid. Full payment is the default. Manual payment is supported by recording and verifying the payment in Shopify; an email saying payment was sent does not establish payment. Partial payment and deposit arrangements require an explicit operator exception and do not unlock booking by default. Mark the deal won only on the configured verified payment event, then expose the order for fulfillment handoff.

### Provider capabilities and unresolved access

Shopify documents draft order creation and invoice sending. Freightcom advertises a shipping API, but account credentials, pallet support, included services, expiry, and rates matching the current workflow need validation. Local PDF generation requires no separate provider credentials. Any external renderer added later must be explicitly configured.

## Implementation scope and acceptance criteria

### Data and ownership

Store Conversation, Message, ExtractedField, ContactLink, ProjectDealLink, EmailDraft, QuoteVersion, PackingPlan, FreightRate, ShipmentBooking, DraftOrderLink, IntegrationConnection, LlmRun, Job, and AuditEvent records. The application owns workflow and quote snapshots; the inbox owns delivered messages; HubSpot owns CRM records; Shopify owns catalog and order or payment records; the freight provider owns returned carrier rates. Retain stable IDs across each integration.

Use Active Job with Solid Queue for parsing, synchronization, freight requests, PDFs, and order conversion. Apply bounded retries for safe operations and reconciliation for uncertain external writes. Require operator login, server side credentials, verified webhook signatures where supported, least privilege access, and private attachment storage. Retention and backup policies must be agreed before launch.

### Build sequence

- Foundation: standalone Rails application, PostgreSQL, Hotwire, Tailwind, Solid Queue worker, operator login, fake-provider workflow, and documented development commands.
- First: inbox ingestion, categorization, contact synchronization, conversation workspace, and reviewed sending.
- Second: product resolution, policy configuration, packing data, manual freight entry, deterministic quote calculation, and PDF review.
- Third: verified Freightcom rate integration, quote acceptance, Shopify draft conversion, invoice review, and payment reconciliation.
- Fourth: optional Freightcom shipment booking, booking reconciliation, shipping-document storage, and fulfillment handoff.

### Acceptance criteria

- A web form inquiry creates one conversation linked to the actual customer; reprocessing it creates no duplicate message or contact.
- A partial inquiry produces an editable follow up asking only necessary missing questions; nothing sends before approval.
- Customer replies and operator inbox replies appear in the same relevant project conversation.
- A complete quote shows source prices, packing inputs, selected freight, tax treatment, exact PDF, and matching total.
- Quantity or destination changes invalidate the old draft and produce a new quote version.
- Freight or CRM failure leaves recoverable work; no guessed freight or lost inquiry is sent.
- Acceptance of one version creates one Shopify draft; total mismatch blocks the invoice.
- Unknown send or creation outcomes reconcile before retry; repeated webhooks do not duplicate orders.
- Only verified payment marks the workflow paid; all operator decisions and external actions retain an audit trail.
- Trade eligibility is manually approved; a near-minimum mixed-pattern order is evaluated by coverage rather than the obsolete 60-block rule.
- A half pallet submits 40 × 40 × 24 inches and assigned block weight plus 10 lb; a full submits 40 × 40 × 44 inches, with tare applied to each pallet.
- Rates show up to three cheapest suitable results including required services; mixed-size packing requires confirmation.
- Inbox ingestion excludes unrelated mail while preserving direct-to-Kevin replies in tracked sales threads; sending uses the accepted sales alias.
- LLM connection tests reject incompatible output, credentials remain private, and provider changes never cause implicit cross-provider fallback.
- Booking requires verified payment, ready goods, and explicit confirmation; uncertain results reconcile before retry and do not duplicate shipments.

### Remaining setup and validation

The commercial rules, mail provider and identities, administrator ownership, Rails stack, and LLM integration architecture are settled. Remaining work is configuration and verification rather than repeating those choices:

- Choose hosting, object storage, domain, operator authentication, exact supported dependencies, PDF library, and first LLM adapter.
- Register and authorize Google, HubSpot, and Shopify connections; validate the sales send-as identity and actual form message structure.
- Obtain Freightcom credentials and verify rate/booking capabilities and rate parity.
- Locate product weights and coverage data; verify units and confirm mixed-size packing suggestions.
- Map HubSpot pipeline and fields and verify Shopify tax, inventory, payment, and accepted-price behaviour.
- Configure origin/pickup contacts, sample products and parcel packing, retention, backups, and production commercial defaults.

### Primary integration references

Shopify draft creation: https://shopify.dev/docs/api/admin-graphql/latest/mutations/draftOrderCreate

Shopify invoice sending: https://shopify.dev/docs/api/admin-graphql/latest/mutations/draftOrderInvoiceSend

Freightcom API overview: https://www.freightcom.com/shipping-api

Invoice Generator API: https://invoice-generator.com/developers

## Technical references

- [Rails getting started](https://guides.rubyonrails.org/getting_started.html)
- [Rails Active Job and Solid Queue](https://guides.rubyonrails.org/active_job_basics.html)
- [Hotwire](https://hotwired.dev/)
- [Rails Active Storage](https://guides.rubyonrails.org/active_storage_overview.html)
- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)

## Integration access references

- [Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes)
- [Gmail send-as aliases](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs)
- [Google OAuth app audience](https://support.google.com/cloud/answer/15549945)
- [Google OAuth token lifecycle](https://developers.google.com/identity/protocols/oauth2)
