// Dependency-free PWA icon generator.
// Draws the Moonlog crescent (accent on Night-bg) and encodes PNGs using only
// Node built-ins (zlib for DEFLATE). Runs automatically on `npm run dev|build`.
import { deflateSync } from 'node:zlib';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');

// --- Palette (Sleepy Llamas maroon Night theme) ---
const BG = [0x1a, 0x0a, 0x0e]; // maroon-black
const ACCENT = [0xd9, 0xa9, 0x6b]; // brand gold
const ACCENT_DEEP = [0xbd, 0x87, 0x48];
const STAR = [0xf0, 0xd2, 0xcb]; // blush

const lerp = (a, b, t) => a + (b - a) * t;
const mix = (c1, c2, t) => [lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t)];

// CRC32 (PNG chunk checksums)
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const body = Buffer.concat([typeBuf, data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}
function encodePNG(width, height, rgba) {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type RGBA
  // 10,11,12 = compression, filter, interlace = 0
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0; // filter: none
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride);
  }
  const idat = deflateSync(raw, { level: 9 });
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
}

// Stars in fractional coordinates (x, y, radius-fraction)
const STARS = [
  [0.74, 0.26, 0.018],
  [0.83, 0.42, 0.012],
  [0.68, 0.5, 0.01],
];

// coverage helper for a filled circle, returns color or null at a point
function crescentColor(px, py, S, scale) {
  // outer disc and offset cut-out disc -> crescent
  const cx = S * 0.5;
  const cy = S * 0.52;
  const rOuter = S * 0.34 * scale;
  const rCut = S * 0.3 * scale;
  const cutX = cx + S * 0.135 * scale;
  const cutY = cy - S * 0.1 * scale;
  const dOuter = Math.hypot(px - cx, py - cy);
  const dCut = Math.hypot(px - cutX, py - cutY);
  if (dOuter <= rOuter && dCut >= rCut) {
    const t = (py - (cy - rOuter)) / (2 * rOuter); // vertical gradient
    return mix(ACCENT, ACCENT_DEEP, Math.max(0, Math.min(1, t)));
  }
  // stars (only outside the moon disc area)
  for (const [sx, sy, sr] of STARS) {
    if (Math.hypot(px - sx * S, py - sy * S) <= sr * S * scale) return STAR;
  }
  return null;
}

function render(size, { scale = 1 } = {}) {
  const rgba = Buffer.alloc(size * size * 4);
  const SS = 2; // 2x2 supersampling for smooth edges
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let r = 0, g = 0, b = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const px = x + (sx + 0.5) / SS;
          const py = y + (sy + 0.5) / SS;
          const c = crescentColor(px, py, size, scale) ?? BG;
          r += c[0]; g += c[1]; b += c[2];
        }
      }
      const n = SS * SS;
      const i = (y * size + x) * 4;
      rgba[i] = Math.round(r / n);
      rgba[i + 1] = Math.round(g / n);
      rgba[i + 2] = Math.round(b / n);
      rgba[i + 3] = 255;
    }
  }
  return encodePNG(size, size, rgba);
}

const outDir = resolve(root, 'public/icons');
mkdirSync(outDir, { recursive: true });

const targets = [
  ['public/icons/icon-192.png', render(192)],
  ['public/icons/icon-512.png', render(512)],
  // maskable: shrink into the inner ~80% safe zone, full-bleed bg
  ['public/icons/maskable-512.png', render(512, { scale: 0.78 })],
  ['public/apple-touch-icon.png', render(180)],
];
for (const [rel, buf] of targets) {
  const p = resolve(root, rel);
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, buf);
}
console.log(`moonlog: generated ${targets.length} icons`);
