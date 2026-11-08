// Kora admin panel. Plain JavaScript, no build step.
// Every action calls a server function that checks the user is an admin.
(function () {
  'use strict';

  // ------------------------------------------------------------------ helpers

  const $ = (sel) => document.querySelector(sel);
  const TZ = 'Africa/Cairo';

  /** Builds DOM nodes. Text is always set as text, never as HTML. */
  function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v == null || v === false) continue;
      if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
      else if (k === 'class') el.className = v;
      else el.setAttribute(k, v === true ? '' : v);
    }
    for (const c of children.flat()) {
      if (c == null || c === false) continue;
      el.append(c instanceof Node ? c : document.createTextNode(String(c)));
    }
    return el;
  }

  const fmtDate = (iso) =>
    new Intl.DateTimeFormat('en-GB', {
      timeZone: TZ, weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
    }).format(new Date(iso));

  const egp = (n) => `${n} EGP`;

  function toast(msg) {
    const t = $('#toast');
    t.textContent = msg;
    t.hidden = false;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { t.hidden = true; }, 3500);
  }

  /** Egyptian mobile number to E.164 (+2010xxxxxxxx), or null. */
  function normalizePhone(input) {
    let s = String(input).replace(/[٠-٩]/g, (d) => '٠١٢٣٤٥٦٧٨٩'.indexOf(d));
    let d = s.replace(/\D/g, '');
    if (d.startsWith('0020')) d = d.slice(4);
    if (d.startsWith('20') && d.length === 12) d = d.slice(2);
    if (d.startsWith('1') && d.length === 10) d = '0' + d;
    return /^01[0125]\d{8}$/.test(d) ? '+2' + d : null;
  }

  /** Reads coordinates from a Google Maps link or "lat, lng". */
  function parseLocation(text) {
    const s = String(text || '').trim();
    const patterns = [
      /@(-?\d+\.\d+),\s*(-?\d+\.\d+)/,            // .../@29.96,31.25,17z
      /!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/,           // ...!3d29.96!4d31.25
      /[?&](?:q|query|ll|destination)=(-?\d+\.\d+),\s*(-?\d+\.\d+)/, // ?q=29.96,31.25
      /^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/, // 29.96, 31.25
    ];
    for (const re of patterns) {
      const m = s.match(re);
      if (m) {
        const lat = Number(m[1]);
        const lng = Number(m[2]);
        if (Math.abs(lat) <= 90 && Math.abs(lng) <= 180) return { lat, lng };
      }
    }
    return null;
  }

  const ERRORS = {
    admin_only: 'Only admins can do that.',
    match_not_pending: 'This match is already confirmed or cancelled.',
    match_not_open: 'This match is no longer open.',
    dispute_not_open: 'This dispute was already decided.',
    no_refund_due: 'This refund was already marked.',
    not_signed_in: 'Your session ended. Sign in again.',
  };
  const errorText = (e) => {
    const message = String((e && e.message) || e).trim();
    if (/unsupported phone provider|phone.*(disabled|not enabled)/i.test(message)) {
      return 'Phone sign-in is not turned on yet. In Supabase: Authentication > Sign In / Providers > Phone.';
    }
    return ERRORS[message.split(/\s/)[0]] || message;
  };

  async function act(button, fn, okMessage) {
    if (button) button.disabled = true;
    try {
      await fn();
      if (okMessage) toast(okMessage);
      return true;
    } catch (e) {
      toast(errorText(e));
      return false;
    } finally {
      if (button) button.disabled = false;
    }
  }

  // ---------------------------------------------------------------- data API

  function supabaseApi(client) {
    const rpc = async (fn, args) => {
      const { data, error } = await client.rpc(fn, args || {});
      if (error) throw error;
      return data;
    };
    return {
      async userId() {
        const { data } = await client.auth.getSession();
        return data.session ? data.session.user.id : null;
      },
      onAuthChange(cb) { client.auth.onAuthStateChange((_e, session) => cb(session ? session.user.id : null)); },
      async sendOtp(phone) { const { error } = await client.auth.signInWithOtp({ phone }); if (error) throw error; },
      async verifyOtp(phone, token) {
        const { error } = await client.auth.verifyOtp({ phone, token, type: 'sms' });
        if (error) throw error;
      },
      async signOut() { await client.auth.signOut(); },
      isAdmin: () => rpc('is_admin'),
      matches: () => rpc('admin_matches'),
      confirmPitch: (id) => rpc('confirm_pitch', { p_match: id }),
      cancelMatch: (id, reason) => rpc('cancel_match', { p_match: id, p_reason: reason }),
      pitches: () => rpc('admin_pitches'),
      savePitch: (p) => rpc('admin_upsert_pitch', {
        p_id: p.id || null, p_name: p.name, p_area: p.area, p_address: p.address, p_lat: p.lat, p_lng: p.lng,
        p_price_per_hour_egp: p.price, p_photo_urls: p.photos, p_contact_phone: p.contact_phone || null,
        p_is_active: p.is_active,
      }),
      disputes: () => rpc('admin_disputes'),
      resolveDispute: (id, upheld) => rpc('admin_resolve_dispute', { p_dispute: id, p_upheld: upheld }),
      refunds: () => rpc('admin_refunds_due'),
      markRefunded: (spotId) => rpc('admin_mark_refunded', { p_spot: spotId }),
      players: (q) => rpc('admin_players', { p_query: q || null }),
      setBanned: (id, banned) => rpc('admin_set_banned', { p_player: id, p_banned: banned }),
      collusion: () => rpc('admin_collusion_report'),
    };
  }

  // -------------------------------------------------------------------- state

  let api;
  let pitchCache = [];
  let currentTab = 'matches';
  let loginPhone = null;

  function show(viewId) {
    document.querySelectorAll('main > section').forEach((s) => { s.hidden = s.id !== viewId; });
  }

  // -------------------------------------------------------------------- login

  function setupLogin() {
    $('#form-phone').addEventListener('submit', async (e) => {
      e.preventDefault();
      const phone = normalizePhone($('#phone').value);
      $('#login-error').textContent = '';
      if (!phone) { $('#login-error').textContent = 'Enter a valid Egyptian mobile number.'; return; }
      const ok = await act(e.submitter, () => api.sendOtp(phone));
      if (ok) {
        loginPhone = phone;
        $('#form-phone').hidden = true;
        $('#form-code').hidden = false;
        $('#code').focus();
      }
    });
    $('#form-code').addEventListener('submit', async (e) => {
      e.preventDefault();
      await act(e.submitter, async () => {
        await api.verifyOtp(loginPhone, $('#code').value.trim());
        await route();
      });
    });
    $('#code-back').addEventListener('click', () => {
      $('#form-code').hidden = true;
      $('#form-phone').hidden = false;
    });
    $('#sign-out').addEventListener('click', async () => { await api.signOut(); await route(); });
  }

  async function route() {
    const uid = await api.userId();
    $('#tabs').hidden = true;
    $('#sign-out').hidden = !uid;
    if (!uid) { show('view-login'); return; }
    let admin = false;
    try { admin = await api.isAdmin(); } catch (_) { admin = false; }
    if (!admin) {
      $('#make-admin-sql').textContent = `update profiles set is_admin = true where id = '${uid}';`;
      show('view-not-admin');
      return;
    }
    $('#tabs').hidden = false;
    openTab(currentTab);
    refreshCounts();
  }

  // --------------------------------------------------------------------- tabs

  const LOADERS = {
    matches: renderMatches,
    pitches: renderPitches,
    disputes: renderDisputes,
    refunds: renderRefunds,
    players: renderPlayers,
  };

  function openTab(tab) {
    currentTab = tab;
    document.querySelectorAll('#tabs button').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
    show(`view-${tab}`);
    LOADERS[tab]();
  }

  async function refreshCounts() {
    try {
      const [d, r] = await Promise.all([api.disputes(), api.refunds()]);
      $('#count-disputes').textContent = d.length || '';
      $('#count-refunds').textContent = r.length || '';
    } catch (_) { /* counts are a convenience */ }
  }

  async function load(container, fetcher, render) {
    container.replaceChildren(h('div', { class: 'empty' }, 'Loading…'));
    try {
      const rows = await fetcher();
      container.replaceChildren(render(rows));
    } catch (e) {
      container.replaceChildren(h('div', { class: 'empty error' }, errorText(e)));
    }
  }

  const table = (headers, rows) =>
    h('div', { class: 'table-wrap' },
      h('table', {},
        h('thead', {}, h('tr', {}, headers.map((x) => h('th', { class: x.cls }, x.label || x)))),
        h('tbody', {}, rows)));

  const tel = (phone) => (phone ? h('a', { href: `tel:${phone}` }, phone) : '');

  // ------------------------------------------------------------------ matches

  function matchBadge(m) {
    if (m.status === 'cancelled') return h('span', { class: 'badge bad' }, 'Cancelled');
    if (m.status === 'closed') return h('span', { class: 'badge plain' }, 'Finished');
    if (m.status === 'pending_pitch') return h('span', { class: 'badge warn' }, 'Pitch not confirmed');
    if (new Date(m.kickoff_at) < new Date()) return h('span', { class: 'badge plain' }, 'Played, awaiting results');
    return h('span', { class: 'badge ok' }, 'Open');
  }

  function renderMatches() {
    const pendingOnly = $('#matches-pending-only').checked;
    load($('#matches-list'), api.matches, (rows) => {
      const list = pendingOnly ? rows.filter((m) => m.status === 'pending_pitch') : rows;
      if (!list.length) return h('div', { class: 'empty' }, pendingOnly ? 'No match is waiting for pitch confirmation.' : 'No matches in the last 3 days or coming up.');
      return table(
        ['Kickoff (Cairo)', 'Pitch', { label: 'Host', cls: 'hide-sm' }, 'Players', { label: 'Price', cls: 'hide-sm' }, 'Status', ''],
        list.map((m) => {
          const active = m.status === 'pending_pitch' || m.status === 'open';
          return h('tr', { 'data-match': m.id },
            h('td', {}, fmtDate(m.kickoff_at), h('div', { class: 'sub' }, `${m.format} · ${m.duration_minutes} min`)),
            h('td', {}, m.pitch_name, h('div', { class: 'sub' }, m.pitch_area, m.pitch_phone ? ' · ' : '', tel(m.pitch_phone))),
            h('td', { class: 'hide-sm' }, m.host_name, h('div', { class: 'sub' }, tel(m.host_phone))),
            h('td', {}, `${m.joined}/${m.capacity}`),
            h('td', { class: 'hide-sm' }, m.cost_split === 'host_pays' ? 'Host pays' : egp(m.price_per_player_egp)),
            h('td', {}, matchBadge(m), m.cancelled_reason ? h('div', { class: 'sub' }, m.cancelled_reason.replace(/_/g, ' ')) : ''),
            h('td', { class: 'actions' },
              m.status === 'pending_pitch' && h('button', {
                class: 'primary',
                onclick: (e) => act(e.currentTarget, () => api.confirmPitch(m.id), 'Pitch confirmed. Players can now pay.').then((ok) => ok && renderMatches()),
              }, 'Confirm pitch'),
              active && h('button', {
                class: 'danger',
                onclick: (e) => {
                  const reason = prompt('Why is this match cancelled? Everyone who paid will be refunded.', 'pitch_unavailable');
                  if (reason === null) return;
                  act(e.currentTarget, () => api.cancelMatch(m.id, reason.trim() || 'admin_cancelled'), 'Match cancelled. Refunds are listed under Refunds.')
                    .then((ok) => { if (ok) { renderMatches(); refreshCounts(); } });
                },
              }, 'Cancel')));
        }));
    });
  }

  // ------------------------------------------------------------------ pitches

  function renderPitches() {
    load($('#pitches-list'), async () => (pitchCache = await api.pitches()), (rows) => {
      if (!rows.length) return h('div', { class: 'empty' }, 'No pitches yet. Add your partner pitches so players can create matches.');
      return table(
        ['Pitch', 'Area', 'Price / hour', { label: 'Contact', cls: 'hide-sm' }, 'Status', ''],
        rows.map((p) => h('tr', {},
          h('td', {}, p.name, h('div', { class: 'sub' }, p.address)),
          h('td', {}, p.area),
          h('td', {}, egp(p.price_per_hour_egp)),
          h('td', { class: 'hide-sm' }, tel(p.contact_phone)),
          h('td', {}, p.is_active ? h('span', { class: 'badge ok' }, 'Active') : h('span', { class: 'badge plain' }, 'Hidden')),
          h('td', { class: 'actions' },
            h('a', { href: `https://www.google.com/maps?q=${p.lat},${p.lng}`, target: '_blank', rel: 'noopener' }, 'Map'),
            h('button', { onclick: () => openPitchDialog(p) }, 'Edit')))));
    });
  }

  function openPitchDialog(p) {
    const f = $('#pitch-form');
    f.reset();
    $('#pitch-error').textContent = '';
    $('#location-hint').textContent = '';
    $('#pitch-dialog-title').textContent = p ? 'Edit pitch' : 'Add pitch';
    f.elements.id.value = p ? p.id : '';
    f.elements.name.value = p ? p.name : '';
    f.elements.area.value = p ? p.area : '';
    f.elements.address.value = p ? p.address : '';
    f.elements.location.value = p ? `${p.lat}, ${p.lng}` : '';
    f.elements.price.value = p ? p.price_per_hour_egp : '';
    f.elements.contact_phone.value = p && p.contact_phone ? p.contact_phone : '';
    f.elements.photos.value = p ? (p.photo_urls || []).join('\n') : '';
    f.elements.is_active.checked = p ? p.is_active : true;
    $('#pitch-dialog').showModal();
  }

  function setupPitchDialog() {
    const f = $('#pitch-form');
    $('#pitch-add').addEventListener('click', () => openPitchDialog(null));
    $('#pitch-cancel').addEventListener('click', () => $('#pitch-dialog').close());
    f.elements.location.addEventListener('input', () => {
      const loc = parseLocation(f.elements.location.value);
      $('#location-hint').textContent = loc ? `Found ${loc.lat}, ${loc.lng}` : '';
    });
    f.addEventListener('submit', async (e) => {
      e.preventDefault();
      const loc = parseLocation(f.elements.location.value);
      if (!loc) {
        $('#pitch-error').textContent =
          'Could not read a location. In Google Maps, right-click the pitch and copy the numbers (like 29.96, 31.25), or paste the full link from the address bar. Short maps.app.goo.gl links don\'t work.';
        return;
      }
      let contact = f.elements.contact_phone.value.trim();
      if (contact) {
        const n = normalizePhone(contact);
        if (!n) { $('#pitch-error').textContent = 'Contact phone is not a valid Egyptian mobile number.'; return; }
        contact = n;
      }
      const pitch = {
        id: f.elements.id.value || null,
        name: f.elements.name.value.trim(),
        area: f.elements.area.value.trim(),
        address: f.elements.address.value.trim(),
        lat: loc.lat,
        lng: loc.lng,
        price: Number(f.elements.price.value),
        contact_phone: contact,
        photos: f.elements.photos.value.split('\n').map((s) => s.trim()).filter(Boolean),
        is_active: f.elements.is_active.checked,
      };
      const ok = await act(e.submitter, () => api.savePitch(pitch), pitch.id ? 'Pitch updated.' : 'Pitch added.');
      if (ok) { $('#pitch-dialog').close(); renderPitches(); }
    });
  }

  // ----------------------------------------------------------------- disputes

  function renderDisputes() {
    load($('#disputes-list'), api.disputes, (rows) => {
      if (!rows.length) return h('div', { class: 'empty' }, 'No open disputes.');
      return h('div', { class: 'cards' }, rows.map((d) => {
        const reports = [
          d.no_show_reports ? `${d.no_show_reports} no-show report${d.no_show_reports > 1 ? 's' : ''}` : '',
          d.late_reports ? `${d.late_reports} late report${d.late_reports > 1 ? 's' : ''}` : '',
        ].filter(Boolean).join(', ');
        const decide = (upheld, msg) => (e) =>
          act(e.currentTarget, () => api.resolveDispute(d.id, upheld), msg)
            .then((ok) => { if (ok) { renderDisputes(); refreshCounts(); } });
        return h('article', { class: 'dispute', 'data-dispute': d.id },
          h('strong', {}, d.player_name), ' ', tel(d.player_phone),
          h('div', { class: 'meta' }, `${d.pitch_name} · ${fmtDate(d.kickoff_at)} · ${reports}`),
          h('blockquote', {}, d.reason),
          h('div', { class: 'actions' },
            h('button', { class: 'primary', onclick: decide(true, 'Player is right: reports cleared, counted as on time.') }, 'Player is right (clear reports)'),
            h('button', { onclick: decide(false, 'Reports stand.') }, 'Reports stand')));
      }));
    });
  }

  // ------------------------------------------------------------------ refunds

  function renderRefunds() {
    load($('#refunds-list'), api.refunds, (rows) => {
      if (!rows.length) return h('div', { class: 'empty' }, 'No refunds due.');
      const total = rows.reduce((s, r) => s + r.amount_egp, 0);
      return h('div', {},
        h('p', {}, h('strong', {}, `${rows.length} refund${rows.length > 1 ? 's' : ''}, ${egp(total)} in total`)),
        table(['Player', 'Match', 'Amount', ''],
          rows.map((r) => h('tr', {},
            h('td', {}, r.player_name || 'Guest', h('div', { class: 'sub' }, tel(r.player_phone))),
            h('td', {}, r.pitch_name, h('div', { class: 'sub' }, fmtDate(r.kickoff_at), ' · ', r.match_status.replace('_', ' '))),
            h('td', {}, egp(r.amount_egp), h('div', { class: 'sub' }, r.payment_method)),
            h('td', { class: 'actions' },
              h('button', {
                class: 'primary',
                onclick: (e) => {
                  if (!confirm(`Mark ${egp(r.amount_egp)} to ${r.player_name || 'this player'} as refunded?`)) return;
                  act(e.currentTarget, () => api.markRefunded(r.spot_id), 'Marked as refunded.')
                    .then((ok) => { if (ok) { renderRefunds(); refreshCounts(); } });
                },
              }, 'Mark refunded'))))));
    });
  }

  // ------------------------------------------------------------------ players

  function renderPlayers() {
    const q = $('#player-search').value.trim();
    load($('#players-list'), () => api.players(q), (rows) => {
      if (!rows.length) return h('div', { class: 'empty' }, q ? 'No player matches that search.' : 'No players yet.');
      return table(
        ['Player', 'Level', { label: 'Games', cls: 'hide-sm' }, 'No-shows (30 days)', 'Status', ''],
        rows.map((p) => {
          const paused = p.paused_until && new Date(p.paused_until) > new Date();
          return h('tr', { 'data-player': p.id },
            h('td', {}, p.display_name, p.is_admin ? h('span', { class: 'badge plain' }, ' admin') : '', h('div', { class: 'sub' }, tel(p.phone))),
            h('td', {}, `${p.level[0].toUpperCase()}${p.level.slice(1)}`, h('div', { class: 'sub' }, `${p.points} points`)),
            h('td', { class: 'hide-sm' }, String(p.games_played)),
            h('td', {}, String(p.no_shows_30d)),
            h('td', {},
              p.is_banned ? h('span', { class: 'badge bad' }, 'Banned')
                : paused ? h('span', { class: 'badge warn' }, `Paused until ${fmtDate(p.paused_until)}`)
                  : h('span', { class: 'badge ok' }, 'Active')),
            h('td', { class: 'actions' },
              !p.is_admin && h('button', {
                class: p.is_banned ? '' : 'danger',
                onclick: (e) => {
                  if (!p.is_banned && !confirm(`Ban ${p.display_name}? They won't be able to join or create matches.`)) return;
                  act(e.currentTarget, () => api.setBanned(p.id, !p.is_banned), p.is_banned ? 'Ban lifted.' : 'Player banned.')
                    .then((ok) => ok && renderPlayers());
                },
              }, p.is_banned ? 'Lift ban' : 'Ban')));
        }));
    });
    load($('#collusion-list'), api.collusion, (rows) => {
      if (!rows.length) return h('div', { class: 'empty' }, 'Nothing suspicious so far.');
      return table(['Players', 'Matches in a row', 'Last match'],
        rows.map((r) => h('tr', {},
          h('td', {}, `${r.name_a} & ${r.name_b}`),
          h('td', {}, String(r.streak)),
          h('td', {}, fmtDate(r.last_match_at)))));
    });
  }

  // --------------------------------------------------------------------- start

  async function start(customApi) {
    if (customApi) {
      api = customApi;
    } else {
      const cfg = window.KORA_CONFIG;
      api = supabaseApi(window.supabase.createClient(cfg.supabaseUrl, cfg.supabasePublishableKey));
    }
    setupLogin();
    setupPitchDialog();
    document.querySelectorAll('#tabs button').forEach((b) => b.addEventListener('click', () => openTab(b.dataset.tab)));
    $('#matches-pending-only').addEventListener('change', renderMatches);
    $('#form-player-search').addEventListener('submit', (e) => { e.preventDefault(); renderPlayers(); });
    api.onAuthChange(() => {});
    await route();
  }

  window.KoraAdmin = { start, parseLocation, normalizePhone };
  document.addEventListener('DOMContentLoaded', () => {
    if (window.KORA_TEST_API) start(window.KORA_TEST_API);
    else if (window.supabase && window.KORA_CONFIG) start();
  });
})();
