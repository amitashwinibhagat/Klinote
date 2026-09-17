// Emits a genuine ICO (not a renamed PNG) containing the given PNG at one size.
// ICO container: 6-byte header, one 16-byte directory entry, then the PNG bytes.
// Vista+ ICOs store PNG directly; no BMP/PNG-DIB encoding is needed.
import { readFileSync, writeFileSync } from 'node:fs'

export function pngToIco(pngPath, outPath, size) {
  const png = readFileSync(pngPath)
  const buf = Buffer.alloc(6 + 16 + png.length)
  buf.writeUInt16LE(0, 0) // reserved
  buf.writeUInt16LE(1, 2) // type: 1 = icon
  buf.writeUInt16LE(1, 4) // count
  buf.writeUInt8(size === 256 ? 0 : size, 6) // width
  buf.writeUInt8(size === 256 ? 0 : size, 7) // height
  buf.writeUInt8(0, 8) // colour count: 0 = no palette
  buf.writeUInt8(0, 9) // reserved
  buf.writeUInt16LE(1, 10) // colour planes
  buf.writeUInt16LE(32, 12) // bits per pixel
  buf.writeUInt32LE(png.length, 14) // image size
  buf.writeUInt32LE(22, 18) // offset to image data
  png.copy(buf, 22)
  writeFileSync(outPath, buf)
}
