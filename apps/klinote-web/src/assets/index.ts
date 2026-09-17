// The asset bundle ships from qclay.design/lovable/pelmatech/. The template's
// doctor photographs are kept — a clinical product earns its imagery — but the
// semantic slots are renamed to the steps of the product rather than to people
// there is no permission to name. See docs/marketing/LANDING-COPY.md.
const BASE = 'https://qclay.design/lovable/pelmatech/'

export const heroImage = `${BASE}doctor-computer.png`

// The notarized build, published as a GitHub release asset. It is a .zip, not
// a .dmg. Update both when a new version ships.
export const appVersion = '0.1.6'
export const downloadUrl =
  'https://github.com/amitashwinibhagat/Klinote/releases/download/v0.1.6/Klinote-0.1.6.zip'
export const releasesUrl = 'https://github.com/amitashwinibhagat/Klinote/releases'

export const clockLamp = `${BASE}clock-lamp.png`
export const pills = `${BASE}pills.png`
export const waitlist = `${BASE}waitlist.png`

// Carousel: five steps. The three portraits stand in for the five-step
// workflow; a full build replaces them with real product photography.
export const record = `${BASE}blur-doctor.png`
export const transcribe = `${BASE}happy-doctor.png`
export const route = `${BASE}young-doctor.png`
export const cite = `${BASE}happy-doctor.png`
export const sign = `${BASE}blur-doctor.png`

export { default as logo } from './logo.svg'
export { default as logoDark } from './logo-dark.svg'
