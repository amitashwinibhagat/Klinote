#!/usr/bin/env node
// Prints every stored enquiry, newest first.
//
//   npm run enquiries
//
// Reads Netlify Blobs through the Netlify CLI, so it uses the same login the
// deploys use and needs no API key of its own.
import { execFileSync } from 'node:child_process'

const STORE = 'klinote-contact'

function cli(args) {
  return execFileSync('netlify', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
}

let listing
try {
  listing = cli(['blobs:list', STORE])
} catch {
  console.error(`No store named "${STORE}" yet. If that is unexpected, check the Netlify login.`)
  process.exit(0)
}

// Honeypot submissions are stored under `spam-<same key>`. The old pattern
// stripped that prefix and then asked Blobs for a key that did not exist, so
// every spam entry appeared as an unreadable enquiry.
const keys = [...listing.matchAll(/(?:spam-)?[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z-[0-9a-f-]{36}/g)]
  .map((m) => m[0])
  .sort()
  .reverse()

if (keys.length === 0) {
  console.log('No enquiries.')
  process.exit(0)
}

console.log(`${keys.length} enquir${keys.length === 1 ? 'y' : 'ies'}\n`)

for (const key of keys) {
  let raw
  try {
    raw = cli(['blobs:get', STORE, key])
  } catch (error) {
    console.error(`could not read ${key}: ${error.message}`)
    continue
  }
  const start = raw.indexOf('{')
  if (start < 0) continue
  const body = JSON.parse(raw.slice(start))

  console.log('─'.repeat(64))
  const spam = key.startsWith('spam-') || body.spam === true
  console.log(`${body.receivedAt}   [${body.topic}]${spam ? ' · spam/honeypot' : ''}`)
  console.log(`${body.name}${body.practice ? ` — ${body.practice}` : ''}`)
  console.log(`Reply to: ${body.email}`)
  console.log('')
  console.log(body.message)
  console.log('')
}
