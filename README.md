# AfroVows

Wedding planning website for couples in Ghana: a free public vendor directory, and a private planner for couples (budget with invoices and receipts, guests and RSVPs, to-dos, vendors, photos, Our Story, wedding and venue details). Vendors list their business and can buy a paid plan. The site owner approves listings and plans, reads contact messages and edits the public pages.

## How it fits together

- `public/` is the website, a static folder served by **Cloudflare Pages**.
  - `index.html`: all the pages.
  - `config.js`: the Supabase address and its public (publishable) key.
  - `vendor/supabase.js`: the Supabase browser library (v2.118.0).
- **Supabase** holds the accounts, database and file storage.
  - `supabase/migrations/` sets up the tables, privacy rules and storage buckets.
- Without `config.js`, `index.html` runs as a self-contained preview that keeps everything in the browser. This is how the claude.ai preview link works.

### Who can see what

- **Public:** approved vendor listings (only their public version), reviews, About us, site text.
- **Couples:** only their own wedding, and only the bride, groom and people they invite. An invited person must type the first and last name on their invite, and the bride or groom approves them before they get any access. Only the bride or groom can change the team list. Removing someone from the Team tab removes their access.
- **Guests:** the wedding page via the wedding code, without signing in. They can find their own invitation by exact name or WhatsApp number, RSVP and add photos. They never see the guest list, budget or planner.
- **Vendors:** their own listings (one or more, one per service). They can't approve themselves or give themselves a paid plan. The business registration number is never public.
- **Site owner (admin):** listings, paid plans, contact messages and site text.
- **Files:** invoices and receipts are in a private bucket that only the couple's team can open. Photos are in a public bucket under random file names.

## One-time setup

1. **Database.** In Supabase, open SQL Editor → New query. Paste the whole of `supabase/migrations/20261115000000_init.sql` and click Run. Then run each later file in `supabase/migrations/` the same way, oldest first.
2. **Sign-in settings.** Go to Authentication.
   - URL Configuration: set Site URL to the live address, e.g. `https://afrovows.pages.dev`.
   - Sign In / Providers → Email: "Confirm email" is on by default. Supabase's built-in email service only sends a few emails an hour, so either connect your own email sender (SMTP, e.g. Resend) before launch, or turn confirmation off while testing.
3. **Make yourself the site owner.** Sign up on the site as a couple with your own email. Then run this in the SQL Editor:
   ```sql
   update public.profiles set role = 'admin' where email = 'your@email.com';
   ```
   After that, sign in from the footer's "Site owner" link.
4. **Website.** In Cloudflare, go to Workers & Pages → Create and connect this repository. `wrangler.jsonc` tells Cloudflare to serve the `public` folder, so each merge to `main` deploys automatically. The default deploy command (`npx wrangler deploy`) works as is.

## Testing locally

```
npx supabase start                  # needs Docker
node tests/privacy-checks.mjs       # 31 privacy checks
```

To run the site against the local stack, point `public/config.js` at `http://127.0.0.1:54321` with the local publishable key and serve `public/`.

## Known limits (first version)

- When two people edit the same planner at the same moment, the last save wins. Changes from others show after a page refresh.
- Paid plans are confirmed by hand from MoMo transaction IDs. There's no Paystack integration yet.
