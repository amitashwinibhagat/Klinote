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
enquiry to Netlify Blobs. Read what arrived with:

```bash
netlify blobs:list klinote-contact
netlify blobs:get klinote-contact <key>
```

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
