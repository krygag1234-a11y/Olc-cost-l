# Windows + браузер: найти хосты плеера и применить на VPS

VPS часто получает **403** на lordfilm/bbc-doctorwho — `curl` с сервера не видит плеер.  
Делайте discovery **из браузера** (вы уже на сайте через Olcbox), затем одна команда SSH.

---

## 1. Консоль браузера (F12 → Console)

Откройте страницу с плеером, **дождитесь** появления iframe/ошибки 404, вставьте целиком:

```javascript
(async () => {
  const hosts = new Set();
  const add = (u) => {
    try {
      const h = new URL(u, location.href).hostname.toLowerCase();
      if (h && h.includes('.')) hosts.add(h);
    } catch (_) {}
  };
  document.querySelectorAll('script').forEach((s) => {
    const t = s.textContent || '';
    for (const m of t.matchAll(/atob\("([A-Za-z0-9+/=]+)"\)/g)) {
      try {
        const d = atob(m[1]);
        if (d.startsWith('http')) add(d);
      } catch (_) {}
    }
  });
  document.querySelectorAll('iframe[src], video[src], source[src]').forEach((el) => add(el.src));
  performance.getEntriesByType('resource').forEach((e) => add(e.name));

  // kinobalancer API (как на lordfilm / bbc-doctorwho themes)
  for (const s of document.scripts) {
    const m = s.textContent.match(/atob\("([A-Za-z0-9+/=]+)"\)/);
    if (m && atob(m[1]).includes('embed-domain')) {
      try {
        const r = await fetch(atob(m[1]));
        const j = await r.json();
        if (j.domain) add(j.domain);
        console.log('embed-domain API →', j);
      } catch (e) {
        console.warn('embed-domain fetch failed', e);
      }
    }
  }

  const rules = [...hosts].sort().flatMap((h) => [`suffix:.${h}`, `exact:${h}`]);
  console.log('Hosts (' + hosts.size + '):', [...hosts].sort());
  console.log('--- copy below to VPS /var/lib/olcrtc/ru-domains-extra.txt ---');
  console.log(rules.join('\n'));

  // Показать запросы с 404 nginx
  const bad = performance.getEntriesByType('resource')
    .filter((e) => e.transferSize === 0 && e.name.includes('http'));
  console.log('Recent resources (check Network tab for 404):', bad.slice(-15).map((e) => e.name));
})();
```

Скопируйте блок из консоли `suffix:...` / `exact:...` → файл на VPS (шаг 3).

**Network (вручную):** F12 → Network → фильтр `404` → колонка **Domain** — это то, что нужно добавить, если его нет в списке выше.

---

## 2. PowerShell на Windows (SSH `vpsy`)

### Вариант A — URL (если VPS не в бане)

```powershell
ssh vpsy "sudo bash /opt/Olc-cost-l/scripts/discover-page-hosts.sh 'https://www.bbc-doctorwho.ru/season-7/episode-7/' && sudo bash /opt/Olc-cost-l/scripts/fetch-ru-direct-domains.sh && sudo systemctl restart olcrtc-manager && echo DONE"
```

### Вариант B — HTML из браузера (рекомендуется при 403)

1. На странице: `Ctrl+S` → сохранить как `page.html`  
2. Загрузить и применить:

```powershell
scp C:\Users\ВАШ_ЮЗЕР\Downloads\page.html vpsy:/tmp/page.html
ssh vpsy "sudo bash /opt/Olc-cost-l/scripts/discover-page-hosts-from-html.sh /tmp/page.html && sudo bash /opt/Olc-cost-l/scripts/fetch-ru-direct-domains.sh && sudo systemctl restart olcrtc-manager && echo DONE"
```

### Вариант C — скрипт из репо

```powershell
cd C:\path\to\Olc-cost-l\scripts
.\win-apply-discover.ps1 -HtmlFile "C:\Users\you\Downloads\page.html"
# или
.\win-apply-discover.ps1 -Url "https://www.bbc-doctorwho.ru/season-7/episode-7/"
```

### Вставить правила из консоли браузера вручную

```powershell
ssh vpsy
sudo nano /var/lib/olcrtc/ru-domains-extra.txt
# вставить suffix:/exact: строки из консоли
sudo bash /opt/Olc-cost-l/scripts/fetch-ru-direct-domains.sh
sudo systemctl restart olcrtc-manager
exit
```

---

## 3. После изменений на VPS — обязательно на ПК

1. **Полностью закройте Olcbox** (не только вкладку).
2. Запустите снова и **новая сессия** к инстансу (старый туннель без новых правил).
3. В панели можно **Restart** location / инстанс.

Пинг может вырасти из‑за Tor на API (`bhcesh.me` → Cloudflare) — это нормально; главное, чтобы **embed** (`ortified`, `rewall-domain.ru`, `lumex`) шёл **direct** с RU VPS.

---

## 4. Проверка фикса DNS→CIDR на VPS

```powershell
ssh vpsy "grep -A12 'func (s \*Server) shouldDialDirect' /tmp/olcrtc-src/internal/server/server.go 2>/dev/null | head -14; grep ortified /var/lib/olcrtc/ru-direct-domains.txt | head -2"
```

Не должно быть `LookupIP` внутри `shouldDialDirect`. Должны быть строки `ortified` / `lumex`.

Пересборка при необходимости:

```powershell
ssh vpsy "cd /opt/Olc-cost-l && git pull && sudo bash scripts/apply-olcrtc-patches.sh && sudo bash scripts/setup-split-ru.sh && sudo systemctl restart olcrtc-manager"
```

---

## 5. Если 404 остаётся

В Network найдите **точный URL** с `404` и `server: nginx`. Пришлите **только host** (например `p.lumex.space`) — добавим в `data/ru-embed-balancers.txt`.

Частые случаи:
| Симптом | Причина |
|--------|---------|
| 404 на `*.ru` embed | мёртвый плеер на сайте (не туннель) |
| 404 на CDN | хост не в списке → добавить из консоли |
| Пинг растёт, страница ок | Tor на зарубежные API — ожидаемо |
