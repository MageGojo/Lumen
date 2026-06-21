// Lumen 下载接管 — MV3 service worker.
//
// Primary feature (IDM-style): intercept browser downloads the moment they
// start, cancel them, and hand the URL (+ Referer + filename) to the desktop
// app for multi-threaded downloading. A safety net restores the native
// download if the app is unreachable.
//
// Secondary (optional): sniff page video / media via webRequest + a content
// script, listed in the popup.

const DEFAULT_SETTINGS = {
  port: 8787,
  intercept: true, // take over browser downloads
  sniff: true, // also list sniffed page media
  minSizeMB: 0, // 0 = no minimum
  skipExt: 'm3u8,mpd', // let the browser keep these (manifests, not real files)
};

const MAX_CAPTURES = 60;
const MAX_MEDIA = 50;

let appOnline = false;
let lastPingAt = 0;
const PING_TTL_MS = 2500; // reuse a recent ping result instead of pinging per download

// Settings are read on hot paths — every intercepted download and (via the
// media sniffer) potentially every network response. Cache them in memory so we
// don't hit chrome.storage.sync per event; the cache is invalidated whenever
// settings actually change.
let settingsCache = null;
let settingsCacheAt = 0;
const SETTINGS_TTL_MS = 3000;

async function getSettings() {
  const now = Date.now();
  if (settingsCache && now - settingsCacheAt < SETTINGS_TTL_MS) {
    return settingsCache;
  }
  settingsCache = await chrome.storage.sync.get(DEFAULT_SETTINGS);
  settingsCacheAt = now;
  return settingsCache;
}

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'sync') {
    settingsCache = null;
    settingsCacheAt = 0;
  }
});

function baseName(name) {
  if (!name) return '';
  const clean = name.split('?')[0].split('#')[0];
  const parts = clean.split(/[\\/]/).filter(Boolean);
  return parts.length ? decodeURIComponent(parts[parts.length - 1]) : '';
}

function extOf(s) {
  const m = /\.([a-z0-9]{1,6})(\?|#|$)/i.exec(s || '');
  return m ? m[1].toLowerCase() : '';
}

function host(url) {
  try {
    return new URL(url).host;
  } catch (e) {
    return '';
  }
}

// ---- Desktop bridge ---------------------------------------------------------

async function getPort() {
  const { port } = await chrome.storage.sync.get({ port: DEFAULT_SETTINGS.port });
  return port || DEFAULT_SETTINGS.port;
}

async function pingApp() {
  const port = await getPort();
  try {
    const res = await fetch(`http://127.0.0.1:${port}/ping`, {
      signal: AbortSignal.timeout(1200),
    });
    const j = await res.json();
    appOnline = !!j.ok;
  } catch (e) {
    appOnline = false;
  }
  lastPingAt = Date.now();
  return appOnline;
}

// Cached online check for the hot download path: a fresh ping result is reused
// for PING_TTL_MS so a burst of downloads never pings (or stalls) per item.
async function isAppOnline() {
  if (Date.now() - lastPingAt < PING_TTL_MS) return appOnline;
  return pingApp();
}

async function sendToApp(payload) {
  const url = payload && payload.url;
  if (!url) return { ok: false, message: '无效链接' };
  const port = await getPort();
  try {
    const res = await fetch(`http://127.0.0.1:${port}/add`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        url,
        referer: payload.referer || '',
        title: payload.title || '',
      }),
      signal: AbortSignal.timeout(10000),
    });
    const j = await res.json();
    appOnline = true;
    return j;
  } catch (e) {
    appOnline = false;
    return { ok: false, message: '无法连接 Lumen(应用是否在运行?)' };
  }
}

// ---- Capture log (intercepted downloads + manual sends) ---------------------

async function getCaptures() {
  const { captures } = await chrome.storage.local.get({ captures: [] });
  return captures;
}

async function setBadge() {
  const { unseen } = await chrome.storage.local.get({ unseen: 0 });
  chrome.action.setBadgeText({ text: unseen ? String(unseen) : '' });
  chrome.action.setBadgeBackgroundColor({ color: '#2563eb' });
}

async function recordCapture(item) {
  const captures = await getCaptures();
  if (!captures.some((x) => x.url === item.url)) {
    captures.unshift(item);
    if (captures.length > MAX_CAPTURES) captures.length = MAX_CAPTURES;
    const { unseen } = await chrome.storage.local.get({ unseen: 0 });
    await chrome.storage.local.set({ captures, unseen: unseen + 1 });
    await setBadge();
  }
}

// ---- Download interception (the core IDM-style feature) ---------------------

// Downloads we re-create ourselves (the offline safety net) — never re-handle,
// so a missed attribution can't turn it into an infinite cancel→restore loop.
// In-memory is correct: an id only matters within one worker lifetime.
const selfDownloadIds = new Set();
// In-flight de-dupe within the current worker. Kept in memory on purpose: if the
// worker is killed mid hand-off the entry simply vanishes, whereas persisting it
// could wedge a URL as "in flight" forever. Cross-restart de-dupe lives in the
// persisted guard below instead.
const inflightUrls = new Set();

const DEDUP_MS = 6000;
const STORM_WINDOW_MS = 10000;
const STORM_LIMIT = 8; // take-overs per window before it counts as a storm
const STORM_COOLDOWN_MS = 30000;
// A fresh browser launch restores tabs and fires a burst of auto-downloads; hold
// the circuit open this long on startup so that opening burst is left to the
// browser (see chrome.runtime.onStartup below).
const STARTUP_GRACE_MS = 8000;

// MV3 service workers are evicted after ~30s idle and respawned per event, which
// would reset an in-memory breaker / de-dupe to zero — exactly when a storm (or
// a browser-launch burst) needs it most. So the guard (storm window + cooldown +
// recent-sent set) lives in chrome.storage.session, which survives worker
// recycling and is cleared when the browser quits. All read-modify-writes go
// through withGuard() so concurrent download events can't clobber each other.
const GUARD_KEY = 'sg_guard';
let guardChain = Promise.resolve();

function withGuard(fn) {
  const run = guardChain.then(fn);
  guardChain = run.then(() => {}, () => {});
  return run;
}

async function loadGuard() {
  try {
    const data = await chrome.storage.session.get(GUARD_KEY);
    const g = data[GUARD_KEY];
    if (g && typeof g === 'object') {
      return {
        circuitOpenUntil: g.circuitOpenUntil || 0,
        takeoverTimes: Array.isArray(g.takeoverTimes) ? g.takeoverTimes : [],
        sent: g.sent && typeof g.sent === 'object' ? g.sent : {},
      };
    }
  } catch (e) {}
  return { circuitOpenUntil: 0, takeoverTimes: [], sent: {} };
}

async function saveGuard(g) {
  try {
    await chrome.storage.session.set({ [GUARD_KEY]: g });
  } catch (e) {}
}

// Drop expired entries so the persisted guard can't grow without bound.
function sweepGuard(g, now) {
  g.takeoverTimes = g.takeoverTimes.filter((t) => now - t < STORM_WINDOW_MS);
  for (const u of Object.keys(g.sent)) {
    if (now - g.sent[u] >= DEDUP_MS) delete g.sent[u];
  }
}

// True while inside a storm cooldown / startup grace, or when the take-over rate
// just crossed the threshold (which itself opens the cooldown). De-dupe catches
// the *same* URL fired twice; this catches a flood of *different* URLs.
function stormActive(g, now) {
  if (now < g.circuitOpenUntil) return true;
  if (g.takeoverTimes.length >= STORM_LIMIT) {
    g.circuitOpenUntil = now + STORM_COOLDOWN_MS;
    g.takeoverTimes = [];
    return true;
  }
  return false;
}

// Atomically decide what to do with a candidate take-over and, when proceeding,
// reserve the slot (count the take-over + mark the URL sent) so a concurrent
// event or a worker restart can neither double-count nor double-send.
// Returns 'dup' | 'storm' | 'proceed'.
async function decideTakeover(url) {
  return withGuard(async () => {
    const now = Date.now();
    const g = await loadGuard();
    sweepGuard(g, now);

    if (inflightUrls.has(url) || g.sent[url]) {
      await saveGuard(g);
      return 'dup';
    }
    if (stormActive(g, now)) {
      await saveGuard(g);
      return 'storm';
    }
    g.takeoverTimes.push(now);
    g.sent[url] = now;
    await saveGuard(g);
    inflightUrls.add(url);
    return 'proceed';
  });
}

// Roll back a reservation when the hand-off ultimately failed, so a later retry
// of the same URL isn't silently swallowed by the de-dupe.
async function releaseTakeover(url) {
  return withGuard(async () => {
    const g = await loadGuard();
    delete g.sent[url];
    await saveGuard(g);
  });
}

chrome.downloads.onCreated.addListener(async (item) => {
  try {
    if (selfDownloadIds.has(item.id)) {
      selfDownloadIds.delete(item.id);
      return;
    }
    if (item.byExtensionId && item.byExtensionId === chrome.runtime.id) return;

    const s = await getSettings();
    if (!s.intercept) return;

    const url = item.finalUrl || item.url || '';
    if (!/^https?:\/\//i.test(url)) return; // skip blob:, data:, file:

    const name = baseName(item.filename) || baseName(url);
    const ext = extOf(name) || extOf(url);
    const skip = (s.skipExt || '')
      .split(',')
      .map((x) => x.trim().toLowerCase())
      .filter(Boolean);
    if (ext && skip.includes(ext)) return;
    if (s.minSizeMB > 0 && item.fileSize > 0 && item.fileSize < s.minSizeMB * 1024 * 1024) {
      return;
    }

    // Detection gate (the safety net the README promises): only take over when
    // the app is actually reachable. If it isn't, leave the browser download
    // completely untouched — never cancel it, never spam the bridge.
    if (!(await isAppOnline())) return;

    // Atomically consult the (persisted) de-dupe + storm guard and reserve a
    // slot. Persisted so a worker recycle mid-storm — or a cold worker on
    // browser launch — can't reset the breaker and let a burst through.
    const action = await decideTakeover(url);

    // Storm in progress (page-fired flood or launch backlog): leave it to the
    // browser entirely so the app is never flooded with auto-started downloads.
    if (action === 'storm') return;

    // Exact URL already in flight / just sent: swallow the browser's duplicate
    // copy (so it keeps none) but don't hand it off again — no second add, no
    // second window pop.
    if (action === 'dup') {
      try { await chrome.downloads.cancel(item.id); } catch (e) {}
      try { await chrome.downloads.erase({ id: item.id }); } catch (e) {}
      return;
    }

    // action === 'proceed': we hold the reservation; hand the download off.
    try {
      try { await chrome.downloads.cancel(item.id); } catch (e) {}
      try { await chrome.downloads.erase({ id: item.id }); } catch (e) {}

      const payload = { url, referer: item.referrer || '', title: name };
      const res = await sendToApp(payload);

      if (res && res.ok) {
        await recordCapture({
          url,
          kind: '下载',
          name: name || host(url),
          host: host(url),
          size: item.fileSize > 0 ? item.fileSize : 0,
          referer: item.referrer || '',
          ts: Date.now(),
        });
      } else {
        // App went away between the ping and the hand-off — release the de-dupe
        // marker and restore the native download so the file is never silently
        // lost. Track the new id so the listener above skips it instead of
        // looping.
        await releaseTakeover(url);
        try {
          const id = await chrome.downloads.download({ url });
          if (typeof id === 'number') selfDownloadIds.add(id);
        } catch (e) {}
      }
    } finally {
      inflightUrls.delete(url);
    }
  } catch (e) {
    // never let interception throw
  }
});

// ---- Optional media sniffer (secondary) -------------------------------------

const HLS_RE = /\.m3u8(\?|#|$)/i;
const DASH_RE = /\.mpd(\?|#|$)/i;
const VIDEO_RE = /\.(mp4|webm|mkv|mov|flv|avi|m4v|ogv|3gp)(\?|#|$)/i;
const AUDIO_RE = /\.(mp3|m4a|flac|wav|aac|ogg|opus)(\?|#|$)/i;
const SEGMENT_RE =
  /(\.m4s|\.ts)(\?|#|$)|[-_/](seg|segment|chunk|frag|fragment)[-_]?\d/i;

function classifyMedia(url, type, ct) {
  ct = (ct || '').toLowerCase();
  if (HLS_RE.test(url) || /mpegurl/.test(ct)) return 'HLS';
  if (DASH_RE.test(url) || /dash\+xml/.test(ct)) return 'DASH';
  if (SEGMENT_RE.test(url)) return null;
  if (VIDEO_RE.test(url) || /^video\//.test(ct) || type === 'media') return '视频';
  if (AUDIO_RE.test(url) || /^audio\//.test(ct)) return '音频';
  return null;
}

const tabMeta = new Map();

async function getMedia(tabId) {
  const key = 'm' + tabId;
  const data = await chrome.storage.session.get(key);
  return data[key] || [];
}

async function addMedia(tabId, raw) {
  // Classify first (pure + synchronous): the overwhelming majority of inputs are
  // non-media and bail here without touching storage.
  const kind = classifyMedia(raw.url, raw.type, raw.contentType);
  if (!kind) return;
  if (!/^https?:/i.test(raw.url)) return;
  const s = await getSettings();
  if (!s.sniff) return;

  const key = 'm' + tabId;
  const items = await getMedia(tabId);
  if (items.some((x) => x.url === raw.url)) return;
  const meta = tabMeta.get(tabId) || {};
  items.unshift({
    url: raw.url,
    kind,
    host: host(raw.url),
    referer: meta.url || '',
    title: raw.title || meta.title || '',
    ts: Date.now(),
  });
  if (items.length > MAX_MEDIA) items.length = MAX_MEDIA;
  await chrome.storage.session.set({ [key]: items });
}

chrome.webRequest.onHeadersReceived.addListener(
  (d) => {
    if (d.tabId < 0) return;
    let ct = '';
    for (const h of d.responseHeaders || []) {
      if (h.name.toLowerCase() === 'content-type') {
        ct = h.value || '';
        break;
      }
    }
    // Cheap synchronous gate: this fires for *every* response in *every* tab
    // (images, scripts, fonts, XHR, beacons…). Bail on non-media inline — no
    // async task, no storage read — so the sniffer can't drag the browser down.
    if (!classifyMedia(d.url, d.type, ct)) return;
    addMedia(d.tabId, { url: d.url, type: d.type, contentType: ct });
  },
  { urls: ['<all_urls>'] },
  ['responseHeaders'],
);

chrome.tabs.onUpdated.addListener((id, info, tab) => {
  if (info.status === 'loading' && info.url) {
    chrome.storage.session.remove('m' + id);
  }
  tabMeta.set(id, { title: (tab && tab.title) || '', url: (tab && tab.url) || info.url || '' });
});

chrome.tabs.onRemoved.addListener((id) => {
  chrome.storage.session.remove('m' + id);
  tabMeta.delete(id);
});

// ---- Context menu -----------------------------------------------------------

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: 'sg-link',
    title: '用 Lumen 下载此链接',
    contexts: ['link', 'video', 'audio', 'image'],
  });
  chrome.contextMenus.create({
    id: 'sg-page',
    title: '用 Lumen 解析此页面',
    contexts: ['page'],
  });
  setBadge();
});

// A fresh browser launch restores tabs, which fires a burst of auto-downloads.
// Hold the circuit open for a short grace period so that opening burst is left
// to the browser instead of flooding the app the instant it comes online — the
// "open the browser and the downloader goes wild" case. Manual context-menu
// sends bypass onCreated, so deliberate downloads still work during the grace.
chrome.runtime.onStartup.addListener(async () => {
  await withGuard(async () => {
    const g = await loadGuard();
    const until = Date.now() + STARTUP_GRACE_MS;
    if (until > g.circuitOpenUntil) g.circuitOpenUntil = until;
    await saveGuard(g);
  });
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const isLink = info.menuItemId === 'sg-link';
  const url = isLink ? info.srcUrl || info.linkUrl : info.pageUrl || (tab && tab.url);
  const res = await sendToApp({
    url,
    referer: (tab && tab.url) || info.pageUrl || '',
    title: (tab && tab.title) || '',
  });
  if (isLink && res && res.ok) {
    await recordCapture({
      url,
      kind: '下载',
      name: baseName(url) || host(url),
      host: host(url),
      size: 0,
      ts: Date.now(),
    });
  }
});

// ---- Messaging --------------------------------------------------------------

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  (async () => {
    if (msg.type === 'dom-media') {
      const tabId = sender.tab && sender.tab.id;
      if (tabId != null && tabId >= 0) {
        if (msg.title || msg.url) {
          tabMeta.set(tabId, { title: msg.title || '', url: msg.url || '' });
        }
        for (const url of msg.items || []) {
          await addMedia(tabId, { url, type: 'media', title: msg.title });
        }
      }
      sendResponse({ ok: true });
    } else if (msg.type === 'state') {
      const settings = await getSettings();
      const online = await pingApp();
      const captures = await getCaptures();
      const media = msg.tabId != null ? await getMedia(msg.tabId) : [];
      // Opening the popup marks captures as seen.
      await chrome.storage.local.set({ unseen: 0 });
      await setBadge();
      sendResponse({ settings, online, captures, media });
    } else if (msg.type === 'send') {
      const res = await sendToApp(msg.payload || { url: msg.url });
      if (res && res.ok && msg.payload && msg.payload.url) {
        await recordCapture({
          url: msg.payload.url,
          kind: msg.payload.kind || '下载',
          name: msg.payload.title || baseName(msg.payload.url) || host(msg.payload.url),
          host: host(msg.payload.url),
          size: 0,
          ts: Date.now(),
        });
      }
      sendResponse(res);
    } else if (msg.type === 'setSettings') {
      await chrome.storage.sync.set(msg.values || {});
      sendResponse({ ok: true });
    } else if (msg.type === 'clear') {
      await chrome.storage.local.set({ captures: [], unseen: 0 });
      if (msg.tabId != null) await chrome.storage.session.remove('m' + msg.tabId);
      await setBadge();
      sendResponse({ ok: true });
    } else if (msg.type === 'ping') {
      sendResponse({ ok: await pingApp() });
    }
  })();
  return true;
});
