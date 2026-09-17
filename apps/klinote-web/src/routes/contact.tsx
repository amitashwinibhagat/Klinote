import { createFileRoute, Link } from '@tanstack/react-router'
import * as React from 'react'
import { ArrowUpRight } from 'lucide-react'
import { AnimatedHeading, AnimatedText } from '~/components/AnimatedHeading'
import { submitContact } from '~/server/contact'
import { logoDark } from '~/assets'

export const Route = createFileRoute('/contact')({
  validateSearch: (search: Record<string, unknown>) => ({
    topic:
      search.topic === 'cohort' || search.topic === 'template' || search.topic === 'other'
        ? search.topic
        : undefined,
  }),
  component: ContactPage,
})

type Status = 'idle' | 'sending' | 'sent' | 'failed'

const TOPIC_LABELS: Record<string, string> = {
  cohort: 'Founding cohort',
  template: 'A template built for you',
  other: 'Enquiry',
}

const FORM_FIELDS = ['name', 'practice', 'email', 'topic', 'message'] as const

function ContactPage() {
  const { topic } = Route.useSearch()
  const [status, setStatus] = React.useState<Status>('idle')
  const [draft, setDraft] = React.useState<Record<string, string>>({})

  const onSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    const data = new FormData(e.currentTarget)
    const values: Record<string, string> = {}
    for (const field of FORM_FIELDS) {
      values[field] = String(data.get(field) ?? '')
    }
    setDraft(values)
    setStatus('sending')

    try {
      // The server answers explicitly, so a success state means the message was
      // written to storage. Never infer receipt from a status code alone.
      const result = await submitContact({
        data: {
          name: values.name,
          practice: values.practice,
          email: values.email,
          topic: values.topic,
          message: values.message,
          website: String(data.get('website') ?? ''),
        },
      })
      setStatus(result.ok ? 'sent' : 'failed')
    } catch {
      setStatus('failed')
    }
  }

  const fallbackMailto = React.useMemo(() => {
    const body = [
      draft.message ?? '',
      '',
      '---',
      `Name: ${draft.name ?? ''}`,
      draft.practice ? `Practice: ${draft.practice}` : null,
      `Email: ${draft.email ?? ''}`,
    ]
      .filter(Boolean)
      .join('\n')
    const subject = `Klinote: ${TOPIC_LABELS[draft.topic ?? 'other'] ?? 'Enquiry'}`
    return `mailto:amit@datadab.com?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`
  }, [draft])

  return (
    <div className="min-h-screen bg-background text-foreground">
      <div className="px-8 md:px-12 pt-10">
        <Link to="/" aria-label="Klinote home">
          <img src={logoDark} alt="Klinote" className="h-8 w-auto" />
        </Link>
      </div>

      <section className="py-24 px-8 md:px-12">
        <div className="max-w-2xl">
          <p className="text-xs tracking-[0.2em] uppercase text-muted-foreground font-mono mb-10">
            Klinote · Contact
          </p>

          <AnimatedHeading as="h1" className="text-5xl md:text-6xl font-medium leading-[1.05]">
            A person reads this
          </AnimatedHeading>

          <AnimatedText className="text-base text-muted-foreground leading-relaxed mt-6">
            Questions about the founding cohort, a template build, or anything
            else on the page. Replies come from me, not a ticketing system.
          </AnimatedText>

          {status === 'sent' ? (
            <div className="mt-16 border-t border-border pt-10">
              <p className="text-2xl font-medium">Received.</p>
              <p className="text-sm text-muted-foreground leading-relaxed mt-4 max-w-lg">
                It comes straight to me and I reply to the address you gave
                {draft.email ? <> ({draft.email})</> : null}.
              </p>
              <Link
                to="/"
                className="mt-8 inline-flex items-center gap-3 font-medium text-sm bg-foreground text-background rounded-full pl-6 pr-2 py-2 hover:opacity-90 transition"
              >
                Back to the page
                <span className="w-9 h-9 rounded-full bg-background text-foreground flex items-center justify-center">
                  <ArrowUpRight className="w-4 h-4" />
                </span>
              </Link>
            </div>
          ) : (
            <form
              name="klinote-contact"
              onSubmit={onSubmit}
              className="mt-16"
              noValidate
            >
              <p className="hidden" aria-hidden="true">
                <label>
                  Leave this field empty: <input name="website" tabIndex={-1} autoComplete="off" />
                </label>
              </p>

              <noscript>
                <p className="mb-8 text-sm text-muted-foreground leading-relaxed">
                  This form needs JavaScript. Without it, write to{' '}
                  <a
                    href="mailto:amit@datadab.com"
                    className="text-foreground underline underline-offset-4 decoration-border"
                  >
                    amit@datadab.com
                  </a>
                  .
                </p>
              </noscript>

              {status === 'failed' ? (
                <div className="mb-10 border border-border rounded-lg p-6 bg-surface">
                  <p className="text-sm text-foreground font-medium">
                    That did not send. Nothing was received.
                  </p>
                  <p className="text-sm text-muted-foreground leading-relaxed mt-2">
                    Your message is kept below. Send it by email instead and it
                    opens with everything you typed already in place, or write to{' '}
                    <a
                      href="mailto:amit@datadab.com"
                      className="text-foreground underline underline-offset-4 decoration-border hover:decoration-foreground transition"
                    >
                      amit@datadab.com
                    </a>
                    .
                  </p>
                  <a
                    href={fallbackMailto}
                    className="mt-6 inline-flex items-center gap-3 font-medium text-sm bg-foreground text-background rounded-full pl-6 pr-2 py-2 hover:opacity-90 transition"
                  >
                    Send it by email instead
                    <span className="w-9 h-9 rounded-full bg-background text-foreground flex items-center justify-center">
                      <ArrowUpRight className="w-4 h-4" />
                    </span>
                  </a>
                </div>
              ) : null}

              <div className="grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-8">
                <Field label="Name">
                  <input
                    name="name"
                    required
                    autoComplete="name"
                    className="w-full bg-background border border-border rounded-md px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-foreground/30"
                  />
                </Field>
                <Field label="Practice (optional)">
                  <input
                    name="practice"
                    autoComplete="organization"
                    className="w-full bg-background border border-border rounded-md px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-foreground/30"
                  />
                </Field>
                <Field label="Email">
                  <input
                    name="email"
                    type="email"
                    required
                    autoComplete="email"
                    className="w-full bg-background border border-border rounded-md px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-foreground/30"
                  />
                </Field>
                <Field label="What it is about">
                  <select
                    name="topic"
                    defaultValue={topic ?? 'other'}
                    className="w-full bg-background border border-border rounded-md px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-foreground/30"
                  >
                    <option value="cohort">Founding cohort</option>
                    <option value="template">A template built for you</option>
                    <option value="other">Something else</option>
                  </select>
                </Field>
              </div>

              <div className="mt-8">
                <Field label="Message">
                  <textarea
                    name="message"
                    required
                    rows={6}
                    className="w-full bg-background border border-border rounded-md px-4 py-3 text-sm leading-relaxed focus:outline-none focus:ring-2 focus:ring-foreground/30"
                  />
                </Field>
              </div>

              <button
                type="submit"
                disabled={status === 'sending'}
                className="mt-10 inline-flex items-center gap-3 font-medium text-sm bg-foreground text-background rounded-full pl-6 pr-2 py-2 hover:opacity-90 transition disabled:opacity-50"
              >
                {status === 'sending' ? 'Sending' : 'Send'}
                <span className="w-9 h-9 rounded-full bg-background text-foreground flex items-center justify-center">
                  <ArrowUpRight className="w-4 h-4" />
                </span>
              </button>
            </form>
          )}
        </div>
      </section>
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="block text-xs tracking-[0.2em] uppercase text-muted-foreground font-mono mb-3">
        {label}
      </span>
      {children}
    </label>
  )
}
