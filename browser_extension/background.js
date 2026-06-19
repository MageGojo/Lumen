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

async function getSettings() {
  return chrome.storage.sync.get(DEFAULT_SETTINGS);
}

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
const selfDownloadIds = new Set();
// Short-term de-dupe: one logical download (or a quick re-fire of the same URL)
// must not be handed off twice, which would pop the app window twice.
const inflightUrls = new Set();
const recentlySent = new Map(); // url -> timestamp
const DEDUP_MS = 6000;

function sweepRecent() {
  const cutoff = Date.now() - DEDUP_MS;
  for (const [u, t] of recentlySent) if (t < cutoff) recentlySent.delete(u);
}

// Storm breaker — the key guard against "open the browser and the downloader
// goes wild". A page that programmatically fires a burst of downloads (or a
// backlog of auto-started requests on launch) must NOT be relayed to the app
// one-by-one. We count recent take-overs in a sliding window; once the rate
// looks abnormal we open a "circuit" for a cooldown, during which downloads are
// left entirely to the browser (never cancelled, never sent). De-dupe only
// catches the *same* URL fired twice; this catches a flood of *different* URLs.
const STORM_WINDOW_MS = 10000;
const STORM_LIMIT = 8; // take-overs per window before it counts as a storm
const STORM_COOLDOWN_MS = 30000;
let takeoverTimes = [];
let circuitOpenUntil = 0;

function stormActive() {
  const now = Date.now();
  if (now < circuitOpenUntil) return true;
  takeoverTimes = takeoverTimes.filter((t) => now - t < STORM_WINDOW_MS);
  if (takeoverTimes.length >= STORM_LIMIT) {
    circuitOpenUntil = now + STORM_COOLDOWN_MS;
    takeoverTimes = [];
    return true;
  }
  return false;
}

function noteTakeover() {
  takeoverTimes.push(Date.now());
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

    // De-dupe: if this exact URL is already in flight or was just sent, silently
    // take over the duplicate (so the browser keeps no copy) but don't hand it
    // to the app again — avoids a second window pop for one download.
    sweepRecent();
    if (inflightUrls.has(url) || recentlySent.has(url)) {
      try { await chrome.downloads.cancel(item.id); } catch (e) {}
      try { await chrome.downloads.erase({ id: item.id }); } catch (e) {}
      return;
    }

    // Storm breaker: during a burst (page-fired downloads, or a backlog on
    // launch) stop taking over and let the browser handle them, so the app is
    // never flooded with auto-started downloads.
    if (stormActive()) return;

    // Detection gate (the safety net the README promises): only take over when
    // the app is actually reachable. If it isn't, leave the browser download
    // completely untouched — never cancel it, never spam the bridge.
    if (!(await isAppOnline())) return;

    inflightUrls.add(url);
    noteTakeover();
    try {
      try { await chrome.downloads.cancel(item.id); } catch (e) {}
      try { await chrome.downloads.erase({ id: item.id }); } catch (e) {}

      const payload = { url, referer: item.referrer || '', title: name };
      const res = await sendToApp(payload);

      if (res && res.ok) {
        recentlySent.set(url, Date.now());
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
        // App went away between the ping and the hand-off — restore the native
        // download so the file is never silently lost. Track the new id so the
        // listener above skips it instead of looping.
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
  const s = await getSettings();
  if (!s.sniff) return;
  const kind = classifyMedia(raw.url, raw.type, raw.contentType);
  if (!kind) return;
  if (!/^https?:/i.test(raw.url)) return;

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
      if (h.name.toLowerCase() === 'content-type') ct = h.value || '';
    }
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
