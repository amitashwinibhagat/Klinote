# klinote-web

The marketing site for Klinote, served at [klinote.one](https://klinote.one).

TanStack Start (React 19, Tailwind v4) deployed to Netlify as an SSR function.
Built to the Pelmatech design spec: exact tokens, responsive zoom below 1728px,
masked image reveals, the blur-puck carousel. Copy is PAS and lives in
`docs/marketing/LANDING-COPY.md`, governed by `docs/product/PRODUCT-TRUTH.md`.

## Deploy

```bash
npm run build
netlify deploy --prod
```

`netlify.toml` carries the build command, publish dir, and headers, so no
linking step is needed. The site is linked to Netlify project
`luminous-speculoos-4764fd`.

## The contact form

`/contact` posts to a server function (`src/server/contact.ts`) that writes the
enquiry to Netlify Blobs.

Read every enquiry, newest first:

```bash
npm run enquiries
```

### Being told when one arrives

Configured and working: every submission emails **amit@datadab.com** from
**enquiries@klinote.one**, with `reply_to` set to the enquirer so hitting Reply
answers the prospect. Verified delivered through the Resend API, not merely
accepted.

`klinote.one` is verified in Resend. The DNS records live at **Spaceship**, not
Netlify, and are:

| Type | Name | Value |
|---|---|---|
| TXT | `resend._domainkey` | the DKIM key from `GET /domains/{id}` |
| CNAME | `rsend` | `rsend-apne1.forge.rmta.net` |
| CNAME | `send` | `send.forge.rmta.net` |

To change who is told, or who it appears to come from:

```bash
netlify env:set CONTACT_TO 'amit@datadab.com,someone@else.com'   # comma separated
netlify env:set CONTACT_FROM 'Klinote enquiries <enquiries@klinote.one>'
```

A redeploy is needed for env changes to reach the function. Without a domain
verification, Resend only delivers to the account owner's address, which is why
`CONTACT_FROM` defaults to its test sender.

## Brand assets

Generated from two SVGs, not hand-exported:

```bash
node src/assets/generate.mjs   # og.png, favicon set, icons, manifest
```

Sources are `src/assets/og-source.svg` (1200×630 social card) and
`src/assets/icon-source.svg` (app mark). `png-to-ico.mjs` writes a real ICO
container, because this sharp build has no `.ico()` output.

## Two traps worth knowing

**Responsive zoom must not touch `element.style`.** `hydrateRoot(document)` in
React 19 compares the `<html>` element's attributes against the server markup,
and an inline `style.zoom` set before hydration is a mismatch it throws #418 on.
Worse, React's SSR renderer strips `suppressHydrationWarning`, so that prop
cannot paper over it. Zoom is applied through a `<style>` rule instead, which
changes computed style without touching the attribute.

**Images load from `qclay.design`.** The template's asset bundle is hot-linked
rather than vendored. That is fine for a marketing site and is not a product
network path, but it does mean the page depends on a third-party host. Vendoring
them into `src/assets/` would remove that dependency.
