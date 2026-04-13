#!/usr/bin/env node
/**
 * Photo optimizer for Dogs & Llamas
 *
 * Usage:
 *   node scripts/optimize-photos.js          — process media/originals/
 *   node scripts/optimize-photos.js some.jpg  — process a single file
 *   npm run photos                            — same as above (via package.json)
 *
 * What it does:
 *   1. Scans media/originals/ for JPG, PNG, HEIC, WEBP files
 *   2. Resizes to max 1600px wide → media/{name}.jpg  (full size, quality 82)
 *   3. Resizes to max 400px wide  → media/thumbs/{name}.jpg  (gallery thumbnail)
 *   4. Skips files that already have an output in media/ (use --force to re-process)
 *
 * Note: DNG (raw) files are NOT supported by sharp. Convert them to JPG/PNG
 * first using any photo app (Google Photos export, Lightroom, etc.) then drop
 * the JPG into media/originals/.
 */

const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const ORIGINALS = path.join(ROOT, 'media', 'originals');
const MEDIA = path.join(ROOT, 'media');
const THUMBS = path.join(ROOT, 'media', 'thumbs');

const FULL_WIDTH = 1600;
const THUMB_WIDTH = 400;
const QUALITY = 82;
const SUPPORTED = /\.(jpe?g|png|webp|heic|heif|tiff?|dng)$/i;

const force = process.argv.includes('--force');

async function processFile(inputPath) {
  const ext = path.extname(inputPath);
  const baseName = path.basename(inputPath, ext);
  // Normalize filename: spaces → hyphens, lowercase
  const safeName = baseName.replace(/\s+/g, '-').toLowerCase();
  const outFull = path.join(MEDIA, safeName + '.jpg');
  const outThumb = path.join(THUMBS, safeName + '.jpg');

  if (!force && fs.existsSync(outFull) && fs.existsSync(outThumb)) {
    console.log(`  skip: ${baseName} (already exists — use --force to re-process)`);
    return;
  }

  console.log(`  processing: ${path.basename(inputPath)}`);

  const img = sharp(inputPath).rotate(); // auto-rotate from EXIF

  // Full-size (max 1600px wide, preserve aspect ratio)
  await img
    .clone()
    .resize({ width: FULL_WIDTH, withoutEnlargement: true })
    .jpeg({ quality: QUALITY, mozjpeg: true })
    .toFile(outFull);

  const fullStat = fs.statSync(outFull);
  console.log(`    → media/${safeName}.jpg (${(fullStat.size / 1024).toFixed(0)} KB)`);

  // Thumbnail (400×400 square crop, center-weighted so the dog stays in frame)
  await img
    .clone()
    .resize({ width: THUMB_WIDTH, height: THUMB_WIDTH, fit: 'cover', position: 'attention' })
    .jpeg({ quality: 78, mozjpeg: true })
    .toFile(outThumb);

  const thumbStat = fs.statSync(outThumb);
  console.log(`    → media/thumbs/${safeName}.jpg (${(thumbStat.size / 1024).toFixed(0)} KB)`);
}

async function main() {
  // Ensure output dirs exist
  fs.mkdirSync(MEDIA, { recursive: true });
  fs.mkdirSync(THUMBS, { recursive: true });

  // If a specific file was passed as an argument, process just that
  const specificFile = process.argv.find(a => !a.startsWith('-') && a !== process.argv[0] && a !== process.argv[1]);
  if (specificFile) {
    const abs = path.resolve(specificFile);
    if (!fs.existsSync(abs)) {
      console.error(`File not found: ${abs}`);
      process.exit(1);
    }
    await processFile(abs);
    console.log('\nDone.');
    return;
  }

  // Otherwise, scan media/originals/
  if (!fs.existsSync(ORIGINALS)) {
    console.log('No media/originals/ folder found. Create it and drop photos in.');
    return;
  }

  const files = fs.readdirSync(ORIGINALS).filter(f => SUPPORTED.test(f));
  if (files.length === 0) {
    console.log('No supported image files in media/originals/. Drop JPG/PNG/HEIC/WEBP files in.');
    console.log('(DNG/RAW files need to be exported to JPG first — use Google Photos or any photo app.)');
    return;
  }

  console.log(`Found ${files.length} image(s) in media/originals/\n`);

  for (const file of files) {
    try {
      await processFile(path.join(ORIGINALS, file));
    } catch (err) {
      console.error(`  ERROR processing ${file}: ${err.message}`);
    }
  }

  console.log('\nDone. Add the new photos to gallery.html or the GALLERY array.');
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
