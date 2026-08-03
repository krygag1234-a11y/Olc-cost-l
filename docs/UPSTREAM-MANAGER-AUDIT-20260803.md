# Аудит upstream manager `ad8ec6f..df62603`

Дата: 2026-08-03. База production pipeline: `ad8ec6f6f84c9869230dd06d85724c9808ebec6b`. Upstream: `df626030d21d00286304bc8ef1e990e28c247a55`. Итог нашей панели до vendoring: чистый patch-stack `Olc-cost-l` `54aab55`.

Цель аудита — не сделать нашу панель идентичной upstream, а не потерять полезные исправления перед переносом готового manager внутрь `Olc-cost-l`.

| Commit | Простыми словами | Фактическое состояние у нас | Решение перед vendoring |
|---|---|---|---|
| `82ad6c5` | Логин/пароль для исходящего SOCKS OlcRTC | Реализовано шире: instance/client/global, наследование и UI | Сохранить нашу реализацию |
| `458fff2` | Удаление Jazz из списка carrier | Jazz отсутствует в итоговом Go/UI | Закрыто |
| `e08bb7c` | Swap на VPS с малым объёмом RAM | Есть отдельный `scripts/lib-swap-auto.sh` | Сохранить нашу реализацию |
| `c679980` | Копирование в буфер при недоступном Clipboard API | Есть общий `olcSafeCopy` | Закрыто |
| `d00fa12` | Обновление Go под актуальный OlcRTC | Итоговый manager использует `go 1.26.3` | Закрыто |
| `836d9fa` | Полное удаление Jazz и запрет несовместимого `wbstream + datachannel` | Jazz удалён; `wbstream + datachannel` намеренно оставлен experimental | Сознательное расхождение; исследовать токены/права позднее |
| `e22e7f7` | Разделение Jitsi Server/Room ID и UUID | Реализовано шире: умная раскладка URL, UUID, отдельный HTTPS helper | Сохранить нашу реализацию |
| `d31efbb` | Merge Jitsi-изменений и transport matrix | Отдельной функции сверх соседних коммитов нет | Покрыто решениями `836d9fa` и `e22e7f7` |
| `2feed9f` | Пересборка готового browser bundle | Это generated JS после изменения `main.tsx` | Не переносить как функцию; bundle собирать воспроизводимо |
| `643b57a` | Слушать внешний интерфейс по умолчанию | У нас безопасный default `127.0.0.1`, внешний bind задаёт deploy-profile/env вместе с TLS/HTTP policy | Сохранить нашу управляемую реализацию, не открывать `0.0.0.0` без профиля |
| `a1879e0` | HTTPS панели | У нас расширенная реализация: trusted IP certificate, self-signed, HTTP, TUI/CLI, renewal и сохранение режима | Сохранить нашу реализацию |
| `a7bc06a` | Уточнение README про сгенерированные admin credentials | Runtime-функции нет | Сверить текст наших install docs, отдельный код не переносить |
| `a4cd467` | Jitsi UUID локально; WBStream/Telemost комнаты только вручную | UI Jitsi UUID есть, но backend `generateRoomID` всё ещё вызывает OlcRTC для любого carrier | Частично: Jitsi закрыт; WBStream/Telemost отложить и решать вместе с cookies/token flow, не копировать запрет вслепую |
| `fec1023` | Не писать дублирующий top-level `locations`; читать существующий port | Итоговый config пока пишет/читает `locations` и `clients[].locations`; собственный install/update имеет profile/TLS/port логику | Config — открытая обратимая миграция; port — проверить тестом нашей реализации |
| `fc400d2` | При reinstall показывать реально настроенный port | Собственный update/install flow должен сохранять и показывать фактический URL | Проверить clean install → installer update transition → `olc-update`; upstream-код не брать автоматически |
| `a975e82` | Заменить Jitsi default на `meet.handyweb.org` | Новая форма намеренно имеет пустой редактируемый Server и helper | Сознательно отклонить: указанный default у пользователя не работает |
| `df62603` | Показывать peer count | Наша версия богаче: `peer_devices`, `peer_at`, связь с инстансом; строгий parser повреждённой строки перенесён | Сохранить нашу реализацию |

## Блокеры перед отключением legacy manager patch-stack

1. Проверить backend room generation paths: создание/копирование/регенерация Jitsi, WBStream и Telemost. Не менять WB/Telemost до отдельного token/cookies исследования.
2. Проверить фактический port/URL во всех четырёх путях: clean install, `-full`, установщик обнаружил существующую систему и перешёл в update, отдельный `olc-update`.
3. Определить обратимую config migration. До round-trip старых подписок и backup/import legacy `locations` не удалять.
4. Сверить admin credential docs с реальным первым запуском.
5. Зафиксировать vendored baseline и сравнить его с чистым legacy patch-stack по Go tests, Vite build, API/UI markers и конфигурационной совместимости.
