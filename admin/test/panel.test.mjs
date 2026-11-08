// Browser test for the admin panel against a fake backend.
// Run: node admin/test/panel.test.mjs   (needs Playwright with Chromium)
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const page_url = pathToFileURL(path.join(here, '..', 'index.html')).href;
const screenshotDir = process.env.SCREENSHOT_DIR;

// The fake backend runs inside the page. Names include HTML to check that
// nothing user-written is ever treated as markup.
const fakeApi = `
window.__calls = [];
const later = (h) => new Date(Date.now() + h * 3600e3).toISOString();
const state = {
  uid: window.__START_SIGNED_IN ? 'admin-1' : null,
  admin: true,
  matches: [
    { id: 'm1', kickoff_at: later(30), duration_minutes: 60, format: '5v5', status: 'pending_pitch', pitch_confirmed: false,
      cost_split: 'equal', price_per_player_egp: 65, total_cost_egp: 600, pitch_name: 'Pitch A', pitch_area: 'Maadi',
      pitch_phone: '+201111111111', host_id: 'h1', host_name: 'Mido', host_phone: '+201000000001', joined: 7, capacity: 10 },
    { id: 'm2', kickoff_at: later(50), duration_minutes: 90, format: '6v6', status: 'open', pitch_confirmed: true,
      cost_split: 'host_pays', price_per_player_egp: 0, total_cost_egp: 900, pitch_name: 'Pitch B', pitch_area: 'Nasr City',
      pitch_phone: null, host_id: 'h2', host_name: 'Zizo', host_phone: '+201000000002', joined: 12, capacity: 12 },
  ],
  pitches: [{ id: 'p1', name: 'Pitch A', area: 'Maadi', address: 'Road 9', lat: 29.96, lng: 31.25,
    price_per_hour_egp: 600, photo_urls: [], contact_phone: '+201111111111', is_active: true }],
  disputes: [{ id: 'd1', match_id: 'm0', kickoff_at: later(-30), pitch_name: 'Pitch A', player_id: 'x1',
    player_name: '<img src=x onerror=window.__xss=1>Hamada', player_phone: '+201000000003',
    reason: 'I was there, ask the host', late_reports: 0, no_show_reports: 2 }],
  refunds: [{ spot_id: 's1', match_id: 'm0', kickoff_at: later(-5), pitch_name: 'Pitch A', match_status: 'cancelled',
    player_id: 'x2', player_name: 'Karim', player_phone: '+201000000004', amount_egp: 65, payment_method: 'online' }],
  players: [
    { id: 'x1', display_name: 'Hamada', phone: '+201000000003', points: 40, level: 'rookie', games_played: 3, no_shows_30d: 2,
      paused_until: null, is_banned: false, is_admin: false },
    { id: 'admin-1', display_name: 'Ahmed', phone: '+201000000009', points: 0, level: 'rookie', games_played: 0, no_shows_30d: 0,
      paused_until: null, is_banned: false, is_admin: true },
  ],
};
const call = (name, ...args) => { window.__calls.push([name, ...args]); };
window.KORA_TEST_API = {
  userId: async () => state.uid,
  onAuthChange() {},
  sendOtp: async (p) => call('sendOtp', p),
  verifyOtp: async (p, c) => { call('verifyOtp', p, c); state.uid = 'admin-1'; },
  signOut: async () => { state.uid = null; },
  isAdmin: async () => state.admin,
  matches: async () => state.matches,
  confirmPitch: async (id) => { call('confirmPitch', id); const m = state.matches.find((x) => x.id === id); m.status = 'open'; m.pitch_confirmed = true; },
  cancelMatch: async (id, r) => { call('cancelMatch', id, r); state.matches.find((x) => x.id === id).status = 'cancelled'; },
  pitches: async () => state.pitches,
  savePitch: async (p) => { call('savePitch', p); state.pitches.push({ ...p, id: 'p' + (state.pitches.length + 1), price_per_hour_egp: p.price, photo_urls: p.photos }); },
  disputes: async () => state.disputes,
  resolveDispute: async (id, upheld) => { call('resolveDispute', id, upheld); state.disputes = state.disputes.filter((d) => d.id !== id); },
  refunds: async () => state.refunds,
  markRefunded: async (id) => { call('markRefunded', id); state.refunds = []; },
  players: async (q) => state.players.filter((p) => !q || p.display_name.toLowerCase().includes(q.toLowerCase())),
  setBanned: async (id, b) => { call('setBanned', id, b); state.players.find((p) => p.id === id).is_banned = b; },
  collusion: async () => [],
};
`;

async function open(browser, { signedIn }) {
  const context = await browser.newContext({ viewport: { width: 1200, height: 800 }, deviceScaleFactor: 1 });
  const page = await context.newPage();
  await page.route('https://cdn.jsdelivr.net/**', (r) => r.fulfill({ status: 200, contentType: 'text/javascript', body: '' }));
  await page.addInitScript(`window.__START_SIGNED_IN = ${signedIn};` + fakeApi);
  page.on('dialog', (d) => d.accept(d.type() === 'prompt' ? 'pitch_flooded' : undefined));
  const errors = [];
  page.on('pageerror', (e) => errors.push(e));
  await page.goto(page_url);
  return { page, context, errors };
}

const calls = (page) => page.evaluate(() => window.__calls);
let passed = 0;
const check = (cond, what) => { assert.ok(cond, what); passed++; console.log('ok -', what); };

const browser = await chromium.launch();
try {
  // Sign in with phone and code.
  {
    const { page, context, errors } = await open(browser, { signedIn: false });
    await page.waitForSelector('#view-login:not([hidden])');
    await page.fill('#phone', '0101234');
    await page.click('#form-phone button[type=submit]');
    check((await page.textContent('#login-error')).includes('valid Egyptian'), 'rejects a bad phone number');
    await page.fill('#phone', '010 1234 5678');
    await page.click('#form-phone button[type=submit]');
    await page.waitForSelector('#form-code:not([hidden])');
    await page.fill('#code', '123456');
    await page.click('#form-code button[type=submit]');
    await page.waitForSelector('#view-matches:not([hidden])');
    check(JSON.stringify(await calls(page)).includes('"+201012345678"'), 'sends the code to the normalized number');
    check(errors.length === 0, 'no page errors during sign-in');
    await context.close();
  }

  const { page, context, errors } = await open(browser, { signedIn: true });

  // Matches: confirm a pitch and cancel a match.
  await page.waitForSelector('[data-match=m1]');
  if (screenshotDir) await page.screenshot({ path: path.join(screenshotDir, 'admin-matches.png') });
  check((await page.textContent('[data-match=m1]')).includes('Pitch not confirmed'), 'shows unconfirmed pitch');
  check((await page.textContent('#count-disputes')) === '1' && (await page.textContent('#count-refunds')) === '1', 'tab counts for disputes and refunds');
  await page.click('[data-match=m1] button.primary');
  await page.waitForFunction(() => document.querySelector('[data-match=m1]')?.textContent.includes('Open'));
  check(JSON.stringify(await calls(page)).includes('["confirmPitch","m1"]'), 'confirms the pitch');
  await page.click('[data-match=m2] button.danger');
  await page.waitForFunction(() => document.querySelector('[data-match=m2]')?.textContent.includes('Cancelled'));
  check(JSON.stringify(await calls(page)).includes('["cancelMatch","m2","pitch_flooded"]'), 'cancels with a reason');

  // Pitches: add one from a Google Maps link.
  await page.click('#tabs button[data-tab=pitches]');
  await page.waitForSelector('#pitches-list table');
  await page.click('#pitch-add');
  await page.fill('#pitch-form [name=name]', 'Pitch C');
  await page.fill('#pitch-form [name=area]', 'Heliopolis');
  await page.fill('#pitch-form [name=address]', 'Merghany St');
  await page.fill('#pitch-form [name=location]', 'https://www.google.com/maps/place/X/@30.0916,31.3220,17z/data=x');
  await page.fill('#pitch-form [name=price]', '700');
  await page.fill('#pitch-form [name=contact_phone]', '01223456789');
  check((await page.textContent('#location-hint')).includes('30.0916, 31.322'), 'reads coordinates from a maps link');
  if (screenshotDir) await page.screenshot({ path: path.join(screenshotDir, 'admin-add-pitch.png') });
  await page.click('#pitch-form button[type=submit]');
  await page.waitForFunction(() => document.querySelector('#pitches-list')?.textContent.includes('Pitch C'));
  const saved = (await calls(page)).find((c) => c[0] === 'savePitch')[1];
  check(saved.lat === 30.0916 && saved.lng === 31.322 && saved.price === 700 && saved.contact_phone === '+201223456789',
    'saves the pitch with location, price and normalized phone');

  // Disputes: player names are text, never HTML.
  await page.click('#tabs button[data-tab=disputes]');
  await page.waitForSelector('[data-dispute=d1]');
  check(await page.evaluate(() => window.__xss === undefined), 'player names cannot run code in the panel');
  check((await page.textContent('[data-dispute=d1]')).includes('2 no-show reports'), 'shows the report count');
  await page.click('[data-dispute=d1] button.primary');
  await page.waitForSelector('#disputes-list .empty');
  check(JSON.stringify(await calls(page)).includes('["resolveDispute","d1",true]'), 'upholds the dispute');

  // Refunds.
  await page.click('#tabs button[data-tab=refunds]');
  await page.waitForSelector('#refunds-list table');
  check((await page.textContent('#refunds-list')).includes('65 EGP in total'), 'shows the refund total');
  await page.click('#refunds-list button.primary');
  await page.waitForSelector('#refunds-list .empty');
  check(JSON.stringify(await calls(page)).includes('["markRefunded","s1"]'), 'marks refunded');

  // Players: ban, and admins can't be banned from the panel.
  await page.click('#tabs button[data-tab=players]');
  await page.waitForSelector('[data-player=x1]');
  check((await page.$('[data-player=admin-1] button')) === null, 'no ban button for admins');
  await page.click('[data-player=x1] button.danger');
  await page.waitForFunction(() => document.querySelector('[data-player=x1]')?.textContent.includes('Banned'));
  check(JSON.stringify(await calls(page)).includes('["setBanned","x1",true]'), 'bans a player');

  // Narrow phone screen: no sideways page scroll.
  await page.setViewportSize({ width: 375, height: 700 });
  await page.click('#tabs button[data-tab=matches]');
  await page.waitForSelector('[data-match=m1]');
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  check(overflow <= 0, 'fits a phone screen without sideways scrolling');

  check(errors.length === 0, `no page errors (${errors.map(String).join('; ')})`);
  await context.close();
} finally {
  await browser.close();
}
console.log(`${passed} checks passed`);
