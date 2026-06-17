// Lumen sniffer — content script.
//
// Complements the network sniffer by reading direct media URLs straight from
// the DOM (<video>/<audio>/<source>, og:video meta, and JW/HTML5 players),
// plus the page title for nicer naming. Runs in every frame so embedded
// players are covered. blob:/data: URLs are skipped (they are MSE streams the
// network sniffer resolves to a real manifest).

(function () {
  const seen = new Set();

  function isReal(src) {
    return (
      typeof src === 'string' &&
      /^https?:\/\//i.test(src) &&
      !src.startsWith('blob:') &&
      !src.startsWith('data:')
    );
  }

  function collect() {
    const found = [];

    document.querySelectorAll('video, audio').forEach((el) => {
      const src = el.currentSrc || el.getAttribute('src');
      if (isReal(src)) found.push(src);
      el.querySelectorAll('source').forEach((s) => {
        const ss = s.getAttribute('src');
        if (isReal(ss)) found.push(ss);
      });
    });

    document
      .querySelectorAll(
        'meta[property="og:video"], meta[property="og:video:url"], meta[property="og:video:secure_url"], meta[name="twitter:player:stream"]',
      )
      .forEach((m) => {
        const c = m.getAttribute('content');
        if (isReal(c)) found.push(c);
      });

    const fresh = found.filter((u) => !seen.has(u));
    fresh.forEach((u) => seen.add(u));
    if (fresh.length) {
      try {
        chrome.runtime.sendMessage({
          type: 'dom-media',
          items: fresh,
          title: document.title || '',
          url: location.href,
        });
      } catch (e) {
        // extension reloaded / context invalidated — ignore
      }
    }
  }

  // Initial sweep + react to dynamically inserted players / src changes.
  const debounced = (() => {
    let t = null;
    return () => {
      clearTimeout(t);
      t = setTimeout(collect, 600);
    };
  })();

  collect();
  window.addEventListener('loadeddata', debounced, true);
  window.addEventListener('play', debounced, true);
  document.addEventListener('DOMContentLoaded', collect);

  try {
    const mo = new MutationObserver(debounced);
    mo.observe(document.documentElement || document, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['src'],
    });
  } catch (e) {
    // no DOM yet — the listeners above will still fire
  }
})();
