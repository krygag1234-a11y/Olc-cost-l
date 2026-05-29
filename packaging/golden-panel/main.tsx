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
/* olc-jitsi-preflight-ui-v1 */
/* olc-jitsi-preflight-ui-v2 */
/* olc-jitsi-preflight-ui-v3 */
/* olc-panel-ui-v10 */
import React, { useCallback, useContext, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  Activity,
  ChevronDown,
  ChevronRight,
  Copy,
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
    splitAnalyzeTitle: "Найти домены, поддомены, IP и CDN для сайта",
    splitAnalyzeHelp: "Вставьте домен, ссылку, IP или CIDR. Панель проверит DNS, сертификаты, whois и текущие split/zapret списки, затем предложит что добавить.",
    splitAnalyzeButton: "Анализировать",
    splitAnalyzeNeedTarget: "Введите домен, ссылку, IP или CIDR",
    splitAnalyzing: "Анализирую домены и IP…",
    splitAnalyzeDone: "Анализ готов",
    splitAnalyzeResult: "Результат: {target}",
    splitFoundDomains: "Найденные домены/поддомены",
    splitFoundCidrs: "Найденные IP/CIDR",
    splitApplyAnalysis: "Добавить найденное в Split",
    splitApplyDone: "Найденное добавлено в Split",
    splitSyncConfig: "Пересобрать из инстансов",
    splitSyncRunning: "Пересобираю список из инстансов…",
    splitSyncDone: "Список инстансов пересобран",
    splitAutoGroupsTitle: "Автоматически найдено",
    splitAutoGroupsHelp: "Группы из инстансов и анализа. Главный домен/IP виден сразу, список поддоменов и CIDR можно раскрыть.",
    splitNoGroups: "Пока нет автоматических групп. Нажмите «Пересобрать из инстансов» или выполните анализ домена.",
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
    olcrtcBranchPin: "Ветка: fix/all · pin:",
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
    splitAnalyzeTitle: "Find domains, subdomains, IPs and CDN for a site",
    splitAnalyzeHelp: "Paste a domain, URL, IP or CIDR. The panel checks DNS, certificates, whois and current split/zapret lists, then suggests what to add.",
    splitAnalyzeButton: "Analyze",
    splitAnalyzeNeedTarget: "Enter a domain, URL, IP or CIDR",
    splitAnalyzing: "Analyzing domains and IPs…",
    splitAnalyzeDone: "Analysis complete",
    splitAnalyzeResult: "Result: {target}",
    splitFoundDomains: "Found domains/subdomains",
    splitFoundCidrs: "Found IP/CIDR",
    splitApplyAnalysis: "Add found items to Split",
    splitApplyDone: "Found items added to Split",
    splitSyncConfig: "Rebuild from instances",
    splitSyncRunning: "Rebuilding from instances…",
    splitSyncDone: "Instance list rebuilt",
    splitAutoGroupsTitle: "Automatically discovered",
    splitAutoGroupsHelp: "Groups from instances and analysis. The main domain/IP is visible, subdomains and CIDRs are expandable.",
    splitNoGroups: "No automatic groups yet. Click Rebuild from instances or analyze a domain.",
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
    olcrtcBranchPin: "Branch: fix/all · pin:",
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
  locations: LocationState[];
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

type ClientLocationForm = {
  name: string;
  room_id: string;
  key: string;
  carrier: string;
  transport: string;
  payload: Record<string, string>;
  dns: string;
  link?: string;
};

type ClientForm = {
  client_id: string;
  refresh: string;
  quota: Quota;
  locations: ClientLocationForm[];
};

type SettingsForm = {
  name: string;
  port: string;
  subscription_path: string;
  refresh: string;
};

const carriers = ["jitsi", "wbstream", "telemost", "jazz"];
const transportsByCarrier: Record<string, string[]> = {
  jitsi: ["datachannel", "vp8channel", "seichannel"],
  wbstream: ["datachannel", "vp8channel", "seichannel"],
  telemost: ["vp8channel", "seichannel"],
  jazz: ["datachannel"],
};

/** Снят с поддержки для новых локаций; старые config не ломаем. */
const LEGACY_TRANSPORTS = new Set(["videochannel"]);

const defaultLocationForm: ClientLocationForm = {
  name: "",
  room_id: "",
  key: "",
  carrier: "jitsi",
  transport: "datachannel",
  payload: {},
  dns: "1.1.1.1:53",
  link: "tor",
};

const defaultForm: ClientForm = {
  client_id: "",
  refresh: "",
  quota: {},
  locations: [{ ...defaultLocationForm }],
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

function InstanceDefaultsModal({ onBack, onClose }: { onBack: () => void; onClose: () => void }) {
  const { t } = usePanelLang();
  const [cfg, setCfg] = useState<InstanceDefaultsV1>(() => loadInstanceDefaults());
  const [saved, setSaved] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    void fetchInstanceDefaultsFromAPI().then((next) => {
      if (!cancelled) {
        setCfg(next);
        setLoading(false);
      }
    });
    return () => {
      cancelled = true;
    };
  }, []);

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
        <label className="mt-2 flex items-center gap-2 text-xs">
          <input
            type="checkbox"
            checked={tCfg.maxValues}
            onChange={(e) => updateTransport(carrier, transport, { maxValues: e.target.checked })}
          />
          Это максимальные значения? (нельзя выставить выше при создании)
        </label>
      </div>
    );
  };

  return (
    <Modal title="Настройки инстансов по умолчанию" onClose={onClose}>
      <div className="space-y-4 p-4 text-sm">
        <button type="button" className="text-xs text-primary hover:underline" onClick={onBack}>
          ← Назад к настройкам OlcRTC
        </button>
        {loading ? (
          <p className="text-xs text-muted-foreground">{t('loading')}</p>
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
        {saved && <p className="text-xs text-emerald-400">{saved}</p>}
        <div className="flex justify-end gap-2">
          <button type="button" className="rounded border border-border px-3 py-1 text-xs hover:bg-muted" onClick={onBack}>
            Назад
          </button>
          <button
            type="button"
            className="rounded border border-primary bg-primary/20 px-3 py-1 text-xs text-primary disabled:opacity-60"
            disabled={loading}
            onClick={() => {
              void (async () => {
                try {
                  await saveInstanceDefaults(cfg);
                  setSaved("Сохранено на сервере (применяется к новым инстансам)");
                } catch (e) {
                  setSaved(e instanceof Error ? e.message : String(e));
                }
              })();
            }}
          >
            Сохранить
          </button>
        </div>
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
    throw new Error((await res.text()).trim() || res.statusText);
  }
  return res;
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
  if (c === "telemost" || c === "wbstream" || c === "jazz") {
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
    const err = validateRoomIDInput(loc.room_id, loc.carrier);
    if (err) throw new Error(err);
  }
}

function RoomIDInput({
  value,
  carrier,
  onChange,
  inputClassName = "h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary",
}: {
  value: string;
  carrier: string;
  onChange: (value: string) => void;
  inputClassName?: string;
}) {
  const err = value.trim() ? validateRoomIDInput(value, carrier) : null;
  return (
    <div className="grid gap-1">
      <input
        className={`${inputClassName}${err ? " border-destructive/70 focus:border-destructive" : ""}`}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={roomPlaceholder(carrier)}
      />
      {err ? <p className="text-xs text-destructive">{err}</p> : null}
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
  const options = transportOptions(location.carrier, location.transport);
  const transport = options.includes(location.transport) ? location.transport : options[0];
  const fields = payloadFields[transport] ?? [];
  const allowed = new Set(fields.map((field) => field.key));
  const payload = Object.fromEntries(Object.entries(location.payload).filter(([key]) => allowed.has(key)));
  for (const field of fields) {
    if (!payload[field.key]?.trim()) payload[field.key] = field.defaultValue;
  }
  const link = (location.link?.trim() || "tor").toLowerCase();
  return mergeInstanceDefaults({
    ...location,
    transport,
    payload,
    link: link === "direct" ? "direct" : "tor",
  });
}

function normalizeForm(form: ClientForm): ClientForm {
  return {
    ...form,
    locations: form.locations.length ? form.locations.map(normalizeLocationForm) : [{ ...defaultLocationForm }],
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
      locations: (c.locations ?? []).map((loc) => normalizeLocationState(loc as Partial<LocationState>)),
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
    room_id: normalizeRoomIDInput(location.room_id),
    key: location.key.trim(),
    carrier: location.carrier,
    transport: location.transport,
    payload: payloadForSubmit(location.payload),
    dns: location.dns.trim(),
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
function LogScrollBox({
  className = "",
  children,
  ...rest
}: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={`overscroll-contain ${className}`}
      onWheel={(e) => e.stopPropagation()}
      {...rest}
    >
      {children}
    </div>
  );
}

function LogScrollPre({
  className = "",
  children,
  ...rest
}: React.HTMLAttributes<HTMLPreElement>) {
  return (
    <pre
      className={`overscroll-contain ${className}`}
      onWheel={(e) => e.stopPropagation()}
      {...rest}
    >
      {children}
    </pre>
  );
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

function ClientSettingsFields({
  form,
  setForm,
  includeClientID,
}: {
  form: ClientForm;
  setForm: (form: ClientForm) => void;
  includeClientID: boolean;
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
        <input
          className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
          value={form.refresh}
          onChange={(event) => set({ refresh: event.target.value })}
          placeholder="например 10m"
        />
      </label>
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
}: {
  location: ClientLocationForm;
  setLocation: (location: ClientLocationForm) => void;
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
      <label className="grid gap-2 text-sm text-muted-foreground">
        Room ID
        <RoomIDInput
          value={location.room_id}
          carrier={location.carrier}
          onChange={(room_id) => set({ room_id })}
        />
        <p className="text-[11px] text-muted-foreground">
          {location.carrier === "jitsi"
            ? "Jitsi: полная ссылка meet (https://…) или домен/путь"
            : "Telemost / WB Stream / Jazz: только ID комнаты (цифры и латиница), без https://"}
        </p>
        <JitsiPreflightNotice carrier={location.carrier} roomID={location.room_id} />
      </label>
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
}: {
  form: ClientForm;
  setForm: (form: ClientForm) => void;
  includeClientID: boolean;
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
        <input
          className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
          value={form.refresh}
          onChange={(event) => set({ refresh: event.target.value })}
          placeholder="например 10m"
        />
      </label>
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
            <label className="grid gap-2 text-sm text-muted-foreground">
              Room ID
              <RoomIDInput
                value={location.room_id}
                carrier={location.carrier}
                onChange={(room_id) => setLocation(index, { room_id })}
                inputClassName="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
              />
            </label>
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

type FeatureName = "zapret" | "tor" | "split" | "webtunnel" | "warp" | "olcrtc";

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
    lines: ["panel.env, Jitsi TLS, публичный URL", "ветка fix/all"],
  },
  webtunnel: {
    title: "Мосты",
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
  const [path, setPath] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const res = await fetch(`/api/features/logs/${feature}`, { cache: "no-store" });
        const body = (await res.json()) as { lines?: string[]; path?: string };
        if (!cancelled) {
          setLines(body.lines ?? []);
          setPath(body.path ?? "");
        }
      } catch (e) {
        if (!cancelled) setLines([String(e)]);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [feature]);

  return (
    <Modal title={t("logsTitle", { name: feature })} onClose={onClose}>
      <div className="p-4 space-y-3">
        <div className="flex items-center justify-between gap-2">
          {path && <div className="text-xs text-muted-foreground truncate">{path}</div>}
          <div className="flex shrink-0 gap-2">
            <button
              type="button"
              className="inline-flex items-center rounded-md border border-border bg-background px-2 py-1 text-xs hover:bg-accent disabled:opacity-50"
              disabled={loading}
              onClick={async () => {
                try {
                  const res = await fetch(`/api/features/logs/${feature}`, { cache: "no-store" });
                  const body = (await res.json()) as { lines?: string[]; path?: string };
                  setLines(body.lines ?? []);
                  setPath(body.path ?? "");
                } catch (e) {
                  setLines([String(e)]);
                }
              }}
            >
              {t("refresh")}
            </button>
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
        {path && <div className="mb-2 text-xs text-muted-foreground">{path}</div>}
        <LogScrollPre className="max-h-[60vh] overflow-y-auto rounded-md border border-border bg-background p-3 text-xs">
          {loading ? t("loading") : lines.join("\n") || t("empty")}
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
      <label className="grid gap-1 text-xs text-muted-foreground">
        Активный профиль
        <select
          className="h-8 rounded border border-border bg-background px-2"
          value={activeId}
          onChange={(e) => patchProfiles({ ...prof, active_profile: e.target.value })}
        >
          <option value="system">Оригинальный (системный)</option>
          {custom.map((pr) => (
            <option key={String(pr.id)} value={String(pr.id)}>
              {String(pr.label ?? pr.id)}
            </option>
          ))}
        </select>
      </label>
      <div className="rounded border border-border p-3 text-xs space-y-2">
        <div className="font-medium">Оригинальный профиль</div>
        <p className="text-muted-foreground">Нельзя удалить. Обновляется из встроенных источников Olc-cost-l.</p>
        <label className="grid gap-1">
          Типы мостов
          <select
            className="h-8 rounded border border-border bg-background px-2"
            value={String(sys.types ?? "obfs4,webtunnel")}
            onChange={(e) => patchProfiles({ ...prof, system: { ...sys, types: e.target.value } })}
          >
            <option value="obfs4">obfs4</option>
            <option value="webtunnel">webTunnel</option>
            <option value="obfs4,webtunnel">obfs4 + webTunnel</option>
          </select>
        </label>
        <label className="flex items-center gap-2">
          <input
            type="checkbox"
            checked={Boolean(sys.auto_update)}
            onChange={(e) => patchProfiles({ ...prof, system: { ...sys, auto_update: e.target.checked } })}
          />
          Автообновление (cron)
        </label>
        {!Boolean(sys.auto_update) && (
          <button type="button" className="rounded border border-border px-2 py-1 hover:bg-muted" disabled={poolBusy || jobStatus === "running"} onClick={() => void refreshPool(String(sys.types ?? "obfs4,webtunnel"))}>
            Обновить сейчас
          </button>
        )}
      </div>
      {custom.length > 0 && (
        <div className="space-y-2 text-xs">
          <div className="font-medium">Свои профили</div>
          {custom.map((pr) => (
            <div key={String(pr.id)} className="flex items-center justify-between rounded border border-border px-2 py-1">
              <span>
                {String(pr.label ?? pr.id)} ({String(pr.mode ?? "?")})
              </span>
              <button type="button" className="text-destructive hover:underline" onClick={() => removeProfile(String(pr.id))}>
                Удалить
              </button>
            </div>
          ))}
        </div>
      )}
      <div className="flex flex-wrap gap-2">
        <button type="button" className="rounded border border-border px-2 py-1 text-xs" onClick={() => setAddMode("manual")}>
          + Свои мосты
        </button>
        <button type="button" className="rounded border border-border px-2 py-1 text-xs" onClick={() => setAddMode("url")}>
          + Ссылка (raw)
        </button>
      </div>
      {addMode === "manual" && (
        <div className="rounded border border-dashed border-border p-2 space-y-2 text-xs">
          <input className="h-8 w-full rounded border border-border bg-background px-2" placeholder="Название профиля" value={newLabel} onChange={(e) => setNewLabel(e.target.value)} />
          <textarea className="min-h-[80px] w-full rounded border border-border bg-background p-2 font-mono" placeholder="Bridge obfs4 ...&#10;Bridge webtunnel ..." value={newBridges} onChange={(e) => setNewBridges(e.target.value)} />
          <button type="button" className="rounded border border-primary px-2 py-1 text-primary" onClick={addCustomProfile}>
            Добавить профиль
          </button>
        </div>
      )}
      {addMode === "url" && (
        <div className="rounded border border-dashed border-border p-2 space-y-2 text-xs">
          <input className="h-8 w-full rounded border border-border bg-background px-2" placeholder="Название профиля" value={newLabel} onChange={(e) => setNewLabel(e.target.value)} />
          <textarea className="min-h-[60px] w-full rounded border border-border bg-background p-2 font-mono" placeholder="https://.../bridges.txt (по строке)" value={newUrls} onChange={(e) => setNewUrls(e.target.value)} />
          <p className="text-muted-foreground">Формат raw: одна ссылка на строку, как на GitHub.</p>
          <button type="button" className="rounded border border-primary px-2 py-1 text-primary" onClick={addCustomProfile}>
            Добавить профиль
          </button>
        </div>
      )}
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
    </>
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

  useEffect(() => {
    setInstanceDefaultsOpen(false);
  }, [feature]);

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

  const save = async () => {
    setSaving(true);
    setMsg("");
    try {
      let payload: Record<string, unknown> = { ...settings };
      if (feature === "webtunnel") {
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
    } catch (e) {
      setMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const setStr = (key: string, value: string) => setSettings((s) => ({ ...s, [key]: value }));
  const setBool = (key: string, value: boolean) => setSettings((s) => ({ ...s, [key]: value }));

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
      setMsg(t("splitAnalyzeNeedTarget"));
      return;
    }
    setSaving(true);
    setMsg(t("splitAnalyzing"));
    try {
      const res = await fetch("/api/settings/split/analyze", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ target }),
      });
      const body = await res.json();
      if (!res.ok) throw new Error(body?.error || `HTTP ${res.status}`);
      setSplitAnalysis((body.result ?? body) as Record<string, unknown>);
      setMsg(t("splitAnalyzeDone"));
    } catch (e) {
      setMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const splitApplyAnalysis = async () => {
    if (!splitAnalysis) return;
    setSaving(true);
    setMsg("");
    try {
      const res = await fetch("/api/settings/split/apply-analysis", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(splitAnalysis),
      });
      const body = await res.json();
      if (!res.ok) throw new Error(body?.error || `HTTP ${res.status}`);
      if (body.settings) setSettings(body.settings);
      else await reloadSettings();
      setMsg(t("splitApplyDone"));
    } catch (e) {
      setMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const splitSyncConfig = async () => {
    setSaving(true);
    setMsg(t("splitSyncRunning"));
    try {
      const res = await fetch("/api/settings/split/sync-config", { method: "POST" });
      const body = await res.json();
      if (!res.ok) throw new Error(body?.error || `HTTP ${res.status}`);
      if (body.settings) setSettings(body.settings);
      else await reloadSettings();
      setMsg(t("splitSyncDone"));
    } catch (e) {
      setMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const splitDiscovery = (settings.discovery ?? {}) as { groups?: Array<Record<string, unknown>> };
  const splitGroups = Array.isArray(splitDiscovery.groups) ? splitDiscovery.groups : [];
  const splitAnalysisDomains = splitAnalysis && Array.isArray(splitAnalysis.domains) ? splitAnalysis.domains.map(String) : [];
  const splitAnalysisCidrs = splitAnalysis && Array.isArray(splitAnalysis.cidrs) ? splitAnalysis.cidrs.map(String) : [];

  return (
    <Modal title={t("settingsTitle", { name: title })} onClose={onClose}>
      <div className="space-y-4 p-4 text-sm">
        {loading ? (
          <p className="text-muted-foreground">{t("loading")}</p>
        ) : (
          <>
            {feature === "zapret" && (
              <>
                <label className="flex items-center gap-2 text-xs text-muted-foreground">
                  <input
                    type="checkbox"
                    checked={Boolean(settings.auto_sync)}
                    onChange={(e) => setBool("auto_sync", e.target.checked)}
                  />
                  {t("zapretAutoSync")}
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  {t("zapretExcludeDomains")}
                  <textarea
                    className="min-h-[100px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.exclude_domains ?? "")}
                    onChange={(e) => setStr("exclude_domains", e.target.value)}
                  />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  {t("zapretForceDomains")}
                  <textarea
                    className="min-h-[80px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.force_domains ?? "")}
                    onChange={(e) => setStr("force_domains", e.target.value)}
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
                <p className="text-xs text-muted-foreground">{t("torSocksPort", { port: String(settings.socks_port ?? "9050") })}</p>
                <label className="grid gap-1 text-muted-foreground">
                  ExitNodes
                  <input
                    className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs"
                    value={String(settings.exit_nodes ?? "")}
                    onChange={(e) => setStr("exit_nodes", e.target.value)}
                    placeholder="{de},{nl},{fi}"
                  />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  ExcludeExitNodes
                  <input
                    className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs"
                    value={String(settings.exclude_exit_nodes ?? "")}
                    onChange={(e) => setStr("exclude_exit_nodes", e.target.value)}
                    placeholder="{ru},{by},{ua}"
                  />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  StrictNodes (1 = только ExitNodes)
                  <input
                    className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs"
                    value={String(settings.strict_nodes ?? "")}
                    onChange={(e) => setStr("strict_nodes", e.target.value)}
                    placeholder="0 или 1"
                  />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  SocksPort
                  <input className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs" value={String(settings.socks_listen ?? "")} onChange={(e) => setStr("socks_listen", e.target.value)} placeholder="9050" />
                </label>
                <p className="text-xs text-muted-foreground">
                  {t("torTestLine", { test: String(settings.test_socks ?? "—"), safe: String(settings.safe_socks ?? "—"), dns: String(settings.dns_port ?? "—") })}
                </p>
                <p className="text-xs text-muted-foreground">
                  {t("torBridgesLine", { wt: settings.webtunnel_client ? t("yes") : t("no"), bridges: settings.bridges_enabled ? t("yes") : t("no") })}
                </p>
                <p className="text-xs text-muted-foreground">
                  {t("torAfterSave")}
                </p>
              </>
            )}
            {feature === "split" && (
              <>
                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <div>
                    <div className="font-medium">{t("splitDirectTitle")}</div>
                    <p className="text-xs text-muted-foreground">{t("splitDirectHelp")}</p>
                  </div>
                  <label className="grid gap-1 text-muted-foreground">
                    {t("splitCustomDirect")}
                    <textarea
                      className="min-h-[90px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                      placeholder="vk.com&#10;userapi.com&#10;87.240.128.0/18"
                      value={String(settings.custom_direct_domains ?? "")}
                      onChange={(e) => setStr("custom_direct_domains", e.target.value)}
                    />
                  </label>
                  <label className="grid gap-1 text-muted-foreground">
                    {t("splitPanelHosts")}
                    <textarea
                      className="min-h-[70px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                      value={String(settings.panel_hosts ?? "")}
                      onChange={(e) => setStr("panel_hosts", e.target.value)}
                    />
                  </label>
                  <label className="grid gap-1 text-muted-foreground">
                    {t("splitPanelCidrs")}
                    <textarea
                      className="min-h-[50px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                      value={String(settings.panel_cidrs ?? "")}
                      onChange={(e) => setStr("panel_cidrs", e.target.value)}
                    />
                  </label>
                </section>

                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <div className="font-medium">{t("splitAnalyzeTitle")}</div>
                      <p className="text-xs text-muted-foreground">{t("splitAnalyzeHelp")}</p>
                    </div>
                    <button type="button" className="rounded border border-border px-2 py-1 text-xs hover:bg-muted" disabled={saving} onClick={() => void splitSyncConfig()}>
                      {t("splitSyncConfig")}
                    </button>
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
                          <LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2">{splitAnalysisDomains.slice(0, 80).join("\n") || t("empty")}</LogScrollPre>
                        </div>
                        <div>
                          <div className="text-muted-foreground">{t("splitFoundCidrs")}</div>
                          <LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2">{splitAnalysisCidrs.slice(0, 80).join("\n") || t("empty")}</LogScrollPre>
                        </div>
                      </div>
                      {String(splitAnalysis.whois ?? "") && <LogScrollPre className="max-h-[90px] overflow-y-auto rounded bg-muted p-2">{String(splitAnalysis.whois)}</LogScrollPre>}
                      <button type="button" className="rounded border border-primary px-2 py-1 text-xs text-primary" disabled={saving} onClick={() => void splitApplyAnalysis()}>
                        {t("splitApplyAnalysis")}
                      </button>
                    </div>
                  )}
                </section>

                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <div>
                    <div className="font-medium">{t("splitAutoGroupsTitle")}</div>
                    <p className="text-xs text-muted-foreground">{t("splitAutoGroupsHelp")}</p>
                  </div>
                  {splitGroups.length === 0 ? (
                    <p className="text-xs text-muted-foreground">{t("splitNoGroups")}</p>
                  ) : (
                    <div className="space-y-2">
                      {splitGroups.map((g) => {
                        const id = String(g.id ?? g.target ?? g.label ?? Math.random());
                        const domains = Array.isArray(g.selected_domains) ? g.selected_domains.map(String) : Array.isArray(g.domains) ? g.domains.map(String) : [];
                        const cidrs = Array.isArray(g.selected_cidrs) ? g.selected_cidrs.map(String) : Array.isArray(g.cidrs) ? g.cidrs.map(String) : [];
                        const open = Boolean(splitExpanded[id]);
                        return (
                          <div key={id} className="rounded border border-border bg-background p-2 text-xs">
                            <button type="button" className="flex w-full items-center justify-between text-left" onClick={() => setSplitExpanded((s) => ({ ...s, [id]: !open }))}>
                              <span className="font-medium">{String(g.label ?? g.target ?? id)}</span>
                              <span className="text-muted-foreground">{String(g.source ?? "auto")} · {domains.length} domains · {cidrs.length} cidr</span>
                            </button>
                            {open && (
                              <div className="mt-2 grid gap-2 md:grid-cols-2">
                                <LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2">{domains.join("\n") || t("empty")}</LogScrollPre>
                                <LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2">{cidrs.join("\n") || t("empty")}</LogScrollPre>
                              </div>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  )}
                </section>

                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <div className="font-medium">{t("splitAdvancedTitle")}</div>
                  <label className="grid gap-1 text-muted-foreground">
                    {t("splitForceTor")}
                    <textarea className="min-h-[60px] rounded-md border border-border bg-background p-2 font-mono text-xs" value={String(settings.force_tor_domains ?? "")} onChange={(e) => setStr("force_tor_domains", e.target.value)} />
                  </label>
                  <label className="grid gap-1 text-muted-foreground">
                    {t("splitBlockedTor")}
                    <textarea className="min-h-[60px] rounded-md border border-border bg-background p-2 font-mono text-xs" value={String(settings.blocked_tor_domains ?? "")} onChange={(e) => setStr("blocked_tor_domains", e.target.value)} />
                  </label>
                  <label className="flex items-center gap-2 text-sm">
                    <input type="checkbox" checked={Boolean(settings.cidr_only)} onChange={(e) => setBool("cidr_only", e.target.checked)} />
                    {t("splitCidrOnly")}
                  </label>
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
                <label className="flex items-center gap-2 text-xs">
                  <input type="checkbox" checked={Boolean(settings.jitsi_insecure_tls)} onChange={(e) => setBool("jitsi_insecure_tls", e.target.checked)} />
                  {t("olcrtcJitsiTls")}
                </label>
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
                      <option value="jazz">jazz</option>
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
                <label className="grid gap-1 text-muted-foreground">
                  SOCKS proxy (optional)
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" value={String(settings.socks_proxy ?? "")} onChange={(e) => setStr("socks_proxy", e.target.value)} placeholder="user:pass@host:port" />
                </label>
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
                <label className="flex items-center gap-2 text-xs">
                  <input type="checkbox" checked={Boolean(settings.autoconnect ?? true)} onChange={(e) => setBool("autoconnect", e.target.checked)} />
                  {t("warpAutoconnect")}
                </label>
                <label className="flex items-center gap-2 text-xs">
                  <input type="checkbox" checked={Boolean(settings.warp_plus)} onChange={(e) => setBool("warp_plus", e.target.checked)} />
                  {t("warpPlus")}
                </label>
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
            {feature === "webtunnel" && (
              <BridgesSettingsFields settings={settings} setSettings={setSettings} setMsg={setMsg} onReload={async () => { const res = await fetch(`/api/settings/bridges`, { cache: "no-store" }); const raw = await res.text(); let body: { settings?: Record<string, unknown> } = {}; try { body = (raw ? JSON.parse(raw) : {}) as { settings?: Record<string, unknown> }; } catch { body = {}; } setSettings(body.settings ?? {}); }} />
            )}
          </>
        )}
        {msg && <p className={`text-xs ${msg === t("saved") ? "text-emerald-400" : "text-destructive"}`}>{msg}</p>}
        <div className="flex justify-end gap-2">
          <button
            type="button"
            className="rounded-md border border-border px-3 py-2 text-sm hover:bg-muted"
            onClick={onClose}
          >
            {t("close")}
          </button>
          <button
            type="button"
            disabled={loading || saving}
            className="rounded-md border border-primary bg-primary/20 px-3 py-2 text-sm text-primary disabled:opacity-50"
            onClick={() => void save()}
          >
            {saving ? "…" : t("save")}
          </button>
        </div>
      </div>
    </Modal>
  );
}

function notifyFeaturesChanged() {
  window.dispatchEvent(new CustomEvent("olc-features-changed"));
}

async function postFeatureToggle(name: FeatureName, enabled: boolean, flags?: Record<FeatureName, boolean>) {
  if (name === "split" && enabled && flags && !flags.tor) {
    throw new Error("Сначала включите Tor — split маршрутизирует остальной трафик через exit");
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
      await postFeatureToggle(name, enabled, flags);
      await load();
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
    { name: "webtunnel", label: "Мосты" },
    { name: "warp", label: "WARP" },
  ];

  return (
    <div className="flex w-full min-w-0 flex-col gap-1">
      <div className="flex flex-wrap items-center gap-2 rounded-md border border-border bg-muted/40 px-2 py-1">
        {items.filter((it) => visible(it.name)).map((it) => {
          const on = Boolean(flags?.[it.name]);
          const splitBlocked = it.name === "split" && !flags?.tor;
          const bridgesBlocked = it.name === "webtunnel" && !flags?.tor;
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

  const load = async () => {
    try {
      const res = await fetch("/api/features", { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setData(await res.json());
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
      await postFeatureToggle(name, enabled, data?.flags);
      await load();
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
    { name: "webtunnel", label: "Мосты", hint: "obfs4 + webtunnel, пул и профили" },
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
                    title="Логи"
                    className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-border hover:bg-muted"
                    onClick={() => setLogFeature(row.name)}
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
              <div className="text-xs text-muted-foreground">panel.env, Jitsi TLS, split lists — ветка fix/all</div>
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
      <div className="font-medium">Автодетектор ошибок</div>
      <p className="text-xs text-muted-foreground">Сканирует логи и состояние сервисов, создаёт уведомления в колокольчике.</p>
      <label className="flex items-center gap-2 text-xs">
        <input type="checkbox" checked={Boolean(s.enabled)} onChange={(e) => setS({ ...s, enabled: e.target.checked })} />
        Включён
      </label>
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
            <label className="flex items-center gap-2 text-xs">
              <input type="checkbox" checked={Boolean(s.show_toast)} onChange={(e) => setS({ ...s, show_toast: e.target.checked })} />
              Всплывающие подсказки (toast)
            </label>
            <div className="text-xs font-medium text-muted-foreground">Источники для автодетектора</div>
            {["instance", "olcrtc", "tor", "zapret", "panel", "split"].map((k) => (
              <label key={k} className="flex items-center gap-2 text-xs">
                <input type="checkbox" checked={sources[k] !== false} onChange={(e) => setSource(k, e.target.checked)} />
                {k}
              </label>
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
  const [open, setOpen] = useState(false);
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
  const [open, setOpen] = useState(false);
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
          setLogLines(lj.lines ?? []);
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
    if (!window.confirm(t("updateConfirm"))) return;
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
  const [open, setOpen] = useState(false);
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
    if (!window.confirm(t(action === "install" ? "confirmInstall" : "confirmUninstall", { name }))) return;
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
                        disabled={isRunning && jobAction !== "install"}
                        title={undefined}
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
  const [open, setOpen] = useState(false);
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

function App() {
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
  const [showSettings, setShowSettings] = useState(false);
  const [showAutodetectInline, setShowAutodetectInline] = useState(false);
  const [autodetectMiniOpen, setAutodetectMiniOpen] = useState(false);
  const [logs, setLogs] = useState<LogLine[]>([]);
  const [logsVerbose, setLogsVerbose] = useState(false);
  const [clientLogs, setClientLogs] = useState<ClientLogGroup[]>([]);
  const [createForm, setCreateForm] = useState<ClientForm>(defaultForm);
  const [editForm, setEditForm] = useState<ClientForm>(defaultForm);
  const [locationForm, setLocationForm] = useState<ClientLocationForm>(defaultLocationForm);
  const [locationModalError, setLocationModalError] = useState("");
  const [settingsForm, setSettingsForm] = useState<SettingsForm>(defaultSettingsForm);
  const [passwordForm, setPasswordForm] = useState({ current: "", next: "", repeat: "" });
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
  };

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

  useEffect(() => {
    if (!authenticated) return;
    const id = window.setInterval(() => {
      Promise.all([loadState(), loadMetrics()]).catch((err) => setNotice(err.message));
    }, 5000);
    return () => window.clearInterval(id);
  }, [authenticated]);


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
      setNotice(err instanceof Error ? err.message : String(err));
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
        locations: [{ ...defaultLocationForm }],
      }),
    );
  };

  const openCreateLocation = (client: ClientState) => {
    setCreateLocationClient(client);
    setLocationForm({ ...defaultLocationForm });
  };

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
    setLocationForm(
      normalizeLocationForm({
        name: location.name,
        room_id: location.room_id,
        key: location.key,
        carrier: location.carrier,
        transport: location.transport,
        payload: location.payload ?? {},
        dns: location.dns,
        link: location.link,
      }),
    );
  };

  const addClient = () =>
    runAction(async () => {
      const cidErr = validateClientIDInput(createForm.client_id);
      if (cidErr) throw new Error(cidErr);
      const locs = createForm.locations.map((loc) =>
        normalizeLocationForm({ ...loc, key: loc.key.trim() || randomHex64() }),
      );
      for (const loc of locs) {
        const re = validateRoomIDInput(loc.room_id, loc.carrier);
        if (re) throw new Error(re);
      }
      await request("/api/clients", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: createForm.client_id.trim(),
          refresh: cleanRefresh(createForm.refresh),
          quota: cleanQuota(createForm.quota),
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
        }),
      });
      setEditClient(null);
    }, "Клиент обновлен");

  const addLocation = () => {
    if (!createLocationClient) return;
    const prepared = normalizeLocationForm({
      ...locationForm,
      key: locationForm.key.trim() || randomHex64(),
    });
    const roomErr = validateRoomIDInput(prepared.room_id, prepared.carrier);
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
      assertLocationsValid([locationForm]);
      const nextLocations = editLocation.client.locations.map((location, index) =>
        index === editLocation.index
          ? locationForm
          : {
              name: location.name,
              room_id: location.room_id,
              key: location.key,
              carrier: location.carrier,
              transport: location.transport,
              payload: location.payload ?? {},
              dns: location.dns,
            },
      );
      await request(`/api/clients/${encodeURIComponent(editLocation.client.client_id)}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: editLocation.client.client_id,
          refresh: cleanRefresh(editLocation.client.refresh ?? ""),
          quota: cleanQuota(editLocation.client.quota),
          locations: locationsForSubmit(nextLocations),
        }),
      });
      setEditLocation(null);
    }, "Локация обновлена");

  const deleteClient = (id: string) =>
    runAction(async () => {
      if (!window.confirm(`Удалить клиента ${id} и все его локации?`)) return;
      await request(`/api/clients/${encodeURIComponent(id)}`, { method: "DELETE" });
    }, "Клиент удален");

  const deleteLocation = async (clientID: string, location: LocationState) => {
    if (!window.confirm(`Удалить локацию ${location.name || location.room_id}?`)) return;
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

  const openLogs = async (clientID: string, location: LocationState) => {
    setLogs([]);
    setNotice("");
    try {
      const res = await request(logsURL(clientID, location), { cache: "no-store" });
      const body = (await res.json()) as { logs: LogLine[] };
      setLogs(body.logs ?? []);
      setLogTarget({ clientID, location });
    } catch (err) {
      setLogTarget(null);
      setNotice(err instanceof Error ? err.message : String(err));
    }
  };

  const openClientLogs = async (client: ClientState) => {
    setClientLogs([]);
    setNotice("");
    setClientLogTarget(client);
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
  };

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
      await navigator.clipboard.writeText(uri);
    }, t("linkCopied", { id: clientID }));

  const copySubscription = (clientID: string) =>
    runAction(async () => {
      await navigator.clipboard.writeText(subscriptionURL(clientID, currentSubscriptionPath));
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
                        <span className="mt-1 block text-xs text-muted-foreground">
                          {clientSummary(client, running)}
                        </span>
                      </span>
                    </button>

                    <div className="flex flex-wrap gap-2 lg:justify-end">
                      <button
                        className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                        disabled={busy}
                        onClick={() => copySubscription(client.client_id)}
                      >
                        {t("subBtn")}
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
                        <table className="w-full min-w-[920px] border-collapse text-sm">
                          <thead>
                            <tr className="border-b border-border text-left text-muted-foreground">
                              <th className="py-2 pr-3 font-medium">Локация</th>
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
                                <td className="py-3 pr-3 font-medium">{loc.name || "Default"}</td>
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
                                <td className="py-3 text-right">
                                  <div className="flex flex-wrap justify-end gap-2">
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
                                      className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                                      disabled={busy}
                                      onClick={() => copyOlcBoxLink(client.client_id, loc.uri)}
                                    >
                                      <Copy className="h-4 w-4" />
                                      {t("olcBox")}
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
            <ClientFormFields form={createForm} setForm={setCreateForm} includeClientID />
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
            <ClientSettingsFields form={editForm} setForm={setEditForm} includeClientID />
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
            <LocationFormFields location={locationForm} setLocation={(loc) => { setLocationForm(loc); setLocationModalError(""); }} />
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
        <Modal title={`Редактировать локацию ${editLocation.location.name || editLocation.location.room_id}`} onClose={() => setEditLocation(null)}>
          <div className="p-5">
            <LocationFormFields location={locationForm} setLocation={setLocationForm} />
            <div className="mt-5 flex justify-end gap-2">
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => setEditLocation(null)}
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
      {showSettings && (
        <Modal wide title={t('settings')} onClose={() => setShowSettings(false)}>
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
                <input
                  className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                  value={settingsForm.refresh}
                  onChange={(event) => setSettingsForm({ ...settingsForm, refresh: event.target.value })}
                  placeholder="например 10m"
                />
              </label>
            </section>

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
                onClick={() => { setShowAutodetectInline(false); setShowSettings(false); }}
              >
                {t('close')}
              </button>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md bg-primary px-3 text-sm font-medium text-black hover:bg-primary/90 disabled:opacity-60"
                disabled={busy}
                onClick={saveSettings}
              >
                <Settings className="h-4 w-4" />
                {t('saveSettings')}
              </button>
            </div>
          </div>
        </Modal>
      )}

      {clientLogTarget && (
        <Modal title={t("logsClient", { id: clientLogTarget.client_id })} onClose={() => setClientLogTarget(null)}>
          <div className="p-5">
            <LogScrollBox className="max-h-[520px] overflow-y-auto rounded-md border border-border bg-black p-3 font-mono text-xs text-slate-100">
              {clientLogs.length === 0 ? (
                <div className="text-muted-foreground">{t("loadingLogs")}</div>
              ) : (
                clientLogs.map((group) => (
                  <div key={`${group.location.room_id}-${group.location.transport}`} className="mb-5 last:mb-0">
                    <div className="mb-2 text-[11px] uppercase text-muted-foreground">
                      {group.location.name || t("defaultLocationName")} · {group.location.transport} · {group.location.runtime.status}
                    </div>
                    {group.error ? (
                      <div className="text-muted-foreground">{t("logsUnavailableDetail", { error: group.error })}</div>
                    ) : group.lines.length === 0 ? (
                      <div className="text-muted-foreground">Логов пока нет</div>
                    ) : (
                      group.lines.map((line, index) => (
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
                  </div>
                ))
              )}
            </LogScrollBox>

            <div className="mt-5 flex items-center justify-between gap-2">
              <label className="inline-flex items-center gap-2 text-xs text-muted-foreground">
                <input type="checkbox" checked={logsVerbose} onChange={(event) => setLogsVerbose(event.target.checked)} />
                {t("logsVerbose")}
              </label>
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => openClientLogs(clientLogTarget)}
              >
                {t("refresh")}
              </button>
            </div>
          </div>
        </Modal>
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

            <LogScrollBox className="mt-4 max-h-[420px] overflow-y-auto rounded-md border border-border bg-black p-3 font-mono text-xs text-slate-100">
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
              <label className="inline-flex items-center gap-2 text-xs text-muted-foreground">
                <input type="checkbox" checked={logsVerbose} onChange={(event) => setLogsVerbose(event.target.checked)} />
                {t("logsVerbose")}
              </label>
              <div className="flex justify-end gap-2">
                <button
                  className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                  onClick={() => openLogs(logTarget.clientID, logTarget.location)}
                >
                  {t("refresh")}
                </button>
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
