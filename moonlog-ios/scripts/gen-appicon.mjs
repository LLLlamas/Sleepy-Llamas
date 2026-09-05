// Dependency-free app-icon generator.
//
// Draws the same Moonlog crescent as the retired PWA — same geometry, same Night
// palette — so the brand carries over. Node built-ins only; no image library.
//
//   node scripts/gen-appicon.mjs
//
// Output is committed, since an icon changes rarely and a build should not depend
// on regenerating it. iOS app icons must be OPAQUE: an alpha channel is rejected
// at upload, so every pixel is written at full alpha.
import { deflateSync } from 'node:zlib';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const BG = [0x1a, 0x0a, 0x0e];          // Night maroon-black
const ACCENT = [0xd9, 0xa9, 0x6b];      // brand gold
const ACCENT_DEEP = [0xbd, 0x87, 0x48];
const STAR = [0xf0, 0xd2, 0xcb];        // blush

const lerp = (a, b, t) => a + (b - a) * t;
const mix = (c1, c2, t) => [lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t)];

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
const crc32 = (buf) => {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const chunk = (type, data) => {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
};

/** 8-bit RGB, no alpha channel at all — colour type 2. */
function encodePNG(size, rgb) {
  const stride = size * 3;
  const raw = Buffer.alloc((stride + 1) * size);
  for (let y = 0; y < size; y++) {
    raw[y * (stride + 1)] = 0; // filter: none
    rgb.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 2;   // truecolour, no alpha
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const STARS = [
  [0.74, 0.26, 0.018],
  [0.83, 0.42, 0.012],
  [0.68, 0.5, 0.01],
];

/** Outer disc minus an offset cut-out disc: the crescent. */
function crescentColor(px, py, S, scale) {
  const cx = S * 0.5;
  const cy = S * 0.52;
  const rOuter = S * 0.34 * scale;
  const rCut = S * 0.3 * scale;
  const cutX = cx + S * 0.135 * scale;
  const cutY = cy - S * 0.1 * scale;
  if (Math.hypot(px - cx, py - cy) <= rOuter && Math.hypot(px - cutX, py - cutY) >= rCut) {
    const t = (py - (cy - rOuter)) / (2 * rOuter);
    return mix(ACCENT, ACCENT_DEEP, Math.max(0, Math.min(1, t)));
  }
  for (const [sx, sy, sr] of STARS) {
    if (Math.hypot(px - sx * S, py - sy * S) <= sr * S * scale) return STAR;
  }
  return null;
}

function render(size, scale) {
  const rgb = Buffer.alloc(size * size * 3);
  const SS = 3; // supersampling — 1024px is large enough that edges show
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let r = 0, g = 0, b = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const c = crescentColor(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS, size, scale) ?? BG;
          r += c[0]; g += c[1]; b += c[2];
        }
      }
      const n = SS * SS;
      const i = (y * size + x) * 3;
      rgb[i] = Math.round(r / n);
      rgb[i + 1] = Math.round(g / n);
      rgb[i + 2] = Math.round(b / n);
    }
  }
  return encodePNG(size, rgb);
}

// 0.92 rather than full bleed: iOS rounds the corners, and the crescent should
// not crowd them.
const out = resolve(root, 'Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png');
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, render(1024, 0.92));
console.log('moonlog: generated', out);
