#!/usr/bin/env node
/**
 * screenshot-grid.mjs
 * Multi-viewport Playwright screenshots of a list of routes.
 */

import { chromium } from 'playwright';
import { mkdir } from 'fs/promises';
import { existsSync } from 'fs';
import path from 'path';

// ---------------------------------------------------------------------------
// Built-in viewport presets
// ---------------------------------------------------------------------------
const PRESETS = {
  mobile:  { width: 390,  height: 844  },
  laptop:  { width: 1024, height: 768  },
  desktop: { width: 1440, height: 900  },
  '2k':    { width: 2560, height: 1440 },
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function parseViewport(spec) {
  if (PRESETS[spec]) return { name: spec, ...PRESETS[spec] };
  const m = spec.match(/^(\d+)[xX](\d+)$/);
  if (m) return { name: spec, width: parseInt(m[1], 10), height: parseInt(m[2], 10) };
  throw new Error(`Unknown viewport: "${spec}". Use a preset (${Object.keys(PRESETS).join(', ')}) or WxH (e.g. 1280x800).`);
}

function routeToSlug(route) {
  const stripped = route.replace(/^\//, '').replace(/\//g, '-');
  return stripped || 'index';
}

function timestamp() {
  return new Date().toISOString().replace(/[:.]/g, '-').replace('T', '_').slice(0, 19);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--help' || a === '-h') { args.help = true; continue; }
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (!next || next.startsWith('--')) {
        args[key] = true;
      } else {
        args[key] = next;
        i++;
      }
    }
  }
  return args;
}

function printHelp() {
  console.log(`
screenshot-grid — multi-viewport Playwright screenshots

Usage:
  node screenshot-grid.mjs [flags]

Flags:
  --base-url    <url>         Base URL  (default: SCREENSHOT_BASE_URL or http://localhost:3000)
  --routes      <r1,r2,...>   Routes    (default: SCREENSHOT_ROUTES or /)
  --out         <dir>         Output    (default: SCREENSHOT_OUT or ./screenshots/<timestamp>)
  --viewports   <v1,v2,...>   Viewports (default: SCREENSHOT_VIEWPORTS or mobile,laptop,desktop)
  --full-page   true|false    Full page (default: true)
  --dpr         <n>           deviceScaleFactor (default: 2)
  --reduced-motion true|false Disable animations (default: true)
  --wait-for    <event>       Playwright waitUntil (default: networkidle)
  --timeout-ms  <ms>          Per-page timeout (default: 30000)
  --help                      Print this help

Built-in viewport presets:
  mobile   390x844
  laptop   1024x768
  desktop  1440x900
  2k       2560x1440

Custom: --viewports 800x600,1280x800

Output structure:
  <out>/<viewport>/<route-slug>.png
`.trim());
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  const cliArgs = parseArgs(process.argv.slice(2));

  if (cliArgs.help) {
    printHelp();
    process.exit(0);
  }

  // Resolve config: CLI flag > env var > default
  const baseUrl       = cliArgs['base-url']        || process.env.SCREENSHOT_BASE_URL       || 'http://localhost:3000';
  const routesRaw     = cliArgs['routes']           || process.env.SCREENSHOT_ROUTES         || '/';
  const outBase       = cliArgs['out']              || process.env.SCREENSHOT_OUT             || `./screenshots/${timestamp()}`;
  const viewportsRaw  = cliArgs['viewports']        || process.env.SCREENSHOT_VIEWPORTS       || 'mobile,laptop,desktop';
  const fullPage      = (cliArgs['full-page']       ?? process.env.SCREENSHOT_FULL_PAGE       ?? 'true') !== 'false';
  const dpr           = parseFloat(cliArgs['dpr']   || process.env.SCREENSHOT_DPR             || '2');
  const reducedMotion = (cliArgs['reduced-motion']  ?? process.env.SCREENSHOT_REDUCED_MOTION  ?? 'true') !== 'false';
  const waitFor       = cliArgs['wait-for']         || process.env.SCREENSHOT_WAIT_FOR        || 'networkidle';
  const timeoutMs     = parseInt(cliArgs['timeout-ms'] || process.env.SCREENSHOT_TIMEOUT_MS   || '30000', 10);

  const routes    = routesRaw.split(',').map(r => r.trim()).filter(Boolean);
  const viewports = viewportsRaw.split(',').map(v => parseViewport(v.trim()));

  console.log(`screenshot-grid`);
  console.log(`  base-url:   ${baseUrl}`);
  console.log(`  routes:     ${routes.join(', ')}`);
  console.log(`  viewports:  ${viewports.map(v => v.name).join(', ')}`);
  console.log(`  out:        ${path.resolve(outBase)}`);
  console.log(`  full-page:  ${fullPage}`);
  console.log(`  dpr:        ${dpr}`);
  console.log(`  reduced-motion: ${reducedMotion}`);
  console.log(`  wait-for:   ${waitFor}`);
  console.log(`  timeout-ms: ${timeoutMs}`);
  console.log('');

  const browser = await chromium.launch();
  const failures = [];
  const created = [];

  try {
    for (const vp of viewports) {
      const vpDir = path.join(outBase, vp.name);
      await mkdir(vpDir, { recursive: true });

      const context = await browser.newContext({
        viewport:         { width: vp.width, height: vp.height },
        deviceScaleFactor: dpr,
        reducedMotion:    reducedMotion ? 'reduce' : 'no-preference',
      });

      try {
        for (const route of routes) {
          const url  = `${baseUrl.replace(/\/$/, '')}${route}`;
          const slug = routeToSlug(route);
          const file = path.join(vpDir, `${slug}.png`);

          const page = await context.newPage();
          try {
            console.log(`  [${vp.name}] ${url} → ${slug}.png`);
            await page.goto(url, { waitUntil: waitFor, timeout: timeoutMs });
            await page.screenshot({ path: file, fullPage });
            created.push(file);
          } catch (err) {
            const msg = `FAIL [${vp.name}] ${url}: ${err.message}`;
            console.error(msg);
            failures.push(msg);
          } finally {
            await page.close();
          }
        }
      } finally {
        await context.close();
      }
    }
  } finally {
    await browser.close();
  }

  console.log('');
  console.log(`Done. ${created.length} screenshot(s) saved to: ${path.resolve(outBase)}`);

  if (failures.length > 0) {
    console.error(`\n${failures.length} failure(s):`);
    for (const f of failures) console.error(`  ${f}`);
    process.exit(1);
  }
}

main().catch(err => {
  console.error('Fatal:', err.message);
  process.exit(1);
});
