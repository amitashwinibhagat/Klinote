import { createFileRoute } from '@tanstack/react-router'
import { ArrowUpRight } from 'lucide-react'

import { Header } from '~/components/Header'
import { AnimatedHeading, AnimatedText, MaskedImage } from '~/components/AnimatedHeading'
import { TeamCarousel } from '~/components/TeamCarousel'
import { clockLamp, heroImage, pills, waitlist, downloadUrl, appVersion } from '~/assets'

const PROBLEMS = [
  {
    num: '01',
    title: 'Uploaded',
    desc: 'A cloud scribe means the session sits on a vendor’s disk before the note does. Licence, ethics or law may say the room stays in the room, and the recording leaves first.',
    img: clockLamp,
  },
  {
    num: '02',
    title: 'Invented',
    desc: 'A draft that puts words in the client’s mouth is worse than no draft: a risk they did not name, a feeling they did not describe, and a plan they did not agree to. You cannot sign that, and you should not have to rewrite it either.',
    img: pills,
  },
  {
    num: '03',
    title: 'Untraceable',
    desc: 'When a sentence arrives with no source, the question "why is this in my note?" has no answer a record accepts.',
    img: waitlist,
  },
] as const

export const Route = createFileRoute('/')({
  component: HomePage,
})

function HomePage() {
  return (
    <div className="bg-background text-foreground">
      <Header />
      <main>
        <Hero />
        <BenefitsSection />
        <TeamSection />
        <SupportSection />
        <FaqSection />
        <FinalCta />
      </main>
    </div>
  )
}

function Hero() {
  // The template inherited this strip from a slide deck; on a scrolling page the
  // only honest version is a working "next" and a count of the sections below.
  const SECTIONS_AHEAD = ['the-cost', 'how-it-works', 'support', 'faq', 'start']
  return (
    <section className="relative h-screen min-h-[780px] w-full overflow-hidden">
      <img
        src={heroImage}
        alt="A clinician at a Mac, drafting a note"
        className="absolute inset-0 w-full h-full object-cover"
      />
      <div className="absolute inset-0 bg-black/25" />
      <div className="absolute inset-0 bg-gradient-to-t from-black/40 via-transparent to-transparent" />

      <div className="absolute inset-0 flex flex-col justify-end pb-16 px-8 md:px-12">
        <div className="flex items-end justify-between gap-8">
          <div className="max-w-3xl">
            <AnimatedHeading
              as="h1"
              className="text-white font-medium leading-[1.05]"
            >
              <span style={{ fontSize: '72.73px', lineHeight: 1.05, display: 'block' }}>
                The session stays in the room.<br />The note still gets written.
              </span>
            </AnimatedHeading>

            <div className="mt-8 w-max">
              <AnimatedText className="text-white/85 max-w-xl leading-relaxed">
                <span
                  style={{
                    fontSize: '20.99px',
                    lineHeight: '28.21px',
                    display: 'block',
                    width: '608px',
                  }}
                >
                  Klinote turns a session, recorded or dictated, into a
                  structured progress-note draft entirely on your Mac. Every
                  sentence cites the words that produced it. Nothing is uploaded,
                  because there is nothing to upload to.
                </span>
              </AnimatedText>
            </div>
          </div>

          <div className="flex items-center gap-6 shrink-0 pb-1">
            <a
              href={downloadUrl}
              className="bg-white text-foreground rounded-full pl-6 pr-2 py-2 flex items-center gap-3 font-medium text-sm hover:bg-white/90 transition"
            >
              Download for Mac
              <span className="w-9 h-9 rounded-full bg-foreground text-white flex items-center justify-center">
                <ArrowUpRight className="w-4 h-4" />
              </span>
            </a>
            <a
              href="#how-it-works"
              className="text-white flex items-center gap-1 text-sm font-medium"
            >
              How it works <ArrowUpRight className="w-4 h-4" />
            </a>
          </div>
        </div>

        <div
          className="mt-12 pt-5 border-t border-white/20 flex items-center justify-between tracking-[0.2em] text-white/70 uppercase font-mono"
          style={{ fontSize: '12px' }}
        >
          <span>No account · No upload · Encrypted at rest</span>
          <span className="flex items-center gap-6">
            <span>
              <span className="text-white">01</span> / {String(SECTIONS_AHEAD.length).padStart(2, '0')}
            </span>
            <button
              onClick={() =>
                document.getElementById(SECTIONS_AHEAD[0])?.scrollIntoView({ behavior: 'smooth' })
              }
              className="hover:text-white transition cursor-pointer"
              aria-label="Continue to the next section"
            >
              Next
            </button>
          </span>
          <span>Scroll to explore</span>
        </div>
      </div>
    </section>
  )
}

function TeamSection() {
  return (
    <section
      className="py-32 px-8 md:px-12 scroll-mt-24"
      id="how-it-works"
    >
      <div style={{ paddingLeft: '335.26px' }}>
        <div
          className="mb-16 flex gap-24 tracking-[0.2em] uppercase text-muted-foreground font-mono"
          style={{ fontSize: '11.26px' }}
        >
          <span>Klinote</span>
          <span>How it works</span>
        </div>

        <AnimatedHeading className="font-medium leading-[1.05]">
          <span
            style={{
              fontSize: '58.55px',
              lineHeight: 1.05,
              display: 'block',
            }}
          >
            Five steps, and the fourth<br />one is the product
          </span>
        </AnimatedHeading>
      </div>

      <div className="mt-20">
        <TeamCarousel
          intro={
            <AnimatedText className="text-muted-foreground leading-relaxed">
              <span
                style={{
                  fontSize: '16.89px',
                  lineHeight: 1.5,
                  display: 'block',
                  width: '270px',
                }}
              >
                Writing a note is the small part of the work. Deciding where each
                sentence belongs is most of it. Klinote does that filing on the Mac
                and hands you the draft with a receipt for every line.
              </span>
            </AnimatedText>
          }
        />
      </div>
    </section>
  )
}

function BenefitsSection() {
  return (
    <section className="py-32 px-8 md:px-12 bg-surface scroll-mt-24" id="the-cost">
      <div className="grid grid-cols-12 gap-12 mb-24">
        <div className="col-span-12 md:col-span-7">
          <AnimatedHeading className="text-5xl md:text-6xl font-medium leading-[1.05]">
            What a cloud scribe<br />costs you
          </AnimatedHeading>
        </div>
        <div className="col-span-12 md:col-span-4 md:col-start-9 md:pt-4">
          <AnimatedText className="text-base text-muted-foreground leading-relaxed">
            The objection is rarely the editor. It is the disk, the invention and the
            missing receipt, three problems a better text box does not fix.
          </AnimatedText>
        </div>
      </div>

      <div
        className="relative grid grid-cols-1 md:grid-cols-3"
        style={{
          backgroundImage:
            'linear-gradient(to right, rgba(255,255,255,0.45) 1px, transparent 1px), linear-gradient(to right, rgba(255,255,255,0.45) 1px, transparent 1px)',
          backgroundSize: '1px 100%, 1px 100%',
          backgroundPosition: '33.3333% 0, 66.6666% 0',
          backgroundRepeat: 'no-repeat',
        }}
      >
        <span
          aria-hidden
          className="pointer-events-none absolute left-0 right-0 top-0 h-px"
          style={{
            background:
              'linear-gradient(to right, transparent 0%, rgba(255,255,255,0.45) 15%, rgba(255,255,255,0.45) 85%, transparent 100%)',
          }}
        />
        <span
          aria-hidden
          className="pointer-events-none absolute left-0 right-0 bottom-0 h-px"
          style={{
            background:
              'linear-gradient(to right, transparent 0%, rgba(255,255,255,0.45) 15%, rgba(255,255,255,0.45) 85%, transparent 100%)',
          }}
        />

        {PROBLEMS.map((p, i) => (
          <div key={p.num} className="p-10 flex flex-col gap-8">
            {i === 1 ? (
              <>
                <div className="aspect-square overflow-hidden">
                  <MaskedImage src={p.img} alt={p.title} className="w-full h-full" delay={i * 0.12} />
                </div>
                <CardContent p={p} i={i} />
              </>
            ) : (
              <>
                <CardContent p={p} i={i} />
                <div className="mt-auto">
                  <div className="aspect-square overflow-hidden">
                    <MaskedImage src={p.img} alt={p.title} className="w-full h-full" delay={i * 0.12} />
                  </div>
                </div>
              </>
            )}
          </div>
        ))}
      </div>
    </section>
  )
}

function CardContent({
  p,
  i,
}: {
  p: (typeof PROBLEMS)[number]
  i: number
}) {
  return (
    <div className="mt-auto">
      <div className="flex items-start gap-3 mb-4">
        <span className="text-xs text-muted-foreground mt-2 font-mono">({p.num})</span>
        <AnimatedHeading as="h3" className="text-3xl font-medium" delay={i * 0.1}>
          {p.title}
        </AnimatedHeading>
      </div>
      <AnimatedText
        className="text-sm text-muted-foreground leading-relaxed max-w-sm"
        delay={0.2 + i * 0.1}
      >
        {p.desc}
      </AnimatedText>
    </div>
  )
}

const FAQS = [
  {
    q: 'Does the recording leave my Mac?',
    a: 'No. The Rust engine has no HTTP client, and that is checked on every build. Speech recognition is the system’s own SpeechAnalyzer, so listening makes no request either. The one download the app ever makes is the note model, once, on first use. Audio and notes never leave.',
  },
  {
    q: 'Will it invent findings my client didn’t mention?',
    a: 'It is built not to, and the refusal is mechanical rather than a promise: a quote must exist in the transcript or it does not enter the note, risk is never generated, and anything the generator cannot confidently route lands in an "unfiled" list for you to place. Nothing goes to the bin.',
  },
  {
    q: 'Is it HIPAA or GDPR compliant?',
    a: 'That has not been assessed, so it is not claimed. What is true today: no account, no upload, no telemetry, and the store is SQLCipher-encrypted with the key in your Keychain. A strong posture is not a determination.',
  },
  {
    q: 'Does it integrate with my EHR?',
    a: 'Not today. Output is Markdown and JSON for copy-paste into the record you already keep. Integration is decided by which systems paying users name.',
  },
  {
    q: 'How accurate is it?',
    a: 'That has not been measured on real encounters, so no accuracy figure is published. The draft is exactly that: a draft, for a clinician to review and sign. Nothing is ever presented as final.',
  },
] as const

function FaqSection() {
  return (
    <section className="py-32 px-8 md:px-12" id="faq">
      <div className="grid grid-cols-12 gap-12">
        <div className="col-span-12 md:col-span-7">
          <AnimatedHeading className="text-5xl md:text-6xl font-medium leading-[1.05]">
            The questions a<br />therapist asks first
          </AnimatedHeading>
        </div>
        <div className="col-span-12 md:col-span-4 md:col-start-9 md:pt-4">
          <AnimatedText className="text-base text-muted-foreground leading-relaxed">
            Ask these of any scribe. The answers here are the ones that are true
            today, including the ones that are still "not yet measured".
          </AnimatedText>
        </div>
      </div>

      <div className="mt-20 grid grid-cols-12 gap-12">
        <div className="col-span-12 md:col-span-8 md:col-start-3">
          <dl className="border-t border-border">
            {FAQS.map((f, i) => (
              <div key={f.q} className="border-b border-border py-8">
                <AnimatedHeading
                  as="dt"
                  className="text-xl font-medium"
                  delay={i * 0.06}
                >
                  {f.q}
                </AnimatedHeading>
                <AnimatedText
                  className="text-sm text-muted-foreground leading-relaxed mt-4 max-w-2xl"
                  delay={0.1 + i * 0.06}
                >
                  {f.a}
                </AnimatedText>
              </div>
            ))}
          </dl>

          <AnimatedText
            className="text-sm text-muted-foreground leading-relaxed mt-12"
            delay={0.2}
          >
            <span className="font-mono">Klinote {appVersion}</span> for macOS is free to try, notarized, and
           {' '}
            <a
              href={downloadUrl}
              className="text-foreground underline underline-offset-4 decoration-border hover:decoration-foreground transition"
            >
              downloadable directly from GitHub
            </a>
            . There is no account to create and no telemetry to switch off.
          </AnimatedText>
        </div>
      </div>
    </section>
  )
}

const SUPPORT_TIERS = [
  {
    num: '01',
    title: 'Community support',
    price: 'Free',
    note: 'Apache-2.0, always',
    desc: 'File an issue on GitHub and the person who wrote the code reads it. The privacy model, the template format and the known gaps are documented in the open, including the two the project names as unfunded: scoring a draft against a clinician-signed note, and separating two voices that sound alike.',
    cta: 'Open an issue',
    href: 'https://github.com/amitashwinibhagat/Klinote/issues',
  },
  {
    num: '02',
    title: 'Shape it for your discipline',
    price: 'Free',
    note: 'Three to five practices',
    desc: 'You get the template build free, the same work that costs $600, tuned to how your practice documents. In exchange you report honestly on the draft: what it invented, what it misfiled, and whether reviewing it took longer than typing it. Those reports are how the defaults for your discipline get written by someone who has signed its notes. That is why this one is free.',
    cta: 'Apply for a place',
    href: '/contact?topic=cohort',
  },
  {
    num: '03',
    title: 'A template built for you',
    price: 'from $600',
    note: 'One-off, no subscription',
    desc: 'For a practice whose notes do not fit a built-in shape. Your template is written and tuned to the way your clinicians document, tested against notes you have already signed, and handed back as a file you own. It is template work, and it buys no promise about transcription.',
    cta: 'Commission a template',
    href: '/contact?topic=template',
  },
] as const

function SupportSection() {
  return (
    <section className="py-32 px-8 md:px-12 bg-surface" id="support">
      <div className="grid grid-cols-12 gap-12 mb-24">
        <div className="col-span-12 md:col-span-7">
          <AnimatedHeading className="text-5xl md:text-6xl font-medium leading-[1.05]">
            Help that doesn’t cost<br />you the room
          </AnimatedHeading>
        </div>
        <div className="col-span-12 md:col-span-4 md:col-start-9 md:pt-4">
          <AnimatedText className="text-base text-muted-foreground leading-relaxed">
            A solo practitioner does not have a procurement department, so there is
            no procurement process here. Two of these cost nothing. The third is
            template work you can buy today, and the subscription comes later, if
            validation earns it.
          </AnimatedText>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
        {SUPPORT_TIERS.map((t, i) => (
          <div
            key={t.num}
            className="p-10 flex flex-col border border-border rounded-lg bg-background"
          >
            <div className="flex items-baseline justify-between gap-4 mb-6">
              <div className="flex items-start gap-3">
                <span className="text-xs text-muted-foreground mt-2 font-mono">({t.num})</span>
                <AnimatedHeading as="h3" className="text-3xl font-medium" delay={i * 0.1}>
                  {t.title}
                </AnimatedHeading>
              </div>
              <AnimatedText
                className="text-2xl font-medium shrink-0"
                delay={0.05 + i * 0.1}
              >
                {t.price}
              </AnimatedText>
            </div>

            <p className="text-xs tracking-[0.2em] text-muted-foreground uppercase mb-8 font-mono">
              {t.note}
            </p>

            <AnimatedText
              className="text-sm text-muted-foreground leading-relaxed"
              delay={0.15 + i * 0.1}
            >
              {t.desc}
            </AnimatedText>

            <a
              href={t.href}
              className="mt-10 self-start inline-flex items-center gap-3 font-medium text-sm bg-foreground text-background rounded-full pl-6 pr-2 py-2 hover:opacity-90 transition"
            >
              {t.cta}
              <span className="w-9 h-9 rounded-full bg-background text-foreground flex items-center justify-center">
                <ArrowUpRight className="w-4 h-4" />
              </span>
            </a>
          </div>
        ))}
      </div>

      <AnimatedText
        className="text-sm text-muted-foreground leading-relaxed mt-12 max-w-3xl"
        delay={0.2}
      >
        Nothing here is a subscription yet. A subscription would promise more
        than the validation sprint can support. When the cohort says the draft is
        worth standing behind, the practice tier arrives: tuned templates,
        priority triage, and a named person accountable, priced per practice.
        Until then the one thing money buys is a template, and it buys no promise
        about accuracy, compliance or time saved.
      </AnimatedText>
    </section>
  )
}

function FinalCta() {
  return (
    <section className="py-32 px-8 md:px-12 bg-ink" id="start">
      <div className="grid grid-cols-12 gap-12">
        <div className="col-span-12 md:col-span-7">
          <AnimatedHeading className="text-5xl md:text-6xl font-medium leading-[1.05] text-white">
            See if the draft is one<br />you would have signed
          </AnimatedHeading>
          <AnimatedText
            className="text-base text-white/75 leading-relaxed mt-8 max-w-xl"
            delay={0.15}
          >
            Klinote <span className="font-mono">{appVersion}</span> for macOS is free and
            Apache-2.0. No account, no card, nothing to cancel, and nothing leaves the Mac
            while you decide whether it earns a place in your room.
          </AnimatedText>

          <div className="mt-12 flex flex-wrap items-center gap-6">
            <a
              href={downloadUrl}
              className="bg-white text-foreground rounded-full pl-6 pr-2 py-2 flex items-center gap-3 font-medium text-sm hover:bg-white/90 transition"
            >
              Download for Mac
              <span className="w-9 h-9 rounded-full bg-foreground text-white flex items-center justify-center">
                <ArrowUpRight className="w-4 h-4" />
              </span>
            </a>
            <a
              href="/contact?topic=cohort"
              className="text-white border border-white/30 rounded-full px-6 py-2 text-sm font-medium hover:bg-white/10 transition"
            >
              Apply for the cohort
            </a>
          </div>

          <p className="mt-10 text-xs tracking-[0.2em] text-white/50 uppercase font-mono">
            Three to five cohort places. That limit is real.
          </p>
        </div>
      </div>
    </section>
  )
}
