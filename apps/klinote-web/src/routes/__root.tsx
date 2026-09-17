/// <reference types="vite/client" />
import {
  HeadContent,
  Scripts,
  createRootRoute,
} from '@tanstack/react-router'
import * as React from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

import appCss from '~/styles.css?url'

// The whole document is uniformly downscaled below 1728px so the layout can be
// authored once, at the 1728px reference width. Duplicated in a useEffect below
// so it re-applies after hydration.
//
// IMPORTANT: zoom is applied through a <style> rule, not element.style.zoom.
// hydrateRoot(document) compares the <html> element's attributes against the
// server markup, and an inline style set before hydration is a mismatch React
// throws #418 on. A stylesheet rule changes computed style without touching the
// attribute, so React sees the same element both sides. React's SSR also strips
// suppressHydrationWarning, so that prop cannot be used to paper over it.
const ZOOM_STYLE_ID = 'klinote-responsive-zoom'
const ZOOM_SCRIPT = `(function(){
  function u(){
    var w = document.documentElement.clientWidth;
    var z = w < 1728 ? w / 1728 : 1;
    var s = document.getElementById('${ZOOM_STYLE_ID}');
    if (!s) {
      s = document.createElement('style');
      s.id = '${ZOOM_STYLE_ID}';
      document.head.appendChild(s);
    }
    s.textContent = 'html{zoom:' + z + '}';
  }
  u();
  window.addEventListener('resize', u);
})();`

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: 'utf-8' },
      {
        name: 'viewport',
        content: 'width=device-width, initial-scale=1',
      },
      {
        title: 'Klinote — The session stays in the room. The note still gets written.',
      },
      {
        name: 'description',
        content:
          'Klinote turns a consultation recording into a structured progress-note draft entirely on your Mac. Every sentence cites the words that produced it. Nothing is uploaded.',
      },

      // Open Graph / Twitter. Absolute URLs: scrapers do not resolve relatives.
      { property: 'og:type', content: 'website' },
      { property: 'og:site_name', content: 'Klinote' },
      {
        property: 'og:title',
        content: 'The session stays in the room. The note still gets written.',
      },
      {
        property: 'og:description',
        content:
          'On-device clinical documentation for macOS. Every sentence cites the words that produced it. Nothing is uploaded.',
      },
      { property: 'og:url', content: 'https://klinote.one/' },
      { property: 'og:image', content: 'https://klinote.one/og.png' },
      { property: 'og:image:width', content: '1200' },
      { property: 'og:image:height', content: '630' },
      { property: 'og:image:alt', content: 'Klinote wordmark on an ink ground, with the positioning line and its four privacy commitments.' },
      { name: 'twitter:card', content: 'summary_large_image' },
      { name: 'twitter:title', content: 'The session stays in the room. The note still gets written.' },
      {
        name: 'twitter:description',
        content:
          'On-device clinical documentation for macOS. Every sentence cites the words that produced it. Nothing is uploaded.',
      },
      { name: 'twitter:image', content: 'https://klinote.one/og.png' },
    ],
    links: [
      { rel: 'stylesheet', href: appCss },
      { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
      {
        rel: 'preconnect',
        href: 'https://fonts.gstatic.com',
        crossOrigin: 'anonymous',
      },
      {
        rel: 'stylesheet',
        href: 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Inter+Tight:wght@400;500;600&display=swap',
      },

      // Icons. Generated from src/assets/icon-source.svg by generate.mjs.
      { rel: 'icon', type: 'image/x-icon', href: '/favicon.ico' },
      { rel: 'icon', type: 'image/png', sizes: '16x16', href: '/favicon-16x16.png' },
      { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32x32.png' },
      {
        rel: 'apple-touch-icon',
        sizes: '180x180',
        href: '/apple-touch-icon.png',
      },
      { rel: 'manifest', href: '/site.webmanifest' },
    ],
    scripts: [
      { children: ZOOM_SCRIPT },
    ],
  }),
  shellComponent: RootDocument,
})

function RootDocument({ children }: { children: React.ReactNode }) {
  React.useEffect(() => {
    const apply = () => {
      const w = document.documentElement.clientWidth
      const z = w < 1728 ? w / 1728 : 1
      let s = document.getElementById(ZOOM_STYLE_ID)
      if (!s) {
        s = document.createElement('style')
        s.id = ZOOM_STYLE_ID
        document.head.appendChild(s)
      }
      s.textContent = `html{zoom:${z}}`
    }
    apply()
    window.addEventListener('resize', apply)
    return () => window.removeEventListener('resize', apply)
  }, [])

  return (
    <html lang="en">
      <head>
        <HeadContent />
      </head>
      <body>
        <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
        <Scripts />
      </body>
    </html>
  )
}

const queryClient = new QueryClient()
