import * as React from 'react'
import { AnimatePresence, motion } from 'motion/react'
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
    desc: 'Capture the session, or dictate it after. A patient-visible strip keeps consent where it belongs — on the desk, not in a settings screen.',
  },
  {
    img: transcribe,
    role: 'STEP 02',
    name: 'Transcribe',
    desc: 'Speech recognition runs on the Mac itself — the system’s own engine. No download to wait for, no request to leave the room.',
  },
  {
    img: route,
    role: 'STEP 03',
    name: 'Route',
    desc: 'Each statement is filed into the structure your discipline actually documents in — DAP, BIRP, SOAP — not a generic dump.',
  },
  {
    img: cite,
    role: 'STEP 04',
    name: 'Cite',
    desc: 'Every sentence carries the words that produced it, and a quote that is not in the transcript does not enter the note. This step is the product.',
  },
  {
    img: sign,
    role: 'STEP 05',
    name: 'Sign',
    desc: 'You review, correct and file. Required sections you did not cover are named out loud, not hidden. The machine never signs — only you can.',
  },
] as const

const INTRO_WIDTH = 324
const GAP = 11.26
const VISIBLE = 3.25
const MAX_INDEX = Math.max(0, Math.ceil(STEPS.length - VISIBLE))

export function TeamCarousel({ intro }: { intro: React.ReactNode }) {
  const [index, setIndex] = React.useState(0)
  const [hovered, setHovered] = React.useState(false)

  return (
    <div
      className="relative"
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
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
            transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
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

      <AnimatePresence>
        {hovered && (
          <motion.div
            className="absolute top-[35%] left-1/2 -translate-x-1/2 -translate-y-1/2 z-10"
            initial={{ opacity: 0, scale: 0.85 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.85 }}
            transition={{ duration: 0.25 }}
          >
            <div
              className="flex items-center justify-center gap-4 rounded-full cursor-pointer"
              style={{
                width: 126,
                height: 126,
                background: 'rgba(72, 72, 72, 0.16)',
                backdropFilter: 'blur(84px)',
                WebkitBackdropFilter: 'blur(84px)',
              }}
            >
              <button
                className="flex items-center justify-center text-white disabled:opacity-30 transition cursor-pointer"
                disabled={index === 0}
                onClick={() => setIndex((i) => Math.max(0, i - 1))}
                aria-label="Previous step"
              >
                <ArrowLeft className="w-7 h-7" />
              </button>
              <button
                className="flex items-center justify-center text-white disabled:opacity-30 transition cursor-pointer"
                disabled={index >= MAX_INDEX}
                onClick={() => setIndex((i) => Math.min(MAX_INDEX, i + 1))}
                aria-label="Next step"
              >
                <ArrowRight className="w-7 h-7" />
              </button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
