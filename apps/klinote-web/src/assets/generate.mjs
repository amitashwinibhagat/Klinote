// Generates every static brand asset the site needs, from the two source SVGs:
//   og-source.svg   -> og.png (1200x630 social card)
//   icon-source.svg -> favicon 32/16, apple-touch-icon 180, icon 192/512
//
// Run after changing either source:  node src/assets/generate.mjs
import sharp from 'sharp'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { pngToIco } from './png-to-ico.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const pub = join(here, '..', '..', 'public')

const og = readFileSync(join(here, 'og-source.svg'))
const icon = readFileSync(join(here, 'icon-source.svg'))

await sharp(og).png().toFile(join(pub, 'og.png'))

for (const size of [16, 32, 180, 192, 512]) {
  const name =
    size === 180 ? 'apple-touch-icon.png'
    : size === 512 ? 'icon-512.png'
    : size === 192 ? 'icon-192.png'
    : `favicon-${size}x${size}.png`
  await sharp(icon).resize(size, size).png().toFile(join(pub, name))
}

// A real .ico containing 16 and 32, for browsers that still ask for it by name.
// sharp in this build has no .ico() output, so the container is written here.
const tmp = join(pub, 'favicon-32x32.png')
pngToIco(tmp, join(pub, 'favicon.ico'), 32)

console.log('generated brand assets into public/')
