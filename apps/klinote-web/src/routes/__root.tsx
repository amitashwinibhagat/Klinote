/// <reference types="vite/client" />
import {
  HeadContent,
  Scripts,
  createRootRoute,
} from '@tanstack/react-router'
import * as React from 'react'

import appCss from '~/styles.css?url'

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
  }),
  shellComponent: RootDocument,
})

function RootDocument({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <HeadContent />
        {/* If the bundle never runs, Motion's initial opacity/clip styles are
            still in the SSR markup. This is the no-JS fallback: the copy is
            readable even when hydration fails. */}
        <noscript
          dangerouslySetInnerHTML={{
            __html:
              '<style>.klinote-motion{opacity:1!important;transform:none!important;clip-path:none!important;filter:none!important}</style>',
          }}
        />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  )
}
