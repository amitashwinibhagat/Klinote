import * as React from 'react'
import { Download } from 'lucide-react'
import logo from '~/assets/logo.svg'
import logoDark from '~/assets/logo-dark.svg'
import { downloadUrl } from '~/assets'

// Every href below must resolve to a section id that exists on the page, or to
// an external URL. Anchor links that point at nothing are the bug this replaced.
const NAV_ITEMS = [
  { label: 'Home', href: '#' },
  { label: 'The cost', href: '#the-cost' },
  { label: 'How it works', href: '#how-it-works' },
  { label: 'Support', href: '#support' },
  { label: 'FAQ', href: '#faq' },
] as const

export function Header() {
  const [scrolled, setScrolled] = React.useState(false)

  React.useEffect(() => {
    const onScroll = () => {
      setScrolled(window.scrollY > window.innerHeight - 80)
    }
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <>
      {/* The hero image is light at the top; a white wordmark needs a scrim.
          Once the page has scrolled, the header sits on the page colour and
          the scrim would just be a grey band. */}
      {!scrolled ? (
        <div
          aria-hidden
          className="pointer-events-none fixed inset-x-0 top-0 z-40 h-28 bg-gradient-to-b from-black/45 to-transparent"
        />
      ) : null}
      <header className="fixed top-6 left-0 right-0 z-50 px-8 flex items-center justify-between">
      <a href="#" aria-label="Klinote — home">
        <img
          src={scrolled ? logoDark : logo}
          alt="Klinote"
          className="h-8 w-auto transition-opacity"
        />
      </a>

      <nav aria-label="Primary" className="flex items-center gap-1 bg-[var(--header-bg)] backdrop-blur-md text-white rounded-full pl-2 pr-2 py-2">
        {NAV_ITEMS.map((item) => (
          <a
            key={item.label}
            href={item.href}
            className={
              (item.href === '#'
                ? 'px-5 py-2 text-sm rounded-full bg-white/10 font-medium'
                : 'px-5 py-2 text-sm rounded-full opacity-80 hover:opacity-100 transition') +
              ' hidden md:inline-block'
            }
          >
            {item.label}
          </a>
        ))}

        <a
          href={downloadUrl}
          className="ml-2 flex items-center gap-2 px-4 py-2 text-sm rounded-full hover:bg-white/10 transition bg-white/10 font-medium"
        >
          <Download className="w-4 h-4" />
          Download
        </a>
      </nav>
      </header>
    </>
  )
}
