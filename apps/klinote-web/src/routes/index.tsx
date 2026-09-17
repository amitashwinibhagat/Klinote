import { createFileRoute } from '@tanstack/react-router'
import { ArrowUpRight } from 'lucide-react'

import { Header } from '~/components/Header'
import { AnimatedHeading, AnimatedText, MaskedImage } from '~/components/AnimatedHeading'
import { TeamCarousel } from '~/components/TeamCarousel'
import { clockLamp, heroImage, pills, waitlist, downloadUrl, appVersion } from '~/assets'

const TT_HOVES = '"TT Hoves", "Helvetica Neue", Helvetica, Arial, sans-serif'

const PROBLEMS = [
  {
    num: '01',
    title: 'Uploaded',
    desc: 'We understand that there may be times when a session cannot exist on a vendor’s disk. Licence, ethics, or law says the room stays in the room — and the recording leaves before the note is written.',
    img: clockLamp,
  },
  {
    num: '02',
    title: 'Invented',
    desc: 'A draft that puts words in the client’s mouth is worse than no draft: a risk they did not name, a feeling they did not describe, a plan they did not agree to. Promotion is not the only way to prescribe the wrong thing.',
    img: pills,
  },
  {
    num: '03',
    title: 'Untraceable',
    desc: 'When a sentence arrives with no source, the only honest question is “why is this in my note?” — and “the model said so” is not an answer a record accepts.',
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
        <TeamSection />
        <BenefitsSection />
        <FaqSection />
      </main>
    </div>
  )
}

function Hero() {
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
                  Klinote turns a consultation recording into a structured progress-note draft
                  entirely on your Mac. Every sentence cites the words that produced it. Nothing
                  is uploaded — there is nothing to upload to.
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
          className="mt-12 pt-5 border-t border-white/20 flex items-center justify-between tracking-[0.2em] text-white/70 uppercase"
          style={{ fontSize: '12px' }}
        >
          <span>No account · No upload · Encrypted at rest</span>
          <span className="flex items-center gap-6">
            <span><span className="text-white">01</span> / 04</span>
            <span>Next</span>
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
      style={{ fontFamily: TT_HOVES }}
      id="how-it-works"
    >
      <div style={{ paddingLeft: '335.26px' }}>
        <div
          className="mb-16 flex gap-24 tracking-[0.2em] uppercase text-muted-foreground"
          style={{ fontSize: '11.26px', fontFamily: TT_HOVES }}
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
              fontFamily: TT_HOVES,
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
                  fontFamily: TT_HOVES,
                }}
              >
                Most of a note is not writing — it is deciding where each sentence
                belongs. Klinote does that filing on the Mac, then hands you the draft
                and the receipt for every line of it.
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
            missing receipt — three problems that a better text box does not fix.
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
        <span className="text-xs text-muted-foreground mt-2">({p.num})</span>
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
    a: 'No. The Rust engine has no HTTP client — it is checked on every build. Speech recognition is the system’s own SpeechAnalyzer, so listening makes no request either. The one download the app ever makes is the note model, once, on first use. Audio and notes never leave.',
  },
  {
    q: 'Will it invent findings my client didn’t mention?',
    a: 'It is built not to, and the refusal is mechanical rather than a promise: a quote must exist in the transcript or it does not enter the note, risk is never generated, and anything the generator cannot confidently route lands in an “unfiled” list for you to place — never in the bin.',
  },
  {
    q: 'Is it HIPAA or GDPR compliant?',
    a: 'That has not been assessed, so it is not claimed. What is true today: no account, no upload, no telemetry, and the store is SQLCipher-encrypted with the key in your Keychain. A strong posture is not a determination.',
  },
  {
    q: 'Does it integrate with my EHR?',
    a: 'Not today — output is Markdown and JSON for copy-paste into the record you already keep. Integration is decided by which systems paying users name.',
  },
  {
    q: 'How accurate is it?',
    a: 'That has not been measured on real encounters, so no accuracy figure is published. The draft is exactly that — a draft, for a clinician to review and sign. Nothing is ever presented as final.',
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
            today, including the ones that are still “not yet measured”.
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
            Klinote {appVersion} for macOS is free to try, notarized, and
           {' '}
            <a
              href={downloadUrl}
              className="text-foreground underline underline-offset-4 decoration-border hover:decoration-foreground transition"
            >
              downloadable directly from GitHub
            </a>
            . No account, no sign-up, no telemetry — ever.
          </AnimatedText>
        </div>
      </div>
    </section>
  )
}
