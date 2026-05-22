# Olcbox — клиент

## Ссылки (стабильные)

| Назначение | URL |
|------------|-----|
| **Последний nightly** (точный тег) | https://github.com/alananisimov/olcbox/releases/tag/nightly |
| **Все релизы** (не меняется) | https://github.com/alananisimov/olcbox/releases |
| **Репозиторий** | https://github.com/alananisimov/olcbox |

Nightly собирается с [olcrtc `master`](https://github.com/openlibrecommunity/olcrtc/tree/master) (см. поле `olcrtc branch` в [релизе nightly](https://github.com/alananisimov/olcbox/releases/tag/nightly)).

Старый тег `nightly-universal-carrier` можно не использовать — universal-carrier влит в `master`.

## Подписка с VPS

```
http://ВАШ-DDNS:8888/<client_id>/
```

В `panel.env` на сервере:

```bash
OLCRTC_PUBLIC_URL=http://ВАШ-DDNS:8888
```

## Рекомендуемые настройки

- **Jitsi** + transport `datachannel` — основной стабильный режим.
- **WB Stream** — `vp8channel` (datachannel на WB часто нестабилен).
- DNS в location: `8.8.8.8:53` или `1.1.1.1:53`.
