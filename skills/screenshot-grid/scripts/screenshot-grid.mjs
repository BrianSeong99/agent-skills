#!/usr/bin/env node
/**
 * screenshot-grid.mjs
 *
 * Captures per-viewport Playwright screenshots of a list of routes.
 * Writes PNGs to <out>/<viewport>/<route-slug>.png.
 *
 * Usage:
 *   node screenshot-grid.mjs [options]
 *
 * All options can also be set via environment variables (see --help).
 */

import { chromium } from 'playwright';
import { mkdir, writeFile } from 'fs/promises';
import { existsSync } from 'fs';
import { join } from 'path';

// ---------------------------------------------------------------------------
// Built-in viewport presets
// ---------------------------------------------------------------------------
const VIEWPORT_PRESETS = {
  mobile:  { width: 390,  height: 844  },
  laptop:  { width: 1024, height: 768  },
  desktop: { width: 1440, height: 900  },
  '2k':    { width: 2560, height: 1440 },
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function usage() {
  console.log(`
screenshot-grid — multi-viewport Playwright screenshot capture

Usage:
  node screenshot-grid.mjs [options]

Options:
  --base-url <url>          Base URL to screenshot (env: SCREENSHOT_BASE_URL)
                            Default: http://localhost:3000
  --routes <r1,r2,...>      Comma-separated route list (env: SCREENSHOT_ROUTES)
                            Default: /
  --out <dir>               Output directory (env: SCREENSHOT_OUT)
                            Default: ./screenshots/<timestamp>
  --viewports <v1,v2,...>   Viewport names: mobile,laptop,desktop,2k
                            (env: SCREENSHOT_VIEWPORTS)
                            Default: mobile,laptop,desktop
  --full-page <bool>        Full page capture (env: SCREENSHOT_FULL_PAGE)
                            Default: true
  --dpr <n>                 deviceScaleFactor (env: SCREENSHOT_DPR)
                            Default: 2
  --reduced-motion <bool>   Set reducedMotion:'reduce' (env: SCREENSHOT_REDUCED_MOTION)
                            Default: true
  --wait-for <condition>    Playwright wait condition (env: SCREENSHOT_WAIT_FOR)
                            load | domcontentloaded | networkidle | commit
                            Default: networkidle
  --timeout-ms <ms>         Per-page navigation timeout (env: SCREENSHOT_TIMEOUT_MS)
                            Default: 30000
  --help                    Print this message and exit

Built-in viewport sizes:
  mobile   390 × 844
  laptop  1024 × 768
  desktop 1440 × 900
  2k      2560 × 1440
`.trim());
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') {
      usage();
      process.exit(0);
    }
    if (arg.startsWith('--') && i + 1 < argv.length) {
      const key = arg.slice(2);
      args[key] = argv[++i];
    }
  }
  return args;
}

function env(name, fallback) {
  return process.env[name] !== undefined ? process.env[name] : fallback;
}

function bool(val) {
  if (typeof val === 'boolean') return val;
  return String(val).toLowerCase() !== 'false' && String(val) !== '0';
}

function routeToSlug(route) {
  // / → root, /about → about, /some/deep/path → some-deep-path
  const stripped = route.replace(/^\/+|\/+$/g, '');
  if (!stripped) return 'root';
  return stripped.replace(/\//g, '-').replace(/[^a-zA-Z0-9_-]/g, '_');
}

function timestamp() {
  const now = new Date();
  return now.toISOString()
    .replace(/T/, '-')
    .replace(/:/g, '')
    .replace(/\..+/, '');
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const cliArgs = parseArgs(process.argv.slice(2));

  const baseUrl    = cliArgs['base-url']       ?? env('SCREENSHOT_BASE_URL',       'http://localhost:3000');
  const routesRaw  = cliArgs['routes']         ?? env('SCREENSHOT_ROUTES',         '/');
  const outDir     = cliArgs['out']            ?? env('SCREENSHOT_OUT',            `./screenshots/${timestamp()}`);
  const vpRaw      = cliArgs['viewports']      ?? env('SCREENSHOT_VIEWPORTS',      'mobile,laptop,desktop');
  const fullPage   = bool(cliArgs['full-page'] ?? env('SCREENSHOT_FULL_PAGE',      'true'));
  const dpr        = Number(cliArgs['dpr']     ?? env('SCREENSHOT_DPR',            '2'));
  const redMotion  = bool(cliArgs['reduced-motion'] ?? env('SCREENSHOT_REDUCED_MOTION', 'true'));
  const waitFor    = cliArgs['wait-for']       ?? env('SCREENSHOT_WAIT_FOR',       'networkidle');
  const timeoutMs  = Number(cliArgs['timeout-ms'] ?? env('SCREENSHOT_TIMEOUT_MS',  '30000'));

  const routes   = routesRaw.split(',').map(r => r.trim()).filter(Boolean);
  const vpNames  = vpRaw.split(',').map(v => v.trim().toLowerCase()).filter(Boolean);

  // Validate viewports
  const unknownVp = vpNames.filter(v => !VIEWPORT_PRESETS[v]);
  if (unknownVp.length > 0) {
    console.error(`Unknown viewport(s): ${unknownVp.join(', ')}`);
    console.error(`Known: ${Object.keys(VIEWPORT_PRESETS).join(', ')}`);
    process.exit(1);
  }

  console.log(`screenshot-grid`);
  console.log(`  base-url:  ${baseUrl}`);
  console.log(`  routes:    ${routes.join(', ')}`);
  console.log(`  viewports: ${vpNames.join(', ')}`);
  console.log(`  out:       ${outDir}`);
  console.log(`  full-page: ${fullPage}, dpr: ${dpr}, reduced-motion: ${redMotion}`);
  console.log(`  wait-for:  ${waitFor}, timeout: ${timeoutMs}ms`);
  console.log('');

  const browser = await chromium.launch();
  let failures = 0;
  let captured = 0;

  try {
    for (const vpName of vpNames) {
      const viewport = VIEWPORT_PRESETS[vpName];
      const vpOutDir = join(outDir, vpName);
      await mkdir(vpOutDir, { recursive: true });

      const context = await browser.newContext({
        viewport,
        deviceScaleFactor: dpr,
        reducedMotion: redMotion ? 'reduce' : 'no-preference',
      });

      const page = await context.newPage();
      page.setDefaultNavigationTimeout(timeoutMs);

      for (const route of routes) {
        const url = `${baseUrl.replace(/\/$/, '')}${route}`;
        const slug = routeToSlug(route);
        const outPath = join(vpOutDir, `${slug}.png`);

        try {
          process.stdout.write(`  [${vpName}] ${url} → ${slug}.png ... `);
          await page.goto(url, { waitUntil: waitFor, timeout: timeoutMs });
          await page.screenshot({ path: outPath, fullPage });
          console.log('ok');
          captured++;
        } catch (err) {
          console.log(`FAILED`);
          console.error(`    ${err.message}`);
          failures++;
        }
      }

      await context.close();
    }
  } finally {
    await browser.close();
  }

  console.log('');
  console.log(`Done. ${captured} screenshot(s) written to ${outDir}`);

  if (failures > 0) {
    console.error(`${failures} page(s) failed.`);
    process.exit(1);
  }

  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
