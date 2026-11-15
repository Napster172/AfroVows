# AfroVows

Wedding planning website for couples in Ghana: a free public vendor directory, and a private planner for couples (budget with invoices and receipts, guests and RSVPs, to-dos, vendors, photos, Our Story, wedding and venue details). Vendors can list their business and choose a paid plan, and the site owner approves listings and plans.

## What's in this repository

- `public/index.html` is the clickable prototype: one HTML file with all the pages, styles and code.
- `public/afrovows-logo.svg` is the logo.

## Status: prototype

The prototype keeps every account, wedding and listing in the visitor's own browser (localStorage). Nothing is shared between devices or people yet, and the sample vendors are made up.

The next step is the hosted version:
- **Website:** Cloudflare Pages, serving the `public` folder.
- **Accounts, database and file uploads:** Supabase, in the London or Frankfurt region.

## Try it locally

Open `public/index.html` in a browser, or serve the folder:

```
npx serve public
```

Demo logins are on the sign-in pages ("Explore the sample wedding" and "Open as site owner").
