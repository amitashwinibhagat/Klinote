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

/**
 * Stores a contact enquiry in Netlify Blobs.
 *
 * This replaced Netlify Forms, which silently discarded browser submissions
 * here while still answering 200 with a success page: eleven attempts were
 * logged, five stored, and every one that came from a browser was dropped with
 * no error and no spam-list entry. A contact form that loses enquiries without
 * saying so is worse than no form, so the submission path is owned here and the
 * caller gets an explicit answer it can check.
 *
 * Read what arrived with:
 *   netlify blobs:list klinote-contact
 *   netlify blobs:get klinote-contact <key>
 */
export const submitContact = createServerFn({ method: 'POST' })
  .inputValidator((input: unknown): ContactInput => {
    const raw = (input ?? {}) as Record<string, unknown>
    return {
      name: clean(raw.name, 120),
      practice: clean(raw.practice, 160),
      email: clean(raw.email, 200),
      topic: clean(raw.topic, 40) || 'other',
      message: clean(raw.message, MAX_MESSAGE),
      website: clean(raw.website, 200),
    }
  })
  .handler(async ({ data }) => {
    // Bot trap. Answer as if it worked so the caller learns nothing.
    if (data.website) {
      return { ok: true as const }
    }

    if (!data.name || !data.message) {
      return { ok: false as const, error: 'missing_fields' as const }
    }
    if (!data.email.includes('@') || data.email.length < 5) {
      return { ok: false as const, error: 'invalid_email' as const }
    }

    try {
      const { getStore } = await import('@netlify/blobs')
      const store = getStore('klinote-contact')
      const receivedAt = new Date().toISOString()
      const key = `${receivedAt}-${crypto.randomUUID()}`
      await store.setJSON(key, {
        name: data.name,
        practice: data.practice,
        email: data.email,
        topic: data.topic,
        message: data.message,
        receivedAt,
      })
      return { ok: true as const }
    } catch (error) {
      console.error('contact: could not store submission', error)
      return { ok: false as const, error: 'storage_failed' as const }
    }
  })
