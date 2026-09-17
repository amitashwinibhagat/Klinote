import * as React from 'react'
import { motion } from 'motion/react'

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
  const MotionTag = motion(As)

  return (
    <MotionTag
      className={className}
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
  return (
    <motion.p
      className={className}
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
 * Images reveal downward, unmasking from bottom to top. The clip starts fully
 * closed from the top edge, so the first thing seen is the bottom of the image.
 */
export function MaskedImage({
  src,
  alt,
  className,
  delay = 0,
}: {
  src: string
  alt: string
  className?: string
  delay?: number
}) {
  return (
    <motion.div
      className={className}
      initial={{ clipPath: 'inset(100% 0 0 0)' }}
      whileInView={{ clipPath: 'inset(0% 0 0 0)' }}
      viewport={{ once: true, margin: '-80px' }}
      transition={{ duration: 1.1, delay, ease: EASE }}
    >
      <img src={src} alt={alt} className="w-full h-full object-cover" />
    </motion.div>
  )
}
