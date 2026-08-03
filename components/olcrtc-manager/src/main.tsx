/* olc-panel-hotfix-v22 */
/* olc-panel-hotfix-v23 */
/* olc-panel-hotfix-v10 */
/* olc-panel-hotfix-v11 */
/* olc-panel-hotfix-v12 */
/* olc-panel-hotfix-v3 */
/* olc-panel-hotfix-v4 */
/* olc-panel-hotfix-v6 */
/* olc-panel-hotfix-v7 */
/* olc-panel-hotfix-v8 */
/* olc-panel-hotfix-v13 */
/* olc-panel-hotfix-v15 */
/* olc-panel-hotfix-v16 */
/* olc-panel-hotfix-v17 */
/* olc-panel-hotfix-v19 */
/* olc-panel-hotfix-v17-settings-layout */
/* olc-panel-ui-warp */
const COMPONENT_JOB_UI_TTL_MS = 120_000;
const JOB_MSG_TTL_MS = 45_000;

/* olc-panel-logs-verbose-v1 */
/* olc-panel-logs-live-v1 */
/* olc-jitsi-preflight-ui-v1 */
/* olc-jitsi-preflight-ui-v2 */
/* olc-jitsi-preflight-ui-v3 */
/* olc-panel-ui-v10 */
import React, { useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  Activity,
  ChevronDown,
  ChevronRight,
  Copy,
  Info,
  Edit3,
  KeyRound,
  LogOut,
  Lock,
  Plus,
  RefreshCw,
  Server,
  Settings,
  Terminal,
  Trash2,
  Users,
  X,
  Bell,
  Package,
  AlertTriangle,
  Download,
} from "lucide-react";
import "./index.css";

const OLC_PANEL_LANG_KEY = "olc-panel-lang-v1";
type PanelLang = "ru" | "en";

const PANEL_I18N: Record<PanelLang, Record<string, string>> = {
  ru: {
    settings: "Настройки",
    interface: "Интерфейс",
    language: "Язык панели",
    server: "Сервер",
    serverName: "Название",
    panelPort: "Порт панели",
    subscriptions: "Подписки",
    path: "Путь",
    refreshInterval: "Интервал обновления",
    adminPassword: "Пароль администратора",
    currentPassword: "Текущий пароль",
    newPassword: "Новый пароль",
    repeatPassword: "Повтор нового пароля",
    close: "Закрыть",
    save: "Сохранить",
    saveSettings: "Сохранить настройки",
    changePassword: "Сменить пароль",
    refresh: "Обновить",
    logout: "Выйти",
    loading: "Загрузка…",
    clients: "Клиенты",
    instances: "Инстансы",
    profile: "Профиль",
    createClient: "Создать клиента",
    create: "Создать",
    edit: "Изменить",
    delete: "Удалить",
    logs: "Логи",
    logsClient: "Логи {id}",
    loadingLogs: "Загрузка логов…",
    logsUnavailable: "Логи недоступны",
    noLogsYet: "Логов пока нет",
    networkBypass: "Сеть и обход",
    networkHint: "Вкл/выкл zapret · tor · split · webtunnel · warp. Состояние: /etc/olcrtc-manager/features.env.",
    expand: "Развернуть",
    collapse: "Свернуть",
    enable: "Включить",
    disable: "Выключить",
    notifications: "Уведомления",
    notificationSettings: "Настройки уведомлений",
    autodetect: "Автодетектор",
    autodetectSettings: "Настройки уведомлений автодетектора",
    autodetectOpen: "Настройки автодетектора →",
    noNotifications: "Нет активных предупреждений",
    markRead: "Прочитано",
    errors: "Ошибки",
    noErrors: "Критичных ошибок не найдено",
    locations: "Локации",
    addLocation: "Добавить локацию",
    login: "Вход в панель",
    setup: "Первичная настройка",
    loginLabel: "Логин",
    password: "Пароль",
    signIn: "Войти",
    savePassword: "Сохранить пароль",
    settingsTitle: "Настройки: {name}",
    instanceDefaultsBtn: "Настройки инстансов по умолчанию…",
    olcrtcCore: "OlcRTC (ядро)",
    portOverride: "Порт переопределён аргументом запуска менеджера.",
    savedServer: "Сохранено на сервере",
    updateAvailable: "Доступно обновление с GitHub",
    open: "Открыть",
    userLabel: "Пользователь",
    cancel: "Отмена",
    back: "Назад",
    saved: "Сохранено",
    updated: "Обновлено",
    copy: "Копировать",
    empty: "(пусто)",
    logsTitle: "Логи: {name}",
    logsVerbose: "Показать подробно (time/stream)",
    logsUnavailableDetail: "Логи недоступны: {error}",
    logStatus: "Статус: {status}",
    logPid: "PID: {pid}",
    logStarted: "Запуск: {at}",
    logExited: "Выход: {at}",
    logExitError: "Ошибка выхода: {err}",
    logsCopied: "Логи скопированы",
    logsLive: "Live",
    logsLiveOn: "Live: вкл",
    linkCopied: "Ссылка для {id} скопирована",
    subCopied: "Subscription для {id} скопирован",
    copyUri: "Копировать URI",
    copySub: "Копировать Sub",
    reloadPage: "Обновить страницу",
    panelErrorTitle: "Ошибка панели",
    panelErrorHint: "Панель не смогла отобразить данные (возможно, некорректная локация в config). Обновите страницу; если не помогло — удалите проблемную локацию через CLI или исправьте config.json.",
    updateFromGithub: "Обновить с GitHub",
    updateStarting: "Запуск…",
    updateStuck: "Прошлое обновление зависло — нажмите «Обновить с GitHub» ещё раз.",
    updateInProgress: "Обновление выполняется… не закрывайте вкладку до перезапуска панели.",
    checkUpdate: "Проверить",
    checkingUpdate: "Проверка…",
    updateAvailableDot: "● Доступно обновление",
    versionCurrent: "● Актуальная версия",
    updateConfirm: "Обновить Olc-cost-l с GitHub? Панель перезапустится (~2–10 мин).",
    componentsVps: "Компоненты VPS",
    componentsDrawerHint: "Установка и удаление компонентов",
    componentInstalled: "установлен",
    componentNotInstalled: "не установлен",
    componentOn: "вкл",
    componentOff: "выкл",
    componentLog: "Лог",
    jobLogTitle: "Лог задачи: {id}",
    installing: "Устанавливается…",
    uninstalling: "Удаляется…",
    installBtn: "Установить",
    uninstallBtn: "Удалить",
    jobInstallingStatus: "Устанавливается…",
    jobUninstallingStatus: "Удаляется…",
    jobDone: "Готово",
    jobFailed: "Ошибка: {error}",
    jobStatusUnknown: "Статус: {status}",
    jobStarted: "Задача {id} запущена",
    jobInstalled: "Установлено",
    jobUninstalled: "Удалено",
    jobErrorSeeLog: "Ошибка задачи — см. лог",
    confirmInstall: "Установить {name}? Может занять несколько минут.",
    confirmUninstall: "Удалить {name}? Может занять несколько минут.",
    profileLabel: "Профиль: {id}",
    subBtn: "Sub",
    restart: "Restart",
    olcBox: "OlcBox",
    qr: "QR",
    defaultLocationName: "Default",
    poolLogTitle: "Лог обновления пула",
    waitingLogLines: "Ожидание строк лога…",
    legacyTransport: "устар.",
    legacyTransportHint:
      "Транспорт videochannel снят с поддержки для новых локаций. Инстанс продолжит работать; при смене transport вернуть videochannel нельзя.",
    tableStatus: "Статус",
    locationActions: "Действия локации",
    yes: "да",
    no: "нет",
    zapretAutoSync: "Еженедельный auto-sync exclude списков",
    zapretExcludeDomains: "Домены-исключения (direct, по строке)",
    zapretForceDomains: "Домены только через zapret (по строке)",
    zapretNfqwsConfig: "Ядро nfqws (config)",
    zapretNfqwsWarn: "Внимание: это низкоуровневый конфиг zapret/nfqws. Если не уверены, лучше не менять.",
    zapretStrategyLine: "Стратегия: {strategy} · nfqws: {nfqws} · hostlist: {hostlist}",
    zapretCommunityLine: "Community lists: {state}",
    communityOn: "включены",
    communityOff: "выключены",
    zapretStrategySelect: "Выбор стратегии Zapret",
    zapretActiveStrategy: "Активная стратегия: {name}",
    zapretAfterSave: "После сохранения: olc-feature zapret reload или olc-update",
    torSocksPort: "SOCKS порт: {port}",
    torAfterSave: "После сохранения применяется configure-tor-exit (может потребоваться перезапуск инстансов).",
    torTestLine: "TestSocks: {test} · SafeSocks: {safe} · DNS: {dns}",
    torBridgesLine: "webtunnel-client: {wt} · bridges.conf подключён: {bridges}",
    splitDirectTitle: "Исключения для прямого подключения",
    splitDirectHelp: "Домены, поддомены, IP или CIDR, которые должны идти напрямую с VPS, а не через Tor. Достаточно указать vk.com — поддомены тоже будут учитываться.",
    splitCustomDirect: "Домены/IP/CIDR вручную (по строке)",
    splitPanelHosts: "Авто-хосты из инстансов и сервисов",
    splitPanelCidrs: "Авто-IP/CIDR из инстансов и DNS",
    splitGlobalSyncTitle: "Глобальный авто-список",
    splitGlobalSyncHelp: "Это не привязано к полю ниже. Кнопка пересобирает общий список по всем инстансам, сохранённым ручным правилам и runtime-логам сервера. Она не ищет только VK и не зависит от последнего введённого сайта.",
    splitAnalyzeTitle: "Точечный анализ одного сайта",
    splitAnalyzeHelp: "Это относится только к тому, что введено в поле: домен, ссылка, IP или CIDR. Панель проверит DNS, сертификаты, whois и текущие split/zapret списки, затем предложит что добавить.",
    splitAnalyzeButton: "Анализировать",
    splitAnalyzeNeedTarget: "Введите домен, ссылку, IP или CIDR",
    splitAnalyzing: "Анализирую домены и IP…",
    splitAnalyzeDone: "Анализ готов",
    splitAnalyzeResult: "Результат: {target}",
    splitFoundDomains: "Найденные домены/поддомены",
    splitFoundCidrs: "Найденные IP/CIDR",
    splitApplyAnalysis: "Добавить найденное в Split",
    splitApplyDefault: "Добавить в авто-группу Direct",
    splitApplyDestination: "Куда будет добавлено",
    splitApplySelectedDirect: "Авто-группа Split → direct: сайт, найденные CDN и IP/CIDR",
    splitApplySelectedManual: "Ручные direct-исключения: домены/IP/CIDR появятся в верхнем списке",
    splitApplySelectedTor: "Всегда через Tor: найденные домены будут принудительно отправлены в Tor",
    splitApplySelectedBlocked: "RU через VPS/Zapret: домены попадут в список заблокированных RU-сайтов",
    splitFamilyGroups: "подгрупп",
    splitApplyChoose: "Выбрать список для добавления",
    splitApplyDirect: "В прямое подключение: сайт и найденные CDN идут напрямую, не через Tor",
    splitApplyManualDirect: "В ручные direct-исключения: показать в верхнем списке и применять напрямую",
    splitApplyForceTor: "Всегда через Tor: если сайт нельзя пускать напрямую",
    splitApplyBlockedTor: "В RU через VPS/zapret: для заблокированных RU-сайтов, которые надо открывать напрямую",
    splitApplyDone: "Найденное добавлено в выбранный список",
    splitSyncConfig: "Обновить авто-список из инстансов и логов",
    splitSyncLogs: "Подтянуть CDN из логов сессии (VK и др.)",
    splitExpand: "Расширить субдомены (cert/crt.sh/CDN)",
    splitExpandRunning: "Расширение субдоменов…",
    splitExpandDone: "Субдомены и CDN добавлены в группы",
    splitSyncRunning: "Пересобираю общий авто-список…",
    splitSyncDone: "Общий авто-список пересобран",
    splitSyncLogsDone: "CDN из логов добавлены в общий список",
    splitApplyRouting: "Применить маршрутизацию",
    splitApplyRoutingDone: "Маршрутизация применена к инстансам",
    splitRestartHint: "Списки сначала пишутся на диск. «Применить маршрутизацию» — отдельно, когда VK/сайт не грузится. Не жми во время загрузки страницы.",
    splitAutoGroupsTitle: "Автоматически найдено",
    splitAutoGroupsHelp: "Глобальные группы, собранные из всех инстансов, ручных правил, анализа и разрешённых семейств из логов. Это общий список для всего olcrtc, а не только для последнего введённого домена.",
    splitProvenanceTitle: "Домены и происхождение",
    splitProvenanceHint: "Справа от домена показано, откуда автодетектор его получил.",
    splitProvTarget: "исходная цель",
    splitProvCname: "DNS CNAME",
    splitProvRuntime: "журнал сессии",
    splitProvBrand: "семейство сервиса/CDN",
    splitProvCertificate: "TLS-сертификат",
    splitProvCrtsh: "crt.sh",
    splitProvUnknown: "автодетектор",
    splitNoGroups: "Пока нет автоматических групп. Нажмите «Обновить авто-список из инстансов и логов» или выполните точечный анализ домена.",
    splitAdvancedTitle: "Расширенные правила",
    splitForceTor: "Всегда через Tor (по строке)",
    splitBlockedTor: "RU-сайты, которые открываем напрямую через VPS/zapret",
    splitCidrOnly: "Только RU CIDR без CDN /32 — меньше 404 на nginx edge",
    splitRuDirectLine: "Активных direct-доменов: {count} · CIDR файл: {file}",
    splitRefreshLists: "Обновить split/zapret списки в фоне",
    splitRefreshStarted: "Обновление split/zapret списков запущено в фоне",
    olcrtcJitsiTls: "OLCRTC_JITSI_INSECURE_TLS (самоподписанные сертификаты Jitsi)",
    olcrtcPublicUrl: "Публичный URL панели (OLCRTC_PUBLIC_URL)",
    olcrtcDefaultCarrier: "Default carrier",
    olcrtcDefaultTransport: "Default transport",
    olcrtcDefaultLink: "Default link",
    olcrtcNotSet: "(не задан)",
    olcrtcAfterSave: "После сохранения — olc-update или перезапуск инстансов.",
    olcrtcBranchPin: "Ветка: master · pin:",
    warpTorExclusive: "WARP и Tor взаимоисключают. На RU VPS обычно Tor; на foreign — профиль foreign-warp.",
    warpProxy: "WARP proxy (OLCRTC_WARP_PROXY)",
    warpAutoconnect: "Автоподключение WARP при включении компонента",
    warpPlus: "Использовать WARP+ (нужен license key)",
    warpLicense: "License key (optional)",
    warpStatusLine: "Установлен: {installed} · подключён: {connected}{profile}",
    warpSafety: "Безопасность: full-tunnel/TUN режим принудительно заблокирован в backend и install-скрипте, чтобы не сломать SSH.",
    warpInProfile: " · в профиле VPS",
    profileAddedSave: "Профиль добавлен — нажмите «Сохранить»",
    bridgePoolUpdate: "обновление пула",
    bridgePoolIdle: "ожидание",
    bridgePoolRunning: "идёт",
    bridgePoolDone: "готово",
    bridgePoolError: "ошибка",
    bridgePoolStarting: "запуск…",
    bridgeActiveProfile: "Активный профиль",
    bridgeSystemProfile: "Оригинальный (системный)",
    bridgeOriginalTitle: "Оригинальный профиль",
    bridgeOriginalHint: "Нельзя удалить. Обновляется из встроенных источников Olc-cost-l.",
    bridgeTypes: "Типы мостов",
    bridgeAutoUpdate: "Автообновление (cron)",
    bridgeRefreshNow: "Обновить сейчас",
    bridgeCustomProfiles: "Свои профили",
    bridgeAddCustom: "Добавить свой профиль",
    bridgeManual: "Вручную (bridges.conf)",
    bridgeFromUrl: "Из URL",
    bridgeAddLine: "Добавить одну строку в /etc/tor/bridges.conf",

  },
  en: {
    settings: "Settings",
    interface: "Interface",
    language: "Panel language",
    server: "Server",
    serverName: "Name",
    panelPort: "Panel port",
    subscriptions: "Subscriptions",
    path: "Path",
    refreshInterval: "Refresh interval",
    adminPassword: "Administrator password",
    currentPassword: "Current password",
    newPassword: "New password",
    repeatPassword: "Repeat new password",
    close: "Close",
    save: "Save",
    saveSettings: "Save settings",
    changePassword: "Change password",
    refresh: "Refresh",
    logout: "Log out",
    loading: "Loading…",
    clients: "Clients",
    instances: "Instances",
    profile: "Profile",
    createClient: "Create client",
    create: "Create",
    edit: "Edit",
    delete: "Delete",
    logs: "Logs",
    logsClient: "Logs {id}",
    loadingLogs: "Loading logs…",
    logsUnavailable: "Logs unavailable",
    noLogsYet: "No logs yet",
    networkBypass: "Network & bypass",
    networkHint: "Toggle zapret · tor · split · webtunnel · warp. State: /etc/olcrtc-manager/features.env.",
    expand: "Expand",
    collapse: "Collapse",
    enable: "Enable",
    disable: "Disable",
    notifications: "Notifications",
    notificationSettings: "Notification settings",
    autodetect: "Autodetector",
    autodetectSettings: "Autodetector notification settings",
    autodetectOpen: "Autodetector settings →",
    noNotifications: "No active warnings",
    markRead: "Mark read",
    errors: "Errors",
    noErrors: "No critical errors found",
    locations: "Locations",
    addLocation: "Add location",
    login: "Sign in",
    setup: "Initial setup",
    loginLabel: "Username",
    password: "Password",
    signIn: "Sign in",
    savePassword: "Save password",
    settingsTitle: "Settings: {name}",
    instanceDefaultsBtn: "Default instance settings…",
    olcrtcCore: "OlcRTC (core)",
    portOverride: "Port is overridden by manager launch argument.",
    savedServer: "Saved on server",
    updateAvailable: "Update available from GitHub",
    open: "Open",
    userLabel: "User",
    cancel: "Cancel",
    back: "Back",
    saved: "Saved",
    updated: "Refreshed",
    copy: "Copy",
    empty: "(empty)",
    logsTitle: "Logs: {name}",
    logsVerbose: "Verbose (time/stream)",
    logsUnavailableDetail: "Logs unavailable: {error}",
    logStatus: "Status: {status}",
    logPid: "PID: {pid}",
    logStarted: "Started: {at}",
    logExited: "Exited: {at}",
    logExitError: "Exit error: {err}",
    logsCopied: "Logs copied",
    logsLive: "Live",
    logsLiveOn: "Live: on",
    linkCopied: "Link for {id} copied",
    subCopied: "Subscription for {id} copied",
    copyUri: "Copy URI",
    copySub: "Copy Sub",
    reloadPage: "Reload page",
    panelErrorTitle: "Panel error",
    panelErrorHint: "The panel could not render data (possibly invalid location in config). Reload the page; if that fails, remove the bad location via CLI or fix config.json.",
    updateFromGithub: "Update from GitHub",
    updateStarting: "Starting…",
    updateStuck: "Previous update stalled — click Update from GitHub again.",
    updateInProgress: "Update in progress… do not close the tab until the panel restarts.",
    checkUpdate: "Check",
    checkingUpdate: "Checking…",
    updateAvailableDot: "● Update available",
    versionCurrent: "● Up to date",
    updateConfirm: "Update Olc-cost-l from GitHub? The panel will restart (~2–10 min).",
    componentsVps: "VPS components",
    componentsDrawerHint: "Install and remove components",
    componentInstalled: "installed",
    componentNotInstalled: "not installed",
    componentOn: "on",
    componentOff: "off",
    componentLog: "Log",
    jobLogTitle: "Job log: {id}",
    installing: "Installing…",
    uninstalling: "Removing…",
    installBtn: "Install",
    uninstallBtn: "Remove",
    jobInstallingStatus: "Installing…",
    jobUninstallingStatus: "Removing…",
    jobDone: "Done",
    jobFailed: "Error: {error}",
    jobStatusUnknown: "Status: {status}",
    jobStarted: "Job {id} started",
    jobInstalled: "Installed",
    jobUninstalled: "Removed",
    jobErrorSeeLog: "Job failed — see log",
    confirmInstall: "Install {name}? This may take several minutes.",
    confirmUninstall: "Remove {name}? This may take several minutes.",
    profileLabel: "Profile: {id}",
    subBtn: "Sub",
    restart: "Restart",
    olcBox: "OlcBox",
    qr: "QR",
    defaultLocationName: "Default",
    poolLogTitle: "Bridge pool update log",
    waitingLogLines: "Waiting for log lines…",
    legacyTransport: "legacy",
    legacyTransportHint:
      "videochannel is deprecated for new locations. Existing instances keep working; you cannot switch back to videochannel after changing transport.",
    tableStatus: "Status",
    locationActions: "Location actions",
    yes: "yes",
    no: "no",
    zapretAutoSync: "Weekly auto-sync of exclude lists",
    zapretExcludeDomains: "Exclude domains (direct, one per line)",
    zapretForceDomains: "Zapret-only domains (one per line)",
    zapretNfqwsConfig: "nfqws core (config)",
    zapretNfqwsWarn: "Warning: low-level zapret/nfqws config. Do not edit unless you know what you are doing.",
    zapretStrategyLine: "Strategy: {strategy} · nfqws: {nfqws} · hostlist: {hostlist}",
    zapretCommunityLine: "Community lists: {state}",
    communityOn: "enabled",
    communityOff: "disabled",
    zapretStrategySelect: "Zapret strategy",
    zapretActiveStrategy: "Active strategy: {name}",
    zapretAfterSave: "After save: olc-feature zapret reload or olc-update",
    torSocksPort: "SOCKS port: {port}",
    torAfterSave: "After save, configure-tor-exit runs (instance restart may be required).",
    torTestLine: "TestSocks: {test} · SafeSocks: {safe} · DNS: {dns}",
    torBridgesLine: "webtunnel-client: {wt} · bridges.conf: {bridges}",
    splitDirectTitle: "Direct connection exceptions",
    splitDirectHelp: "Domains, subdomains, IPs or CIDRs that should go directly from the VPS instead of Tor. Entering vk.com is enough — subdomains are covered too.",
    splitCustomDirect: "Manual domains/IP/CIDR (one per line)",
    splitPanelHosts: "Auto hosts from instances and services",
    splitPanelCidrs: "Auto IP/CIDR from instances and DNS",
    splitGlobalSyncTitle: "Global auto-list",
    splitGlobalSyncHelp: "This is not tied to the field below. The button rebuilds the shared list from all instances, saved manual rules and server runtime logs. It is not VK-only and does not depend on the last entered site.",
    splitAnalyzeTitle: "Targeted analysis for one site",
    splitAnalyzeHelp: "This applies only to the value entered in the field: domain, URL, IP or CIDR. The panel checks DNS, certificates, whois and current split/zapret lists, then suggests what to add.",
    splitAnalyzeButton: "Analyze",
    splitAnalyzeNeedTarget: "Enter a domain, URL, IP or CIDR",
    splitAnalyzing: "Analyzing domains and IPs…",
    splitAnalyzeDone: "Analysis complete",
    splitAnalyzeResult: "Result: {target}",
    splitFoundDomains: "Found domains/subdomains",
    splitFoundCidrs: "Found IP/CIDR",
    splitApplyAnalysis: "Add found items to Split",
    splitApplyDefault: "Add to automatic Direct group",
    splitApplyDestination: "Destination",
    splitApplySelectedDirect: "Split automatic group → direct: site, discovered CDN and IP/CIDR",
    splitApplySelectedManual: "Manual direct exceptions: domains/IP/CIDR appear in the top list",
    splitApplySelectedTor: "Always through Tor: discovered domains are forced through Tor",
    splitApplySelectedBlocked: "RU through VPS/Zapret: domains enter the blocked RU list",
    splitFamilyGroups: "subgroups",
    splitApplyChoose: "Choose destination list",
    splitApplyDirect: "Direct connection: site and discovered CDN go directly, not through Tor",
    splitApplyManualDirect: "Manual direct exceptions: show in the top list and route directly",
    splitApplyForceTor: "Always through Tor: when the site must not go directly",
    splitApplyBlockedTor: "RU via VPS/zapret: for blocked RU sites that should open directly",
    splitApplyDone: "Found items added to the selected list",
    splitSyncConfig: "Update auto-list from instances and logs",
    splitSyncLogs: "Pull CDN from session logs (VK etc.)",
    splitExpand: "Expand subdomains (cert/crt.sh/CDN)",
    splitExpandRunning: "Expanding subdomains…",
    splitExpandDone: "Subdomains and CDN added to groups",
    splitSyncRunning: "Rebuilding shared auto-list…",
    splitSyncDone: "Shared auto-list rebuilt",
    splitSyncLogsDone: "CDN from logs added to the shared list",
    splitApplyRouting: "Apply routing",
    splitApplyRoutingDone: "Routing applied to instances",
    splitRestartHint: "Lists are written to disk first. Apply routing separately when needed — not while a page is loading.",
    splitAutoGroupsTitle: "Automatically discovered",
    splitAutoGroupsHelp: "Global groups collected from all instances, manual rules, analysis and allowed service families from logs. This is shared by the whole olcrtc, not only the last entered domain.",
    splitProvenanceTitle: "Domains and provenance",
    splitProvenanceHint: "Each domain shows how the detector discovered it.",
    splitProvTarget: "source target",
    splitProvCname: "DNS CNAME",
    splitProvRuntime: "session log",
    splitProvBrand: "service/CDN family",
    splitProvCertificate: "TLS certificate",
    splitProvCrtsh: "crt.sh",
    splitProvUnknown: "auto detector",
    splitNoGroups: "No automatic groups yet. Click Update auto-list from instances and logs or run targeted domain analysis.",
    splitAdvancedTitle: "Advanced rules",
    splitForceTor: "Always through Tor (one per line)",
    splitBlockedTor: "RU sites opened directly via VPS/zapret",
    splitCidrOnly: "Only RU CIDR without CDN /32 — fewer nginx edge 404s",
    splitRuDirectLine: "Active direct domains: {count} · CIDR file: {file}",
    splitRefreshLists: "Refresh split/zapret lists in background",
    splitRefreshStarted: "Split/zapret refresh started in background",
    olcrtcJitsiTls: "OLCRTC_JITSI_INSECURE_TLS (self-signed Jitsi certs)",
    olcrtcPublicUrl: "Public panel URL (OLCRTC_PUBLIC_URL)",
    olcrtcDefaultCarrier: "Default carrier",
    olcrtcDefaultTransport: "Default transport",
    olcrtcDefaultLink: "Default link",
    olcrtcNotSet: "(not set)",
    olcrtcAfterSave: "After save — olc-update or restart instances.",
    olcrtcBranchPin: "Branch: master · pin:",
    warpTorExclusive: "WARP and Tor are mutually exclusive. RU VPS usually Tor; foreign — foreign-warp profile.",
    warpProxy: "WARP proxy (OLCRTC_WARP_PROXY)",
    warpAutoconnect: "Auto-connect WARP when component is enabled",
    warpPlus: "Use WARP+ (license key required)",
    warpLicense: "License key (optional)",
    warpStatusLine: "Installed: {installed} · connected: {connected}{profile}",
    warpSafety: "Safety: full-tunnel/TUN is blocked in backend and install scripts to avoid breaking SSH.",
    warpInProfile: " · in VPS profile",
    profileAddedSave: "Profile added — click Save",
    bridgePoolUpdate: "pool update",
    bridgePoolIdle: "idle",
    bridgePoolRunning: "running",
    bridgePoolDone: "done",
    bridgePoolError: "error",
    bridgePoolStarting: "starting…",
    bridgeActiveProfile: "Active profile",
    bridgeSystemProfile: "System (original)",
    bridgeOriginalTitle: "Original profile",
    bridgeOriginalHint: "Cannot be removed. Updated from built-in Olc-cost-l sources.",
    bridgeTypes: "Bridge types",
    bridgeAutoUpdate: "Auto-update (cron)",
    bridgeRefreshNow: "Refresh now",
    bridgeCustomProfiles: "Custom profiles",
    bridgeAddCustom: "Add custom profile",
    bridgeManual: "Manual (bridges.conf)",
    bridgeFromUrl: "From URL",
    bridgeAddLine: "Add one line to /etc/tor/bridges.conf",

  },
};

function readPanelLang(): PanelLang {
  try {
    const v = localStorage.getItem(OLC_PANEL_LANG_KEY);
    if (v === "en" || v === "ru") return v;
  } catch {
    /* ignore */
  }
  return "ru";
}

function panelT(key: string, lang: PanelLang, vars?: Record<string, string>): string {
  let s = PANEL_I18N[lang][key] ?? PANEL_I18N.ru[key] ?? key;
  if (vars) {
    for (const [k, v] of Object.entries(vars)) {
      s = s.split(`{${k}}`).join(v);
    }
  }
  return s;
}

type PanelLangContextValue = {
  lang: PanelLang;
  setLang: (lang: PanelLang) => void;
  t: (key: string, vars?: Record<string, string>) => string;
};

const PanelLangContext = React.createContext<PanelLangContextValue | null>(null);

function PanelLangProvider({ children }: { children: React.ReactNode }) {
  const [lang, setLangState] = useState<PanelLang>(() => readPanelLang());
  const setLang = useCallback((next: PanelLang) => {
    setLangState(next);
    try {
      localStorage.setItem(OLC_PANEL_LANG_KEY, next);
    } catch {
      /* ignore */
    }
    void fetch("/api/panel/lang", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ lang: next }),
    }).catch(() => {
      /* ignore */
    });
  }, []);
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      try {
        const res = await fetch("/api/panel/lang", { cache: "no-store" });
        if (!res.ok) return;
        const body = (await res.json()) as { lang?: string };
        const server = body.lang === "en" ? "en" : body.lang === "ru" ? "ru" : null;
        if (!cancelled && server) {
          setLangState(server);
          try {
            localStorage.setItem(OLC_PANEL_LANG_KEY, server);
          } catch {
            /* ignore */
          }
        }
      } catch {
        /* ignore */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);
  const t = useCallback((key: string, vars?: Record<string, string>) => panelT(key, lang, vars), [lang]);
  const value = useMemo(() => ({ lang, setLang, t }), [lang, setLang, t]);
  return <PanelLangContext.Provider value={value}>{children}</PanelLangContext.Provider>;
}

function usePanelLang(): PanelLangContextValue {
  const ctx = useContext(PanelLangContext);
  if (!ctx) {
    const lang = readPanelLang();
    return {
      lang,
      setLang: () => undefined,
      t: (key: string, vars?: Record<string, string>) => panelT(key, lang, vars),
    };
  }
  return ctx;
}


type LocationState = {
  name: string;
  room_id: string;
  key: string;
  uri: string;
  carrier: string;
  transport: string;
  payload: Record<string, string>;
  link: string;
  dns: string;
  proxy: Socks5Proxy;
  running: boolean;
  runtime: RuntimeState;
};

type RuntimeState = {
  status: string;
  running: boolean;
  pid?: number;
  memory_bytes?: number;
  started_at?: string;
  exited_at?: string;
  exit_error?: string;
  log_count: number;
};

type LogLine = {
  time: string;
  stream: string;
  line: string;
};

type ClientLogGroup = {
  location: LocationState;
  lines: LogLine[];
  error?: string;
};

type ClientState = {
  client_id: string;
  refresh?: string;
  quota: Quota;
  proxy: Socks5Proxy;
  locations: LocationState[];
  randomization?: {
    enabled: boolean;
    randomized_id?: string;
  };
};

type Quota = {
  speed_mbps?: number;
  traffic_gb?: number;
  used_gb?: number;
  used_bytes?: number;
  expires_at?: string;
};

type State = {
  name: string;
  port: number;
  subscription_path: string;
  client_count: number;
  running_count: number;
  clients: ClientState[];
};

type SettingsState = {
  name: string;
  port: number;
  subscription_path: string;
  refresh?: string;
  admin_user: string;
  port_override: boolean;
  restart_required?: boolean;
  subscription_base_url: string;
};

type Metrics = {
  go: {
    version: string;
    goroutines: number;
  };
  memory: {
    alloc_bytes: number;
    sys_bytes: number;
    heap_alloc_bytes: number;
  };
  manager: RuntimeState;
  children: Array<{
    client_id: string;
    room_id: string;
    transport: string;
    name: string;
    runtime: RuntimeState;
  }>;
};

type AuditEvent = {
  time: string;
  action: string;
  detail: string;
};

type Socks5Proxy = {
  enabled: boolean;
  addr: string;
  port: string;
  user: string;
  pass: string;
  routing: "split" | "all";
};

type ClientLocationForm = {
  name: string;
  room_id: string;
  jitsi_instance: string;
  key: string;
  carrier: string;
  transport: string;
  payload: Record<string, string>;
  dns: string;
  proxy: Socks5Proxy;
  link?: string;
};

type ClientForm = {
  client_id: string;
  refresh: string;
  quota: Quota;
  proxy: Socks5Proxy;
  locations: ClientLocationForm[];
};

type SettingsForm = {
  name: string;
  port: string;
  subscription_path: string;
  refresh: string;
};

const DEFAULT_JITSI_INSTANCE = "https://meet.handyweb.org";

const carriers = ["jitsi", "wbstream", "telemost"];
const transportsByCarrier: Record<string, string[]> = {
  jitsi: ["datachannel", "vp8channel", "seichannel"],
  // Keep datachannel visible: OlcRTC still implements it, but ordinary WB guest tokens
  // currently carry canPublishData=false, so the mode is experimental.
  wbstream: ["datachannel", "vp8channel", "seichannel"],
  telemost: ["vp8channel", "seichannel"],
};

/** Снят с поддержки для новых локаций; старые config не ломаем. */
const LEGACY_TRANSPORTS = new Set(["videochannel"]);

const emptyProxy = (): Socks5Proxy => ({
  enabled: false,
  addr: "",
  port: "",
  user: "",
  pass: "",
  routing: "split",
});

const defaultLocationForm: ClientLocationForm = {
  name: "",
  room_id: "",
  jitsi_instance: "",
  key: "",
  carrier: "jitsi",
  transport: "datachannel",
  payload: {},
  dns: "1.1.1.1:53",
  proxy: emptyProxy(),
  link: "tor",
};

const defaultForm: ClientForm = {
  client_id: "",
  refresh: "",
  quota: {},
  proxy: emptyProxy(),
  locations: [{ ...defaultLocationForm, proxy: emptyProxy() }],
};

const defaultSettingsForm: SettingsForm = {
  name: "",
  port: "",
  subscription_path: "sub",
  refresh: "",
};

const payloadFields: Record<string, Array<{ key: string; label: string; defaultValue: string }>> = {
  datachannel: [],
  vp8channel: [
    { key: "vp8-fps", label: "FPS", defaultValue: "50" },
    { key: "vp8-batch", label: "Batch", defaultValue: "50" },
  ],
  seichannel: [
    { key: "fps", label: "FPS", defaultValue: "50" },
    { key: "batch", label: "Batch", defaultValue: "50" },
    { key: "frag", label: "Fragment bytes", defaultValue: "900" },
    { key: "ack-ms", label: "ACK timeout ms", defaultValue: "2000" },
  ],
  videochannel: [
    { key: "video-w", label: "Width", defaultValue: "640" },
    { key: "video-h", label: "Height", defaultValue: "480" },
    { key: "video-fps", label: "FPS", defaultValue: "30" },
    { key: "video-bitrate", label: "Bitrate", defaultValue: "" },
    { key: "video-hw", label: "HW encode", defaultValue: "" },
    { key: "video-codec", label: "Codec", defaultValue: "" },
    { key: "video-qr-size", label: "QR size", defaultValue: "" },
    { key: "video-qr-recovery", label: "QR recovery", defaultValue: "" },
    { key: "video-tile-module", label: "Tile module", defaultValue: "" },
    { key: "video-tile-rs", label: "Tile RS", defaultValue: "" },
  ],
};

/* --- Дефолты инстансов (localStorage, v1) --- */
const INSTANCE_DEFAULTS_LS = "olc-instance-defaults-v1";

type TransportDefCfg = {
  port: string;
  payload: Record<string, string>;
  maxValues: boolean;
};

type CarrierDefCfg = {
  port: string;
  transports: Record<string, TransportDefCfg>;
};

type InstanceDefaultsV1 = {
  globalPort: string;
  carriers: Record<string, CarrierDefCfg>;
};

function defaultTransportCfg(transport: string): TransportDefCfg {
  const fields = payloadFields[transport] ?? [];
  const payload: Record<string, string> = {};
  for (const f of fields) payload[f.key] = f.defaultValue;
  return { port: "", payload, maxValues: false };
}

function emptyInstanceDefaults(): InstanceDefaultsV1 {
  const out: Record<string, CarrierDefCfg> = {};
  for (const c of carriers) {
    const transports: Record<string, TransportDefCfg> = {};
    for (const t of transportOptions(c)) transports[t] = defaultTransportCfg(t);
    out[c] = { port: "", transports };
  }
  return { globalPort: "", carriers: out };
}

let instanceDefaultsCache: InstanceDefaultsV1 | null = null;

function parseInstanceDefaults(raw: Partial<InstanceDefaultsV1> | null | undefined): InstanceDefaultsV1 {
  const base = emptyInstanceDefaults();
  if (!raw) return base;
  return {
    globalPort: String(raw.globalPort ?? ""),
    carriers: { ...base.carriers, ...(raw.carriers ?? {}) },
  };
}

function loadInstanceDefaultsFromLS(): InstanceDefaultsV1 {
  try {
    const raw = localStorage.getItem(INSTANCE_DEFAULTS_LS);
    if (!raw) return emptyInstanceDefaults();
    return parseInstanceDefaults(JSON.parse(raw) as InstanceDefaultsV1);
  } catch {
    return emptyInstanceDefaults();
  }
}

function loadInstanceDefaults(): InstanceDefaultsV1 {
  return instanceDefaultsCache ?? loadInstanceDefaultsFromLS();
}

function setInstanceDefaultsCache(cfg: InstanceDefaultsV1) {
  instanceDefaultsCache = cfg;
  try {
    localStorage.setItem(INSTANCE_DEFAULTS_LS, JSON.stringify(cfg));
  } catch {
    /* ignore */
  }
}

async function fetchInstanceDefaultsFromAPI(): Promise<InstanceDefaultsV1> {
  try {
    const res = await fetch("/api/instance-defaults", { cache: "no-store" });
    if (!res.ok) return loadInstanceDefaultsFromLS();
    const body = (await res.json()) as { defaults?: Partial<InstanceDefaultsV1> };
    const cfg = parseInstanceDefaults(body.defaults);
    setInstanceDefaultsCache(cfg);
    return cfg;
  } catch {
    return loadInstanceDefaultsFromLS();
  }
}

async function saveInstanceDefaults(cfg: InstanceDefaultsV1): Promise<void> {
  setInstanceDefaultsCache(cfg);
  const res = await fetch("/api/instance-defaults", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ defaults: cfg }),
  });
  if (!res.ok) {
    const raw = await res.text();
    throw new Error(raw || `HTTP ${res.status}`);
  }
}

function mergeInstanceDefaults(loc: ClientLocationForm): ClientLocationForm {
  const cfg = loadInstanceDefaults();
  const carrier = loc.carrier || "jitsi";
  const transport = loc.transport || transportOptions(carrier, loc.transport)[0];
  const cCfg = cfg.carriers[carrier];
  if (!cCfg) return loc;
  const tCfg = cCfg.transports[transport];
  if (!tCfg) return loc;
  const port = cfg.globalPort.trim() || tCfg.port.trim() || cCfg.port.trim();
  const payload = { ...loc.payload };
  for (const field of payloadFields[transport] ?? []) {
    const def = tCfg.payload[field.key] ?? field.defaultValue;
    if (!payload[field.key]?.trim()) payload[field.key] = def;
  }
  const dns = loc.dns?.trim() && loc.dns !== "1.1.1.1:53" ? loc.dns : port || loc.dns || "1.1.1.1:53";
  return { ...loc, carrier, transport, payload, dns };
}

function clampPayloadIfMax(
  carrier: string,
  transport: string,
  key: string,
  value: string,
): string {
  const cfg = loadInstanceDefaults();
  const tCfg = cfg.carriers[carrier]?.transports[transport];
  if (!tCfg?.maxValues) return value;
  const cap = tCfg.payload[key];
  if (cap === undefined || cap === "") return value;
  const n = Number(value);
  const m = Number(cap);
  if (!Number.isNaN(n) && !Number.isNaN(m) && n > m) return cap;
  return value;
}

/* OLC_TOGGLE_BUTTONS_UI_V4 */
/* OLC_TOGGLE_TARGETED_LAYOUT_V1 */
type OlcToggleButtonProps = {
  checked?: boolean;
  disabled?: boolean;
  mixed?: boolean;
  compact?: boolean;
  title?: string;
  tone?: "default" | "danger";
  className?: string;
  onClick?: (event: React.MouseEvent<HTMLButtonElement>) => void;
  onChange?: (event: { target: { checked: boolean }; currentTarget: { checked: boolean } }) => void;
};

function OlcToggleButton({ checked = false, disabled = false, mixed = false, compact = false, title, tone = "default", className = "", onClick, onChange }: OlcToggleButtonProps) {
  const stateLabel = mixed ? "Часть" : checked ? "Вкл" : "Выкл";
  const stateClass = mixed
    ? "border-amber-500/40 bg-amber-500/10 text-amber-600 hover:bg-amber-500/20"
    : checked
      ? tone === "danger"
        ? "border-red-500/40 bg-red-500/10 text-red-400 hover:bg-red-500/20"
        : "border-green-500/40 bg-green-500/10 text-green-600 hover:bg-green-500/20"
      : "border-border bg-transparent text-foreground hover:bg-muted";
  const sizeClass = compact ? "h-6 min-w-[44px] px-1.5 text-[10px]" : "h-8 min-w-[72px] px-3 text-xs";
  return (
    <button
      type="button"
      role="switch"
      aria-checked={mixed ? "mixed" : checked}
      aria-label={title || stateLabel}
      title={title}
      disabled={disabled}
      className={`inline-flex shrink-0 items-center justify-center rounded-md border font-semibold transition-colors ${sizeClass} ${stateClass} ${disabled ? "cursor-not-allowed opacity-50" : "cursor-pointer"} ${className}`}
      onClick={(event) => {
        event.stopPropagation();
        onClick?.(event);
        if (event.defaultPrevented || disabled) return;
        const next = !checked;
        onChange?.({ target: { checked: next }, currentTarget: { checked: next } });
      }}
    >
      {stateLabel}
    </button>
  );
}

function InstanceDefaultsModal({ onBack, onClose }: { onBack: () => void; onClose: () => void }) {
  const { t } = usePanelLang();
  const [cfg, setCfg] = useState<InstanceDefaultsV1>(() => loadInstanceDefaults());
  const [saved, setSaved] = useState("");
  const [loading, setLoading] = useState(true);
  const cfgRef = useRef(cfg);
  const savedSnapshotRef = useRef("");
  const autoSaveTimerRef = useRef<number | null>(null);
  const saveQueueRef = useRef<Promise<void>>(Promise.resolve());

  const persistInstanceDefaults = useCallback((next: InstanceDefaultsV1) => {
    const snapshot = JSON.stringify(next);
    if (snapshot === savedSnapshotRef.current) return saveQueueRef.current;
    setSaved("Сохраняю…");
    const run = async () => {
      try {
        await saveInstanceDefaults(next);
        savedSnapshotRef.current = snapshot;
        setSaved("Сохранено автоматически");
      } catch (error) {
        setSaved(`Ошибка автосохранения: ${error instanceof Error ? error.message : String(error)}`);
      }
    };
    saveQueueRef.current = saveQueueRef.current.then(run, run);
    return saveQueueRef.current;
  }, []);

  const flushInstanceDefaults = useCallback(() => {
    if (autoSaveTimerRef.current !== null) {
      window.clearTimeout(autoSaveTimerRef.current);
      autoSaveTimerRef.current = null;
    }
    if (!loading) void persistInstanceDefaults(cfgRef.current);
  }, [loading, persistInstanceDefaults]);

  const closeInstanceDefaults = () => {
    flushInstanceDefaults();
    onClose();
  };
  const backFromInstanceDefaults = () => {
    flushInstanceDefaults();
    onBack();
  };

  useEffect(() => {
    let cancelled = false;
    void fetchInstanceDefaultsFromAPI().then((next) => {
      if (!cancelled) {
        cfgRef.current = next;
        savedSnapshotRef.current = JSON.stringify(next);
        setCfg(next);
        setLoading(false);
      }
    });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    cfgRef.current = cfg;
    if (loading || JSON.stringify(cfg) === savedSnapshotRef.current) return;
    if (autoSaveTimerRef.current !== null) window.clearTimeout(autoSaveTimerRef.current);
    setSaved("Ожидает автосохранения…");
    autoSaveTimerRef.current = window.setTimeout(() => {
      autoSaveTimerRef.current = null;
      void persistInstanceDefaults(cfgRef.current);
    }, 650);
    return () => {
      if (autoSaveTimerRef.current !== null) window.clearTimeout(autoSaveTimerRef.current);
    };
  }, [cfg, loading, persistInstanceDefaults]);

  const setGlobalPort = (v: string) => setCfg((c) => ({ ...c, globalPort: v }));
  const globalActive = cfg.globalPort.trim() !== "";

  const updateCarrierPort = (carrier: string, port: string) =>
    setCfg((c) => ({
      ...c,
      carriers: { ...c.carriers, [carrier]: { ...c.carriers[carrier], port } },
    }));

  const updateTransport = (
    carrier: string,
    transport: string,
    patch: Partial<TransportDefCfg>,
  ) =>
    setCfg((c) => ({
      ...c,
      carriers: {
        ...c.carriers,
        [carrier]: {
          ...c.carriers[carrier],
          transports: {
            ...c.carriers[carrier].transports,
            [transport]: { ...c.carriers[carrier].transports[transport], ...patch },
          },
        },
      },
    }));

  const renderTransportBlock = (carrier: string, transport: string) => {
    const tCfg = cfg.carriers[carrier]?.transports[transport] ?? defaultTransportCfg(transport);
    const fields = payloadFields[transport] ?? [];
    return (
      <div key={transport} className="rounded border border-border bg-background p-3">
        <div className="mb-2 text-xs font-medium uppercase text-muted-foreground">{transport}</div>
        {!globalActive && (
          <label className="mb-2 grid gap-1 text-xs text-muted-foreground">
            Порт по умолчанию (DNS host:port)
            <input
              className="h-8 rounded border border-border bg-card px-2 font-mono text-xs"
              value={tCfg.port}
              onChange={(e) => updateTransport(carrier, transport, { port: e.target.value })}
              placeholder="1.1.1.1:53"
            />
          </label>
        )}
        {fields.length > 0 && (
          <div className="grid gap-2 md:grid-cols-2">
            {fields.map((field) => (
              <label key={field.key} className="grid gap-1 text-xs text-muted-foreground">
                {field.label}
                <input
                  className="h-8 rounded border border-border bg-card px-2 text-xs"
                  value={tCfg.payload[field.key] ?? ""}
                  onChange={(e) =>
                    updateTransport(carrier, transport, {
                      payload: { ...tCfg.payload, [field.key]: e.target.value },
                    })
                  }
                />
              </label>
            ))}
          </div>
        )}
        <div className="mt-2 flex items-center justify-between gap-3 text-xs">
          <span>Это максимальные значения? (нельзя выставить выше при создании)</span>
          <OlcToggleButton

            checked={tCfg.maxValues}
            onChange={(e) => updateTransport(carrier, transport, { maxValues: e.target.checked })}
          />
        </div>
      </div>
    );
  };

  return (
    <Modal title="Настройки инстансов по умолчанию" onClose={closeInstanceDefaults}>
      <div className="space-y-4 p-4 text-sm">
        <button type="button" className="text-xs text-primary hover:underline" onClick={backFromInstanceDefaults}>
          ← Назад к настройкам OlcRTC
        </button>
        {loading ? (
          <LoadingState label={t("loading")} />
        ) : (
        <>
        <label className="grid gap-1 text-muted-foreground">
          Общий порт для всех провайдеров (если заполнен — индивидуальные порты ниже отключены)
          <input
            className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs"
            value={cfg.globalPort}
            onChange={(e) => setGlobalPort(e.target.value)}
            placeholder="пусто = порты по провайдерам"
          />
        </label>
        {(["jitsi", "wbstream", "telemost"] as const).map((carrier) => (
          <section key={carrier} className="grid gap-2 rounded-md border border-border p-3">
            <div className="font-medium capitalize">{carrier}</div>
            {!globalActive && carrier !== "jitsi" && (
              <label className="grid gap-1 text-xs text-muted-foreground">
                Порт по умолчанию ({carrier})
                <input
                  className="h-8 rounded border border-border bg-card px-2 font-mono text-xs disabled:opacity-50"
                  disabled={globalActive}
                  value={cfg.carriers[carrier]?.port ?? ""}
                  onChange={(e) => updateCarrierPort(carrier, e.target.value)}
                />
              </label>
            )}
            {carrier === "jitsi" && !globalActive && (
              <label className="grid gap-1 text-xs text-muted-foreground">
                Порт (datachannel)
                <input
                  className="h-8 rounded border border-border bg-card px-2 font-mono text-xs"
                  value={cfg.carriers.jitsi?.transports.datachannel?.port ?? ""}
                  onChange={(e) => updateTransport("jitsi", "datachannel", { port: e.target.value })}
                />
              </label>
            )}
            <div className="grid gap-2">
              {transportOptions(carrier).map((t) => renderTransportBlock(carrier, t))}
            </div>
          </section>
        ))}
        <p className={`text-xs ${saved.startsWith("Ошибка") ? "text-destructive" : "text-muted-foreground"}`}>
          {saved || "Изменения сохраняются автоматически"}
        </p>
        </>
        )}
      </div>
    </Modal>
  );
}

async function request(path: string, options?: RequestInit) {
  const res = await fetch(path, options);
  if (!res.ok) {
    if (res.status === 401) window.dispatchEvent(new Event("olcrtc-auth-required"));
    if (res.status === 429) {
      const retry = Number.parseInt(res.headers.get("Retry-After") || "60", 10);
      throw new Error(`Слишком много неудачных попыток входа. Повторите через ${Number.isFinite(retry) ? retry : 60} секунд.`);
    }
    throw new Error((await res.text()).trim() || res.statusText);
  }
  return res;
}


function splitJitsiRoomInput(value: string): { server: string; room: string } | null {
  const raw = value.trim().replace(/\/+$/, "");
  if (!raw || !raw.includes("/")) return null;
  const hasScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(raw);
  const protocolRelative = raw.startsWith("//");
  const candidate = hasScheme ? raw : protocolRelative ? `https:${raw}` : `https://${raw}`;
  try {
    const parsed = new URL(candidate);
    const parts = parsed.pathname.split("/").filter(Boolean);
    if (!parsed.host || parts.length === 0) return null;
    const room = decodeURIComponent(parts.pop() || "").trim();
    if (!room) return null;
    const suffix = parts.length ? `/${parts.join("/")}` : "";
    const server = hasScheme
      ? `${parsed.protocol}//${parsed.host}${suffix}`
      : protocolRelative
        ? `//${parsed.host}${suffix}`
        : `${parsed.host}${suffix}`;
    return { server, room };
  } catch {
    return null;
  }
}

function normalizeJitsiServer(value: string): string {
  const server = value.trim().replace(/\/+$/, "");
  if (!server) return "";
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(server)) return server;
  if (server.startsWith("//")) return `https:${server}`;
  return `https://${server}`;
}

function combineJitsiRoomId(server: string, room: string): string {
  const base = normalizeJitsiServer(server);
  const cleanRoom = room.trim().replace(/^\/+/, "");
  return cleanRoom ? `${base}/${cleanRoom}` : base;
}

function jitsiRoomForSubmit(location: Pick<ClientLocationForm, "jitsi_instance" | "room_id">): string {
  return combineJitsiRoomId(location.jitsi_instance, location.room_id);
}

function randomRoomUUID(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = new Uint8Array(16);
  if (typeof crypto !== "undefined" && typeof crypto.getRandomValues === "function") crypto.getRandomValues(bytes);
  else for (let i = 0; i < bytes.length; i += 1) bytes[i] = Math.floor(Math.random() * 256);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function proxyFromState(proxy?: Partial<Socks5Proxy> & { port?: string | number }): Socks5Proxy {
  return {
    enabled: typeof proxy?.enabled === "boolean" ? proxy.enabled : Boolean(proxy?.addr),
    addr: proxy?.addr ?? "",
    port: proxy?.port ? String(proxy.port) : "",
    user: proxy?.user ?? "",
    pass: proxy?.pass ?? "",
    routing: proxy?.routing === "all" ? "all" : "split",
  };
}

function proxyIsEnabled(proxy?: Partial<Socks5Proxy>) {
  return typeof proxy?.enabled === "boolean" ? proxy.enabled : Boolean(proxy?.addr);
}

function proxyForSubmit(proxy: Socks5Proxy) {
  return {
    enabled: Boolean(proxy.enabled),
    addr: proxy.addr.trim(),
    port: Number(proxy.port) || 0,
    user: proxy.user.trim(),
    pass: proxy.pass,
    routing: proxy.routing === "all" ? "all" : "split",
  };
}

function transportOptions(carrier: string, keepTransport?: string) {
  const base = [...(transportsByCarrier[carrier] ?? transportsByCarrier.wbstream)];
  if (keepTransport && LEGACY_TRANSPORTS.has(keepTransport) && !base.includes(keepTransport)) {
    base.push(keepTransport);
  }
  return base;
}

function isLegacyTransport(transport: string) {
  return LEGACY_TRANSPORTS.has(transport);
}


function normalizeRoomIDInput(value: string): string {
  const roomID = value.trim();
  if (!roomID) return roomID;
  if (roomID.startsWith("http://") || roomID.startsWith("https://")) return roomID;
  if (roomID.startsWith("//")) return `https:${roomID}`;
  if (roomID.includes(".") && !roomID.includes(" ")) return `https://${roomID}`;
  return roomID;
}

/** Returns Russian error message or null if OK. */
function validateRoomIDInput(roomId: string, carrier: string): string | null {
  const rid = normalizeRoomIDInput(roomId);
  if (!rid) return "Укажите room id или ссылку meet";
  for (const ch of rid) {
    if (ch.charCodeAt(0) > 127) return "Используйте латиницу и цифры";
  }
  const c = (carrier || "jitsi").trim().toLowerCase();
  // Только Jitsi требует полный URL meet; остальные провайдеры — ID комнаты.
  if (c === "jitsi") {
    if (rid.startsWith("http://") || rid.startsWith("https://")) {
      try {
        new URL(rid);
        return null;
      } catch {
        return "Некорректная ссылка Jitsi";
      }
    }
    if (rid.includes(".") && !rid.includes(" ")) return null;
    return "Некорректная ссылка: https://meet.example.com/room или meet.example.com/room";
  }
  if (c === "telemost" || c === "wbstream") {
    if (rid.startsWith("http://") || rid.startsWith("https://")) {
      return "Для этого провайдера укажите ID комнаты, а не ссылку";
    }
    if (/^[a-zA-Z0-9_-]+$/.test(rid) && rid.length >= 1 && rid.length <= 128) return null;
    return "Некорректный ID комнаты (латиница, цифры, _ и -)";
  }
  return null;
}

function validateClientIDInput(id: string): string | null {
  const v = id.trim();
  if (!v) return "Укажите ID клиента";
  if (v.length > 64) return "ID не длиннее 64 символов";
  if (!/^[a-zA-Z0-9_-]+$/.test(v)) return "ID: только латиница, цифры, _ и -";
  return null;
}

function assertLocationsValid(locations: ClientLocationForm[]) {
  for (const loc of locations) {
    if (loc.carrier === "jitsi" && !loc.jitsi_instance.trim()) {
      throw new Error("Укажите Jitsi Server");
    }
    const roomID = loc.carrier === "jitsi" ? jitsiRoomForSubmit(loc) : loc.room_id;
    const err = validateRoomIDInput(roomID, loc.carrier);
    if (err) throw new Error(err);
  }
}

function RoomIDInput({
  value,
  carrier,
  jitsiServer,
  onChange,
  inputClassName = "h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary",
}: {
  value: string;
  carrier: string;
  jitsiServer?: string;
  onChange: (value: string) => void;
  inputClassName?: string;
}) {
  const valueForValidation = carrier === "jitsi" ? combineJitsiRoomId(jitsiServer || "", value) : value;
  const err = value.trim() ? validateRoomIDInput(valueForValidation, carrier) : null;
  return (
    <div className="grid gap-1">
      <div className="flex gap-2">
        <input
          className={`${inputClassName} flex-1${err ? " border-destructive/70 focus:border-destructive" : ""}`}
          value={value}
          onChange={(event) => onChange(event.target.value)}
          placeholder={carrier === "jitsi" ? "room-name или полная Jitsi-ссылка" : roomPlaceholder(carrier)}
        />
        {carrier === "jitsi" ? (
          <button
            className="inline-flex h-10 items-center rounded-md border border-primary bg-secondary px-3 text-xs font-medium text-primary hover:bg-primary/10"
            type="button"
            onClick={() => onChange(randomRoomUUID())}
          >
            UUID
          </button>
        ) : null}
      </div>
      {err ? <p className="text-xs text-destructive">{err}</p> : null}
    </div>
  );
}

/* OLC_JITSI_HTTPS_DISCOVERY_UI_V1 */
/* OLC_JITSI_FORM_LAYOUT_V1 */
/* OLC_JITSI_BATCH_IMPORT_V1 */
type JitsiHTTPSCandidate = {
  domain: string;
  url: string;
  confidence: string;
  evidence: string[];
};

type JitsiHTTPSDiscoveryResult = {
  ok: boolean;
  source_ip?: string;
  summary: string;
  candidates: JitsiHTTPSCandidate[];
  tried: number;
};

function numericJitsiIP(value: string): string | null {
  const raw = value.trim();
  if (!raw) return null;
  try {
    const parsed = new URL(/^[a-z][a-z0-9+.-]*:\/\//i.test(raw) ? raw : `http://${raw}`);
    const host = parsed.hostname.replace(/^\[|\]$/g, "");
    if (/^\d{1,3}(?:\.\d{1,3}){3}$/.test(host)) {
      const parts = host.split(".").map(Number);
      return parts.every((part) => part >= 0 && part <= 255) ? host : null;
    }
    return /^[0-9a-f:]+$/i.test(host) && host.includes(":") ? host : null;
  } catch {
    return null;
  }
}

type JitsiBatchItem = {
  source: string;
  status: "pending" | "checking" | "done" | "error";
  result?: JitsiHTTPSDiscoveryResult;
  error?: string;
};

function parseJitsiHTTPIPFile(text: string): { items: JitsiBatchItem[]; httpsSkipped: number; invalidSkipped: number; duplicatesSkipped: number } {
  const seen = new Set<string>();
  const items: JitsiBatchItem[] = [];
  let httpsSkipped = 0;
  let invalidSkipped = 0;
  let duplicatesSkipped = 0;
  for (const token of text.split(/[,;\r\n]+/)) {
    const raw = token.trim().replace(/^["']|["']$/g, "");
    if (!raw) continue;
    if (/^https:\/\//i.test(raw)) { httpsSkipped += 1; continue; }
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(raw) && !/^http:\/\//i.test(raw)) { invalidSkipped += 1; continue; }
    try {
      const parsed = new URL(/^http:\/\//i.test(raw) ? raw : `http://${raw}`);
      const ip = numericJitsiIP(parsed.href);
      if (!ip) { invalidSkipped += 1; continue; }
      const host = ip.includes(":") ? `[${ip}]` : ip;
      const source = `http://${host}${parsed.port ? `:${parsed.port}` : ""}`;
      if (seen.has(source)) { duplicatesSkipped += 1; continue; }
      seen.add(source);
      items.push({ source, status: "pending" });
    } catch { invalidSkipped += 1; }
  }
  return { items, httpsSkipped, invalidSkipped, duplicatesSkipped };
}

function JitsiHTTPSDiscovery({ onUse }: { onUse: (server: string) => void }) {
  const [source, setSource] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<JitsiHTTPSDiscoveryResult | null>(null);
  const [error, setError] = useState("");
  const [batch, setBatch] = useState<JitsiBatchItem[]>([]);
  const [batchBusy, setBatchBusy] = useState(false);
  const [batchNote, setBatchNote] = useState("");
  const [batchExpanded, setBatchExpanded] = useState(false);
  const ip = numericJitsiIP(source);

  useEffect(() => {
    setResult(null);
    setError("");
  }, [source]);

  const discover = useCallback(async () => {
    if (!ip) return;
    setBusy(true);
    setError("");
    try {
      const response = await request(`/api/jitsi/discover-https?server=${encodeURIComponent(source.trim())}`, { cache: "no-store" });
      const body = (await response.json()) as JitsiHTTPSDiscoveryResult;
      setResult(body);
      if (!response.ok) setError(body.summary || `HTTP ${response.status}`);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }, [ip, source]);

  const loadBatchFile = useCallback(async (file: File | undefined) => {
    if (!file) return;
    if (file.size > 1024 * 1024) {
      setBatch([]);
      setBatchNote("Файл больше 1 MiB — выберите меньший список");
      return;
    }
    const parsed = parseJitsiHTTPIPFile(await file.text());
    setBatch(parsed.items);
    setBatchExpanded(parsed.items.length > 0 && parsed.items.length <= 5);
    setBatchNote(`Принято HTTP IP: ${parsed.items.length} · пропущено HTTPS: ${parsed.httpsSkipped} · некорректных: ${parsed.invalidSkipped} · дублей: ${parsed.duplicatesSkipped}`);
  }, []);

  const discoverBatch = useCallback(async () => {
    if (!batch.length || batchBusy) return;
    setBatchBusy(true);
    setBatch((current) => current.map((item) => ({ ...item, status: "pending", result: undefined, error: undefined })));
    let cursor = 0;
    const worker = async () => {
      while (true) {
        const index = cursor++;
        if (index >= batch.length) return;
        const item = batch[index];
        setBatch((current) => current.map((entry, i) => i === index ? { ...entry, status: "checking" } : entry));
        try {
          const response = await request(`/api/jitsi/discover-https?server=${encodeURIComponent(item.source)}`, { cache: "no-store" });
          const body = (await response.json()) as JitsiHTTPSDiscoveryResult;
          setBatch((current) => current.map((entry, i) => i === index ? { ...entry, status: response.ok ? "done" : "error", result: body, error: response.ok ? undefined : body.summary || `HTTP ${response.status}` } : entry));
        } catch (cause) {
          const message = cause instanceof Error ? cause.message : String(cause);
          setBatch((current) => current.map((entry, i) => i === index ? { ...entry, status: "error", error: message } : entry));
        }
      }
    };
    await Promise.all(Array.from({ length: Math.min(3, batch.length) }, () => worker()));
    setBatchBusy(false);
  }, [batch, batchBusy]);

  const hasInsecureCandidate = Boolean(result?.candidates.some((candidate) => candidate.confidence !== "verified"));
  const batchFinished = batch.filter((item) => item.status === "done" || item.status === "error").length;
  const batchFound = batch.filter((item) => Boolean(item.result?.candidates.length)).length;
  return (
    <div className="grid gap-2 rounded-md border border-border bg-background/50 p-3 text-xs">
      <div className="grid gap-2">
        <div>
          <div className="font-medium text-foreground">Помощник Jitsi HTTP IP → HTTPS-домен</div>
          <div className="mt-0.5 text-[11px] text-muted-foreground">Проверяет DNS, Jitsi endpoints и доверие TLS. Домены с просроченным/недоверенным сертификатом показываются отдельно и требуют insecure TLS.</div>
        </div>
        <div className="flex gap-2">
          <input
            className="h-9 min-w-0 flex-1 rounded-md border border-border bg-card px-3 font-mono text-xs text-foreground outline-none focus:border-primary"
            value={source}
            onChange={(event) => setSource(event.target.value)}
            placeholder="HTTP IP Jitsi, например 185.16.214.115"
          />
          <button
            type="button"
            className="inline-flex h-9 shrink-0 items-center rounded-md border border-border px-3 text-xs text-foreground hover:bg-muted disabled:opacity-50"
            disabled={busy || !ip}
            onClick={() => void discover()}
          >
            {busy ? "Проверяю…" : "Найти HTTPS-домен"}
          </button>
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-2 border-t border-border pt-2">
        <label className="inline-flex h-8 cursor-pointer items-center rounded-md border border-border px-3 text-xs text-foreground hover:bg-muted">
          Загрузить список IP
          <input className="hidden" type="file" accept=".txt,.csv,text/plain,text/csv" onChange={(event) => { void loadBatchFile(event.target.files?.[0]); event.target.value = ""; }} />
        </label>
        <button type="button" className="inline-flex h-8 items-center rounded-md border border-border px-3 text-xs text-foreground hover:bg-muted disabled:opacity-50" disabled={!batch.length || batchBusy} onClick={() => void discoverBatch()}>
          {batchBusy ? `Проверено ${batchFinished}/${batch.length}` : `Проверить список${batch.length ? ` (${batch.length})` : ""}`}
        </button>
        {batch.length ? <button type="button" className="inline-flex h-8 items-center rounded-md border border-border px-3 text-xs text-muted-foreground hover:bg-muted" onClick={() => { setBatch([]); setBatchNote(""); setBatchExpanded(false); }}>Очистить список</button> : null}
        <span className="text-[10px] text-muted-foreground">Разделители: запятая, ; или перенос строки. HTTPS-записи пропускаются.</span>
      </div>
      {batchNote ? <p className="text-[11px] text-muted-foreground">{batchNote}</p> : null}
      {batch.length ? (
        <div className="rounded-md border border-border bg-card/60">
          <button type="button" className="flex w-full items-center justify-between gap-3 px-3 py-2 text-left hover:bg-muted/50" onClick={() => setBatchExpanded((current) => !current)}>
            <span className="font-medium text-foreground">Пакетная проверка · {batchFound} найдено · {batchFinished}/{batch.length} завершено</span>
            <span className="text-muted-foreground">{batchExpanded ? "Свернуть" : "Развернуть"}</span>
          </button>
          {batchExpanded ? (
            <div className="max-h-72 overflow-y-auto border-t border-border p-2"><div className="grid gap-2">
              {batch.map((item) => (
                <div key={item.source} className="grid gap-1 rounded-md border border-border bg-background/60 p-2">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-mono text-foreground">{item.source}</span>
                    <span className={item.status === "error" ? "text-destructive" : item.status === "done" ? "text-primary" : "text-muted-foreground"}>{item.status === "pending" ? "ожидает" : item.status === "checking" ? "проверяется…" : item.status === "done" ? "готово" : "ошибка"}</span>
                  </div>
                  {item.error ? <div className="text-destructive">{item.error}</div> : null}
                  {item.result && !item.result.candidates.length ? <div className="text-muted-foreground">{item.result.summary}</div> : null}
                  {item.result?.candidates.map((candidate) => (
                    <div key={candidate.domain} className="flex flex-wrap items-center justify-between gap-2">
                      <span className={candidate.confidence === "verified" ? "font-mono text-primary" : "font-mono text-amber-500"}>{candidate.url}</span>
                      <button type="button" className="inline-flex h-7 items-center rounded-md border border-border px-2 text-[11px] text-foreground hover:bg-muted" onClick={() => onUse(candidate.url)}>Использовать</button>
                    </div>
                  ))}
                </div>
              ))}
            </div></div>
          ) : null}
        </div>
      ) : null}
      {error ? <p className="text-destructive">{error}</p> : null}
      {result ? (
        <div className="grid gap-2">
          <p className={result.ok && !hasInsecureCandidate ? "text-primary" : "text-amber-500"}>{result.summary} · проверено кандидатов: {result.tried}</p>
          {result.candidates.map((candidate) => {
            const trusted = candidate.confidence === "verified";
            return (
            <div key={candidate.domain} className={`grid gap-1 rounded-md border p-2 ${trusted ? "border-primary/30 bg-primary/5" : "border-amber-500/40 bg-amber-500/5"}`}>
              <div className="flex flex-wrap items-center justify-between gap-2">
                <span className={`font-mono ${trusted ? "text-primary" : "text-amber-500"}`}>{candidate.url}</span>
                <button
                  type="button"
                  className={`inline-flex h-7 items-center rounded-md border px-2 text-[11px] ${trusted ? "border-primary/40 text-primary hover:bg-primary/10" : "border-amber-500/50 text-amber-500 hover:bg-amber-500/10"}`}
                  onClick={() => onUse(candidate.url)}
                >
                  Использовать
                </button>
              </div>
              <div className={`text-[10px] font-medium ${trusted ? "text-primary" : "text-amber-500"}`}>
                {trusted ? "TLS-сертификат доверен" : "Требует OLCRTC_JITSI_INSECURE_TLS=1"}
              </div>
              {candidate.evidence.slice(0, 4).map((item) => <div key={item} className="text-[10px] text-muted-foreground">• {item}</div>)}
            </div>
          )})}
        </div>
      ) : null}
    </div>
  );
}

function Socks5ProxyFields({
  proxy,
  onChange,
  title = "Upstream SOCKS5",
  hiddenReason = "",
  inputClassName = "h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary",
}: {
  proxy: Socks5Proxy;
  onChange: (proxy: Socks5Proxy) => void;
  title?: string;
  hiddenReason?: string;
  inputClassName?: string;
}) {
  const set = (patch: Partial<Socks5Proxy>) => onChange(proxyFromState({ ...proxy, ...patch }));
  if (hiddenReason) {
    return (
      <div className="rounded-md border border-primary/40 bg-primary/10 p-3 text-xs text-primary">
        {hiddenReason} Сохранённые настройки этого уровня не удалены.
      </div>
    );
  }
  return (
    <div className="grid gap-3 rounded-md border border-border bg-background p-3">
      <div className="flex items-center justify-between gap-3 text-sm font-medium text-foreground">
        <span>{title}</span>
        <OlcToggleButton  checked={proxy.enabled} onChange={(event) => set({ enabled: event.target.checked })} />
      </div>
      <p className="text-[11px] text-amber-300">
        Это серверный исходящий SOCKS5 для OlcRTC, а не локальный SOCKS-порт приложения OlcBox.
        Он имеет приоритет над автоматическим Tor/WARP. При недоступности прокси прямого обхода не будет.
      </p>
      {proxy.enabled ? (
        <>
          <div className="grid gap-3 md:grid-cols-2">
            <label className="grid gap-2 text-sm text-muted-foreground">Host
              <input className={inputClassName} value={proxy.addr} onChange={(event) => set({ addr: event.target.value })} placeholder="proxy.example.org" />
            </label>
            <label className="grid gap-2 text-sm text-muted-foreground">Port
              <input className={inputClassName} type="number" min="1" max="65535" value={proxy.port} onChange={(event) => set({ port: event.target.value })} placeholder="1080" />
            </label>
            <label className="grid gap-2 text-sm text-muted-foreground">User
              <input className={inputClassName} value={proxy.user} onChange={(event) => set({ user: event.target.value })} autoComplete="off" />
            </label>
            <label className="grid gap-2 text-sm text-muted-foreground">Password
              <input className={inputClassName} type="password" value={proxy.pass} onChange={(event) => set({ pass: event.target.value })} autoComplete="new-password" />
            </label>
          </div>
          <label className="grid gap-2 text-sm text-muted-foreground">Маршрутизация
            <select className={inputClassName} value={proxy.routing} onChange={(event) => set({ routing: event.target.value === "all" ? "all" : "split" })}>
              <option value="split">Сохранять split/Tor/Zapret-правила (рекомендуется)</option>
              <option value="all">Весь трафик инстанса через этот SOCKS5</option>
            </select>
          </label>
        </>
      ) : (
        <p className="text-[11px] text-muted-foreground">Выключено: используется следующий уровень или штатная автоматическая маршрутизация.</p>
      )}
    </div>
  );
}

type JitsiPreflightResult = {
  ok?: boolean;
  code?: string;
  summary?: string;
  details?: string[];
  ws_status?: number;
  ws_url?: string;
  bosh_status?: number;
  bosh_url?: string;
  bridge_postjoin_risk?: boolean;
  bridge_postjoin_note?: string;
};

function JitsiPreflightNotice({ carrier, roomID }: { carrier: string; roomID: string }) {
  const { t } = usePanelLang();
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<JitsiPreflightResult | null>(null);
  const [error, setError] = useState("");
  const normalized = normalizeRoomIDInput(roomID);
  const canCheck = (carrier || "").toLowerCase() === "jitsi" && Boolean(normalized);
  const roomErr = canCheck ? validateRoomIDInput(normalized, "jitsi") : null;

  const runCheck = useCallback(async () => {
    if (!canCheck || roomErr) return;
    setBusy(true);
    setError("");
    try {
      const q = encodeURIComponent(normalized);
      const res = await request(`/api/jitsi/preflight?room_id=${q}`, { cache: "no-store" });
      setResult((await res.json()) as JitsiPreflightResult);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }, [canCheck, roomErr, normalized]);

  useEffect(() => {
    if (!canCheck || roomErr) {
      setResult(null);
      setError("");
      return;
    }
    const id = window.setTimeout(() => void runCheck(), 700);
    return () => window.clearTimeout(id);
  }, [canCheck, roomErr, runCheck]);

  if ((carrier || "").toLowerCase() !== "jitsi") return null;
  return (
    <div className="mt-2 rounded-md border border-border/80 bg-muted/20 px-3 py-2 text-xs">
      <div className="flex items-center justify-between gap-2">
        <span className="text-muted-foreground">Jitsi preflight</span>
        <button
          type="button"
          className="inline-flex items-center rounded-md border border-border bg-background px-2 py-1 hover:bg-accent disabled:opacity-50"
          disabled={!canCheck || Boolean(roomErr) || busy}
          onClick={() => void runCheck()}
        >
          {busy ? "Проверка…" : "Проверить"}
        </button>
      </div>
      {roomErr ? (
        <p className="mt-1 text-destructive">{roomErr}</p>
      ) : error ? (
        <p className="mt-1 text-destructive">Ошибка проверки: {error}</p>
      ) : result ? (
        <div className="mt-1 space-y-1">
          <p className={result.ok ? "text-emerald-400" : (result.code === "jitsi-websocket-404" || result.code === "invalid-room" ? "text-destructive" : "text-amber-300")}>
            {result.summary || "Проверка завершена"}
          </p>
          <p className="text-muted-foreground">
            ws: {result.ws_status ?? "?"} {result.ws_url ? `(${result.ws_url})` : ""}
          </p>
          {result.details?.slice(0, 3).map((d) => (
            <p key={d} className="text-muted-foreground">
              - {d}
            </p>
          ))}
          <div className="mt-2 rounded border border-border/70 bg-background/40 px-2 py-2">
            <p className="text-[11px] uppercase text-muted-foreground">Bridge WS compatibility (post-join pattern)</p>
            <p className={result.bridge_postjoin_risk ? "mt-1 text-amber-300" : "mt-1 text-emerald-400"}>
              {result.bridge_postjoin_risk
                ? "join может пройти, но bridge websocket может быть несовместим"
                : "явных признаков bridge websocket-конфликта не обнаружено"}
            </p>
            <p className="mt-1 text-muted-foreground">
              OK-паттерн: "jitsi: bridge open ..." + "Link connected"
            </p>
            <p className="text-muted-foreground">
              Fail-паттерн: "expected handshake response status code 101 but got 200"
            </p>
            {result.bridge_postjoin_note ? (
              <p className="mt-1 text-muted-foreground">Подсказка: {result.bridge_postjoin_note}</p>
            ) : null}
          </div>
        </div>
      ) : (
        <p className="mt-1 text-muted-foreground">Проверка запускается автоматически при вводе room URL.</p>
      )}
    </div>
  );
}


function roomPlaceholder(carrier: string) {
  return carrier === "jitsi" ? "https://meet.example.org/room" : "room-id";
}

function normalizeLocationForm(location: ClientLocationForm): ClientLocationForm {
  const normalized: ClientLocationForm = { ...location, proxy: proxyFromState(location.proxy) };
  if (normalized.carrier === "jitsi") {
    const fromServer = splitJitsiRoomInput(normalized.jitsi_instance || "");
    const fromRoom = splitJitsiRoomInput(normalized.room_id || "");
    const split = fromRoom || fromServer;
    if (split) {
      normalized.jitsi_instance = split.server;
      normalized.room_id = split.room;
    }
  }
  const options = transportOptions(normalized.carrier, normalized.transport);
  const transport = options.includes(normalized.transport) ? normalized.transport : options[0];
  const fields = payloadFields[transport] ?? [];
  const allowed = new Set(fields.map((field) => field.key));
  const payload = Object.fromEntries(Object.entries(normalized.payload).filter(([key]) => allowed.has(key)));
  for (const field of fields) {
    if (!payload[field.key]?.trim()) payload[field.key] = field.defaultValue;
  }
  const link = (normalized.link?.trim() || "tor").toLowerCase();
  return mergeInstanceDefaults({
    ...normalized,
    transport,
    payload,
    link: link === "direct" ? "direct" : "tor",
  });
 }

function locationStateForEdit(location: LocationState): ClientLocationForm {
  const raw = location as LocationState & { proxy?: Partial<Socks5Proxy> & { port?: string | number } };
  return normalizeLocationForm({
    name: location.name,
    room_id: location.room_id,
    jitsi_instance: "",
    key: location.key,
    carrier: location.carrier,
    transport: location.transport,
    payload: location.payload ?? {},
    dns: location.dns,
    proxy: proxyFromState(raw.proxy),
    link: location.link,
  });
}

function normalizeForm(form: ClientForm): ClientForm {
  return {
    ...form,
    proxy: proxyFromState(form.proxy),
    locations: form.locations.length ? form.locations.map(normalizeLocationForm) : [{ ...defaultLocationForm, proxy: emptyProxy() }],
  };
}

function payloadForSubmit(payload: Record<string, string>) {
  return Object.fromEntries(Object.entries(payload).filter(([, value]) => value.trim() !== ""));
}

function randomHex64() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}


const defaultRuntime = (): RuntimeState => ({
  status: "unknown",
  running: false,
  log_count: 0,
  restarts: 0,
});

function normalizeLocationState(loc: Partial<LocationState>): LocationState {
  const runtime = loc.runtime ?? defaultRuntime();
  return {
    name: loc.name ?? "Default",
    room_id: loc.room_id ?? "",
    key: loc.key ?? "",
    uri: loc.uri ?? "",
    carrier: loc.carrier ?? "jitsi",
    transport: loc.transport ?? "datachannel",
    payload: loc.payload ?? {},
    link: loc.link ?? "tor",
    dns: loc.dns ?? "1.1.1.1:53",
    proxy: proxyFromState(loc.proxy),
    running: Boolean(loc.running ?? runtime.running),
    runtime: {
      ...defaultRuntime(),
      ...runtime,
      running: Boolean(runtime.running),
    },
  };
}

function normalizePanelState(raw: State): State {
  const clients = (raw.clients ?? [])
    .filter((c) => c && typeof c === "object")
    .map((c) => ({
      client_id: String(c.client_id ?? "").trim(),
      refresh: c.refresh,
      quota: c.quota ?? {},
      proxy: proxyFromState(c.proxy),
      locations: (c.locations ?? []).map((loc) => normalizeLocationState(loc as Partial<LocationState>)),
      randomization: c.randomization,
    }))
    .filter((c) => c.client_id !== "");
  return {
    ...raw,
    clients,
    client_count: clients.length,
    port: Number(raw.port) || 8888,
  };
}

class PanelErrorBoundary extends React.Component<
  { children: React.ReactNode },
  { error: Error | null }
> {
  state = { error: null as Error | null };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  render() {
    if (this.state.error) {
      return (
        <div className="grid min-h-screen place-items-center p-6">
          <div className="max-w-lg rounded-lg border border-destructive/40 bg-card p-6 text-sm">
            <h2 className="text-lg font-semibold text-destructive">{panelT("panelErrorTitle", readPanelLang())}</h2>
            <p className="mt-2 text-muted-foreground">{panelT("panelErrorHint", readPanelLang())}</p>
            <pre className="mt-3 max-h-40 overflow-auto rounded border border-border bg-background p-2 text-xs">
              {this.state.error.message}
            </pre>
            <button
              type="button"
              className="mt-4 rounded-md border border-border bg-muted px-3 py-2 hover:bg-muted/80"
              onClick={() => window.location.reload()}
            >
              {panelT("reloadPage", readPanelLang())}
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}


function formatBytes(bytes?: number) {
  if (!bytes) return "...";
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

async function olcSafeCopy(text: string): Promise<void> {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }
  } catch { /* fall through to legacy copy */ }
  const ta = document.createElement("textarea");
  ta.value = text;
  ta.style.position = "fixed";
  ta.style.opacity = "0";
  document.body.appendChild(ta);
  ta.select();
  try { document.execCommand("copy"); } finally { document.body.removeChild(ta); }
}

function subscriptionURL(clientID: string, subscriptionPath?: string) {
  const path = subscriptionPath?.trim().replace(/^\/+|\/+$/g, "") || "sub";
  const prefix = path ? `/${path}` : "";
  return `${window.location.origin}${prefix}/${encodeURIComponent(clientID)}/`;
}

function logsURL(clientID: string, location: LocationState) {
  const params = new URLSearchParams({
    client_id: clientID,
    room_id: location.room_id,
    transport: location.transport,
  });
  return `/api/logs/?${params.toString()}`;
}

const LOGS_VERBOSE_STORAGE_KEY = "olc-panel-logs-verbose-v1";
const LOGS_LIVE_STORAGE_KEY = "olc-panel-logs-live-v1";
const LOGS_LIVE_INTERVAL_MS = 2_000;

function usePersistedOpen(key: string): [boolean, (v: boolean | ((p: boolean) => boolean)) => void] {
  const [open, setOpenRaw] = useState(() => readStoredBool(key, false));
  const setOpen = useCallback((v: boolean | ((p: boolean) => boolean)) => {
    setOpenRaw((prev) => {
      const next = typeof v === "function" ? (v as (p: boolean) => boolean)(prev) : v;
      writeStoredBool(key, next);
      return next;
    });
  }, [key]);
  return [open, setOpen];
}

function readStoredBool(key: string, fallback = false) {
  try {
    const value = window.localStorage.getItem(key);
    if (value === "1") return true;
    if (value === "0") return false;
  } catch {
    // localStorage can be unavailable in restricted browser contexts.
  }
  return fallback;
}

function writeStoredBool(key: string, value: boolean) {
  try {
    window.localStorage.setItem(key, value ? "1" : "0");
  } catch {
    // Ignore persistence failures; the UI state still works for this session.
  }
}

// olcMergeTail: append-only склейка предыдущих строк лога с новым снапшотом-хвостом.
// next обычно = prev, у которого срезано начало и дописаны новые строки. Находим
// наибольшее перекрытие (суффикс prev == префикс next) и дописываем только хвост,
// чтобы старые строки не «уезжали» при ротации буфера. cap ограничивает рост.
function olcMergeTail<T>(prev: T[], next: T[], key: (x: T) => string, cap = 1500): T[] {
  if (!prev || prev.length === 0) return (next || []).slice(-cap);
  if (!next || next.length === 0) return prev;
  const maxK = Math.min(prev.length, next.length);
  let overlap = 0;
  for (let k = maxK; k > 0; k--) {
    let ok = true;
    for (let i = 0; i < k; i++) {
      if (key(prev[prev.length - k + i]) !== key(next[i])) { ok = false; break; }
    }
    if (ok) { overlap = k; break; }
  }
  const merged = prev.concat(next.slice(overlap));
  return merged.length > cap ? merged.slice(-cap) : merged;
}

function useStickyLogScroll<T extends HTMLElement>(deps: React.DependencyList, enabled = true) {
  const ref = useRef<T | null>(null);
  const stickToBottom = useRef(true);
  const olcStickyResume = useRef<number | null>(null);
  const onScroll = useCallback(() => {
    const el = ref.current;
    if (!el) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 32;
    if (nearBottom) {
      // Возврат к низу — возобновляем автопрокрутку с задержкой ~700мс,
      // чтобы не дёргать вниз, пока пользователь ещё листает у низа.
      if (olcStickyResume.current) window.clearTimeout(olcStickyResume.current);
      olcStickyResume.current = window.setTimeout(() => { stickToBottom.current = true; }, 700);
    } else {
      // Листаем вверх — немедленно останавливаем автопрокрутку.
      stickToBottom.current = false;
      if (olcStickyResume.current) { window.clearTimeout(olcStickyResume.current); olcStickyResume.current = null; }
    }
  }, []);

  useEffect(() => {
    if (!enabled || !stickToBottom.current) return;
    window.requestAnimationFrame(() => {
      const el = ref.current;
      if (el) el.scrollTop = el.scrollHeight;
    });
  }, deps);

  return { ref, onScroll };
}

function cleanQuota(quota: Quota): Quota {
  return {
    speed_mbps: quota.speed_mbps || undefined,
    traffic_gb: quota.traffic_gb || undefined,
    used_gb: quota.used_gb || undefined,
    used_bytes: quota.used_bytes || undefined,
    expires_at: quota.expires_at?.trim() || undefined,
  };
}

function cleanRefresh(refresh: string) {
  return refresh.trim() || undefined;
}

function locationsForSubmit(locations: ClientLocationForm[]) {
  return locations.map((location) => ({
    name: location.name.trim(),
    room_id: location.carrier === "jitsi" ? jitsiRoomForSubmit(location) : normalizeRoomIDInput(location.room_id),
    key: location.key.trim(),
    carrier: location.carrier,
    transport: location.transport,
    payload: payloadForSubmit(location.payload),
    dns: location.dns.trim(),
    proxy: proxyForSubmit(location.proxy),
    link: (location.link?.trim() || "tor").toLowerCase(),
  }));
}

function quotaText(quota?: Quota) {
  if (!quota) return "none";
  const parts = [];
  if (quota.speed_mbps) parts.push(`${quota.speed_mbps} Mbps`);
  if (quota.traffic_gb) {
    const used = quota.used_bytes ? (quota.used_bytes / 1024 / 1024 / 1024).toFixed(2) : `${quota.used_gb ?? 0}`;
    parts.push(`${used}/${quota.traffic_gb} GB`);
  }
  if (quota.expires_at) parts.push(`до ${quota.expires_at}`);
  return parts.length ? parts.join(" · ") : "none";
}

function clientSummary(client: ClientState, running: number) {
  const parts = [`${client.locations.length} локац.`, `${running} running`, quotaText(client.quota)];
  if (client.refresh) parts.push(`refresh ${client.refresh}`);
  return parts.join(" · ");
}

function ProfileStatCard({
  name,
  onSave,
}: {
  name: string;
  onSave: (next: string) => Promise<void>;
}) {
  const [editing, setEditing] = useState(false);
  const [val, setVal] = useState(name);
  const [err, setErr] = useState("");
  useEffect(() => setVal(name), [name]);
  return (
    <div className="rounded-lg border border-border bg-card p-4">
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <Server className="h-4 w-4" />
        <span>Профиль</span>
      </div>
      {editing ? (
        <div className="mt-2 flex gap-2">
          <input className="h-9 flex-1 rounded-md border border-border bg-background px-2 text-sm" value={val} onChange={(e) => setVal(e.target.value)} />
          <button type="button" className="rounded border border-primary px-2 text-xs text-primary" onClick={() =>
            void onSave(val)
              .then(() => {
                setErr("");
                setEditing(false);
              })
              .catch((e) => setErr(e instanceof Error ? e.message : String(e)))
          }>
            OK
          </button>
        </div>
      ) : (
        <button type="button" className="mt-2 block text-left text-2xl font-semibold hover:text-primary" onClick={() => setEditing(true)} title="Переименовать">
          {name || "…"}
        </button>
      )}
      {err && <p className="mt-2 text-xs text-destructive">{err}</p>}
    </div>
  );
}

function StatCard({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode;
  label: string;
  value: React.ReactNode;
}) {
  return (
    <div className="rounded-lg border border-border bg-card p-4">
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        {icon}
        <span>{label}</span>
      </div>
      <div className="mt-2 text-2xl font-semibold tracking-normal">{value}</div>
    </div>
  );
}

function HeaderMetric({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="grid h-9 min-w-24 content-center rounded-md border border-border bg-card px-3">
      <div className="text-[10px] uppercase leading-3 text-muted-foreground">{label}</div>
      <div className="text-sm font-semibold leading-4">{value}</div>
    </div>
  );
}

/** Прокрутка логов: колёсико не уезжает на фоновую страницу. */
const LogScrollBox = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(function LogScrollBox({
  className = "",
  children,
  ...rest
}, ref) {
  return (
    <div
      ref={ref}
      className={`overscroll-contain ${className}`}
      onWheel={(e) => e.stopPropagation()}
      {...rest}
    >
      {children}
    </div>
  );
});

const LogScrollPre = React.forwardRef<HTMLPreElement, React.HTMLAttributes<HTMLPreElement>>(function LogScrollPre({
  className = "",
  children,
  ...rest
}, ref) {
  return (
    <pre
      ref={ref}
      className={`overscroll-contain ${className}`}
      onWheel={(e) => e.stopPropagation()}
      {...rest}
    >
      {children}
    </pre>
  );
});

function LoadingState({ label }: { label: string }) {
  return (
    <div className="flex items-center gap-3 rounded-md border border-border bg-muted/20 p-3 text-xs text-muted-foreground">
      <span className="relative inline-flex h-9 w-9 items-center justify-center rounded-full border border-primary/30 bg-primary/10">
        <span className="absolute h-9 w-9 animate-ping rounded-full bg-primary/20" />
        <span className="relative h-3 w-3 animate-pulse rounded-full bg-primary" />
      </span>
      <div className="grid gap-0.5">
        <span className="font-medium text-foreground">{label}</span>
        <span>Подгружаем данные и обновляем состояние панели…</span>
      </div>
    </div>
  );
}

type OlcConfirmOptions = {
  title?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  danger?: boolean;
};

function olcConfirm(message: string, options: OlcConfirmOptions = {}): Promise<boolean> {
  return new Promise((resolve) => {
    const overlay = document.createElement("div");
    overlay.className = "fixed inset-0 z-[100] grid place-items-center bg-black/70 p-4";
    overlay.setAttribute("role", "dialog");
    overlay.setAttribute("aria-modal", "true");

    const panel = document.createElement("div");
    panel.className = "w-full max-w-lg rounded-lg border border-border bg-card p-4 shadow-2xl";

    const title = document.createElement("div");
    title.className = "text-base font-semibold text-foreground";
    title.textContent = options.title || "Подтвердите действие";

    const body = document.createElement("p");
    body.className = "mt-2 whitespace-pre-line text-sm leading-relaxed text-muted-foreground";
    body.textContent = String(message || "");

    const actions = document.createElement("div");
    actions.className = "mt-4 flex justify-end gap-2";

    const cancel = document.createElement("button");
    cancel.type = "button";
    cancel.className = "rounded-md border border-border px-3 py-1.5 text-sm hover:bg-muted";
    cancel.textContent = options.cancelLabel || "Отмена";

    const confirm = document.createElement("button");
    confirm.type = "button";
    const inferredDanger = /удал|уничтож|переустанов|отключ|uninstall|delete/i.test(String(message || ""));
    const danger = options.danger ?? inferredDanger;
    confirm.className = danger
      ? "rounded-md border border-red-500/60 bg-red-500/15 px-3 py-1.5 text-sm text-red-300 hover:bg-red-500/25"
      : "rounded-md border border-amber-500/60 bg-amber-500/15 px-3 py-1.5 text-sm text-amber-300 hover:bg-amber-500/25";
    confirm.textContent = options.confirmLabel || "Продолжить";

    const previousOverflow = document.documentElement.style.overflow;
    document.documentElement.style.overflow = "hidden";
    let finished = false;
    const finish = (accepted: boolean) => {
      if (finished) return;
      finished = true;
      document.removeEventListener("keydown", onKeyDown);
      document.documentElement.style.overflow = previousOverflow;
      overlay.remove();
      resolve(accepted);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") finish(false);
      if (event.key === "Enter") finish(true);
    };
    cancel.addEventListener("click", () => finish(false));
    confirm.addEventListener("click", () => finish(true));
    overlay.addEventListener("mousedown", (event) => {
      if (event.target === overlay) finish(false);
    });
    document.addEventListener("keydown", onKeyDown);

    actions.append(cancel, confirm);
    panel.append(title, body, actions);
    overlay.append(panel);
    document.body.append(overlay);
    window.requestAnimationFrame(() => confirm.focus());
  });
}

type MissingComponentsChoice = "skip" | "install";

function olcChooseMissingComponents(missing: string[]): Promise<MissingComponentsChoice | null> {
  return new Promise((resolve) => {
    const overlay = document.createElement("div");
    overlay.className = "fixed inset-0 z-[100] grid place-items-center bg-black/70 p-4";
    overlay.setAttribute("role", "dialog");
    overlay.setAttribute("aria-modal", "true");

    const panel = document.createElement("div");
    panel.className = "w-full max-w-xl rounded-lg border border-border bg-card p-4 shadow-2xl";

    const title = document.createElement("div");
    title.className = "text-base font-semibold text-foreground";
    title.textContent = "В бэкапе есть отсутствующие модули";

    const body = document.createElement("div");
    body.className = "mt-2 grid gap-3 text-sm leading-relaxed text-muted-foreground";
    const intro = document.createElement("p");
    intro.textContent = "На этом VPS не установлены модули, настройки и состояния которых сохранены в бэкапе:";
    const list = document.createElement("div");
    list.className = "max-h-40 overflow-y-auto rounded-md border border-border bg-background/50 p-3 font-mono text-foreground";
    list.textContent = missing.join(", ");
    const explanation = document.createElement("p");
    explanation.textContent = "Можно пропустить только данные этих модулей либо восстановить их и последовательно запустить доустановку.";
    body.append(intro, list, explanation);

    const actions = document.createElement("div");
    actions.className = "mt-4 flex flex-wrap justify-end gap-2";

    const cancel = document.createElement("button");
    cancel.type = "button";
    cancel.className = "rounded-md border border-border px-3 py-1.5 text-sm hover:bg-muted";
    cancel.textContent = "Отмена";

    const skip = document.createElement("button");
    skip.type = "button";
    skip.className = "rounded-md border border-border bg-muted/30 px-3 py-1.5 text-sm text-foreground hover:bg-muted";
    skip.textContent = "Пропустить их настройки";

    const install = document.createElement("button");
    install.type = "button";
    install.className = "rounded-md border border-primary/60 bg-primary/10 px-3 py-1.5 text-sm text-primary hover:bg-primary/20";
    install.textContent = "Восстановить и доустановить";

    const previousOverflow = document.documentElement.style.overflow;
    document.documentElement.style.overflow = "hidden";
    let finished = false;
    const finish = (choice: MissingComponentsChoice | null) => {
      if (finished) return;
      finished = true;
      document.removeEventListener("keydown", onKeyDown);
      document.documentElement.style.overflow = previousOverflow;
      overlay.remove();
      resolve(choice);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") finish(null);
    };
    cancel.addEventListener("click", () => finish(null));
    skip.addEventListener("click", () => finish("skip"));
    install.addEventListener("click", () => finish("install"));
    overlay.addEventListener("mousedown", (event) => {
      if (event.target === overlay) finish(null);
    });
    document.addEventListener("keydown", onKeyDown);

    actions.append(cancel, skip, install);
    panel.append(title, body, actions);
    overlay.append(panel);
    document.body.append(overlay);
    window.requestAnimationFrame(() => skip.focus());
  });
}

async function installBackupComponents(raw: unknown): Promise<string[]> {
  const requested = Array.isArray(raw) ? raw.filter((name): name is string => typeof name === "string") : [];
  const order = ["tor", "bridges", "split", "zapret", "warp"];
  const components = order.filter((name) => requested.includes(name));
  const installed: string[] = [];
  for (const name of components) {
    const res = await fetch(`/api/components/${name}/install`, { method: "POST" });
    const data = await res.json().catch(() => ({} as any));
    if (!res.ok) throw new Error(`Не удалось запустить установку модуля ${name}: ${data?.error || `HTTP ${res.status}`}`);
    const jobId = String(data?.job_id || "");
    if (!jobId) throw new Error(`Установка модуля ${name} не вернула job_id`);
    const status = await waitForComponentJobDone(name, jobId);
    if (status !== "done") throw new Error(`Установка модуля ${name} завершилась со статусом ${status}`);
    installed.push(name);
  }
  if (installed.length) {
    window.dispatchEvent(new Event("olc-capabilities-changed"));
    window.dispatchEvent(new Event("olc-features-changed"));
  }
  return installed;
}

async function importBackupWithDecisions(endpoint: string, body: string, foreignWarning: string) {
  let confirmedForeign = false;
  let missingMode: "" | MissingComponentsChoice = "";
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const params = new URLSearchParams();
    if (confirmedForeign) params.set("confirm_foreign_host", "1");
    if (missingMode) params.set("missing_components", missingMode);
    const suffix = params.size ? `?${params.toString()}` : "";
    const res = await fetch(endpoint + suffix, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    });
    const data = await res.json().catch(() => ({} as any));
    if (res.status === 409 && data?.code === "missing_components_confirmation_required") {
      const choice = await olcChooseMissingComponents(Array.isArray(data?.missing_components) ? data.missing_components : []);
      if (!choice) return { cancelled: true, data: null as any, installed: [] as string[] };
      missingMode = choice;
      continue;
    }
    if (res.status === 409 && data?.code === "foreign_host_confirmation_required") {
      if (!await olcConfirm(foreignWarning)) return { cancelled: true, data: null as any, installed: [] as string[] };
      confirmedForeign = true;
      continue;
    }
    if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
    const installed = await installBackupComponents(data?.install_components);
    return { cancelled: false, data, installed };
  }
  throw new Error("Импорт не удалось подтвердить после нескольких попыток");
}

function Modal({
  title,
  children,
  onClose,
  wide,
}: {
  title: string;
  children: React.ReactNode;
  onClose: () => void;
  wide?: boolean;
}) {
  useEffect(() => {
    const html = document.documentElement;
    const prev = html.style.overflow;
    html.style.overflow = "hidden";
    return () => {
      html.style.overflow = prev;
    };
  }, []);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
      onWheel={(e) => e.stopPropagation()}
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        className={`flex max-h-[min(90vh,calc(100vh-2rem))] w-full flex-col overflow-hidden rounded-lg border border-border bg-card shadow-2xl ${
          wide ? "max-w-4xl" : "max-w-3xl"
        }`}
        onWheel={(e) => e.stopPropagation()}
      >
        <div className="flex shrink-0 items-center justify-between border-b border-border px-5 py-4">
          <h2 className="text-lg font-semibold tracking-normal">{title}</h2>
          <button
            type="button"
            className="inline-flex h-9 w-9 items-center justify-center rounded-md border border-border bg-muted hover:bg-muted/80"
            onClick={onClose}
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain" onWheel={(e) => e.stopPropagation()}>
          {children}
        </div>
      </div>
    </div>
  );
}

function LoginView({ setupRequired, onLogin }: { setupRequired: boolean; onLogin: () => void }) {
  const { t } = usePanelLang();
  const [user, setUser] = useState("admin");
  const [password, setPassword] = useState("");
  const [repeat, setRepeat] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const firstRunBackupRef = useRef<HTMLInputElement | null>(null);

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      if (setupRequired && password !== repeat) throw new Error("Пароли не совпадают");
      await request(setupRequired ? "/api/auth/setup" : "/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user, password }),
      });
      onLogin();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  };

  const restoreFirstRunBackup = async (file: File) => {
    setBusy(true); setError("");
    try {
      const body = await file.text();
      const result = await importBackupWithDecisions(
        "/api/backup/import-first-run",
        body,
        "Бэкап создан на другом VPS и содержит активные room+key. Импортировать его на этот сервер?"
      );
      if (result.cancelled) return;
      await onLogin();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
      if (firstRunBackupRef.current) firstRunBackupRef.current.value = "";
    }
  };

  return (
    <div className="grid min-h-screen place-items-center bg-background px-5">
      <form className="grid w-full max-w-sm gap-4 rounded-lg border border-border bg-card p-5" onSubmit={submit}>
        <div className="flex items-center gap-3">
          <div className="grid h-10 w-10 place-items-center rounded-md bg-primary/15 text-primary">
            <Lock className="h-5 w-5" />
          </div>
          <div>
            <h1 className="text-xl font-semibold tracking-normal">OlcRTC Manager</h1>
            <div className="text-sm text-muted-foreground">{setupRequired ? t("setup") : t("login")}</div>
          </div>
        </div>
        <label className="grid gap-2 text-sm text-muted-foreground">
          Логин
          <input
            className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
            value={user}
            onChange={(event) => setUser(event.target.value)}
            autoComplete="username"
          />
        </label>
        <label className="grid gap-2 text-sm text-muted-foreground">
          Пароль
          <input
            className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            autoComplete="current-password"
          />
        </label>
        {setupRequired && (
          <label className="grid gap-2 text-sm text-muted-foreground">
            Повтор пароля
            <input
              className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
              type="password"
              value={repeat}
              onChange={(event) => setRepeat(event.target.value)}
              autoComplete="new-password"
            />
          </label>
        )}
        {setupRequired && (
          <div className="grid gap-2 rounded-md border border-border bg-muted/30 p-3">
            <div className="text-xs text-muted-foreground">Уже есть полный бекап? Восстановите его до создания новой учётной записи — логин, пароль и остальные настройки будут импортированы вместе.</div>
            <button type="button" disabled={busy} className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60" onClick={() => firstRunBackupRef.current?.click()}>
              Восстановить из бекапа JSON
            </button>
            <input ref={firstRunBackupRef} type="file" accept="application/json,.json" className="hidden" onChange={(event) => { const file = event.target.files?.[0]; if (file) void restoreFirstRunBackup(file); }} />
          </div>
        )}
        {error && <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">{error}</div>}
        <button
          className="inline-flex h-10 items-center justify-center gap-2 rounded-md bg-primary px-3 text-sm font-medium text-black hover:bg-primary/90 disabled:opacity-60"
          disabled={busy}
        >
          <Lock className="h-4 w-4" />
          {setupRequired ? t("savePassword") : t("signIn")}
        </button>
      </form>
    </div>
  );
}

function RefreshHoursPicker({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const presets = [1, 6, 12, 24];
  const raw = (value || "").trim();
  const m = /^(\d+)h$/.exec(raw);
  const curHours = m ? parseInt(m[1], 10) : 0;
  const legacy = raw !== "" && curHours === 0;
  // Пусто = дефолт olcbox 24ч → подсвечиваем 24ч ЯВНО (не оставляем пустым/невыбранным).
  const effHours = curHours > 0 ? curHours : (legacy ? 0 : 24);
  const isPreset = presets.indexOf(effHours) >= 0;
  return (
    <div className="grid gap-2">
      <div className="flex flex-wrap items-center gap-2">
        {presets.map((h) => (
          <button key={h} type="button"
            className={effHours === h
              ? "rounded-md border border-primary bg-primary/10 px-3 py-1.5 text-sm text-primary"
              : "rounded-md border border-border bg-background px-3 py-1.5 text-sm text-muted-foreground hover:bg-muted"}
            onClick={() => onChange(h + "h")}>{h}ч</button>
        ))}
        <label className="flex items-center gap-1 text-sm text-muted-foreground">
          своё:
          <input type="number" min={1} max={720}
            className="h-9 w-20 rounded-md border border-border bg-background px-2 text-foreground outline-none focus:border-primary"
            value={!isPreset && curHours > 0 ? String(curHours) : ""}
            placeholder="ч"
            onChange={(e) => { const n = parseInt(e.target.value, 10); onChange(Number.isFinite(n) && n > 0 ? String(Math.min(720, n)) + "h" : ""); }} />
        </label>
        {raw !== "" && (
          <button type="button" className="rounded-md border border-border px-2 py-1.5 text-xs text-muted-foreground hover:bg-muted" onClick={() => onChange("")}>сброс</button>
        )}
      </div>
      <div className="text-[11px] text-muted-foreground">
        {legacy
          ? "Текущее значение «" + raw + "» — устаревший формат; olcbox округлит до часов. Выберите часы явно."
          : curHours > 0
            ? "Клиент (olcbox) автообновляет подписку раз в " + curHours + " ч."
            : "По умолчанию — раз в 24 ч (значение подставляется явно; отправляется заголовком profile-update-interval)."}
        {" "}olcbox проверяет не чаще раза в час и при заходе в приложение.
      </div>
    </div>
  );
}

function ClientSettingsFields({
  form,
  setForm,
  includeClientID,
  globalProxyEnabled = false,
}: {
  form: ClientForm;
  setForm: (form: ClientForm) => void;
  includeClientID: boolean;
  globalProxyEnabled?: boolean;
}) {
  const set = (patch: Partial<ClientForm>) => setForm(normalizeForm({ ...form, ...patch }));

  return (
    <div className="grid gap-4">
      {includeClientID && (
        <label className="grid gap-2 text-sm text-muted-foreground">
          ID клиента
          <div className="flex gap-2">
            <input
              className="h-10 flex-1 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
              value={form.client_id}
              onChange={(event) => set({ client_id: event.target.value })}
              placeholder="client-id"
            />
            <button
              className="inline-flex h-10 items-center rounded-md border border-primary bg-secondary px-3 text-xs font-medium text-primary hover:bg-primary/10"
              type="button"
              onClick={() => {
                const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
                const bytes = new Uint8Array(21);
                crypto.getRandomValues(bytes);
                let client_id = "";
                for (let i = 0; i < bytes.length; i++) {
                  client_id += ALPHABET[bytes[i] % 62];
                }
                set({ client_id });
              }}
            >
              Generate
            </button>
          </div>
        </label>
      )}
      <label className="grid gap-2 text-sm text-muted-foreground">
        Интервал обновления подписки
        <RefreshHoursPicker value={form.refresh} onChange={(v) => set({ refresh: v })} />
      </label>
      <Socks5ProxyFields
        proxy={form.proxy}
        onChange={(proxy) => set({ proxy })}
        title="SOCKS5 для всех инстансов этого клиента"
        hiddenReason={globalProxyEnabled ? "Включён глобальный SOCKS5 для всех клиентов и инстансов." : ""}
      />
      <div className="grid gap-3 rounded-md border border-border bg-background p-3">
        <div className="text-sm font-medium text-foreground">Квоты клиента</div>
        <div className="grid gap-3 md:grid-cols-2">
          <label className="grid gap-2 text-sm text-muted-foreground">
            Скорость, Mbps
            <input
              className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
              type="number"
              min="0"
              value={form.quota.speed_mbps ?? ""}
              onChange={(event) => set({ quota: { ...form.quota, speed_mbps: Number(event.target.value) || undefined } })}
              placeholder="без лимита"
            />
          </label>
          <label className="grid gap-2 text-sm text-muted-foreground">
            Трафик, GB
            <input
              className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
              type="number"
              min="0"
              value={form.quota.traffic_gb ?? ""}
              onChange={(event) => set({ quota: { ...form.quota, traffic_gb: Number(event.target.value) || undefined } })}
              placeholder="без лимита"
            />
          </label>
          <label className="grid gap-2 text-sm text-muted-foreground">
            Использовано, GB
            <input
              className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
              type="number"
              min="0"
              value={form.quota.used_gb ?? ""}
              onChange={(event) => set({ quota: { ...form.quota, used_gb: Number(event.target.value) || undefined, used_bytes: undefined } })}
              placeholder="0"
            />
          </label>
          <label className="grid gap-2 text-sm text-muted-foreground">
            Действует до
            <input
              className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
              type="date"
              value={form.quota.expires_at ?? ""}
              onChange={(event) => set({ quota: { ...form.quota, expires_at: event.target.value || undefined } })}
            />
          </label>
        </div>
      </div>
    </div>
  );
}

function LocationFormFields({
  location,
  setLocation,
  globalProxyEnabled = false,
  clientProxyEnabled = false,
}: {
  location: ClientLocationForm;
  setLocation: (location: ClientLocationForm) => void;
  globalProxyEnabled?: boolean;
  clientProxyEnabled?: boolean;
}) {
  const { t } = usePanelLang();
  const set = (patch: Partial<ClientLocationForm>) => setLocation(normalizeLocationForm({ ...location, ...patch }));
  const fields = payloadFields[location.transport] ?? [];
  const transportOpts = transportOptions(location.carrier, location.transport);

  return (
    <div className="grid gap-3">
      <label className="grid gap-2 text-sm text-muted-foreground">
        Название локации
        <input
          className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
          value={location.name}
          onChange={(event) => set({ name: event.target.value })}
          placeholder="Default location"
        />
      </label>
      <div className="grid gap-3 md:grid-cols-2">
        <label className="grid gap-2 text-sm text-muted-foreground">
          Provider
          <select
            className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
            value={location.carrier}
            onChange={(event) => set({ carrier: event.target.value })}
          >
            {carriers.map((carrier) => (
              <option key={carrier} value={carrier}>
                {carrier}
              </option>
            ))}
          </select>
        </label>
        <label className="grid gap-2 text-sm text-muted-foreground">
          Transport
          <select
            className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
            value={location.transport}
            onChange={(event) => set({ transport: event.target.value })}
          >
            {transportOpts.map((transport) => (
              <option key={transport} value={transport}>
                {transport}
                {isLegacyTransport(transport) ? ` (${t("legacyTransport")})` : ""}
              </option>
            ))}
          </select>
        </label>
      </div>
      {isLegacyTransport(location.transport) && (
        <p className="rounded-md border border-amber-500/40 bg-amber-500/10 p-2 text-xs text-amber-200">{t("legacyTransportHint")}</p>
      )}
      {location.carrier === "jitsi" ? (
        <div className="grid gap-3 text-sm text-muted-foreground">
          <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_minmax(260px,0.65fr)]">
            <label className="grid gap-2">
              Jitsi Server
              <input className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary" value={location.jitsi_instance} onChange={(event) => set({ jitsi_instance: event.target.value })} placeholder={DEFAULT_JITSI_INSTANCE} />
            </label>
            <label className="grid gap-2">
              Room ID
              <RoomIDInput value={location.room_id} carrier={location.carrier} jitsiServer={location.jitsi_instance} onChange={(room_id) => set({ room_id })} />
            </label>
          </div>
          <p className="text-[11px] text-muted-foreground">Можно вставить полную ссылку сюда или в Room ID — поля разделятся автоматически.</p>
          <JitsiHTTPSDiscovery onUse={(jitsi_instance) => set({ jitsi_instance })} />
          <JitsiPreflightNotice carrier={location.carrier} roomID={jitsiRoomForSubmit(location)} />
        </div>
      ) : (
        <label className="grid gap-2 text-sm text-muted-foreground">
          Room ID
          <RoomIDInput value={location.room_id} carrier={location.carrier} onChange={(room_id) => set({ room_id })} />
          <p className="text-[11px] text-muted-foreground">Telemost / WB Stream: только ID комнаты (цифры и латиница), без https://</p>
        </label>
      )}
      <label className="grid gap-2 text-sm text-muted-foreground">
        Key
        <div className="flex gap-2">
          <input
            className="h-10 flex-1 rounded-md border border-border bg-background px-3 font-mono text-xs text-foreground outline-none focus:border-primary"
            value={location.key}
            onChange={(event) => set({ key: event.target.value })}
            placeholder="64 hex chars"
          />
          <button
            className="inline-flex h-10 items-center rounded-md border border-primary bg-secondary px-3 text-xs font-medium text-primary hover:bg-primary/10"
            type="button"
            onClick={() => set({ key: randomHex64() })}
          >
            Generate
          </button>
        </div>
      </label>
      <label className="grid gap-2 text-sm text-muted-foreground">
        DNS
        <input
          className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
          value={location.dns}
          onChange={(event) => set({ dns: event.target.value })}
          placeholder="1.1.1.1:53"
        />
      </label>
      <Socks5ProxyFields
        proxy={location.proxy}
        onChange={(proxy) => set({ proxy })}
        title="SOCKS5 только для этого инстанса"
        hiddenReason={globalProxyEnabled
          ? "Включён глобальный SOCKS5 для всех клиентов и инстансов."
          : clientProxyEnabled ? "Включён SOCKS5 для всех инстансов этого клиента." : ""}
      />
      {location.carrier === "wbstream" && location.transport === "datachannel" ? (
        <p className="rounded-md border border-amber-500/40 bg-amber-500/10 p-2 text-xs text-amber-200">Экспериментально: OlcRTC поддерживает этот режим, но обычный WB guest-токен сейчас выдаётся с canPublishData=false. Оставлено для будущих токенов с нужными правами.</p>
      ) : null}
      {fields.length > 0 && (
        <div className="grid gap-3 rounded-md border border-border bg-background p-3">
          <div className="text-sm font-medium text-foreground">Параметры транспорта</div>
          <div className="grid gap-3 md:grid-cols-2">
            {fields.map((field) => (
              <label key={field.key} className="grid gap-2 text-sm text-muted-foreground">
                {field.label}
                <input
                  className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                  value={location.payload[field.key] ?? ""}
                  onChange={(event) =>
                    set({
                      payload: {
                        ...location.payload,
                        [field.key]: clampPayloadIfMax(
                          location.carrier,
                          location.transport,
                          field.key,
                          event.target.value,
                        ),
                      },
                    })
                  }
                  placeholder={field.defaultValue}
                />
              </label>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function ClientFormFields({
  form,
  setForm,
  includeClientID,
  globalProxyEnabled = false,
}: {
  form: ClientForm;
  setForm: (form: ClientForm) => void;
  includeClientID: boolean;
  globalProxyEnabled?: boolean;
}) {
  const { t } = usePanelLang();
  const set = (patch: Partial<ClientForm>) => setForm(normalizeForm({ ...form, ...patch }));

  const setLocation = (index: number, patch: Partial<ClientLocationForm>) => {
    const locations = form.locations.map((location, current) =>
      current === index ? normalizeLocationForm({ ...location, ...patch }) : location,
    );
    set({ locations });
  };

  const addLocation = () => set({ locations: [...form.locations, { ...defaultLocationForm }] });

  const removeLocation = (index: number) => {
    if (form.locations.length <= 1) return;
    set({ locations: form.locations.filter((_, current) => current !== index) });
  };

  return (
    <div className="grid gap-4">
      {includeClientID && (
        <label className="grid gap-2 text-sm text-muted-foreground">
          ID клиента
          <div className="flex gap-2">
            <input
              className="h-10 flex-1 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
              value={form.client_id}
              onChange={(event) => set({ client_id: event.target.value })}
              placeholder="client-id"
            />
            <button
              className="inline-flex h-10 items-center rounded-md border border-primary bg-secondary px-3 text-xs font-medium text-primary hover:bg-primary/10"
              type="button"
              onClick={() => {
                const ALPHABET =
                  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

                const bytes = new Uint8Array(21);
                crypto.getRandomValues(bytes);

                let client_id = "";
                for (let i = 0; i < bytes.length; i++) {
                  client_id += ALPHABET[bytes[i] % 62];
                }

                set({ client_id });
              }}
            >
              Generate
            </button>
          </div>
        </label>
      )}
      <label className="grid gap-2 text-sm text-muted-foreground">
        Интервал обновления подписки
        <RefreshHoursPicker value={form.refresh} onChange={(v) => set({ refresh: v })} />
      </label>
      <Socks5ProxyFields
        proxy={form.proxy}
        onChange={(proxy) => set({ proxy })}
        title="SOCKS5 для всех инстансов этого клиента"
        hiddenReason={globalProxyEnabled ? "Включён глобальный SOCKS5 для всех клиентов и инстансов." : ""}
      />
      <div className="grid gap-3 rounded-md border border-border bg-background p-3">
        <div className="text-sm font-medium text-foreground">Квоты клиента</div>
        <div className="grid gap-3 md:grid-cols-2">
          <label className="grid gap-2 text-sm text-muted-foreground">
            Скорость, Mbps
            <input
              className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
              type="number"
              min="0"
              value={form.quota.speed_mbps ?? ""}
              onChange={(event) => set({ quota: { ...form.quota, speed_mbps: Number(event.target.value) || undefined } })}
              placeholder="без лимита"
            />
          </label>
          <label className="grid gap-2 text-sm text-muted-foreground">
            Трафик, GB
            <input
              className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
              type="number"
              min="0"
              value={form.quota.traffic_gb ?? ""}
              onChange={(event) => set({ quota: { ...form.quota, traffic_gb: Number(event.target.value) || undefined } })}
              placeholder="без лимита"
            />
          </label>
          <label className="grid gap-2 text-sm text-muted-foreground">
            Использовано, GB
            <input
              className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
              type="number"
              min="0"
              value={form.quota.used_gb ?? ""}
              onChange={(event) => set({ quota: { ...form.quota, used_gb: Number(event.target.value) || undefined, used_bytes: undefined } })}
              placeholder="0"
            />
          </label>
          <label className="grid gap-2 text-sm text-muted-foreground">
            Действует до
            <input
              className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
              type="date"
              value={form.quota.expires_at ?? ""}
              onChange={(event) => set({ quota: { ...form.quota, expires_at: event.target.value || undefined } })}
            />
          </label>
        </div>
      </div>
      {form.locations.map((location, index) => {
        const fields = payloadFields[location.transport] ?? [];
        const transportOpts = transportOptions(location.carrier, location.transport);
        return (
          <div key={index} className="grid gap-3 rounded-md border border-border bg-background p-3">
            <div className="flex items-center justify-between gap-2">
              <div className="text-sm font-medium text-foreground">Комната {index + 1}</div>
              {form.locations.length > 1 && (
                <button
                  className="inline-flex h-8 items-center gap-2 rounded-md border border-destructive/40 px-2 text-sm text-destructive hover:bg-destructive/10"
                  type="button"
                  onClick={() => removeLocation(index)}
                >
                  <Trash2 className="h-4 w-4" />
                  Удалить
                </button>
              )}
            </div>
            <label className="grid gap-2 text-sm text-muted-foreground">
              Название локации
              <input
                className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                value={location.name}
                onChange={(event) => setLocation(index, { name: event.target.value })}
                placeholder="Default location"
              />
            </label>
            <div className="grid gap-3 md:grid-cols-2">
              <label className="grid gap-2 text-sm text-muted-foreground">
                Provider
                <select
                  className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                  value={location.carrier}
                  onChange={(event) => setLocation(index, { carrier: event.target.value })}
                >
                  {carriers.map((carrier) => (
                    <option key={carrier} value={carrier}>
                      {carrier}
                    </option>
                  ))}
                </select>
              </label>
              <label className="grid gap-2 text-sm text-muted-foreground">
                Transport
                <select
                  className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                  value={location.transport}
                  onChange={(event) => setLocation(index, { transport: event.target.value })}
                >
                  {transportOpts.map((transport) => (
                    <option key={transport} value={transport}>
                      {transport}
                      {isLegacyTransport(transport) ? ` (${t("legacyTransport")})` : ""}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            {isLegacyTransport(location.transport) && (
              <p className="rounded-md border border-amber-500/40 bg-amber-500/10 p-2 text-xs text-amber-200">{t("legacyTransportHint")}</p>
            )}
            {location.carrier === "jitsi" ? (
              <div className="grid gap-3 text-sm text-muted-foreground">
                <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_minmax(260px,0.65fr)]">
                  <label className="grid gap-2">
                    Jitsi Server
                    <input className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary" value={location.jitsi_instance} onChange={(event) => setLocation(index, { jitsi_instance: event.target.value })} placeholder={DEFAULT_JITSI_INSTANCE} />
                  </label>
                  <label className="grid gap-2">
                    Room ID
                    <RoomIDInput value={location.room_id} carrier={location.carrier} jitsiServer={location.jitsi_instance} onChange={(room_id) => setLocation(index, { room_id })} inputClassName="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary" />
                  </label>
                </div>
                <p className="text-[11px] text-muted-foreground">Полную ссылку можно вставить в любое из двух полей.</p>
                <JitsiHTTPSDiscovery onUse={(jitsi_instance) => setLocation(index, { jitsi_instance })} />
              </div>
            ) : (
              <label className="grid gap-2 text-sm text-muted-foreground">
                Room ID
                <RoomIDInput value={location.room_id} carrier={location.carrier} onChange={(room_id) => setLocation(index, { room_id })} inputClassName="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary" />
              </label>
            )}
            <label className="grid gap-2 text-sm text-muted-foreground">
              Key
              <div className="flex gap-2">
                <input
                  className="h-10 flex-1 rounded-md border border-border bg-card px-3 font-mono text-xs text-foreground outline-none focus:border-primary"
                  value={location.key}
                  onChange={(event) => setLocation(index, { key: event.target.value })}
                  placeholder="64 hex chars"
                />
                <button
                  className="inline-flex h-10 items-center rounded-md border border-primary bg-secondary px-3 text-xs font-medium text-primary hover:bg-primary/10"
                  type="button"
                  onClick={() => setLocation(index, { key: randomHex64() })}
                >
                  Generate
                </button>
              </div>
            </label>
            <label className="grid gap-2 text-sm text-muted-foreground">
              DNS
              <input
                className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                value={location.dns}
                onChange={(event) => setLocation(index, { dns: event.target.value })}
                placeholder="1.1.1.1:53"
              />
            </label>
            <Socks5ProxyFields
              proxy={location.proxy}
              onChange={(proxy) => setLocation(index, { proxy })}
              title="SOCKS5 только для этого инстанса"
              hiddenReason={globalProxyEnabled
                ? "Включён глобальный SOCKS5 для всех клиентов и инстансов."
                : form.proxy.enabled ? "Включён SOCKS5 для всех инстансов этого клиента." : ""}
              inputClassName="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
            />
            {location.carrier === "wbstream" && location.transport === "datachannel" ? (
              <p className="rounded-md border border-amber-500/40 bg-amber-500/10 p-2 text-xs text-amber-200">Экспериментально: core сохраняет поддержку, но guest-токен WB пока не разрешает публикацию DataChannel.</p>
            ) : null}
            {fields.length > 0 && (
              <div className="grid gap-3 rounded-md border border-border bg-card p-3">
                <div className="text-sm font-medium text-foreground">Параметры транспорта</div>
                <div className="grid gap-3 md:grid-cols-2">
                  {fields.map((field) => (
                    <label key={field.key} className="grid gap-2 text-sm text-muted-foreground">
                      {field.label}
                      <input
                        className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
                        value={location.payload[field.key] ?? ""}
                        onChange={(event) =>
                          setLocation(index, {
                            payload: {
                              ...location.payload,
                              [field.key]: event.target.value,
                            },
                          })
                        }
                        placeholder={field.defaultValue}
                      />
                    </label>
                  ))}
                </div>
              </div>
            )}
          </div>
        );
      })}
      <button
        className="inline-flex h-9 items-center justify-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
        type="button"
        onClick={addLocation}
      >
        <Plus className="h-4 w-4" />
        Добавить комнату
      </button>
    </div>
  );
}

type FeatureName = "zapret" | "tor" | "split" | "bridges" | "webtunnel" | "warp" | "olcrtc";

interface FeaturesResponse {
  flags: Record<FeatureName, boolean>;
  live: Record<string, string>;
  script: string;
}


const FEATURE_SETTINGS_HINTS: Record<FeatureName, { title: string; lines: string[] }> = {
  zapret: {
    title: "Zapret",
    lines: [
      "DPI-обход для direct egress (*.ru / CDN).",
      "Полная переустановка: OLCRTC_ZAPRET_REINSTALL=1 olc-update",
      "Синхронизация списков: olc-feature zapret reload",
    ],
  },
  tor: {
    title: "Tor",
    lines: [
      "SOCKS5 127.0.0.1:9050 + bridges в /etc/tor/bridges.conf",
      "Пул мостов: systemctl start olcrtc-tor-bridge-pool.service",
      "Без Tor split не имеет смысла — нет exit для остального трафика.",
    ],
  },
  split: {
    title: "Split routing",
    lines: [
      "Требует включённый Tor.",
      "*.ru / CDN → direct (+ zapret); остальное → Tor.",
      "Полное обновление списков: olc-update (не из панели).",
      "Файлы: /var/lib/olcrtc/lists/*.txt",
    ],
  },
  olcrtc: {
    title: "OlcRTC",
    lines: ["panel.env, Jitsi TLS, публичный URL", "ветка master"],
  },
  bridges: {
    title: "Мосты",
    lines: [
      "Общий модуль мостов для Tor.",
      "Transport-подмодули: obfs4, webtunnel и snowflake.",
      "Активные transport-ы выбираются в профиле мостов.",
    ],
  },
  webtunnel: {
    title: "WebTunnel",
    lines: [
      "Бинарь: /usr/bin/webtunnel-client (mirror-cry)",
      "При выкл — Tor использует obfs4/snowflake.",
      "Включение может занять 1–2 мин (скачивание).",
    ],
  },
  warp: {
    title: "WARP",
    lines: [
      "Cloudflare WARP proxy (SOCKS5, обычно 127.0.0.1:40000).",
      "Недоступен при включённом Tor — выберите один egress.",
      "Профиль foreign-warp: install.sh --with-warp",
    ],
  },
};

function FeatureLogsModal({
  feature,
  onClose,
}: {
  feature: FeatureName;
  onClose: () => void;
}) {
  const { t } = usePanelLang();
  const [lines, setLines] = useState<string[]>([]);
  const lastFeaturePathRef = useRef<string>("");
  const [path, setPath] = useState("");
  const [loading, setLoading] = useState(true);
  const [liveRaw, setLiveRaw] = useState(() => readStoredBool(LOGS_LIVE_STORAGE_KEY, false));
  const [autologi, setAutologi] = useState(true);
  useEffect(() => {
    void fetch("/api/settings/logs", { cache: "no-store" })
      .then((r) => r.json())
      .then((b: { auto_refresh?: boolean }) => setAutologi(b.auto_refresh ?? true))
      .catch(() => setAutologi(true));
  }, []);
  const setLive = useCallback(
    (v: boolean | ((prev: boolean) => boolean)) => {
      setLiveRaw((prev) => {
        const next = typeof v === "function" ? (v as (p: boolean) => boolean)(prev) : v;
        writeStoredBool(LOGS_LIVE_STORAGE_KEY, next);
        return next;
      });
    },
    [],
  );
  const live = autologi || liveRaw;
  const logScroll = useStickyLogScroll<HTMLPreElement>([lines], true);

  const loadFeatureLogs = useCallback(
    async (showLoading = false) => {
      if (showLoading) setLoading(true);
      try {
        const res = await fetch(`/api/features/logs/${feature}`, { cache: "no-store" });
        const body = (await res.json()) as { lines?: string[]; path?: string };
        setLines((prev) => (String(body.path ?? "") !== "" && String(body.path ?? "") === lastFeaturePathRef.current) ? olcMergeTail(prev, body.lines ?? [], (x) => x, 1500) : (body.lines ?? []));
        lastFeaturePathRef.current = String(body.path ?? "");
        setPath(body.path ?? "");
      } catch (e) {
        setLines([String(e)]);
      } finally {
        setLoading(false);
      }
    },
    [feature],
  );

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (cancelled) return;
      await loadFeatureLogs(true);
    })();
    return () => {
      cancelled = true;
    };
  }, [loadFeatureLogs]);

  useEffect(() => {
    if (!live) return;
    const id = window.setInterval(() => void loadFeatureLogs(false), LOGS_LIVE_INTERVAL_MS);
    return () => window.clearInterval(id);
  }, [live, loadFeatureLogs]);

  return (
    <Modal title={t("logsTitle", { name: feature })} onClose={onClose}>
      <div className="p-4 space-y-3">
        <div className="flex items-center justify-between gap-2">
          <div className="flex shrink-0 gap-2">
            {autologi ? (
              <span className="inline-flex items-center rounded-md border border-emerald-500/30 bg-emerald-500/10 px-2 py-1 text-xs text-emerald-600">Автообновление</span>
            ) : (
              <>
                <button
                  type="button"
                  className="inline-flex items-center rounded-md border border-border bg-background px-2 py-1 text-xs hover:bg-accent disabled:opacity-50"
                  disabled={loading || live}
                  onClick={() => void loadFeatureLogs(true)}
                >
                  {t("refresh")}
                </button>
                <button
                  type="button"
                  className={`inline-flex items-center rounded-md border border-border px-2 py-1 text-xs hover:bg-accent ${
                    live ? "bg-primary text-primary-foreground" : "bg-background"
                  }`}
                  onClick={() => setLive((value) => !value)}
                >
                  {live ? t("logsLiveOn") : t("logsLive")}
                </button>
              </>
            )}
            <button
              type="button"
              className="inline-flex items-center rounded-md border border-border bg-background px-2 py-1 text-xs hover:bg-accent disabled:opacity-50"
              disabled={loading || lines.length === 0}
              onClick={async () => {
                const text = lines.join("\n");
                try {
                  await navigator.clipboard.writeText(text);
                } catch {
                  const textarea = document.createElement("textarea");
                  textarea.value = text;
                  textarea.style.position = "fixed";
                  textarea.style.opacity = "0";
                  document.body.appendChild(textarea);
                  textarea.select();
                  try {
                    document.execCommand("copy");
                  } finally {
                    document.body.removeChild(textarea);
                  }
                }
              }}
            >
              {t("copy")}
            </button>
          </div>
        </div>
        <LogScrollPre
          ref={logScroll.ref}
          onScroll={logScroll.onScroll}
          className="max-h-[60vh] overflow-y-auto rounded-md border border-border bg-background p-3 text-xs"
        >
          {loading ? `${t("loading")}\n\n…` : lines.join("\n") || t("empty")}
        </LogScrollPre>
      </div>
    </Modal>
  );
}

function FeatureSettingsModal({
  feature,
  onClose,
}: {
  feature: FeatureName;
  onClose: () => void;
}) {
  return <ComponentSettingsModal feature={feature} onClose={onClose} />;
}


const BRIDGE_POOL_UI_KEY = "olc-bridge-pool-ui";

function bridgePoolFinishedMs(job?: Record<string, unknown>): number | null {
  const raw = job?.finished_at;
  if (typeof raw !== "string" || !raw) return null;
  const ms = Date.parse(raw);
  return Number.isFinite(ms) ? ms : null;
}

function bridgePoolUiVisible(job?: Record<string, unknown>): boolean {
  const status = String(job?.status ?? "idle");
  if (status === "running") return true;
  if (status === "done" || status === "error") {
    const doneAt = bridgePoolFinishedMs(job);
    if (doneAt == null) return true;
    return Date.now() - doneAt < JOB_MSG_TTL_MS;
  }
  return false;
}

function BridgesSettingsFields({
  settings,
  setSettings,
  setMsg,
  onReload,
}: {
  settings: Record<string, unknown>;
  setSettings: React.Dispatch<React.SetStateAction<Record<string, unknown>>>;
  setMsg: (s: string) => void;
  onReload: () => Promise<void>;
}) {
  const { t } = usePanelLang();
  const ps = (settings.pool_stats as Record<string, number>) ?? {};
  const prof = (settings.profiles as Record<string, unknown>) ?? {};
  const sys = (prof.system as Record<string, unknown>) ?? {};
  const custom = (prof.profiles as Record<string, unknown>[]) ?? [];
  const activeId = String(prof.active_profile ?? "system");
  const [addMode, setAddMode] = useState<"" | "manual" | "url">("");
  const [newLabel, setNewLabel] = useState("");
  const [newBridges, setNewBridges] = useState("");
  const [newUrls, setNewUrls] = useState("");
  const [poolBusy, setPoolBusy] = useState(false);
  const [poolUiOpen, setPoolUiOpen] = useState(false);
  const [poolHint, setPoolHint] = useState("");
  // --- Sources management ---
  const [sources, setSources] = useState<Record<string, unknown>[]>([]);
  const [sourcesBusy, setSourcesBusy] = useState(false);
  const [addSourceUrl, setAddSourceUrl] = useState("");
  const [addSourceLabel, setAddSourceLabel] = useState("");
  const loadSources = async () => {
    try {
      const res = await fetch("/api/sources/bridges");
      if (!res.ok) return;
      const body = await res.json() as { sources?: Record<string, unknown>[]; error?: string };
      if (body.sources) setSources(body.sources);
    } catch { /* ignore */ }
  };
  const saveSources = async () => {
    setSourcesBusy(true);
    try {
      const res = await fetch("/api/sources/bridges", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sources }),
      });
      const body = await res.json() as { sources?: Record<string, unknown>[]; error?: string };
      if (!res.ok) { setPoolHint(body.error || `HTTP ${res.status}`); }
      else {
        if (body.sources) setSources(body.sources);
        await onReload();
        setPoolHint("Источники обновлены ✓");
      }
    } catch (e) {
      setPoolHint(e instanceof Error ? e.message : "Ошибка источника");
    } finally {
      setSourcesBusy(false);
    }
  };
  const enableSource = (id: string) => {
    setSources((ss) => ss.map((s) => {
      const m = { ...s } as Record<string, unknown>;
      if (String(m.id) === id) m.enabled = !m.enabled;
      return m;
    }));
  };
  const removeSource = (id: string) => {
    setSources((ss) => ss.filter((s) => String(s.id) !== id));
  };
  const addNewSource = () => {
    if (!addSourceUrl.trim()) return;
    const entry: Record<string, unknown> = {
      id: "custom-" + Date.now().toString(36),
      url: addSourceUrl.trim(),
      label: addSourceLabel.trim() || addSourceUrl.trim().slice(0, 60),
      enabled: true,
      editable: true,
    };
    setSources((ss) => [...ss, entry]);
    setAddSourceUrl("");
    setAddSourceLabel("");
  };
  // --- Health check ---
  const health = (settings.health as Record<string, unknown>[]) ?? [];
  const aliveCount = health.filter((h) => Boolean(h.alive)).length;
  const unCheckedCount = health.filter((h) => !h.checked).length;
  const [healthOpen, setHealthOpen] = useState(false);
  const [probeBusy, setProbeBusy] = useState(false);
  const probeNow = async () => {
    setProbeBusy(true);
    setPoolUiOpen(true);
    setPoolHint("Проверка мостов запущена…");
    try {
      const res = await fetch("/api/settings/bridges", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "probe_now" }),
      });
      const body = (await res.json()) as { pool_job?: Record<string, unknown>; error?: string };
      if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
      setSettings((s) => ({ ...s, pool_job: body.pool_job ?? { status: "running" } }));
      const started = Date.now();
      while (Date.now() - started < 480_000) {
        await new Promise((r) => window.setTimeout(r, 1500));
        const res2 = await fetch("/api/settings/bridges", { cache: "no-store" });
        if (!res2.ok) break;
        const raw2 = await res2.text();
        let b2: { settings?: Record<string, unknown> } = {};
        try { b2 = (raw2 ? JSON.parse(raw2) : {}) as { settings?: Record<string, unknown> }; } catch { break; }
        setSettings((s) => ({ ...s, ...(b2.settings ?? {}) }));
        const st = String((b2.settings?.pool_job as Record<string, unknown>)?.status ?? "");
        if (st === "done") { setPoolHint("Проверка завершена"); break; }
        if (st === "error") { setPoolHint("Ошибка проверки"); break; }
        if (st !== "running") break;
      }
    } catch (e) {
      setPoolHint(e instanceof Error ? e.message : String(e));
    } finally {
      setProbeBusy(false);
    }
  };
  const poolJob = (settings.pool_job as Record<string, unknown>) ?? {};
  const jobStatus = String(poolJob.status ?? "idle");
  const logTail = (poolJob.log_tail as string[]) ?? [];
  const wtInstalled = Boolean(poolJob.webtunnel_client ?? settings.webtunnel_client);
  const poolUiActive = poolUiOpen;

  useEffect(() => {
    try {
      const raw = sessionStorage.getItem(BRIDGE_POOL_UI_KEY);
      if (!raw) return;
      const st = JSON.parse(raw) as { open?: boolean; hint?: string; job?: Record<string, unknown> };
      const pj = st.job ?? {};
      const stt = String(pj.status ?? "idle");
      if (st.open || stt === "running" || bridgePoolUiVisible(pj)) {
        setPoolUiOpen(true);
        if (st.hint) setPoolHint(st.hint);
      }
    } catch {
      /* ignore */
    }
  }, []);

  useEffect(() => {
    if (!poolUiOpen && !poolHint && jobStatus === "idle") {
      sessionStorage.removeItem(BRIDGE_POOL_UI_KEY);
      return;
    }
    sessionStorage.setItem(
      BRIDGE_POOL_UI_KEY,
      JSON.stringify({ open: poolUiOpen, hint: poolHint, job: poolJob }),
    );
  }, [poolUiOpen, poolHint, poolJob, jobStatus]);

  useEffect(() => {
    if (jobStatus === "running") setPoolUiOpen(true);
  }, [jobStatus]);

  useEffect(() => {
    if (!bridgePoolUiVisible(poolJob)) return;
    const ms = jobStatus === "running" ? 1500 : 4000;
    const id = window.setInterval(() => void onReload(), ms);
    return () => window.clearInterval(id);
  }, [jobStatus, poolJob, onReload]);

  /* olc-panel-hotfix-v18: pool log stays until user closes */

  const patchProfiles = (next: Record<string, unknown>) => {
    setSettings((s) => ({ ...s, profiles: next }));
  };

  const refreshPool = async (types: string) => {
    setPoolBusy(true);
    setPoolUiOpen(true);
    setPoolHint("Обновление пула запущено…");
    try {
      const res = await fetch("/api/settings/bridges", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "refresh_pool", types }),
      });
      const body = (await res.json()) as { pool_job?: Record<string, unknown>; error?: string };
      if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
      const pj = body.pool_job ?? { status: "running" };
      setSettings((s) => ({ ...s, pool_job: pj }));
      setPoolHint("Обновление пула…");
      await onReload();
      const poolWaitStarted = Date.now();
      while (Date.now() - poolWaitStarted < 600_000) {
        await new Promise((r) => window.setTimeout(r, 1500));
        const res2 = await fetch("/api/settings/bridges", { cache: "no-store" });
        if (!res2.ok) break;
        const raw2 = await res2.text();
        let b2: { settings?: Record<string, unknown> } = {};
        try {
          b2 = (raw2 ? JSON.parse(raw2) : {}) as { settings?: Record<string, unknown> };
        } catch {
          break;
        }
        const pj2 = (b2.settings?.pool_job as Record<string, unknown>) ?? {};
        setSettings((s) => ({ ...s, pool_job: pj2, pool_stats: b2.settings?.pool_stats ?? s.pool_stats }));
        const st = String(pj2.status ?? "");
        if (st === "done") {
          setPoolHint(`Готово ${String(pj2.finished_at ?? "").slice(11, 19)}`);
          break;
        }
        if (st === "error") {
          setPoolHint(String(pj2.error ?? "ошибка обновления"));
          break;
        }
        if (st !== "running") break;
      }
      await onReload();
    } catch (e) {
      setPoolHint(e instanceof Error ? e.message : String(e));
    } finally {
      setPoolBusy(false);
    }
  };

  const addCustomProfile = () => {
    if (!newLabel.trim()) return;
    const id = `p-${Date.now().toString(36)}`;
    const entry: Record<string, unknown> = {
      id,
      label: newLabel.trim(),
      mode: addMode,
      readonly: false,
      auto_update: addMode === "url",
    };
    if (addMode === "manual") {
      entry.bridges = newBridges;
    } else {
      entry.urls = newUrls.split("\n").map((u) => u.trim()).filter(Boolean);
    }
    patchProfiles({ ...prof, profiles: [...custom, entry] });
    setAddMode("");
    setNewLabel("");
    setNewBridges("");
    setNewUrls("");
    setMsg(t("profileAddedSave"));
  };

  const removeProfile = (id: string) => {
    patchProfiles({ ...prof, profiles: custom.filter((x) => x.id !== id) });
    if (activeId === id) {
      patchProfiles({ ...prof, active_profile: "system", profiles: custom.filter((x) => x.id !== id) });
    }
  };

  return (
    <>
      <div className="flex flex-wrap gap-2 text-xs">
        <span className="rounded border border-border bg-muted/50 px-2 py-1">
          webtunnel-client: <strong className={wtInstalled ? "text-emerald-400" : "text-amber-400"}>{wtInstalled ? t("yes") : t("no")}</strong>
        </span>
        <span className="rounded border border-border bg-muted/50 px-2 py-1">
          {t("bridgePoolUpdate")}: <strong className="text-foreground">{jobStatus === "running" ? t("bridgePoolRunning") : jobStatus === "done" ? t("bridgePoolDone") : jobStatus === "error" ? t("bridgePoolError") : t("bridgePoolIdle")}</strong>
        </span>
        {poolBusy && <span className="rounded border border-amber-500/40 bg-amber-500/10 px-2 py-1 text-amber-400">{t("bridgePoolStarting")}</span>}
      </div>

      <p className="text-xs text-muted-foreground">
        Пул: obfs4 {ps.obfs4 ?? 0}, webtunnel {ps.webtunnel ?? 0}, прочие {ps.other ?? 0}, всего {ps.total ?? 0}
        {!wtInstalled && String(sys.types ?? "").includes("webtunnel") && (
          <span className="block text-amber-400">webtunnel-client не установлен — скачивается с mirror-cry при обновлении</span>
        )}
      </p>
      {poolHint && (
        <p className={`text-xs ${jobStatus === "error" ? "text-destructive" : jobStatus === "done" ? "text-emerald-400" : "text-amber-400"}`}>
          {poolHint}
          {jobStatus === "done" && ` · webtunnel-client: ${wtInstalled ? "да" : "нет"}`}
        </p>
      )}
      {poolUiActive && (
        <div className="rounded border border-border bg-background p-2">
          <div className="mb-2 flex items-center justify-between gap-2">
            <span className="text-xs text-muted-foreground">{t("poolLogTitle")}</span>
            <button
              type="button"
              className="text-xs text-muted-foreground hover:text-foreground"
              onClick={() => {
                setPoolUiOpen(false);
                setPoolHint("");
                sessionStorage.removeItem(BRIDGE_POOL_UI_KEY);
              }}
            >
              {t("close")}
            </button>
          </div>
          <LogScrollPre className="max-h-48 overflow-y-auto text-xs leading-relaxed whitespace-pre-wrap">
            {(logTail.length > 0 ? logTail : [jobStatus === "running" ? t("waitingLogLines") : poolHint || ""]).slice(-250).join("\n")}
          </LogScrollPre>
        </div>
      )}
      {/* Profile selector + create */}
      <div className="rounded-lg border border-border bg-muted/10 p-2.5 text-xs space-y-2">
        <div className="mb-1 font-semibold text-foreground">Профили мостов</div>

        {/* System profile */}
        <div className={`rounded border p-2 ${activeId === "system" ? "border-primary bg-primary/5" : "border-border bg-background"}`}>
          <div className="flex items-center justify-between">
            <div>
              <div className="font-medium">
                <span className="inline-block h-2 w-2 rounded-full bg-blue-400 mr-1"></span>
                Оригинальный (системный)
              </div>
              <div className="text-[10px] text-muted-foreground">Из встроенных источников</div>
            </div>
            <input type="radio" name="profile" checked={activeId === "system"} onChange={() => patchProfiles({ ...prof, active_profile: "system" })} />
          </div>
          {/* olc-bridge-system-controls: типы мостов / автообновление / обновить (восстановлено) */}
          <div className="mt-2 space-y-2 border-t border-border pt-2">
            <label className="grid gap-1 text-[11px] text-muted-foreground">
              Типы мостов
              <select
                className="h-8 rounded border border-border bg-background px-2 text-foreground"
                value={String(sys.types ?? "obfs4")}
                onChange={(e) => patchProfiles({ ...prof, system: { ...sys, types: e.target.value } })}
              >
                <option value="obfs4">obfs4</option>
                <option value="webtunnel">webTunnel</option>
                <option value="obfs4,webtunnel">obfs4 + webTunnel</option>
              </select>
            </label>
            <div className="flex items-center justify-between gap-3 text-[11px] text-muted-foreground">
              <span>Автообновление пула (cron, ~каждые 6ч)</span>
              <OlcToggleButton compact checked={Boolean(sys.auto_update)} onChange={(e) => patchProfiles({ ...prof, system: { ...sys, auto_update: e.target.checked } })} />
            </div>
            <button
              type="button"
              className="rounded border border-border px-2 py-1 text-[11px] hover:bg-muted disabled:opacity-60"
              disabled={poolBusy || jobStatus === "running"}
              onClick={() => void refreshPool(String(sys.types ?? "obfs4"))}
            >
              Обновить пул сейчас
            </button>
            <p className="text-[10px] text-muted-foreground">
              Обновляет мосты выбранных типов из встроенных источников. obfs4 — быстрее;
              webtunnel — устойчивее к блокировкам (качается бинарь webtunnel-client).
            </p>
          </div>
        </div>

        {/* Custom profile cards */}
        {custom.map((pr) => {
          const id = String(pr.id);
          const isSelected = activeId === id;
          const label = String(pr.label ?? id);
          const mode = String(pr.mode ?? "?");
          const bridgeCount = String((pr.bridges as string) ?? "").split("\n").filter((l: string) => l.trim().startsWith("Bridge")).length;
          return (
            <div key={id} className={`rounded border p-2 ${isSelected ? "border-primary bg-primary/5" : "border-border bg-background"}`}>
              <div className="flex items-center justify-between">
                <div>
                  <div className="font-medium">
                    <span className={`inline-block h-2 w-2 rounded-full mr-1 ${mode === "manual" ? "bg-green-400" : "bg-amber-400"}`}></span>
                    {label}
                  </div>
                  <div className="text-[10px] text-muted-foreground">
                    {bridgeCount > 0 ? bridgeCount + " мост" : "через URL"} · {mode === "manual" ? "ручные" : "источники"}
                  </div>
                </div>
                <div className="flex items-center gap-1">
                  <input type="radio" name="profile" checked={isSelected} onChange={() => patchProfiles({ ...prof, active_profile: id })} />
                  <button type="button" className="text-destructive text-[10px] hover:underline" onClick={() => removeProfile(id)}>✕</button>
                </div>
              </div>
            </div>
          );
        })}

        {/* Create new profile (always visible) */}
        <div className="rounded border border-border bg-background p-2">
          <div className="mb-1 font-medium text-primary">Создать профиль</div>
          <input
            className="h-7 w-full rounded border border-border bg-background px-2 text-xs mb-1"
            placeholder="Название"
            value={newLabel}
            onChange={(e) => setNewLabel(e.target.value)}
          />
          <div className="flex gap-1 mb-1">
            <button type="button" className={`rounded border px-2 py-1 text-[10px] ${addMode === "" || addMode === "manual" ? "border-primary text-primary" : "border-border hover:bg-muted"}`} onClick={() => setAddMode("manual")}>Ручной (Bridge ...)</button>
            <button type="button" className={`rounded border px-2 py-1 text-[10px] ${addMode === "url" ? "border-primary text-primary" : "border-border hover:bg-muted"}`} onClick={() => setAddMode("url")}>URL (ссылка)</button>
          </div>
          {addMode === "manual" && (
            <textarea
              className="min-h-[60px] w-full rounded border border-border bg-background p-2 font-mono text-xs mb-1"
              placeholder="Bridge obfs4 ...&#10;Bridge webtunnel ..."
              value={newBridges}
              onChange={(e) => setNewBridges(e.target.value)}
            />
          )}
          {addMode === "url" && (
            <textarea
              className="min-h-[50px] w-full rounded border border-border bg-background p-2 font-mono text-xs mb-1"
              placeholder="https://.../bridges.txt (по строке)"
              value={newUrls}
              onChange={(e) => setNewUrls(e.target.value)}
            />
          )}
          <button type="button" className="rounded border border-primary px-2 py-1 text-xs text-primary hover:bg-primary/10" onClick={addCustomProfile}>Создать</button>
        </div>
      </div>
      <label className="grid gap-1 text-muted-foreground">
        Добавить одну строку в /etc/tor/bridges.conf
        <input
          className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs"
          placeholder="Bridge webtunnel ..."
          value={String(settings.custom_bridge ?? "")}
          onChange={(e) => setSettings((s) => ({ ...s, custom_bridge: e.target.value }))}
        />
      </label>
      <LogScrollPre className="max-h-[160px] overflow-y-auto rounded border border-border bg-background p-2 text-xs">
        {String(settings.bridges_conf ?? "").slice(-3000) || t("empty")}
      </LogScrollPre>
      {/* --- Health Check --- */}
      <div className="rounded-lg border border-border bg-muted/10 p-2.5 text-xs">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <span>
            Здоровье мостов:{" "}
            <strong className="text-emerald-400">{aliveCount} живых</strong>
            {" · "}
            <strong className={unCheckedCount > 0 ? "text-muted-foreground" : "text-destructive"}>
              {unCheckedCount > 0 ? unCheckedCount + " не проверен" : (health.length - aliveCount) + " мёртвых"}
            </strong>
          </span>
          <div className="flex items-center gap-2">
            {health.length > 0 && (
              <button type="button" className="text-muted-foreground hover:text-foreground" onClick={() => setHealthOpen((v) => !v)}>
                {healthOpen ? "Скрыть" : "Показать список"}
              </button>
            )}
            <button
              type="button"
              className="rounded border border-border px-2 py-1 hover:bg-muted disabled:opacity-50"
              disabled={probeBusy || jobStatus === "running"}
              onClick={() => void probeNow()}
            >
              {probeBusy ? "Проверяю…" : "Проверить сейчас"}
            </button>
          </div>
        </div>
        {healthOpen && health.length > 0 && (
          <div className="mt-2 max-h-56 space-y-1 overflow-y-auto">
            {health.map((h, i) => {
              const alive = Boolean(h.alive);
              const checked = Boolean(h.checked);
              const ts = Number(h.checked_at ?? 0);
              const when = ts > 0 ? new Date(ts * 1000).toLocaleString() : "—";
              return (
                <div key={i} className="flex items-center gap-2 rounded bg-background/60 px-2 py-1 font-mono">
                  <span
                    className={`inline-block h-2 w-2 shrink-0 rounded-full ${!checked ? "bg-muted-foreground" : alive ? "bg-emerald-400" : "bg-destructive"}`}
                    title={!checked ? "не проверялся" : alive ? "жив" : "мёртв"}
                  />
                  <span className="w-20 shrink-0 text-muted-foreground">{String(h.type ?? "?")}</span>
                  <span className="flex-1 truncate">{String(h.addr ?? "")}</span>
                  <span className="shrink-0 text-[10px] text-muted-foreground" title={String(h.last_status ?? "")}>{checked ? when : "не проверен"}</span>
                </div>
              );
            })}
          </div>
        )}
      </div>
      {/* --- Sources Management --- */}
      <section className="rounded-lg border border-border bg-muted/10 p-2.5 text-xs">
        <div className="mb-2 flex items-center justify-between">
          <h3 className="font-semibold text-foreground">Источники мостов</h3>
          <div className="flex items-center gap-1.5">
            <span className="text-[10px] text-muted-foreground">{sources.filter((s) => (s as Record<string, unknown>).enabled).length}/{sources.length} активно</span>
            <button
              type="button"
              className="rounded border border-border px-2 py-1 hover:bg-muted disabled:opacity-50"
              disabled={sourcesBusy}
              onClick={() => void saveSources()}
            >
              {sourcesBusy ? "…" : "Применить"}
            </button>
          </div>
        </div>
        <div className="space-y-1">
          {sources.map((s) => {
            const id = String(s.id ?? "");
            const enabled = Boolean((s as Record<string, unknown>).enabled);
            const label = String((s as Record<string, unknown>).label ?? id);
            const url = String((s as Record<string, unknown>).url ?? "");
            const editable = Boolean((s as Record<string, unknown>).editable);
            return (
              <div key={id} className="flex items-start gap-2 rounded bg-background/60 px-2 py-1.5">
                <OlcToggleButton

                  className="mt-0.5 rounded border-border"
                  checked={enabled}
                  onChange={() => void enableSource(id)}
                />
                <div className="flex-1 min-w-0">
                  <div className="font-medium text-foreground">{label}</div>
                  <div className="font-mono text-[10px] text-muted-foreground truncate" title={url}>{url}</div>
                </div>
                {editable && (
                  <button
                    type="button"
                    className="text-destructive text-[10px] hover:underline shrink-0"
                    onClick={() => void removeSource(id)}
                  >
                    ✕
                  </button>
                )}
              </div>
            );
          })}
        </div>
        <div className="mt-2 rounded border border-dashed border-border bg-background/50 p-2">
          <div className="mb-1 text-[10px] font-medium text-muted-foreground">Добавить источник</div>
          <div className="grid gap-1.5">
            <input
              className="h-7 rounded border border-border bg-background px-2 text-[10px]"
              placeholder="Название"
              value={addSourceLabel}
              onChange={(e) => setAddSourceLabel(e.target.value)}
            />
            <input
              className="h-7 rounded border border-border bg-background px-2 font-mono text-[10px]"
              placeholder="https://example.com/bridges.txt"
              value={addSourceUrl}
              onChange={(e) => setAddSourceUrl(e.target.value)}
            />
            <button
              type="button"
              className="rounded border border-primary px-2 py-1 text-[10px] text-primary hover:bg-primary/10"
              onClick={() => void addNewSource()}
            >
              Добавить
            </button>
          </div>
        </div>
      </section>
    </>
  );
}

function SettingsSection({ title, hint, children }: { title: string; hint?: string; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-border bg-muted/10 p-3">
      <div className="mb-2">
        <h3 className="text-sm font-semibold text-foreground">{title}</h3>
        {hint && <p className="mt-0.5 text-[11px] leading-snug text-muted-foreground">{hint}</p>}
      </div>
      <div className="space-y-3">{children}</div>
    </section>
  );
}

function SettingField({
  label,
  caption,
  value,
  onChange,
  placeholder,
  mono = true,
}: {
  label: string;
  caption?: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  mono?: boolean;
}) {
  return (
    <label className="grid gap-1">
      <span className="text-xs font-medium text-foreground">{label}</span>
      {caption && <span className="text-[11px] leading-snug text-muted-foreground">{caption}</span>}
      <input
        className={`h-9 rounded-md border border-border bg-background px-2 text-xs ${mono ? "font-mono" : ""}`}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
      />
    </label>
  );
}

function AddonSettingsIntro({ feature }: { feature: FeatureName }) {
  const hint = FEATURE_SETTINGS_HINTS[feature];
  if (!hint || !hint.lines?.length) return null;
  return (
    <div className="rounded-lg border border-primary/30 bg-primary/5 p-3">
      <p className="text-xs font-semibold text-foreground">{hint.title}</p>
      <ul className="mt-1 list-disc space-y-0.5 pl-4 text-[11px] leading-snug text-muted-foreground">
        {hint.lines.map((line, i) => (
          <li key={i}>{line}</li>
        ))}
      </ul>
    </div>
  );
}

// ============================================================================
// Olc-cost-l: секция «Бекап данных» в общих настройках.
// Экспорт/импорт ВСЕХ данных панели (серверы, инстансы, клиенты, настройки) в
// один JSON. Данные хранятся ТОЛЬКО на устройстве пользователя. Импорт устойчив
// к смене версий панели (бэкенд делает schema-независимый deep-merge).
//
// !!! ПРИ ИЗМЕНЕНИИ UI/НАСТРОЕК: новые данные, которые должны переживать
// переустановку, должны попадать в бэкап на бэкенде (config.json или
// backupExtraFiles() в patch-olcrtc-manager-backup-api.sh). См. docs/BACKUP.md.
// ============================================================================
function BackupSection() {
  const [busy, setBusy] = useState(false);
  const [restartBusy, setRestartBusy] = useState(false);
  const [restartReady, setRestartReady] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement | null>(null);

  const doExport = async () => {
    setBusy(true); setErr(null); setMsg(null);
    try {
      const res = await fetch("/api/backup/export", { cache: "no-store" });
      if (!res.ok) throw new Error("HTTP " + res.status);
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      const stamp = new Date().toISOString().replace(/[:T]/g, "-").slice(0, 19);
      a.download = "olc-backup-" + stamp + ".json";
      document.body.appendChild(a); a.click(); a.remove();
      URL.revokeObjectURL(url);
      setMsg("Бекап скачан. Храните файл в надёжном месте — в нём все ваши данные.");
    } catch (e: any) {
      setErr("Не удалось экспортировать: " + (e?.message || String(e)));
    } finally { setBusy(false); }
  };

  const doImport = async (file: File) => {
    setBusy(true); setErr(null); setMsg(null);
    try {
      const text = await file.text();
      const result = await importBackupWithDecisions(
        "/api/backup/import",
        text,
        "ВНИМАНИЕ: этот бэкап создан на другом VPS или в старой версии панели.\n\n" +
          "Он содержит активные room+key. Если исходный сервер всё ещё работает, после запуска второго сервера клиенты могут случайно подключаться то к одному, то к другому.\n\n" +
          "Продолжайте только если старый сервер остановлен либо вы осознанно переносите панель. Импортировать всё равно?"
      );
      if (result.cancelled) {
        setMsg("Импорт отменён: данные на диске не изменены.");
        return;
      }
      const restored = result.data?.restored || [];
      const installed = result.installed.length ? ` Доустановлены модули: ${result.installed.join(", ")}.` : "";
      setRestartReady(true);
      setMsg("Восстановлено: " + (restored.join(", ") || "нет данных") + "." + installed + " " + (result.data?.note || ""));
    } catch (e: any) {
      setErr("Не удалось импортировать: " + (e?.message || String(e)));
    } finally {
      setBusy(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  };

  const doRestart = async () => {
    setRestartBusy(true); setErr(null);
    try {
      const res = await fetch("/api/backup/restart", { method: "POST" });
      const data = await res.json().catch(() => ({} as any));
      if (!res.ok) throw new Error(data?.error || ("HTTP " + res.status));
      setMsg("Панель перезапускается. Ожидаю её возвращения…");
      await new Promise((resolve) => window.setTimeout(resolve, 2500));
      let online = false;
      for (let i = 0; i < 35; i += 1) {
        try {
          const probe = await fetch("/api/state", { cache: "no-store" });
          if (probe.ok) { online = true; break; }
        } catch (_) {}
        await new Promise((resolve) => window.setTimeout(resolve, 1000));
      }
      if (!online) throw new Error("панель не ответила в течение 35 секунд");
      setRestartReady(false);
      setMsg("Панель перезапущена, восстановленные данные применены. Обновляю страницу…");
      window.setTimeout(() => window.location.reload(), 700);
    } catch (e: any) {
      setErr("Не удалось подтвердить перезапуск: " + (e?.message || String(e)));
    } finally {
      setRestartBusy(false);
    }
  };

  return (
    <section className="grid gap-3 rounded-md border border-border bg-background p-4">
      <div className="text-sm font-medium text-foreground">Бекап данных</div>
      <div className="text-xs text-muted-foreground">
        Экспортируйте все свои данные (серверы, инстансы, клиенты, все настройки) в один
        файл и восстановите их после переустановки или на новом VPS. Импорт устойчив к
        обновлению панели. Эта информация хранится ИСКЛЮЧИТЕЛЬНО на ваших устройствах, где
        находится панель — сервер её никуда не отправляет.
      </div>
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
          disabled={busy}
          onClick={doExport}
        >
          Экспортировать (скачать JSON)
        </button>
        <button
          type="button"
          className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
          disabled={busy}
          onClick={() => fileRef.current?.click()}
        >
          Импортировать (выбрать JSON)
        </button>
        <input
          ref={fileRef}
          type="file"
          accept="application/json,.json"
          className="hidden"
          onChange={(e) => { const file = e.target.files && e.target.files[0]; if (file) doImport(file); }}
        />
        {restartReady && (
          <button
            type="button"
            className="inline-flex h-9 items-center gap-2 rounded-md bg-amber-600 px-3 text-sm text-white hover:bg-amber-500 disabled:opacity-60"
            disabled={busy || restartBusy}
            onClick={doRestart}
          >
            {restartBusy ? "Перезапуск…" : "Перезапустить панель"}
          </button>
        )}
      </div>
      {msg && <div className="text-xs text-green-500 whitespace-pre-wrap">{msg}</div>}
      {err && <div className="text-xs text-red-500 whitespace-pre-wrap">{err}</div>}
      <div className="text-[11px] text-muted-foreground">
        После импорта появится кнопка перезапуска. На другом VPS импорт потребует отдельного подтверждения, чтобы случайно не запустить сервер-двойник с теми же room+key.
      </div>
    </section>
  );
}

// ============================================================================
// Olc-cost-l: секция «Контроль доступа» — настоящий allowlist по hwid устройства.
// olcbox при запросе подписки шлёт заголовок x-hwid (стабильный per-install id).
// Разрешённое устройство получает подписку (и может брать её по ОРИГИНАЛЬНОМУ
// client-id даже при включённой рандомизации); чужое — блокируется (enforce) и
// попадает в журнал. Надёжнее «рандомизации пути». См. docs/ACCESS-CONTROL.md.
// !!! ПРИ ИЗМЕНЕНИИ формата access-control — учтите бэкап (backupExtraFiles) и API.
// ============================================================================
const olcClearDeviceHistory = (hwid: string) => {
  const q = encodeURIComponent((hwid || "").trim()); if (!q) return;
  void Promise.all([
    fetch(`/api/access/attempts/clear?hwid=${q}`, { method: "POST" }),
    fetch(`/api/access/connections?clear=1&hwid=${q}`),
  ]);
};

function AccessControlSection() {
  const [enabled, setEnabled] = useState(false);
  const [mode, setMode] = useState<"monitor" | "enforce" | "keyrand">("monitor");
  const [devices, setDevices] = useState<Array<{ hwid: string; label?: string; enabled: boolean }>>([]);
  const [ban, setBan] = useState<Array<{ hwid: string; label?: string; enabled: boolean }>>([]);
  const [banNoHwid, setBanNoHwid] = useState(false);
  const [enforceConns, setEnforceConns] = useState(false);
  const [connDevices, setConnDevices] = useState<Array<{ hwid: string; label?: string; enabled: boolean }>>([]);
  const [connBan, setConnBan] = useState<Array<{ hwid: string; label?: string; enabled: boolean }>>([]);
  const [newConnDev, setNewConnDev] = useState("");
  const [newConnBan, setNewConnBan] = useState("");
  const [newBanHwid, setNewBanHwid] = useState("");
  const [connScope, setConnScope] = useState<"all" | "selective">("all");
  const [connInstances, setConnInstances] = useState<string[]>([]);
  const [allInstances, setAllInstances] = useState<Array<{ client_id: string; room_id: string; name: string }>>([]);
  const [hiddenCross, setHiddenCross] = useState<string[]>(() => { try { return JSON.parse(localStorage.getItem("olc-cross-hidden-g-v1") || "[]"); } catch { return []; } });
  const hideCross = (k: string) => { const nx = Array.from(new Set([...hiddenCross, k])); setHiddenCross(nx); try { localStorage.setItem("olc-cross-hidden-g-v1", JSON.stringify(nx)); } catch { /* ignore */ } };
  const unhideCross = (k: string) => { const nx = hiddenCross.filter((x) => x !== k); setHiddenCross(nx); try { localStorage.setItem("olc-cross-hidden-g-v1", JSON.stringify(nx)); } catch { /* ignore */ } };
  const [allowedIps, setAllowedIps] = useState<Array<{ ip: string; enabled: boolean }>>([]);
  const normIps = (v: any) => (Array.isArray(v) ? v : []).map((x: any) => (typeof x === "string" ? { ip: x, enabled: true } : { ip: String(x?.ip || ""), enabled: x?.enabled !== false })).filter((x: any) => x.ip);
  const [newIp, setNewIp] = useState("");
  const [banIps, setBanIps] = useState<Array<{ ip: string; enabled: boolean }>>([]);
  const [newBanIp, setNewBanIp] = useState("");
  // Мини-модалка подтверждения (конфликт бан↔разрешено).
  const [confirmA, setConfirmA] = useState<null | { text: string; ok: string; cancel: string; okCls: "red" | "emerald"; run: () => void }>(null);
  const [attempts, setAttempts] = useState<Array<Record<string, any>>>([]);
  const [connections, setConnections] = useState<Array<Record<string, any>>>([]);
  const [autolog, setAutolog] = useState(true);
  const [newHwid, setNewHwid] = useState("");
  const [busyRaw, setBusy] = useState(false);
  const busy = busyRaw && readStoredBool("olc-ctrl-lock-v1", true);
  const saveQueueRef = useRef<Promise<void>>(Promise.resolve());
  const saveVersionRef = useRef(0);
  const pendingSavesRef = useRef(0);
  const [msg, setMsg] = useState<string | null>(null);
  const listRef = useRef<HTMLDivElement | null>(null);
  const followRef = useRef(true);
  const resumeRef = useRef<number | null>(null);
  const connListRef = useRef<HTMLDivElement | null>(null);
  const connFollowRef = useRef(true);
  const connResumeRef = useRef<number | null>(null);
  const [connClearedAt, setConnClearedAt] = useState<string>(() => { try { return localStorage.getItem("olc-conn-cleared-global") || ""; } catch { return ""; } });
  const [randOn, setRandOn] = useState(false);
  const [randType, setRandType] = useState(1);
  const [randScope, setRandScope] = useState("both");
  const [connKeyrand, setConnKeyrand] = useState(false);

  const loadSettings = async () => {
    try {
      const s = await fetch("/api/access/settings", { cache: "no-store" });
      const sb = await s.json();
      setEnabled(!!sb.enabled);
      setMode(sb.mode === "enforce" ? "enforce" : sb.mode === "keyrand" ? "keyrand" : "monitor");
      setDevices(Array.isArray(sb.devices) ? sb.devices : []);
      setBan(Array.isArray(sb.ban) ? sb.ban : []);
      setBanNoHwid(!!sb.ban_no_hwid);
      setEnforceConns(!!sb.enforce_connections); setConnKeyrand(sb.conn_mode === "keyrand");
      setConnDevices(Array.isArray(sb.conn_devices) ? sb.conn_devices : []);
      setConnBan(Array.isArray(sb.conn_ban) ? sb.conn_ban : []);
      setAllowedIps(normIps(sb.allowed_ips));
      setBanIps(normIps(sb.ban_ips));
      setConnScope(sb.conn_scope === "selective" ? "selective" : "all");
      setConnInstances(Array.isArray(sb.conn_instances) ? sb.conn_instances : []);
    } catch { /* ignore */ }
    try {
      // Инстансы ВСЕХ клиентов — для глобального выбора «Только выбранные».
      const st = await fetch("/api/state", { cache: "no-store" });
      const stb = await st.json();
      const out: Array<{ client_id: string; room_id: string; name: string }> = [];
      for (const c of (stb.clients || [])) for (const l of (c.locations || [])) out.push({ client_id: String(c.client_id || ""), room_id: String(l.room_id || ""), name: String(l.name || l.room_id || "") });
      setAllInstances(out);
    } catch { /* ignore */ }
    try {
      const l = await fetch("/api/settings/logs", { cache: "no-store" });
      const lb = await l.json();
      setAutolog(lb.auto_refresh !== false);
    } catch { setAutolog(true); }
  };
  const loadAttempts = async () => {
    try {
      const a = await fetch("/api/access/attempts", { cache: "no-store" });
      const ab = await a.json();
      setAttempts(Array.isArray(ab.attempts) ? ab.attempts : []);
    } catch { /* ignore */ }
    try {
      const c = await fetch("/api/access/connections", { cache: "no-store" });
      const cb = await c.json();
      setConnections(Array.isArray(cb.connections) ? cb.connections : []);
    } catch { /* ignore */ }
  };
  const loadRand = async () => {
    try {
      const r = await fetch("/api/settings/randomization/global", { cache: "no-store" });
      const b = await r.json();
      let on = !!b.enabled; let ty = b.rand_type === 2 ? 2 : 1;
      if (!on) {
        try {
          const cr = await fetch("/api/clients/", { cache: "no-store" });
          const cb = await cr.json();
          const cls = Array.isArray(cb.clients) ? cb.clients : [];
          if (cls.some((c: any) => c.randomization?.enabled)) { on = true; ty = cls.some((c: any) => c.randomization?.enabled && c.randomization?.rand_type === 2) ? 2 : 1; }
        } catch { /* ignore */ }
      }
      setRandOn(on); setRandType(ty); setRandScope((b.rand_scope === "client_id" || b.rand_scope === "crypto") ? b.rand_scope : "both");
    } catch { /* ignore */ }
  };
  const loadAll = async () => { await loadSettings(); await loadAttempts(); await loadRand(); };

  useEffect(() => { void loadAll(); }, []);
  useEffect(() => {
    // Scope transitions may atomically reset global access modes as well as
    // randomization. Reload both snapshots so a stale global '+' cannot appear
    // again when the scope later returns to "both".
    const refreshRand = () => { void loadSettings(); void loadRand(); };
    window.addEventListener("olc-randomization-saved", refreshRand);
    const id = window.setInterval(refreshRand, 1500);
    return () => { window.removeEventListener("olc-randomization-saved", refreshRand); window.clearInterval(id); };
  }, []);
  // Автообновление журнала при включённых автологах.
  useEffect(() => {
    if (!autolog) return;
    const id = window.setInterval(() => { void loadAttempts(); }, 2000);
    return () => window.clearInterval(id);
  }, [autolog]);
  // follow-newest: после обновления списка прокрутить вниз, если follow активен.
  useEffect(() => {
    if (followRef.current && listRef.current) {
      listRef.current.scrollTop = listRef.current.scrollHeight;
    }
  }, [attempts]);
  useEffect(() => {
    if (connFollowRef.current && connListRef.current) {
      connListRef.current.scrollTop = connListRef.current.scrollHeight;
    }
  }, [connections]);

  const onScroll = () => {
    const el = listRef.current;
    if (!el) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 24;
    if (nearBottom) {
      if (resumeRef.current) window.clearTimeout(resumeRef.current);
      resumeRef.current = window.setTimeout(() => { followRef.current = true; }, 1500);
    } else {
      followRef.current = false;
      if (resumeRef.current) { window.clearTimeout(resumeRef.current); resumeRef.current = null; }
    }
  };
  const onConnScroll = () => {
    const el = connListRef.current;
    if (!el) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 24;
    if (nearBottom) {
      if (connResumeRef.current) window.clearTimeout(connResumeRef.current);
      connResumeRef.current = window.setTimeout(() => { connFollowRef.current = true; }, 1500);
    } else {
      connFollowRef.current = false;
      if (connResumeRef.current) { window.clearTimeout(connResumeRef.current); connResumeRef.current = null; }
    }
  };
  const clearConnections = async () => {
    setBusy(true);
    try { await fetch("/api/access/connections?clear=1", { cache: "no-store" }); } catch { /* ignore */ }
    const ts = new Date().toISOString(); setConnClearedAt(ts); try { localStorage.setItem("olc-conn-cleared-global", ts); } catch { /* ignore */ }
    await loadAttempts(); setBusy(false);
  };

  const saveSettings = (next: { enabled?: boolean; mode?: string; devices?: any[]; ban?: any[]; ban_no_hwid?: boolean; enforce_connections?: boolean; conn_mode?: string; conn_devices?: any[]; conn_ban?: any[]; allowed_ips?: any[]; ban_ips?: any[]; conn_scope?: string; conn_instances?: string[] }) => {
    const version = ++saveVersionRef.current;
    pendingSavesRef.current += 1; setBusy(true); setMsg(null);
    const run = async () => {
      try {
        const res = await fetch("/api/access/settings", { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...next }) });
        const b = await res.json(); if (!res.ok) throw new Error(b.error || ("HTTP " + res.status));
        if (version === saveVersionRef.current) {
          setEnabled(!!b.enabled); setMode(b.mode === "enforce" ? "enforce" : b.mode === "keyrand" ? "keyrand" : "monitor");
          setDevices(Array.isArray(b.devices) ? b.devices : []); setBan(Array.isArray(b.ban) ? b.ban : []);
          setBanNoHwid(!!b.ban_no_hwid); setEnforceConns(!!b.enforce_connections); setConnKeyrand(b.conn_mode === "keyrand");
          setConnDevices(Array.isArray(b.conn_devices) ? b.conn_devices : []); setConnBan(Array.isArray(b.conn_ban) ? b.conn_ban : []);
          setConnScope(b.conn_scope === "selective" ? "selective" : "all"); setConnInstances(Array.isArray(b.conn_instances) ? b.conn_instances : []);
          setAllowedIps(normIps(b.allowed_ips)); setBanIps(normIps(b.ban_ips));
        }
        try { window.dispatchEvent(new CustomEvent("olc-access-saved", { detail: { enabled: !!b.enabled } })); } catch { /* ignore */ }
      } catch (e: any) { if (version === saveVersionRef.current) setMsg("Ошибка: " + (e?.message || String(e))); }
      finally { pendingSavesRef.current -= 1; if (pendingSavesRef.current === 0) setBusy(false); }
    };
    saveQueueRef.current = saveQueueRef.current.then(run, run); return saveQueueRef.current;
  };
  // ── Конфликт бан↔разрешено: НИКОГДА не держать hwid/IP в обоих списках.
  // Добавление при наличии в противоположном списке → мини-модалка; подтверждение
  // = атомарный перенос (один saveSettings).
  const inL = (list: Array<{ hwid: string }>, h: string) => (list || []).some((d) => (d.hwid || "").toLowerCase() === (h || "").toLowerCase());
  const dropH = (list: Array<any>, h: string) => (list || []).filter((d) => (d.hwid || "").toLowerCase() !== (h || "").toLowerCase());
  const namedGlobalDevice = (h: string) => { const d = [...devices, ...ban, ...connDevices, ...connBan].find((x) => (x.hwid || "").toLowerCase() === h.toLowerCase()); return { hwid: h, ...(d?.label?.trim() ? { label: d.label.trim() } : {}), enabled: true }; };
  const saveGlobalLabel = (h: string, label: string) => { const patch = (xs: any[]) => xs.map((x) => (x.hwid || "").toLowerCase() === h.toLowerCase() ? { ...x, label } : x); const nd=patch(devices), nb=patch(ban), nc=patch(connDevices), ncb=patch(connBan); setDevices(nd); setBan(nb); setConnDevices(nc); setConnBan(ncb); void saveSettings({ devices: nd, ban: nb, conn_devices: nc, conn_ban: ncb }); };
  const ipIn = (list: any[], ip: string) => (list || []).some((x: any) => x.ip === ip);
  const dropIp = (list: any[], ip: string) => (list || []).filter((x: any) => x.ip !== ip);
  const toggleGInstance = (room: string, on: boolean) => { const nx = on ? [...connInstances, room] : connInstances.filter((r) => r !== room); setConnInstances(nx); void saveSettings({ conn_instances: nx }); };
  const toggleGClientInstances = (rooms: string[], on: boolean) => { const set = new Set(connInstances); if (on) rooms.forEach((r) => set.add(r)); else rooms.forEach((r) => set.delete(r)); const nx = Array.from(set); setConnInstances(nx); void saveSettings({ conn_instances: nx }); };
  const setConnDevice = (hwid: string, patch: { enabled?: boolean; label?: string }) => { const nx = connDevices.map((d) => d.hwid === hwid ? { ...d, ...patch } : d); setConnDevices(nx); void saveSettings({ conn_devices: nx }); };
  const addConnDevice = (hwid: string) => {
    const h = (hwid || "").trim(); if (!h) return;
    const existing = connDevices.find((d) => (d.hwid || "").toLowerCase() === h.toLowerCase());
    if (existing) { if (existing.enabled === false) void saveSettings({ conn_devices: connDevices.map((d) => d === existing ? { ...d, enabled: true } : d) }); return; }
    if (inL(connBan, h)) {
      setConfirmA({ text: `Устройство ${h} забанено для ПОДКЛЮЧЕНИЯ. Разбанить его и добавить в разрешённые?`, ok: "Разбанить", cancel: "Нет", okCls: "emerald", run: () => { olcClearDeviceHistory(h); void saveSettings({ conn_ban: dropH(connBan, h), conn_devices: [...connDevices, namedGlobalDevice(h)] }); } });
      return;
    }
    olcClearDeviceHistory(h); void saveSettings({ conn_devices: [...connDevices, namedGlobalDevice(h)] });
  };
  const rmConnDevice = (hwid: string) => { const nx = connDevices.filter((d) => d.hwid !== hwid); setConnDevices(nx); void saveSettings({ conn_devices: nx }); };
  const addConnBan = (hwid: string) => {
    const h = (hwid || "").trim(); if (!h || inL(connBan, h)) return;
    if (inL(connDevices, h)) {
      setConfirmA({ text: `Устройство ${h} в списке разрешённых для ПОДКЛЮЧЕНИЯ. Оно будет удалено из разрешённых и забанено.`, ok: "Бан", cancel: "Отмена", okCls: "red", run: () => void saveSettings({ conn_devices: dropH(connDevices, h), conn_ban: [...connBan, namedGlobalDevice(h)] }) });
      return;
    }
    void saveSettings({ conn_ban: [...connBan, namedGlobalDevice(h)] });
  };
  const rmConnBan = (hwid: string) => { const nx = connBan.filter((d) => d.hwid !== hwid); setConnBan(nx); void saveSettings({ conn_ban: nx }); };
  const toggleConnBan = (hwid: string, en: boolean) => { const nx = connBan.map((d) => d.hwid === hwid ? { ...d, enabled: en } : d); setConnBan(nx); void saveSettings({ conn_ban: nx }); };
  const crossBtn = (hwid: string, kind: "allow" | "ban", target: "sub" | "conn", present: boolean, add: () => void) => {
    const key = `${hwid}|${kind}|${target}`;
    if (present) return null;
    if (hiddenCross.includes(key)) {
      return <button type="button" className="shrink-0 rounded border border-border px-1 py-1 text-[10px] text-muted-foreground hover:bg-muted" title="Показать кнопку добавления в противоположный список" onClick={() => unhideCross(key)}>⋯</button>;
    }
    const title = kind === "allow"
      ? (target === "sub" ? "Добавить в разрешённые устройства для получения подписки" : "Добавить в разрешённые устройства для подключения к инстансам")
      : (target === "sub" ? "Добавить в забаненные устройства для получения подписки" : "Добавить в забаненные устройства для подключения к инстансам");
    const label = (kind === "allow" ? "✅→" : "🚫→") + (target === "sub" ? "подписка" : "подключение");
    const cls = kind === "allow" ? "border-emerald-500/50 text-emerald-400 hover:bg-emerald-500/10" : "border-orange-500/50 text-orange-400 hover:bg-orange-500/10";
    return (
      <span className="inline-flex shrink-0 items-center">
        <button type="button" className={`rounded-l border px-1.5 py-1 text-[10px] ${cls}`} disabled={busy} title={title} onClick={add}>{label}</button>
        <button type="button" className="rounded-r border border-l-0 border-border px-1 py-1 text-[10px] text-muted-foreground hover:bg-muted" title="Скрыть эту кнопку (можно вернуть)" onClick={() => hideCross(key)}>×</button>
      </span>
    );
  };
  const banDevice = (hwid: string) => {
    const h = (hwid || "").trim(); if (!h || inL(ban, h)) return;
    if (inL(devices, h)) {
      setConfirmA({ text: `Устройство ${h} в списке разрешённых (подписка). Оно будет удалено из разрешённых и забанено.`, ok: "Бан", cancel: "Отмена", okCls: "red", run: () => void saveSettings({ devices: dropH(devices, h), ban: [...ban, namedGlobalDevice(h)] }) });
      return;
    }
    void saveSettings({ ban: [...ban, namedGlobalDevice(h)] });
  };
  const removeBan = (hwid: string) => { const nx = ban.filter((d) => d.hwid !== hwid); setBan(nx); void saveSettings({ ban: nx }); };
  const toggleBan = (hwid: string, en: boolean) => { const nx = ban.map((d) => d.hwid === hwid ? { ...d, enabled: en } : d); setBan(nx); void saveSettings({ ban: nx }); };
  const allow = async (hwid: string) => {
    const h = (hwid || "").trim(); if (!h) return;
    const existing = devices.find((d) => (d.hwid || "").toLowerCase() === h.toLowerCase());
    if (existing) { if (existing.enabled === false) await saveSettings({ devices: devices.map((d) => d === existing ? { ...d, enabled: true } : d) }); return; }
    if (inL(ban, h)) {
      setConfirmA({ text: `Устройство ${h} забанено (подписка). Разбанить его и добавить в разрешённые?`, ok: "Разбанить", cancel: "Нет", okCls: "emerald", run: () => { setNewHwid(""); olcClearDeviceHistory(h); void saveSettings({ ban: dropH(ban, h), devices: [...devices, namedGlobalDevice(h)] }); } });
      return;
    }
    setNewHwid("");
    olcClearDeviceHistory(h); await saveSettings({ devices: [...devices, namedGlobalDevice(h)] });
  };
  const remove = (hwid: string) => { const nx = devices.filter((d) => d.hwid !== hwid); setDevices(nx); void saveSettings({ devices: nx }); };
  const clearAttempts = async () => {
    setBusy(true); setMsg(null);
    try {
      await fetch("/api/access/attempts/clear", { method: "POST" });
      followRef.current = true;
      await loadAttempts();
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };
  const setDevice = (hwid: string, patch: { label?: string; enabled?: boolean }) => { const nx = devices.map((d) => d.hwid === hwid ? { ...d, ...patch } : d); setDevices(nx); void saveSettings({ devices: nx }); };
  // IP-allowlist: backend уже энфорсит allowed_ips (olcAccessAllowed), UI лишь
  // управляет списком через те же /api/access/{allow,remove} с телом {ip}.
  const allowIp = async (ip: string) => {
    const v = (ip || "").trim(); if (!v) return;
    const existing = allowedIps.find((x: any) => x.ip === v);
    if (existing) { if (existing.enabled === false) await saveSettings({ allowed_ips: allowedIps.map((x: any) => x === existing ? { ...x, enabled: true } : x) }); return; }
    if (ipIn(banIps, v)) {
      setConfirmA({ text: `IP ${v} забанен (подписка). Разбанить его и добавить в разрешённые?`, ok: "Разбанить", cancel: "Нет", okCls: "emerald", run: () => { setNewIp(""); void saveSettings({ ban_ips: dropIp(banIps, v), allowed_ips: [...allowedIps, { ip: v, enabled: true }] }); } });
      return;
    }
    setNewIp("");
    await saveSettings({ allowed_ips: [...allowedIps, { ip: v, enabled: true }] });
  };
  const banIp = (ip: string) => {
    const v = (ip || "").trim(); if (!v || ipIn(banIps, v)) return;
    if (ipIn(allowedIps, v)) {
      setConfirmA({ text: `IP ${v} в списке разрешённых (подписка). Он будет удалён из разрешённых и забанен.`, ok: "Бан", cancel: "Отмена", okCls: "red", run: () => { setNewBanIp(""); void saveSettings({ allowed_ips: dropIp(allowedIps, v), ban_ips: [...banIps, { ip: v, enabled: true }] }); } });
      return;
    }
    setNewBanIp("");
    void saveSettings({ ban_ips: [...banIps, { ip: v, enabled: true }] });
  };
  const rmBanIp = (ip: string) => { const nx = banIps.filter((x) => x.ip !== ip); setBanIps(nx); void saveSettings({ ban_ips: nx }); };
  const toggleBanIp = (ip: string, en: boolean) => { const nx = banIps.map((x) => (x.ip === ip ? { ...x, enabled: en } : x)); setBanIps(nx); void saveSettings({ ban_ips: nx }); };
  const toggleIp = (ip: string, en: boolean) => { const nx = allowedIps.map((x) => (x.ip === ip ? { ...x, enabled: en } : x)); setAllowedIps(nx); void saveSettings({ allowed_ips: nx }); };
  const removeIp = (ip: string) => { const nx = allowedIps.filter((x) => x.ip !== ip); setAllowedIps(nx); void saveSettings({ allowed_ips: nx }); };
  const isKnown = (hwid: string) => devices.some((d) => (d.hwid || "").toLowerCase() === hwid.toLowerCase() && d.enabled !== false);
  // Режимы секций: «Выключено» затемняет и блокирует ТОЛЬКО свою область разрешённых.
  const randSub = randOn && randScope !== "crypto";
  const randConn = randOn && randScope !== "client_id";
  const subKeyrand = mode === "keyrand";
  const subKeyrandAvailable = randSub || subKeyrand;
  const subOff = mode !== "enforce" && !subKeyrand;
  const connKr = connKeyrand && randConn;
  const connOff = !enforceConns && !connKr;
  const olcKeyrandHint = (target: "sub" | "conn") => {
    const typeText = randType === 2
      ? "Тип 2: рандомизированные значения меняются динамически."
      : "Тип 1: для неизвестных используется статичное рандомизированное значение.";
    if (target === "sub") {
      if (randScope === "client_id") return `Разрешённые получают подписку по оригинальному client_id; неизвестные — только по рандомизированному. Криптоключи не рандомизируются и остаются оригинальными для всех. ${typeText} Бан действует всегда.`;
      return `Разрешённые используют оригинальные client_id и криптоключи. Неизвестным нужен рандомизированный client_id, а в полученной подписке — рандомизированные криптоключи. ${typeText} Бан действует всегда.`;
    }
    if (randScope === "crypto") return `Разрешённые подключаются по оригинальным криптоключам; неизвестные — только по рандомизированным. Client_id не рандомизируется и остаётся оригинальным для всех. ${typeText} Отключение разрешения сбрасывает живую сессию по оригинальному ключу; бан действует всегда.`;
    return `Разрешённые используют оригинальные криптоключи и client_id; неизвестным нужны рандомизированные значения. ${typeText} Отключение разрешения сбрасывает живую сессию по оригинальному ключу; бан действует всегда.`;
  };
  const dimCls = (off: boolean) => (off ? " pointer-events-none opacity-40 select-none" : "");

  return (
    <section className="grid gap-4 rounded-md border border-border bg-background p-4">
      <div>
        <div className="text-sm font-semibold text-foreground">🔐 Глобальный контроль доступа по устройству</div>
        <div className="mt-1 text-xs text-muted-foreground">
          Действует на <b className="text-foreground">все подписки</b>. Белый список устройств по <span className="font-mono">hwid</span>,
          который olcbox присылает при запросе подписки. Пока он включён — выборочные настройки в ⚙ у клиентов недоступны.
          Все данные хранятся только на этом сервере.
        </div>
      </div>
      <button type="button" disabled={busy}
        onClick={() => { const v = !enabled; setEnabled(v); void saveSettings({ enabled: v }); }}
        className={"inline-flex w-fit items-center gap-2 rounded-md border px-3 py-1.5 text-sm font-medium transition-colors duration-300 " + (enabled ? "border-emerald-600/60 bg-emerald-500/15 text-emerald-300" : "border-border text-muted-foreground hover:bg-muted")}>
        <span>{enabled ? "🔓" : "🔒"}</span> {enabled ? "Контроль доступа включён" : "Включить контроль доступа"}
      </button>

      {enabled && (
        <>
          {/* ── БЛОК 1: доступ к подписке (режим) ── */}
          <div className="grid gap-2 rounded-md border border-border bg-card/40 p-3">
            <div className="text-xs font-semibold text-foreground">🎫 Доступ к подписке <span className="font-normal text-muted-foreground">— кто может ПОЛУЧИТЬ ссылку-подписку (списки ниже)</span></div>
            <div className="flex flex-wrap gap-2 text-xs">
              <button type="button" disabled={busy}
                className={subOff ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300 transition-colors duration-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground transition-colors duration-300 hover:bg-muted"}
                onClick={() => { if (subOff) return; const go = () => { setMode("monitor"); void saveSettings({ mode: "monitor" }); }; if (randSub) { setConfirmA({ text: (randType === 2 ? "При выключении контроля доступа (переключении на «Пускать всех») подписка станет недоступна для всех. Не рекомендуем данное действие." : "При выключении контроля доступа (переключении на «Пускать всех») и включённой рандомизации 1 типа подписка станет недоступна по оригинальному client id для всех. Не рекомендуем данное действие."), ok: "Всё равно выключить", cancel: "Отмена", okCls: "red", run: go }); } else { go(); } }}>
                Выключено (пускать всех (кроме бан-листа), лог)
              </button>
              {subKeyrandAvailable && (
                <button type="button" disabled={busy}
                  title={olcKeyrandHint("sub")}
                  className={subKeyrand ? "rounded-md border border-amber-500/70 bg-emerald-500/15 px-3 py-1 font-medium text-emerald-300 transition-all duration-300 active:scale-95" : "rounded-md border border-amber-500/60 bg-amber-500/15 px-3 py-1 font-medium text-amber-300 transition-all duration-300 active:scale-95 hover:bg-amber-500/25"}
                  onClick={() => { if (subKeyrand) return; setMode("keyrand"); void saveSettings({ mode: "keyrand" }); }}>
                  +
                </button>
              )}
              <button type="button" disabled={busy}
                className={mode === "enforce" ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300 transition-colors duration-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground transition-colors duration-300 hover:bg-muted"}
                onClick={() => { if (mode === "enforce") return; setMode("enforce"); void saveSettings({ mode: "enforce" }); }}>
                Блокировать неизвестных (+логирование)
              </button>
            </div>
            <div className="text-[10px] leading-snug text-muted-foreground">Журнал и бан-лист действуют в ОБОИХ режимах. «Блокировать неизвестных» дополнительно пускает только устройства/IP из «Разрешённых».</div>
          </div>

          {/* ── БЛОК 2: разрешённые устройства ── */}
          <div className={"grid gap-2 rounded-md border p-3 transition-colors duration-300" + (subKeyrand ? " border-amber-500/50 bg-amber-500/5" : " border-emerald-600/30 bg-emerald-500/5") + dimCls(subOff)}
            title={subOff ? "Режим «Выключено»: списки разрешённых не действуют и недоступны — включите «Блокировать неизвестных»" : undefined}>
            <div className={"text-xs font-semibold " + (subKeyrand ? "text-amber-400" : "text-emerald-400")}>✅ Разрешённые устройства (получение подписки){subKeyrand ? " (режим «+»: у них полный доступ)" : subOff ? " — не действуют в режиме «Выключено»" : ""}</div>
            {devices.length === 0 && <div className="text-xs text-muted-foreground">Пока пусто. Добавьте hwid вручную или кнопкой «Разрешить» из журнала/подключений ниже.</div>}
            {devices.length > 0 && (
              <div className="grid max-h-40 gap-1 overflow-y-auto">
                {devices.map((d) => (
                  <div key={d.hwid} className="flex items-center gap-2 rounded border border-border bg-background px-2 py-1 text-xs">
                    <OlcToggleButton compact  title="Вкл/выкл доступ" checked={d.enabled !== false} disabled={busy}
                      onChange={(e) => void setDevice(d.hwid, { enabled: e.target.checked })} />
                    <input className="h-7 w-28 shrink-0 rounded border border-border bg-card px-1 text-[11px] text-foreground outline-none focus:border-primary"
                      placeholder="имя" defaultValue={d.label || ""}
                      onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }} onBlur={(e) => { if ((e.target.value || "") !== (d.label || "")) saveGlobalLabel(d.hwid, e.target.value); }} />
                    <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : ""}`}>{d.hwid}</span>
                    {crossBtn(d.hwid, "allow", "conn", connDevices.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addConnDevice(d.hwid))}
                    <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => void remove(d.hwid)}>✕</button>
                  </div>
                ))}
              </div>
            )}
            <div className="flex gap-2">
              <input className="h-8 flex-1 rounded-md border border-border bg-card px-2 text-xs text-foreground outline-none focus:border-primary"
                placeholder="install-… (hwid устройства)" value={newHwid} onChange={(e) => setNewHwid(e.target.value)} />
              <button type="button" className="rounded border border-border px-2 py-1 text-xs hover:bg-muted" disabled={busy || !newHwid.trim()} onClick={() => void allow(newHwid.trim())}>Добавить</button>
            </div>
            <details className="text-[11px]">
              <summary className="cursor-pointer text-muted-foreground">🌐 Разрешить по IP (без hwid — напр. свой сервер/скрипт)</summary>
              <div className="mt-2 grid gap-2">
                <div className="text-[11px] leading-snug text-amber-500/90">⚠️ Поддерживаются IP, CIDR (`203.0.113.0/24`) или диапазон (`203.0.113.10-203.0.113.80`). IP-список действует НЕЗАВИСИМО от списка устройств: запрос с включённого IP получает подписку, даже если его устройство выключено или отсутствует в списке. Чтобы IP перестал действовать — снимите с него галочку (или удалите).</div>
                {allowedIps.length > 0 && (
                  <div className="grid max-h-32 gap-1 overflow-y-auto">
                    {allowedIps.map((x) => (
                      <div key={x.ip} className="flex items-center gap-2 rounded border border-border bg-background px-2 py-1">
                        <OlcToggleButton compact  checked={x.enabled} disabled={busy} title={x.enabled ? "IP активен: пропускает подписку" : "IP выключен: не действует"} onChange={(e) => toggleIp(x.ip, e.target.checked)} />
                        <span className={"min-w-0 flex-1 truncate font-mono " + (x.enabled ? "text-foreground" : "text-muted-foreground line-through opacity-60")}>{x.ip}</span>
                        <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => void removeIp(x.ip)}>✕</button>
                      </div>
                    ))}
                  </div>
                )}
                <div className="flex gap-2">
                  <input className="h-8 flex-1 rounded-md border border-border bg-card px-2 text-xs text-foreground outline-none focus:border-primary"
                    placeholder="IP, CIDR или диапазон (203.0.113.7, /24, A-B)" value={newIp} onChange={(e) => setNewIp(e.target.value)} />
                  <button type="button" className="rounded border border-border px-2 py-1 hover:bg-muted" disabled={busy || !newIp.trim()} onClick={() => void allowIp(newIp.trim())}>Добавить IP</button>
                </div>
              </div>
            </details>
          </div>

          {/* ── БЛОК 3: забаненные устройства ── */}
          <div className="grid gap-2 rounded-md border border-red-500/30 bg-red-500/5 p-3">
            <div className="text-xs font-semibold text-red-400">🚫 Забаненные устройства (получение подписки)</div>
            <div className="text-[11px] text-muted-foreground">Жёсткий блок — действует ВСЕГДА, в обоих режимах (и в «Выключено»).</div>
            {ban.length === 0 && <div className="text-xs text-muted-foreground">Пусто.</div>}
            {ban.length > 0 && (
              <div className="grid max-h-32 gap-1 overflow-y-auto">
                {ban.map((d) => (
                  <div key={d.hwid} className="flex items-center gap-2 rounded border border-red-500/30 bg-background px-2 py-1 text-xs">
                    <OlcToggleButton compact  title="Вкл/выкл бан" checked={d.enabled !== false} disabled={busy} onChange={(e) => toggleBan(d.hwid, e.target.checked)} />
                    <input className="h-7 w-28 shrink-0 rounded border border-border bg-card px-1 text-[11px] text-foreground outline-none focus:border-primary"
                      placeholder="имя" defaultValue={d.label || ""}
                      onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }} onBlur={(e) => { if ((e.target.value || "") !== (d.label || "")) saveGlobalLabel(d.hwid, e.target.value); }} />
                    <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : "text-red-300"}`}>{d.hwid}</span>
                    {crossBtn(d.hwid, "ban", "conn", connBan.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addConnBan(d.hwid))}
                    <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => removeBan(d.hwid)}>✕</button>
                  </div>
                ))}
              </div>
            )}
            <div className="flex gap-2">
              <input className="h-8 flex-1 rounded-md border border-border bg-card px-2 text-xs text-foreground outline-none focus:border-primary"
                placeholder="install-… (забанить)" value={newBanHwid} onChange={(e) => setNewBanHwid(e.target.value)} />
              <button type="button" className="rounded-md border border-red-500/40 bg-red-500/10 px-3 py-1 text-xs font-medium text-red-400 hover:bg-red-500/20" disabled={busy || !newBanHwid.trim()} onClick={() => { banDevice(newBanHwid.trim()); setNewBanHwid(""); }}>Забанить</button>
            </div>
            <details className="text-[11px]">
              <summary className="cursor-pointer text-muted-foreground">🌐🚫 Забаненные IP (получение подписки)</summary>
              <div className="mt-2 grid gap-2">
                <div className="text-[11px] leading-snug text-amber-500/90">⚠️ Бан по IP действует ВСЕГДА — в обоих режимах (и в «Выключено»). Запрос подписки с забаненного IP блокируется независимо от устройства.</div>
                {banIps.length > 0 && (
                  <div className="grid max-h-32 gap-1 overflow-y-auto">
                    {banIps.map((x) => (
                      <div key={x.ip} className="flex items-center gap-2 rounded border border-red-500/30 bg-background px-2 py-1">
                        <OlcToggleButton compact  checked={x.enabled} disabled={busy} title={x.enabled ? "Бан IP активен" : "Бан IP выключен: не действует"} onChange={(e) => toggleBanIp(x.ip, e.target.checked)} />
                        <span className={"min-w-0 flex-1 truncate font-mono " + (x.enabled ? "text-red-300" : "text-muted-foreground line-through opacity-60")}>{x.ip}</span>
                        <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => rmBanIp(x.ip)}>✕</button>
                      </div>
                    ))}
                  </div>
                )}
                {banIps.length === 0 && <div className="text-[11px] text-muted-foreground">Пусто.</div>}
                <div className="flex gap-2">
                  <input className="h-8 flex-1 rounded-md border border-border bg-card px-2 text-xs text-foreground outline-none focus:border-primary"
                    placeholder="IP, CIDR или диапазон (забанить)" value={newBanIp} onChange={(e) => setNewBanIp(e.target.value)} />
                  <button type="button" className="rounded-md border border-red-500/40 bg-red-500/10 px-2 py-1 text-xs font-medium text-red-400 hover:bg-red-500/20" disabled={busy || !newBanIp.trim()} onClick={() => banIp(newBanIp)}>Забанить IP</button>
                </div>
              </div>
            </details>
            <div className="flex items-center justify-between gap-3 text-[11px] text-muted-foreground">
              <span>Блокировать запросы без hwid (Compatibility-режим olcbox) — действует в обоих режимах</span>
              <OlcToggleButton tone="danger" checked={banNoHwid} disabled={busy} onChange={(e) => { setBanNoHwid(e.target.checked); void saveSettings({ ban_no_hwid: e.target.checked }); }} />
            </div>
          </div>

          {/* ── БЛОК 4: журнал попыток подписки ── */}
          <div className="grid gap-2 rounded-md border border-border bg-card/40 p-3">
            <div className="flex items-center justify-between">
              <div className="text-xs font-semibold text-foreground">📋 Журнал попыток (подписка)</div>
              <div className="flex items-center gap-2">
                {autolog ? (
                  <span className="rounded-full border border-emerald-600/50 bg-emerald-500/10 px-2 py-0.5 text-[10px] text-emerald-400">● автологи</span>
                ) : (
                  <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void loadAttempts()}>Обновить</button>
                )}
                <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void clearAttempts()}>Очистить</button>
              </div>
            </div>
            {attempts.length === 0 && <div className="text-xs text-muted-foreground">Попыток пока не зафиксировано.</div>}
            {attempts.length > 0 && (
              <div ref={listRef} onScroll={onScroll} className="grid max-h-56 gap-1 overflow-y-auto overflow-x-hidden rounded border border-border bg-background p-2">
                {attempts.map((a, i) => {
                  const hwid = String(a.hwid || "");
                  const known = isKnown(hwid);
                  const knownDev = devices.find((d) => d.hwid.toLowerCase() === hwid.toLowerCase());
                  const count = Number(a.count || 1);
                  const aip = String(a.ip || "");
                  const ipAllowed = allowedIps.some((x: any) => x.ip === aip && x.enabled !== false);
                  const ipBanned = ipIn(banIps, aip);
                  return (
                    <div key={hwid + "|" + String(a.client_id) + "|" + i} className="flex min-w-0 items-center justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]">
                      <div className="min-w-0 flex-1">
                        <div className="break-all font-mono">
                          <span className={a.allowed ? "text-emerald-400" : "text-red-400"}>{a.allowed ? "✓" : "✗"}</span> {a.label?.trim() || knownDev?.label?.trim() || hwid || "(без hwid)"}{(a.label?.trim() || knownDev?.label?.trim()) && <span className="ml-1 text-[10px] text-muted-foreground" title={hwid}>({hwid})</span>}
                          {count > 1 && <span className="ml-1 rounded bg-muted px-1 text-muted-foreground">×{count}</span>}
                        </div>
                        <div className="break-words text-muted-foreground">{aip} · подписка: {String(a.client_id || "—")} · {String(a.ua || "")} · {String(a.ts || "").slice(0, 19)}</div>
                      </div>
                      {hwid && (
                        <div className="flex shrink-0 gap-1">
                          {!known && (subOff
                            ? <button type="button" className="cursor-not-allowed rounded border border-border px-2 py-1 text-muted-foreground opacity-40" disabled title="Режим «Выключено»: разрешённые не действуют. Доступно в «Блокировать неизвестных»">Разрешить</button>
                            : <button type="button" className="rounded border border-emerald-600/50 px-2 py-1 text-emerald-400 hover:bg-emerald-500/10" disabled={busy} onClick={() => void allow(hwid)}>Разрешить</button>)}
                          {!ban.some((d) => d.hwid.toLowerCase() === hwid.toLowerCase()) && <button type="button" className="rounded border border-red-500/40 px-2 py-1 text-red-400 hover:bg-red-500/10" disabled={busy} onClick={() => banDevice(hwid)}>Бан</button>}
                          {aip && (subOff
                            ? (!ipBanned && <button type="button" className="rounded border border-red-500/50 bg-red-500/10 px-2 py-1 text-red-400 hover:bg-red-500/20" disabled={busy} title="Режим «Выключено»: IP можно только ЗАБАНИТЬ (разрешённые IP не действуют)" onClick={() => banIp(aip)}>+IP</button>)
                            : <span className="inline-flex shrink-0">
                                {!ipAllowed && <button type="button" className={"border border-emerald-600/50 px-1.5 py-1 text-emerald-400 hover:bg-emerald-500/10 " + (ipBanned ? "rounded" : "rounded-l")} disabled={busy} title="Разрешить этот IP" onClick={() => void allowIp(aip)}>+IP</button>}
                                {!ipBanned && <button type="button" className={"border border-red-500/50 px-1.5 py-1 text-red-400 hover:bg-red-500/10 " + (ipAllowed ? "rounded" : "rounded-r border-l-0")} disabled={busy} title="Забанить этот IP" onClick={() => banIp(aip)}>🚫</button>}
                              </span>)}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* ── БЛОК 4b: контроль ПОДКЛЮЧЕНИЯ (отдельные списки) ── */}
          <div className="grid gap-2 rounded-md border border-sky-500/40 bg-sky-500/5 p-3">
            <div className="text-xs font-semibold text-sky-400">🔌 Доступ к подключению <span className="font-normal text-muted-foreground">— кто может ПОДКЛЮЧИТЬСЯ к инстансам (даже с валидной ссылкой)</span></div>
            <div className="flex flex-wrap gap-2 text-xs">
              <button type="button" disabled={busy}
                className={(connOff && !connKr) ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300 transition-colors duration-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground transition-colors duration-300 hover:bg-muted"}
                onClick={() => { if (connOff && !connKr) return; const go = () => { setEnforceConns(false); setConnKeyrand(false); void saveSettings({ enforce_connections: false, conn_mode: "off" }); }; if (randConn) { setConfirmA({ text: (randType === 2 ? "При выключении контроля доступа (переключении на «Пускать всех») инстансы в подписке станут недоступны для всех. Не рекомендуем данное действие." : "При выключении контроля доступа (переключении на «Пускать всех») и включённой рандомизации 1 типа инстансы в подписке станут недоступны по оригинальным ключам шифрования для всех. Не рекомендуем данное действие."), ok: "Всё равно выключить", cancel: "Отмена", okCls: "red", run: go }); } else { go(); } }}>
                Выключено (пускать всех (кроме бан-листа), лог)
              </button>
              {randConn && (
                <button type="button" disabled={busy}
                  title={olcKeyrandHint("conn")}
                  className={connKr ? "rounded-md border border-amber-500/70 bg-emerald-500/15 px-3 py-1 font-medium text-emerald-300 transition-all duration-300 active:scale-95" : "rounded-md border border-amber-500/60 bg-amber-500/15 px-3 py-1 font-medium text-amber-300 transition-all duration-300 active:scale-95 hover:bg-amber-500/25"}
                  onClick={() => { if (connKr) return; setEnforceConns(false); setConnKeyrand(true); void saveSettings({ enforce_connections: false, conn_mode: "keyrand" }); }}>
                  +
                </button>
              )}
              <button type="button" disabled={busy}
                className={(!connOff && !connKr) ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300 transition-colors duration-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground transition-colors duration-300 hover:bg-muted"}
                onClick={() => { if (!connOff && !connKr) return; setEnforceConns(true); setConnKeyrand(false); void saveSettings({ enforce_connections: true, conn_mode: "enforce" }); }}>
                Блокировать неизвестных (+логирование)
              </button>
            </div>
            <div className="text-[10px] leading-snug text-muted-foreground">«Блокировать неизвестных»: на подключении пускаются только устройства из списка ниже (закрывает «слитый инстанс»). Если список пуст — <b className="text-foreground">не пускает никого</b>. Журнал и бан-лист действуют в ОБОИХ режимах.<span className="text-amber-500"> ⚠️ Проверьте на своём устройстве.</span></div>
            {(
              <div className={"grid gap-2 pl-5" + dimCls(connOff && !connKr)}>
                <div className="flex flex-wrap gap-3 text-[11px] text-muted-foreground">
                  <label className="flex items-center gap-1">
                    <input type="radio" name="olc-conn-scope-global" checked={connScope === "all"} disabled={busy}
                      onChange={() => { setConnScope("all"); void saveSettings({ conn_scope: "all" }); }} />
                    Все инстансы (всех подписок)
                  </label>
                  <label className="flex items-center gap-1">
                    <input type="radio" name="olc-conn-scope-global" checked={connScope === "selective"} disabled={busy}
                      onChange={() => { setConnScope("selective"); void saveSettings({ conn_scope: "selective" }); }} />
                    Только выбранные
                  </label>
                </div>
                {connScope === "selective" && (() => {
                  // Группировка инстансов по КЛИЕНТУ: каждый клиент — сворачиваемый
                  // details (клик разворачивает его инстансы), а не плоский список.
                  const byClient: Record<string, Array<{ room_id: string; name: string }>> = {};
                  for (const it of allInstances) { (byClient[it.client_id] = byClient[it.client_id] || []).push({ room_id: it.room_id, name: it.name }); }
                  const clients = Object.entries(byClient);
                  return (
                    <div className="grid gap-1">
                      {clients.length === 0 && <div className="text-[11px] text-muted-foreground">Клиенты/инстансы не найдены.</div>}
                      {clients.map(([cid, insts]) => {
                        const rooms = insts.map((x) => x.room_id).filter(Boolean);
                        const sel = rooms.filter((r) => connInstances.includes(r)).length;
                        const allSel = rooms.length > 0 && sel === rooms.length;
                        return (
                          <details key={cid} className="rounded border border-border bg-background text-[11px]" open={sel > 0}>
                            <summary className="flex cursor-pointer list-none items-center gap-2 px-2 py-1">
                              <OlcToggleButton compact  checked={allSel} disabled={busy}
                                mixed={sel > 0 && !allSel}
                                onClick={(e) => e.stopPropagation()}
                                onChange={(e) => toggleGClientInstances(rooms, e.target.checked)} />
                              <span className="shrink-0 rounded bg-muted px-1 font-mono text-foreground">{cid}</span>
                              <span className="min-w-0 flex-1 truncate text-muted-foreground">подписка · инстансов: {insts.length}</span>
                              <span className={"shrink-0 rounded px-1 " + (sel > 0 ? "bg-sky-500/15 text-sky-300" : "text-muted-foreground")}>выбрано {sel}/{rooms.length}</span>
                            </summary>
                            <div className="grid gap-1 border-t border-border px-2 py-1">
                              {insts.map((it) => (
                                <div key={it.room_id} className="flex items-center gap-2 rounded px-1 py-0.5">
                                  <OlcToggleButton compact  checked={connInstances.includes(it.room_id)} disabled={busy}
                                    onChange={(e) => toggleGInstance(it.room_id, e.target.checked)} />
                                  <span className="min-w-0 flex-1 truncate">{it.name}</span>
                                  <span className="shrink-0 font-mono text-muted-foreground">{it.room_id}</span>
                                </div>
                              ))}
                            </div>
                          </details>
                        );
                      })}
                      <div className="text-[10px] text-muted-foreground">Вайтлист инстансов: контроль по спискам — на отмеченных; <b className="text-foreground">НЕотмеченные не пускают никого</b>. Клик по клиенту разворачивает его инстансы; галочка у клиента отмечает все его инстансы.</div>
                    </div>
                  );
                })()}
              </div>
            )}
            <div className={"grid gap-2 rounded-md border p-2 transition-colors duration-300 " + (connKr ? "border-amber-500/50 bg-amber-500/5" : "border-sky-500/30 bg-sky-500/5") + dimCls(connOff && !connKr)} title={(connOff && !connKr) ? "Режим «Выключено»: список разрешённых не действует и недоступен — включите «Блокировать неизвестных»" : undefined}>
              <div className="text-xs font-semibold text-sky-400">🔌 Разрешённые устройства (подключение к инстансам){(connOff && !connKr) ? " — не действуют в режиме «Выключено»" : ""}</div>
              <div className="text-[11px] text-muted-foreground">ОТДЕЛЬНЫЙ список от «получения подписки». <span className="text-amber-500">IP-фильтра здесь нет: на подключении виден только hwid устройства, не IP — IP-контроль работает только в разделе «получение подписки».</span></div>
              {connDevices.length === 0 && <div className="text-xs text-muted-foreground">Пусто.</div>}
              {connDevices.length > 0 && (
                <div className="grid max-h-40 gap-1 overflow-y-auto">
                  {connDevices.map((d) => (
                    <div key={d.hwid} className="flex items-center gap-2 rounded border border-sky-500/30 bg-background px-2 py-1 text-xs">
                      <OlcToggleButton compact  title="Вкл/выкл" checked={d.enabled !== false} disabled={busy} onChange={(e) => setConnDevice(d.hwid, { enabled: e.target.checked })} />
                      <input className="h-7 w-28 shrink-0 rounded border border-border bg-card px-1 text-[11px] text-foreground outline-none focus:border-primary"
                        placeholder="имя" defaultValue={d.label || ""}
                        onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }} onBlur={(e) => { if ((e.target.value || "") !== (d.label || "")) saveGlobalLabel(d.hwid, e.target.value); }} />
                      <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : ""}`}>{d.hwid}</span>
                      {crossBtn(d.hwid, "allow", "sub", devices.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => void allow(d.hwid))}
                      <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => rmConnDevice(d.hwid)}>✕</button>
                    </div>
                  ))}
                </div>
              )}
              <div className="flex gap-2">
                <input className="h-8 flex-1 rounded-md border border-border bg-card px-2 text-xs text-foreground outline-none focus:border-primary" placeholder="install-… (hwid)" value={newConnDev} onChange={(e) => setNewConnDev(e.target.value)} />
                <button type="button" className="rounded border border-sky-500/50 px-2 py-1 text-xs text-sky-400 hover:bg-sky-500/10" disabled={busy || !newConnDev.trim()} onClick={() => { addConnDevice(newConnDev.trim()); setNewConnDev(""); }}>Разрешить</button>
              </div>
            </div>
          </div>

          {/* ── БЛОК 4c: бан подключения ── */}
          <div className="grid gap-2 rounded-md border border-orange-500/30 bg-orange-500/5 p-3">
            <div className="text-xs font-semibold text-orange-400">🔌🚫 Забаненные устройства (подключение к инстансам)</div>
            <div className="text-[10px] text-amber-500/90">Бан действует ВСЕГДА — в обоих режимах (и в «Выключено»).</div>
            {connBan.length === 0 && <div className="text-xs text-muted-foreground">Пусто.</div>}
            {connBan.length > 0 && (
              <div className="grid max-h-32 gap-1 overflow-y-auto">
                {connBan.map((d) => (
                  <div key={d.hwid} className="flex items-center gap-2 rounded border border-orange-500/30 bg-background px-2 py-1 text-xs">
                    <OlcToggleButton compact  title="Вкл/выкл бан" checked={d.enabled !== false} disabled={busy} onChange={(e) => toggleConnBan(d.hwid, e.target.checked)} />
                    <input className="h-7 w-28 shrink-0 rounded border border-border bg-card px-1 text-[11px] text-foreground outline-none focus:border-primary"
                      placeholder="имя" defaultValue={d.label || ""}
                      onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }} onBlur={(e) => { if ((e.target.value || "") !== (d.label || "")) saveGlobalLabel(d.hwid, e.target.value); }} />
                    <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : "text-orange-300"}`}>{d.hwid}</span>
                    {crossBtn(d.hwid, "ban", "sub", ban.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => banDevice(d.hwid))}
                    <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => rmConnBan(d.hwid)}>✕</button>
                  </div>
                ))}
              </div>
            )}
            <div className="flex gap-2">
              <input className="h-8 flex-1 rounded-md border border-border bg-card px-2 text-xs text-foreground outline-none focus:border-primary" placeholder="install-… (забанить подключение)" value={newConnBan} onChange={(e) => setNewConnBan(e.target.value)} />
              <button type="button" className="rounded-md border border-orange-500/40 bg-orange-500/10 px-3 py-1 text-xs font-medium text-orange-400 hover:bg-orange-500/20" disabled={busy || !newConnBan.trim()} onClick={() => { addConnBan(newConnBan.trim()); setNewConnBan(""); }}>Забанить</button>
            </div>
          </div>

          {/* ── БЛОК 5: подключения к инстансам (с привязкой клиент/инстанс) ── */}
          <div className="grid gap-2 rounded-md border border-border bg-card/40 p-3">
            <div className="flex items-center justify-between">
              <div className="text-xs font-semibold text-foreground">🔌 Подключения к инстансам</div>
              <div className="flex items-center gap-2">
                {autolog ? (
                  <span className="rounded-full border border-emerald-600/50 bg-emerald-500/10 px-2 py-0.5 text-[10px] text-emerald-400">● автологи</span>
                ) : (
                  <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void loadAttempts()}>Обновить</button>
                )}
                <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void clearConnections()}>Очистить</button>
              </div>
            </div>
            <div className="rounded border border-sky-500/25 bg-sky-500/5 px-2 py-1 text-[10px] text-sky-200">Изменения доступа во время активного подключения применяются сразу, но восстановление туннеля после переключения может занять некоторое время. При проверке смотрите логи нужного инстанса.</div>
            <div className="text-[11px] text-muted-foreground">Устройства (device), реально подключавшиеся к инстансам — тот же идентификатор, что hwid подписки. Показывает, к какой подписке и инстансу шло подключение.</div>
            {(() => { const shown = connClearedAt ? connections.filter((c) => String(c.last || "") > connClearedAt) : connections;
            // Группировка по девайсу: одна запись на устройство, внутри — развернуть по подпискам/инстансам.
            const gmap: Record<string, any[]> = {};
            for (const c of shown) { const k = String(c.device || ""); (gmap[k] = gmap[k] || []).push(c); }
            const groups = Object.entries(gmap).map(([gdev, rows]) => ({
              dev: gdev,
              label: rows.map((r: any) => String(r.label || "").trim()).find(Boolean) || "",
              rows: rows.slice().sort((a: any, b: any) => (String(a.last || "") < String(b.last || "") ? -1 : 1)),
              count: rows.reduce((s: number, r: any) => s + Number(r.count || 0), 0),
              denied: rows.reduce((s: number, r: any) => s + Number(r.denied || 0), 0),
              kicked: rows.reduce((s: number, r: any) => s + Number(r.kicked || 0), 0),
              last: rows.reduce((m: string, r: any) => (String(r.last || "") > m ? String(r.last || "") : m), ""),
            })).sort((a, b) => (a.last < b.last ? -1 : 1));
            return (<>
            {groups.length === 0 && <div className="text-xs text-muted-foreground">Подключений пока не зафиксировано.</div>}
            {groups.length > 0 && (
              <div ref={connListRef} onScroll={onConnScroll} className="grid max-h-56 gap-1 overflow-x-hidden overflow-y-auto rounded border border-border bg-background p-2">
                {groups.map((g) => {
                  const dev = g.dev;
                  const known = connDevices.some((d) => d.hwid.toLowerCase() === dev.toLowerCase() && d.enabled !== false);
                  const knownDev = connDevices.find((d) => d.hwid.toLowerCase() === dev.toLowerCase());
                  const banned = connBan.some((d) => d.hwid.toLowerCase() === dev.toLowerCase());
                  return (
                    <details key={dev} className="rounded border border-border px-2 py-1 text-[11px]">
                      <summary className="flex cursor-pointer list-none items-center justify-between gap-2">
                        <div className="min-w-0">
                          <div className="break-all font-mono">▸ {g.label || knownDev?.label?.trim() || dev || "—"}{(g.label || knownDev?.label?.trim()) && <span className="ml-1 text-[10px] text-muted-foreground" title={dev}>({dev})</span>} {known && <span className="ml-1 rounded border border-sky-500/40 bg-sky-500/10 px-1 text-sky-300">Разрешённый</span>}{!known && g.count > 0 && <span className="ml-1 rounded bg-muted px-1 text-muted-foreground">×{g.count}</span>}{!known && g.denied > 0 && <span className="ml-1 rounded border border-red-500/40 bg-red-500/10 px-1 text-red-400" title="Отклонённые попытки подключения (бан / не в списке) — устройство НЕ подключилось, это ретраи клиента">🚫 отклонено ×{g.denied}</span>}{!known && g.kicked > 0 && <span className="ml-1 rounded border border-orange-500/40 bg-orange-500/10 px-1 text-orange-400" title="Живая сессия сброшена ядром по бану (ban-watcher): устройство было подключено и его отключило">⛔ сброшен ×{g.kicked}</span>}</div>
                          <div className="break-words text-muted-foreground">инстансов: {g.rows.length} · последнее: {String(g.last).slice(0, 19)}{g.count === 0 && g.denied > 0 ? " · только отклонённые попытки" : ""}</div>
                        </div>
                        {dev && (
                          <div className="flex shrink-0 gap-1" onClick={(e) => { e.preventDefault(); e.stopPropagation(); }}>
                            {!known && (connOff
                              ? <button type="button" className="cursor-not-allowed rounded border border-border px-2 py-1 text-muted-foreground opacity-40" disabled title="Режим «Выключено»: разрешённые не действуют. Доступно в «Блокировать неизвестных»">Разрешить</button>
                              : <button type="button" className="rounded border border-sky-500/50 px-2 py-1 text-sky-400 hover:bg-sky-500/10" disabled={busy} title="Разрешить для ПОДКЛЮЧЕНИЯ" onClick={() => addConnDevice(dev)}>Разрешить</button>)}
                            {!banned && <button type="button" className="rounded border border-orange-500/40 px-2 py-1 text-orange-400 hover:bg-orange-500/10" disabled={busy} title="Забанить для ПОДКЛЮЧЕНИЯ (действует в обоих режимах)" onClick={() => addConnBan(dev)}>Бан</button>}
                          </div>
                        )}
                      </summary>
                      <div className="mt-1 grid gap-0.5 border-t border-border pt-1">
                        {g.rows.map((c: any, i: number) => (
                          <div key={i} className="flex items-center justify-between gap-2 pl-3 text-[11px]">
                            <span className="min-w-0 truncate">→ {String(c.client_id || "—")}{c.location_name ? <> · {String(c.location_name)}</> : null}</span>
                            <span className="shrink-0 text-muted-foreground">{Number(c.count || 0) > 0 ? `×${c.count}` : ""}{Number(c.denied || 0) > 0 ? <span className="text-red-400"> 🚫×{c.denied}</span> : null}{Number(c.kicked || 0) > 0 ? <span className="text-orange-400"> ⛔×{c.kicked}</span> : null} · {String(c.last || "").slice(0, 19)}</span>
                          </div>
                        ))}
                      </div>
                    </details>
                  );
                })}
              </div>
            )}
            </>); })()}
          </div>
        </>
      )}
      {msg && <div className="text-xs text-red-500 whitespace-pre-wrap">{msg}</div>}
      {confirmA && (
        <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/60 p-4" onClick={() => setConfirmA(null)}>
          <div className="w-full max-w-sm rounded-lg border border-border bg-card p-4 shadow-xl" onClick={(e) => e.stopPropagation()}>
            <div className="text-sm leading-snug text-foreground">{confirmA.text}</div>
            <div className="mt-3 flex justify-end gap-2">
              <button type="button" className="rounded border border-border px-3 py-1 text-xs hover:bg-muted" onClick={() => setConfirmA(null)}>{confirmA.cancel}</button>
              <button type="button"
                className={confirmA.okCls === "red" ? "rounded border border-red-500/50 bg-red-500/10 px-3 py-1 text-xs font-medium text-red-400 hover:bg-red-500/20" : "rounded border border-emerald-600/50 bg-emerald-500/10 px-3 py-1 text-xs font-medium text-emerald-400 hover:bg-emerald-500/20"}
                onClick={() => { const r = confirmA.run; setConfirmA(null); r(); }}>{confirmA.ok}</button>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}

// ============================================================================
// Olc-cost-l: per-client контроль доступа к подписке (модалка по шестерёнке у 🎲).
// Индивидуально для ОДНОЙ подписки: режим, белый список (allow) и бан устройств.
// Забаненные не получат подписку даже если разрешены глобально. См. docs/ACCESS-CONTROL.md.
// ============================================================================
function ClientAccessModal({ clientId, onClose }: { clientId: string; onClose: () => void }) {
  type Dev = { hwid: string; label?: string; enabled: boolean };
  const [mode, setMode] = useState<string>("off");
  const [allow, setAllow] = useState<Dev[]>([]);
  const [ban, setBan] = useState<Dev[]>([]);
  const [connAllow, setConnAllow] = useState<Dev[]>([]);
  const [connBan, setConnBan] = useState<Dev[]>([]);
  const [hiddenCross, setHiddenCross] = useState<string[]>(() => { try { return JSON.parse(localStorage.getItem("olc-cross-hidden-v1") || "[]"); } catch { return []; } });
  const hideCross = (k: string) => { const nx = Array.from(new Set([...hiddenCross, k])); setHiddenCross(nx); try { localStorage.setItem("olc-cross-hidden-v1", JSON.stringify(nx)); } catch { /* ignore */ } };
  const unhideCross = (k: string) => { const nx = hiddenCross.filter((x) => x !== k); setHiddenCross(nx); try { localStorage.setItem("olc-cross-hidden-v1", JSON.stringify(nx)); } catch { /* ignore */ } };
  const [allowIps, setAllowIps] = useState<Array<{ ip: string; enabled: boolean }>>([]);
  const normIps = (v: any) => (Array.isArray(v) ? v : []).map((x: any) => (typeof x === "string" ? { ip: x, enabled: true } : { ip: String(x?.ip || ""), enabled: x?.enabled !== false })).filter((x: any) => x.ip);
  const [banIps, setBanIps] = useState<Array<{ ip: string; enabled: boolean }>>([]);
  const [banNoHwid, setBanNoHwid] = useState(false);
  const [newIp, setNewIp] = useState("");
  const [newBanIp, setNewBanIp] = useState("");
  // Мини-модалка подтверждения (конфликт бан↔разрешено): текст, кнопка ok, действие.
  const [confirmA, setConfirmA] = useState<null | { text: string; ok: string; cancel: string; okCls: "red" | "emerald"; run: () => void }>(null);
  const [attempts, setAttempts] = useState<Array<Record<string, any>>>([]);
  const [connections, setConnections] = useState<Array<Record<string, any>>>([]);
  const [connClearedAt, setConnClearedAt] = useState<string>(() => { try { return localStorage.getItem("olc-conn-cleared-" + clientId) || ""; } catch { return ""; } });
  const aListRef = useRef<HTMLDivElement | null>(null);
  const aFollowRef = useRef(true);
  const aResumeRef = useRef<number | null>(null);
  const kListRef = useRef<HTMLDivElement | null>(null);
  const kFollowRef = useRef(true);
  const kResumeRef = useRef<number | null>(null);
  const [newAllow, setNewAllow] = useState("");
  const [newBan, setNewBan] = useState("");
  const [newConnAllow, setNewConnAllow] = useState("");
  const [newConnBan, setNewConnBan] = useState("");
  const [autolog, setAutolog] = useState(true);
  const [busyRaw, setBusy] = useState(false);
  const busy = busyRaw && readStoredBool("olc-ctrl-lock-v1", true);
  const saveQueueRef = useRef<Promise<void>>(Promise.resolve());
  const saveVersionRef = useRef(0);
  const pendingSavesRef = useRef(0);
  const [msg, setMsg] = useState<string | null>(null);
  const [connEnforce, setConnEnforce] = useState(false);
  const [connScope, setConnScope] = useState<"all" | "selective">("all");
  const [connInstances, setConnInstances] = useState<string[]>([]);
  const [globalEnforceConns, setGlobalEnforceConns] = useState(false);
  const [glob, setGlob] = useState<any>({ devices: [], ban: [], allow_ips: [], ban_ips: [], conn_devices: [], conn_ban: [] });
  const [randOn, setRandOn] = useState(false);
  const [randType, setRandType] = useState(1);
  const [randScope, setRandScope] = useState("both");
  const [connKeyrand, setConnKeyrand] = useState(false);
  const [syncHidden, setSyncHidden] = useState<boolean>(() => { try { return localStorage.getItem("olc-sync-hidden-" + clientId) === "1"; } catch { return false; } });
  const [instances, setInstances] = useState<Array<{ room_id: string; name: string }>>([]);

  const load = async () => {
    try {
      const r = await fetch(`/api/access/client?client_id=${encodeURIComponent(clientId)}`, { cache: "no-store" });
      const b = await r.json();
      setMode(b.mode === "enforce" ? "enforce" : b.mode === "keyrand" ? "keyrand" : "off"); // off+monitor слиты в «Выключено»
      setAllow(Array.isArray(b.allow) ? b.allow : []);
      setBan(Array.isArray(b.ban) ? b.ban : []);
      setConnAllow(Array.isArray(b.conn_allow) ? b.conn_allow : []);
      setConnBan(Array.isArray(b.conn_ban) ? b.conn_ban : []);
      setAllowIps(normIps(b.allow_ips));
      setBanIps(normIps(b.ban_ips));
      setBanNoHwid(!!b.ban_no_hwid);
      setConnEnforce(!!b.conn_enforce); setConnKeyrand(b.conn_mode === "keyrand");
      setConnScope(b.conn_scope === "selective" ? "selective" : "all");
      setConnInstances(Array.isArray(b.conn_instances) ? b.conn_instances : []);
    } catch { /* ignore */ }
    try {
      const s = await fetch("/api/access/settings", { cache: "no-store" });
      const sb = await s.json();
      setGlobalEnforceConns(!!sb.enforce_connections);
      setGlob({
        devices: Array.isArray(sb.devices) ? sb.devices : [],
        ban: Array.isArray(sb.ban) ? sb.ban : [],
        allow_ips: normIps(sb.allowed_ips),
        ban_ips: normIps(sb.ban_ips),
        conn_devices: Array.isArray(sb.conn_devices) ? sb.conn_devices : [],
        conn_ban: Array.isArray(sb.conn_ban) ? sb.conn_ban : [],
        mode: sb.mode,
        conn_mode: sb.conn_mode,
        enforce_connections: !!sb.enforce_connections,
        conn_scope: sb.conn_scope === "selective" ? "selective" : "all",
        conn_instances: Array.isArray(sb.conn_instances) ? sb.conn_instances : [],
        ban_no_hwid: !!sb.ban_no_hwid,
      });
    } catch { /* ignore */ }
    try {
      const st = await fetch("/api/state", { cache: "no-store" });
      const stb = await st.json();
      const cl = (stb.clients || []).find((c: any) => String(c.client_id) === clientId);
      setInstances((cl?.locations || []).map((l: any) => ({ room_id: String(l.room_id || ""), name: String(l.name || l.room_id || "") })));
      try { const gr = await fetch("/api/settings/randomization/global", { cache: "no-store" }); const gb = await gr.json(); setRandOn(!!gb.enabled || !!(cl?.randomization?.enabled)); setRandType(gb.enabled ? (gb.rand_type === 2 ? 2 : 1) : ((cl?.randomization?.rand_type) === 2 ? 2 : 1)); setRandScope((gb.rand_scope === "client_id" || gb.rand_scope === "crypto") ? gb.rand_scope : "both"); } catch { setRandOn(!!(cl?.randomization?.enabled)); setRandType((cl?.randomization?.rand_type) === 2 ? 2 : 1); }
    } catch { /* ignore */ }
    try {
      const l = await fetch("/api/settings/logs", { cache: "no-store" });
      const lb = await l.json();
      setAutolog(lb.auto_refresh !== false);
    } catch { setAutolog(true); }
    await loadAttempts();
  };
  const loadAttempts = async () => {
    try {
      const a = await fetch("/api/access/attempts", { cache: "no-store" });
      const ab = await a.json();
      setAttempts((Array.isArray(ab.attempts) ? ab.attempts : []).filter((x: any) => String(x.client_id) === clientId));
    } catch { /* ignore */ }
    try {
      const c = await fetch("/api/access/connections", { cache: "no-store" });
      const cb = await c.json();
      setConnections((Array.isArray(cb.connections) ? cb.connections : []).filter((x: any) => String(x.client_id) === clientId));
    } catch { /* ignore */ }
  };
  useEffect(() => { void load(); }, [clientId]);
  useEffect(() => {
    if (!autolog) return;
    const id = window.setInterval(() => { void loadAttempts(); }, 2500);
    return () => window.clearInterval(id);
  }, [autolog, clientId]);
  useEffect(() => { if (aFollowRef.current && aListRef.current) aListRef.current.scrollTop = aListRef.current.scrollHeight; }, [attempts]);
  useEffect(() => { if (kFollowRef.current && kListRef.current) kListRef.current.scrollTop = kListRef.current.scrollHeight; }, [connections]);
  const mkOnScroll = (elRef: any, followRef: any, resumeRef: any) => () => {
    const el = elRef.current; if (!el) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 24;
    if (nearBottom) { if (resumeRef.current) window.clearTimeout(resumeRef.current); resumeRef.current = window.setTimeout(() => { followRef.current = true; }, 1500); }
    else { followRef.current = false; if (resumeRef.current) { window.clearTimeout(resumeRef.current); resumeRef.current = null; } }
  };
  const onAScroll = mkOnScroll(aListRef, aFollowRef, aResumeRef);
  const onKScroll = mkOnScroll(kListRef, kFollowRef, kResumeRef);
  const clearConnections = async () => {
    setBusy(true);
    try { await fetch(`/api/access/connections?clear=1&client_id=${encodeURIComponent(clientId)}`, { cache: "no-store" }); } catch { /* ignore */ }
    const ts = new Date().toISOString(); setConnClearedAt(ts); try { localStorage.setItem("olc-conn-cleared-" + clientId, ts); } catch { /* ignore */ }
    await loadAttempts(); setBusy(false);
  };
  const clearLog = async () => {
    setBusy(true); setMsg(null);
    try {
      await fetch(`/api/access/attempts/clear?client_id=${encodeURIComponent(clientId)}`, { method: "POST" });
      await loadAttempts();
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };

  const save = (next?: { mode?: string; allow?: Dev[]; ban?: Dev[]; allow_ips?: any[]; ban_ips?: any[]; ban_no_hwid?: boolean; conn_allow?: Dev[]; conn_ban?: Dev[]; conn_enforce?: boolean; conn_mode?: string; conn_scope?: string; conn_instances?: string[] }) => {
    const version = ++saveVersionRef.current;
    pendingSavesRef.current += 1; setBusy(true); setMsg(null);
    const run = async () => {
      try {
        const r = await fetch("/api/access/client", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ client_id: clientId, ...(next || {}) }) });
        const b = await r.json(); if (!r.ok) throw new Error(b.error || ("HTTP " + r.status));
        const cc = (b.clients || {})[clientId] || {};
        if (version === saveVersionRef.current) {
          setMode(cc.mode === "enforce" ? "enforce" : cc.mode === "keyrand" ? "keyrand" : "off"); setAllow(Array.isArray(cc.allow) ? cc.allow : []); setBan(Array.isArray(cc.ban) ? cc.ban : []);
          setConnAllow(Array.isArray(cc.conn_allow) ? cc.conn_allow : []); setConnBan(Array.isArray(cc.conn_ban) ? cc.conn_ban : []);
          setAllowIps(normIps(cc.allow_ips)); setBanIps(normIps(cc.ban_ips)); setBanNoHwid(!!cc.ban_no_hwid);
          setConnEnforce(!!cc.conn_enforce); setConnKeyrand(cc.conn_mode === "keyrand"); setConnScope(cc.conn_scope === "selective" ? "selective" : "all"); setConnInstances(Array.isArray(cc.conn_instances) ? cc.conn_instances : []);
        }
        try { window.dispatchEvent(new CustomEvent("olc-access-saved", { detail: {} })); } catch { /* ignore */ }
      } catch (e: any) { if (version === saveVersionRef.current) setMsg("Ошибка: " + (e?.message || String(e))); }
      finally { pendingSavesRef.current -= 1; if (pendingSavesRef.current === 0) setBusy(false); }
    };
    saveQueueRef.current = saveQueueRef.current.then(run, run); return saveQueueRef.current;
  };
  // ── Конфликт бан↔разрешено: устройство/IP НИКОГДА не должно быть в обоих
  // списках одновременно. Добавление в один список при наличии в противоположном
  // → мини-модалка подтверждения; подтверждение = атомарный перенос (один save).
  const inList = (list: Dev[], h: string) => list.some((d) => (d.hwid || "").toLowerCase() === (h || "").toLowerCase());
  const dropHwid = (list: Dev[], h: string) => list.filter((d) => (d.hwid || "").toLowerCase() !== (h || "").toLowerCase());
  const namedClientDevice = (h: string) => { const d = [...allow, ...ban, ...connAllow, ...connBan].find((x) => (x.hwid || "").toLowerCase() === h.toLowerCase()); return { hwid: h, ...(d?.label?.trim() ? { label: d.label.trim() } : {}), enabled: true }; };
  const saveClientLabel = (h: string, label: string) => { const patch = (xs: Dev[]) => xs.map((x) => (x.hwid || "").toLowerCase() === h.toLowerCase() ? { ...x, label } : x); const na=patch(allow), nb=patch(ban), nc=patch(connAllow), ncb=patch(connBan); setAllow(na); setBan(nb); setConnAllow(nc); setConnBan(ncb); void save({ allow: na, ban: nb, conn_allow: nc, conn_ban: ncb }); };
  const ipIn = (list: any[], ip: string) => (list || []).some((x: any) => x.ip === ip);
  const dropIp = (list: any[], ip: string) => (list || []).filter((x: any) => x.ip !== ip);
  const addIp = (ip: string) => {
    const v = (ip || "").trim(); if (!v) return;
    const existing = allowIps.find((x: any) => x.ip === v);
    if (existing) { if (existing.enabled === false) void save({ allow_ips: allowIps.map((x: any) => x === existing ? { ...x, enabled: true } : x) }); return; }
    if (ipIn(banIps, v)) {
      setConfirmA({ text: `IP ${v} забанен (подписка). Разбанить его и добавить в разрешённые?`, ok: "Разбанить", cancel: "Нет", okCls: "emerald", run: () => { setNewIp(""); void save({ ban_ips: dropIp(banIps, v), allow_ips: [...allowIps, { ip: v, enabled: true }] }); } });
      return;
    }
    setNewIp(""); void save({ allow_ips: [...allowIps, { ip: v, enabled: true }] });
  };
  const rmIp = (ip: string) => { const nx = allowIps.filter((x) => x.ip !== ip); setAllowIps(nx); void save({ allow_ips: nx }); };
  const toggleIp = (ip: string, en: boolean) => { const nx = allowIps.map((x) => (x.ip === ip ? { ...x, enabled: en } : x)); setAllowIps(nx); void save({ allow_ips: nx }); };
  const addBanIp = (ip: string) => {
    const v = (ip || "").trim(); if (!v || ipIn(banIps, v)) return;
    if (ipIn(allowIps, v)) {
      setConfirmA({ text: `IP ${v} в списке разрешённых (подписка). Он будет удалён из разрешённых и забанен.`, ok: "Бан", cancel: "Отмена", okCls: "red", run: () => { setNewBanIp(""); void save({ allow_ips: dropIp(allowIps, v), ban_ips: [...banIps, { ip: v, enabled: true }] }); } });
      return;
    }
    setNewBanIp(""); void save({ ban_ips: [...banIps, { ip: v, enabled: true }] });
  };
  const rmBanIp = (ip: string) => { const nx = banIps.filter((x) => x.ip !== ip); setBanIps(nx); void save({ ban_ips: nx }); };
  const toggleBanIp = (ip: string, en: boolean) => { const nx = banIps.map((x) => (x.ip === ip ? { ...x, enabled: en } : x)); setBanIps(nx); void save({ ban_ips: nx }); };
  const addConnAllow = (h: string) => {
    h = (h || "").trim(); if (!h) return;
    const existing = connAllow.find((d) => (d.hwid || "").toLowerCase() === h.toLowerCase());
    if (existing) { if (existing.enabled === false) void save({ conn_allow: connAllow.map((d) => d === existing ? { ...d, enabled: true } : d) }); return; }
    if (inList(connBan, h)) {
      setConfirmA({ text: `Устройство ${h} забанено для ПОДКЛЮЧЕНИЯ. Разбанить его и добавить в разрешённые?`, ok: "Разбанить", cancel: "Нет", okCls: "emerald", run: () => { olcClearDeviceHistory(h); void save({ conn_ban: dropHwid(connBan, h), conn_allow: [...connAllow, namedClientDevice(h)] }); } });
      return;
    }
    olcClearDeviceHistory(h); void save({ conn_allow: [...connAllow, namedClientDevice(h)] });
  };
  const addConnBan = (h: string) => {
    h = (h || "").trim(); if (!h || inList(connBan, h)) return;
    if (inList(connAllow, h)) {
      setConfirmA({ text: `Устройство ${h} в списке разрешённых для ПОДКЛЮЧЕНИЯ. Оно будет удалено из разрешённых и забанено.`, ok: "Бан", cancel: "Отмена", okCls: "red", run: () => void save({ conn_allow: dropHwid(connAllow, h), conn_ban: [...connBan, namedClientDevice(h)] }) });
      return;
    }
    void save({ conn_ban: [...connBan, namedClientDevice(h)] });
  };
  const rmConnAllow = (h: string) => { const nx = connAllow.filter((d) => d.hwid !== h); setConnAllow(nx); void save({ conn_allow: nx }); };
  const rmConnBan = (h: string) => { const nx = connBan.filter((d) => d.hwid !== h); setConnBan(nx); void save({ conn_ban: nx }); };
  const toggleConnAllow = (h: string, en: boolean) => { const nx = connAllow.map((d) => d.hwid === h ? { ...d, enabled: en } : d); setConnAllow(nx); void save({ conn_allow: nx }); };
  const toggleConnBan = (h: string, en: boolean) => { const nx = connBan.map((d) => d.hwid === h ? { ...d, enabled: en } : d); setConnBan(nx); void save({ conn_ban: nx }); };
  // Кросс-кнопка «добавить в противоположный список». title — полный текст (подсказка).
  const crossBtn = (hwid: string, kind: "allow" | "ban", target: "sub" | "conn", present: boolean, add: () => void) => {
    const key = `${clientId}|${hwid}|${kind}|${target}`;
    if (present) return null;
    if (hiddenCross.includes(key)) {
      return <button type="button" className="shrink-0 rounded border border-border px-1 py-1 text-[10px] text-muted-foreground hover:bg-muted" title="Показать кнопку добавления в противоположный список" onClick={() => unhideCross(key)}>⋯</button>;
    }
    const title = kind === "allow"
      ? (target === "sub" ? "Добавить в разрешённые устройства для получения подписки" : "Добавить в разрешённые устройства для подключения к инстансам")
      : (target === "sub" ? "Добавить в забаненные устройства для получения подписки" : "Добавить в забаненные устройства для подключения к инстансам");
    const label = (kind === "allow" ? "✅→" : "🚫→") + (target === "sub" ? "подписка" : "подключение");
    const cls = kind === "allow" ? "border-emerald-500/50 text-emerald-400 hover:bg-emerald-500/10" : "border-orange-500/50 text-orange-400 hover:bg-orange-500/10";
    return (
      <span className="inline-flex shrink-0 items-center">
        <button type="button" className={`rounded-l border px-1.5 py-1 text-[10px] ${cls}`} disabled={busy} title={title} onClick={add}>{label}</button>
        <button type="button" className="rounded-r border border-l-0 border-border px-1 py-1 text-[10px] text-muted-foreground hover:bg-muted" title="Скрыть эту кнопку (можно вернуть)" onClick={() => hideCross(key)}>×</button>
      </span>
    );
  };
  const toggleInstance = (room: string, on: boolean) => {
    const nx = on ? [...connInstances, room] : connInstances.filter((r) => r !== room);
    setConnInstances(nx); void save({ conn_instances: nx });
  };
  const allowIp = (ip: string) => addIp(ip); // из журнала — в per-client список этой подписки
  const addAllow = (h: string) => {
    h = (h || "").trim(); if (!h) return;
    const existing = allow.find((d) => (d.hwid || "").toLowerCase() === h.toLowerCase());
    if (existing) { if (existing.enabled === false) void save({ allow: allow.map((d) => d === existing ? { ...d, enabled: true } : d) }); return; }
    if (inList(ban, h)) {
      setConfirmA({ text: `Устройство ${h} забанено (подписка). Разбанить его и добавить в разрешённые?`, ok: "Разбанить", cancel: "Нет", okCls: "emerald", run: () => { setNewAllow(""); olcClearDeviceHistory(h); void save({ ban: dropHwid(ban, h), allow: [...allow, namedClientDevice(h)] }); } });
      return;
    }
    setNewAllow(""); olcClearDeviceHistory(h); void save({ allow: [...allow, namedClientDevice(h)] });
  };
  const addBan = (h: string) => {
    h = (h || "").trim(); if (!h || inList(ban, h)) return;
    if (inList(allow, h)) {
      setConfirmA({ text: `Устройство ${h} в списке разрешённых (подписка). Оно будет удалено из разрешённых и забанено.`, ok: "Бан", cancel: "Отмена", okCls: "red", run: () => { setNewBan(""); void save({ allow: dropHwid(allow, h), ban: [...ban, namedClientDevice(h)] }); } });
      return;
    }
    setNewBan(""); void save({ ban: [...ban, namedClientDevice(h)] });
  };
  const rmAllow = (h: string) => { const nx = allow.filter((d) => d.hwid !== h); setAllow(nx); void save({ allow: nx }); };
  const rmBan = (h: string) => { const nx = ban.filter((d) => d.hwid !== h); setBan(nx); void save({ ban: nx }); };
  const toggleAllow = (h: string, en: boolean) => { const nx = allow.map((d) => d.hwid === h ? { ...d, enabled: en } : d); setAllow(nx); void save({ allow: nx }); };
  const toggleBan = (h: string, en: boolean) => { const nx = ban.map((d) => d.hwid === h ? { ...d, enabled: en } : d); setBan(nx); void save({ ban: nx }); };
  // Режимы секций: «Выключено» затемняет и блокирует ТОЛЬКО свою область разрешённых.
  const randSub = randOn && randScope !== "crypto";
  const randConn = randOn && randScope !== "client_id";
  const subKeyrand = mode === "keyrand" && randSub;
  const subOff = mode !== "enforce" && !subKeyrand;
  const connKr = connKeyrand && randConn;
  const connOff = !connEnforce && !connKr;
  const olcKeyrandHint = (target: "sub" | "conn") => {
    const typeText = randType === 2
      ? "Тип 2: рандомизированные значения меняются динамически."
      : "Тип 1: для неизвестных используется статичное рандомизированное значение.";
    if (target === "sub") {
      if (randScope === "client_id") return `Разрешённые получают подписку по оригинальному client_id; неизвестные — только по рандомизированному. Криптоключи не рандомизируются и остаются оригинальными для всех. ${typeText} Бан действует всегда.`;
      return `Разрешённые используют оригинальные client_id и криптоключи. Неизвестным нужен рандомизированный client_id, а в полученной подписке — рандомизированные криптоключи. ${typeText} Бан действует всегда.`;
    }
    if (randScope === "crypto") return `Разрешённые подключаются по оригинальным криптоключам; неизвестные — только по рандомизированным. Client_id не рандомизируется и остаётся оригинальным для всех. ${typeText} Отключение разрешения сбрасывает живую сессию по оригинальному ключу; бан действует всегда.`;
    return `Разрешённые используют оригинальные криптоключи и client_id; неизвестным нужны рандомизированные значения. ${typeText} Отключение разрешения сбрасывает живую сессию по оригинальному ключу; бан действует всегда.`;
  };
  const dimCls = (off: boolean) => (off ? " pointer-events-none opacity-40 select-none" : "");

  const devRow = (d: Dev, onToggle: ((en: boolean) => void) | null, onRemove: () => void, extra?: any, onLabel?: (label: string) => void) => (
    <div key={d.hwid} className="flex items-center gap-2 rounded border border-border px-2 py-1 text-[11px]">
      {onToggle && <OlcToggleButton compact  title="вкл/выкл" checked={d.enabled !== false} disabled={busy} onChange={(e) => onToggle(e.target.checked)} />}
      {onLabel && <input className="h-7 w-28 shrink-0 rounded border border-border bg-card px-1 text-[11px] text-foreground outline-none focus:border-primary"
        placeholder="имя" defaultValue={d.label || ""}
        onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }} onBlur={(e) => { if ((e.target.value || "") !== (d.label || "")) onLabel(e.target.value); }} />}
      <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : ""}`}>{d.hwid}</span>
      {extra || null}
      <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={onRemove}>✕</button>
    </div>
  );

  // Синхронизация per-client списков с ГЛОБАЛЬНЫМИ (одной кнопкой). Объединение
  // (union): глобальные записи доливаются в списки подписки, ничего не удаляя.
  const hasHwid = (list: Dev[], h: string) => list.some((d) => (d.hwid || "").toLowerCase() === (h || "").toLowerCase());
  const mergeDev = (base: Dev[], add: Dev[]) => { const out = [...base]; for (const d of add || []) { if (d && d.hwid && !hasHwid(out, d.hwid)) out.push({ hwid: d.hwid, label: d.label, enabled: d.enabled !== false }); } return out; };
  const mergeIp = (base: any[], add: any[]) => { const out = [...(base || [])]; for (const x of add || []) { if (x && x.ip && !out.some((y: any) => y.ip === x.ip)) out.push({ ip: x.ip, enabled: x.enabled !== false }); } return out; };
  const syncSubMode = glob.mode === "enforce" ? "enforce" : (glob.mode === "keyrand" && randSub ? "keyrand" : "off");
  const syncConnMode = (glob.conn_mode === "enforce" || glob.enforce_connections)
    ? "enforce"
    : (glob.conn_mode === "keyrand" && randConn ? "keyrand" : "off");
  const sameRooms = (a: string[], b: string[]) => [...(a || [])].sort().join("\n") === [...(b || [])].sort().join("\n");
  const isSynced = () =>
    (glob.devices || []).every((d: Dev) => hasHwid(allow, d.hwid)) &&
    (glob.ban || []).every((d: Dev) => hasHwid(ban, d.hwid)) &&
    (glob.conn_devices || []).every((d: Dev) => hasHwid(connAllow, d.hwid)) &&
    (glob.conn_ban || []).every((d: Dev) => hasHwid(connBan, d.hwid)) &&
    (glob.allow_ips || []).every((x: any) => (allowIps || []).some((y: any) => y.ip === x.ip)) &&
    (glob.ban_ips || []).every((x: any) => (banIps || []).some((y: any) => y.ip === x.ip)) &&
    mode === syncSubMode &&
    (connKeyrand ? "keyrand" : connEnforce ? "enforce" : "off") === syncConnMode &&
    connScope === (glob.conn_scope || "all") &&
    sameRooms(connInstances, glob.conn_instances || []) &&
    banNoHwid === !!glob.ban_no_hwid;
  const syncFromGlobal = () => {
    void save({
      allow: mergeDev(allow, glob.devices),
      ban: mergeDev(ban, glob.ban),
      conn_allow: mergeDev(connAllow, glob.conn_devices),
      conn_ban: mergeDev(connBan, glob.conn_ban),
      allow_ips: mergeIp(allowIps, glob.allow_ips),
      ban_ips: mergeIp(banIps, glob.ban_ips),
      ban_no_hwid: !!glob.ban_no_hwid,
      mode: syncSubMode,
      conn_mode: syncConnMode,
      conn_enforce: syncConnMode === "enforce",
      conn_scope: glob.conn_scope || "all",
      conn_instances: Array.isArray(glob.conn_instances) ? glob.conn_instances : [],
    });
  };
  const setSyncHiddenPersist = (v: boolean) => { setSyncHidden(v); try { localStorage.setItem("olc-sync-hidden-" + clientId, v ? "1" : "0"); } catch { /* ignore */ } };
  const synced = isSynced();

  return (
    <Modal title={`Выборочный доступ · подписка ${clientId}`} onClose={onClose}>
      <div className="grid gap-3 rounded-md bg-background p-4 text-sm">
        <div className="rounded-md border border-sky-500/30 bg-sky-500/5 p-3 text-xs text-muted-foreground">
          Это <b className="text-sky-400">выборочные</b> правила <b className="text-foreground">только для этой подписки и её инстансов</b>
          — независимо от других подписок. Действуют, когда глобальный контроль в общих настройках выключен.
          Идентификатор устройства (hwid) olcbox присылает при запросе подписки.
        </div>

        {syncHidden ? (
          <div className="flex justify-end">
            <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] text-muted-foreground hover:bg-muted" onClick={() => setSyncHiddenPersist(false)} title="Показать кнопку синхронизации с глобальными">⋯ синхронизация</button>
          </div>
        ) : (
          <div className={`flex items-center justify-between gap-2 rounded-md border px-3 py-2 ${synced ? "border-border bg-card/30" : "border-indigo-500/50 bg-indigo-500/10"}`}>
            <div className="min-w-0 text-[11px] text-muted-foreground">
              {synced ? "Списки этой подписки уже включают все глобальные записи." : "Скопировать глобальные режимы доступа, область инстансов и все разрешённые/забаненные/IP. Списки объединяются без удаления локальных записей."}
            </div>
            <div className="flex shrink-0 items-center gap-1">
              <button type="button" disabled={busy || synced}
                className={`rounded px-2 py-1 text-[11px] font-medium ${synced ? "cursor-not-allowed border border-border text-muted-foreground opacity-50" : "border border-indigo-500/60 bg-indigo-500/15 text-indigo-300 hover:bg-indigo-500/25"}`}
                onClick={syncFromGlobal}>Синхронизировать с глобальными</button>
              <button type="button" className="rounded border border-border px-1 py-1 text-[10px] text-muted-foreground hover:bg-muted" title="Скрыть (можно вернуть)" onClick={() => setSyncHiddenPersist(true)}>×</button>
            </div>
          </div>
        )}

        {/* ═══ СЕКЦИЯ A: доступ к получению подписки ═══ */}
        <div className="grid gap-3 rounded-md border border-border bg-card/30 p-3">
          <div className="text-sm font-semibold text-foreground">🎫 Кто может получить подписку</div>

          <div className="flex flex-wrap gap-2 text-xs">
            <button type="button" disabled={busy}
              className={subOff ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300 transition-colors duration-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground transition-colors duration-300 hover:bg-muted"}
              onClick={() => { if (subOff) return; const go = () => { setMode("off"); void save({ mode: "off" }); }; if (randSub) { setConfirmA({ text: (randType === 2 ? "При выключении контроля доступа (переключении на «Пускать всех») подписка станет недоступна для всех. Не рекомендуем данное действие." : "При выключении контроля доступа (переключении на «Пускать всех») и включённой рандомизации 1 типа подписка станет недоступна по оригинальному client id для всех. Не рекомендуем данное действие."), ok: "Всё равно выключить", cancel: "Отмена", okCls: "red", run: go }); } else { go(); } }}>
              Выключено (пускать всех (кроме бан-листа), лог)
            </button>
            {randSub && (
              <button type="button" disabled={busy}
                title={olcKeyrandHint("sub")}
                className={subKeyrand ? "rounded-md border border-amber-500/70 bg-emerald-500/15 px-3 py-1 font-medium text-emerald-300 transition-all duration-300 active:scale-95" : "rounded-md border border-amber-500/60 bg-amber-500/15 px-3 py-1 font-medium text-amber-300 transition-all duration-300 active:scale-95 hover:bg-amber-500/25"}
                onClick={() => { if (subKeyrand) return; setMode("keyrand"); void save({ mode: "keyrand" }); }}>
                +
              </button>
            )}
            <button type="button" disabled={busy}
              className={mode === "enforce" ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300 transition-colors duration-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground transition-colors duration-300 hover:bg-muted"}
              onClick={() => { if (mode === "enforce") return; setMode("enforce"); void save({ mode: "enforce" }); }}>
              Блокировать неизвестных (+логирование)
            </button>
          </div>
          <div className="text-[10px] leading-snug text-muted-foreground">Журнал и бан-лист действуют в ОБОИХ режимах. «Блокировать неизвестных» дополнительно пускает только устройства/IP из «Разрешённых».</div>

          <div className={"grid gap-2 rounded-md border p-2 transition-colors duration-300" + (subKeyrand ? " border-amber-500/50 bg-amber-500/5" : " border-emerald-600/30 bg-emerald-500/5") + dimCls(subOff)}
            title={subOff ? "Режим «Выключено»: списки разрешённых не действуют и недоступны — включите «Блокировать неизвестных»" : undefined}>
            <div className={"text-xs font-semibold " + (subKeyrand ? "text-amber-400" : "text-emerald-400")}>✅ Разрешённые устройства{subKeyrand ? " (режим «+»: полный доступ)" : subOff ? " — не действуют в режиме «Выключено»" : ""}</div>
            {allow.length === 0 && <div className="text-[11px] text-muted-foreground">Пусто.</div>}
            <div className="grid max-h-32 gap-1 overflow-y-auto">{allow.map((d) => devRow(d, (en) => toggleAllow(d.hwid, en), () => rmAllow(d.hwid), crossBtn(d.hwid, "allow", "conn", connAllow.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addConnAllow(d.hwid)), (label) => void save({ allow: allow.map((x) => x.hwid === d.hwid ? { ...x, label } : x) }), (label) => saveClientLabel(d.hwid, label)))}</div>
            <div className="flex gap-2">
              <input className="h-8 flex-1 rounded border border-border bg-card px-2 text-xs text-foreground" placeholder="install-… (hwid)" value={newAllow} onChange={(e) => setNewAllow(e.target.value)} />
              <button type="button" className="rounded border border-emerald-600/50 px-2 py-1 text-xs text-emerald-400 hover:bg-emerald-500/10" disabled={busy || !newAllow.trim()} onClick={() => addAllow(newAllow)}>Разрешить</button>
            </div>
            <details className="text-[11px]">
              <summary className="cursor-pointer text-muted-foreground">🌐 Разрешить по IP (для этой подписки)</summary>
              <div className="mt-2 grid gap-2">
                <div className="text-[11px] leading-snug text-amber-500/90">⚠️ Поддерживаются IP, CIDR (`203.0.113.0/24`) или диапазон (`203.0.113.10-203.0.113.80`). IP-список действует НЕЗАВИСИМО от списка устройств: запрос с включённого IP получает эту подписку, даже если его устройство выключено или отсутствует в списке. Чтобы IP перестал действовать — снимите с него галочку (или удалите).</div>
                {allowIps.length > 0 && (
                  <div className="grid max-h-28 gap-1 overflow-y-auto">
                    {allowIps.map((x) => (
                      <div key={x.ip} className="flex items-center gap-2 rounded border border-border bg-background px-2 py-1">
                        <OlcToggleButton compact  checked={x.enabled} disabled={busy} title={x.enabled ? "IP активен: пропускает подписку" : "IP выключен: не действует"} onChange={(e) => toggleIp(x.ip, e.target.checked)} />
                        <span className={"min-w-0 flex-1 truncate font-mono " + (x.enabled ? "text-foreground" : "text-muted-foreground line-through opacity-60")}>{x.ip}</span>
                        <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => rmIp(x.ip)}>✕</button>
                      </div>
                    ))}
                  </div>
                )}
                <div className="flex gap-2">
                  <input className="h-8 flex-1 rounded border border-border bg-card px-2 text-xs text-foreground" placeholder="IP, CIDR или диапазон" value={newIp} onChange={(e) => setNewIp(e.target.value)} />
                  <button type="button" className="rounded border border-border px-2 py-1 hover:bg-muted" disabled={busy || !newIp.trim()} onClick={() => addIp(newIp)}>Добавить IP</button>
                </div>
              </div>
            </details>
          </div>

          <div className="grid gap-2 rounded-md border border-red-500/30 bg-red-500/5 p-2">
            <div className="text-xs font-semibold text-red-400">🚫 Забаненные устройства (эта подписка)</div>
            {ban.length === 0 && <div className="text-[11px] text-muted-foreground">Пусто.</div>}
            <div className="grid max-h-32 gap-1 overflow-y-auto">{ban.map((d) => devRow(d, (en) => toggleBan(d.hwid, en), () => rmBan(d.hwid), crossBtn(d.hwid, "ban", "conn", connBan.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addConnBan(d.hwid)), (label) => saveClientLabel(d.hwid, label)))}</div>
            <div className="flex gap-2">
              <input className="h-8 flex-1 rounded border border-border bg-card px-2 text-xs text-foreground" placeholder="install-… (забанить)" value={newBan} onChange={(e) => setNewBan(e.target.value)} />
              <button type="button" className="rounded-md border border-red-500/40 bg-red-500/10 px-3 py-1 text-xs font-medium text-red-400 hover:bg-red-500/20" disabled={busy || !newBan.trim()} onClick={() => addBan(newBan)}>Забанить</button>
            </div>
            <details className="text-[11px]">
              <summary className="cursor-pointer text-muted-foreground">🌐🚫 Забаненные IP (эта подписка)</summary>
              <div className="mt-2 grid gap-2">
                <div className="text-[11px] leading-snug text-amber-500/90">⚠️ Бан по IP действует ВСЕГДА — в обоих режимах (и в «Выключено»). Запрос подписки с забаненного IP блокируется независимо от устройства.</div>
                {banIps.length > 0 && (
                  <div className="grid max-h-28 gap-1 overflow-y-auto">
                    {banIps.map((x) => (
                      <div key={x.ip} className="flex items-center gap-2 rounded border border-red-500/30 bg-background px-2 py-1">
                        <OlcToggleButton compact  checked={x.enabled} disabled={busy} title={x.enabled ? "Бан IP активен" : "Бан IP выключен: не действует"} onChange={(e) => toggleBanIp(x.ip, e.target.checked)} />
                        <span className={"min-w-0 flex-1 truncate font-mono " + (x.enabled ? "text-red-300" : "text-muted-foreground line-through opacity-60")}>{x.ip}</span>
                        <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => rmBanIp(x.ip)}>✕</button>
                      </div>
                    ))}
                  </div>
                )}
                {banIps.length === 0 && <div className="text-[11px] text-muted-foreground">Пусто.</div>}
                <div className="flex gap-2">
                  <input className="h-8 flex-1 rounded border border-border bg-card px-2 text-xs text-foreground" placeholder="IP, CIDR или диапазон (забанить)" value={newBanIp} onChange={(e) => setNewBanIp(e.target.value)} />
                  <button type="button" className="rounded-md border border-red-500/40 bg-red-500/10 px-2 py-1 text-xs font-medium text-red-400 hover:bg-red-500/20" disabled={busy || !newBanIp.trim()} onClick={() => addBanIp(newBanIp)}>Забанить IP</button>
                </div>
              </div>
            </details>
            <div className="flex items-center justify-between gap-3 text-[11px] text-muted-foreground">
              <span>Блокировать запросы без hwid (Compatibility-режим olcbox) — действует в обоих режимах</span>
              <OlcToggleButton tone="danger" checked={banNoHwid} disabled={busy} onChange={(e) => { setBanNoHwid(e.target.checked); void save({ ban_no_hwid: e.target.checked }); }} />
            </div>
          </div>

          <div className="grid gap-2 rounded-md border border-border bg-background/60 p-2">
            <div className="flex items-center justify-between">
              <div className="text-xs font-semibold text-foreground">📋 Журнал попыток получить подписку</div>
              <div className="flex items-center gap-2">
                {autolog
                  ? <span className="rounded-full border border-emerald-600/50 bg-emerald-500/10 px-2 py-0.5 text-[10px] text-emerald-400">● автологи</span>
                  : <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void loadAttempts()}>Обновить</button>}
                <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void clearLog()}>Очистить</button>
              </div>
            </div>
            {attempts.length === 0 && <div className="text-[11px] text-muted-foreground">Пока нет.</div>}
            {attempts.length > 0 && (
            <div ref={aListRef} onScroll={onAScroll} className="grid max-h-40 gap-1 overflow-x-hidden overflow-y-auto rounded border border-border bg-background p-2">
              {attempts.map((a, i) => {
                const hwid = String(a.hwid || "");
                const known = allow.some((d) => d.hwid.toLowerCase() === hwid.toLowerCase() && d.enabled !== false);
                const knownDev = allow.find((d) => d.hwid.toLowerCase() === hwid.toLowerCase());
                const banned = ban.some((d) => d.hwid.toLowerCase() === hwid.toLowerCase());
                const aip = String(a.ip || "");
                const ipAllowed = allowIps.some((x: any) => x.ip === aip && x.enabled !== false);
                const ipBanned = ipIn(banIps, aip);
                return (
                  <div key={hwid + i} className="flex min-w-0 flex-wrap items-start justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]">
                    <div className="min-w-0">
                      <div className="break-all font-mono"><span className={a.allowed ? "text-emerald-400" : "text-red-400"}>{a.allowed ? "✓" : "✗"}</span> {a.label?.trim() || knownDev?.label?.trim() || hwid || "(без hwid)"}{(a.label?.trim() || knownDev?.label?.trim()) && <span className="ml-1 text-[10px] text-muted-foreground" title={hwid}>({hwid})</span>}{Number(a.count || 1) > 1 && <span className="ml-1 rounded bg-muted px-1 text-muted-foreground">×{a.count}</span>}</div>
                      <div className="break-words text-muted-foreground">{aip} · {String(a.ua || "")} · {String(a.ts || "").slice(0, 19)}</div>
                    </div>
                    {hwid && (
                      <div className="flex shrink-0 gap-1">
                        {!known && (subOff
                          ? <button type="button" className="cursor-not-allowed rounded border border-border px-2 py-1 text-muted-foreground opacity-40" disabled title="Режим «Выключено»: разрешённые не действуют. Доступно в «Блокировать неизвестных»">Разрешить</button>
                          : <button type="button" className="rounded border border-emerald-600/50 px-2 py-1 text-emerald-400 hover:bg-emerald-500/10" disabled={busy} onClick={() => addAllow(hwid)}>Разрешить</button>)}
                        {!banned && <button type="button" className="rounded border border-red-500/40 px-2 py-1 text-red-400 hover:bg-red-500/10" disabled={busy} onClick={() => addBan(hwid)}>Бан</button>}
                        {aip && (subOff
                          ? (!ipBanned && <button type="button" className="rounded border border-red-500/50 bg-red-500/10 px-2 py-1 text-red-400 hover:bg-red-500/20" disabled={busy} title="Режим «Выключено»: IP можно только ЗАБАНИТЬ (разрешённые IP не действуют)" onClick={() => addBanIp(aip)}>+IP</button>)
                          : <span className="inline-flex shrink-0">
                              {!ipAllowed && <button type="button" className={"border border-emerald-600/50 px-1.5 py-1 text-emerald-400 hover:bg-emerald-500/10 " + (ipBanned ? "rounded" : "rounded-l")} disabled={busy} title="Разрешить этот IP для этой подписки" onClick={() => addIp(aip)}>+IP</button>}
                              {!ipBanned && <button type="button" className={"border border-red-500/50 px-1.5 py-1 text-red-400 hover:bg-red-500/10 " + (ipAllowed ? "rounded" : "rounded-r border-l-0")} disabled={busy} title="Забанить этот IP для этой подписки" onClick={() => addBanIp(aip)}>🚫</button>}
                            </span>)}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
            )}
          </div>
        </div>

        {/* ═══ СЕКЦИЯ B: доступ к подключению ═══ */}
        <div className="grid gap-3 rounded-md border border-border bg-card/30 p-3">
          <div className="text-sm font-semibold text-foreground">🔌 Кто может подключаться к инстансам</div>
          {(
            <>
              <div className="flex flex-wrap gap-2 text-xs">
                <button type="button" disabled={busy}
                  className={(connOff && !connKr) ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300 transition-colors duration-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground transition-colors duration-300 hover:bg-muted"}
                  onClick={() => { if (connOff && !connKr) return; const go = () => { setConnEnforce(false); setConnKeyrand(false); void save({ conn_enforce: false, conn_mode: "off" }); }; if (randConn) { setConfirmA({ text: (randType === 2 ? "При выключении контроля доступа (переключении на «Пускать всех») инстансы в подписке станут недоступны для всех. Не рекомендуем данное действие." : "При выключении контроля доступа (переключении на «Пускать всех») и включённой рандомизации 1 типа инстансы в подписке станут недоступны по оригинальным ключам шифрования для всех. Не рекомендуем данное действие."), ok: "Всё равно выключить", cancel: "Отмена", okCls: "red", run: go }); } else { go(); } }}>
                  Выключено (пускать всех (кроме бан-листа), лог)
                </button>
                {randConn && (
                  <button type="button" disabled={busy}
                    title={olcKeyrandHint("conn")}
                    className={connKr ? "rounded-md border border-amber-500/70 bg-emerald-500/15 px-3 py-1 font-medium text-emerald-300 transition-all duration-300 active:scale-95" : "rounded-md border border-amber-500/60 bg-amber-500/15 px-3 py-1 font-medium text-amber-300 transition-all duration-300 active:scale-95 hover:bg-amber-500/25"}
                    onClick={() => { if (connKr) return; setConnEnforce(false); setConnKeyrand(true); void save({ conn_enforce: false, conn_mode: "keyrand" }); }}>
                    +
                  </button>
                )}
                <button type="button" disabled={busy}
                  className={(!connOff && !connKr) ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300 transition-colors duration-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground transition-colors duration-300 hover:bg-muted"}
                  onClick={() => { if (!connOff && !connKr) return; setConnEnforce(true); setConnKeyrand(false); void save({ conn_enforce: true, conn_mode: "enforce" }); }}>
                  Блокировать неизвестных (+логирование)
                </button>
              </div>
              <div className="text-[10px] leading-snug text-muted-foreground">«Блокировать неизвестных»: к инстансам этой подписки пускаются только устройства из «Разрешённых для подключения». Если список пуст — <b className="text-foreground">не пускает никого</b>. Журнал и бан-лист действуют в ОБОИХ режимах.</div>
              {(
                <div className={"grid gap-2 pl-5" + dimCls(connOff && !connKr)}>
                  <div className="flex flex-wrap gap-3 text-[11px] text-muted-foreground">
                    <label className="flex items-center gap-1">
                      <input type="radio" name={`olc-conn-scope-${clientId}`} checked={connScope === "all"} disabled={busy}
                        onChange={() => { setConnScope("all"); void save({ conn_scope: "all" }); }} />
                      Все инстансы подписки
                    </label>
                    <label className="flex items-center gap-1">
                      <input type="radio" name={`olc-conn-scope-${clientId}`} checked={connScope === "selective"} disabled={busy}
                        onChange={() => { setConnScope("selective"); void save({ conn_scope: "selective" }); }} />
                      Только выбранные
                    </label>
                  </div>
                  {connScope === "selective" && (
                    <div className="grid gap-1">
                      {instances.length === 0 && <div className="text-[11px] text-muted-foreground">Инстансы не найдены.</div>}
                      {instances.map((it) => (
                        <div key={it.room_id} className="flex items-center gap-2 rounded border border-border bg-background px-2 py-1 text-[11px]">
                          <OlcToggleButton compact  checked={connInstances.includes(it.room_id)} disabled={busy}
                            onChange={(e) => toggleInstance(it.room_id, e.target.checked)} />
                          <span className="min-w-0 flex-1 truncate">{it.name}</span>
                          <span className="shrink-0 font-mono text-muted-foreground">{it.room_id}</span>
                        </div>
                      ))}
                      <div className="text-[10px] text-muted-foreground">Контроль — только на отмеченных инстансах.</div>
                    </div>
                  )}
                </div>
              )}

              <div className={"grid gap-2 rounded-md border p-2 transition-colors duration-300 " + (connKr ? "border-amber-500/50 bg-amber-500/5" : "border-sky-500/30 bg-sky-500/5") + dimCls(connOff && !connKr)}
                title={(connOff && !connKr) ? "Режим «Выключено»: список разрешённых не действует и недоступен — включите «Блокировать неизвестных»" : undefined}>
                <div className="text-xs font-semibold text-sky-400">🔌✅ Разрешённые для ПОДКЛЮЧЕНИЯ (эта подписка){(connOff && !connKr) ? " — не действуют в режиме «Выключено»" : ""}</div>
                <div className="text-[10px] text-muted-foreground">Отдельный список от «получения подписки». Кнопкой можно продублировать устройство в список подписки. <span className="text-amber-500">IP тут не фильтруется (на подключении виден только hwid).</span></div>
                {connAllow.length === 0 && <div className="text-[11px] text-muted-foreground">Пусто{connEnforce ? " — при включённом контроле никто не подключится" : ""}.</div>}
                <div className="grid max-h-32 gap-1 overflow-y-auto">{connAllow.map((d) => devRow(d, (en) => toggleConnAllow(d.hwid, en), () => rmConnAllow(d.hwid), crossBtn(d.hwid, "allow", "sub", allow.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addAllow(d.hwid)), (label) => void save({ conn_allow: connAllow.map((x) => x.hwid === d.hwid ? { ...x, label } : x) }), (label) => saveClientLabel(d.hwid, label)))}</div>
                <div className="flex gap-2">
                  <input className="h-8 flex-1 rounded border border-border bg-card px-2 text-xs text-foreground" placeholder="install-… (hwid)" value={newConnAllow} onChange={(e) => setNewConnAllow(e.target.value)} />
                  <button type="button" className="rounded border border-sky-500/50 px-2 py-1 text-xs text-sky-400 hover:bg-sky-500/10" disabled={busy || !newConnAllow.trim()} onClick={() => { addConnAllow(newConnAllow); setNewConnAllow(""); }}>Разрешить</button>
                </div>
              </div>

              <div className="grid gap-2 rounded-md border border-orange-500/30 bg-orange-500/5 p-2">
                <div className="text-xs font-semibold text-orange-400">🔌🚫 Забаненные для ПОДКЛЮЧЕНИЯ (эта подписка)</div>
                <div className="text-[10px] text-amber-500/90">Бан действует ВСЕГДА — в обоих режимах (и в «Выключено»).</div>
                {connBan.length === 0 && <div className="text-[11px] text-muted-foreground">Пусто.</div>}
                <div className="grid max-h-32 gap-1 overflow-y-auto">{connBan.map((d) => devRow(d, (en) => toggleConnBan(d.hwid, en), () => rmConnBan(d.hwid), crossBtn(d.hwid, "ban", "sub", ban.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addBan(d.hwid)), (label) => saveClientLabel(d.hwid, label)))}</div>
                <div className="flex gap-2">
                  <input className="h-8 flex-1 rounded border border-border bg-card px-2 text-xs text-foreground" placeholder="install-… (забанить подключение)" value={newConnBan} onChange={(e) => setNewConnBan(e.target.value)} />
                  <button type="button" className="rounded-md border border-orange-500/40 bg-orange-500/10 px-3 py-1 text-xs font-medium text-orange-400 hover:bg-orange-500/20" disabled={busy || !newConnBan.trim()} onClick={() => { addConnBan(newConnBan); setNewConnBan(""); }}>Забанить</button>
                </div>
              </div>
            </>
          )}
          <div className="grid gap-2 rounded-md border border-border bg-background/60 p-2">
            <div className="flex items-center justify-between">
              <div className="text-xs font-semibold text-foreground">🔌 Журнал подключений (эта подписка)</div>
              <div className="flex items-center gap-2">
                {autolog
                  ? <span className="rounded-full border border-emerald-600/50 bg-emerald-500/10 px-2 py-0.5 text-[10px] text-emerald-400">● автологи</span>
                  : <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void loadAttempts()}>Обновить</button>}
                <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void clearConnections()}>Очистить</button>
              </div>
            </div>
            <div className="w-full rounded border border-sky-500/25 bg-sky-500/5 px-2 py-1 text-[10px] leading-relaxed text-sky-200">Изменения доступа во время активного подключения применяются сразу, но восстановление туннеля после переключения может занять некоторое время. При проверке смотрите логи нужного инстанса.</div>
            {(() => { const shown = connClearedAt ? connections.filter((c) => String(c.last || "") > connClearedAt) : connections;
            // Группировка по девайсу: одна запись на устройство, внутри — развернуть по инстансам.
            const gmap: Record<string, any[]> = {};
            for (const c of shown) { const k = String(c.device || ""); (gmap[k] = gmap[k] || []).push(c); }
            const groups = Object.entries(gmap).map(([gdev, rows]) => ({
              dev: gdev,
              label: rows.map((r: any) => String(r.label || "").trim()).find(Boolean) || "",
              rows: rows.slice().sort((a: any, b: any) => (String(a.last || "") < String(b.last || "") ? -1 : 1)),
              count: rows.reduce((s: number, r: any) => s + Number(r.count || 0), 0),
              denied: rows.reduce((s: number, r: any) => s + Number(r.denied || 0), 0),
              kicked: rows.reduce((s: number, r: any) => s + Number(r.kicked || 0), 0),
              last: rows.reduce((m: string, r: any) => (String(r.last || "") > m ? String(r.last || "") : m), ""),
            })).sort((a, b) => (a.last < b.last ? -1 : 1));
            return (<>
            {groups.length === 0 && <div className="text-[11px] text-muted-foreground">Подключений пока нет.</div>}
            {groups.length > 0 && (
            <div ref={kListRef} onScroll={onKScroll} className="grid max-h-40 gap-1 overflow-x-hidden overflow-y-auto rounded border border-border bg-background p-2">
              {groups.map((g) => {
                const dev = g.dev;
                const known = connAllow.some((d) => d.hwid.toLowerCase() === dev.toLowerCase() && d.enabled !== false);
                const knownDev = connAllow.find((d) => d.hwid.toLowerCase() === dev.toLowerCase());
                const banned = connBan.some((d) => d.hwid.toLowerCase() === dev.toLowerCase());
                return (
                  <details key={dev} className="rounded border border-border px-2 py-1 text-[11px]">
                    <summary className="flex cursor-pointer list-none items-center justify-between gap-2">
                      <div className="min-w-0">
                        <div className="break-all font-mono">▸ {g.label || knownDev?.label?.trim() || dev || "—"}{(g.label || knownDev?.label?.trim()) && <span className="ml-1 text-[10px] text-muted-foreground" title={dev}>({dev})</span>} {known && <span className="ml-1 rounded border border-sky-500/40 bg-sky-500/10 px-1 text-sky-300">Разрешённый</span>}{!known && g.count > 0 && <span className="ml-1 rounded bg-muted px-1 text-muted-foreground">×{g.count}</span>}{!known && g.denied > 0 && <span className="ml-1 rounded border border-red-500/40 bg-red-500/10 px-1 text-red-400" title="Отклонённые попытки подключения (бан / не в списке) — устройство НЕ подключилось, это ретраи клиента">🚫 отклонено ×{g.denied}</span>}{!known && g.kicked > 0 && <span className="ml-1 rounded border border-orange-500/40 bg-orange-500/10 px-1 text-orange-400" title="Живая сессия сброшена ядром по бану (ban-watcher): устройство было подключено и его отключило">⛔ сброшен ×{g.kicked}</span>}</div>
                        <div className="break-words text-muted-foreground">инстансов: {g.rows.length} · последнее: {String(g.last).slice(0, 19)}{g.count === 0 && g.denied > 0 ? " · только отклонённые попытки" : ""}</div>
                      </div>
                      {dev && (
                        <div className="flex shrink-0 gap-1" onClick={(e) => { e.preventDefault(); e.stopPropagation(); }}>
                          {!known && (connOff
                            ? <button type="button" className="cursor-not-allowed rounded border border-border px-2 py-1 text-muted-foreground opacity-40" disabled title="Режим «Выключено»: разрешённые не действуют. Доступно в «Блокировать неизвестных»">Разрешить</button>
                            : <button type="button" className="rounded border border-sky-500/50 px-2 py-1 text-sky-400 hover:bg-sky-500/10" disabled={busy} title="Разрешить для подключения" onClick={() => addConnAllow(dev)}>Разрешить</button>)}
                          {!banned && <button type="button" className="rounded border border-orange-500/40 px-2 py-1 text-orange-400 hover:bg-orange-500/10" disabled={busy} title="Забанить для подключения (действует в обоих режимах)" onClick={() => addConnBan(dev)}>Бан</button>}
                        </div>
                      )}
                    </summary>
                    <div className="mt-1 grid gap-0.5 border-t border-border pt-1">
                      {g.rows.map((c: any, i: number) => (
                        <div key={i} className="flex items-center justify-between gap-2 pl-3 text-[11px]">
                          <span className="min-w-0 truncate">→ {String(c.location_name || c.room_id || "—")}</span>
                          <span className="shrink-0 text-muted-foreground">{Number(c.count || 0) > 0 ? `×${c.count}` : ""}{Number(c.denied || 0) > 0 ? <span className="text-red-400"> 🚫×{c.denied}</span> : null}{Number(c.kicked || 0) > 0 ? <span className="text-orange-400"> ⛔×{c.kicked}</span> : null} · {String(c.last || "").slice(0, 19)}</span>
                        </div>
                      ))}
                    </div>
                  </details>
                );
              })}
            </div>
            )}
            </>); })()}
          </div>
        </div>
        {msg && <div className="text-xs text-red-500 whitespace-pre-wrap">{msg}</div>}
        {confirmA && (
          <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/60 p-4" onClick={() => setConfirmA(null)}>
            <div className="w-full max-w-sm rounded-lg border border-border bg-card p-4 shadow-xl" onClick={(e) => e.stopPropagation()}>
              <div className="text-sm leading-snug text-foreground">{confirmA.text}</div>
              <div className="mt-3 flex justify-end gap-2">
                <button type="button" className="rounded border border-border px-3 py-1 text-xs hover:bg-muted" onClick={() => setConfirmA(null)}>{confirmA.cancel}</button>
                <button type="button"
                  className={confirmA.okCls === "red" ? "rounded border border-red-500/50 bg-red-500/10 px-3 py-1 text-xs font-medium text-red-400 hover:bg-red-500/20" : "rounded border border-emerald-600/50 bg-emerald-500/10 px-3 py-1 text-xs font-medium text-emerald-400 hover:bg-emerald-500/20"}
                  onClick={() => { const r = confirmA.run; setConfirmA(null); r(); }}>{confirmA.ok}</button>
              </div>
            </div>
          </div>
        )}
      </div>
    </Modal>
  );
}

function ComponentSettingsModal({
  feature,
  onClose,
}: {
  feature: FeatureName;
  onClose: () => void;
}) {
  const { t } = usePanelLang();
  const apiName = feature === "webtunnel" ? "bridges" : feature === "olcrtc" ? "olcrtc" : feature === "warp" ? "warp" : feature;
  const title = FEATURE_SETTINGS_HINTS[feature]?.title ?? feature;
  const [settings, setSettings] = useState<Record<string, unknown>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState("");
  const [instanceDefaultsOpen, setInstanceDefaultsOpen] = useState(false);
  const [splitAnalyzeTarget, setSplitAnalyzeTarget] = useState("");
  const [splitAnalysis, setSplitAnalysis] = useState<Record<string, unknown> | null>(null);
  const [splitExpanded, setSplitExpanded] = useState<Record<string, boolean>>({});
  const [splitAutoGroupsCollapsed, setSplitAutoGroupsCollapsed] = useState(true);
  const [splitAnalyzeMsg, setSplitAnalyzeMsg] = useState("");
  const [splitApplyMenuOpen, setSplitApplyMenuOpen] = useState(false);
  const [splitApplyTarget, setSplitApplyTarget] = useState("direct");
  const [newCustomDirectDomain, setNewCustomDirectDomain] = useState("");
  const [newPanelHost, setNewPanelHost] = useState("");
  const [newPanelCidr, setNewPanelCidr] = useState("");
  const [newForceTorDomain, setNewForceTorDomain] = useState("");
  const [newBlockedTorDomain, setNewBlockedTorDomain] = useState("");
  const [panelHostsExpanded, setPanelHostsExpanded] = usePersistedOpen("olc-split-panel-hosts-v1");
  const [panelCidrsExpanded, setPanelCidrsExpanded] = usePersistedOpen("olc-split-panel-cidrs-v1");
  const [forceTorExpanded, setForceTorExpanded] = usePersistedOpen("olc-split-force-tor-v1");
  const [blockedTorExpanded, setBlockedTorExpanded] = usePersistedOpen("olc-split-blocked-tor-v1");
  const [customDirectExpanded, setCustomDirectExpanded] = usePersistedOpen("olc-split-custom-direct-v1");

  useEffect(() => {
    setInstanceDefaultsOpen(false);
  }, [feature]);

  // --- Autosave (Phase 0): no Save button; persist changes automatically. ---
  const saveRef = useRef<() => Promise<void>>(async () => {});
  const dirtyRef = useRef(false);
  const autoTimer = useRef<number | null>(null);
  const markDirtyAndSchedule = () => {
    dirtyRef.current = true;
    if (autoTimer.current) window.clearTimeout(autoTimer.current);
    autoTimer.current = window.setTimeout(() => {
      dirtyRef.current = false;
      void saveRef.current();
    }, 1000);
  };
  const flushSave = () => {
    if (autoTimer.current) {
      window.clearTimeout(autoTimer.current);
      autoTimer.current = null;
    }
    if (dirtyRef.current) {
      dirtyRef.current = false;
      void saveRef.current();
    }
  };
  // Persist on page unload/reload and flush any pending debounce on unmount.
  useEffect(() => {
    const onUnload = () => { if (dirtyRef.current) { dirtyRef.current = false; void saveRef.current(); } };
    window.addEventListener("beforeunload", onUnload);
    return () => {
      window.removeEventListener("beforeunload", onUnload);
      flushSave();
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const res = await fetch(`/api/settings/${apiName}`, { cache: "no-store" });
        const raw = await res.text();
        let body: { settings?: Record<string, unknown>; error?: string } = {};
        try {
          body = (raw ? JSON.parse(raw) : {}) as { settings?: Record<string, unknown>; error?: string };
        } catch {
          body = { error: raw || undefined };
        }
        if (!res.ok) throw new Error(body.error || raw || `HTTP ${res.status}`);
        if (!cancelled) setSettings(body.settings ?? {});
      } catch (e) {
        if (!cancelled) setMsg(String(e));
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [apiName]);

  if (feature === "olcrtc" && instanceDefaultsOpen) {
    return <InstanceDefaultsModal onBack={() => setInstanceDefaultsOpen(false)} onClose={onClose} />;
  }

  if (loading) {
    return (
      <Modal title={`Настройки: ${title}`} onClose={onClose} wide={feature === "split"}>
        <div className="p-4">
          <LoadingState label={t("loading")} />
        </div>
      </Modal>
    );
  }

  const save = async () => {
    setSaving(true);
    setMsg("");
    try {
      let payload: Record<string, unknown> = { ...settings };
      if (feature === "webtunnel" || feature === "bridges") {
        const prof = settings.profiles as Record<string, unknown> | undefined;
        if (prof) {
          payload = {
            bridge_profiles: prof,
            active_profile: prof.active_profile,
            custom_bridge: settings.custom_bridge,
          };
        }
      }
      const res = await fetch(`/api/settings/${apiName}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      if (!res.ok) {
        const raw = await res.text();
        let errText = raw;
        try {
          const err = (raw ? JSON.parse(raw) : {}) as { error?: string };
          errText = err.error || raw;
        } catch {
          /* keep raw text */
        }
        throw new Error(errText || `HTTP ${res.status}`);
      }
      setMsg(t("saved"));
      if (feature === "olcrtc") {
        window.dispatchEvent(new CustomEvent("olc-global-proxy-saved", { detail: { enabled: Boolean(settings.global_socks_enabled) } }));
      }
    } catch (e) {
      setMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  saveRef.current = save;
  const setStr = (key: string, value: string) => { setSettings((s) => ({ ...s, [key]: value })); markDirtyAndSchedule(); };
  const setBool = (key: string, value: boolean) => {
    setSettings((s) => ({ ...s, [key]: value }));
    if (feature === "olcrtc" && key === "global_socks_enabled") {
      window.dispatchEvent(new CustomEvent("olc-global-proxy-saved", { detail: { enabled: value } }));
    }
    markDirtyAndSchedule();
  };

  const readJsonOrText = async (res: Response): Promise<Record<string, unknown>> => {
    const raw = await res.text();
    try {
      return (raw ? JSON.parse(raw) : {}) as Record<string, unknown>;
    } catch {
      return { error: raw || `HTTP ${res.status}` };
    }
  };

  const reloadSettings = async () => {
    const res = await fetch(`/api/settings/${apiName}`, { cache: "no-store" });
    const raw = await res.text();
    const body = raw ? JSON.parse(raw) : {};
    if (!res.ok) throw new Error(body?.error || raw || `HTTP ${res.status}`);
    setSettings(body.settings ?? {});
  };

  const splitAnalyze = async () => {
    const target = splitAnalyzeTarget.trim();
    if (!target) {
      setSplitAnalyzeMsg(t("splitAnalyzeNeedTarget"));
      return;
    }
    setSaving(true);
    setSplitAnalyzeMsg(t("splitAnalyzing"));
    try {
      const res = await fetch("/api/settings/split/analyze", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ target }),
      });
      const body = await readJsonOrText(res);
      if (!res.ok) throw new Error(String(body.error || `HTTP ${res.status}`));
      setSplitAnalysis((body.result ?? body) as Record<string, unknown>);
      setSplitAnalyzeMsg(t("splitAnalyzeDone"));
    } catch (e) {
      setSplitAnalyzeMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const splitApplyAnalysis = async (targetList = "direct") => {
    if (!splitAnalysis) return;
    setSaving(true);
    setSplitAnalyzeMsg("");
    setSplitApplyMenuOpen(false);
    try {
      const res = await fetch("/api/settings/split/apply-analysis", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...splitAnalysis, target_list: targetList }),
      });
      const body = await readJsonOrText(res);
      if (!res.ok) throw new Error(String(body.error || `HTTP ${res.status}`));
      if (body.settings) setSettings(body.settings as Record<string, unknown>);
      else await reloadSettings();
      setSplitAnalyzeMsg(t("splitApplyDone"));
    } catch (e) {
      setSplitAnalyzeMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const splitSyncConfig = async () => {
    setSaving(true);
    setSplitAnalyzeMsg(t("splitSyncRunning"));
    try {
      const res = await fetch("/api/settings/split/sync-config", { method: "POST" });
      const body = await readJsonOrText(res);
      if (!res.ok) throw new Error(String(body.error || `HTTP ${res.status}`));
      if (body.settings) setSettings(body.settings as Record<string, unknown>);
      else await reloadSettings();
      setSplitAnalyzeMsg(t("splitSyncDone"));
    } catch (e) {
      setSplitAnalyzeMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const splitSyncLogs = async () => {
    setSaving(true);
    setSplitAnalyzeMsg(t("splitSyncRunning"));
    try {
      const res = await fetch("/api/settings/split/sync-logs", { method: "POST" });
      const body = await readJsonOrText(res);
      if (!res.ok) throw new Error(String(body.error || `HTTP ${res.status}`));
      if (body.settings) setSettings(body.settings as Record<string, unknown>);
      else await reloadSettings();
      setSplitAnalyzeMsg(t("splitSyncLogsDone"));
    } catch (e) {
      setSplitAnalyzeMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const splitExpand = async () => {
    setSaving(true);
    setSplitAnalyzeMsg(t("splitExpandRunning"));
    try {
      const res = await fetch("/api/settings/split/expand", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ force: false }),
      });
      const body = await readJsonOrText(res);
      if (!res.ok) throw new Error(String(body.error || `HTTP ${res.status}`));
      if (body.settings) setSettings(body.settings as Record<string, unknown>);
      else await reloadSettings();
      const r = (body.result || {}) as Record<string, unknown>;
      const gained = Number(r.added_domains || 0);
      setSplitAnalyzeMsg(t("splitExpandDone") + (gained ? " (+" + gained + ")" : ""));
    } catch (e) {
      setSplitAnalyzeMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const splitApplyRouting = async () => {
    setSaving(true);
    setSplitAnalyzeMsg("");
    try {
      const res = await fetch("/api/settings/split/apply-routing", { method: "POST" });
      const body = await readJsonOrText(res);
      if (!res.ok) throw new Error(String(body.error || `HTTP ${res.status}`));
      setSplitAnalyzeMsg(t("splitApplyRoutingDone"));
    } catch (e) {
      setSplitAnalyzeMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
      window.setTimeout(() => setSplitAnalyzeMsg((m) => (m === t("splitApplyRoutingDone") ? "" : m)), 8000);
    }
  };

  const splitApplyAll = async () => {
    setSaving(true);
    setSplitAnalyzeMsg("Синхронизация конфига...");
    try {
      const res1 = await fetch("/api/settings/split/sync-config", { method: "POST" });
      const body1 = await readJsonOrText(res1);
      if (!res1.ok) throw new Error(`Sync config: ${body1.error || res1.status}`);
      if (body1.settings) setSettings(body1.settings as Record<string, unknown>);
      else await reloadSettings();

      setSplitAnalyzeMsg("Синхронизация логов...");
      const res2 = await fetch("/api/settings/split/sync-logs", { method: "POST" });
      const body2 = await readJsonOrText(res2);
      if (!res2.ok) throw new Error(`Sync logs: ${body2.error || res2.status}`);
      if (body2.settings) setSettings(body2.settings as Record<string, unknown>);
      else await reloadSettings();

      setSplitAnalyzeMsg("Применение роутинга...");
      const res3 = await fetch("/api/settings/split/apply-routing", { method: "POST" });
      const body3 = await readJsonOrText(res3);
      if (!res3.ok) throw new Error(`Apply routing: ${body3.error || res3.status}`);

      setSplitAnalyzeMsg("✓ Все изменения применены");
    } catch (e) {
      setSplitAnalyzeMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
      window.setTimeout(() => setSplitAnalyzeMsg((m) => (m === "✓ Все изменения применены" ? "" : m)), 8000);
    }
  };

  const splitDiscovery = (settings.discovery ?? {}) as { groups?: Array<Record<string, unknown>> };
  const splitGroups = Array.isArray(splitDiscovery.groups) ? splitDiscovery.groups : [];
  const splitFamilies = Array.from(splitGroups.reduce((families, group) => {
    const target = String(group.target ?? group.label ?? "other").toLowerCase();
    const targetParts = target.split(".").filter(Boolean);
    const fallbackBase = targetParts.length > 1 ? targetParts.slice(-2).join(".") : target;
    const vkFamily = /(^|\.)(vk\.com|vk\.ru|vkvideo\.ru|userapi\.com|vkuseraudio\.net|vkuservideo\.net|vkuser\.net|mycdn\.me)$/.test(target);
    const familyId = String(group.family_id ?? (vkFamily ? "brand:vk" : `domain:${fallbackBase}`));
    const familyLabel = String(group.family_label ?? (vkFamily ? "VK" : fallbackBase));
    const current = families.get(familyId) ?? { id: familyId, label: familyLabel, groups: [] as Array<Record<string, unknown>> };
    current.groups.push(group);
    families.set(familyId, current);
    return families;
  }, new Map<string, { id: string; label: string; groups: Array<Record<string, unknown>> }>()).values());
  const splitApplyOptions: Record<string, { label: string; hint: string }> = {
    direct: { label: t("splitApplyDefault"), hint: t("splitApplySelectedDirect") },
    custom_direct: { label: t("splitApplyManualDirect"), hint: t("splitApplySelectedManual") },
    force_tor: { label: t("splitApplyForceTor"), hint: t("splitApplySelectedTor") },
    blocked_tor: { label: t("splitApplyBlockedTor"), hint: t("splitApplySelectedBlocked") },
  };
  const splitApplySelection = splitApplyOptions[splitApplyTarget] ?? splitApplyOptions.direct;
  const splitAnalysisDomains = splitAnalysis && Array.isArray(splitAnalysis.domains) ? splitAnalysis.domains.map(String) : [];
  const splitAnalysisCidrs = splitAnalysis && Array.isArray(splitAnalysis.cidrs) ? splitAnalysis.cidrs.map(String) : [];
  const splitAnalysisProvenance = splitAnalysis && splitAnalysis.domain_provenance && typeof splitAnalysis.domain_provenance === "object"
    ? splitAnalysis.domain_provenance as Record<string, unknown>
    : {};
  const splitDomainWithProvenance = (domain: string, provenance: Record<string, unknown>) => {
    const rawEntries = Array.isArray(provenance[domain]) ? provenance[domain] as Array<Record<string, unknown>> : [];
    const labels = rawEntries.map((entry) => {
      const source = String(entry?.source ?? "unknown");
      const label = source === "target" ? t("splitProvTarget")
        : source === "cname" ? t("splitProvCname")
        : source === "runtime_log" ? t("splitProvRuntime")
        : source === "brand_family" ? t("splitProvBrand")
        : source === "certificate" ? t("splitProvCertificate")
        : source === "crt.sh" ? t("splitProvCrtsh")
        : t("splitProvUnknown");
      const detail = String(entry?.detail ?? "");
      return detail && detail !== domain ? `${label}: ${detail}` : label;
    });
    const unique = Array.from(new Set(labels));
    return unique.length ? `${domain}  ← ${unique.join(", ")}` : domain;
  };

  return (
    <Modal title={t("settingsTitle", { name: title })} onClose={onClose}>
      <div className="space-y-4 p-4 text-sm">
        {loading ? (
          <p className="text-muted-foreground">{t("loading")}</p>
        ) : (
          <>
            <AddonSettingsIntro feature={feature} />
            {feature === "zapret" && (
              <>
                <div className="flex items-center justify-between gap-3 text-xs text-muted-foreground">
                  <span>{t("zapretAutoSync")}</span>
                  <OlcToggleButton checked={Boolean(settings.auto_sync)} onChange={(e) => setBool("auto_sync", e.target.checked)} />
                </div>
                <label className="grid gap-1">
                  <span className="text-xs font-medium text-foreground">{t("zapretExcludeDomains")}</span>
                  <span className="text-[11px] leading-snug text-muted-foreground">Домены-исключения (по одному в строке): к ним DPI-обход НЕ применяется — идут напрямую.</span>
                  <textarea
                    className="min-h-[100px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.exclude_domains ?? "")}
                    onChange={(e) => setStr("exclude_domains", e.target.value)}
                    placeholder="example.ru\nvk.com"
                  />
                </label>
                <label className="grid gap-1">
                  <span className="text-xs font-medium text-foreground">{t("zapretForceDomains")}</span>
                  <span className="text-[11px] leading-snug text-muted-foreground">Домены (по одному в строке), к которым DPI-обход применяется принудительно, даже если они не в общих списках.</span>
                  <textarea
                    className="min-h-[80px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.force_domains ?? "")}
                    onChange={(e) => setStr("force_domains", e.target.value)}
                    placeholder="youtube.com\ndiscord.com"
                  />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  {t("zapretNfqwsConfig")}
                  <textarea
                    className="min-h-[140px] rounded-md border border-border bg-background p-2 font-mono text-[10px]"
                    value={String(settings.nfqws_config ?? "")}
                    onChange={(e) => setStr("nfqws_config", e.target.value)}
                  />
                </label>
                <p className="text-xs text-amber-400">
                  {t("zapretNfqwsWarn")}
                </p>
                <p className="text-xs text-muted-foreground">
                  {t("zapretStrategyLine", { strategy: String(settings.strategy ?? "—"), nfqws: settings.zapret_full ? t("yes") : t("no"), hostlist: String(settings.hostlist_user ?? "—") })}
                </p>
                <p className="text-xs text-muted-foreground">
                  {t("zapretCommunityLine", { state: settings.community_sync ? t("communityOn") : t("communityOff") })}
                </p>
                <label className="grid gap-1 text-muted-foreground">
                  {t("zapretStrategySelect")}
                  <select
                    className="h-9 rounded-md border border-border bg-background px-2 text-xs"
                    value={String((settings.strategy_id ?? settings.strategy_current ?? settings.strategy ?? "") as string)}
                    onChange={(e) => setSettings((s) => ({ ...s, strategy_id: e.target.value }))}
                  >
                    {((settings.strategy_presets as { id?: string; label?: string }[] | undefined) ?? []).map((p) => (
                      <option key={String(p.id ?? "")} value={String(p.id ?? "")}>
                        {String(p.label ?? p.id ?? "")}
                      </option>
                    ))}
                  </select>
                </label>
                <p className="text-xs text-muted-foreground">
                  {t("zapretActiveStrategy", { name: String(settings.strategy_current ?? settings.strategy ?? "—") })}
                </p>
                <p className="text-xs text-muted-foreground">
                  {t("zapretAfterSave")}
                </p>
              </>
            )}
            {feature === "tor" && (
              <>
                <SettingsSection
                  title="Страны выхода (Exit nodes)"
                  hint="Через какие страны выпускать зарубежный трафик. Коды в фигурных скобках, через запятую. Оставьте пустым — Tor выберет автоматически."
                >
                  <SettingField
                    label="ExitNodes — разрешённые страны выхода"
                    caption="Пример: {de},{nl},{fi} — Германия, Нидерланды, Финляндия. Пусто = любая страна."
                    value={String(settings.exit_nodes ?? "")}
                    onChange={(v) => setStr("exit_nodes", v)}
                    placeholder="{de},{nl},{fi}"
                  />
                  <SettingField
                    label="ExcludeExitNodes — запрещённые страны"
                    caption="Пример: {ru},{by},{ua} — никогда не выходить через эти страны."
                    value={String(settings.exclude_exit_nodes ?? "")}
                    onChange={(v) => setStr("exclude_exit_nodes", v)}
                    placeholder="{ru},{by},{ua}"
                  />
                  <SettingField
                    label="StrictNodes — строгий режим"
                    caption="1 = использовать ТОЛЬКО указанные ExitNodes (если недоступны — соединения не будет). 0 = мягко, как предпочтение."
                    value={String(settings.strict_nodes ?? "")}
                    onChange={(v) => setStr("strict_nodes", v)}
                    placeholder="0 или 1"
                  />
                </SettingsSection>
                <SettingsSection
                  title="Локальный порт SOCKS"
                  hint={t("torSocksPort", { port: String(settings.socks_port ?? "9050") })}
                >
                  <SettingField
                    label="SocksPort — порт прослушивания"
                    caption="Порт локального SOCKS5-прокси на 127.0.0.1. По умолчанию 9050 — меняйте только при конфликте портов."
                    value={String(settings.socks_listen ?? "")}
                    onChange={(v) => setStr("socks_listen", v)}
                    placeholder="9050"
                  />
                </SettingsSection>
                <div className="space-y-1 rounded-md border border-border bg-muted/10 p-3 text-[11px] text-muted-foreground">
                  <p>{t("torTestLine", { test: String(settings.test_socks ?? "—"), safe: String(settings.safe_socks ?? "—"), dns: String(settings.dns_port ?? "—") })}</p>
                  <p>{t("torBridgesLine", { wt: settings.webtunnel_client ? t("yes") : t("no"), bridges: settings.bridges_enabled ? t("yes") : t("no") })}</p>
                  <p className="text-amber-400">{t("torAfterSave")}</p>
                </div>
              </>
            )}
            {feature === "split" && (
              <>
                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <div>
                    <div className="font-medium">{t("splitDirectTitle")}</div>
                    <p className="text-xs text-muted-foreground">{t("splitDirectHelp")}</p>
                  </div>
                  <div className="space-y-2">
                    <button
                      type="button"
                      className="flex w-full items-center justify-between text-left rounded-md border border-border p-2 hover:bg-muted/50 transition-colors"
                      onClick={() => setCustomDirectExpanded(v => !v)}
                    >
                      <div className="text-xs font-medium text-muted-foreground">
                        {t("splitCustomDirect")}
                        {!customDirectExpanded && (
                          <span className="ml-2 text-xs text-muted-foreground/70">
                            ({String(settings.custom_direct_domains ?? "").split('\n').filter(s => s.trim()).length} элементов)
                          </span>
                        )}
                      </div>
                      <span className="text-muted-foreground text-sm">{customDirectExpanded ? '▾' : '▸'}</span>
                    </button>
                    {customDirectExpanded && (
                      <>
                        <div className="space-y-1 max-h-[120px] overflow-y-auto">
                          {String(settings.custom_direct_domains ?? "").split('\n').filter(s => s.trim()).map((domain, idx) => (
                        <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                          <span className="font-mono text-xs truncate">{domain.trim()}</span>
                          <button
                            type="button"
                            className="shrink-0 text-xs text-red-400 hover:text-red-300"
                            onClick={() => {
                              const domains = String(settings.custom_direct_domains ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                              const updated = domains.filter((d, i) => i !== idx);
                              setStr("custom_direct_domains", updated.join('\n'));
                            }}
                            title="Удалить"
                          >
                            ✕
                          </button>
                        </div>
                      ))}
                    </div>
                    <div className="flex gap-2">
                      <input
                        className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs font-mono"
                        placeholder="vk.com, 87.240.128.0/18"
                        value={newCustomDirectDomain}
                        onChange={(e) => setNewCustomDirectDomain(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') {
                            e.preventDefault();
                            const trimmed = newCustomDirectDomain.trim();
                            if (!trimmed) return;
                            const domains = String(settings.custom_direct_domains ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                            if (domains.includes(trimmed)) {
                              setNewCustomDirectDomain("");
                              return;
                            }
                            const updated = [...domains, trimmed];
                            setStr("custom_direct_domains", updated.join('\n'));
                            setNewCustomDirectDomain("");
                          }
                        }}
                      />
                      <button
                        type="button"
                        className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                        onClick={() => {
                          const trimmed = newCustomDirectDomain.trim();
                          if (!trimmed) return;
                          const domains = String(settings.custom_direct_domains ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                          if (domains.includes(trimmed)) {
                            setNewCustomDirectDomain("");
                            return;
                          }
                          const updated = [...domains, trimmed];
                          setStr("custom_direct_domains", updated.join('\n'));
                          setNewCustomDirectDomain("");
                        }}
                      >
                        Добавить
                      </button>
                    </div>
                      </>
                    )}
                  </div>
                  <div className="space-y-2">
                    <button
                      type="button"
                      className="flex w-full items-center justify-between text-left rounded-md border border-border p-2 hover:bg-muted/50 transition-colors"
                      onClick={() => setPanelHostsExpanded(v => !v)}
                    >
                      <div className="text-xs font-medium text-muted-foreground">
                        {t("splitPanelHosts")}
                        {!panelHostsExpanded && (
                          <span className="ml-2 text-xs text-muted-foreground/70">
                            ({String(settings.panel_hosts ?? "").split('\n').filter(s => s.trim()).length} элементов)
                          </span>
                        )}
                      </div>
                      <span className="text-muted-foreground text-sm">{panelHostsExpanded ? '▾' : '▸'}</span>
                    </button>
                    {panelHostsExpanded && (
                      <>
                        <div className="space-y-1 max-h-[120px] overflow-y-auto">
                          {String(settings.panel_hosts ?? "").split('\n').filter(s => s.trim()).map((host, idx) => (
                            <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                              <span className="font-mono text-xs truncate">{host.trim()}</span>
                              <button
                                type="button"
                                className="shrink-0 text-xs text-red-400 hover:text-red-300"
                                onClick={() => {
                                  const hosts = String(settings.panel_hosts ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                                  const updated = hosts.filter((h, i) => i !== idx);
                                  setStr("panel_hosts", updated.join('\n'));
                                }}
                                title="Удалить"
                              >
                                ✕
                              </button>
                            </div>
                          ))}
                        </div>
                        <div className="flex gap-2">
                          <input
                            className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs font-mono"
                            placeholder="example.com"
                            value={newPanelHost}
                            onChange={(e) => setNewPanelHost(e.target.value)}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter') {
                                e.preventDefault();
                                const trimmed = newPanelHost.trim();
                                if (!trimmed) return;
                                const hosts = String(settings.panel_hosts ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                                if (hosts.includes(trimmed)) {
                                  setNewPanelHost("");
                                  return;
                                }
                                const updated = [...hosts, trimmed];
                                setStr("panel_hosts", updated.join('\n'));
                                setNewPanelHost("");
                              }
                            }}
                          />
                          <button
                            type="button"
                            className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                            onClick={() => {
                              const trimmed = newPanelHost.trim();
                              if (!trimmed) return;
                              const hosts = String(settings.panel_hosts ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                              if (hosts.includes(trimmed)) {
                                setNewPanelHost("");
                                return;
                              }
                              const updated = [...hosts, trimmed];
                              setStr("panel_hosts", updated.join('\n'));
                              setNewPanelHost("");
                            }}
                          >
                            Добавить
                          </button>
                        </div>
                      </>
                    )}
                  </div>
                  <div className="space-y-2">
                    <button
                      type="button"
                      className="flex w-full items-center justify-between text-left rounded-md border border-border p-2 hover:bg-muted/50 transition-colors"
                      onClick={() => setPanelCidrsExpanded(v => !v)}
                    >
                      <div className="text-xs font-medium text-muted-foreground">
                        {t("splitPanelCidrs")}
                        {!panelCidrsExpanded && (
                          <span className="ml-2 text-xs text-muted-foreground/70">
                            ({String(settings.panel_cidrs ?? "").split('\n').filter(s => s.trim()).length} элементов)
                          </span>
                        )}
                      </div>
                      <span className="text-muted-foreground text-sm">{panelCidrsExpanded ? '▾' : '▸'}</span>
                    </button>
                    {panelCidrsExpanded && (
                      <>
                        <div className="space-y-1 max-h-[120px] overflow-y-auto">
                          {String(settings.panel_cidrs ?? "").split('\n').filter(s => s.trim()).map((cidr, idx) => (
                            <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                              <span className="font-mono text-xs truncate">{cidr.trim()}</span>
                              <button
                                type="button"
                                className="shrink-0 text-xs text-red-400 hover:text-red-300"
                                onClick={() => {
                                  const cidrs = String(settings.panel_cidrs ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                                  const updated = cidrs.filter((c, i) => i !== idx);
                                  setStr("panel_cidrs", updated.join('\n'));
                                }}
                                title="Удалить"
                              >
                                ✕
                              </button>
                            </div>
                          ))}
                        </div>
                        <div className="flex gap-2">
                          <input
                            className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs font-mono"
                            placeholder="10.0.0.0/8"
                            value={newPanelCidr}
                            onChange={(e) => setNewPanelCidr(e.target.value)}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter') {
                                e.preventDefault();
                                const trimmed = newPanelCidr.trim();
                                if (!trimmed) return;
                                const cidrs = String(settings.panel_cidrs ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                                if (cidrs.includes(trimmed)) {
                                  setNewPanelCidr("");
                                  return;
                                }
                                const updated = [...cidrs, trimmed];
                                setStr("panel_cidrs", updated.join('\n'));
                                setNewPanelCidr("");
                              }
                            }}
                          />
                          <button
                            type="button"
                            className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                            onClick={() => {
                              const trimmed = newPanelCidr.trim();
                              if (!trimmed) return;
                              const cidrs = String(settings.panel_cidrs ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                              if (cidrs.includes(trimmed)) {
                                setNewPanelCidr("");
                                return;
                              }
                              const updated = [...cidrs, trimmed];
                              setStr("panel_cidrs", updated.join('\n'));
                              setNewPanelCidr("");
                            }}
                          >
                            Добавить
                          </button>
                        </div>
                      </>
                    )}
                  </div>
                </section>

                <section data-ui="split-apply-compact" className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <div className="font-medium">Применить изменения</div>
                      <p className="text-xs text-muted-foreground">Синхронизирует конфиг, логи и применяет роутинг</p>
                    </div>
                    <button
                      type="button"
                      className="rounded border border-primary px-3 py-2 text-xs text-primary hover:bg-primary/10 disabled:opacity-50"
                      disabled={saving}
                      onClick={() => void splitApplyAll()}
                    >
                      Применить
                    </button>
                  </div>
                  {splitAnalyzeMsg && (
                    <p className={`text-xs ${splitAnalyzeMsg.startsWith("✓") ? "text-emerald-400" : splitAnalyzeMsg.includes("...") ? "text-blue-400" : "text-red-400"}`}>
                      {splitAnalyzeMsg}
                    </p>
                  )}
                  <p className="text-[10px] text-muted-foreground">{t("splitRestartHint")}</p>
                </section>

                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <div className="font-medium">{t("splitAnalyzeTitle")}</div>
                      <p className="text-xs text-muted-foreground">{t("splitAnalyzeHelp")}</p>
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <input
                      className="h-9 flex-1 rounded-md border border-border bg-background px-2 text-xs"
                      placeholder="vk.com, meet.example.ru, 1.2.3.4, 1.2.3.0/24"
                      value={splitAnalyzeTarget}
                      onChange={(e) => setSplitAnalyzeTarget(e.target.value)}
                    />
                    <button type="button" className="rounded border border-primary px-3 py-1 text-xs text-primary" disabled={saving} onClick={() => void splitAnalyze()}>
                      {t("splitAnalyzeButton")}
                    </button>
                  </div>
                  {splitAnalysis && (
                    <div className="rounded border border-border bg-background p-2 text-xs space-y-2">
                      <div className="font-medium">{t("splitAnalyzeResult", { target: String(splitAnalysis.normalized ?? splitAnalysis.input ?? "") })}</div>
                      <div className="grid gap-2 md:grid-cols-2">
                        <div>
                          <div className="text-muted-foreground">{t("splitFoundDomains")}</div>
                          <LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2" title={t("splitProvenanceHint")}>{splitAnalysisDomains.slice(0, 80).map((domain) => splitDomainWithProvenance(domain, splitAnalysisProvenance)).join("\n") || t("empty")}</LogScrollPre>
                        </div>
                        <div>
                          <div className="text-muted-foreground">{t("splitFoundCidrs")}</div>
                          <LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2">{splitAnalysisCidrs.slice(0, 80).join("\n") || t("empty")}</LogScrollPre>
                        </div>
                      </div>
                      {String(splitAnalysis.whois ?? "") && <LogScrollPre className="max-h-[90px] overflow-y-auto rounded bg-muted p-2">{String(splitAnalysis.whois)}</LogScrollPre>}
                      <div className="space-y-1">
                        <div className="text-[10px] uppercase tracking-wide text-muted-foreground">{t("splitApplyDestination")}</div>
                        <div className="relative inline-flex max-w-full">
                          <button type="button" className="rounded-l border border-primary px-3 py-1.5 text-left text-xs text-primary hover:bg-primary/10" disabled={saving} onClick={() => void splitApplyAnalysis(splitApplyTarget)}>
                            {splitApplySelection.label}
                          </button>
                          <button type="button" className="rounded-r border border-l-0 border-primary px-2 py-1 text-xs text-primary hover:bg-primary/10" disabled={saving} onClick={() => setSplitApplyMenuOpen((v) => !v)} aria-label={t("splitApplyChoose")}>
                            ▾
                          </button>
                          {splitApplyMenuOpen && (
                            <div className="absolute left-0 top-9 z-20 w-96 max-w-[80vw] rounded border border-border bg-background p-1 shadow-lg">
                              {Object.entries(splitApplyOptions).map(([key, option]) => (
                                <button key={key} type="button" className={`block w-full rounded px-2 py-2 text-left text-xs hover:bg-muted ${splitApplyTarget === key ? "bg-primary/10 text-primary" : ""}`} onClick={() => { setSplitApplyTarget(key); setSplitApplyMenuOpen(false); }}>
                                  <span className="block font-medium">{option.label}</span>
                                  <span className="block pt-0.5 text-[10px] text-muted-foreground">{option.hint}</span>
                                </button>
                              ))}
                            </div>
                          )}
                        </div>
                        <p className="text-[10px] text-muted-foreground">{splitApplySelection.hint}</p>
                      </div>
                    </div>
                  )}
                  {splitAnalyzeMsg && <p className={`text-xs ${splitAnalyzeMsg === t("splitAnalyzeDone") || splitAnalyzeMsg === t("splitApplyDone") || splitAnalyzeMsg === t("splitSyncDone") || splitAnalyzeMsg === t("splitSyncLogsDone") || splitAnalyzeMsg.startsWith(t("splitExpandDone")) || splitAnalyzeMsg === t("splitApplyRoutingDone") ? "text-emerald-400" : "text-muted-foreground"}`}>{splitAnalyzeMsg}</p>}
                </section>

                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <button
                    type="button"
                    className="flex w-full items-center justify-between text-left"
                    onClick={() => setSplitAutoGroupsCollapsed(v => !v)}
                  >
                    <div>
                      <div className="font-medium">{t("splitAutoGroupsTitle")}</div>
                      <p className="text-xs text-muted-foreground">
                        {splitAutoGroupsCollapsed
                          ? `${splitFamilies.length} семейств · ${splitGroups.length} ${t("splitFamilyGroups")} · ${splitGroups.reduce((sum, g) => sum + (Array.isArray(g.selected_domains) ? g.selected_domains.length : Array.isArray(g.domains) ? g.domains.length : 0), 0)} доменов`
                          : t("splitAutoGroupsHelp")}
                      </p>
                    </div>
                    <span className="text-muted-foreground">{splitAutoGroupsCollapsed ? '▸' : '▾'}</span>
                  </button>
                  {!splitAutoGroupsCollapsed && (
                    splitFamilies.length === 0 ? (
                      <p className="text-xs text-muted-foreground">{t("splitNoGroups")}</p>
                    ) : (
                      <div className="space-y-2">
                        {splitFamilies.map((family) => {
                          const familyKey = `family:${family.id}`;
                          const familyOpen = Boolean(splitExpanded[familyKey]);
                          const familyDomains = family.groups.reduce((sum, g) => sum + (Array.isArray(g.selected_domains) ? g.selected_domains.length : Array.isArray(g.domains) ? g.domains.length : 0), 0);
                          const familyCidrs = family.groups.reduce((sum, g) => sum + (Array.isArray(g.selected_cidrs) ? g.selected_cidrs.length : Array.isArray(g.cidrs) ? g.cidrs.length : 0), 0);
                          return (
                            <div key={family.id} className="rounded border border-border bg-background/70 p-2 text-xs">
                              <button type="button" className="flex w-full items-center justify-between gap-2 text-left" onClick={() => setSplitExpanded((s) => ({ ...s, [familyKey]: !familyOpen }))}>
                                <span className="font-semibold">{familyOpen ? '▾' : '▸'} {family.label}</span>
                                <span className="text-muted-foreground">{family.groups.length} {t("splitFamilyGroups")} · {familyDomains} domains · {familyCidrs} cidr</span>
                              </button>
                              {familyOpen && (
                                <div className="mt-2 space-y-2 border-l border-border pl-2">
                                  {family.groups.map((g) => {
                                    const id = String(g.id ?? g.target ?? g.label ?? Math.random());
                                    const domains = Array.isArray(g.selected_domains) ? g.selected_domains.map(String) : Array.isArray(g.domains) ? g.domains.map(String) : [];
                                    const cidrs = Array.isArray(g.selected_cidrs) ? g.selected_cidrs.map(String) : Array.isArray(g.cidrs) ? g.cidrs.map(String) : [];
                                    const provenance = g.domain_provenance && typeof g.domain_provenance === "object" ? g.domain_provenance as Record<string, unknown> : {};
                                    const domainLines = domains.map((domain) => splitDomainWithProvenance(domain, provenance));
                                    const open = Boolean(splitExpanded[id]);
                                    return (
                                      <div key={id} className="rounded border border-border bg-background p-2">
                                        <button type="button" className="flex w-full items-center justify-between gap-2 text-left" onClick={() => setSplitExpanded((s) => ({ ...s, [id]: !open }))}>
                                          <span className="font-medium">{open ? '▾' : '▸'} {String(g.label ?? g.target ?? id)}</span>
                                          <span className="text-muted-foreground">{String(g.source ?? "auto")} · {domains.length} domains · {cidrs.length} cidr</span>
                                        </button>
                                        {open && (
                                          <div className="mt-2 grid gap-2 md:grid-cols-2">
                                            <div>
                                              <div className="mb-1 text-muted-foreground" title={t("splitProvenanceHint")}>{t("splitProvenanceTitle")}</div>
                                              <LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2">{domainLines.join("\n") || t("empty")}</LogScrollPre>
                                            </div>
                                            <LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2">{cidrs.join("\n") || t("empty")}</LogScrollPre>
                                          </div>
                                        )}
                                      </div>
                                    );
                                  })}
                                </div>
                              )}
                            </div>
                          );
                        })}
                      </div>
                    )
                  )}
                </section>

                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <div className="font-medium">{t("splitAdvancedTitle")}</div>
                  <label className="grid gap-1 text-muted-foreground">
                    {t("splitForceTor")}
                    <div className="space-y-2">
                      <button
                        type="button"
                        className="flex w-full items-center justify-between text-left rounded-md border border-border p-2 hover:bg-muted/50 transition-colors"
                        onClick={() => setForceTorExpanded(v => !v)}
                      >
                        <div className="text-xs font-medium">
                          {!forceTorExpanded && (
                            <span className="text-xs text-muted-foreground/70">
                              ({String(settings.force_tor_domains ?? "").split('\n').filter(s => s.trim()).length} элементов)
                            </span>
                          )}
                        </div>
                        <span className="text-muted-foreground text-sm">{forceTorExpanded ? '▾' : '▸'}</span>
                      </button>
                      {forceTorExpanded && (
                        <>
                          <div className="space-y-1 max-h-[120px] overflow-y-auto">
                            {String(settings.force_tor_domains ?? "").split('\n').filter(s => s.trim()).map((domain, idx) => (
                              <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                                <span className="font-mono text-xs truncate">{domain.trim()}</span>
                                <button
                                  type="button"
                                  className="shrink-0 text-xs text-red-400 hover:text-red-300"
                                  onClick={() => {
                                    const domains = String(settings.force_tor_domains ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                                    const updated = domains.filter((d, i) => i !== idx);
                                    setStr("force_tor_domains", updated.join('\n'));
                                  }}
                                  title="Удалить"
                                >
                                  ✕
                                </button>
                              </div>
                            ))}
                          </div>
                          <div className="flex gap-2">
                            <input
                              className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs font-mono"
                              placeholder="example.com"
                              value={newForceTorDomain}
                              onChange={(e) => setNewForceTorDomain(e.target.value)}
                              onKeyDown={(e) => {
                                if (e.key === 'Enter') {
                                  e.preventDefault();
                                  const trimmed = newForceTorDomain.trim();
                                  if (!trimmed) return;
                                  const domains = String(settings.force_tor_domains ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                                  if (domains.includes(trimmed)) {
                                    setNewForceTorDomain("");
                                    return;
                                  }
                                  const updated = [...domains, trimmed];
                                  setStr("force_tor_domains", updated.join('\n'));
                                  setNewForceTorDomain("");
                                }
                              }}
                            />
                            <button
                              type="button"
                              className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                              onClick={() => {
                                const trimmed = newForceTorDomain.trim();
                                if (!trimmed) return;
                                const domains = String(settings.force_tor_domains ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                                if (domains.includes(trimmed)) {
                                  setNewForceTorDomain("");
                                  return;
                                }
                                const updated = [...domains, trimmed];
                                setStr("force_tor_domains", updated.join('\n'));
                                setNewForceTorDomain("");
                              }}
                            >
                              Добавить
                            </button>
                          </div>
                        </>
                      )}
                    </div>
                  </label>
                  <label className="grid gap-1 text-muted-foreground">
                    {t("splitBlockedTor")}
                    <div className="space-y-2">
                      <button
                        type="button"
                        className="flex w-full items-center justify-between text-left rounded-md border border-border p-2 hover:bg-muted/50 transition-colors"
                        onClick={() => setBlockedTorExpanded(v => !v)}
                      >
                        <div className="text-xs font-medium">
                          {!blockedTorExpanded && (
                            <span className="text-xs text-muted-foreground/70">
                              ({String(settings.blocked_tor_domains ?? "").split('\n').filter(s => s.trim()).length} элементов)
                            </span>
                          )}
                        </div>
                        <span className="text-muted-foreground text-sm">{blockedTorExpanded ? '▾' : '▸'}</span>
                      </button>
                      {blockedTorExpanded && (
                        <>
                          <div className="space-y-1 max-h-[120px] overflow-y-auto">
                            {String(settings.blocked_tor_domains ?? "").split('\n').filter(s => s.trim()).map((domain, idx) => (
                              <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                                <span className="font-mono text-xs truncate">{domain.trim()}</span>
                                <button
                                  type="button"
                                  className="shrink-0 text-xs text-red-400 hover:text-red-300"
                                  onClick={() => {
                                    const domains = String(settings.blocked_tor_domains ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                                    const updated = domains.filter((d, i) => i !== idx);
                                    setStr("blocked_tor_domains", updated.join('\n'));
                                  }}
                                  title="Удалить"
                                >
                                  ✕
                                </button>
                              </div>
                            ))}
                          </div>
                          <div className="flex gap-2">
                            <input
                              className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs font-mono"
                              placeholder="example.com"
                              value={newBlockedTorDomain}
                              onChange={(e) => setNewBlockedTorDomain(e.target.value)}
                              onKeyDown={(e) => {
                                if (e.key === 'Enter') {
                                  e.preventDefault();
                                  const trimmed = newBlockedTorDomain.trim();
                                  if (!trimmed) return;
                                  const domains = String(settings.blocked_tor_domains ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                                  if (domains.includes(trimmed)) {
                                    setNewBlockedTorDomain("");
                                    return;
                                  }
                                  const updated = [...domains, trimmed];
                                  setStr("blocked_tor_domains", updated.join('\n'));
                                  setNewBlockedTorDomain("");
                                }
                              }}
                            />
                            <button
                              type="button"
                              className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                              onClick={() => {
                                const trimmed = newBlockedTorDomain.trim();
                                if (!trimmed) return;
                                const domains = String(settings.blocked_tor_domains ?? "").split('\n').filter(s => s.trim()).map(s => s.trim());
                                if (domains.includes(trimmed)) {
                                  setNewBlockedTorDomain("");
                                  return;
                                }
                                const updated = [...domains, trimmed];
                                setStr("blocked_tor_domains", updated.join('\n'));
                                setNewBlockedTorDomain("");
                              }}
                            >
                              Добавить
                            </button>
                          </div>
                        </>
                      )}
                    </div>
                  </label>
                  <div className="flex items-center justify-between gap-3 text-sm">
                    <span>{t("splitCidrOnly")}</span>
                    <OlcToggleButton checked={Boolean(settings.cidr_only)} onChange={(e) => setBool("cidr_only", e.target.checked)} />
                  </div>
                </section>

                <p className="text-xs text-muted-foreground">
                  {t("splitRuDirectLine", { count: String(settings.ru_direct_count ?? "?"), file: String(settings.direct_cidrs_file ?? "—") })}
                </p>
                <button
                  type="button"
                  className="rounded border border-border px-2 py-1 text-xs hover:bg-muted"
                  disabled={saving}
                  onClick={async () => {
                    setSaving(true);
                    setMsg("");
                    try {
                      const res = await fetch(`/api/settings/${apiName}`, {
                        method: "PUT",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({ ...settings, refresh_lists: true }),
                      });
                      if (!res.ok) throw new Error(`HTTP ${res.status}`);
                      setMsg(t("splitRefreshStarted"));
                    } catch (e) {
                      setMsg(e instanceof Error ? e.message : String(e));
                    } finally {
                      setSaving(false);
                    }
                  }}
                >
                  {t("splitRefreshLists")}
                </button>
              </>
            )}
            {feature === "olcrtc" && (
              <>
                <button
                  type="button"
                  className="w-fit rounded-md border border-border bg-muted px-3 py-2 text-xs hover:bg-muted/80"
                  onClick={() => setInstanceDefaultsOpen(true)}
                >
                  {t("instanceDefaultsBtn")}
                </button>
                <div className="flex items-center justify-between gap-3 text-xs">
                  <span>{t("olcrtcJitsiTls")}</span>
                  <OlcToggleButton checked={Boolean(settings.jitsi_insecure_tls)} onChange={(e) => setBool("jitsi_insecure_tls", e.target.checked)} />
                </div>
                <label className="grid gap-1 text-muted-foreground">
                  {t("olcrtcPublicUrl")}
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs" value={String(settings.public_url ?? "")} onChange={(e) => setStr("public_url", e.target.value)} placeholder="https://vps.example:8888" />
                </label>
                <div className="grid gap-2 md:grid-cols-2">
                  <label className="grid gap-1 text-muted-foreground">
                    {t("olcrtcDefaultCarrier")}
                    <select className="h-9 rounded-md border border-border bg-background px-2 text-xs" value={String(settings.default_carrier ?? "")} onChange={(e) => setStr("default_carrier", e.target.value)}>
                      <option value="">{t("olcrtcNotSet")}</option>
                      <option value="jitsi">jitsi</option>
                      <option value="wbstream">wbstream</option>
                      <option value="telemost">telemost</option>
                    </select>
                  </label>
                  <label className="grid gap-1 text-muted-foreground">
                    {t("olcrtcDefaultTransport")}
                    <select className="h-9 rounded-md border border-border bg-background px-2 text-xs" value={String(settings.default_transport ?? "")} onChange={(e) => setStr("default_transport", e.target.value)}>
                      <option value="">{t("olcrtcNotSet")}</option>
                      <option value="datachannel">datachannel</option>
                      <option value="vp8channel">vp8channel</option>
                      <option value="seichannel">seichannel</option>
                    </select>
                  </label>
                </div>
                <label className="grid gap-1 text-muted-foreground">
                  Default link
                  <select className="h-9 rounded-md border border-border bg-background px-2 text-xs" value={String(settings.default_link ?? "")} onChange={(e) => setStr("default_link", e.target.value)}>
                    <option value="">{t("olcrtcNotSet")}</option>
                    <option value="tor">tor</option>
                    <option value="direct">direct</option>
                  </select>
                </label>
                <div className="grid gap-3 rounded-md border border-border bg-background p-3">
                  <div className="flex items-center justify-between gap-3 text-sm font-medium text-foreground">
                    <span>Глобальный upstream SOCKS5 для всех клиентов и инстансов</span>
                    <OlcToggleButton  checked={Boolean(settings.global_socks_enabled)} onChange={(e) => setBool("global_socks_enabled", e.target.checked)} />
                  </div>
                  <p className="text-[11px] text-amber-300">
                    Имеет наивысший приоритет. Настройки SOCKS5 клиентов и инстансов сохраняются, но временно скрываются.
                    Это не локальный SOCKS-порт OlcBox; при ошибке прокси прямого обхода нет.
                  </p>
                  {Boolean(settings.global_socks_enabled) ? (
                    <>
                      <div className="grid gap-2 md:grid-cols-2">
                        <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" value={String(settings.global_socks_addr ?? "")} onChange={(e) => setStr("global_socks_addr", e.target.value)} placeholder="proxy.example.org" />
                        <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" type="number" min="1" max="65535" value={String(settings.global_socks_port ?? "")} onChange={(e) => setStr("global_socks_port", e.target.value)} placeholder="1080" />
                        <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" value={String(settings.global_socks_user ?? "")} onChange={(e) => setStr("global_socks_user", e.target.value)} placeholder="User" autoComplete="off" />
                        <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" type="password" value={String(settings.global_socks_pass ?? "")} onChange={(e) => setStr("global_socks_pass", e.target.value)} placeholder="Password" autoComplete="new-password" />
                      </div>
                      <select className="h-9 rounded-md border border-border bg-background px-2 text-xs" value={String(settings.global_socks_routing ?? "split")} onChange={(e) => setStr("global_socks_routing", e.target.value)}>
                        <option value="split">Сохранять split/Tor/Zapret-правила (рекомендуется)</option>
                        <option value="all">Весь трафик через этот SOCKS5</option>
                      </select>
                    </>
                  ) : null}
                </div>
                <label className="grid gap-1 text-muted-foreground">
                  Tor signaling proxy (optional)
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" value={String(settings.tor_proxy ?? "")} onChange={(e) => setStr("tor_proxy", e.target.value)} placeholder="user:pass@host:port" />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  WebRTC signaling proxy (optional)
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" value={String(settings.webrtc_proxy ?? "")} onChange={(e) => setStr("webrtc_proxy", e.target.value)} placeholder="user:pass@host:port" />
                </label>
                <p className="text-xs text-muted-foreground">{t("olcrtcBranchPin")} <code>{String(settings.olcrtc_pinned_sha ?? "").slice(0, 12) || "—"}</code></p><p className="text-xs text-muted-foreground">{t("olcrtcAfterSave")}</p>
              </>
            )}
            {feature === "warp" && (
              <>
                <p className="text-xs text-amber-400">{t("warpTorExclusive")}</p>
                <label className="grid gap-1 text-muted-foreground">
                  {t("warpProxy")}
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" value={String(settings.proxy ?? "127.0.0.1:40000")} onChange={(e) => setStr("proxy", e.target.value)} placeholder="127.0.0.1:40000" />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  Mode
                  <select
                    className="h-9 rounded-md border border-border bg-background px-2 text-xs"
                    value={String(settings.mode ?? "proxy")}
                    onChange={(e) => setStr("mode", e.target.value)}
                  >
                    <option value="proxy">proxy (safe)</option>
                    <option value="tun" disabled>tun (blocked by safety)</option>
                  </select>
                </label>
                <div className="flex items-center gap-2 text-xs">
                  <OlcToggleButton  checked={Boolean(settings.autoconnect ?? true)} onChange={(e) => setBool("autoconnect", e.target.checked)} />
                  {t("warpAutoconnect")}
                </div>
                <div className="flex items-center gap-2 text-xs">
                  <OlcToggleButton  checked={Boolean(settings.warp_plus)} onChange={(e) => setBool("warp_plus", e.target.checked)} />
                  {t("warpPlus")}
                </div>
                <label className="grid gap-1 text-muted-foreground">
                  {t("warpLicense")}
                  <input
                    className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono"
                    value={String(settings.license_key ?? "")}
                    onChange={(e) => setStr("license_key", e.target.value)}
                    placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                  />
                </label>
                <p className="text-xs text-muted-foreground">
                  {t("warpStatusLine", { installed: settings.installed ? t("yes") : t("no"), connected: settings.connected ? t("yes") : t("no"), profile: settings.profile_enabled ? t("warpInProfile") : "" })}
                </p>
                <p className="text-xs text-amber-400">{t("warpSafety")}</p>
              </>
            )}
            {(feature === "webtunnel" || feature === "bridges") && (
              <BridgesSettingsFields settings={settings} setSettings={setSettings} setMsg={setMsg} onReload={async () => { const res = await fetch(`/api/settings/bridges`, { cache: "no-store" }); const raw = await res.text(); let body: { settings?: Record<string, unknown> } = {}; try { body = (raw ? JSON.parse(raw) : {}) as { settings?: Record<string, unknown> }; } catch { body = {}; } setSettings(body.settings ?? {}); }} />
            )}
          </>
        )}
        <div className="flex items-center justify-between gap-2">
          <span className="text-xs">
            {saving
              ? <span className="text-muted-foreground">Сохраняю…</span>
              : msg === t("saved")
                ? <span className="text-emerald-400">Сохранено ✓</span>
                : msg
                  ? <span className="text-destructive">{msg}</span>
                  : <span className="text-muted-foreground">Изменения сохраняются автоматически</span>}
          </span>
          <button
            type="button"
            className="rounded-md border border-border px-3 py-2 text-sm hover:bg-muted"
            onClick={() => { flushSave(); onClose(); }}
          >
            {t("close")}
          </button>
        </div>
      </div>
    </Modal>
  );
}

function notifyFeaturesChanged() {
  window.dispatchEvent(new CustomEvent("olc-features-changed"));
}

async function featuresFetch(): Promise<Response> {
  // The manager restarts ~2s after a toggle and is unreachable ~8-10s. Try a few
  // times with per-attempt timeouts so a background refresh eventually succeeds.
  const attempt = async (timeoutMs: number): Promise<Response> => {
    const ctrl = new AbortController();
    const timer = window.setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      return await fetch("/api/features", { cache: "no-store", signal: ctrl.signal });
    } finally {
      window.clearTimeout(timer);
    }
  };
  let lastErr: unknown;
  for (let i = 0; i < 8; i++) {
    try {
      const res = await attempt(4000);
      if (res.ok) return res;
      lastErr = new Error(`HTTP ${res.status}`);
    } catch (e) {
      lastErr = e;
    }
    await new Promise((r) => window.setTimeout(r, 2000));
  }
  throw lastErr ?? new Error("features unavailable");
}

async function postFeatureToggle(name: FeatureName, enabled: boolean, flags?: Record<FeatureName, boolean>) {
  if (name === "split" && enabled && flags && !flags.tor) {
    throw new Error("Сначала включите Tor — split маршрутизирует остальной трафик через exit");
  }
  if ((name === "bridges" || name === "webtunnel") && enabled && flags && !flags.tor) {
    throw new Error("Сначала включите Tor — мосты (obfs4/webtunnel) работают только поверх Tor");
  }
  if (name === "warp" && enabled && flags && flags.tor) {
    throw new Error("WARP недоступен при включённом Tor — сначала выключите Tor");
  }
  if (name === "tor" && enabled && flags && flags.warp) {
    throw new Error("Tor недоступен при включённом WARP — сначала выключите WARP");
  }
  const res = await fetch(`/api/features/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ enabled }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok && !body?.warning) {
    throw new Error(body?.error || `HTTP ${res.status}`);
  }
  notifyFeaturesChanged();
  return body;
}


type Capabilities = {
  panel_version?: string;
  deploy_profile?: string;
  components?: Record<string, { installed?: boolean; enabled?: boolean; label?: string; requires?: string[] }>;
};

function useCapabilities() {
  const [caps, setCaps] = useState<Capabilities | null>(null);
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch("/api/capabilities", { cache: "no-store" });
        if (!res.ok) return;
        const body = (await res.json()) as Capabilities;
        if (!cancelled) setCaps(body);
      } catch {
        /* ignore */
      }
    })();
    const reloadCaps = async () => {
      try {
        const res = await fetch("/api/capabilities", { cache: "no-store" });
        if (!res.ok) return;
        const body = (await res.json()) as Capabilities;
        if (!cancelled) setCaps(body);
      } catch {
        /* ignore */
      }
    };
    const onCapsChanged = () => void reloadCaps();
    window.addEventListener("olc-capabilities-changed", onCapsChanged);
    const iv = window.setInterval(() => void reloadCaps(), 30_000);
    return () => {
      cancelled = true;
      window.clearInterval(iv);
      window.removeEventListener("olc-capabilities-changed", onCapsChanged);
    };
  }, []); /* capabilitiesRefresh30s */
  const visible = (name: FeatureName) => {
    const key = name === "webtunnel" ? "bridges" : name === "warp" ? "warp" : name;
    const c = caps?.components?.[key];
    if (!c) return name !== "warp";
    if (key === "warp") return c.installed === true;
    return c.installed !== false;
  };
  const reloadCapsNow = async () => {
    try {
      const res = await fetch("/api/capabilities", { cache: "no-store" });
      if (!res.ok) return;
      const body = (await res.json()) as Capabilities;
      setCaps(body);
    } catch {
      /* ignore */
    }
  };
  return { caps, visible, reloadCaps: reloadCapsNow };
}


function HeaderNetworkToggles() { // NetworkUIV3
  const { t } = usePanelLang();
  const { visible } = useCapabilities();
  const [flags, setFlags] = useState<Record<FeatureName, boolean> | null>(null);
  const [busy, setBusy] = useState<FeatureName | null>(null);
  const [logFeature, setLogFeature] = useState<FeatureName | null>(null);
  const [settingsFeature, setSettingsFeature] = useState<FeatureName | null>(null);
  const [err, setErr] = useState("");

  const load = async () => {
    try {
      const res = await fetch("/api/features", { cache: "no-store" });
      if (!res.ok) return;
      const body = (await res.json()) as { flags?: Record<FeatureName, boolean> };
      setFlags(body.flags ?? null);
      setErr("");
    } catch (e) {
      setErr(String(e));
    }
  };

  useEffect(() => {
    void load();
    const onChange = () => void load();
    window.addEventListener("olc-features-changed", onChange);
    return () => window.removeEventListener("olc-features-changed", onChange);
  }, []);

  const toggle = async (name: FeatureName) => {
    if (!flags) return;
    setBusy(name);
    setErr("");
    try {
      const enabled = !flags[name];
      const body = await postFeatureToggle(name, enabled, flags);
      // The POST already returns the new flags; apply them and release the button
      // right away instead of blocking on a GET during the manager restart window.
      if (body && body.flags) setFlags(body.flags as Record<FeatureName, boolean>);
      setBusy(null);
      // Reconcile in the background once the manager is back (non-blocking).
      void featuresFetch()
        .then((res) => res.json())
        .then((b) => { if (b && b.flags) setFlags(b.flags as Record<FeatureName, boolean>); })
        .catch(() => {});
      return;
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  };

  const items: { name: FeatureName; label: string }[] = [
    { name: "zapret", label: "Zp" },
    { name: "tor", label: "Tor" },
    { name: "split", label: "Sp" },
    { name: "bridges", label: "Мосты" },
    { name: "warp", label: "WARP" },
  ];

  return (
    <div className="flex w-full min-w-0 flex-col gap-1">
      <div className="flex flex-wrap items-center gap-2 rounded-md border border-border bg-muted/40 px-2 py-1">
        {items.filter((it) => visible(it.name)).map((it) => {
          const on = Boolean(flags?.[it.name]);
          const splitBlocked = it.name === "split" && !flags?.tor;
          const bridgesBlocked = it.name === "bridges" && !flags?.tor;
          const warpBlocked = it.name === "warp" && Boolean(flags?.tor);
          const torBlocked = it.name === "tor" && Boolean(flags?.warp);
          const blocked = splitBlocked || bridgesBlocked || warpBlocked || torBlocked;
          const blockTitle = warpBlocked
            ? "WARP недоступен при включённом Tor"
            : torBlocked
              ? "Tor недоступен при включённом WARP"
              : splitBlocked || bridgesBlocked
                ? "Сначала Tor"
                : `${it.name}: ${on ? "on" : "off"}`;
          return (
            <div key={it.name} className="flex items-center gap-0.5 rounded border border-border/60 bg-background/50 pr-0.5">
              <button
                type="button"
                title={blockTitle}
                className={`inline-flex h-7 min-w-[2rem] items-center justify-center rounded-l px-1.5 text-[11px] font-medium disabled:opacity-50 ${
                  on ? "bg-emerald-500/25 text-emerald-300" : "text-muted-foreground hover:bg-muted"
                }`}
                disabled={busy !== null || blocked}
                onClick={() => void toggle(it.name)}
              >
                {busy === it.name ? "…" : it.label}
              </button>
              <button
                type="button"
                title="Логи"
                className="inline-flex h-7 w-7 items-center justify-center text-muted-foreground hover:bg-muted hover:text-foreground"
                onClick={() => setLogFeature(it.name)}
              >
                <Terminal className="h-3.5 w-3.5" />
              </button>
              <button
                type="button"
                title="Настройки"
                className="inline-flex h-7 w-7 items-center justify-center text-muted-foreground hover:bg-muted hover:text-foreground"
                onClick={() => setSettingsFeature(it.name)}
              >
                <Settings className="h-3.5 w-3.5" />
              </button>
            </div>
          );
        })}
      </div>
      {err && <p className="max-w-full truncate text-xs text-red-400" title={err}>{err}</p>}
      {logFeature && <FeatureLogsModal feature={logFeature} onClose={() => setLogFeature(null)} />}
      {settingsFeature && <FeatureSettingsModal feature={settingsFeature} onClose={() => setSettingsFeature(null)} />}
    </div>
  );
}

function FeaturesPanel() { // FeaturesPanelV2 NetworkUIV3
  const { t } = usePanelLang();
  const { visible } = useCapabilities();
  const [data, setData] = useState<FeaturesResponse | null>(null);
  const [busy, setBusy] = useState<FeatureName | null>(null);
  const [err, setErr] = useState<string>("");
  const [collapsed, setCollapsed] = useState<boolean>(() => {
    try {
      return localStorage.getItem("olc-network-bypass-collapsed") === "1";
    } catch {
      return false;
    }
  });
  const [logFeature, setLogFeature] = useState<FeatureName | null>(null);
  const [settingsFeature, setSettingsFeature] = useState<FeatureName | null>(null);
  const featureModalRestoredRef = useRef(false);

  useEffect(() => {
    if (logFeature) {
      try { window.localStorage.setItem("olc-active-feature-modal-v1", JSON.stringify({ k: "log", f: logFeature })); } catch { /* */ }
    } else if (settingsFeature) {
      try { window.localStorage.setItem("olc-active-feature-modal-v1", JSON.stringify({ k: "settings", f: settingsFeature })); } catch { /* */ }
    } else if (featureModalRestoredRef.current) {
      try { window.localStorage.removeItem("olc-active-feature-modal-v1"); } catch { /* */ }
    }
  }, [logFeature, settingsFeature]);

  const load = async () => {
    try {
      const res = await fetch("/api/features", { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setData(await res.json());
      if (!featureModalRestoredRef.current) {
        featureModalRestoredRef.current = true;
        try {
          const raw = window.localStorage.getItem("olc-active-feature-modal-v1");
          if (raw) {
            const d = JSON.parse(raw);
            if (d?.k === "log" && d.f) setLogFeature(d.f as FeatureName);
            else if (d?.k === "settings" && d.f) setSettingsFeature(d.f as FeatureName);
          }
        } catch { /* */ }
      }
      setErr("");
    } catch (e) {
      setErr(String(e));
    }
  };

  useEffect(() => {
    void load();
    const onChange = () => void load();
    window.addEventListener("olc-features-changed", onChange);
    return () => window.removeEventListener("olc-features-changed", onChange);
  }, []);

  const toggle = async (name: FeatureName, enabled: boolean) => {
    setBusy(name);
    setErr("");
    try {
      const body = await postFeatureToggle(name, enabled, data?.flags);
      // Apply flags from the POST response and release the button immediately;
      // don't block on a GET while the manager is restarting.
      if (body && body.flags) setData((prev: any) => ({ ...(prev ?? {}), flags: body.flags }));
      setBusy(null);
      void featuresFetch()
        .then((res) => res.json())
        .then((b) => { if (b) setData(b); })
        .catch(() => {});
      return;
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  };

  if (!data && !err) {
    return null;
  }

  const rows: { name: FeatureName; label: string; hint: string }[] = [
    { name: "zapret", label: "Zapret", hint: "DPI bypass for blocked .ru on direct egress" },
    { name: "tor",     label: "Tor",     hint: "SOCKS5 9050 + bridges (RU VPS)" },
    { name: "split",   label: "Split routing", hint: "*.ru / CDN → direct; rest → Tor" },
    { name: "bridges", label: "Мосты", hint: "модуль: obfs4 / webtunnel / snowflake" },
    { name: "warp", label: "WARP", hint: "Cloudflare proxy egress; недоступен при Tor" },
  ];

  return (
    <section className="mt-4 rounded-lg border border-border bg-card p-4">
      <div>
        <h2 className="text-lg font-semibold tracking-normal">{t("networkBypass")}</h2>
        <p className="text-xs text-muted-foreground">{t("networkHint")}</p>
        <button
          type="button"
          className="mt-2 inline-flex h-8 items-center rounded-md border border-border px-3 text-xs hover:bg-muted"
          onClick={() => {
            setCollapsed((v) => {
              const next = !v;
              try {
                localStorage.setItem("olc-network-bypass-collapsed", next ? "1" : "0");
              } catch {
                /* ignore */
              }
              return next;
            });
          }}
        >
          {collapsed ? t("expand") : t("collapse")}
        </button>
      </div>
      {err && <div className="mt-3 rounded-md border border-red-500/40 bg-red-500/10 p-3 text-xs text-red-300">{err}</div>}
      {!collapsed && data && (
        <div className="mt-4 grid gap-2">
          {rows.filter((row) => visible(row.name)).map((row) => {
            const enabled = Boolean(data.flags?.[row.name]);
            return (
              <div key={row.name} className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-border bg-background p-3">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{row.label}</span>
                    <span className={`inline-flex h-5 items-center rounded-full px-2 text-[10px] uppercase tracking-wider ${enabled ? "bg-emerald-500/20 text-emerald-300" : "bg-zinc-500/20 text-zinc-300"}`}>
                      {enabled ? "on" : "off"}
                    </span>
                    {data.live?.[row.name] && (
                      <span className="text-[10px] uppercase tracking-wider text-muted-foreground">live: {data.live[row.name]}</span>
                    )}
                  </div>
                  <div className="text-xs text-muted-foreground">{row.hint}</div>
                </div>
                <div className="flex flex-wrap gap-1">
                  <button
                    type="button"
                    title={enabled ? "Логи" : "Логи недоступны — дополнение выключено"}
                    disabled={!enabled}
                    className={`inline-flex h-8 w-8 items-center justify-center rounded-md border border-border ${enabled ? "hover:bg-muted" : "opacity-40 cursor-not-allowed"}`}
                    onClick={() => { if (enabled) setLogFeature(row.name); }}
                  >
                    <Terminal className="h-4 w-4" />
                  </button>
                  <button
                    type="button"
                    title="Настройки"
                    className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-border hover:bg-muted"
                    onClick={() => setSettingsFeature(row.name)}
                  >
                    <Settings className="h-4 w-4" />
                  </button>
                  <button
                    className={`inline-flex h-8 items-center gap-2 rounded-md border px-3 text-sm disabled:opacity-60 ${enabled ? "border-red-500/40 hover:bg-red-500/10" : "border-emerald-500/40 hover:bg-emerald-500/10"}`}
                    disabled={
                      busy !== null ||
                      (row.name === "split" && !enabled && !data.flags?.tor) ||
                      (row.name === "bridges" && !enabled && !data.flags?.tor) ||
                      (row.name === "warp" && !enabled && Boolean(data.flags?.tor)) ||
                      (row.name === "tor" && !enabled && Boolean(data.flags?.warp))
                    }
                    onClick={() => void toggle(row.name, !enabled)}
                  >
                    {busy === row.name ? "…" : enabled ? t("disable") : t("enable")}
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}
          <div className="col-span-full my-1 border-t border-border" />
          <div className="col-span-full flex flex-wrap items-center justify-between gap-3 rounded-md border border-dashed border-border bg-background p-3">
            <div>
              <div className="font-medium">{t("olcrtcCore")}</div>
              <div className="text-xs text-muted-foreground">panel.env, Jitsi TLS, split lists — ветка master</div>
            </div>
            <div className="flex gap-1">
              <button type="button" title="Логи olcrtc" className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-border hover:bg-muted" onClick={() => setLogFeature("olcrtc")}>
                <Terminal className="h-4 w-4" />
              </button>
              <button type="button" title="Настройки OlcRTC" className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-border hover:bg-muted" onClick={() => setSettingsFeature("olcrtc" as FeatureName)}>
                <Settings className="h-4 w-4" />
              </button>
            </div>
          </div>

      {logFeature && <FeatureLogsModal feature={logFeature} onClose={() => setLogFeature(null)} />}
      {settingsFeature && <FeatureSettingsModal feature={settingsFeature} onClose={() => setSettingsFeature(null)} />}
    </section>
  );
}


// olc-phase456-ui
type PanelNotification = {
  id: string;
  catalog_id?: string;
  severity?: string;
  title?: string;
  meaning?: string;
  fixes?: string[];
  read?: boolean;
};


function AutodetectNotificationSettingsPanel({
  onClose,
}: {
  onClose?: () => void;
}) {
  const [s, setS] = useState<Record<string, unknown>>({});
  const [msg, setMsg] = useState("");
  useEffect(() => {
    void fetch("/api/notification-settings")
      .then((r) => r.json())
      .then((b: { settings?: Record<string, unknown> }) => setS(b.settings ?? {}));
  }, []);
  const save = async () => {
    const res = await fetch("/api/notification-settings", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(s),
    });
    setMsg(res.ok ? "Сохранено" : `HTTP ${res.status}`);
  };
  return (
    <div className="space-y-3 text-sm">
      <div className="flex items-center justify-between gap-3">
        <div className="font-medium">Автодетектор ошибок</div>
        <OlcToggleButton checked={Boolean(s.enabled)} onChange={(e) => setS({ ...s, enabled: e.target.checked })} />
      </div>
      <p className="text-xs text-muted-foreground">Сканирует логи и состояние сервисов, создаёт уведомления в колокольчике.</p>
      <label className="grid gap-1 text-xs text-muted-foreground">
        Интервал сканирования (сек)
        <input type="number" className="h-8 rounded border border-border bg-card px-2" value={Number(s.scan_interval_sec ?? 60)} onChange={(e) => setS({ ...s, scan_interval_sec: Number(e.target.value) })} />
      </label>
      <label className="grid gap-1 text-xs text-muted-foreground">
        Минимальная severity
        <select className="h-8 rounded border border-border bg-card px-2" value={String(s.min_severity ?? "warning")} onChange={(e) => setS({ ...s, min_severity: e.target.value })}>
          <option value="warning">warning и выше</option>
          <option value="error">только error</option>
        </select>
      </label>
      {msg && <p className="text-xs text-muted-foreground">{msg}</p>}
      <div className="flex gap-2">
        <button type="button" className="rounded border border-primary px-3 py-1 text-xs text-primary" onClick={() => void save()}>
          Сохранить
        </button>
        {onClose && (
          <button type="button" className="rounded border border-border px-3 py-1 text-xs" onClick={onClose}>
            Закрыть
          </button>
        )}
      </div>
    </div>
  );
}

function NotificationPreferencesModal({ onClose }: { onClose: () => void }) {
  const { t } = usePanelLang();
  const [view, setView] = useState<"main" | "autodetect">("main");
  const [s, setS] = useState<Record<string, unknown>>({});
  const [msg, setMsg] = useState("");
  useEffect(() => {
    void fetch("/api/notification-settings")
      .then((r) => r.json())
      .then((b: { settings?: Record<string, unknown> }) => setS(b.settings ?? {}));
  }, []);
  const saveGeneral = async () => {
    const res = await fetch("/api/notification-settings", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(s),
    });
    setMsg(res.ok ? "Сохранено" : `HTTP ${res.status}`);
  };
  const sources = (s.sources as Record<string, boolean>) ?? {};
  const setSource = (k: string, v: boolean) => setS({ ...s, sources: { ...sources, [k]: v } });
  return (
    <Modal title={view === "main" ? t("notificationSettings") : t("autodetect")} onClose={onClose}>
      <div className="p-4">
        {view === "main" ? (
          <div className="space-y-3 text-sm">
            <div className="flex items-center justify-between gap-3 text-xs">
              <span>Всплывающие подсказки (toast)</span>
              <OlcToggleButton compact checked={Boolean(s.show_toast)} onChange={(e) => setS({ ...s, show_toast: e.target.checked })} />
            </div>
            <div className="text-xs font-medium text-muted-foreground">Источники для автодетектора</div>
            {["instance", "olcrtc", "tor", "zapret", "panel", "split"].map((k) => (
              <div key={k} className="flex items-center justify-between gap-3 py-0.5 text-xs">
                <span>{k}</span>
                <OlcToggleButton compact checked={sources[k] !== false} onChange={(e) => setSource(k, e.target.checked)} />
              </div>
            ))}
            <button type="button" className="w-full rounded border border-border px-3 py-2 text-left text-xs hover:bg-muted" onClick={() => setView("autodetect")}>
              {t("autodetectOpen")}
            </button>
            {msg && <p className="text-xs text-muted-foreground">{msg}</p>}
            <button type="button" className="rounded border border-primary px-3 py-1 text-xs text-primary" onClick={() => void saveGeneral()}>
              {t("save")}
            </button>
          </div>
        ) : (
          <>
            <button type="button" className="mb-3 text-xs text-primary hover:underline" onClick={() => setView("main")}>
              ← Назад к общим уведомлениям
            </button>
            <AutodetectNotificationSettingsPanel />
          </>
        )}
      </div>
    </Modal>
  );
}

function MainSettingsAutodetectLink({
  expanded,
  onToggle,
}: {
  expanded: boolean;
  onToggle: () => void;
}) {
  const { t } = usePanelLang();
  return (
    <section className="grid gap-3 rounded-md border border-border bg-background p-4">
      <div className="text-sm font-medium text-foreground">{t("autodetect")}</div>
      <p className="text-xs text-muted-foreground">{t("autodetectSettings")}</p>
      <button type="button" className="w-fit rounded border border-border px-3 py-2 text-xs hover:bg-muted" onClick={onToggle}>
        {t("autodetectSettings")}
      </button>
      {expanded && (
        <div className="rounded-md border border-dashed border-border bg-card p-3">
          <AutodetectNotificationSettingsPanel />
        </div>
      )}
    </section>
  );
}

function NotificationBell() {
  const { t } = usePanelLang();
  const [open, setOpen] = usePersistedOpen("olc-modal-notifications-v1");
  const [prefsOpen, setPrefsOpen] = useState(false);
  const [list, setList] = useState<PanelNotification[]>([]);
  const [unread, setUnread] = useState(0);

  const load = async () => {
    try {
      const res = await fetch("/api/notifications", { cache: "no-store" });
      if (!res.ok) return;
      const body = (await res.json()) as { notifications?: PanelNotification[]; unread?: number };
      setList(body.notifications ?? []);
      setUnread(body.unread ?? 0);
    } catch {
      /* ignore */
    }
  };

  useEffect(() => {
    let intervalSec = 45;
    const tick = async () => {
      try {
        const ps = await fetch("/api/notification-settings", { cache: "no-store" });
        if (ps.ok) {
          const cfg = (await ps.json()) as { enabled?: boolean; scan_interval_sec?: number };
          if (cfg.enabled === false) return;
          if (cfg.scan_interval_sec && cfg.scan_interval_sec > 10) intervalSec = cfg.scan_interval_sec;
        }
      } catch {
        /* ignore */
      }
      await fetch("/api/notifications/scan", { method: "POST" });
      await load();
    };
    void tick();
    const id = window.setInterval(() => void tick(), intervalSec * 1000);
    return () => window.clearInterval(id);
  }, []);

  const dismiss = async (id: string) => {
    await fetch(`/api/notifications/${encodeURIComponent(id)}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dismiss: true }),
    });
    await load();
  };

  const markRead = async (id: string) => {
    await fetch(`/api/notifications/${encodeURIComponent(id)}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ read: true }),
    });
    await load();
  };

  return (
    <div className="relative">
      <button
        type="button"
        className="relative inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
        onClick={() => setOpen((o) => !o)}
        title={t("notifications")}
      >
        <Bell className="h-4 w-4" />
        {unread > 0 && (
          <span className="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-destructive px-1 text-[10px] text-white">
            {unread > 9 ? "9+" : unread}
          </span>
        )}
      </button>
      {open && (
        <div className="absolute right-0 z-50 mt-1 w-[min(24rem,90vw)] rounded-lg border border-border bg-card shadow-lg">
          <div className="flex items-center justify-between border-b border-border px-3 py-2 text-sm font-medium">
            <span>{t('notifications')}</span>
            <div className="flex gap-2">
              <button type="button" className="text-xs text-primary hover:underline" onClick={() => { setOpen(false); setPrefsOpen(true); }}>
                Настройки
              </button>
              <button type="button" className="text-xs text-muted-foreground hover:text-foreground" onClick={() => setOpen(false)}>
                {t("close")}
              </button>
            </div>
          </div>
          <ul className="max-h-80 overflow-auto p-2 text-xs">
            {list.length === 0 && <li className="p-2 text-muted-foreground">{t("noNotifications")}</li>}
            {list.map((n) => (
              <li key={n.id} className="mb-2 rounded border border-border p-2">
                <div className="flex items-start justify-between gap-2">
                  <span className={n.severity === "error" ? "text-destructive" : "text-amber-400"}>{n.title}</span>
                  <button type="button" className="shrink-0 text-muted-foreground hover:text-foreground" onClick={() => void dismiss(n.id)}>
                    ×
                  </button>
                </div>
                {n.meaning && <p className="mt-1 text-muted-foreground">{n.meaning}</p>}
                <button type="button" className="mt-1 text-primary hover:underline" onClick={() => void markRead(n.id)}>
                  Прочитано
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}
      {prefsOpen && <NotificationPreferencesModal onClose={() => setPrefsOpen(false)} />}
    </div>
  );
}

function ProjectUpdateButton({ disabled }: { disabled?: boolean }) {
  const { t } = usePanelLang();
  const [open, setOpen] = usePersistedOpen("olc-modal-project-v1");
  const [status, setStatus] = useState<Record<string, unknown> | null>(null);
  const [job, setJob] = useState<{ job_id?: string; status?: string } | null>(null);
  const [logLines, setLogLines] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [checkBusy, setCheckBusy] = useState(false);

  const loadAll = async () => {
    setErr("");
    try {
      const res = await fetch("/api/project/status", { cache: "no-store" });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error((body as { error?: string }).error || `HTTP ${res.status}`);
      setStatus(body as Record<string, unknown>);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    }
    const sr = await fetch("/api/updates/status", { cache: "no-store" });
    if (sr.ok) {
      const b = (await sr.json()) as { job?: { job_id?: string; status?: string }; locked?: boolean };
      if (b.job) setJob(b.job);
      if (b.locked && b.job?.job_id) {
        const lr = await fetch(`/api/jobs/${encodeURIComponent(b.job.job_id)}/log`, { cache: "no-store" });
        if (lr.ok) {
          const lj = (await lr.json()) as { lines?: string[] };
          setLogLines((prev) => olcMergeTail(prev, lj.lines ?? [], (x) => x, 1500));
        }
      }
    }
  };

  useEffect(() => {
    void loadAll();
    const id = window.setInterval(() => void loadAll(), 30000);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    if (!open) return;
    void loadAll();
    const id = window.setInterval(() => void loadAll(), 4000);
    return () => window.clearInterval(id);
  }, [open]);

  const runUpdate = async () => {
    if (!await olcConfirm(t("updateConfirm"))) return;
    setBusy(true);
    try {
      const res = await fetch("/api/updates/run", { method: "POST" });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error((body as { error?: string }).error || `HTTP ${res.status}`);
      setJob(body as { job_id?: string; status?: string });
      await loadAll();
    } catch (e) {
      alert(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };

  const stack = (status?.stack ?? status?.patches) as { enabled?: number; total?: number; items?: { id?: string; label?: string; enabled?: boolean }[] } ?? {};
  const notif = (status?.notifications as { total?: number; errors?: number; unread?: number }) ?? {};
  const caps = (status?.capabilities as { flags?: Record<string, boolean> }) ?? {};

  return (
    <>
      <button
        type="button"
        disabled={disabled}
        className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
        onClick={() => setOpen(true)}
        title="Состояние проекта и обновление"
      >
        <Download className="h-4 w-4" />
        Проект
        {Boolean(status?.update_available) && <span className="h-2 w-2 rounded-full bg-emerald-400" title="Доступно обновление" />}
      </button>
      {open && (
        <Modal title="Состояние проекта" onClose={() => setOpen(false)}>
          <div className="max-h-[70vh] space-y-4 overflow-auto p-4 text-sm">
            {err && <p className="text-destructive">{err}</p>}
            <div className="grid gap-3 md:grid-cols-3">
              <div className="rounded border border-border p-3">
                <div className="text-xs text-muted-foreground">Версия панели</div>
                <div className="text-lg font-semibold">{String(status?.panel_version ?? "—")}</div>
                <div className="text-xs text-muted-foreground">канал: {String(status?.channel ?? "—")} · профиль: {String(status?.deploy_profile ?? "—")}</div>
              </div>
              <div className="rounded border border-border p-3">
                <div className="text-xs text-muted-foreground">Стек сервисов</div>
                <div className="text-lg font-semibold">
                  {(stack.enabled as number) ?? 0}/{(stack.total as number) ?? 4}
                </div>
                <div className="mt-2 h-2 w-full overflow-hidden rounded bg-zinc-700/50">
                  <div
                    className="h-full bg-emerald-400 transition-all"
                    style={{
                      width: `${Math.max(0, Math.min(100, Math.round((((stack.enabled as number) ?? 0) / Math.max(1, ((stack.total as number) ?? 4))) * 100)))}%`,
                    }}
                  />
                </div>
                <div className="mt-1 flex flex-wrap gap-1 text-[10px]">
                  {((stack.items as { id?: string; enabled?: boolean; label?: string }[]) ?? []).map((it) => (
                    <span key={it.id} className={`rounded px-1.5 py-0.5 ${it.enabled ? "bg-emerald-500/20 text-emerald-300" : "bg-zinc-600/30"}`}>
                      {it.label ?? it.id}
                    </span>
                  ))}
                </div>
                <p className="mt-1 text-[10px] text-muted-foreground">Zapret · Tor · Split · Мосты (WARP — опционально)</p>
              </div>
              <div className="rounded border border-border p-3">
                <div className="text-xs text-muted-foreground">Автодетектор</div>
                <div className="text-lg font-semibold">{notif.errors ?? 0} ошибок</div>
                <div className="text-xs text-muted-foreground">всего {notif.total ?? 0}, непрочит. {notif.unread ?? 0}</div>
                <div className="mt-2 grid grid-cols-3 gap-1 text-[10px]">
                  <div className="rounded bg-zinc-700/40 px-1 py-1 text-center">
                    <div className="text-muted-foreground">all</div>
                    <div>{notif.total ?? 0}</div>
                  </div>
                  <div className="rounded bg-amber-500/15 px-1 py-1 text-center">
                    <div className="text-muted-foreground">unread</div>
                    <div>{notif.unread ?? 0}</div>
                  </div>
                  <div className="rounded bg-red-500/15 px-1 py-1 text-center">
                    <div className="text-muted-foreground">errors</div>
                    <div>{notif.errors ?? 0}</div>
                  </div>
                </div>
              </div>
            </div>
            <div className="rounded border border-border p-3 text-xs">
              <div className="mb-1 font-medium">Git</div>
              <div>
                локально: <code>{String(status?.local_sha ?? "—").slice(0, 12)}</code>
                {status?.remote_sha ? (
                  <>
                    {" "}
                    → удалённо: <code>{String(status.remote_sha).slice(0, 12)}</code>
                  </>
                ) : (
                  <span className="text-muted-foreground">
                    {" "}
                    (origin/main недоступен — git fetch с VPS или safe.directory; локальный SHA: {status?.local_sha ? "есть" : "нет"})
                  </span>
                )}
              </div>
              <div className="mt-1 text-muted-foreground">
                Релиз стека (установлен):{" "}
                {(status?.installed_release_tag ?? status?.latest_release_tag) ? (
                  <code>{String(status?.installed_release_tag ?? status?.latest_release_tag)}</code>
                ) : (
                  <span className="text-amber-400">нет в version.json</span>
                )}
              </div>
              {status?.latest_release_tag &&
                status?.installed_release_tag &&
                String(status.latest_release_tag) !== String(status.installed_release_tag) && (
                  <div className="mt-1 text-xs text-emerald-400">
                    На GitHub новее: <code>{String(status.latest_release_tag)}</code>
                  </div>
                )}
              <div className="mt-1 text-[10px]">
                <a
                  className="text-primary underline"
                  href="https://github.com/krygag1234-a11y/Olc-cost-l/releases"
                  target="_blank"
                  rel="noreferrer"
                >
                  github.com/.../Olc-cost-l/releases
                </a>
              </div>
              {Boolean(status?.git_ahead) && (
                <p className="mt-1 text-amber-400">Локальный репозиторий впереди origin/main (есть незапушенные коммиты)</p>
              )}
              {Boolean(status?.update_available) && (
                <p className="mt-1 text-emerald-400">
                  {status?.update_source === "release"
                    ? `Доступен релиз ${String(status?.latest_release_tag ?? "")}`
                    : "Доступно обновление origin/main"}
                </p>
              )}
            </div>
            <div className="rounded border border-border p-3 text-xs">
              <div className="mb-1 font-medium">Компоненты (флаги features.env)</div>
              <div className="flex flex-wrap gap-2">
                {(
                  [
                    ["zapret", "Zapret"],
                    ["tor", "Tor"],
                    ["split", "Split"],
                    ["bridges", "Мосты"],
                    ["warp", "WARP"],
                    ["olcrtc", "OlcRTC"],
                  ] as const
                ).map(([k, label]) => {
                  const v = Boolean((caps.flags as Record<string, boolean> | undefined)?.[k]);
                  return (
                    <span key={k} className={`rounded px-2 py-0.5 ${v ? "bg-emerald-500/20 text-emerald-300" : "bg-zinc-500/20"}`}>
                      {label}: {v ? "on" : "off"}
                    </span>
                  );
                })}
              </div>
            </div>
            {(status?.stack_manifest as Record<string, unknown> | undefined) && (
              <div className="rounded border border-border p-3 text-xs">
                <div className="mb-1 font-medium">Состав релиза (upstream pins)</div>
                <ul className="space-y-1 font-mono text-[10px] text-muted-foreground">
                  {Object.entries(status.stack_manifest as Record<string, { ref?: string; branch?: string; source?: string; channel?: string }>).map(([name, meta]) => (
                    <li key={name}>
                      {name}:{" "}
                      {meta.ref ? <span>{String(meta.ref).slice(0, 12)}</span> : null}
                      {meta.branch ? <span> ({meta.branch})</span> : null}
                      {meta.source ? <span> · {meta.source}</span> : null}
                      {meta.channel ? <span> · {meta.channel}</span> : null}
                    </li>
                  ))}
                </ul>
                <p className="mt-1 text-[10px] text-muted-foreground">webtunnel-client — бинарь с mirror-cry, не из olcrtc gitlab</p>
              </div>
            )}
            {Boolean(status?.update_locked) && (
              <p className="text-amber-400">{t("updateInProgress")}</p>
            )}
            {!status?.update_locked && job?.status === "running" && (
              <p className="text-amber-400">{t("updateStuck")}</p>
            )}
            {job?.status === "failed" && job?.error ? (
              <p className="text-destructive text-xs">{String(job.error)}</p>
            ) : null}
            <div className="flex flex-wrap gap-2">
              <button type="button" className="rounded-md border border-primary bg-primary/20 px-3 py-2 text-primary disabled:opacity-50" disabled={busy || Boolean(status?.update_locked)} onClick={() => void runUpdate()}>
                {busy ? t("updateStarting") : t("updateFromGithub")}
              </button>
              <button type="button" className="rounded-md border border-border px-3 py-2 disabled:opacity-50" disabled={checkBusy} onClick={() => { setCheckBusy(true); void loadAll().finally(() => setCheckBusy(false)); }}>
                {checkBusy ? t("checkingUpdate") : t("checkUpdate")}
              </button>
              <span className={`self-center text-xs ${status?.update_available ? "text-emerald-400" : "text-muted-foreground"}`}>
                {status?.update_available ? t("updateAvailableDot") : status?.local_sha ? t("versionCurrent") : ""}
              </span>
            </div>
            {logLines.length > 0 && (
              <LogScrollPre className="max-h-48 overflow-y-auto rounded border border-border bg-background p-2 text-xs">{logLines.slice(-50).join("\n")}</LogScrollPre>
            )}
          </div>
        </Modal>
      )}
    </>
  );
}


function componentJobFinishedMs(j?: { finished_at?: string; status?: string }): number | null {
  if (!j?.finished_at) return null;
  const ms = Date.parse(j.finished_at);
  return Number.isFinite(ms) ? ms : null;
}

function componentJobUiVisible(j?: { status?: string; finished_at?: string }): boolean {
  if (!j?.status) return false;
  if (j.status === "running") return true;
  if (j.status === "failed") {
    const doneAt = componentJobFinishedMs(j);
    return doneAt == null || Date.now() - doneAt < COMPONENT_JOB_UI_TTL_MS * 2;
  }
  if (j.status === "done") {
    const doneAt = componentJobFinishedMs(j);
    return doneAt == null || Date.now() - doneAt < COMPONENT_JOB_UI_TTL_MS;
  }
  return false;
}


async function waitForComponentJobDone(component: string, jobId: string, timeoutMs = 600_000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try {
      const res = await fetch("/api/components/jobs", { cache: "no-store" });
      if (!res.ok) break;
      const body = (await res.json()) as { jobs?: { component?: string; job_id?: string; status?: string }[] };
      const job = (body.jobs ?? []).find((j) => j.component === component && j.job_id === jobId);
      if (!job || job.status === "done" || job.status === "failed") return job?.status ?? "done";
    } catch {
      /* ignore */
    }
    await new Promise((r) => window.setTimeout(r, 2000));
  }
  return "timeout";
}

const COMPONENT_DRAWER_ITEMS = [
  { id: "zapret", label: "Zapret (DPI)" },
  { id: "tor", label: "Tor" },
  { id: "split", label: "Split" },
  { id: "bridges", label: "Мосты" },
  { id: "warp", label: "WARP (Cloudflare)" },
] as const;

/* olc-components-jobs-ui-ttl */
/* olc-roadmap-finish-v1 */
/* olc-roadmap-finish-v2 */
function ComponentsDrawerButton() {
  const { t } = usePanelLang();
  const [open, setOpen] = usePersistedOpen("olc-modal-components-v1");
  const { caps, reloadCaps } = useCapabilities();
  const [jobMsg, setJobMsg] = useState("");
  const [jobsByComponent, setJobsByComponent] = useState<Record<string, { job_id?: string; status?: string; action?: string; error?: string; finished_at?: string }>>({});
  const [activeJobId, setActiveJobId] = useState<string | null>(null);
  const [activeJobLines, setActiveJobLines] = useState<string[]>([]);

  const loadJobs = async () => {
    try {
      const res = await fetch("/api/components/jobs", { cache: "no-store" });
      if (!res.ok) return;
      const body = (await res.json()) as { jobs?: { component?: string; job_id?: string; status?: string; action?: string; error?: string; finished_at?: string }[] };
      const next: Record<string, { job_id?: string; status?: string; action?: string; error?: string; finished_at?: string }> = {};
      for (const j of body.jobs ?? []) {
        if (!j.component || next[j.component]) continue;
        if (!componentJobUiVisible(j)) continue;
        next[j.component] = { job_id: j.job_id, status: j.status, action: j.action, error: j.error, finished_at: j.finished_at };
      }
      setJobsByComponent(next);
    } catch {
      // ignore
    }
  };

  const loadJobLog = async (jobId: string) => {
    try {
      const lr = await fetch(`/api/jobs/${encodeURIComponent(jobId)}/log`, { cache: "no-store" });
      if (!lr.ok) return;
      const body = (await lr.json()) as { lines?: string[] };
      setActiveJobLines(body.lines ?? []);
    } catch {
      // ignore
    }
  };

  useEffect(() => {
    if (!open) return;
    void loadJobs();
    const id = window.setInterval(() => void loadJobs(), 4000);
    return () => window.clearInterval(id);
  }, [open]);


  useEffect(() => {
    if (!activeJobId) return;
    const entry = Object.values(jobsByComponent).find((j) => j.job_id === activeJobId);
    if (!entry || entry.status === "running") return;
    const doneAt = componentJobFinishedMs(entry) ?? Date.now();
    const left = COMPONENT_JOB_UI_TTL_MS - (Date.now() - doneAt);
    const delay = Math.max(0, Math.min(left, COMPONENT_JOB_UI_TTL_MS));
    const timer = window.setTimeout(() => {
      setActiveJobId(null);
      setActiveJobLines([]);
      setJobMsg("");
    }, delay);
    return () => window.clearTimeout(timer);
  }, [activeJobId, jobsByComponent]);

  useEffect(() => {
    if (!open) return;
    const timer = window.setInterval(() => {
      setJobsByComponent((prev) => {
        const next: typeof prev = {};
        for (const [k, j] of Object.entries(prev)) {
          if (componentJobUiVisible(j)) next[k] = j;
        }
        return Object.keys(next).length === Object.keys(prev).length ? prev : next;
      });
    }, 15_000);
    return () => window.clearInterval(timer);
  }, [open]);

  useEffect(() => {
    if (!activeJobId) return;
    void loadJobLog(activeJobId);
    const id = window.setInterval(() => void loadJobLog(activeJobId), 2500);
    return () => window.clearInterval(id);
  }, [activeJobId]);

  const run = async (name: string, action: "install" | "uninstall") => {
    if (!await olcConfirm(t(action === "install" ? "confirmInstall" : "confirmUninstall", { name }))) return;
    setJobMsg(t("updateStarting"));
    try {
      const res = await fetch(`/api/components/${name}/${action}`, { method: "POST" });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error((body as { error?: string }).error || `HTTP ${res.status}`);
      const jobId = (body as { job_id?: string }).job_id ?? "";
      setJobMsg(t("jobStarted", { id: jobId }));
      setJobsByComponent((prev) => ({ ...prev, [name]: { job_id: jobId, status: "running", action } }));
      if (jobId) {
        setActiveJobId(jobId);
      }
      await loadJobs();
      if (jobId) {
        const finalStatus = await waitForComponentJobDone(name, jobId);
        await loadJobs();
        await reloadCaps();
        window.dispatchEvent(new Event("olc-capabilities-changed"));
        window.dispatchEvent(new Event("olc-features-changed"));
        if (finalStatus === "done") {
          setJobMsg(action === "install" ? t("jobInstalled") : t("jobUninstalled"));
        } else if (finalStatus === "failed") {
          setJobMsg(t("jobErrorSeeLog"));
        }
      }
    } catch (e) {
      setJobMsg(e instanceof Error ? e.message : String(e));
    }
  };

  return (
    <>
      <button
        type="button"
        className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
        onClick={() => setOpen(true)}
        title={t("componentsDrawerHint")}
      >
        <Package className="h-4 w-4" />
        ±
      </button>
      {open && (
        <Modal title={t("componentsVps")} onClose={() => { setOpen(false); setJobMsg(""); setActiveJobId(null); setActiveJobLines([]); }}>
          <div className="space-y-3 p-4 text-sm">
            <p className="text-xs text-muted-foreground">{t("profileLabel", { id: caps?.deploy_profile ?? "—" })}</p>
            {COMPONENT_DRAWER_ITEMS.map((c) => {
              const st = caps?.components?.[c.id];
              const installed = st?.installed ?? false;
              const j = jobsByComponent[c.id];
              const isRunning = j?.status === "running";
              const jobAction = isRunning ? j?.action : undefined;
              const jobDone = j?.status === "done";
              const effectiveInstalled =
                isRunning && jobAction === "uninstall" ? false
                : isRunning && jobAction === "install" ? false
                : jobDone && j?.action === "uninstall" ? false
                : jobDone && j?.action === "install" ? true
                : installed;
              const showInstallBtn = isRunning ? jobAction === "install" : !effectiveInstalled;
              const showDeleteBtn = isRunning ? jobAction === "uninstall" : effectiveInstalled;
              const unmetRequires = (st?.requires ?? []).filter((required) => {
                const dep = caps?.components?.[required];
                return dep?.installed !== true || dep?.enabled !== true;
              });
              const installBlocked = unmetRequires.length > 0;
              const showJob = j && componentJobUiVisible(j);
              const statusText = showJob
                ? j.status === "running"
                  ? j.action === "uninstall" ? t("jobUninstallingStatus") : t("jobInstallingStatus")
                  : j.status === "done"
                    ? t("jobDone")
                    : j.status === "failed"
                      ? t("jobFailed", { error: j.error ?? t("jobErrorSeeLog") })
                      : t("jobStatusUnknown", { status: j.status ?? "unknown" })
                : "";
              return (
                <div key={c.id} className="flex flex-wrap items-center justify-between gap-2 rounded border border-border p-2">
                  <div>
                    <div className="font-medium">{c.label}</div>
                    <div className="text-xs text-muted-foreground">
                      {installed ? t("componentInstalled") : t("componentNotInstalled")}
                      {st?.enabled ? ` · ${t("componentOn")}` : st?.installed ? ` · ${t("componentOff")}` : ""}
                    </div>
                    {installBlocked && (
                      <div className="text-xs text-amber-400">Requires: {unmetRequires.join(", ")}</div>
                    )}
                    {statusText && <div className={`text-xs ${j?.status === "failed" ? "text-destructive" : j?.status === "done" ? "text-emerald-400" : "text-amber-400"}`}>{statusText}</div>}
                  </div>
                  <div className="flex gap-2">
                    {j?.job_id && showJob && (
                      <button
                        type="button"
                        className="rounded border border-border px-2 py-1 text-xs"
                        onClick={() => setActiveJobId(j.job_id ?? null)}
                      >
                        {t("componentLog")}
                      </button>
                    )}
                    {showInstallBtn && (
                      <button
                        type="button"
                        className="rounded border border-primary px-2 py-1 text-xs text-primary"
                        disabled={(isRunning && jobAction !== "install") || installBlocked}
                        title={installBlocked ? `Requires installed and enabled: ${unmetRequires.join(", ")}` : undefined}
                        onClick={() => void run(c.id, "install")}
                      >
                        {jobAction === "install" ? t("installing") : t("installBtn")}
                      </button>
                    )}
                    {showDeleteBtn && (
                      <button
                        type="button"
                        className="rounded border border-destructive px-2 py-1 text-xs text-destructive"
                        disabled={isRunning && jobAction !== "uninstall"}
                        onClick={() => void run(c.id, "uninstall")}
                      >
                        {jobAction === "uninstall" ? t("uninstalling") : t("uninstallBtn")}
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
            {jobMsg && <p className="text-xs text-muted-foreground">{jobMsg}</p>}
            {activeJobId && (
              <div className="rounded border border-border bg-background p-2">
                <div className="mb-2 flex items-center justify-between">
                  <div className="text-xs text-muted-foreground">{t("jobLogTitle", { id: activeJobId })}</div>
                  <button type="button" className="text-xs text-muted-foreground hover:text-foreground" onClick={() => { setActiveJobId(null); setActiveJobLines([]); if (jobMsg === t("jobInstalled") || jobMsg === t("jobUninstalled")) setJobMsg(""); }}>
                    {t("close")}
                  </button>
                </div>
                <LogScrollPre className="max-h-48 overflow-y-auto whitespace-pre-wrap text-xs leading-relaxed">{activeJobLines.slice(-250).join("\n")}</LogScrollPre>
              </div>
            )}
          </div>
        </Modal>
      )}
    </>
  );
}


function ErrorsSummaryButton() {
  const { t } = usePanelLang();
  const [open, setOpen] = usePersistedOpen("olc-modal-errors-v1");
  const [autodetectOpen, setAutodetectOpen] = useState(false);
  const [items, setItems] = useState<PanelNotification[]>([]);

  const refreshIssues = async () => {
    try {
      await fetch("/api/notifications/scan", { method: "POST" });
      const res = await fetch("/api/notifications", { cache: "no-store" });
      if (!res.ok) return;
      const b = (await res.json()) as { notifications?: PanelNotification[] };
      setItems(b.notifications ?? []);
    } catch {
      /* ignore */
    }
  };

  useEffect(() => {
    void refreshIssues();
    const id = window.setInterval(() => void refreshIssues(), 45_000);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    if (!open) return;
    void refreshIssues();
  }, [open]);

  const issues = items.filter((n) => n.severity === "error" || n.severity === "warning");
  const errors = issues;

  return (
    <>
      <button
        type="button"
        className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
        onClick={() => setOpen(true)}
        title="Ошибки по каталогу"
      >
        <AlertTriangle className="h-4 w-4" />
        {errors.length > 0 && <span className="text-destructive">{errors.length}</span>}
      </button>
      {open && (
        <Modal title={t("errors")} onClose={() => setOpen(false)}>
          <ul className="max-h-96 space-y-2 overflow-auto p-4 text-sm">
            {errors.length === 0 && <li className="text-muted-foreground">{t("noErrors")}</li>}
            {errors.map((n) => (
              <li key={n.id} className="rounded border border-border p-2">
                <div className="font-medium text-destructive">{n.title}</div>
                <p className="text-xs text-muted-foreground">{n.meaning}</p>
                {Array.isArray((n as { matched_lines?: string[] }).matched_lines) &&
                  (n as { matched_lines?: string[] }).matched_lines!.length > 0 && (
                  <pre className="mt-1 max-h-24 overflow-auto rounded bg-muted p-1 font-mono text-[10px]">
                    {(n as { matched_lines?: string[] }).matched_lines!.join("\n")}
                  </pre>
                )}
                {n.fixes && n.fixes.length > 0 && (
                  <ul className="mt-1 list-disc pl-4 text-xs">
                    {n.fixes.map((f, i) => (
                      <li key={i}>{f}</li>
                    ))}
                  </ul>
                )}
              </li>
            ))}
            <p className="text-xs">
              <button type="button" className="text-primary underline" onClick={() => { setOpen(false); setAutodetectOpen(true); }}>
                {t("autodetectSettings")}
              </button>
            </p>
          </ul>
        </Modal>
      )}
      {autodetectOpen && (
        <Modal title={t("autodetectSettings")} onClose={() => setAutodetectOpen(false)}>
          <div className="p-4">
            <AutodetectNotificationSettingsPanel onClose={() => setAutodetectOpen(false)} />
          </div>
        </Modal>
      )}
    </>
  );
}


function UpdateAvailableToast() {
  const { t } = usePanelLang();
  const [show, setShow] = useState(false);
  const [dismissed, setDismissed] = useState(false);
  useEffect(() => {
    const check = async () => {
      try {
        const res = await fetch("/api/updates/check", { cache: "no-store" });
        if (!res.ok) return;
        const b = (await res.json()) as { available?: boolean };
        if (b.available && !dismissed) setShow(true);
      } catch { /* ignore */ }
    };
    void check();
    const id = window.setInterval(() => void check(), 6 * 60 * 60 * 1000);
    return () => window.clearInterval(id);
  }, [dismissed]);
  if (!show) return null;
  return (
    <div className="fixed bottom-4 right-4 z-50 flex max-w-sm items-start gap-2 rounded-lg border border-primary bg-background p-3 shadow-lg">
      <span className="text-sm">{t("updateAvailable")}</span>
      <button type="button" className="text-xs text-primary underline" onClick={() => window.dispatchEvent(new Event("olc-open-project-modal"))}>
        {t("open")}
      </button>
      <button type="button" className="ml-auto text-muted-foreground" onClick={() => { setDismissed(true); setShow(false); }} aria-label={t("close")}>
        ✕
      </button>
    </div>
  );
}


function SelectiveRandomizationPanel({
  globalEnabled,
}: {
  globalEnabled?: boolean;
}) {
  const [clients, setClients] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [msg, setMsg] = useState("");

  const loadClients = () => {
    setLoading(true);
    fetch("/api/clients/", { cache: "no-store" })
      .then((r) => r.json())
      .then((data: any) => {
        setClients(data.clients || []);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  };

  useEffect(() => {
    loadClients();
  }, []);

  const [typeTarget, setTypeTarget] = useState<{ id: string; edit: boolean } | null>(null);
  const applyRand = async (clientID: string, enabled: boolean, randType?: number) => {
    const body: any = { enabled };
    if (enabled && randType) body.rand_type = randType;
    const res = await fetch(`/api/clients/${encodeURIComponent(clientID)}/randomization`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (res.ok) {
      setMsg(`Рандомизация ${enabled ? "включена" : "отключена"} для ${clientID}`);
      loadClients();
    } else {
      setMsg(`Ошибка: HTTP ${res.status}`);
    }
  };

  return (
    <div className="space-y-3 text-sm">
      <div className="font-medium">Выборочная рандомизация</div>
      <p className="text-xs text-muted-foreground">
        Настройте рандомизацию URL для каждого клиента индивидуально
      </p>
      {loading ? (
        <p className="text-xs text-muted-foreground">Загрузка...</p>
      ) : clients.length === 0 ? (
        <p className="text-xs text-muted-foreground">Нет клиентов</p>
      ) : (
        <div className="space-y-2 max-h-60 overflow-y-auto">
          {clients.map((c: any) => {
            const perClientEnabled = c.randomization?.enabled ?? false;
            const enabled = globalEnabled || perClientEnabled;
            const randomizedID = c.randomization?.randomized_id || "";
            return (
              <div key={c.client_id} className="border border-border rounded p-2 space-y-1">
                <div className="flex items-center justify-between gap-2">
                  <div className="text-xs font-medium truncate flex-1">{c.client_id}</div>
                  {perClientEnabled && !globalEnabled && (
                    <button type="button" className="rounded border border-border px-1 text-xs text-muted-foreground hover:bg-muted" title="Изменить тип рандомизации" onClick={() => setTypeTarget({ id: c.client_id, edit: true })}>✏️</button>
                  )}
                  <div className="flex items-center gap-1">
                    <OlcToggleButton compact

                      checked={enabled}
                      disabled={globalEnabled}
                      onChange={() => { if (perClientEnabled) { void applyRand(c.client_id, false); } else { setTypeTarget({ id: c.client_id, edit: false }); } }}
                      className={globalEnabled ? "rounded opacity-50 cursor-not-allowed" : "rounded"}
                    />

                  </div>
                </div>
                {enabled && (
                  <div className="text-xs text-muted-foreground truncate">
                    Тип: {globalEnabled ? "глобальный" : `Т${c.randomization?.rand_type || 1}`}{randomizedID ? ` · Hash: ${randomizedID}` : ""}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
      {typeTarget && (
        <RandTypeModal
          clientId={typeTarget.id}
          edit={typeTarget.edit}
          onClose={() => setTypeTarget(null)}
          onChoose={(ty) => { const tt = typeTarget; setTypeTarget(null); void applyRand(tt.id, true, ty); }}
        />
      )}
      {msg && <p className="text-xs text-amber-600">{msg}</p>}
    </div>
  );
}


function SubscriptionRandomizationPanel({
  onClose,
  globalEnabled,
  onGlobalChange,
}: {
  onClose?: () => void;
  globalEnabled?: boolean;
  onGlobalChange?: (v: boolean) => void;
}) {
  const enabled = globalEnabled ?? false;
  const loading = false;
  const [msg, setMsg] = useState("");
  const [gType, setGType] = useState(1);
  useEffect(() => {
    void fetch("/api/settings/randomization/global", { cache: "no-store" })
      .then((r) => r.json())
      .then((b: any) => { if (b && b.rand_type) setGType(b.rand_type); })
      .catch(() => {});
  }, []);
  const setType = async (ty: number) => {
    setGType(ty);
    await fetch("/api/settings/randomization/global", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ enabled: true, rand_type: ty }),
    });
    setMsg("Тип сохранён");
  };

  const toggle = async () => {
    const newVal = !enabled;
    // optimistic: update shared App state immediately so client cards + selective panel react instantly
    onGlobalChange?.(newVal);
    const res = await fetch("/api/settings/randomization/global", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ enabled: newVal }),
    });
    if (res.ok) {
      setMsg("Сохранено");
    } else {
      onGlobalChange?.(enabled); // rollback on failure
      setMsg(`Ошибка: HTTP ${res.status}`);
    }
  };

  return (
    <div className="space-y-3 text-sm">
      <div className="font-medium">Глобальная рандомизация подписок</div>
      <p className="text-xs text-muted-foreground">
        Включает защиту от enumeration для всех клиентов. Direct ID блокируется, работает только через hash.
      </p>
      {loading ? (
        <p className="text-xs text-muted-foreground">Загрузка...</p>
      ) : (
        <div className="flex items-center text-xs">
          <OlcToggleButton checked={enabled} onChange={() => void toggle()} />
        </div>
      )}
      {enabled && (
        <div className="grid gap-1 rounded-md border border-amber-500/40 bg-amber-500/10 p-2">
          <div className="text-[11px] font-medium text-amber-600">Тип рандомизации (глобально)</div>
          <label className="flex items-center gap-1 text-xs cursor-pointer"><input type="radio" name="olc-grand-type" checked={gType === 1} onChange={() => void setType(1)} /> Тип 1 — статичный хэш</label>
          <label className="flex items-center gap-1 text-xs cursor-pointer"><input type="radio" name="olc-grand-type" checked={gType === 2} onChange={() => void setType(2)} /> Тип 2 — посекундная ротация <span className="text-amber-500">(нужен контроль доступа)</span></label>
        </div>
      )}
      {msg && <p className="text-xs text-muted-foreground">{msg}</p>}
      {onClose && (
        <button type="button" className="rounded border border-border px-3 py-1 text-xs" onClick={onClose}>
          Закрыть
        </button>
      )}
    </div>
  );
}

function Type2Warning({ show }: { show: boolean }) {
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    if (!show) { setVisible(false); return; }
    const id = window.setTimeout(() => setVisible(true), 1200);
    return () => window.clearTimeout(id);
  }, [show]);
  if (!visible) return null;
  return (
    <span className="mt-1 block text-[10px] leading-tight text-amber-500">
      ⚠️ Тип 2 без контроля доступа: ссылка меняется каждую секунду — пользоваться нереально. Настройте контроль доступа (⚙), тогда оригинальный client_id заработает для разрешённых устройств.
    </span>
  );
}

function RandTypeModal({ clientId, onChoose, onClose, edit }: { clientId: string; onChoose: (ty: number) => void; onClose: () => void; edit?: boolean }) {
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4" onClick={onClose}>
      <div className="w-full max-w-md rounded-lg border border-border bg-card p-4 shadow-xl" onClick={(e) => e.stopPropagation()}>
        <div className="mb-1 flex items-center justify-between">
          <div className="truncate text-sm font-semibold text-foreground">🎲 {edit ? "Изменить тип" : "Тип рандомизации"} — {clientId}</div>
          <button type="button" className="rounded px-2 text-muted-foreground hover:bg-muted" onClick={onClose}>✕</button>
        </div>
        <p className="mb-3 text-[11px] text-muted-foreground">{edit ? "Выберите новый тип. Сгенерированный хэш сохранится. Закрыть без выбора — оставить как есть." : "Выберите тип. Если закрыть без выбора — рандомизация НЕ включится."}</p>
        <div className="grid gap-2">
          <button type="button" className="grid gap-1 rounded-md border border-emerald-500/40 bg-emerald-500/5 p-3 text-left transition-colors hover:bg-emerald-500/10" onClick={() => onChoose(1)}>
            <div className="text-sm font-medium text-emerald-500">Тип 1 — статичный хэш</div>
            <div className="text-[11px] text-muted-foreground">Постоянный случайный хэш вместо client_id. Работает БЕЗ контроля доступа. Ссылка не меняется.</div>
          </button>
          <button type="button" className="grid gap-1 rounded-md border border-sky-500/40 bg-sky-500/5 p-3 text-left transition-colors hover:bg-sky-500/10" onClick={() => onChoose(2)}>
            <div className="text-sm font-medium text-sky-400">Тип 2 — посекундная ротация</div>
            <div className="text-[11px] text-muted-foreground">Хэш меняется каждую секунду (HMAC). Оригинальный client_id работает только для разрешённых устройств через контроль доступа. <span className="text-amber-500">Без настроенного контроля доступа пользоваться нереально — ссылка меняется каждую секунду.</span></div>
          </button>
        </div>
      </div>
    </div>
  );
}

function ClientQrModal({ client, path, globalRandomizationEnabled, randomizationScope, globalAccessEnabled, accessConfigured, onClose }: { client: any; path?: string; globalRandomizationEnabled?: boolean; randomizationScope?: string; globalAccessEnabled?: boolean; accessConfigured?: boolean; onClose: () => void }) {
  const origin = window.location.origin;
  const p = (path && path.trim().replace(/^\/+|\/+$/g, "")) || "sub";
  const rnd = client.randomization || {};
  const enabled = randomizationScope !== "crypto" && !!(rnd.enabled || globalRandomizationEnabled);
  const rtype = rnd.rand_type || 1;
  const origUrl = `${origin}/${p}/${encodeURIComponent(client.client_id)}/`;
  const staticUrl = rnd.randomized_id ? `${origin}/${p}/${rnd.randomized_id}/` : "";
  const [rotUrl, setRotUrl] = useState("");
  useEffect(() => {
    if (!(enabled && rtype === 2)) return;
    let stop = false;
    const tick = () => {
      void fetch(`/api/clients/${encodeURIComponent(client.client_id)}/subscription-url`, { cache: "no-store" })
        .then((r) => r.json())
        .then((b: any) => { if (!stop && b && b.url) setRotUrl(`${origin}${b.url}`); })
        .catch(() => {});
    };
    tick();
    const id = window.setInterval(tick, 1000);
    return () => { stop = true; window.clearInterval(id); };
  }, []);
  const qr = (data: string) => `https://api.qrserver.com/v1/create-qr-code/?size=256x256&data=${encodeURIComponent(data)}`;
  const [copiedKey, setCopiedKey] = useState("");
  const copy = (s: string, key: string) => {
    if (!s) return;
    void olcSafeCopy(s);
    setCopiedKey(key);
    window.setTimeout(() => setCopiedKey((k) => (k === key ? "" : k)), 1500);
  };
  const type2NoAccess = enabled && rtype === 2 && !globalAccessEnabled && !accessConfigured;
  const stdBlock = (k: string, title: string, url: string, note?: string) => (
    <div key={k} className="grid w-full max-w-xs justify-items-center gap-2 rounded-md border border-border p-3">
      <div className="text-center text-xs font-semibold text-foreground">{title}</div>
      <img className="h-44 w-44 rounded-md bg-white p-2" src={qr(url || origUrl)} alt="QR" />
      {note && <div className="max-w-[16rem] text-center text-[10px] leading-tight text-muted-foreground">{note}</div>}
      <div className="max-w-full break-all rounded border border-border bg-background p-2 font-mono text-[10px] text-muted-foreground">{url || "—"}</div>
      <button type="button" className={"h-8 rounded-md border px-3 text-xs transition-transform active:scale-95 disabled:opacity-50 " + (copiedKey === k ? "border-emerald-500/60 bg-emerald-500/15 text-emerald-500 font-medium" : "border-border bg-muted hover:bg-muted/80")} disabled={!url} onClick={() => copy(url, k)}>{copiedKey === k ? "✓ Скопировано" : "Копировать"}</button>
    </div>
  );
  const rotBlock = () => (
    <div key="rot" className="grid w-full max-w-xs justify-items-center gap-2 rounded-md border border-border p-3">
      <div className="text-center text-xs font-semibold text-foreground">Ротация (меняется каждую секунду)</div>
      <div className="relative h-44 w-44">
        <img className="pointer-events-none h-44 w-44 select-none rounded-md bg-white p-2 opacity-70 blur-[10px]" src={qr(origUrl)} alt="" aria-hidden="true" />
        <div className="absolute inset-0 grid place-items-center p-3 text-center text-[10px] font-semibold text-foreground/80">статический QR при динамическом хэше недоступен</div>
      </div>
      <div className="max-w-full break-all rounded border border-border bg-background p-2 font-mono text-[10px] text-amber-500">{rotUrl || "…"}</div>
      <div className="text-center text-[10px] text-muted-foreground">client_id меняется каждую секунду</div>
      {type2NoAccess && <div className="max-w-[16rem] text-center text-[10px] leading-tight text-amber-500">Тип 2 без контроля доступа: пользоваться нереально. Настройте контроль доступа (⚙).</div>}
    </div>
  );
  const blocks: any[] = [];
  if (!enabled) {
    blocks.push(stdBlock("o", "Ссылка-подписка", origUrl));
  } else {
    blocks.push(stdBlock("o", "Оригинальный client_id", origUrl, rtype === 2 ? "Работает только для разрешённых устройств (контроль доступа)" : "При рандомизации прямой доступ по client_id заблокирован"));
    if (rtype === 1) blocks.push(stdBlock("s", "Рандомная (рабочая) ссылка", staticUrl, "Постоянный случайный хэш"));
    else blocks.push(rotBlock());
  }
  return (
    <Modal title={`QR — ${client.client_id}`} onClose={onClose}>
      <div className={blocks.length > 1 ? "grid gap-3 p-4 sm:grid-cols-2" : "grid justify-items-center gap-3 p-4"}>{blocks}</div>
    </Modal>
  );
}

function ClientLogPanel({ title, load, empty, autologi, liveKey, maxH, statusMode, hint, onClear }: { title: string; load: () => Promise<React.ReactNode[]>; empty: string; autologi: boolean; liveKey: string; maxH?: string; statusMode?: boolean; hint?: string; onClear?: () => Promise<void> }) {
  const { t } = usePanelLang();
  const [rows, setRows] = useState<React.ReactNode[]>([]);
  const [loading, setLoading] = useState(true);
  const [liveRaw, setLiveRaw] = useState(() => readStoredBool(liveKey, false));
  const setLive = (v: boolean | ((p: boolean) => boolean)) => setLiveRaw((prev) => { const nx = typeof v === "function" ? (v as (p: boolean) => boolean)(prev) : v; writeStoredBool(liveKey, nx); return nx; });
  const live = autologi || liveRaw;
  const scroll = useStickyLogScroll<HTMLDivElement>([rows], true);
  const refresh = useCallback(async (showLoading: boolean) => {
    if (showLoading) setLoading(true);
    try { setRows(await load()); } catch { /* ignore */ } finally { setLoading(false); }
  }, [load]);
  useEffect(() => { void refresh(true); }, [refresh]);
  useEffect(() => {
    if (!live && !statusMode) return;
    const id = window.setInterval(() => void refresh(false), LOGS_LIVE_INTERVAL_MS);
    return () => window.clearInterval(id);
  }, [live, statusMode, refresh]);
  return (
    <div className="grid gap-2 rounded-md border border-border bg-card/40 p-3">
      <div className="flex items-center justify-between gap-2">
        <div className="text-xs font-semibold text-foreground">{title}</div>
        <div className="flex shrink-0 items-center gap-2">
          {onClear && <button type="button" className="inline-flex items-center rounded-md border border-destructive/40 px-2 py-0.5 text-[11px] text-destructive hover:bg-destructive/10" onClick={async () => { await onClear(); void refresh(true); }}>Очистить</button>}
          {statusMode ? (
            <span className="inline-flex items-center gap-1 rounded-md border border-emerald-500/30 bg-emerald-500/10 px-2 py-0.5 text-[11px] text-emerald-600"><span className="text-emerald-400">●</span> живой статус</span>
          ) : autologi ? (
            <span className="inline-flex items-center rounded-md border border-emerald-500/30 bg-emerald-500/10 px-2 py-0.5 text-[11px] text-emerald-600">Автообновление</span>
          ) : (
            <>
              <button type="button" className="inline-flex items-center rounded-md border border-border bg-background px-2 py-0.5 text-[11px] hover:bg-muted disabled:opacity-50" disabled={loading || live} onClick={() => void refresh(true)}>{t("refresh")}</button>
              <button type="button" className={"inline-flex items-center rounded-md border border-border px-2 py-0.5 text-[11px] hover:bg-muted " + (live ? "bg-primary text-primary-foreground" : "bg-background")} onClick={() => setLive((v) => !v)}>{live ? t("logsLiveOn") : t("logsLive")}</button>
            </>
          )}
        </div>
      </div>
      {hint && <div className="text-[11px] leading-snug text-muted-foreground">{hint}</div>}
      <LogScrollBox ref={scroll.ref} onScroll={scroll.onScroll} className={"overflow-y-auto rounded-md border border-border bg-black p-3 font-mono text-xs text-slate-100 " + (maxH || "max-h-52")}>
        {loading && rows.length === 0 ? (
          <div className="text-muted-foreground">{t("loadingLogs")}</div>
        ) : rows.length === 0 ? (
          <div className="text-muted-foreground">{empty}</div>
        ) : (
          rows
        )}
      </LogScrollBox>
    </div>
  );
}

function ClientAccessLogModal({ client, autologi, onClose }: { client: any; autologi: boolean; onClose: () => void }) {
  const { t } = usePanelLang();
  const cid = client.client_id;
  const loadAttempts = useCallback(async (): Promise<React.ReactNode[]> => {
    const b = await fetch("/api/access/attempts", { cache: "no-store" }).then((r) => r.json()).catch(() => ({ attempts: [] }));
    return (b.attempts || []).filter((a: any) => a.client_id === cid).map((a: any, i: number) => (
      <div key={"a-" + i} className="whitespace-pre-wrap break-words leading-relaxed">
        <span className={a.allowed ? "text-emerald-400" : "text-red-400"}>{a.allowed ? "✓" : "✕"}</span>{" "}
        <span className="text-muted-foreground">{a.ts}</span>{"  "}{a.label?.trim() || a.hwid || "—"} · {a.ip || "—"}{a.count > 1 ? ` ×${a.count}` : ""}{a.path ? ` · ${a.path}` : ""}
      </div>
    ));
  }, [cid]);
  const loadConns = useCallback(async (): Promise<React.ReactNode[]> => {
    const b = await fetch("/api/access/connections", { cache: "no-store" }).then((r) => r.json()).catch(() => ({ connections: [] }));
    return (b.connections || []).filter((c: any) => c.client_id === cid).map((c: any, i: number) => (
      <div key={"c-" + i} className="whitespace-pre-wrap break-words leading-relaxed">
        <span className="text-muted-foreground">{c.last}</span>{"  "}{c.label?.trim() || c.device || "—"} <span className="text-muted-foreground">→</span> {c.location_name || c.room_id}{Number(c.count || 0) > 1 ? ` ×${c.count}` : ""}{Number(c.denied || 0) > 0 ? <span className="text-red-400" title="Отклонённые попытки подключения (бан / не в списке) — устройство НЕ подключилось"> 🚫 отклонено ×{c.denied}</span> : null}{Number(c.kicked || 0) > 0 ? <span className="text-orange-400" title="Живая сессия сброшена ядром по бану (ban-watcher)"> ⛔ сброшен ×{c.kicked}</span> : null}
      </div>
    ));
  }, [cid]);
  const clearAttempts = async () => { try { await fetch(`/api/access/attempts/clear?client_id=${encodeURIComponent(cid)}`, { method: "POST" }); } catch { /* ignore */ } };
  const clearConns = async () => { try { await fetch(`/api/access/connections?clear=1&client_id=${encodeURIComponent(cid)}`, { cache: "no-store" }); } catch { /* ignore */ } };
  const loadActive = useCallback(async (): Promise<React.ReactNode[]> => {
    const d = await fetch("/api/state", { cache: "no-store" }).then((r) => r.json()).catch(() => ({ clients: [] }));
    const lc = (d.clients || []).find((x: any) => x.client_id === cid);
    const locs = (lc?.locations || []);
    // Живой сигнал здоровья по инстансам с активными пирами: ядро НЕ логирует
    // ICE-disconnect, но логирует «control missed pong»/«unhealthy»/«reason=liveness»
    // — ПЕРВЫЙ признак обрыва (~10-30с), раньше обнуления peer_count.
    const withPeers = locs.filter((loc: any) => (((loc.runtime && loc.runtime.peer_devices) || []).length) > 0);
    const badByRoom: Record<string, boolean> = {};
    await Promise.all(withPeers.map(async (loc: any) => {
      try {
        const q = new URLSearchParams({ client_id: cid, room_id: String(loc.room_id), transport: loc.transport || "" });
        const b = await fetch(`/api/logs/?${q.toString()}`, { cache: "no-store" }).then((r) => r.json());
        const lines = (b.logs || b.lines || []) as any[];
        let up = ""; let bad = "";
        for (const ln of lines) {
          const s = typeof ln === "string" ? ln : (ln.line || "");
          const tm = (ln && ln.time) || "";
          if (s.includes("peer connected: device=")) up = tm;
          else if (s.includes("control missed pong") || s.includes("control unhealthy") || s.includes("reason=liveness")) bad = tm;
        }
        badByRoom[String(loc.room_id)] = !!(bad && bad > up);
      } catch { /* ignore */ }
    }));
    const byDev: Record<string, { inst: string; at: string; bad: boolean }> = {};
    locs.forEach((loc: any) => {
      const inst = loc.name || loc.room_id;
      const at = (loc.runtime && loc.runtime.peer_at) || "";
      const bad = !!badByRoom[String(loc.room_id)];
      ((loc.runtime && loc.runtime.peer_devices) || []).forEach((dev: string) => {
        if (!byDev[dev] || at > byDev[dev].at) byDev[dev] = { inst, at, bad };
      });
    });
    return Object.keys(byDev).map((dev, i) => {
      const bad = byDev[dev].bad;
      return (
        <div key={"act-" + i} className="whitespace-pre-wrap break-words leading-relaxed">
          <span className={bad ? "text-amber-400" : "text-emerald-400"}>{bad ? "◌" : "●"}</span> {dev} <span className="text-muted-foreground">→</span> {byDev[dev].inst}{bad ? <span className="text-amber-500 text-[10px]"> · обрыв связи (ядро закроет по liveness, до ~1.5 мин)</span> : null}
        </div>
      );
    });
  }, [cid]);
  return (
    <Modal title={t("logsClient", { id: cid })} onClose={onClose}>
      <div className="grid gap-3 p-5">
        <div className="text-xs text-muted-foreground">Данные по этому клиенту. Показываются независимо от того, включён ли контроль доступа.</div>
        <ClientLogPanel title="🎫 Попытки подключения к подписке" load={loadAttempts} onClear={clearAttempts} empty="Попыток пока нет." autologi={autologi} liveKey={"olc-clog-att-" + cid} />
        <ClientLogPanel title="🔌 Попытки подключения к инстансам" load={loadConns} onClear={clearConns} empty="Попыток пока нет." autologi={autologi} liveKey={"olc-clog-conn-" + cid} />
        <ClientLogPanel title="🔌 Подключения к инстансам (активны сейчас)" load={loadActive} onClear={clearConns} empty="Нет активных подключений/туннелей." autologi={autologi} liveKey={"olc-clog-act-" + cid} maxH="max-h-40" statusMode hint="Отражает сессии, которые держит ядро. После реального отключения запись может исчезать с задержкой до ~1 минуты: ядро выдерживает окно на переподключение, чтобы кратковременный обрыв сети (напр. мобильная) не рвал туннель." />
      </div>
    </Modal>
  );
}

// ============================================================================
// Olc-cost-l: «♻️ Автосмена ключей» (Z5-B). ОТДЕЛЬНАЯ секция рядом с
// рандомизациями. Раз в интервал автообновления подписки (N ч) сервер
// перегенерирует ОРИГИНАЛЬНЫЕ ключи шифрования инстансов; занятые (с активным
// туннелем или недавними повторными попытками) откладываются до следующего круга. Клиент подхватывает новые ключи
// при автообновлении. Независимо от рандомизации. См. docs/ACCESS-CONTROL.md.
// ============================================================================
function KeyRotationSection() {
  const [globalEnabled, setGlobalEnabled] = useState(false);
  const [clients, setClients] = useState<string[]>([]);
  const [perClient, setPerClient] = useState<Record<string, boolean>>({});
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const load = async () => {
    try {
      const r = await fetch("/api/settings/key-rotation", { cache: "no-store" });
      const b = await r.json();
      setGlobalEnabled(!!b.global_enabled);
      setPerClient((b.clients && typeof b.clients === "object") ? b.clients : {});
    } catch { /* ignore */ }
    try {
      const r = await fetch("/api/clients/", { cache: "no-store" });
      const b = await r.json();
      setClients((Array.isArray(b.clients) ? b.clients : []).map((c: any) => String(c.client_id)));
    } catch { /* ignore */ }
  };
  useEffect(() => { void load(); }, []);

  const saveGlobal = async (v: boolean) => {
    setBusy(true); setMsg(null);
    try {
      const r = await fetch("/api/settings/key-rotation", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ global_enabled: v }) });
      const b = await r.json();
      if (!r.ok) throw new Error(b.error || ("HTTP " + r.status));
      setGlobalEnabled(!!b.global_enabled);
      setPerClient((b.clients && typeof b.clients === "object") ? b.clients : {});
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };
  const saveClient = async (id: string, v: boolean) => {
    setBusy(true); setMsg(null);
    try {
      const r = await fetch(`/api/clients/${encodeURIComponent(id)}/key-rotation`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ enabled: v }) });
      const b = await r.json();
      if (!r.ok) throw new Error(b.error || ("HTTP " + r.status));
      setPerClient((b.clients && typeof b.clients === "object") ? b.clients : {});
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };

  return (
    <section className="grid gap-3 rounded-md border border-amber-500/30 bg-amber-500/5 p-4">
      <div>
        <div className="text-sm font-semibold text-amber-400">♻️ Автосмена ключей</div>
        <div className="mt-1 grid gap-1 text-xs text-muted-foreground">
          <div>Раз в <b className="text-foreground">N ч</b> сервер перегенерирует <b className="text-foreground">оригинальные ключи шифрования</b> инстансов. Клиент подхватывает новые ключи при автообновлении подписки. Защита от <b className="text-foreground">утёкшей подписки</b> (слитый ключ протухает за N). Работает независимо от рандомизации ключей/ID.</div>
          <div><b className="text-foreground">N = интервал автообновления подписки</b> (заголовок <span className="font-mono">profile-update-interval</span>, который вы задаёте пикером часов): для <b className="text-foreground">глобальной</b> смены берётся интервал из <b className="text-foreground">общих настроек подписки</b>; для <b className="text-foreground">выборочной</b> (по клиенту) — интервал, заданный у этого клиента в <span className="font-mono">Edit</span>. Если интервал нигде не задан — по умолчанию <b className="text-foreground">24 ч</b>.</div>
          <div>Инстансы с <b className="text-foreground">активным туннелем или попытками подключения за последние 2 минуты пропускаются</b> до следующего круга — ключ не меняется во время сессии или постоянных переподключений.</div>
        </div>
      </div>

      {/* Глобальный режим */}
      <div className="grid gap-2 rounded-md border border-border bg-card/40 p-3">
        <div className="text-xs font-semibold text-foreground">🌐 Глобально (все клиенты и инстансы)</div>
        <div className="flex flex-wrap gap-2 text-xs">
          <button type="button" disabled={busy}
            className={!globalEnabled ? "rounded-md border border-border px-2 py-1 font-medium text-muted-foreground hover:bg-muted" : "rounded-md border border-border px-2 py-1 text-muted-foreground transition-colors duration-300 hover:bg-muted"}
            onClick={() => { if (!globalEnabled) return; void saveGlobal(false); }}>
            Выключено
          </button>
          <button type="button" disabled={busy}
            className={globalEnabled ? "rounded-md border border-amber-500/60 bg-amber-500/15 px-2 py-1 font-medium text-amber-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground transition-colors duration-300 hover:bg-muted"}
            onClick={() => { if (globalEnabled) return; void saveGlobal(true); }}>
            ♻️ Включить для всех
          </button>
        </div>
        {globalEnabled && <div className="text-[10px] leading-snug text-amber-500/90">Включено глобально: ключи всех инстансов всех подписок ротируются каждый их интервал автообновления. Индивидуальные тумблеры ниже не требуются.</div>}
      </div>

      {/* Выборочно по клиентам */}
      <div className={"grid gap-2 rounded-md border border-border bg-card/40 p-3" + (globalEnabled ? " pointer-events-none opacity-40 select-none" : "")}
        title={globalEnabled ? "Включено глобально — индивидуальный выбор не нужен" : undefined}>
        <div className="text-xs font-semibold text-foreground">🎯 Выборочно (отдельные подписки)</div>
        {clients.length === 0 && <div className="text-[11px] text-muted-foreground">Клиентов нет.</div>}
        <div className="grid gap-1">
          {clients.map((id) => {
            const on = globalEnabled || !!perClient[id];
            return (
              <div key={id} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1 text-[11px]">
                <span className="min-w-0 flex-1 truncate font-mono">{id}</span>
                <button type="button" disabled={busy || globalEnabled}
                  className={on ? "shrink-0 rounded border border-amber-500/60 bg-amber-500/15 px-2 py-1 font-medium text-amber-300" : "shrink-0 rounded border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                  onClick={() => void saveClient(id, !perClient[id])}>
                  {on ? "♻️ Вкл" : "Выкл"}
                </button>
              </div>
            );
          })}
        </div>
        <div className="text-[10px] leading-snug text-muted-foreground">Ротируются все инстансы выбранной подписки. Активная сессия или попытки подключения за последние 2 минуты откладывают инстанс до следующего круга. Интервал N = автообновление подписки этого клиента (Edit); если у клиента не задано — глобальный интервал; если и он не задан — 24 ч.</div>
      </div>

      {msg && <div className="text-xs text-red-500 whitespace-pre-wrap">{msg}</div>}
    </section>
  );
}

// ============================================================================
// Olc-cost-l: «Дополнительные функции рандомизации» — контейнер рядом с блоками
// рандомизации (выборочная / глобальная). Сейчас содержит «♻️ Автосмена ключей».
// Задел под будущие расширенные настройки рандомизации. Сворачивается отдельно
// (localStorage olc-addrand-open-v1), чтобы не удлинять модалку настроек.
// ============================================================================
function AdditionalRandomizationSection() {
  const [open, setOpen] = useState(() => readStoredBool("olc-addrand-open-v1", false));
  const [randScopeSel, setRandScopeSel] = useState("both");
  const [randScopeSaving, setRandScopeSaving] = useState(false);
  const [randScopeMsg, setRandScopeMsg] = useState("");
  const [randScopePending, setRandScopePending] = useState<null | "crypto" | "client_id">(null);
  useEffect(() => { void fetch("/api/settings/randomization/scope", { cache: "no-store" }).then((r) => r.json()).then((b: any) => { if (b && (b.rand_scope === "client_id" || b.rand_scope === "crypto" || b.rand_scope === "both")) setRandScopeSel(b.rand_scope); }).catch(() => {}); }, []);
  const saveRandScope = async (s: string) => {
    if (s === randScopeSel || randScopeSaving) return;
    setRandScopeSaving(true); setRandScopeMsg("");
    try {
      const r = await fetch("/api/settings/randomization/scope", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ rand_scope: s }) });
      if (!r.ok) throw new Error((await r.text()) || ("HTTP " + r.status));
      const b: any = await r.json(); setRandScopeSel(b.rand_scope || s);
      window.dispatchEvent(new Event("olc-randomization-saved"));
    } catch (e: any) { setRandScopeMsg(e?.message || "Не удалось сохранить область рандомизации"); }
    finally { setRandScopeSaving(false); }
  };
  const requestRandScope = (s: string) => {
    if (s === randScopeSel || randScopeSaving) return;
    if (s === "crypto" || s === "client_id") {
      setRandScopePending(s);
      return;
    }
    void saveRandScope(s);
  };
  const scopeBtn = (val: string, label: string) => (
    <button type="button" disabled={randScopeSaving} onClick={() => requestRandScope(val)}
      className={"rounded-md border px-2 py-1 text-xs font-medium transition-colors duration-300 " + (randScopeSel === val ? "border-amber-500/60 bg-amber-500/15 text-amber-300" : "border-border text-muted-foreground hover:bg-muted")}>
      {label}
    </button>
  );
  const toggle = () => { const v = !open; setOpen(v); writeStoredBool("olc-addrand-open-v1", v); };
  const pendingTitle = randScopePending === "crypto"
    ? "Переключение на «Только ключи»"
    : "Переключение на «Только client_id»";
  const pendingText = randScopePending === "crypto"
    ? "Старые статические и динамические рандомизированные client_id станут недействительны без восстановления. Режим 🎫 «+» будет постоянно сброшен на «Выкл» глобально и у отдельных клиентов. Крипто-рандомизация останется включена: при режиме 🔌 «Выкл» список разрешённых выключен, оригинальные ключи не принимаются. Используйте рандомизированные ключи, настройте «+»/«Блокировать неизвестных» либо отключите рандомизацию."
    : "Старые статические и динамические рандомизированные криптоключи станут недействительны без восстановления. Режим 🔌 «+» будет постоянно сброшен на «Выкл» глобально и у отдельных клиентов. Рандомизация client_id останется включена: при режиме 🎫 «Выкл» список разрешённых выключен, оригинальный client_id не принимается. Используйте рандомизированный URL, настройте «+»/«Блокировать неизвестных» либо отключите рандомизацию.";
  return (
    <>
    {randScopePending && (
      <div className="fixed inset-0 z-[80] grid place-items-center bg-black/65 p-4" onMouseDown={(e) => { if (e.target === e.currentTarget) setRandScopePending(null); }}>
        <div className="w-full max-w-lg rounded-lg border border-amber-500/40 bg-card p-4 shadow-2xl">
          <div className="text-base font-semibold text-foreground">{pendingTitle}</div>
          <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{pendingText}</p>
          <div className="mt-4 flex justify-end gap-2">
            <button type="button" className="rounded-md border border-border px-3 py-1.5 text-sm hover:bg-muted" onClick={() => setRandScopePending(null)}>Отмена</button>
            <button type="button" className="rounded-md border border-amber-500/60 bg-amber-500/15 px-3 py-1.5 text-sm text-amber-300 hover:bg-amber-500/25" onClick={() => { const next = randScopePending; setRandScopePending(null); if (next) void saveRandScope(next); }}>Переключить</button>
          </div>
        </div>
      </div>
    )}
    <div className="grid gap-2 rounded-md border border-border bg-card/30 p-3">
      <div className="flex items-center justify-between gap-2">
        <div>
          <div className="text-sm font-semibold text-foreground">🧩 Дополнительные функции рандомизации</div>
          <div className="text-xs text-muted-foreground">Расширенные возможности поверх рандомизации подписок/ключей</div>
          {!open && <div className="mt-0.5 text-[11px] text-muted-foreground">Внутри: ♻️ Автосмена ключей</div>}
        </div>
        <button
          type="button"
          className="rounded bg-amber-500/10 border border-amber-500/30 px-2 py-1 text-xs text-amber-600 hover:bg-amber-500/20 transition-colors"
          onClick={toggle}
        >
          {open ? "Скрыть" : "Настроить"}
        </button>
      </div>
      {open && (
        <div className="border-l-2 border-amber-500/30 pl-3 grid gap-2">
          <div className="grid gap-2 rounded-md border border-border bg-card/40 p-3">
            <div className="text-xs font-semibold text-foreground">🎯 Область действия рандомизации</div>
            <div className="text-[11px] text-muted-foreground">К чему применяется рандомизация (тип 1/2). По умолчанию — к обоим.</div>
            <div className="flex flex-wrap gap-2">
              {scopeBtn("both", "И client_id, и ключи")}
              {scopeBtn("client_id", "Только client_id (🎫)")}
              {scopeBtn("crypto", "Только ключи (🔌)")}
            </div>
            {randScopeMsg && <div className="text-[11px] text-red-500">{randScopeMsg}</div>}
            <div className="text-[10px] leading-snug text-muted-foreground">Определяет применение выбранного типа: client_id → 🎫 подписка, ключи → 🔌 альтернативный ключ подключения, оба → обе защиты. Изменение крипто-режима перезапускает затронутые инстансы.</div>
          </div>
          <KeyRotationSection />
        </div>
      )}
    </div>
    </>
  );
}

// ============================================================================
// Olc-cost-l: Info-модалка отдельного инстанса. Самодостаточна: опрашивает
// /api/state (активные пиры/аптайм/память), /api/instances/info (ключи+трафик),
// /api/access/connections (журнал по устройствам этого инстанса). Учитывает
// автологи: при autologi=on журнал обновляется автоматически, иначе — по кнопке
// «Обновить». Живой статус (активные пиры) опрашивается всегда пока модалка
// открыта. Для тип2 рандомизации ключей рандомизированный ключ тикает раз в сек.
// ============================================================================
function olcFmtBytes(n?: number): string {
  if (!n || n <= 0) return "0 B";
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0; let v = n;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return `${v.toFixed(i === 0 ? 0 : 2)} ${u[i]}`;
}
function olcFmtUptime(started?: string): string {
  if (!started) return "—";
  const ms = Date.now() - new Date(started).getTime();
  if (isNaN(ms) || ms < 0) return "—";
  const s = Math.floor(ms / 1000);
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}д ${h}ч ${m}м`;
  if (h > 0) return `${h}ч ${m}м`;
  if (m > 0) return `${m}м ${s % 60}с`;
  return `${s}с`;
}

function InstanceInfoModal({ clientID, roomID, name, transport, autologi, onClose }: { clientID: string; roomID: string; name?: string; transport?: string; autologi: boolean; onClose: () => void }) {
  const [runtime, setRuntime] = useState<any>(null);
  const [peers, setPeers] = useState<{ count: number; sessions: number; devices: string[] }>({ count: 0, sessions: 0, devices: [] });
  const [info, setInfo] = useState<any>(null);
  const [conns, setConns] = useState<any[]>([]);
  const [msg, setMsg] = useState("");
  const [showOrig, setShowOrig] = useState(false);
  const [showRand, setShowRand] = useState(false);
  const [ice, setIce] = useState<{ state: string; at: string }>({ state: "", at: "" });

  const loadStatus = async () => {
    try {
      const r = await fetch("/api/state", { cache: "no-store" });
      const b = await r.json();
      const c = (b.clients || []).find((x: any) => x.client_id === clientID);
      const loc = c?.locations?.find((l: any) => String(l.room_id) === String(roomID));
      if (loc) {
        setRuntime(loc.runtime || null);
        const rt = loc.runtime || {};
        const devs: string[] = Array.isArray(rt.peer_devices) ? rt.peer_devices : [];
        const uniq = Array.from(new Set(devs));
        const sessions = typeof rt.peer_count === "number" ? rt.peer_count : devs.length;
        setPeers({ count: uniq.length, sessions, devices: uniq });
      }
    } catch { /* ignore */ }
  };
  // Живой сигнал здоровья связи: ядро НЕ логирует ICE-disconnect, но логирует
  // «control missed pong»/«control unhealthy»/«reason=liveness» — это ПЕРВЫЙ признак
  // обрыва (~10-30с), раньше чем peer_count обнулится после liveness-таймаута. Не
  // трогаем сам таймаут; peer_count остаётся авторитетным.
  const loadIce = async () => {
    try {
      const q = new URLSearchParams({ client_id: clientID, room_id: String(roomID), transport: transport || "" });
      const r = await fetch(`/api/logs/?${q.toString()}`, { cache: "no-store" });
      const b = await r.json();
      const lines = (b.logs || b.lines || []) as any[];
      let up = ""; let bad = "";
      for (const ln of lines) {
        const s = typeof ln === "string" ? ln : (ln.line || "");
        const tm = (ln && ln.time) || "";
        if (s.includes("peer connected: device=")) up = tm;
        else if (s.includes("control missed pong") || s.includes("control unhealthy") || s.includes("reason=liveness")) bad = tm;
      }
      setIce({ state: (bad && bad > up) ? "unhealthy" : (up ? "connected" : ""), at: bad || up });
    } catch { /* ignore */ }
  };
  const loadInfo = async () => {
    try {
      const r = await fetch(`/api/instances/info?client_id=${encodeURIComponent(clientID)}&room_id=${encodeURIComponent(roomID)}`, { cache: "no-store" });
      if (r.ok) setInfo(await r.json());
    } catch { /* ignore */ }
  };
  const loadConns = async () => {
    try {
      const r = await fetch("/api/access/connections", { cache: "no-store" });
      const b = await r.json();
      setConns((Array.isArray(b.connections) ? b.connections : []).filter((rec: any) => String(rec.room_id) === String(roomID)));
    } catch { /* ignore */ }
  };
  const clearJournal = async () => {
    try {
      await fetch(`/api/access/connections?clear=1&client_id=${encodeURIComponent(clientID)}`, { cache: "no-store" });
      setConns([]);
      setMsg("Журнал очищен");
      window.setTimeout(() => setMsg((m) => (m === "Журнал очищен" ? "" : m)), 2000);
      await loadConns();
    } catch { setMsg("Ошибка очистки"); }
  };

  // Живой статус (пиры/рантайм/транспорт) — всегда пока модалка открыта, 1.5с.
  useEffect(() => {
    void loadStatus(); void loadIce();
    const id = window.setInterval(() => { void loadStatus(); void loadIce(); }, 1500);
    return () => window.clearInterval(id);
  }, [clientID, roomID]);

  // Ключи/трафик: тип2 (dynamic) — раз в секунду, иначе раз в 5с.
  const dynamic = !!info?.key_rand?.dynamic;
  useEffect(() => {
    void loadInfo();
    const id = window.setInterval(() => { void loadInfo(); }, dynamic ? 1000 : 5000);
    return () => window.clearInterval(id);
  }, [clientID, roomID, dynamic]);

  // Журнал устройств: автологи — авто-обновление; иначе — по кнопке.
  useEffect(() => {
    void loadConns();
    if (!autologi) return;
    const id = window.setInterval(() => { void loadConns(); }, 4000);
    return () => window.clearInterval(id);
  }, [clientID, roomID, autologi]);

  const kr = info?.key_rand;
  const traffic = info?.traffic;
  const mask = (s?: string) => (s ? (s.length > 16 ? s.slice(0, 8) + "…" + s.slice(-8) : s) : "—");

  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4" onClick={onClose}>
      <div className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-lg border border-border bg-background p-4 shadow-xl" onClick={(e) => e.stopPropagation()}>
        <div className="mb-3 flex items-center justify-between gap-2">
          <div className="min-w-0">
            <div className="truncate text-sm font-semibold text-foreground">ℹ️ Инфо об инстансе — {name || roomID}</div>
            <div className="truncate text-[11px] text-muted-foreground">{clientID} · <span className="font-mono">{roomID}</span></div>
          </div>
          <button type="button" className="rounded px-2 text-muted-foreground hover:bg-muted" onClick={onClose}>✕</button>
        </div>

        {/* Состояние инстанса */}
        <section className="mb-3 grid gap-2 rounded-md border border-border border-l-2 border-l-sky-500/50 bg-card/40 p-3 text-xs">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-sky-400">⚙️ Состояние</div>
          <div className="grid grid-cols-2 gap-x-4 gap-y-1 sm:grid-cols-3">
            <div><span className="text-muted-foreground">Статус:</span> <span className={runtime?.running ? "text-emerald-500 font-medium" : "text-muted-foreground"}>{runtime?.status || "—"}</span></div>
            <div><span className="text-muted-foreground">Аптайм:</span> <span className="font-medium text-foreground">{runtime?.running ? olcFmtUptime(runtime?.started_at) : "—"}</span></div>
            <div><span className="text-muted-foreground">Память:</span> <span className="font-medium text-foreground">{runtime?.memory_bytes ? olcFmtBytes(runtime.memory_bytes) : "—"}</span></div>
            <div><span className="text-muted-foreground">PID:</span> <span className="font-medium text-foreground">{runtime?.pid || "—"}</span></div>
            <div><span className="text-muted-foreground">Рестартов:</span> <span className="font-medium text-foreground">{typeof runtime?.restarts === "number" ? runtime.restarts : "—"}</span></div>
            <div><span className="text-muted-foreground">Лог-строк:</span> <span className="font-medium text-foreground">{runtime?.log_count ?? "—"}</span></div>
          </div>
          {runtime?.exit_error && <div className="text-destructive">Ошибка выхода: {runtime.exit_error}</div>}
        </section>

        {/* Трафик */}
        <section className="mb-3 grid gap-1 rounded-md border border-border border-l-2 border-l-violet-500/50 bg-card/40 p-3 text-xs">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-violet-400">📊 Трафик</div>
          {traffic?.available
            ? <div><span className="text-muted-foreground">Передано (этот инстанс):</span> <span className="font-medium text-foreground">{olcFmtBytes(traffic.used_bytes)}</span></div>
            : <div className="text-muted-foreground">Учёт по инстансу недоступен (нужны квоты/netns для инстанса). Суммарный трафик клиента — в карточке клиента.</div>}
        </section>

        {/* Активные подключения сейчас */}
        <section className="mb-3 grid gap-1.5 rounded-md border border-border border-l-2 border-l-emerald-500/50 bg-card/40 p-3 text-xs">
          <div className="flex items-center gap-2 text-[11px] font-semibold uppercase tracking-wide text-emerald-400">🔌 Активны сейчас <span className="rounded bg-emerald-500/15 px-1.5 normal-case text-[10px] font-normal text-emerald-500">● живой статус</span></div>
          {(() => {
            const st = ice.state;
            const up = st === "connected";
            const dropped = st === "unhealthy";
            if (!st) return null;
            return (
              <div className={"flex items-center gap-1.5 text-[10px] " + (up ? "text-emerald-500" : "text-amber-500")}>
                <span>{up ? "🟢" : "🟡"}</span>
                <span>Связь: <b>{up ? "активна" : "проверяется — возможен обрыв"}</b></span>
                {dropped && peers.count > 0 && <span className="text-muted-foreground">— ядро закроет сессию по liveness (обычно до ~1.5 мин)</span>}
              </div>
            );
          })()}
          {peers.count > 0
            ? <div className="grid gap-1">
                <div><span className="text-muted-foreground">Устройств онлайн:</span> <span className="font-medium text-foreground">{peers.count}</span>{peers.sessions > peers.count && <span className="text-[10px] text-amber-500"> · сессий ядра: {peers.sessions} (вкл. переподключения/залипшие — ядро закроет по liveness ~30с)</span>}</div>
                {peers.devices.length > 0 && <div className="flex flex-wrap gap-1">{peers.devices.map((d, i) => <span key={i} className="rounded border border-emerald-500/40 bg-emerald-500/10 px-1.5 py-0.5 font-mono text-[10px] text-emerald-400">{d}</span>)}</div>}
              </div>
            : <div className="text-muted-foreground">Нет активных подключений</div>}
        </section>

        {/* Журнал по устройствам (этот инстанс) */}
        <section className="mb-3 grid gap-2 rounded-md border border-border border-l-2 border-l-amber-500/50 bg-card/40 p-3 text-xs">
          <div className="flex items-center justify-between gap-2">
            <div className="text-[11px] font-semibold uppercase tracking-wide text-amber-400">📖 Журнал устройств (этот инстанс)</div>
            <div className="flex gap-1">
              {!autologi && <button type="button" className="rounded border border-border px-2 py-0.5 hover:bg-muted" onClick={() => void loadConns()}>Обновить</button>}
              <button type="button" className="rounded border border-destructive/40 px-2 py-0.5 text-destructive hover:bg-destructive/10" onClick={() => void clearJournal()}>Очистить</button>
            </div>
          </div>
          {autologi
            ? <div className="text-[10px] text-emerald-500/80">Автологи включены — журнал обновляется автоматически.</div>
            : <div className="text-[10px] text-muted-foreground">Автологи выключены — жмите «Обновить».</div>}
          {conns.length === 0
            ? <div className="text-muted-foreground">Записей нет</div>
            : <div className="grid gap-1 max-h-48 overflow-y-auto">
                {conns.map((rec, i) => (
                  <div key={i} className="rounded border border-border bg-background px-2 py-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="min-w-0 flex-1 truncate font-mono text-[11px]">{rec.device}</span>
                      {rec.count > 0 && <span className="rounded bg-emerald-500/15 px-1.5 text-[10px] text-emerald-500">✅ ×{rec.count}</span>}
                      {rec.denied > 0 && <span className="rounded bg-red-500/15 px-1.5 text-[10px] text-red-500">🚫 отклонено ×{rec.denied}</span>}
                      {rec.kicked > 0 && <span className="rounded bg-amber-500/15 px-1.5 text-[10px] text-amber-500">👢 кик ×{rec.kicked}</span>}
                      {(!rec.count && !rec.denied && !rec.kicked) && <span className="text-[10px] text-muted-foreground">только отклонённые попытки</span>}
                    </div>
                    <div className="mt-0.5 text-[10px] text-muted-foreground">
                      {rec.first && <>первое: {new Date(rec.first).toLocaleString()} · </>}
                      {rec.last && <>последнее: {new Date(rec.last).toLocaleString()}</>}
                    </div>
                  </div>
                ))}
              </div>}
        </section>

        {/* Ключи + рандомизация */}
        <section className="grid gap-2 rounded-md border border-border border-l-2 border-l-indigo-500/50 bg-card/40 p-3 text-xs">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-indigo-400">🔑 Ключи шифрования</div>
          <div className="grid gap-1">
            <div className="flex items-center gap-2">
              <span className="text-muted-foreground shrink-0">Оригинальный:</span>
              <span className="min-w-0 flex-1 truncate font-mono text-[11px]">{showOrig ? (info?.orig_key || "—") : mask(info?.orig_key)}</span>
              <button type="button" className="shrink-0 rounded border border-border px-1.5 py-0.5 text-[10px] hover:bg-muted" onClick={() => setShowOrig((v) => !v)}>{showOrig ? "скрыть" : "показать"}</button>
              {info?.orig_key && <button type="button" className="shrink-0 rounded border border-border px-1.5 py-0.5 text-[10px] hover:bg-muted" onClick={() => { void olcSafeCopy(info.orig_key); setMsg("Ключ скопирован"); }}>копировать</button>}
            </div>
            <div className="grid gap-1">
              <span className="text-muted-foreground">Рандомизированный:</span>
              {!kr?.enabled
                ? <span className="text-muted-foreground">Рандомизация ключей выключена</span>
                : kr?.rand_type === 2
                  ? <div className="grid gap-0.5">
                      <div className="flex items-center gap-2">
                        <span className="rounded bg-sky-500/15 px-1.5 text-[10px] text-sky-400">🔄 тип 2 · посекундно</span>
                        <span className="min-w-0 flex-1 truncate font-mono text-[11px] text-sky-300">{showRand ? (kr?.randomized_key || "…") : mask(kr?.randomized_key)}</span>
                        <button type="button" className="shrink-0 rounded border border-border px-1.5 py-0.5 text-[10px] hover:bg-muted" onClick={() => setShowRand((v) => !v)}>{showRand ? "скрыть" : "показать"}</button>
                      </div>
                      <div className="text-[10px] text-muted-foreground">Меняется каждую секунду (значение выше обновляется live).</div>
                    </div>
                  : <div className="flex items-center gap-2">
                      <span className="rounded bg-emerald-500/15 px-1.5 text-[10px] text-emerald-500">🔒 тип 1 · статичный</span>
                      <span className="min-w-0 flex-1 truncate font-mono text-[11px] text-emerald-300">{showRand ? (kr?.randomized_key || "—") : mask(kr?.randomized_key)}</span>
                      <button type="button" className="shrink-0 rounded border border-border px-1.5 py-0.5 text-[10px] hover:bg-muted" onClick={() => setShowRand((v) => !v)}>{showRand ? "скрыть" : "показать"}</button>
                      {kr?.randomized_key && <button type="button" className="shrink-0 rounded border border-border px-1.5 py-0.5 text-[10px] hover:bg-muted" onClick={() => { void olcSafeCopy(kr.randomized_key); setMsg("Ключ скопирован"); }}>копировать</button>}
                    </div>}
            </div>
          </div>
          <div className="text-[10px] leading-snug text-muted-foreground">Рандомизированная версия ключа отражает текущую рандомизацию клиента (тип 1 — статичная, тип 2 — меняется каждую секунду). Оригинальный ключ инстанса ротирует только «♻️ Автосмена ключей».</div>
        </section>

        {msg && <div className="mt-2 text-[11px] text-amber-500">{msg}</div>}
      </div>
    </div>
  );
}

function CtrlLockToggle() {
  const [on, setOn] = useState(() => readStoredBool("olc-ctrl-lock-v1", true));
  return (
    <div className="flex items-center justify-between border-b border-border py-2">
      <div>
        <div className="text-sm font-medium">Блокировать управление при сохранении</div>
        <div className="text-xs text-muted-foreground">Защита от двойных нажатий: кнопки/поля на миг блокируются во время сохранения. Выключите, если мешает при быстром переключении.</div>
      </div>
      <div className="inline-flex items-center gap-2 text-xs cursor-pointer">
        <OlcToggleButton  checked={on} onChange={() => { const v = !on; setOn(v); writeStoredBool("olc-ctrl-lock-v1", v); }} className="cursor-pointer" />

      </div>
    </div>
  );
}

function App() {
  useEffect(() => {
    const finishInput = (e: KeyboardEvent) => {
      if (e.key !== "Enter" || e.shiftKey || e.ctrlKey || e.altKey || e.metaKey || e.isComposing) return;
      const el = e.target;
      if (!(el instanceof HTMLInputElement)) return;
      if (["button", "submit", "reset", "checkbox", "radio", "file", "range", "color"].includes(el.type)) return;
      e.preventDefault();
      el.blur();
    };
    document.addEventListener("keydown", finishInput, true); // olc-plain-enter-blur
    return () => document.removeEventListener("keydown", finishInput, true);
  }, []);
  const { t, lang, setLang } = usePanelLang();
  const [authenticated, setAuthenticated] = useState<boolean | null>(null);
  const [setupRequired, setSetupRequired] = useState(false);
  const [state, setState] = useState<State | null>(null);
  const [settings, setSettings] = useState<SettingsState | null>(null);
  const [metrics, setMetrics] = useState<Metrics | null>(null);
  const [audit, setAudit] = useState<AuditEvent[]>([]);
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const [pendingLocations, setPendingLocations] = useState<Record<string, string>>({});
  const [createOpen, setCreateOpen] = useState(false);
  const [editClient, setEditClient] = useState<ClientState | null>(null);
  const [createLocationClient, setCreateLocationClient] = useState<ClientState | null>(null);
  const [editLocation, setEditLocation] = useState<{ client: ClientState; location: LocationState; index: number } | null>(null);
  const [logTarget, setLogTarget] = useState<{ clientID: string; location: LocationState } | null>(null);
  const [clientLogTarget, setClientLogTarget] = useState<ClientState | null>(null);
  const [qrTarget, setQrTarget] = useState<{ clientID: string; location: LocationState } | null>(null);
  const [instanceInfoTarget, setInstanceInfoTarget] = useState<{ clientID: string; location: LocationState } | null>(null);
  const [showSettings, setShowSettings] = useState(false);
  const [pendingModal] = useState<string>(() => {
    try { return window.localStorage.getItem("olc-active-modal-v1") || ""; } catch { return ""; }
  });
  const modalRestoredRef = useRef(false);
  const [showAutodetectInline, setShowAutodetectInline] = useState(false);
  const [subscriptionRandomizationOpen, setSubscriptionRandomizationOpen] = useState(() => readStoredBool("olc-sub-rand-open-v1", false));
  const [autodetectMiniOpen, setAutodetectMiniOpen] = useState(false);
  const [logs, setLogs] = useState<LogLine[]>([]);
  const [logsVerbose, setLogsVerbose] = useState(() => readStoredBool(LOGS_VERBOSE_STORAGE_KEY, false));
  const [logsLive, setLogsLiveRaw] = useState(() => readStoredBool(LOGS_LIVE_STORAGE_KEY, false));
  const setLogsLive = useCallback(
    (v: boolean | ((prev: boolean) => boolean)) => {
      setLogsLiveRaw((prev) => {
        const next = typeof v === "function" ? (v as (p: boolean) => boolean)(prev) : v;
        writeStoredBool(LOGS_LIVE_STORAGE_KEY, next);
        return next;
      });
    },
    [],
  );
  const [autologi, setAutologi] = useState(true);
  // effective LIVE: autologi forces continuous tailing; otherwise the user's LIVE toggle
  const instanceLogsLive = autologi || logsLive;
  const clientLogsLive = autologi || logsLive;
  const setInstanceLogsLive = setLogsLive;
  const setClientLogsLive = setLogsLive;
  const [clientLogs, setClientLogs] = useState<ClientLogGroup[]>([]);
  const instanceLogScroll = useStickyLogScroll<HTMLDivElement>([logs], Boolean(logTarget));
  const clientLogScroll = useStickyLogScroll<HTMLDivElement>([clientLogs], Boolean(clientLogTarget));
  const [createForm, setCreateForm] = useState<ClientForm>(defaultForm);
  const [editForm, setEditForm] = useState<ClientForm>(defaultForm);
  const [locationForm, setLocationForm] = useState<ClientLocationForm>(defaultLocationForm);
  const [locationModalError, setLocationModalError] = useState("");
  const [settingsForm, setSettingsForm] = useState<SettingsForm>(defaultSettingsForm);
  const [passwordForm, setPasswordForm] = useState({ current: "", next: "", repeat: "" });
  const [selectiveRandomizationOpen, setSelectiveRandomizationOpen] = useState(() => readStoredBool("olc-sel-rand-open-v1", false));
  const [globalRandomizationEnabled, setGlobalRandomizationEnabled] = useState(false);
  const [globalRandomizationScope, setGlobalRandomizationScope] = useState("both");
  const [randTypeTarget, setRandTypeTarget] = useState<string | null>(null);
  const [subQrTarget, setSubQrTarget] = useState<string | null>(null);
  const [globalProxyEnabled, setGlobalProxyEnabled] = useState(false);
  useEffect(() => {
    let stop = false;
    const loadGlobalProxy = async () => {
      try {
        const r = await fetch("/api/settings/olcrtc", { cache: "no-store" });
        const b = await r.json();
        if (!stop) setGlobalProxyEnabled(Boolean(b.settings?.global_socks_enabled));
      } catch { /* keep last known value */ }
    };
    void loadGlobalProxy();
    const id = window.setInterval(loadGlobalProxy, 5000);
    const onSaved = (ev: Event) => {
      setGlobalProxyEnabled(Boolean((ev as CustomEvent).detail?.enabled));
      void loadGlobalProxy();
    };
    window.addEventListener("olc-global-proxy-saved", onSaved);
    return () => { stop = true; window.clearInterval(id); window.removeEventListener("olc-global-proxy-saved", onSaved); };
  }, []);
  const [globalAccessEnabled, setGlobalAccessEnabled] = useState(false);
  const [accessCfg, setAccessCfg] = useState<Record<string, boolean>>({});
  const [accessLoaded, setAccessLoaded] = useState(false);
  const [accessClient, setAccessClientRaw] = useState<string | null>(() => { try { return localStorage.getItem("olc-modal-client-access-v1") || null; } catch { return null; } });
  const setAccessClient = (v: string | null) => { try { if (v) localStorage.setItem("olc-modal-client-access-v1", v); else localStorage.removeItem("olc-modal-client-access-v1"); } catch { /* ignore */ } setAccessClientRaw(v); };
  useEffect(() => {
    let stop = false;
    const load = async () => { try { const r = await fetch("/api/access/settings", { cache: "no-store" }); const b = await r.json(); if (!stop) { setGlobalAccessEnabled(!!b.enabled); const m: Record<string, boolean> = {}; const cl = b.clients || {}; Object.keys(cl).forEach((k) => { const c = cl[k] || {}; m[k] = !!((c.mode && c.mode !== "off") || (Array.isArray(c.allow) && c.allow.length) || (Array.isArray(c.allow_ips) && c.allow_ips.length) || c.conn_enforce); }); setAccessCfg(m); setAccessLoaded(true); } } catch { /* ignore */ } };
    void load();
    const id = window.setInterval(load, 5000);
    const onAccessSaved = (ev: Event) => { const d = (ev as CustomEvent).detail || {}; if (typeof d.enabled === "boolean") setGlobalAccessEnabled(d.enabled); void load(); };
    window.addEventListener("olc-access-saved", onAccessSaved);
    return () => { stop = true; window.clearInterval(id); window.removeEventListener("olc-access-saved", onAccessSaved); };
  }, []);
  const [expandedClients, setExpandedClients] = useState<Record<string, boolean>>({});

  const checkAuth = async () => {
    try {
      const res = await fetch("/api/auth/me", { cache: "no-store" });
      if (!res.ok) {
        try {
          const body = (await res.json()) as { setup_required?: boolean };
          setSetupRequired(Boolean(body.setup_required));
        } catch {
          setSetupRequired(false);
        }
        setAuthenticated(false);
        return;
      }
      const body = (await res.json()) as { setup_required?: boolean };
      setSetupRequired(Boolean(body.setup_required));
      if (body.setup_required) {
        setAuthenticated(false);
        return;
      }
      setAuthenticated(true);
    } catch {
      setAuthenticated(false);
    }
  };

  const afterLogin = async () => {
    await checkAuth();
    await Promise.all([loadState(), loadSettings(), loadMetrics(), loadAudit()]).catch((err) => setNotice(err.message));
  };

  const loadState = async () => {
    const res = await request("/api/state", { cache: "no-store" });
    setState(normalizePanelState((await res.json()) as State));
  };

  const loadMetrics = async () => {
    const res = await request("/api/metrics", { cache: "no-store" });
    setMetrics((await res.json()) as Metrics);
  };

  const loadSettings = async () => {
    const res = await request("/api/settings", { cache: "no-store" });
    const body = (await res.json()) as SettingsState;
    setSettings(body);
    setSettingsForm({
      name: body.name,
      port: String(body.port),
      subscription_path: body.subscription_path,
      refresh: body.refresh ?? "",
    });

    // Load global randomization state
    try {
      const randRes = await request("/api/settings/randomization/global", { cache: "no-store" });
      const randBody = (await randRes.json()) as { enabled: boolean; rand_scope?: string };
      setGlobalRandomizationEnabled(randBody.enabled ?? false);
      setGlobalRandomizationScope(randBody.rand_scope === "crypto" || randBody.rand_scope === "client_id" ? randBody.rand_scope : "both");
    } catch {
      setGlobalRandomizationEnabled(false);
    }

    // Load autologi (auto-refresh logs) state
    try {
      const logsRes = await request("/api/settings/logs", { cache: "no-store" });
      const logsBody = (await logsRes.json()) as { auto_refresh?: boolean };
      setAutologi(logsBody.auto_refresh ?? true);
    } catch {
      setAutologi(true);
    }
  };

  useEffect(() => {
    const refreshRandomization = () => { void loadState(); void loadSettings(); };
    window.addEventListener("olc-randomization-saved", refreshRandomization);
    return () => window.removeEventListener("olc-randomization-saved", refreshRandomization);
  }, []);

  const loadAudit = async () => {
    const res = await request("/api/audit", { cache: "no-store" });
    const body = (await res.json()) as { events: AuditEvent[] };
    setAudit(body.events ?? []);
  };

  useEffect(() => {
    checkAuth();
  }, []);

  useEffect(() => {
    const handler = () => setAuthenticated(false);
    window.addEventListener("olcrtc-auth-required", handler);
    return () => window.removeEventListener("olcrtc-auth-required", handler);
  }, []);

  useEffect(() => {
    if (!authenticated) return;
    Promise.all([loadState(), loadSettings(), loadMetrics(), loadAudit(), fetchInstanceDefaultsFromAPI()]).catch((err) =>
      setNotice(err.message),
    );
  }, [authenticated]);

  // Persist which App-level modal is currently open (skip until restore ran).
  useEffect(() => {
    if (!modalRestoredRef.current) return;
    let d: any = null;
    if (showSettings) d = { k: "settings" };
    else if (createOpen) d = { k: "create" };
    else if (editClient) d = { k: "editClient", id: editClient.client_id };
    else if (createLocationClient) d = { k: "createLocation", id: createLocationClient.client_id };
    else if (editLocation) d = { k: "editLocation", id: editLocation.client.client_id, room: editLocation.location.room_id, idx: editLocation.index };
    else if (qrTarget) d = { k: "qr", id: qrTarget.clientID, room: qrTarget.location.room_id };
    else if (instanceInfoTarget) d = { k: "instanceInfo", id: instanceInfoTarget.clientID, room: instanceInfoTarget.location.room_id };
    else if (subQrTarget) d = { k: "clientQr", id: subQrTarget };
    else if (logTarget) d = { k: "instanceLogs", id: logTarget.clientID, room: logTarget.location.room_id };
    else if (clientLogTarget) d = { k: "clientLogs", id: clientLogTarget.client_id };
    try {
      if (d) window.localStorage.setItem("olc-active-modal-v1", JSON.stringify(d));
      else window.localStorage.removeItem("olc-active-modal-v1");
    } catch {
      /* ignore */
    }
  }, [showSettings, createOpen, editClient, createLocationClient, editLocation, qrTarget, instanceInfoTarget, subQrTarget, logTarget, clientLogTarget]);

  // Restore the previously-open modal once client state is available after reload.
  useEffect(() => {
    if (!authenticated || modalRestoredRef.current || !state) return;
    modalRestoredRef.current = true;
    if (!pendingModal) return;
    let d: any;
    try { d = JSON.parse(pendingModal); } catch { return; }
    const cs = state.clients ?? [];
    const findClient = (id: string) => cs.find((c) => c.client_id === id);
    const findLoc = (c: any, room: string) => c?.locations?.find((l: any) => l.room_id === room);
    switch (d?.k) {
      case "settings": void openSettings(); break;
      case "create": openCreate(); break;
      case "editClient": { const c = findClient(d.id); if (c) openEdit(c); break; }
      case "createLocation": { const c = findClient(d.id); if (c) openCreateLocation(c); break; }
      case "editLocation": { const c = findClient(d.id); const loc = findLoc(c, d.room); if (c && loc) openEditLocation(c, loc, d.idx); break; }
      case "qr": { const c = findClient(d.id); const loc = findLoc(c, d.room); if (loc) setQrTarget({ clientID: d.id, location: loc }); break; }
      case "instanceInfo": { const c = findClient(d.id); const loc = findLoc(c, d.room); if (loc) setInstanceInfoTarget({ clientID: d.id, location: loc }); break; }
      case "clientQr": { const c = findClient(d.id); if (c) setSubQrTarget(d.id); break; }
      case "instanceLogs": { const c = findClient(d.id); const loc = findLoc(c, d.room); if (loc) void openLogs(d.id, loc); break; }
      case "clientLogs": { const c = findClient(d.id); if (c) void openClientLogs(c); break; }
      default: break;
    }
  }, [authenticated, state, pendingModal]);

  useEffect(() => {
    if (!authenticated) return;
    const id = window.setInterval(() => {
      Promise.all([loadState(), loadMetrics()]).catch((err) => setNotice(err.message));
    }, 5000);
    return () => window.clearInterval(id);
  }, [authenticated]);

  useEffect(() => {
    writeStoredBool(LOGS_VERBOSE_STORAGE_KEY, logsVerbose);
  }, [logsVerbose]);


  const locationActionKey = (clientID: string, location: LocationState) =>
    `${clientID}:${location.room_id}:${location.transport}`;

  const clients = state?.clients ?? [];
  const currentSubscriptionPath = settings?.subscription_path ?? state?.subscription_path ?? "";

  const runAction = async (action: () => Promise<void>, okText: string) => {
    setBusy(true);
    setNotice("");
    try {
      await action();
      setNotice(okText);
      await loadState();
      await loadMetrics();
      await loadAudit();
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setNotice(message);
      if (editLocation || createLocationClient) setLocationModalError(message);
    } finally {
      setBusy(false);
    }
  };

  const openCreate = () => {
    setCreateForm(normalizeForm({ ...defaultForm, locations: [{ ...defaultLocationForm }] }));
    setCreateOpen(true);
  };

  const openEdit = (client: ClientState) => {
    setEditClient(client);
    setEditForm(
      normalizeForm({
        client_id: client.client_id,
        refresh: client.refresh ?? "",
        quota: client.quota ?? {},
        proxy: proxyFromState(client.proxy),
        locations: [{ ...defaultLocationForm, proxy: emptyProxy() }],
      }),
    );
  };

  const openCreateLocation = (client: ClientState) => {
    setCreateLocationClient(client);
    setLocationForm({ ...defaultLocationForm });
  };

  useEffect(() => {
    if (!showSettings) return;
    const onUnload = () => { void saveSettingsAuto(); };
    window.addEventListener("beforeunload", onUnload);
    return () => window.removeEventListener("beforeunload", onUnload);
  });

  const openSettings = async () => {
    setShowSettings(true);
    setShowAutodetectInline(false);
    setNotice("");
    try {
      await loadSettings();
    } catch (err) {
      setNotice(err instanceof Error ? err.message : String(err));
    }
  };

  const openEditLocation = (client: ClientState, location: LocationState, index: number) => {
    setEditLocation({ client, location, index });
    setLocationForm(locationStateForEdit(location));
  };

  const addClient = () =>
    runAction(async () => {
      const cidErr = validateClientIDInput(createForm.client_id);
      if (cidErr) throw new Error(cidErr);
      const locs = createForm.locations.map((loc) =>
        normalizeLocationForm({ ...loc, key: loc.key.trim() || randomHex64() }),
      );
      assertLocationsValid(locs);
      await request("/api/clients", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: createForm.client_id.trim(),
          refresh: cleanRefresh(createForm.refresh),
          quota: cleanQuota(createForm.quota),
          client_proxy: proxyForSubmit(createForm.proxy),
          locations: locationsForSubmit(locs),
        }),
      });
      setCreateOpen(false);
    }, "Клиент создан");

  const updateClient = () =>
    runAction(async () => {
      if (!editClient) return;
      if (!editForm.client_id.trim()) throw new Error("Укажи ID клиента");
      await request(`/api/clients/${encodeURIComponent(editClient.client_id)}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: editForm.client_id.trim(),
          refresh: cleanRefresh(editForm.refresh),
          quota: cleanQuota(editForm.quota),
          client_proxy: proxyForSubmit(editForm.proxy),
        }),
      });
      const _oldId = editClient.client_id;
      const _newId = editForm.client_id.trim();
      if (_newId !== _oldId) {
        setAccessCfg((prev) => { if (prev[_oldId] === undefined) return prev; const m = { ...prev }; m[_newId] = m[_oldId]; delete m[_oldId]; return m; });
      }
      setEditClient(null);
    }, "Клиент обновлен");

  const addLocation = () => {
    if (!createLocationClient) return;
    const prepared = normalizeLocationForm({
      ...locationForm,
      key: locationForm.key.trim() || randomHex64(),
    });
    const roomErr = prepared.carrier === "jitsi" && !prepared.jitsi_instance.trim()
      ? "Укажите Jitsi Server"
      : validateRoomIDInput(prepared.carrier === "jitsi" ? jitsiRoomForSubmit(prepared) : prepared.room_id, prepared.carrier);
    if (roomErr) {
      setLocationModalError(roomErr);
      return;
    }
    if (!prepared.name.trim()) {
      setLocationModalError("Укажите название локации");
      return;
    }
    setLocationModalError("");
    void runAction(async () => {
      await request(`/api/clients/${encodeURIComponent(createLocationClient.client_id)}/locations`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          locations: locationsForSubmit([prepared]),
        }),
      });
      setCreateLocationClient(null);
      setExpandedClients((current) => ({ ...current, [createLocationClient.client_id]: true }));
    }, "Локация создана");
  };

  const updateLocation = () =>
    runAction(async () => {
      if (!editLocation) return;
      setLocationModalError("");
      assertLocationsValid([normalizeLocationForm(locationForm)]);
      const nextLocations = editLocation.client.locations.map((location, index) =>
        index === editLocation.index
          ? normalizeLocationForm(locationForm)
          : locationStateForEdit(location),
      );
      await request(`/api/clients/${encodeURIComponent(editLocation.client.client_id)}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: editLocation.client.client_id,
          refresh: cleanRefresh(editLocation.client.refresh ?? ""),
          quota: cleanQuota(editLocation.client.quota),
          client_proxy: proxyForSubmit(proxyFromState(editLocation.client.proxy)),
          locations: locationsForSubmit(nextLocations),
        }),
      });
      setEditLocation(null);
    }, "Локация обновлена");

  const deleteClient = (id: string) =>
    runAction(async () => {
      if (!await olcConfirm(`Удалить клиента ${id} и все его локации?`)) return;
      await request(`/api/clients/${encodeURIComponent(id)}`, { method: "DELETE" });
    }, "Клиент удален");

  const deleteLocation = async (clientID: string, location: LocationState) => {
    if (!await olcConfirm(`Удалить локацию ${location.name || location.room_id}?`)) return;
    const key = locationActionKey(clientID, location);
    setPendingLocations((p) => ({ ...p, [key]: "Удаление… (~5–15 с)" }));
    setNotice("Удаление локации… остальные кнопки доступны");
    try {
      await request(`/api/clients/${encodeURIComponent(clientID)}/locations/${encodeURIComponent(location.room_id)}`, {
        method: "DELETE",
      });
      setNotice("Локация удалена (инстанс останавливается в фоне)");
      await loadState();
      await loadMetrics();
    } catch (err) {
      setNotice(err instanceof Error ? err.message : String(err));
    } finally {
      setPendingLocations((p) => {
        const next = { ...p };
        delete next[key];
        return next;
      });
    }
  };

  const restartLocation = (clientID: string, location: LocationState) =>
    runAction(async () => {
      await request("/api/actions/restart", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: clientID,
          room_id: location.room_id,
          transport: location.transport,
        }),
      });
    }, `${clientID} перезапущен`);

  const logout = async () => {
    await fetch("/api/auth/logout", { method: "POST" });
    setAuthenticated(false);
    setState(null);
    setSettings(null);
    setMetrics(null);
  };

  const changePassword = () =>
    runAction(async () => {
      if (passwordForm.next !== passwordForm.repeat) throw new Error("Новые пароли не совпадают");
      await request("/api/auth/password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ current_password: passwordForm.current, new_password: passwordForm.next }),
      });
      setPasswordForm({ current: "", next: "", repeat: "" });
      setAuthenticated(false);
    }, "Пароль изменен, войди заново");

  const saveSettingsName = async (nextName: string) => {
    const name = nextName.trim();
    if (!name) throw new Error("Укажи название сервера");
    const port = Number(settingsForm.port);
    if (!Number.isInteger(port) || port <= 0 || port > 65535) throw new Error("Порт должен быть от 1 до 65535");
    const res = await request("/api/settings", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name,
        port,
        subscription_path: settingsForm.subscription_path.trim(),
        refresh: cleanRefresh(settingsForm.refresh),
      }),
    });
    const body = (await res.json()) as SettingsState;
    setSettings(body);
    setSettingsForm({
      name: body.name,
      port: String(body.port),
      subscription_path: body.subscription_path,
      refresh: body.refresh ?? "",
    });
    await loadState();
    await loadAudit();
    setNotice("Профиль переименован");
  };

  const settingsFormValid = () => {
    const port = Number(settingsForm.port);
    return Boolean(settingsForm.name.trim()) && Number.isInteger(port) && port > 0 && port <= 65535;
  };
  // Autosave used on close/unload: silent, validated, no form reset (avoids input churn).
  const saveSettingsAuto = async () => {
    if (!settingsFormValid()) return;
    try {
      const port = Number(settingsForm.port);
      await request("/api/settings", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: settingsForm.name.trim(),
          port,
          subscription_path: settingsForm.subscription_path.trim(),
          refresh: cleanRefresh(settingsForm.refresh),
        }),
      });
      loadState().catch(() => {});
      loadAudit().catch(() => {});
    } catch {
      /* best-effort; keep silent on close */
    }
  };

  const saveSettings = async () => {
    setBusy(true);
    setNotice("");
    try {
      const port = Number(settingsForm.port);
      if (!settingsForm.name.trim()) throw new Error("Укажи название сервера");
      if (!Number.isInteger(port) || port <= 0 || port > 65535) throw new Error("Порт должен быть от 1 до 65535");
      const res = await request("/api/settings", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: settingsForm.name.trim(),
          port,
          subscription_path: settingsForm.subscription_path.trim(),
          refresh: cleanRefresh(settingsForm.refresh),
        }),
      });
      const body = (await res.json()) as SettingsState;
      setSettings(body);
      setSettingsForm({
        name: body.name,
        port: String(body.port),
        subscription_path: body.subscription_path,
        refresh: body.refresh ?? "",
      });
      await loadState();
      await loadAudit();
      if (body.restart_required) {
        setNotice("Настройки сохранены. Новый порт применится после рестарта сервиса.");
      } else {
        setNotice("Настройки сохранены");
      }
    } catch (err) {
      setNotice(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  };

  const refreshLogs = useCallback(async (clientID: string, location: LocationState) => {
    const res = await request(logsURL(clientID, location), { cache: "no-store" });
    const body = (await res.json()) as { logs: LogLine[] };
    setLogs((prev) => olcMergeTail(prev, body.logs ?? [], (x) => x.time + "|" + x.stream + "|" + x.line, 1500));
  }, []);

  const openLogs = async (clientID: string, location: LocationState) => {
    setLogs([]);
    setNotice("");
    try {
      await refreshLogs(clientID, location);
      setLogTarget({ clientID, location });
    } catch (err) {
      setLogTarget(null);
      setNotice(err instanceof Error ? err.message : String(err));
    }
  };

  const refreshClientLogs = useCallback(async (client: ClientState) => {
    const groups = await Promise.all(
      client.locations.map(async (location) => {
        try {
          const res = await request(logsURL(client.client_id, location), { cache: "no-store" });
          const body = (await res.json()) as { logs: LogLine[] };
          return { location, lines: body.logs ?? [] };
        } catch (err) {
          return { location, lines: [], error: err instanceof Error ? err.message : String(err) };
        }
      }),
    );
    setClientLogs(groups);
  }, []);

  const openClientLogs = (client: ClientState) => {
    setNotice("");
    setClientLogTarget(client);
  };

  useEffect(() => {
    if (!logTarget || !instanceLogsLive) return;
    const id = window.setInterval(() => {
      refreshLogs(logTarget.clientID, logTarget.location).catch((err) =>
        setNotice(err instanceof Error ? err.message : String(err)),
      );
    }, LOGS_LIVE_INTERVAL_MS);
    return () => window.clearInterval(id);
  }, [logTarget, instanceLogsLive, refreshLogs]);

  // client-log poll removed: панели ClientLogPanel опрашивают себя сами

  const copyLogs = () =>
    runAction(async () => {
      const text = logs.map((line) => `[${line.time}] ${line.stream}: ${line.line}`).join("\n");
      try {
        await navigator.clipboard.writeText(text);
      } catch {
        const textarea = document.createElement("textarea");
        textarea.value = text;
        textarea.style.position = "fixed";
        textarea.style.opacity = "0";
        document.body.appendChild(textarea);
        textarea.select();
        try {
          document.execCommand("copy");
        } finally {
          document.body.removeChild(textarea);
        }
      }
    }, t("logsCopied"));

  const copyOlcBoxLink = (clientID: string, uri: string) =>
    runAction(async () => {
      if (!uri) throw new Error("OlcBox ссылка не найдена");
      await olcSafeCopy(uri);
    }, t("linkCopied", { id: clientID }));

  const toggleRandomization = (clientID: string, currentlyEnabled: boolean, randType?: number) =>
    runAction(async () => {
      const endpoint = currentlyEnabled ? "disable" : "enable";
      const qs = !currentlyEnabled && randType ? `?rand_type=${randType}` : "";
      await request(`/api/clients/${clientID}/randomization/${endpoint}${qs}`, { method: "POST" });
      await loadState();
    }, currentlyEnabled ? "Randomization disabled" : "Randomization enabled");

  const copySubscription = (clientID: string) =>
    runAction(async () => {
      await olcSafeCopy(subscriptionURL(clientID, currentSubscriptionPath));
    }, t("subCopied", { id: clientID }));

  if (authenticated === null) {
    return <div className="grid min-h-screen place-items-center text-sm text-muted-foreground">{t("loading")}</div>;
  }

  if (!authenticated) {
    return <LoginView setupRequired={setupRequired} onLogin={afterLogin} />;
  }

  const serversMemoryBytes = (metrics?.children ?? []).reduce(
    (total, child) => total + (child.runtime?.memory_bytes ?? 0),
    0,
  );

  return (
    <>
    <UpdateAvailableToast />
    <div className="min-h-screen">
      <header className="border-b border-border bg-background/95">
        <div className="mx-auto max-w-7xl px-5 py-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold tracking-normal">OlcRTC Manager</h1>
            <div className="flex flex-wrap items-center gap-2">
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={openSettings}
              >
                <Settings className="h-4 w-4" />
                {t("settings")}
              </button>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
                disabled={busy}
                onClick={() =>
                  runAction(async () => {
                    await loadState();
                    await loadMetrics();
                  }, t("updated"))
                }
              >
                <RefreshCw className="h-4 w-4" />
                {t("refresh")}
              </button>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={logout}
              >
                <LogOut className="h-4 w-4" />
                {t("logout")}
              </button>
            </div>
          </div>
          <div className="mt-2 grid gap-2 xl:grid-cols-[1fr_auto_1fr] xl:items-center">
            <div className="flex flex-wrap items-center gap-2 xl:justify-start">
              <ComponentsDrawerButton />
              <HeaderMetric label="Panel mem" value={formatBytes(metrics?.memory.heap_alloc_bytes)} />
              <HeaderMetric label="Servers mem" value={formatBytes(serversMemoryBytes)} />
              <HeaderMetric label="Panel PID" value={metrics?.manager.pid ?? "..."} />
            </div>
            <div className="flex min-h-9 min-w-0 items-center justify-start xl:justify-center">
              <HeaderNetworkToggles />
            </div>
            <div className="flex flex-wrap items-center gap-2 xl:justify-end">
              <ProjectUpdateButton disabled={busy} />
              <NotificationBell />
              <ErrorsSummaryButton />
            </div>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-7xl px-5 py-6">
        <section className="grid gap-3 md:grid-cols-3">
          <ProfileStatCard name={state?.name ?? ""} onSave={async (next) => { await saveSettingsName(next); }} />
          <StatCard icon={<Users className="h-4 w-4" />} label={t("clients")} value={state?.client_count ?? "..."} />
          <StatCard icon={<Activity className="h-4 w-4" />} label={t("instances")} value={state?.running_count ?? "..."} />
        </section>

        <FeaturesPanel />

        <section className="mt-4 rounded-lg border border-border bg-card p-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 className="text-lg font-semibold tracking-normal">{t("clients")}</h2>
            </div>
            <div className="flex flex-wrap gap-2">
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md bg-primary px-3 text-sm font-medium text-black hover:bg-primary/90"
                onClick={openCreate}
              >
                <Plus className="h-4 w-4" />
                {t("createClient")}
              </button>
            </div>
          </div>

          <div className="mt-3 min-h-5 text-sm text-muted-foreground">{notice}</div>

          <div className="mt-4 grid gap-3">
            {clients.map((client) => {
              const expanded = expandedClients[client.client_id] ?? true;
              const running = (client.locations ?? []).filter((location) => location.runtime?.running).length;

              return (
                <div key={client.client_id} className="overflow-hidden rounded-lg border border-border bg-background">
                  <div className="grid gap-3 p-3 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-center">
                    <button
                      className="flex min-w-0 items-center gap-3 text-left"
                      onClick={() => setExpandedClients((current) => ({ ...current, [client.client_id]: !expanded }))}
                    >
                      <span className="grid h-8 w-8 shrink-0 place-items-center rounded-md border border-border bg-card text-muted-foreground">
                        {expanded ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                      </span>
                      <span className="min-w-0">
                        <span className="block truncate font-semibold">{client.client_id}</span>
                        {globalRandomizationScope !== "crypto" && client.randomization?.enabled ? (
                          <span className="mt-1 block truncate text-xs text-muted-foreground">
                            {client.randomization?.rand_type === 2
                              ? "🔄 ротация каждую секунду"
                              : (client.randomization?.randomized_id ? `🔒 ${client.randomization.randomized_id}` : "🔒 рандомизированный хэш")}
                          </span>
                        ) : globalRandomizationScope !== "crypto" && globalRandomizationEnabled && client.randomization?.randomized_id ? (
                          <span className="mt-1 block truncate text-xs text-muted-foreground">
                            🔒 {client.randomization.randomized_id}
                          </span>
                        ) : null}
                        <Type2Warning show={!!(client.randomization?.enabled && client.randomization?.rand_type === 2 && accessLoaded && !globalAccessEnabled && !accessCfg[client.client_id])} />
                        <span className="mt-1 block text-xs text-muted-foreground">
                          {clientSummary(client, running)}
                        </span>
                      </span>
                    </button>

                    <div className="flex flex-wrap gap-2 lg:justify-end">
                      <button
                        className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                        disabled={busy}
                        title="QR и ссылки подписки"
                        onClick={() => setSubQrTarget(client.client_id)}
                      >
                        📱 Qr
                      </button>
                      <button
                        className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                        disabled={busy}
                        onClick={() => openClientLogs(client)}
                      >
                        <Terminal className="h-4 w-4" />
                        Логи
                      </button>
                      <button
                        className={`inline-flex h-8 items-center gap-2 rounded-md border px-2 text-sm transition-all duration-200 ${
                          client.randomization?.enabled || globalRandomizationEnabled
                            ? "border-green-500/40 bg-green-500/10 text-green-600 hover:bg-green-500/20"
                            : "border-amber-500/40 bg-amber-500/10 text-amber-600 hover:bg-amber-500/20"
                        } ${globalRandomizationEnabled ? 'opacity-50 cursor-not-allowed' : 'disabled:opacity-60'}`}
                        disabled={busy || globalRandomizationEnabled}
                        onClick={() => { if (client.randomization?.enabled) { void toggleRandomization(client.client_id, true); } else { setRandTypeTarget(client.client_id); } }}
                        title={
                          globalRandomizationEnabled
                            ? "Глобальная рандомизация включена (сначала отключите глобальную)"
                            : client.randomization?.enabled
                            ? "Рандомизация ВКЛ — нажмите для отключения"
                            : "Рандомизация ВЫКЛ — нажмите для включения"
                        }
                      >
                        🎲 {globalRandomizationEnabled ? "ON" : client.randomization?.enabled ? `ON · Т${client.randomization?.rand_type || 1}` : "OFF"}
                      </button>
                      <button
                        className="inline-flex h-8 items-center gap-1 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:cursor-not-allowed disabled:opacity-40"
                        disabled={busy || globalAccessEnabled}
                        title={globalAccessEnabled ? "Для доступа к выборочным настройкам доступа по устройству отключите глобальный контроль доступа" : "Выборочный контроль доступа для этой подписки"}
                        onClick={() => setAccessClient(client.client_id)}
                      >
                        ⚙
                      </button>
                      <button
                        className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                        disabled={busy}
                        onClick={() => openEdit(client)}
                      >
                        <Edit3 className="h-4 w-4" />
                        Edit
                      </button>
                      <button
                        className="inline-flex h-8 items-center gap-2 rounded-md border border-destructive/40 px-2 text-sm text-destructive hover:bg-destructive/10 disabled:opacity-60"
                        disabled={busy}
                        onClick={() => deleteClient(client.client_id)}
                      >
                        <Trash2 className="h-4 w-4" />
                        Удалить
                      </button>
                    </div>
                  </div>

                  {expanded && (
                    <div className="border-t border-border/70 p-3">
                      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                        <div className="text-sm font-medium text-muted-foreground">Локации</div>
                        <button
                          className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                          disabled={busy}
                          onClick={() => openCreateLocation(client)}
                        >
                          <Plus className="h-4 w-4" />
                          Добавить локацию
                        </button>
                      </div>
                      <div className="overflow-x-auto">
                        <table className="w-full min-w-[1160px] border-collapse text-sm">
                          <thead>
                            <tr className="border-b border-border text-left text-muted-foreground">
                              <th className="w-[150px] max-w-[150px] py-2 pr-3 font-medium">Локация</th>
                              <th className="py-2 pr-3 font-medium">Room</th>
                              <th className="py-2 pr-3 font-medium">Provider</th>
                              <th className="py-2 pr-3 font-medium">Transport</th>
                              <th className="py-2 pr-3 font-medium">DNS</th>
                              <th className="py-2 pr-3 font-medium">{t("tableStatus")}</th>
                              <th className="py-2 text-right font-medium">{t("locationActions")}</th>
                            </tr>
                          </thead>
                          <tbody>
                            {client.locations.map((loc, index) => (
                              <tr key={`${client.client_id}-${loc.room_id}-${loc.transport}-${index}`} className="border-b border-border/60 last:border-0">
                                <td className="w-[150px] max-w-[150px] py-3 pr-3 font-medium">
                                  <span className="block max-w-[150px] truncate" title={loc.name || "Default"}>
                                    {loc.name || "Default"}
                                  </span>
                                </td>
                                <td className="max-w-[220px] truncate py-3 pr-3 text-muted-foreground">{loc.room_id}</td>
                                <td className="py-3 pr-3">{loc.carrier}</td>
                                <td className="py-3 pr-3">
                                  {loc.transport}
                                  {isLegacyTransport(loc.transport) && (
                                    <span className="ml-1 rounded bg-amber-500/20 px-1.5 py-0.5 text-[10px] uppercase text-amber-300">
                                      {t("legacyTransport")}
                                    </span>
                                  )}
                                </td>
                                <td className="py-3 pr-3 text-muted-foreground">{loc.dns}</td>
                                <td className="py-3 pr-3">
                                  <span
                                    className={`inline-flex rounded-full px-2 py-1 text-xs ${
                                      loc.runtime?.running ? "bg-primary/15 text-primary" : "bg-destructive/15 text-destructive"
                                    }`}
                                  >
                                    {loc.runtime?.status ?? "unknown"}
                                  </span>
                                </td>
                                <td className="w-px whitespace-nowrap py-3 text-right">
                                  <div className="flex flex-nowrap justify-end gap-2">
                                    <button
                                      className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                                      disabled={Boolean(pendingLocations[locationActionKey(client.client_id, loc)])}
                                      onClick={() => restartLocation(client.client_id, loc)}
                                    >
                                      <RefreshCw className="h-4 w-4" />
                                      {t("restart")}
                                    </button>
                                    <button
                                      className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                                      disabled={busy}
                                      onClick={() => openLogs(client.client_id, loc)}
                                    >
                                      <Terminal className="h-4 w-4" />
                                      {t("logs")}
                                    </button>
                                    <button
                                      className="inline-flex h-8 items-center gap-2 rounded-md border border-sky-500/40 bg-sky-500/5 px-2 text-sm text-sky-500 hover:bg-sky-500/15 disabled:opacity-60"
                                      disabled={busy}
                                      title="Инфо, статистика и ключи инстанса"
                                      onClick={() => setInstanceInfoTarget({ clientID: client.client_id, location: loc })}
                                    >
                                      <Info className="h-4 w-4" />
                                      Info
                                    </button>
                                    <button
                                      className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                                      disabled={busy}
                                      onClick={() => setQrTarget({ clientID: client.client_id, location: loc })}
                                    >
                                      {t("qr")}
                                    </button>
                                    <button
                                      className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                                      disabled={busy}
                                      onClick={() => openEditLocation(client, loc, index)}
                                    >
                                      <Edit3 className="h-4 w-4" />
                                      Edit
                                    </button>
                                    <button
                                      className="inline-flex h-8 items-center gap-2 rounded-md border border-destructive/40 px-2 text-sm text-destructive hover:bg-destructive/10 disabled:opacity-60"
                                      disabled={Boolean(pendingLocations[locationActionKey(client.client_id, loc)])}
                                      onClick={() => void deleteLocation(client.client_id, loc)}
                                    >
                                      <Trash2 className="h-4 w-4" />
                                      Удалить
                                    </button>
                                  </div>
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </section>
      </main>

      {createOpen && (
        <Modal title="Создать клиента" onClose={() => setCreateOpen(false)}>
          <div className="p-5">
            <ClientFormFields form={createForm} setForm={setCreateForm} includeClientID globalProxyEnabled={globalProxyEnabled} />
            <div className="mt-5 flex justify-end gap-2">
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => setCreateOpen(false)}
              >
                Отмена
              </button>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md bg-primary px-3 text-sm font-medium text-black hover:bg-primary/90 disabled:opacity-60"
                disabled={busy}
                onClick={addClient}
              >
                <Plus className="h-4 w-4" />
                Создать
              </button>
            </div>
          </div>
        </Modal>
      )}

      {editClient && (
        <Modal title={`Редактировать ${editClient.client_id}`} onClose={() => setEditClient(null)}>
          <div className="p-5">
            <ClientSettingsFields form={editForm} setForm={setEditForm} includeClientID globalProxyEnabled={globalProxyEnabled} />
            <div className="mt-5 flex justify-end gap-2">
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => setEditClient(null)}
              >
                Отмена
              </button>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md bg-primary px-3 text-sm font-medium text-black hover:bg-primary/90 disabled:opacity-60"
                disabled={busy}
                onClick={updateClient}
              >
                <Edit3 className="h-4 w-4" />
                Сохранить
              </button>
            </div>
          </div>
        </Modal>
      )}

      {createLocationClient && (
        <Modal title={`Добавить локацию ${createLocationClient.client_id}`} onClose={() => { setCreateLocationClient(null); setLocationModalError(""); }}>
          <div className="p-5">
            {locationModalError ? <p className="mb-3 rounded border border-destructive/50 bg-destructive/10 p-2 text-sm text-destructive">{locationModalError}</p> : null}
            <LocationFormFields
              location={locationForm}
              setLocation={(loc) => { setLocationForm(loc); setLocationModalError(""); }}
              globalProxyEnabled={globalProxyEnabled}
              clientProxyEnabled={proxyIsEnabled(createLocationClient.proxy)}
            />
            <div className="mt-5 flex justify-end gap-2">
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => setCreateLocationClient(null)}
              >
                Отмена
              </button>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md bg-primary px-3 text-sm font-medium text-black hover:bg-primary/90 disabled:opacity-60"
                disabled={busy}
                onClick={addLocation}
              >
                <Plus className="h-4 w-4" />
                Создать
              </button>
            </div>
          </div>
        </Modal>
      )}

      {editLocation && (
        <Modal title={`Редактировать локацию ${editLocation.location.name || editLocation.location.room_id}`} onClose={() => { setEditLocation(null); setLocationModalError(""); }}>
          <div className="p-5">
            {locationModalError ? <p className="mb-3 rounded border border-destructive/50 bg-destructive/10 p-2 text-sm text-destructive">{locationModalError}</p> : null}
            <LocationFormFields
              location={locationForm}
              setLocation={(next) => { setLocationForm(next); setLocationModalError(""); }}
              globalProxyEnabled={globalProxyEnabled}
              clientProxyEnabled={proxyIsEnabled(editLocation.client.proxy)}
            />
            <div className="mt-5 flex justify-end gap-2">
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => { setEditLocation(null); setLocationModalError(""); }}
              >
                Отмена
              </button>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md bg-primary px-3 text-sm font-medium text-black hover:bg-primary/90 disabled:opacity-60"
                disabled={busy}
                onClick={updateLocation}
              >
                <Edit3 className="h-4 w-4" />
                Сохранить
              </button>
            </div>
          </div>
        </Modal>
      )}

      {instanceInfoTarget && (
        <InstanceInfoModal
          clientID={instanceInfoTarget.clientID}
          roomID={instanceInfoTarget.location.room_id}
          name={instanceInfoTarget.location.name}
          transport={instanceInfoTarget.location.transport}
          autologi={autologi}
          onClose={() => setInstanceInfoTarget(null)}
        />
      )}
      {qrTarget && (
        <Modal title={`QR ${qrTarget.clientID}`} onClose={() => setQrTarget(null)}>
          <div className="grid justify-items-center gap-4 p-5">
            <img
              className="h-64 w-64 rounded-md bg-white p-2"
              src={`https://api.qrserver.com/v1/create-qr-code/?size=256x256&data=${encodeURIComponent(qrTarget.location.uri)}`}
              alt="QR"
            />
            <div className="max-w-full break-all rounded-md border border-border bg-background p-3 font-mono text-xs text-muted-foreground">
              {qrTarget.location.uri}
            </div>
            <div className="flex gap-2">
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => copyOlcBoxLink(qrTarget.clientID, qrTarget.location.uri)}
              >
                {t("copyUri")}
              </button>
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => copySubscription(qrTarget.clientID)}
              >
                {t("copySub")}
              </button>


            </div>
          </div>
        </Modal>
      )}

      {autodetectMiniOpen && <NotificationPreferencesModal onClose={() => setAutodetectMiniOpen(false)} />}
      {accessClient && !globalAccessEnabled && <ClientAccessModal clientId={accessClient} onClose={() => setAccessClient(null)} />}
      {randTypeTarget && (
        <RandTypeModal
          clientId={randTypeTarget}
          onClose={() => setRandTypeTarget(null)}
          onChoose={(ty) => { const cid = randTypeTarget; setRandTypeTarget(null); void toggleRandomization(cid, false, ty); }}
        />
      )}
      {subQrTarget && (() => {
        const c = (state?.clients || []).find((x: any) => x.client_id === subQrTarget);
        if (!c) return null;
        return (
          <ClientQrModal
            client={c}
            path={currentSubscriptionPath}
            globalRandomizationEnabled={globalRandomizationEnabled}
            randomizationScope={globalRandomizationScope}
            globalAccessEnabled={globalAccessEnabled}
            accessConfigured={!!accessCfg[subQrTarget]}
            onClose={() => setSubQrTarget(null)}
          />
        );
      })()}
      {showSettings && (
        <Modal wide title={t('settings')} onClose={() => { void saveSettingsAuto(); setShowSettings(false); }}>
          <div className="grid gap-5 p-5">
            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <div className="text-sm font-medium text-foreground">{t('interface')}</div>
              <label className="grid gap-2 text-sm text-muted-foreground">
                {t('language')}
                <select
                  className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                  value={lang}
                  onChange={(event) => {
                    const next = event.target.value === "en" ? "en" : "ru";
                    setLang(next);
                    try {
                      localStorage.setItem(OLC_PANEL_LANG_KEY, next);
                    } catch {
                      /* ignore */
                    }
                  }}
                >
                  <option value="ru">Русский</option>
                  <option value="en">English</option>
                </select>
              </label>
            </section>

            <BackupSection />

            <AccessControlSection />

            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <div className="text-sm font-medium text-foreground">{t('server')}</div>
              <div className="grid gap-3 md:grid-cols-2">
                <label className="grid gap-2 text-sm text-muted-foreground">
                  {t('serverName')}
                  <input
                    className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                    value={settingsForm.name}
                    onChange={(event) => setSettingsForm({ ...settingsForm, name: event.target.value })}
                    placeholder="OlcRTC VPS"
                  />
                </label>
                <label className="grid gap-2 text-sm text-muted-foreground">
                  {t('panelPort')}
                  <input
                    className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                    type="number"
                    min="1"
                    max="65535"
                    value={settingsForm.port}
                    onChange={(event) => setSettingsForm({ ...settingsForm, port: event.target.value })}
                  />
                </label>
              </div>
              {settings?.port_override && (
                <div className="text-xs text-muted-foreground">{t("portOverride")}</div>
              )}
            </section>

            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <div className="text-sm font-medium text-foreground">{t('subscriptions')}</div>
              <label className="grid gap-2 text-sm text-muted-foreground">
                {t('path')}
                <input
                  className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                  value={settingsForm.subscription_path}
                  onChange={(event) => setSettingsForm({ ...settingsForm, subscription_path: event.target.value })}
                />
              </label>
              <label className="grid gap-2 text-sm text-muted-foreground">
                {t('refreshInterval')}
                <RefreshHoursPicker value={settingsForm.refresh} onChange={(v) => setSettingsForm({ ...settingsForm, refresh: v })} />
              </label>
            </section>

                        <div className="flex items-center justify-between border-b border-border py-2">
              <div>
                <div className="text-sm font-medium">Автологи</div>
                <div className="text-xs text-muted-foreground">Логи обновляются автоматически везде; кнопки LIVE/Обновить скрыты</div>
              </div>
              <div className="inline-flex items-center gap-2 text-xs cursor-pointer">
                <OlcToggleButton

                  checked={autologi}
                  onChange={async () => {
                    const newVal = !autologi;
                    setAutologi(newVal);
                    try {
                      await request("/api/settings/logs", {
                        method: "PATCH",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({ auto_refresh: newVal }),
                      });
                    } catch {
                      setAutologi(!newVal);
                    }
                  }}
                  className="cursor-pointer"
                />
              </div>
            </div>
            <CtrlLockToggle />
                        <div className="flex items-center justify-between border-b border-border py-2">
              <div>
                <div className="text-sm font-medium">Выборочная рандомизация</div>
                <div className="text-xs text-muted-foreground">Индивидуальные настройки рандомизации для каждого клиента</div>
                {!selectiveRandomizationOpen && (() => {
                  const n = (state?.clients || []).filter((c: any) => c.randomization?.enabled).length;
                  return globalRandomizationEnabled
                    ? <div className="mt-0.5 text-[11px] font-medium text-amber-500">🎲 Перекрыта глобальной рандомизацией</div>
                    : n > 0
                      ? <div className="mt-0.5 text-[11px] font-medium text-emerald-500">🎲 Включена у {n} {n === 1 ? "клиента" : "клиентов"}</div>
                      : <div className="mt-0.5 text-[11px] text-muted-foreground">Выключена у всех клиентов</div>;
                })()}
              </div>
              <button
                type="button"
                className="rounded bg-blue-500/10 border border-blue-500/30 px-2 py-1 text-xs text-blue-600 hover:bg-blue-500/20 transition-colors"
                onClick={() => { const v = !selectiveRandomizationOpen; setSelectiveRandomizationOpen(v); writeStoredBool("olc-sel-rand-open-v1", v); }}
              >
                {selectiveRandomizationOpen ? "Скрыть" : "Настроить"}
              </button>
            </div>
            {selectiveRandomizationOpen && (
              <div className="border-l-2 border-primary/30 pl-3">
                <SelectiveRandomizationPanel globalEnabled={globalRandomizationEnabled} />
              </div>
            )}
                        <div className="flex items-center justify-between border-b border-border py-2">
              <div>
                <div className="text-sm font-medium">Subscription Randomization</div>
                <div className="text-xs text-muted-foreground">Защита от enumeration через HMAC-SHA256 hash</div>
                {!subscriptionRandomizationOpen && (
                  globalRandomizationEnabled
                    ? <div className="mt-0.5 text-[11px] font-medium text-amber-500">🟢 Глобальная рандомизация включена</div>
                    : <div className="mt-0.5 text-[11px] text-muted-foreground">Глобальная рандомизация выключена</div>
                )}
              </div>
              <button
                type="button"
                className="rounded bg-amber-500/10 border border-amber-500/30 px-2 py-1 text-xs text-amber-600 hover:bg-amber-500/20 transition-colors"
                onClick={() => { const v = !subscriptionRandomizationOpen; setSubscriptionRandomizationOpen(v); writeStoredBool("olc-sub-rand-open-v1", v); }}
              >
                {subscriptionRandomizationOpen ? "Скрыть" : "Настроить"}
              </button>
            </div>
            {subscriptionRandomizationOpen && (
              <div className="border-l-2 border-primary/30 pl-3">
                <SubscriptionRandomizationPanel
                  globalEnabled={globalRandomizationEnabled}
                  onGlobalChange={setGlobalRandomizationEnabled}
                />
              </div>
            )}
            <div className="py-2"><AdditionalRandomizationSection /></div>
            <MainSettingsAutodetectLink
              expanded={showAutodetectInline}
              onToggle={() => setShowAutodetectInline((v) => !v)}
            />

            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <div className="text-sm font-medium text-foreground">{t('adminPassword')}</div>
              {settings?.admin_user && <div className="text-xs text-muted-foreground">{t('userLabel')}: {settings.admin_user}</div>}
              <label className="grid gap-2 text-sm text-muted-foreground">
                Текущий пароль
                <input
                  className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                  type="password"
                  value={passwordForm.current}
                  onChange={(event) => setPasswordForm({ ...passwordForm, current: event.target.value })}
                  autoComplete="current-password"
                />
              </label>
              <div className="grid gap-3 md:grid-cols-2">
                <label className="grid gap-2 text-sm text-muted-foreground">
                  Новый пароль
                  <input
                    className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                    type="password"
                    value={passwordForm.next}
                    onChange={(event) => setPasswordForm({ ...passwordForm, next: event.target.value })}
                    autoComplete="new-password"
                  />
                </label>
                <label className="grid gap-2 text-sm text-muted-foreground">
                  Повтор нового пароля
                  <input
                    className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                    type="password"
                    value={passwordForm.repeat}
                    onChange={(event) => setPasswordForm({ ...passwordForm, repeat: event.target.value })}
                    autoComplete="new-password"
                  />
                </label>
              </div>
              <div className="flex justify-end">
                <button
                  className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
                  disabled={busy}
                  onClick={changePassword}
                >
                  <KeyRound className="h-4 w-4" />
                  {t('changePassword')}
                </button>
              </div>
            </section>

            <div className="flex justify-end gap-2">
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => { void saveSettingsAuto(); setShowAutodetectInline(false); setShowSettings(false); }}
              >
                {t('close')}
              </button>
              <span className="inline-flex h-9 items-center gap-2 text-xs text-muted-foreground">
                {settingsFormValid()
                  ? "Изменения сохраняются автоматически при закрытии"
                  : <span className="text-destructive">Проверьте название и порт — пока не сохраняется</span>}
              </span>
            </div>
          </div>
        </Modal>
      )}

      {clientLogTarget && (
        <ClientAccessLogModal client={clientLogTarget} autologi={autologi} onClose={() => setClientLogTarget(null)} />
      )}

      {logTarget && (
        <Modal title={t("logsClient", { id: logTarget.clientID })} onClose={() => setLogTarget(null)}>
          <div className="p-5">
            <div className="grid gap-2 rounded-md border border-border bg-background p-3 text-sm text-muted-foreground">
              <div>{t("logStatus", { status: logTarget.location.runtime.status })}</div>
              {logTarget.location.runtime.pid && <div>{t("logPid", { pid: String(logTarget.location.runtime.pid) })}</div>}
              {logTarget.location.runtime.started_at && <div>{t("logStarted", { at: logTarget.location.runtime.started_at })}</div>}
              {logTarget.location.runtime.exited_at && <div>{t("logExited", { at: logTarget.location.runtime.exited_at })}</div>}
              {logTarget.location.runtime.exit_error && (
                <div className="text-destructive">{t("logExitError", { err: logTarget.location.runtime.exit_error })}</div>
              )}
            </div>

            <LogScrollBox
              ref={instanceLogScroll.ref}
              onScroll={instanceLogScroll.onScroll}
              className="mt-4 max-h-[420px] overflow-y-auto rounded-md border border-border bg-black p-3 font-mono text-xs text-slate-100"
            >
              {logs.length === 0 ? (
                <div className="text-muted-foreground">{t("noLogsYet")}</div>
              ) : (
                logs.map((line, index) => (
                  <div key={`${line.time}-${index}`} className="whitespace-pre-wrap break-words">
                    {logsVerbose ? (
                      <>
                        <span className={line.stream === "stderr" ? "text-destructive" : "text-primary"}>
                          {line.stream}
                        </span>{" "}
                        <span className="text-muted-foreground">{line.time}</span> {line.line}
                      </>
                    ) : (
                      line.line
                    )}
                  </div>
                ))
              )}
            </LogScrollBox>

            <div className="mt-5 flex items-center justify-between gap-2">
              <div className="flex min-w-[230px] items-center justify-between gap-3 text-xs text-muted-foreground">
                <span>{t("logsVerbose")}</span>
                <OlcToggleButton checked={logsVerbose} onChange={(event) => setLogsVerbose(event.target.checked)} />
              </div>
              <div className="flex justify-end gap-2">
                {autologi ? (
                  <span className="inline-flex items-center rounded-md border border-emerald-500/30 bg-emerald-500/10 px-3 py-1 text-xs text-emerald-600">Автообновление</span>
                ) : (
                  <>
                    <button
                      className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-50"
                      disabled={instanceLogsLive}
                      onClick={() => openLogs(logTarget.clientID, logTarget.location)}
                    >
                      {t("refresh")}
                    </button>
                    <button
                      className={`h-9 rounded-md border border-border px-3 text-sm hover:bg-muted/80 ${
                        instanceLogsLive ? "bg-primary text-primary-foreground" : "bg-muted"
                      }`}
                      onClick={() => setInstanceLogsLive((value) => !value)}
                    >
                      {instanceLogsLive ? t("logsLiveOn") : t("logsLive")}
                    </button>
                  </>
                )}
                <button
                  className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
                  disabled={logs.length === 0 || busy}
                  onClick={copyLogs}
                >
                  {t("copy")}
                </button>
              </div>
            </div>
          </div>
        </Modal>
      )}
    </div>
    </>
  );
}

createRoot(document.getElementById("root")!).render(
  <PanelErrorBoundary>
    <PanelLangProvider>
      <App />
    </PanelLangProvider>
  </PanelErrorBoundary>,
);

// OLC_MANAGER_UPSTREAM_FOLLOWUP_V1

// OLC_PROXY_POLICY_UI_V1

// OLC_DEFAULTS_AUTOSAVE_CRUD_V1

// OLC_INSTANCE_TABLE_GUARD_V1
