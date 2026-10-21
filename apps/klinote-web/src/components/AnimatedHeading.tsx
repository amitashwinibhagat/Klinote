import * as React from 'react'
import { motion, useReducedMotion } from 'motion/react'

const EASE = [0.22, 1, 0.36, 1] as const

/**
 * Every headline on the page enters the same way: rising out of a blur.
 * Used for h1/h2/h3 alike via the `as` prop.
 */
export function AnimatedHeading({
  children,
  className,
  as: As = 'h2',
  delay = 0,
}: {
  children: React.ReactNode
  className?: string
  as?: React.ElementType
  delay?: number
}) {
  const reduceMotion = useReducedMotion()
  const MotionTag = React.useMemo(() => motion.create(As), [As])
  const classes = [className, 'klinote-motion'].filter(Boolean).join(' ')

  if (reduceMotion) {
    return <As className={classes}>{children}</As>
  }

  return (
    <MotionTag
      className={classes}
      initial={{ opacity: 0, y: 30, filter: 'blur(12px)' }}
      whileInView={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
      viewport={{ once: true, margin: '-80px' }}
      transition={{ duration: 0.9, delay, ease: EASE }}
    >
      {children}
    </MotionTag>
  )
}

/**
 * Body copy: a quieter rise, no blur. Slightly later by default so a heading
 * always lands before its paragraph.
 */
export function AnimatedText({
  children,
  className,
  delay = 0.15,
}: {
  children: React.ReactNode
  className?: string
  delay?: number
}) {
  const reduceMotion = useReducedMotion()
  const classes = [className, 'klinote-motion'].filter(Boolean).join(' ')

  if (reduceMotion) {
    return <p className={classes}>{children}</p>
  }

  return (
    <motion.p
      className={classes}
      initial={{ opacity: 0, y: 20 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-80px' }}
      transition={{ duration: 0.7, delay, ease: EASE }}
    >
      {children}
    </motion.p>
  )
}

/**
 * Images are content, not an animation. The original clip-path reveal left the
 * image fully clipped whenever the in-view observer did not fire — which was
 * every image in the mobile step list — so the page showed empty grey boxes.
 * A reliable image beats a decorative reveal.
 */
export function MaskedImage({
  src,
  alt,
  className,
}: {
  src: string
  alt: string
  className?: string
  delay?: number
}) {
  return (
    <div className={className}>
      <img src={src} alt={alt} className="w-full h-full object-cover" loading="lazy" referrerPolicy="no-referrer" />
    </div>
  )
}
