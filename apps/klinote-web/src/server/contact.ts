import { createServerFn } from '@tanstack/react-start'

export type ContactInput = {
  name: string
  practice: string
  email: string
  topic: string
  message: string
  /** Honeypot. Bots fill it; people never see it. */
  website: string
}

const MAX_MESSAGE = 5000

function clean(value: unknown, limit = 300): string {
  return String(value ?? '').trim().slice(0, limit)
}

/// Header-safe single-line fields. A newline in a name went into the Resend
/// subject; a malformed email made Resend reject the notice while the page
/// still said "Received".
function oneLine(value: unknown, limit = 300): string {
  return clean(value, limit).replace(/[\r\n]+/g, ' ').trim()
}

function validEmail(value: string): boolean {
  return value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)
}

/// Instance-local throttle. Netlify may run several instances, so this is not
/// a hard guarantee; it stops a single page being hammered from one address
/// and costs nothing. A production deployment should pair it with an edge
/// limit or Turnstile.
const recent = new Map<string, number[]>()
const WINDOW_MS = 10 * 60 * 1000
const MAX_PER_WINDOW = 3

function throttled(email: string, now = Date.now()): boolean {
  const key = email.toLowerCase()
  const seen = (recent.get(key) ?? []).filter((at) => now - at < WINDOW_MS)
  if (seen.length >= MAX_PER_WINDOW) {
    recent.set(key, seen)
    return true
  }
  seen.push(now)
  recent.set(key, seen)
  return false
}

function summary(data: ContactInput): string {
  const lines = [
    `New Klinote enquiry: ${data.name}${data.practice ? ` (${data.practice})` : ''}`,
    `Topic: ${data.topic}`,
    `Reply to: ${data.email}`,
    '',
    data.message,
  ]
  return lines.join('\n')
}

/**
 * Tells someone. Returns whether a channel was configured and reached.
 *
 * A submission is never lost just because this fails: the blob is written
 * first and stays the record. This exists because a form whose messages nobody
 * is told about is not a contact form, which is what the first version of this
 * shipped as.
 *
 * Configure exactly one of:
 *   CONTACT_WEBHOOK_URL   Slack or Discord incoming webhook (one pasted URL)
 *   RESEND_API_KEY + CONTACT_TO   email via Resend
 *
 * CONTACT_FROM overrides the sender. It defaults to Resend's test address,
 * which can only deliver to the account owner's own email until a domain is
 * verified. Once klinote.one is verified, set
 * CONTACT_FROM="Klinote enquiries <enquiries@klinote.one>" and notifications
 * can go to any address.
 */
async function notify(data: ContactInput): Promise<'sent' | 'skipped' | 'failed'> {
  const webhook = process.env.CONTACT_WEBHOOK_URL
  const resendKey = process.env.RESEND_API_KEY
  const to = process.env.CONTACT_TO
  const text = summary(data)

  try {
    if (webhook) {
      // Slack reads "text", Discord reads "content". Sending both is harmless
      // and means one variable works for either.
      const res = await fetch(webhook, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text, content: text }),
        signal: AbortSignal.timeout(10_000),
      })
      if (!res.ok) {
        console.error('contact: webhook rejected the notice', res.status)
        return 'failed'
      }
      return 'sent'
    }

    if (resendKey && to) {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${resendKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: process.env.CONTACT_FROM || 'Klinote enquiries <onboarding@resend.dev>',
          // CONTACT_TO may list several addresses, comma separated.
          to: to.split(',').map((address) => address.trim()).filter(Boolean),
          // So hitting Reply answers the prospect, not Resend's test address.
          reply_to: data.email,
          subject: `Klinote enquiry from ${data.name}`,
          text,
        }),
        signal: AbortSignal.timeout(10_000),
      })
      if (!res.ok) {
        console.error('contact: resend rejected the notice', res.status, await res.text())
        return 'failed'
      }
      return 'sent'
    }
  } catch (error) {
    console.error('contact: notification failed', error)
    return 'failed'
  }

  // No channel configured. The enquiry is still stored; this line is the alarm.
  console.error(
    'contact: NO NOTIFICATION CHANNEL CONFIGURED — enquiry stored but nobody was told. ' +
      'Set CONTACT_WEBHOOK_URL, or RESEND_API_KEY and CONTACT_TO.',
  )
  return 'skipped'
}

/**
 * Stores an enquiry in Netlify Blobs, then tries to announce it.
 *
 * Read what arrived with `npm run enquiries`, or:
 *   netlify blobs:list klinote-contact
 *   netlify blobs:get klinote-contact <key>
 */
export const submitContact = createServerFn({ method: 'POST' })
  .validator((input: unknown): ContactInput => {
    const raw = (input ?? {}) as Record<string, unknown>
    return {
      name: oneLine(raw.name, 120),
      practice: oneLine(raw.practice, 160),
      email: oneLine(raw.email, 254),
      topic: oneLine(raw.topic, 40) || 'other',
      message: clean(raw.message, MAX_MESSAGE),
      website: oneLine(raw.website, 200),
    }
  })
  .handler(async ({ data }) => {
    try {
      const { getStore } = await import('@netlify/blobs')
      const store = getStore('klinote-contact')
      const receivedAt = new Date().toISOString()
      const key = `${receivedAt}-${crypto.randomUUID()}`

      if (data.website) {
        // A bot, or a person whose password manager filled a hidden field.
        // Keep it under a separate key so a false positive is recoverable,
        // and do not tell the visitor the human notice went out.
        await store.setJSON(`spam-${key}`, {
          name: data.name,
          practice: data.practice,
          email: data.email,
          topic: data.topic,
          message: data.message,
          receivedAt,
          spam: true,
        })
        return { ok: false as const, error: 'spam' as const }
      }

      if (!data.name || !data.message) {
        return { ok: false as const, error: 'missing_fields' as const }
      }
      if (!validEmail(data.email)) {
        return { ok: false as const, error: 'invalid_email' as const }
      }
      if (throttled(data.email)) {
        return { ok: false as const, error: 'rate_limited' as const }
      }

      await store.setJSON(key, {
        name: data.name,
        practice: data.practice,
        email: data.email,
        topic: data.topic,
        message: data.message,
        receivedAt,
      })

      // Stored first, so a failed notice still leaves the enquiry on record.
      // The client is told which of those two things happened.
      const notified = await notify(data)
      return { ok: true as const, notified }
    } catch (error) {
      console.error('contact: could not store submission', error)
      return { ok: false as const, error: 'storage_failed' as const }
    }
  })
