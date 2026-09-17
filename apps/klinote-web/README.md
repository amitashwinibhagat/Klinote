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

### Being told when one arrives — currently NOT configured

Storing an enquiry is not the same as knowing about it, and right now nobody is
told. The function is written to announce submissions and needs one value in the
Netlify environment. Set **either**:

| Variable | What it is |
|---|---|
| `CONTACT_WEBHOOK_URL` | A Slack or Discord incoming webhook URL. One paste, works for either. |
| `RESEND_API_KEY` **and** `CONTACT_TO` | Email via Resend: an API key and the address to notify. |

```bash
netlify env:set CONTACT_WEBHOOK_URL 'https://hooks.slack.com/...'
```

Until one is set, the function logs
`contact: NO NOTIFICATION CHANNEL CONFIGURED` on every submission, and returns
`notified: "skipped"`. The enquiry is still stored either way — a failed or
missing channel never loses it — but an unannounced enquiry is easy to miss,
which is why `npm run enquiries` exists as the backstop.

### Why it is not Netlify Forms

It was, and it silently lost messages. Netlify Forms answered 200 with a success
page while discarding browser submissions: of eleven attempts across curl and
browser, five were stored, and **every browser submission was dropped** — no
error, no spam-list entry, no trace. Reproduced with headless and headed
Chrome. curl with the same body always stored.

The likely trigger is request fingerprinting: replaying browser headers exactly
(with `sec-ch-ua`, `sec-fetch-*`) stopped Netlify intercepting the POST at all,
and served the static file instead. The mechanism was never fully established,
which is the point — an opaque pipeline that reports success while dropping
enquiries is not something to build a contact form on.

The replacement is owned and verifiable: the server function returns an explicit
`{ ok: true }` only after the blob is written, and the form shows success only
when it sees that. A status code is never treated as proof of receipt.

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
