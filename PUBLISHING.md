# Sleepy Llamas publishing readiness

Reviewed November 16, 2026. The three service pages and SEO work are implemented
in the website source. Publication uses the existing GitHub Pages workflow;
Supabase activation is deferred by the owner.
Approved rates remain in `src/config/services.ts`.

## What is ready

| Area | Implemented |
| --- | --- |
| Newborn and postpartum | `/newborn-postpartum-consultations/`: paid consultation, first-weeks option, specific written deliverables and bounded follow-up |
| Caregiver coaching | `/nanny-caregiver-coaching/`: household routines, children of different ages, caregiver participation and a shared care guide |
| Home visits | `/first-days-home-visit/`: visit priorities, practical care and household setup, written handoff and extra-visit inquiry context |
| Discovery | Service links in navigation, cards and footer; related-page links; XML sitemap |
| Search and sharing | Unique titles/descriptions, consistent canonical and social URLs, brand share image, Organization/Person/Service/Breadcrumb data |
| Inquiry flow | Default email-first mode: validated details open a draft for the parent to review and send. Optional online mode retains timeout, retries and strict saved receipts |
| Deployment guard | Email mode needs no backend. Online mode requires public-key/configuration and read-only API-schema checks. Both run built-page/link/sitemap checks |

The pages use a shared layout with distinct research-informed content. They do not
claim clinical treatment, professional nanny certification, instant booking,
unlimited messaging, or guaranteed outcomes. Free fit calls are separate from paid
planning. A local saved-inquiry event hook contains only the service identifier;
no external analytics integration was installed.

## Publishing now: email-first

The owner requested publication with Supabase deferred. The default
`PUBLIC_INQUIRY_MODE=email` opens a prepared email draft after validation. Parents
review and send it themselves. Nothing is saved online, no saved-request success
is shown, and the overnight calendar is hidden in favor of a direct care inquiry. It does
not contact the deferred backend.
An email app is required; the published email address is also available directly.

GitHub Actions defaults to this mode and does not inject Supabase credentials.
Do not set the repository Actions variable `PUBLIC_INQUIRY_MODE` to `online`
until the checks below are complete. Local builds use the same email default.

## Deferred: activating online inquiry saves

1. **Confirm the active Supabase project.** Public configuration was found in the
   current live website bundle, but its project endpoint failed DNS resolution
   from the audit environment. This does not prove global failure or deletion.
   Check the project's actual status and endpoint in the owner dashboard; do not
   assume existing build settings are current. No local Supabase credentials or
   CLI access were available. GitHub publication uses the connected GitHub tools.
2. **Apply the two incremental migrations to that existing project:**
   `supabase/migrations/202611160001_consultation_inquiries.sql`, then
   `supabase/migrations/202611160002_public_availability_privacy.sql`.
   The original schema/services setup must already exist. Do not rerun the
   original demonstration bootstrap/seed over a configured live database.
3. **Set production build configuration.** The existing workflow reads GitHub
   Actions secrets named `PUBLIC_SUPABASE_URL` and `PUBLIC_SUPABASE_ANON_KEY`.
   Set the repository Actions variable `PUBLIC_INQUIRY_MODE=online` only when ready.
   The key accepts a publishable key or legacy anon key. Keep service-role,
   secret, SMTP and shared-secret credentials out of the client build and chat.
4. **Verify owner handling.** The new form saves into the private
   `consultation_inquiries` table. The owner reviews it through the Supabase
   dashboard; the website has no new admin inquiry inbox. Check the existing
   `app_config`, `pg_net`, and `send-email` relay's server-side settings.
   `owner_notification = queued` means queued, not delivered.
5. **Run one controlled live inquiry after activation.** Use clearly marked test
   details, confirm a matching saved reference and row, verify the owner actually
   receives the notification, and check unchanged-detail retry behavior. No live
   inquiry or email was sent during this implementation. Local mocks/database
   fixtures do not establish production delivery.

In online mode, the deployment workflow refuses to proceed if public configuration is absent,
private-key-shaped, or if a read-only API schema check cannot find the consultation
endpoint. If schema discovery is deliberately disabled in the project, resolve
that verification approach explicitly rather than removing the check silently.
This gate does not prove SMTP delivery or validate the owner workflow.

## Domain and discovery

The current configuration keeps the working GitHub Pages destination:
`https://llllamas.github.io/Sleepy-Llamas/`. New canonicals, sitemap and share URLs
derive from this configuration; there are no invented custom-domain URLs.

If moving to `sleepyllamasdoula.com`, first verify DNS and HTTPS, change Astro's
site/base and the Moonlog deployment paths together, then verify redirects,
canonicals, internal links and sitemap on the new destination. Do not switch a
canonical to a domain merely because it is the desired brand name.

The prior live audit found the existing DoulaMatch profile linking to lowercase
`/sleepy-llamas/`, which returned 404, and still calling Catalina a student. The
owner confirmed certification is complete. Update that existing listing with the
correct destination and status; keep eight years of family-care experience
distinct from years in postpartum doula practice and distinguish shift rates
from consulting fees. No directory changes were made here.

Verify the correct URL-prefix property in Search Console and submit
`/Sleepy-Llamas/sitemap.xml`. A project-path `robots.txt` would not control the
GitHub hostname root, so no misleading project-level robots file was added.
The sitemap is a discovery aid, not a guarantee of indexing. Google Business
Profile eligibility/verification and Search Console access remain account tasks.
Do not create duplicate listings or publish a residential address just to fill a
structured-data field.

Google retired FAQ rich results in May 2026. Useful visible FAQs remain; obsolete
FAQPage/ProfessionalService markup was replaced with a small identity/service
graph. No reviews, ratings, office addresses or endorsements were fabricated.

## Business decisions and useful assets

Before taking paid bookings, confirm actual appointment windows, home-visit travel
coverage/fees, the written-plan delivery timing, and cancellation/rescheduling
terms. These are confirmed personally before payment in the current workflow.
The site collects inquiries, not payments or instant appointment reservations.

A genuine founder portrait, exact credential issuer/date details, and consented
client references would strengthen premium pricing. They are conversion assets,
not reasons to invent imagery or block technical testing. Unverified phone,
WhatsApp and Venmo details remain hidden; the published email route is available.

## Verification commands

```bash
npm run build
npm run check:site
npx --no-install tsc --noEmit
node --test tests/inquiries.test.ts
bash tests/run-database-checks.sh
```

The Node inquiry tests were run with the local Node 26 runtime. Database checks
use a disposable PostgreSQL cluster, private Unix socket and no TCP or email
configuration; they do not touch production. They require PostgreSQL tools and
permission for local shared memory/sockets. The script cleans up its own cluster.

To verify the deferred online mode, with production public values supplied by the build environment:

```bash
PUBLIC_INQUIRY_MODE=online npm run check:publish -- --verify-api
```

This last command performs only a public read-only schema request. Without those
values, online mode fails closed. Email-first publication does not require them. Never use a real client submission as a configuration probe.

Browser QA covers desktop and 390px layouts, navigation, FAQs, all three default
service selections, remote/in-person switching, extra-visit context, and the
unconfigured-backend error with retained input. Production delivery and Core Web
Vitals have not been established by those local checks.

## Research behind the page decisions

- `Doula-Research/newborn-service-page-research-2026-11-16.txt`
- `Doula-Research/caregiver-service-page-research-2026-11-16.txt`
- `Doula-Research/home-visit-service-page-research-2026-11-16.txt`
- `Doula-Research/seo-client-acquisition-strategy-2026-11-15.txt`

The memos separate primary advertised offers, recent professional articles and
individual public parent questions. Anecdotes are qualitative input, not measured
local demand, medical guidance, testimonials or willingness-to-pay evidence.
