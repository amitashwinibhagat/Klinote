import * as React from 'react'
import { motion, useReducedMotion } from 'motion/react'
import { ArrowLeft, ArrowRight } from 'lucide-react'
import { MaskedImage } from './AnimatedHeading'
import { cite, record, route, sign, transcribe } from '~/assets'

// The template shipped a team carousel of five doctors. Klinote has no team to
// photograph and no permission to invent one, so the mechanism is kept exactly
// and the cards carry the five steps of the product instead.
//
// See docs/marketing/LANDING-COPY.md, "Design → copy mapping".
const STEPS = [
  {
    img: record,
    role: 'STEP 01',
    name: 'Record',
    desc: 'Capture the session, or dictate it after. The patient can see that recording is happening, because consent does not belong in a settings screen.',
  },
  {
    img: transcribe,
    role: 'STEP 02',
    name: 'Transcribe',
    desc: 'Speech recognition runs on the Mac with the system’s own engine. No speech model downloads; the optional note model is one download, on first use if you choose it.',
  },
  {
    img: route,
    role: 'STEP 03',
    name: 'Route',
    desc: 'Each statement is filed into the structure your discipline documents in — SOAP, a therapy note, physiotherapy, dentistry or veterinary.',
  },
  {
    img: cite,
    role: 'STEP 04',
    name: 'Cite',
    desc: 'Every sentence carries the words it came from. Figures and drug names that are not in those words are flagged. This step is the product.',
  },
  {
    img: sign,
    role: 'STEP 05',
    name: 'Sign',
    desc: 'You review, correct and file. Required sections you did not cover are named in the open. The machine never signs. Only you can.',
  },
] as const

const INTRO_WIDTH = 324
const GAP = 11.26
const VISIBLE = 3.25
const MAX_INDEX = Math.max(0, Math.ceil(STEPS.length - VISIBLE))

export function TeamCarousel({ intro }: { intro: React.ReactNode }) {
  const [index, setIndex] = React.useState(0)
  const reduceMotion = useReducedMotion()

  return (
    <>
      {/* Phones get the five steps as a readable list. The desktop carousel is
          a 1728 px composition; shrinking it to 390 px was a 22% miniature. */}
      <div className="lg:hidden">
        <div className="mb-10">{intro}</div>
        <div className="space-y-12">
          {STEPS.map((step) => (
            <div key={step.name}>
              <div className="aspect-[4/3] overflow-hidden bg-muted">
                <MaskedImage src={step.img} alt={step.name} className="w-full h-full" />
              </div>
              <p className="text-xs tracking-[0.2em] text-muted-foreground uppercase font-mono mt-5">
                {step.role}
              </p>
              <p className="text-xl mt-2 font-medium">{step.name}</p>
              <p className="text-sm text-muted-foreground leading-relaxed mt-3">
                {step.desc}
              </p>
            </div>
          ))}
        </div>
      </div>

      <div className="hidden lg:block relative">
        <div className="flex" style={{ gap: GAP }}>
          <div className="shrink-0" style={{ width: INTRO_WIDTH }}>
            {intro}
          </div>

          <div className="relative overflow-hidden flex-1 min-w-0">
          <motion.div
            className="flex"
            style={{
              gap: GAP,
              width: `calc(${STEPS.length} * ((100% - ${(VISIBLE - 1) * GAP}px) / ${VISIBLE}) + ${(STEPS.length - 1) * GAP}px)`,
            }}
            animate={{ x: `calc(${-index} * (100% + ${GAP}px) / ${STEPS.length})` }}
            transition={{ duration: reduceMotion ? 0 : 0.7, ease: [0.22, 1, 0.36, 1] }}
          >
            {STEPS.map((m, i) => (
              <div
                key={m.name}
                className="shrink-0"
                style={{
                  width: `calc((100% - ${(STEPS.length - 1) * GAP}px) / ${STEPS.length})`,
                }}
              >
                <div className="aspect-[3/4] overflow-hidden bg-muted">
                  <MaskedImage
                    src={m.img}
                    alt={m.name}
                    className="w-full h-full"
                    delay={i * 0.08}
                  />
                </div>
                <div className="pt-6">
                  <p className="text-xs tracking-[0.2em] text-muted-foreground uppercase font-mono">
                    {m.role}
                  </p>
                  <p className="text-xl mt-2 font-medium">{m.name}</p>
                  <p className="text-sm text-muted-foreground leading-relaxed mt-3">
                    {m.desc}
                  </p>
                </div>
              </div>
            ))}
            </motion.div>
          </div>
        </div>

        {/* Always visible, not on hover: a keyboard or touch user could not
            reach steps four and five when the controls only existed under the
            pointer. */}
        <div className="mt-8 flex items-center justify-center gap-4 rounded-full px-3 py-2 bg-black/35 backdrop-blur-md w-fit mx-auto">
          <button
            className="flex items-center justify-center text-white disabled:opacity-30 transition cursor-pointer"
            disabled={index === 0}
            onClick={() => setIndex((i) => Math.max(0, i - 1))}
            aria-label="Previous step"
          >
            <ArrowLeft className="w-6 h-6" />
          </button>
          <span className="font-mono text-[11px] tracking-[0.18em] text-white/80">
            {String(index + 1).padStart(2, '0')} / {String(STEPS.length).padStart(2, '0')}
          </span>
          <button
            className="flex items-center justify-center text-white disabled:opacity-30 transition cursor-pointer"
            disabled={index >= MAX_INDEX}
            onClick={() => setIndex((i) => Math.min(MAX_INDEX, i + 1))}
            aria-label="Next step"
          >
            <ArrowRight className="w-6 h-6" />
          </button>
        </div>
        <p className="sr-only" aria-live="polite">
          Step {index + 1} of {STEPS.length}
        </p>
      </div>
    </>
  )
}
