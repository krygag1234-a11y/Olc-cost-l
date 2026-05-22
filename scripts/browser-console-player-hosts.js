// Paste in DevTools Console on the episode page (after player loads / 404).
// Chrome: type allow pasting first if prompted.
(async () => {
  const hosts = new Set();
  const add = (u) => {
    try {
      if (!u || u.startsWith('data:') || u.startsWith('blob:')) return;
      const h = new URL(u, location.href).hostname.toLowerCase();
      if (h && h.includes('.') && !h.endsWith('.local')) hosts.add(h);
    } catch (_) {}
  };

  document.querySelectorAll('iframe[src], script[src], video[src], source[src], link[href]').forEach((el) => {
    add(el.src || el.href);
  });

  document.querySelectorAll('script').forEach((s) => {
    const t = s.textContent || '';
    for (const m of t.matchAll(/atob\("([A-Za-z0-9+/=]+)"\)/g)) {
      try {
        const d = atob(m[1]);
        if (d.startsWith('http')) add(d);
      } catch (_) {}
    }
    for (const m of t.matchAll(/https?:\/\/[a-z0-9][-a-z0-9.]*\.[a-z]{2,}/gi)) add(m[0]);
  });

  performance.getEntriesByType('resource').forEach((e) => add(e.name));

  document.querySelectorAll('iframe').forEach((f) => {
    try {
      const d = f.contentWindow?.location?.href;
      if (d) add(d);
    } catch (_) {
      /* cross-origin */
    }
  });

  // kinobalancer embed-domain API (lordfilm themes)
  for (const s of document.scripts) {
    const m = (s.textContent || '').match(/atob\("([A-Za-z0-9+/=]+)"\)/);
    if (m && atob(m[1]).includes('embed-domain')) {
      try {
        const j = await (await fetch(atob(m[1]))).json();
        if (j.domain) add(j.domain);
        console.log('kinobalancer embed-domain →', j);
      } catch (e) {
        console.warn('embed-domain failed', e);
      }
    }
  }

  const rules = [...hosts].sort().flatMap((h) => [`suffix:.${h}`, `exact:${h}`]);
  console.log('=== HOSTS (' + hosts.size + ') ===');
  console.log([...hosts].sort().join('\n'));
  console.log('\n=== COPY → VPS /var/lib/olcrtc/ru-domains-extra.txt ===\n' + rules.join('\n'));

  const res = performance.getEntriesByType('resource').map((e) => ({
    url: e.name,
    host: (() => { try { return new URL(e.name).hostname; } catch { return ''; } })(),
    transferSize: e.transferSize,
    duration: Math.round(e.duration),
  }));
  console.table(res.filter((r) => r.host).slice(-40));
  console.log('Network tab: filter Status=404, copy failing URL host here.');
})();
