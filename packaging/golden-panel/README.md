# Эталон панели (тестовый VPS)

Файлы `main.tsx` и `main.go` — **рабочая** панель с тестового VPS.

При `install.sh --update` скрипт `scripts/apply-golden-panel.sh` копирует их в `/tmp/olcrtc-manager-panel` после цепочки hotfix-патчей, затем `npm run build` + `go build`.

## Обновить эталон после правок на тестовом VPS

```bash
sudo bash /opt/Olc-cost-l/scripts/olc-export-golden-panel.sh
cd /opt/Olc-cost-l && git add packaging/golden-panel && git commit -m "sync: golden panel from test VPS"
```

## Проверка

```bash
sudo bash /opt/Olc-cost-l/scripts/olc-panel-verify.sh
```

Ожидаемый JS-bundle (vite hash): `index-BgVOK4FZ.js` (может измениться после правок эталона).
