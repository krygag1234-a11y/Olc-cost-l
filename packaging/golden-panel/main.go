/* olc-manager-hotfix-v22-room */
/* olc-manager-hotfix-v17 */
/* olc-manager-hotfix-v18 */
/* olc-manager-hotfix-v15 */
/* olc-manager-hotfix-v16-bridge-pool */
/* olc-manager-hotfix-v12 */
/* olc-manager-hotfix-v13 */
/* olc-manager-hotfix-v10 */
/* olc-manager-hotfix-v11 */
/* olc-manager-hotfix-v8 */
/* olc-manager-hotfix-v7 */
package main

// olc-go-fixes-v3

import (
	"io"
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"crypto/subtle"
	"crypto/tls"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"hash/fnv"
	"io/fs"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"reflect"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"gopkg.in/yaml.v3"
)

//go:embed web/dist/*
var adminAssets embed.FS

var managerStartedAt = time.Now()

var authLimiter = newAuthLimiter()
var adminSessions *sessionStore
var adminConfigPath string

var (
	splitReloadMu   sync.Mutex
	splitReloadLast time.Time
)

type Config struct {
	Version          int        `json:"version"`
	LegacyVersion    int        `json:"vesion"`
	Name             string     `json:"name"`
	Port             int        `json:"port"`
	SubscriptionPath string     `json:"subscription_path"`
	Refresh          string     `json:"refresh,omitempty"`
	ActiveLocationID string     `json:"active_location_id"`
	Clients          []Client   `json:"clients"`
	Locations        []Location `json:"locations"`
}

func (c *Config) UnmarshalJSON(data []byte) error {
	type config Config
	var parsed config
	if err := json.Unmarshal(data, &parsed); err != nil {
		return err
	}
	*c = Config(parsed)
	c.Normalize()
	return nil
}

type Client struct {
	ClientID  string     `json:"client-id"`
	Refresh   string     `json:"refresh,omitempty"`
	Quota     Quota      `json:"quota,omitempty"`
	Locations []Location `json:"locations"`
}

type Quota struct {
	SpeedMbps int    `json:"speed_mbps,omitempty"`
	TrafficGB int    `json:"traffic_gb,omitempty"`
	UsedGB    int    `json:"used_gb,omitempty"`
	UsedBytes uint64 `json:"used_bytes,omitempty"`
	ExpiresAt string `json:"expires_at,omitempty"`
}

type Location struct {
	Name      string    `json:"name"`
	ClientID  string    `json:"client-id"`
	Endpoint  Endpoint  `json:"endpoint"`
	Carrier   string    `json:"carrier"`
	Transport Transport `json:"transport"`
	Link      string    `json:"link"`
	Data      string    `json:"data"`
	DNS       string    `json:"dns"`
}

type Endpoint struct {
	RoomID string `json:"room_id"`
	Key    string `json:"key"`
}

type Transport struct {
	Type    string
	Payload map[string]string
}

type olcrtcLivenessConfig struct {
	Interval string `yaml:"interval,omitempty"`
	Timeout  string `yaml:"timeout,omitempty"`
	Failures int    `yaml:"failures,omitempty"`
}

type olcrtcRuntimeConfig struct {
	Liveness *olcrtcLivenessConfig `yaml:"liveness,omitempty"`
	Mode   string             `yaml:"mode"`
	Auth   olcrtcAuthConfig   `yaml:"auth"`
	Room   olcrtcRoomConfig   `yaml:"room,omitempty"`
	Crypto olcrtcCryptoConfig `yaml:"crypto,omitempty"`
	Net      olcrtcNetConfig      `yaml:"net"`
	SOCKS    olcrtcSocksConfig  `yaml:"socks,omitempty"`
	VP8    *olcrtcVP8Config   `yaml:"vp8,omitempty"`
	SEI    *olcrtcSEIConfig   `yaml:"sei,omitempty"`
	Video  *olcrtcVideoConfig `yaml:"video,omitempty"`
	Gen    *olcrtcGenConfig   `yaml:"gen,omitempty"`
	Data   string             `yaml:"data,omitempty"`
	Debug  bool               `yaml:"debug,omitempty"`
	FFmpeg string             `yaml:"ffmpeg,omitempty"`
}

type olcrtcAuthConfig struct {
	Provider string `yaml:"provider"`
}

type olcrtcRoomConfig struct {
	ID string `yaml:"id,omitempty"`
}

type olcrtcCryptoConfig struct {
	Key string `yaml:"key,omitempty"`
}

type olcrtcNetConfig struct {
	Transport string `yaml:"transport,omitempty"`
	DNS       string `yaml:"dns,omitempty"`
}

type olcrtcSocksConfig struct {
	ProxyAddr             string `yaml:"proxy_addr,omitempty"`
	ProxyPort             int    `yaml:"proxy_port,omitempty"`
	DirectCIDRsFile       string `yaml:"direct_cidrs_file,omitempty"`
	DirectDomainsFile     string `yaml:"direct_domains_file,omitempty"`
	BlockedTorDomainsFile string `yaml:"blocked_tor_domains_file,omitempty"`
	ForceTorDomainsFile   string `yaml:"force_tor_domains_file,omitempty"`
}

type olcrtcVP8Config struct {
	FPS       int `yaml:"fps,omitempty"`
	BatchSize int `yaml:"batch_size,omitempty"`
}

type olcrtcSEIConfig struct {
	FPS          int `yaml:"fps,omitempty"`
	BatchSize    int `yaml:"batch_size,omitempty"`
	FragmentSize int `yaml:"fragment_size,omitempty"`
	AckTimeoutMS int `yaml:"ack_timeout_ms,omitempty"`
}

type olcrtcVideoConfig struct {
	Width      int    `yaml:"width,omitempty"`
	Height     int    `yaml:"height,omitempty"`
	FPS        int    `yaml:"fps,omitempty"`
	Bitrate    string `yaml:"bitrate,omitempty"`
	HW         string `yaml:"hw,omitempty"`
	QRSize     int    `yaml:"qr_size,omitempty"`
	QRRecovery string `yaml:"qr_recovery,omitempty"`
	Codec      string `yaml:"codec,omitempty"`
	TileModule int    `yaml:"tile_module,omitempty"`
	TileRS     int    `yaml:"tile_rs,omitempty"`
}

type olcrtcGenConfig struct {
	Amount int `yaml:"amount"`
}

func (t *Transport) UnmarshalJSON(data []byte) error {
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}

	var typ string
	if err := json.Unmarshal(raw["type"], &typ); err != nil {
		return fmt.Errorf("transport.type: %w", err)
	}

	payload := make(map[string]string)
	for key, value := range raw {
		if key == "type" {
			continue
		}

		if key == "payload" {
			var nested map[string]any
			if err := json.Unmarshal(value, &nested); err != nil {
				return fmt.Errorf("transport.payload: %w", err)
			}
			for payloadKey, payloadValue := range nested {
				payload[payloadKey] = fmt.Sprint(payloadValue)
			}
			continue
		}

		var scalar any
		if err := json.Unmarshal(value, &scalar); err != nil {
			return fmt.Errorf("transport.%s: %w", key, err)
		}
		payload[key] = fmt.Sprint(scalar)
	}

	t.Type = typ
	t.Payload = payload
	return nil
}

func (t Transport) MarshalJSON() ([]byte, error) {
	raw := map[string]any{"type": t.Type}
	if len(t.Payload) != 0 {
		raw["payload"] = t.Payload
	}
	return json.Marshal(raw)
}

type process struct {
	location Location
	cmd      *exec.Cmd
	netns    *netnsRuntime
	logs     *logBuffer
	done     chan error
	started  time.Time
	exited   time.Time
	exitErr  string
	running  bool
	restarts int
	mu       sync.RWMutex
}

type starter func(context.Context, string, Location) (*process, error)

type Supervisor struct {
	mu         sync.RWMutex
	cfg        Config
	olcrtcPath string
	processes  map[string]*process
	start      starter
	quota      *QuotaEnforcer
}

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

/* olc-manager-hotfix-v1 */
/* olc-manager-hotfix-v2 */
/* olc-manager-hotfix-v3 */
/* olc-manager-hotfix-v4 */
/* olc-manager-hotfix-v5 */
/* olc-manager-hotfix-v6 */
func run() error {
	var configPath string
	var port int
	var listenAddr string
	flag.StringVar(&configPath, "config", "", "path to olcrtc-manager JSON config")
	flag.IntVar(&port, "port", 0, "HTTP listen port; overrides config.port")
	flag.StringVar(&listenAddr, "addr", envDefault("OLCRTC_MANAGER_ADDR", "127.0.0.1"), "HTTP listen address")
	flag.Parse()

	if configPath == "" {
		return errors.New("-config is required")
	}
	adminConfigPath = configPath
	adminSessions = newSessionStoreForConfig(configPath)

	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	if port != 0 {
		cfg.Port = port
	}
	if err := cfg.Validate(); err != nil {
		return err
	}

	olcrtcPath, err := resolveOlcrtcPath()
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	supervisor := NewSupervisor(olcrtcPath, startInstance)
	quotaEnforcer := NewQuotaEnforcer(configPath, supervisor)
	supervisor.SetQuotaEnforcer(quotaEnforcer)
	if err := supervisor.StartAll(ctx, cfg); err != nil {
		return err
	}
	defer supervisor.StopAll()
	go quotaEnforcer.Run(ctx)

	reloadc := make(chan os.Signal, 1)
	signal.Notify(reloadc, syscall.SIGHUP)
	defer signal.Stop(reloadc)

	reload := func() error {
		reloaded, err := loadConfig(configPath)
		if err != nil {
			return err
		}
		if port != 0 {
			reloaded.Port = port
		}
		if reloaded.Port != cfg.Port {
			return fmt.Errorf("reload cannot change port from %d to %d", cfg.Port, reloaded.Port)
		}
		if err := reloaded.Validate(); err != nil {
			return err
		}
		return supervisor.Reload(ctx, reloaded)
	}

	handler := http.NewServeMux()
	handler.HandleFunc("/-/reload", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if !isLoopbackRequest(r) {
			http.Error(w, "reload is only allowed from loopback", http.StatusForbidden)
			return
		}
		if err := reload(); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})
	adminFileServer, err := adminFileServer()
	if err != nil {
		return err
	}
	handler.Handle("/admin", http.HandlerFunc(adminPageHandler(adminFileServer)))
	handler.Handle("/assets/", adminFileServer)
	handler.Handle("/api/auth/login", http.HandlerFunc(loginHandler(configPath)))
	handler.Handle("/api/auth/setup", http.HandlerFunc(setupHandler(configPath)))
	handler.Handle("/api/auth/logout", adminAuth(http.HandlerFunc(logoutHandler)))
	handler.Handle("/api/auth/me", http.HandlerFunc(authMeHandler(configPath)))
	handler.Handle("/api/auth/password", adminAuth(http.HandlerFunc(changePasswordHandler(configPath))))
	handler.Handle("/api/settings", adminAuth(http.HandlerFunc(settingsHandler(configPath, supervisor, port != 0))))
	handler.Handle("/api/panel/lang", adminAuth(http.HandlerFunc(panelLangHandler)))
	handler.Handle("/api/project/status", adminAuth(http.HandlerFunc(projectStatusHandler)))
	handler.Handle("/api/reload", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if err := reload(); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})))
	handler.Handle("/api/state", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		writeJSON(w, supervisor.State())
	})))
	handler.Handle("/api/metrics", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		writeJSON(w, collectMetrics(supervisor))
	})))
	handler.Handle("/api/audit", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		writeJSON(w, map[string]any{"events": readAudit(configPath, 100)})
	})))
	handler.Handle("/api/settings/split", adminAuth(http.HandlerFunc(componentSettingsHandler())))
	handler.Handle("/api/settings/split/", adminAuth(http.HandlerFunc(splitSettingsActionHandler)))
	handler.Handle("/api/settings/", adminAuth(http.HandlerFunc(componentSettingsHandler())))

	handler.Handle("/api/updates/check", adminAuth(http.HandlerFunc(updatesCheckHandler)))
	handler.Handle("/api/updates/status", adminAuth(http.HandlerFunc(updatesStatusHandler)))
	handler.Handle("/api/updates/run", adminAuth(http.HandlerFunc(updatesRunHandler)))
	handler.Handle("/api/jobs/", adminAuth(panelJobsHandler()))
	handler.Handle("/api/components/jobs", adminAuth(http.HandlerFunc(componentsJobsHandler)))
	handler.Handle("/api/notifications/scan", adminAuth(http.HandlerFunc(notificationsScanHandler)))
	handler.Handle("/api/notifications/", adminAuth(http.HandlerFunc(notificationsPatchHandler)))
	handler.Handle("/api/notification-settings", adminAuth(http.HandlerFunc(notificationSettingsHandler)))
	handler.Handle("/api/instance-defaults", adminAuth(http.HandlerFunc(instanceDefaultsHandler)))
	handler.Handle("/api/notifications", adminAuth(http.HandlerFunc(notificationsListHandler)))
	handler.Handle("/api/components/", adminAuth(http.HandlerFunc(componentsActionHandler)))
	handler.Handle("/api/capabilities", adminAuth(http.HandlerFunc(capabilitiesHandler())))
	handler.Handle("/api/jitsi/preflight", adminAuth(http.HandlerFunc(jitsiPreflightHandler)))
	handler.Handle("/api/features", adminAuth(http.HandlerFunc(featuresListHandler())))
	handler.Handle("/api/features/logs/", adminAuth(http.HandlerFunc(featuresLogsHandler())))
	handler.Handle("/api/features/", adminAuth(http.HandlerFunc(featuresToggleHandler())))
	handler.Handle("/api/logs/", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		clientID, roomID, transport := logRequestTarget(r)
		if clientID == "" || roomID == "" || transport == "" {
			http.NotFound(w, r)
			return
		}
		lines, ok := supervisor.Logs(clientID, roomID, transport)
		if !ok {
			http.NotFound(w, r)
			return
		}
		writeJSON(w, map[string][]LogLine{"logs": lines})
	})))
	handler.Handle("/api/actions/restart", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req locationActionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := supervisor.Restart(r.Context(), req.ClientID, req.RoomID, req.Transport); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})))
	handler.Handle("/api/actions/stop", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req locationActionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := supervisor.Stop(r.Context(), req.ClientID, req.RoomID, req.Transport); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})))
	handler.Handle("/api/actions/regenerate-room", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req clientActionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := regenerateClientRoom(r.Context(), configPath, olcrtcPath, req.ClientID); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := reload(); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})))
	handler.Handle("/api/actions/rotate-key", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req clientActionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := rotateClientKey(configPath, req.ClientID); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := reload(); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})))
	handler.Handle("/api/tools/generate-room", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req generateRoomRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		req.Carrier = strings.TrimSpace(req.Carrier)
		req.DNS = strings.TrimSpace(req.DNS)
		if req.Carrier == "" {
			http.Error(w, "carrier is required", http.StatusBadRequest)
			return
		}
		if req.DNS == "" {
			req.DNS = "1.1.1.1:53"
		}
		roomID, err := generateRoomID(r.Context(), olcrtcPath, req.Carrier, req.DNS)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, map[string]string{"room_id": roomID})
	})))
	handler.Handle("/api/clients", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		clientID, err := addClientFromRequest(r.Context(), configPath, olcrtcPath, r)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := reload(); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusCreated)
		writeJSON(w, map[string]string{"client_id": clientID})
	})))
	handler.Handle("/api/clients/", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodDelete && r.Method != http.MethodPut && r.Method != http.MethodPost {
			w.Header().Set("Allow", "DELETE, PUT, POST")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		rest := strings.TrimPrefix(r.URL.Path, "/api/clients/")
		if strings.HasSuffix(rest, "/locations") && r.Method == http.MethodPost {
			clientID := strings.TrimSuffix(rest, "/locations")
			if err := addLocationFromRequest(r.Context(), configPath, olcrtcPath, clientID, r); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			if err := reload(); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			w.WriteHeader(http.StatusCreated)
			return
		}
		if strings.Contains(rest, "/locations/") && r.Method == http.MethodDelete {
			parts := strings.Split(rest, "/locations/")
			if len(parts) != 2 {
				http.NotFound(w, r)
				return
			}
			if err := deleteLocation(configPath, parts[0], parts[1]); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			if err := reload(); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			w.WriteHeader(http.StatusNoContent)
			return
		}
		clientID := rest
		if clientID == "" || strings.Contains(clientID, "/") {
			http.NotFound(w, r)
			return
		}
		switch r.Method {
		case http.MethodDelete:
			if err := deleteClient(configPath, clientID); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			if err := reload(); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			w.WriteHeader(http.StatusNoContent)
		case http.MethodPut:
			if err := updateClientFromRequest(r.Context(), configPath, olcrtcPath, clientID, r); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			if err := reload(); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			w.WriteHeader(http.StatusNoContent)
		}
	})))
	handler.Handle("/", subscriptionHandler(supervisor))

	server := &http.Server{
		Addr:              net.JoinHostPort(listenAddr, strconv.Itoa(cfg.Port)),
		Handler:           securityHeaders(updateGuardMiddleware(handler)),
		ReadHeaderTimeout: 5 * time.Second,
	}

	errc := make(chan error, 1)
	go func() {
		log.Printf("serving subscription and admin panel on %s", server.Addr)
		if err := server.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
			errc <- err
			return
		}
		errc <- nil
	}()

	for {
		select {
		case <-ctx.Done():
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			return server.Shutdown(shutdownCtx)
		case <-reloadc:
			if err := reload(); err != nil {
				log.Printf("reload failed: %v", err)
				continue
			}
			log.Printf("reload completed")
		case err := <-errc:
			return err
		}
	}
}

func NewSupervisor(olcrtcPath string, start starter) *Supervisor {
	return &Supervisor{
		olcrtcPath: olcrtcPath,
		processes:  make(map[string]*process),
		start:      start,
	}
}

func (s *Supervisor) SetQuotaEnforcer(quota *QuotaEnforcer) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.quota = quota
}

func (s *Supervisor) StartAll(ctx context.Context, cfg Config) error {
	if err := cfg.Validate(); err != nil {
		return err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	for _, loc := range activeLocations(cfg, time.Now()) {
		p, err := s.start(ctx, s.olcrtcPath, loc)
		if err != nil {
			stopProcessMap(s.processes)
			s.processes = make(map[string]*process)
			return err
		}
		s.registerQuotaLocked(loc, quotaForClient(cfg, loc.ClientID), p)
		key := locationKey(loc)
		s.processes[key] = p
		s.monitorProcess(ctx, key, p)
	}
	s.cfg = cfg
	return nil
}

func (s *Supervisor) Reload(ctx context.Context, cfg Config) error {
	if err := cfg.Validate(); err != nil {
		return err
	}

	next := locationsByKey(activeLocations(cfg, time.Now()))

	s.mu.Lock()
	defer s.mu.Unlock()

	current := s.runningLocationsLocked()
	started := make(map[string]*process)

	for id, nextLoc := range next {
		currentLoc, exists := current[id]
		if exists && reflect.DeepEqual(currentLoc, nextLoc) {
			if p := s.processes[id]; p != nil {
				s.registerQuotaLocked(nextLoc, quotaForClient(cfg, nextLoc.ClientID), p)
			}
			continue
		}

		p, err := s.start(ctx, s.olcrtcPath, nextLoc)
		if err != nil {
			stopProcessMap(started)
			return err
		}
		s.registerQuotaLocked(nextLoc, quotaForClient(cfg, nextLoc.ClientID), p)
		started[id] = p
	}

	for id, currentLoc := range current {
		nextLoc, exists := next[id]
		if !exists || !reflect.DeepEqual(currentLoc, nextLoc) {
			s.stopLocked(id)
		}
	}

	for id, p := range started {
		s.processes[id] = p
		s.monitorProcess(ctx, id, p)
	}
	s.cfg = cfg
	return nil
}

func (s *Supervisor) StopAll() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.quota != nil {
		for id := range s.processes {
			s.quota.Unregister(id)
		}
	}
	stopProcessMap(s.processes)
	s.processes = make(map[string]*process)
}

func (s *Supervisor) UpdateSettings(cfg Config) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cfg.Name = cfg.Name
	s.cfg.Port = cfg.Port
	s.cfg.SubscriptionPath = cfg.SubscriptionPath
	s.cfg.Refresh = cfg.Refresh
}

func (s *Supervisor) Subscription(now time.Time) string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return subscription(s.cfg, now)
}

func (s *Supervisor) SubscriptionForClient(clientID string, now time.Time) (string, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return subscriptionForClient(s.cfg, clientID, now)
}

func (s *Supervisor) SubscriptionPath() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.cfg.SubscriptionPath
}

func (s *Supervisor) State() State {
	s.mu.RLock()
	defer s.mu.RUnlock()

	clients := make(map[string][]LocationState)
	for _, loc := range s.cfg.Locations {
		key := locationKey(loc)
		p, exists := s.processes[key]
		runtime := RuntimeState{Status: "stopped"}
		if exists {
			runtime = p.state()
		}
		clients[loc.ClientID] = append(clients[loc.ClientID], LocationState{
			Name:      loc.Name,
			RoomID:    loc.Endpoint.RoomID,
			Key:       loc.Endpoint.Key,
			URI:       locationURI(loc),
			Carrier:   loc.Carrier,
			Transport: loc.Transport.Type,
			Payload:   loc.Transport.Payload,
			Link:      loc.Link,
			DNS:       loc.DNS,
			Running:   runtime.Running,
			Runtime:   runtime,
		})
	}

	clientIDs := make([]string, 0, len(clients))
	for id := range clients {
		clientIDs = append(clientIDs, id)
		sort.Slice(clients[id], func(i, j int) bool {
			return clients[id][i].Name < clients[id][j].Name
		})
	}
	sort.Strings(clientIDs)

	out := State{
		Name:             s.cfg.Name,
		Port:             s.cfg.Port,
		SubscriptionPath: s.cfg.SubscriptionPath,
		Refresh:          s.cfg.Refresh,
		ClientCount:      len(clientIDs),
		RunningCount:     s.runningCountLocked(),
		Clients:          make([]ClientState, 0, len(clientIDs)),
	}
	for _, id := range clientIDs {
		quota := Quota{}
		refresh := ""
		for _, client := range s.cfg.Clients {
			if client.ClientID == id {
				quota = client.Quota
				refresh = client.Refresh
				break
			}
		}
		out.Clients = append(out.Clients, ClientState{
			ClientID:  id,
			Refresh:   refresh,
			Quota:     quota,
			Locations: clients[id],
		})
	}
	return out
}

func (s *Supervisor) Logs(clientID, roomID, transport string) ([]LogLine, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	p, ok := s.processes[strings.Join([]string{clientID, roomID, transport}, ":")]
	if !ok || p.logs == nil {
		return nil, false
	}
	return p.logs.Snapshot(), true
}

func (s *Supervisor) Restart(ctx context.Context, clientID, roomID, transport string) error {
	key := strings.Join([]string{strings.TrimSpace(clientID), strings.TrimSpace(roomID), strings.TrimSpace(transport)}, ":")

	s.mu.Lock()
	p, ok := s.processes[key]
	if !ok {
		loc, found := s.locationLocked(key)
		if !found {
			s.mu.Unlock()
			return fmt.Errorf("location %q not found", key)
		}
		quota := s.clientQuotaLocked(loc.ClientID)
		if quotaStatus(quota, time.Now()) != "active" {
			s.mu.Unlock()
			return fmt.Errorf("location %q is blocked by quota status %s", key, quotaStatus(quota, time.Now()))
		}
		next, err := s.start(context.Background(), s.olcrtcPath, loc)
		if err != nil {
			s.mu.Unlock()
			return err
		}
		s.registerQuotaLocked(loc, quota, next)
		s.processes[key] = next
		s.monitorProcess(ctx, key, next)
		s.mu.Unlock()
		return nil
	}
	loc := p.location
	s.stopLocked(key)
	s.mu.Unlock()

	if err := waitProcessStopped(ctx, p, 5*time.Second); err != nil {
		return err
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	next, err := s.start(context.Background(), s.olcrtcPath, loc)
	if err != nil {
		return err
	}
	s.registerQuotaLocked(loc, s.clientQuotaLocked(loc.ClientID), next)
	s.processes[key] = next
	s.monitorProcess(ctx, key, next)
	return nil
}

func (s *Supervisor) Stop(ctx context.Context, clientID, roomID, transport string) error {
	key := strings.Join([]string{strings.TrimSpace(clientID), strings.TrimSpace(roomID), strings.TrimSpace(transport)}, ":")

	s.mu.Lock()
	p, ok := s.processes[key]
	if !ok {
		s.mu.Unlock()
		return nil
	}
	s.stopLocked(key)
	s.mu.Unlock()
	return waitProcessStopped(ctx, p, 5*time.Second)
}

func (s *Supervisor) monitorProcess(ctx context.Context, key string, p *process) {
	go func() {
		err := <-p.done
		if ctx.Err() != nil {
			return
		}
		if err != nil {
			log.Printf("olcrtc for %s exited: %v", key, err)
		}
		time.Sleep(time.Duration(min(p.restarts+1, 5)) * time.Second)
		s.mu.Lock()
		defer s.mu.Unlock()
		if s.processes[key] != p || ctx.Err() != nil {
			return
		}
		if p.restarts >= 3 {
			log.Printf("olcrtc for %s reached restart limit", key)
			return
		}
		next, startErr := s.start(ctx, s.olcrtcPath, p.location)
		if startErr != nil {
			log.Printf("olcrtc restart for %s failed: %v", key, startErr)
			return
		}
		s.registerQuotaLocked(p.location, s.clientQuotaLocked(p.location.ClientID), next)
		next.restarts = p.restarts + 1
		s.processes[key] = next
		s.monitorProcess(ctx, key, next)
	}()
}

func (s *Supervisor) registerQuotaLocked(loc Location, quota Quota, p *process) {
	if s.quota == nil {
		return
	}
	if err := s.quota.Register(loc, quota, p); err != nil {
		log.Printf("quota accounting unavailable for %s: %v", locationKey(loc), err)
	}
}

func (s *Supervisor) clientQuotaLocked(clientID string) Quota {
	for _, client := range s.cfg.Clients {
		if client.ClientID == clientID {
			return client.Quota
		}
	}
	return Quota{}
}

func (s *Supervisor) runningLocationsLocked() map[string]Location {
	current := make(map[string]Location, len(s.processes))
	for id, p := range s.processes {
		if p != nil {
			current[id] = p.location
		}
	}
	return current
}

func (s *Supervisor) locationLocked(key string) (Location, bool) {
	for _, loc := range s.cfg.Locations {
		if locationKey(loc) == key {
			return loc, true
		}
	}
	return Location{}, false
}

func quotaForClient(cfg Config, clientID string) Quota {
	for _, client := range cfg.Clients {
		if client.ClientID == clientID {
			return client.Quota
		}
	}
	return Quota{}
}

func (s *Supervisor) ApplyQuotaConfig(cfg Config, now time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cfg = cfg
	for _, client := range cfg.Clients {
		if quotaStatus(client.Quota, now) == "active" {
			for _, loc := range client.Locations {
				if p := s.processes[locationKey(loc)]; p != nil {
					s.registerQuotaLocked(loc, client.Quota, p)
				}
			}
			continue
		}
		for _, loc := range client.Locations {
			s.stopLocked(locationKey(loc))
		}
	}
}

func (s *Supervisor) runningCountLocked() int {
	count := 0
	for _, p := range s.processes {
		if p.state().Running {
			count++
		}
	}
	return count
}

type State struct {
	Name             string        `json:"name"`
	Port             int           `json:"port"`
	SubscriptionPath string        `json:"subscription_path"`
	Refresh          string        `json:"refresh,omitempty"`
	ClientCount      int           `json:"client_count"`
	RunningCount     int           `json:"running_count"`
	Clients          []ClientState `json:"clients"`
}

type ClientState struct {
	ClientID  string          `json:"client_id"`
	Refresh   string          `json:"refresh,omitempty"`
	Quota     Quota           `json:"quota"`
	Locations []LocationState `json:"locations"`
}

type LocationState struct {
	Name      string            `json:"name"`
	RoomID    string            `json:"room_id"`
	Key       string            `json:"key"`
	URI       string            `json:"uri"`
	Carrier   string            `json:"carrier"`
	Transport string            `json:"transport"`
	Payload   map[string]string `json:"payload"`
	Link      string            `json:"link"`
	DNS       string            `json:"dns"`
	Running   bool              `json:"running"`
	Runtime   RuntimeState      `json:"runtime"`
}

type RuntimeState struct {
	Status      string `json:"status"`
	Running     bool   `json:"running"`
	PID         int    `json:"pid,omitempty"`
	MemoryBytes uint64 `json:"memory_bytes,omitempty"`
	StartedAt   string `json:"started_at,omitempty"`
	ExitedAt    string `json:"exited_at,omitempty"`
	ExitError   string `json:"exit_error,omitempty"`
	LogCount    int    `json:"log_count"`
	Restarts    int    `json:"restarts"`
}

type LogLine struct {
	Time   string `json:"time"`
	Stream string `json:"stream"`
	Line   string `json:"line"`
}

type addClientRequest struct {
	ClientID   string            `json:"client_id"`
	FromClient string            `json:"from_client"`
	Refresh    string            `json:"refresh"`
	Quota      Quota             `json:"quota"`
	Locations  []locationRequest `json:"locations"`
	RoomID     string            `json:"room_id"`
	Key        string            `json:"key"`
	Carrier    string            `json:"carrier"`
	Transport  string            `json:"transport"`
	Payload    map[string]string `json:"payload"`
	DNS        string            `json:"dns"`
	Name       string            `json:"name"`
}

type updateClientRequest struct {
	ClientID  string            `json:"client_id"`
	Refresh   string            `json:"refresh"`
	Quota     Quota             `json:"quota"`
	Locations []locationRequest `json:"locations"`
	RoomID    string            `json:"room_id"`
	Key       string            `json:"key"`
	Carrier   string            `json:"carrier"`
	Transport string            `json:"transport"`
	Payload   map[string]string `json:"payload"`
	DNS       string            `json:"dns"`
	Name      string            `json:"name"`
}

type locationRequest struct {
	Name      string            `json:"name"`
	RoomID    string            `json:"room_id"`
	Key       string            `json:"key"`
	Carrier   string            `json:"carrier"`
	Transport string            `json:"transport"`
	Payload   map[string]string `json:"payload"`
	DNS       string            `json:"dns"`
	Link      string            `json:"link"`
}

type locationActionRequest struct {
	ClientID  string `json:"client_id"`
	RoomID    string `json:"room_id"`
	Transport string `json:"transport"`
}

type clientActionRequest struct {
	ClientID string `json:"client_id"`
}

type generateRoomRequest struct {
	Carrier string `json:"carrier"`
	DNS     string `json:"dns"`
}

type settingsResponse struct {
	Name                string `json:"name"`
	Port                int    `json:"port"`
	SubscriptionPath    string `json:"subscription_path"`
	Refresh             string `json:"refresh,omitempty"`
	AdminUser           string `json:"admin_user"`
	PortOverride        bool   `json:"port_override"`
	RestartRequired     bool   `json:"restart_required,omitempty"`
	SubscriptionBaseURL string `json:"subscription_base_url"`
}

type updateSettingsRequest struct {
	Name             string `json:"name"`
	Port             int    `json:"port"`
	SubscriptionPath string `json:"subscription_path"`
	Refresh          string `json:"refresh"`
}

func panelLangHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		lang := strings.TrimSpace(readPanelEnvMap()["OLC_PANEL_LANG"])
		if lang != "en" {
			lang = "ru"
		}
		writeJSON(w, map[string]string{"lang": lang})
	case http.MethodPut:
		var req struct {
			Lang string `json:"lang"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		lang := strings.TrimSpace(req.Lang)
		if lang != "en" && lang != "ru" {
			http.Error(w, "lang must be ru or en", http.StatusBadRequest)
			return
		}
		if err := setPanelEnvKey("OLC_PANEL_LANG", lang); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, map[string]string{"lang": lang, "status": "ok"})
	default:
		w.Header().Set("Allow", "GET, PUT")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func settingsHandler(configPath string, supervisor *Supervisor, portOverride bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			cfg, err := loadConfig(configPath)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			writeJSON(w, settingsFromConfig(r, configPath, cfg, portOverride, false))
		case http.MethodPut:
			var req updateSettingsRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			cfg, restartRequired, err := updateSettings(configPath, req)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			supervisor.UpdateSettings(cfg)
			writeJSON(w, settingsFromConfig(r, configPath, cfg, portOverride, restartRequired))
		default:
			w.Header().Set("Allow", "GET, PUT")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}
}

func updateSettings(configPath string, req updateSettingsRequest) (Config, bool, error) {
	cfg, err := loadConfig(configPath)
	if err != nil {
		return Config{}, false, err
	}
	oldPort := cfg.Port
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		return Config{}, false, errors.New("name is required")
	}
	cfg.Name = req.Name
	cfg.Port = req.Port
	path, err := normalizeSubscriptionPath(req.SubscriptionPath)
	if err != nil {
		return Config{}, false, err
	}
	cfg.SubscriptionPath = path
	cfg.Refresh = strings.TrimSpace(req.Refresh)
	cfg.Normalize()
	if err := cfg.Validate(); err != nil {
		return Config{}, false, err
	}
	if err := saveConfig(configPath, cfg); err != nil {
		return Config{}, false, err
	}
	return cfg, cfg.Port != oldPort, nil
}

func settingsFromConfig(r *http.Request, configPath string, cfg Config, portOverride bool, restartRequired bool) settingsResponse {
	return settingsResponse{
		Name:                cfg.Name,
		Port:                cfg.Port,
		SubscriptionPath:    cfg.SubscriptionPath,
		Refresh:             cfg.Refresh,
		AdminUser:           currentAdminUser(configPath),
		PortOverride:        portOverride,
		RestartRequired:     restartRequired,
		SubscriptionBaseURL: subscriptionBaseURL(r, cfg.SubscriptionPath),
	}
}

func subscriptionBaseURL(r *http.Request, subscriptionPath string) string {
	if pub := strings.TrimSpace(os.Getenv("OLCRTC_PUBLIC_URL")); pub != "" {
		base := strings.TrimRight(pub, "/")
		if subscriptionPath == "" {
			return base + "/"
		}
		return base + "/" + strings.Trim(subscriptionPath, "/") + "/"
	}
	base := requestOrigin(r)
	if subscriptionPath == "" {
		return base + "/"
	}
	return base + "/" + subscriptionPath + "/"
}

func logRequestTarget(r *http.Request) (string, string, string) {
	query := r.URL.Query()
	if query.Has("client_id") || query.Has("room_id") || query.Has("transport") {
		return strings.TrimSpace(query.Get("client_id")),
			strings.TrimSpace(query.Get("room_id")),
			strings.TrimSpace(query.Get("transport"))
	}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/logs/"), "/")
	if len(parts) != 3 {
		return "", "", ""
	}
	return parts[0], parts[1], parts[2]
}

func requestOrigin(r *http.Request) string {
	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}
	if forwarded := strings.TrimSpace(r.Header.Get("X-Forwarded-Proto")); forwarded != "" {
		scheme = strings.Split(forwarded, ",")[0]
	}
	host := r.Host
	if forwarded := strings.TrimSpace(r.Header.Get("X-Forwarded-Host")); forwarded != "" {
		host = strings.Split(forwarded, ",")[0]
	}
	return scheme + "://" + strings.TrimSpace(host)
}



func validateRoomIDStrict(roomID, carrier string) error {
	roomID = strings.TrimSpace(roomID)
	if roomID == "" || roomID == "any" {
		return errors.New("room_id обязателен")
	}
	for _, r := range roomID {
		if r > 127 {
			return errors.New("room_id: только латиница и цифры")
		}
	}
	carrier = strings.TrimSpace(strings.ToLower(carrier))
	if carrier == "" {
		carrier = "jitsi"
	}
	rid := roomID
	if carrier == "jitsi" {
		if strings.HasPrefix(rid, "http://") || strings.HasPrefix(rid, "https://") {
			if _, err := url.Parse(rid); err != nil {
				return fmt.Errorf("room_id: некорректный URL Jitsi: %w", err)
			}
			return nil
		}
		if strings.Contains(rid, ".") && !strings.Contains(rid, " ") {
			return nil
		}
		return errors.New("room_id: для Jitsi укажите https://meet.example.com/room или meet.example.com/room")
	}
	if carrier == "telemost" || carrier == "wbstream" || carrier == "jazz" {
		if strings.HasPrefix(rid, "http://") || strings.HasPrefix(rid, "https://") {
			return errors.New("room_id: для этого провайдера укажите ID комнаты, не ссылку")
		}
		for _, ch := range rid {
			if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-' {
				continue
			}
			return errors.New("room_id: некорректный ID (латиница, цифры, _ и -)")
		}
		if len(rid) < 1 || len(rid) > 128 {
			return errors.New("room_id: длина ID 1–128 символов")
		}
		return nil
	}
	return nil
}


func sanitizeConfigInvalidLocations(cfg *Config) []string {
	var warnings []string
	for i := range cfg.Clients {
		kept := cfg.Clients[i].Locations[:0]
		for _, loc := range cfg.Clients[i].Locations {
			room := normalizeRoomID(strings.TrimSpace(loc.Endpoint.RoomID))
			loc.Endpoint.RoomID = room
			if err := validateRoomIDStrict(room, loc.Carrier); err != nil {
				warnings = append(warnings, fmt.Sprintf(
					"removed invalid location for client %q (%s): %v",
					cfg.Clients[i].ClientID, loc.Name, err,
				))
				continue
			}
			kept = append(kept, loc)
		}
		cfg.Clients[i].Locations = kept
	}
	cfg.Normalize()
	return warnings
}

func validateClientIDStrict(clientID string) error {
	clientID = strings.TrimSpace(clientID)
	if clientID == "" {
		return errors.New("client_id is required")
	}
	if len(clientID) > 64 {
		return errors.New("client_id must be <= 64 chars")
	}
	if strings.Contains(clientID, "/") {
		return errors.New("client_id must not contain slash")
	}
	for _, ch := range clientID {
		if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' {
			continue
		}
		return errors.New("client_id allows only a-z A-Z 0-9 _ -")
	}
	return nil
}

func normalizeRoomID(roomID string) string {
	roomID = strings.TrimSpace(roomID)
	if roomID == "" {
		return roomID
	}
	if strings.HasPrefix(roomID, "http://") || strings.HasPrefix(roomID, "https://") {
		return roomID
	}
	if strings.HasPrefix(roomID, "//") {
		return "https:" + roomID
	}
	if strings.Contains(roomID, ".") && !strings.Contains(roomID, " ") {
		return "https://" + roomID
	}
	return roomID
}

func addClientFromRequest(ctx context.Context, configPath, olcrtcPath string, r *http.Request) (string, error) {
	_ = ctx
	_ = olcrtcPath
	var req addClientRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		return "", fmt.Errorf("parse request: %w", err)
	}
	req.ClientID = strings.TrimSpace(req.ClientID)
	req.FromClient = strings.TrimSpace(req.FromClient)
	req.Refresh = strings.TrimSpace(req.Refresh)
	req.Quota = normalizeQuota(req.Quota)
	if err := validateClientIDStrict(req.ClientID); err != nil {
		return "", err
	}
	if err := validateQuota(req.Quota); err != nil {
		return "", err
	}

	cfg, err := loadConfig(configPath)
	if err != nil {
		return "", err
	}
	cfg.ensureClientsFormat()
	for _, client := range cfg.Clients {
		if client.ClientID == req.ClientID {
			return "", fmt.Errorf("client %q already exists", req.ClientID)
		}
	}

	locations, err := createLocationsFromRequest(cfg, req)
	if err != nil {
		return "", err
	}
	for i := range locations {
		locations[i].ClientID = req.ClientID
	}

	cfg.Clients = append(cfg.Clients, Client{ClientID: req.ClientID, Refresh: req.Refresh, Quota: req.Quota, Locations: locations})
	cfg.Normalize()
	if err := cfg.Validate(); err != nil {
		return "", err
	}
	if err := saveConfig(configPath, cfg); err != nil {
		return "", err
	}
	return req.ClientID, nil
}

func updateClientFromRequest(ctx context.Context, configPath, olcrtcPath, clientID string, r *http.Request) error {
	_ = ctx
	_ = olcrtcPath
	var req updateClientRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		return fmt.Errorf("parse request: %w", err)
	}
	req.ClientID = strings.TrimSpace(req.ClientID)
	req.Refresh = strings.TrimSpace(req.Refresh)
	req.Quota = normalizeQuota(req.Quota)
	if err := validateQuota(req.Quota); err != nil {
		return err
	}
	nextClientID := clientID
	if req.ClientID != "" {
		nextClientID = req.ClientID
	}
	if err := validateClientIDStrict(nextClientID); err != nil {
		return err
	}

	var locations []Location
	if updateRequestHasLocations(req) {
		var err error
		locations, err = locationsFromUpdateRequest(nextClientID, req)
		if err != nil {
			return err
		}
	}

	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	cfg.ensureClientsFormat()

	for i := range cfg.Clients {
		if cfg.Clients[i].ClientID != clientID {
			continue
		}
		if nextClientID != clientID {
			for _, client := range cfg.Clients {
				if client.ClientID == nextClientID {
					return fmt.Errorf("client %q already exists", nextClientID)
				}
			}
			cfg.Clients[i].ClientID = nextClientID
			for j := range cfg.Clients[i].Locations {
				cfg.Clients[i].Locations[j].ClientID = nextClientID
			}
		}
		cfg.Clients[i].Refresh = req.Refresh
		cfg.Clients[i].Quota = req.Quota
		if locations != nil {
			cfg.Clients[i].Locations = locations
		}

		cfg.Normalize()
		if err := cfg.Validate(); err != nil {
			return err
		}
		return saveConfig(configPath, cfg)
	}
	return fmt.Errorf("client %q not found", clientID)
}

func updateRequestHasLocations(req updateClientRequest) bool {
	return len(req.Locations) > 0 ||
		req.RoomID != "" ||
		req.Key != "" ||
		req.Carrier != "" ||
		req.Transport != "" ||
		req.DNS != "" ||
		req.Name != "" ||
		len(req.Payload) > 0
}

func createLocationsFromRequest(cfg Config, req addClientRequest) ([]Location, error) {
	if len(req.Locations) > 0 {
		return buildLocations(req.ClientID, req.Locations)
	}
	if req.RoomID != "" || req.Key != "" || req.Carrier != "" || req.Transport != "" || req.DNS != "" || req.Name != "" {
		return buildLocations(req.ClientID, []locationRequest{{
			Name:      req.Name,
			RoomID:    req.RoomID,
			Key:       req.Key,
			Carrier:   req.Carrier,
			Transport: req.Transport,
			Payload:   req.Payload,
			DNS:       req.DNS,
		}})
	}
	return templateLocations(cfg, req.FromClient)
}

func locationsFromUpdateRequest(clientID string, req updateClientRequest) ([]Location, error) {
	if len(req.Locations) > 0 {
		return buildLocations(clientID, req.Locations)
	}
	return buildLocations(clientID, []locationRequest{{
		Name:      req.Name,
		RoomID:    req.RoomID,
		Key:       req.Key,
		Carrier:   req.Carrier,
		Transport: req.Transport,
		Payload:   req.Payload,
		DNS:       req.DNS,
	}})
}


// defaultLocationLink: panel/API default link (OLCRTC_DEFAULT_LINK, else tor).
func defaultLocationLink() string {
	if v := strings.TrimSpace(os.Getenv("OLCRTC_DEFAULT_LINK")); v != "" {
		return strings.ToLower(v)
	}
	return "tor"
}

func buildLocations(clientID string, requests []locationRequest) ([]Location, error) {
	if len(requests) == 0 {
		return nil, errors.New("locations must not be empty")
	}
	locations := make([]Location, 0, len(requests))
	seen := make(map[string]struct{}, len(requests))
	for i, req := range requests {
		req.Name = strings.TrimSpace(req.Name)
		req.RoomID = normalizeRoomID(strings.TrimSpace(req.RoomID))
		req.Key = strings.TrimSpace(req.Key)
		req.Carrier = strings.TrimSpace(req.Carrier)
		req.Transport = strings.TrimSpace(req.Transport)
		req.Payload = cleanPayload(req.Payload)
		req.DNS = strings.TrimSpace(req.DNS)

		prefix := fmt.Sprintf("locations[%d]", i)
		if err := validateRoomIDStrict(req.RoomID, req.Carrier); err != nil {
			return nil, fmt.Errorf("%s.room_id: %w", prefix, err)
		}
		if req.RoomID == "" || req.RoomID == "any" {
			return nil, fmt.Errorf("%s.room_id must be concrete", prefix)
		}
		if err := validateRequestKey(req.Key); err != nil {
			return nil, fmt.Errorf("%s.key: %w", prefix, err)
		}
		carrier := defaultString(req.Carrier, "wbstream")
		transport := defaultString(req.Transport, "datachannel")
		dns := defaultString(req.DNS, "1.1.1.1:53")
		transportConfig := Transport{Type: transport, Payload: req.Payload}
		if !isSupported(carrier, transport) {
			return nil, fmt.Errorf("unsupported carrier/transport combination %s + %s", carrier, transport)
		}
		if err := validatePayload(transportConfig); err != nil {
			return nil, fmt.Errorf("%s.transport: %w", prefix, err)
		}
		name := req.Name
		if name == "" {
			name = "Default location"
		}
		loc := Location{
			Name:      name,
			ClientID:  clientID,
			Endpoint:  Endpoint{RoomID: req.RoomID, Key: req.Key},
			Carrier:   carrier,
			Transport: transportConfig,
			Link:      defaultString(strings.TrimSpace(req.Link), defaultLocationLink()),
			Data:      "data",
			DNS:       dns,
		}
		key := locationKey(loc)
		if _, ok := seen[key]; ok {
			return nil, fmt.Errorf("%s location key %q is duplicated", prefix, key)
		}
		seen[key] = struct{}{}
		locations = append(locations, loc)
	}
	return locations, nil
}

func validateRequestKey(key string) error {
	if key == "" {
		return errors.New("is required")
	}
	if len(key) != 64 {
		return errors.New("must be 64 hex characters")
	}
	if _, err := hex.DecodeString(key); err != nil {
		return errors.New("must be 64 hex characters")
	}
	return nil
}

func deleteClient(configPath, clientID string) error {
	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	cfg.ensureClientsFormat()

	next := cfg.Clients[:0]
	deleted := false
	for _, client := range cfg.Clients {
		if client.ClientID == clientID {
			deleted = true
			continue
		}
		next = append(next, client)
	}
	if !deleted {
		return fmt.Errorf("client %q not found", clientID)
	}
	cfg.Clients = next
	if len(cfg.Clients) == 0 {
		cfg.Locations = nil
	}
	cfg.Normalize()
	if err := cfg.Validate(); err != nil {
		return err
	}
	return saveConfig(configPath, cfg)
}


func panelHostSyncScript() string {
	for _, c := range []string{
		"/opt/Olc-cost-l/scripts/olc-sync-panel-host.sh",
		"/usr/local/bin/olc-sync-panel-host",
	} {
		if info, err := os.Stat(c); err == nil && !info.IsDir() {
			return c
		}
	}
	return ""
}

func syncPanelCarrierHost(action, carrier, roomID string) {
	script := panelHostSyncScript()
	if script == "" {
		return
	}
	carrier = strings.TrimSpace(carrier)
	roomID = strings.TrimSpace(roomID)
	if carrier == "" || roomID == "" {
		return
	}
	cmd := exec.Command("bash", script, action, carrier, roomID)
	cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
	if out, err := cmd.CombinedOutput(); err != nil {
		log.Printf("panel host sync %s %s: %v (%s)", action, roomID, err, strings.TrimSpace(string(out)))
	}
}

func splitAnalyzeScript() string {
	for _, c := range []string{
		filepath.Join(olcRepoRoot(), "scripts/olc-split-analyze.sh"),
		"/usr/local/bin/olc-split-analyze",
	} {
		if info, err := os.Stat(c); err == nil && !info.IsDir() {
			return c
		}
	}
	return ""
}

func runSplitTool(ctx context.Context, args []string, input any, timeout time.Duration) (map[string]any, error) {
	script := splitAnalyzeScript()
	if script == "" {
		return map[string]any{"status": "missing", "error": "olc-split-analyze.sh not found"}, nil
	}
	if timeout <= 0 {
		timeout = 2 * time.Minute
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmdArgs := append([]string{script}, args...)
	cmd := exec.CommandContext(ctx, "bash", cmdArgs...)
	cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
	if input != nil {
		b, err := json.Marshal(input)
		if err != nil {
			return nil, err
		}
		cmd.Env = append(cmd.Env, "OLC_SPLIT_TOOL_INPUT="+string(b))
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("%v: %s", err, strings.TrimSpace(string(out)))
	}
	var decoded map[string]any
	if err := json.Unmarshal(out, &decoded); err != nil {
		return nil, fmt.Errorf("parse split tool output: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	return decoded, nil
}

func splitDiscoveryManifest() map[string]any {
	out, err := runSplitTool(context.Background(), []string{"manifest"}, nil, 15*time.Second)
	if err != nil {
		return map[string]any{"schema": 1, "groups": []any{}, "error": err.Error()}
	}
	return out
}

func addLocationFromRequest(ctx context.Context, configPath, olcrtcPath, clientID string, r *http.Request) error {
	_ = ctx
	_ = olcrtcPath
	clientID = strings.TrimSpace(clientID)
	if err := validateClientIDStrict(clientID); err != nil {
		return err
	}
	var req addClientRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		return fmt.Errorf("parse request: %w", err)
	}
	req.ClientID = clientID
	req.Carrier = strings.TrimSpace(req.Carrier)
	req.Transport = strings.TrimSpace(req.Transport)
	req.Payload = cleanPayload(req.Payload)
	req.DNS = strings.TrimSpace(req.DNS)
	req.Name = strings.TrimSpace(req.Name)
	locs, err := createLocationsFromRequest(Config{}, req)
	if err != nil {
		return err
	}
	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	cfg.ensureClientsFormat()
	for i := range cfg.Clients {
		if cfg.Clients[i].ClientID == clientID {
			cfg.Clients[i].Locations = append(cfg.Clients[i].Locations, locs...)
			cfg.Normalize()
			if err := cfg.Validate(); err != nil {
				return err
			}
			return saveConfig(configPath, cfg)
		}
	}
	return fmt.Errorf("client %q not found", clientID)
}

func asyncReloadAfterLocationDelete(reloadFn func() error) {
	go func() {
		if err := reloadFn(); err != nil {
			log.Printf("reload after location delete: %v", err)
		}
	}()
}

func deleteLocation(configPath, clientID, roomID string) error {
	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	cfg.ensureClientsFormat()
	for i := range cfg.Clients {
		if cfg.Clients[i].ClientID != clientID {
			continue
		}
		next := cfg.Clients[i].Locations[:0]
		deleted := false
		for _, loc := range cfg.Clients[i].Locations {
			if loc.Endpoint.RoomID == roomID {
				deleted = true
				continue
			}
			next = append(next, loc)
		}
		if !deleted {
			return fmt.Errorf("location %q not found", roomID)
		}
		cfg.Clients[i].Locations = next
		cfg.Normalize()
		if err := cfg.Validate(); err != nil {
			return err
		}
		return saveConfig(configPath, cfg)
	}
	return fmt.Errorf("client %q not found", clientID)
}

func regenerateClientRoom(ctx context.Context, configPath, olcrtcPath, clientID string) error {
	clientID = strings.TrimSpace(clientID)
	if clientID == "" {
		return errors.New("client_id is required")
	}
	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	cfg.ensureClientsFormat()
	for i := range cfg.Clients {
		if cfg.Clients[i].ClientID != clientID {
			continue
		}
		for j := range cfg.Clients[i].Locations {
			loc := &cfg.Clients[i].Locations[j]
			loc.Endpoint.RoomID, err = generateRoomID(ctx, olcrtcPath, loc.Carrier, loc.DNS)
			if err != nil {
				return err
			}
		}
		cfg.Normalize()
		if err := cfg.Validate(); err != nil {
			return err
		}
		return saveConfig(configPath, cfg)
	}
	return fmt.Errorf("client %q not found", clientID)
}

func rotateClientKey(configPath, clientID string) error {
	clientID = strings.TrimSpace(clientID)
	if clientID == "" {
		return errors.New("client_id is required")
	}
	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	cfg.ensureClientsFormat()
	for i := range cfg.Clients {
		if cfg.Clients[i].ClientID != clientID {
			continue
		}
		for j := range cfg.Clients[i].Locations {
			cfg.Clients[i].Locations[j].Endpoint.Key, err = randomHex(32)
			if err != nil {
				return err
			}
		}
		cfg.Normalize()
		if err := cfg.Validate(); err != nil {
			return err
		}
		return saveConfig(configPath, cfg)
	}
	return fmt.Errorf("client %q not found", clientID)
}

func (c *Config) ensureClientsFormat() {
	if len(c.Clients) != 0 {
		for i := range c.Clients {
			for j := range c.Clients[i].Locations {
				if c.Clients[i].Locations[j].ClientID == "" {
					c.Clients[i].Locations[j].ClientID = c.Clients[i].ClientID
				}
			}
		}
		return
	}

	byClient := make(map[string][]Location)
	for _, loc := range c.Locations {
		byClient[loc.ClientID] = append(byClient[loc.ClientID], loc)
	}
	clientIDs := make([]string, 0, len(byClient))
	for id := range byClient {
		clientIDs = append(clientIDs, id)
	}
	sort.Strings(clientIDs)
	c.Clients = make([]Client, 0, len(clientIDs))
	for _, id := range clientIDs {
		c.Clients = append(c.Clients, Client{ClientID: id, Locations: byClient[id]})
	}
}

func templateLocations(cfg Config, fromClient string) ([]Location, error) {
	if fromClient == "" && len(cfg.Clients) > 0 {
		fromClient = cfg.Clients[0].ClientID
	}
	for _, client := range cfg.Clients {
		if client.ClientID != fromClient {
			continue
		}
		if len(client.Locations) == 0 {
			return nil, fmt.Errorf("client %q has no locations", fromClient)
		}
		locations := make([]Location, len(client.Locations))
		copy(locations, client.Locations)
		return locations, nil
	}
	return nil, fmt.Errorf("template client %q not found", fromClient)
}

func generateRoomID(ctx context.Context, olcrtcPath, carrier, dns string) (string, error) {
	genCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	cfg := olcrtcRuntimeConfig{
		Mode: "gen",
		Auth: olcrtcAuthConfig{Provider: carrier},
		Net:  olcrtcNetConfig{DNS: dns},
		Gen:  &olcrtcGenConfig{Amount: 1},
	}
	configPath, err := writeTempOlcrtcConfig("olcrtc-manager-gen", cfg)
	if err != nil {
		return "", err
	}
	defer func() { _ = os.Remove(configPath) }()

	out, err := exec.CommandContext(genCtx, olcrtcPath, configPath).CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("generate room id: %w: %s", err, strings.TrimSpace(string(out)))
	}
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			return line, nil
		}
	}
	return "", errors.New("olcrtc generated empty room id")
}


func exitProxyReachable(addr string, port int) bool {
	if addr == "" || port <= 0 {
		return false
	}
	d := net.Dialer{Timeout: 2 * time.Second}
	conn, err := d.Dial("tcp", net.JoinHostPort(addr, strconv.Itoa(port)))
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

func directCIDRsFileFromEnv() string {
	if p := strings.TrimSpace(os.Getenv("OLCRTC_DIRECT_CIDRS")); p != "" {
		return p
	}
	const defaultPath = "/var/lib/olcrtc/ru-cidrs.txt"
	if _, err := os.Stat(defaultPath); err == nil {
		return defaultPath
	}
	return ""
}

func directDomainsFileFromEnv() string {
	if p := strings.TrimSpace(os.Getenv("OLCRTC_DIRECT_DOMAINS")); p != "" {
		return p
	}
	const defaultPath = "/var/lib/olcrtc/ru-direct-domains.txt"
	if _, err := os.Stat(defaultPath); err == nil {
		return defaultPath
	}
	return ""
}

func blockedTorDomainsFileFromEnv() string {
	if p := strings.TrimSpace(os.Getenv("OLCRTC_BLOCKED_TOR_DOMAINS")); p != "" {
		return p
	}
	const defaultPath = "/var/lib/olcrtc/ru-blocked-tor-domains.txt"
	if _, err := os.Stat(defaultPath); err == nil {
		return defaultPath
	}
	return ""
}

func forceTorDomainsFileFromEnv() string {
	if p := strings.TrimSpace(os.Getenv("OLCRTC_FORCE_TOR_DOMAINS")); p != "" {
		return p
	}
	const defaultPath = "/var/lib/olcrtc/force-tor-domains.txt"
	if _, err := os.Stat(defaultPath); err == nil {
		return defaultPath
	}
	return ""
}

func exitProxyFromEnv() (addr string, port int) {
	raw := strings.TrimSpace(os.Getenv("OLCRTC_EXIT_PROXY"))
	if raw == "" {
		addr = strings.TrimSpace(os.Getenv("OLCRTC_EXIT_PROXY_ADDR"))
		if addr == "" {
			return "", 0
		}
		port, _ = strconv.Atoi(strings.TrimSpace(os.Getenv("OLCRTC_EXIT_PROXY_PORT")))
		if port <= 0 {
			port = 9050
		}
	} else {
		host, portStr, err := net.SplitHostPort(raw)
		if err != nil {
			addr, port = raw, 9050
		} else {
			addr = host
			port, _ = strconv.Atoi(portStr)
			if port <= 0 {
				port = 9050
			}
		}
	}
	if addr == "" {
		return "", 0
	}
	if !exitProxyReachable(addr, port) {
		log.Printf("exit proxy %s:%d unreachable, olcrtc runs without SOCKS (Jitsi stays up)", addr, port)
		return "", 0
	}
	return addr, port
}


func defaultLivenessForTransport(transport string) *olcrtcLivenessConfig {
	switch transport {
	case "datachannel":
		return &olcrtcLivenessConfig{Interval: "10s", Timeout: "5s", Failures: 3}
	case "vp8channel", "seichannel", "videochannel":
		return &olcrtcLivenessConfig{Interval: "10s", Timeout: "5s", Failures: 3}
	default:
		return &olcrtcLivenessConfig{Interval: "10s", Timeout: "5s", Failures: 3}
	}
}

func ffmpegPathFromEnv() string {
	if v := strings.TrimSpace(os.Getenv("OLCRTC_FFMPEG")); v != "" {
		return v
	}
	if p, err := exec.LookPath("ffmpeg"); err == nil {
		return p
	}
	return ""
}

func serverConfig(loc Location) (olcrtcRuntimeConfig, error) {
	cfg := olcrtcRuntimeConfig{
		Mode:   "srv",
		Auth:   olcrtcAuthConfig{Provider: loc.Carrier},
		Room:   olcrtcRoomConfig{ID: loc.Endpoint.RoomID},
		Crypto: olcrtcCryptoConfig{Key: loc.Endpoint.Key},
		Net: olcrtcNetConfig{
			Transport: loc.Transport.Type,
			DNS:       loc.DNS,
		},
		Liveness: defaultLivenessForTransport(loc.Transport.Type),
		Data:     loc.Data,
		FFmpeg:   ffmpegPathFromEnv(),
	}
	if err := applyTransportPayload(&cfg, loc.Transport); err != nil {
		return olcrtcRuntimeConfig{}, err
	}
	// link=direct → без Tor/SOCKS; иначе Tor exit + split (RU direct, остальное через SOCKS).
	useTor := !strings.EqualFold(strings.TrimSpace(loc.Link), "direct")
	if useTor {
		if proxyAddr, proxyPort := exitProxyFromEnv(); proxyAddr != "" {
			cfg.SOCKS = olcrtcSocksConfig{
				ProxyAddr: proxyAddr,
				ProxyPort: proxyPort,
			}
			flags := readFeatureFlags()
			if flags["split"] || flags["zapret"] {
				cfg.SOCKS.DirectCIDRsFile = directCIDRsFileFromEnv()
				cfg.SOCKS.DirectDomainsFile = directDomainsFileFromEnv()
				cfg.SOCKS.BlockedTorDomainsFile = blockedTorDomainsFileFromEnv()
				cfg.SOCKS.ForceTorDomainsFile = forceTorDomainsFileFromEnv()
			}
		}
	}

	return cfg, nil
}

func applyTransportPayload(cfg *olcrtcRuntimeConfig, transport Transport) error {
	payload := cleanPayload(transport.Payload)
	switch transport.Type {
	case "datachannel":
		return nil
	case "vp8channel":
		vp8 := olcrtcVP8Config{}
		if err := setPayloadInt(payload, "vp8-fps", &vp8.FPS); err != nil {
			return err
		}
		if err := setPayloadInt(payload, "vp8-batch", &vp8.BatchSize); err != nil {
			return err
		}
		if vp8 != (olcrtcVP8Config{}) {
			cfg.VP8 = &vp8
		}
	case "seichannel":
		sei := olcrtcSEIConfig{}
		if err := setPayloadInt(payload, "fps", &sei.FPS); err != nil {
			return err
		}
		if err := setPayloadInt(payload, "batch", &sei.BatchSize); err != nil {
			return err
		}
		if err := setPayloadInt(payload, "frag", &sei.FragmentSize); err != nil {
			return err
		}
		if err := setPayloadInt(payload, "ack-ms", &sei.AckTimeoutMS); err != nil {
			return err
		}
		if sei != (olcrtcSEIConfig{}) {
			cfg.SEI = &sei
		}
	case "videochannel":
		video := olcrtcVideoConfig{}
		if err := setPayloadInt(payload, "video-w", &video.Width); err != nil {
			return err
		}
		if err := setPayloadInt(payload, "video-h", &video.Height); err != nil {
			return err
		}
		if err := setPayloadInt(payload, "video-fps", &video.FPS); err != nil {
			return err
		}
		if err := setPayloadNonNegativeInt(payload, "video-qr-size", &video.QRSize); err != nil {
			return err
		}
		if err := setPayloadInt(payload, "video-tile-module", &video.TileModule); err != nil {
			return err
		}
		if err := setPayloadNonNegativeInt(payload, "video-tile-rs", &video.TileRS); err != nil {
			return err
		}
		video.Bitrate = payload["video-bitrate"]
		video.HW = payload["video-hw"]
		video.Codec = payload["video-codec"]
		video.QRRecovery = payload["video-qr-recovery"]
		if video != (olcrtcVideoConfig{}) {
			cfg.Video = &video
		}
	default:
		return fmt.Errorf("unknown transport %q", transport.Type)
	}
	return nil
}

func setPayloadInt(payload map[string]string, key string, dst *int) error {
	value := strings.TrimSpace(payload[key])
	if value == "" {
		return nil
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		return fmt.Errorf("%s must be a positive integer", key)
	}
	*dst = parsed
	return nil
}

func setPayloadNonNegativeInt(payload map[string]string, key string, dst *int) error {
	value := strings.TrimSpace(payload[key])
	if value == "" {
		return nil
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 0 {
		return fmt.Errorf("%s must be a non-negative integer", key)
	}
	*dst = parsed
	return nil
}


func managerRunDir() string {
	if v := strings.TrimSpace(os.Getenv("OLCRTC_MANAGER_RUN_DIR")); v != "" {
		return v
	}
	return "/var/lib/olcrtc/manager-run"
}

func pruneManagerRunDir(dir string, keep int) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	type item struct {
		name string
		mod  time.Time
	}
	var files []item
	for _, e := range entries {
		if e.IsDir() || !strings.HasPrefix(e.Name(), "olcrtc-manager-srv-") {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		files = append(files, item{e.Name(), info.ModTime()})
	}
	if len(files) <= keep {
		return
	}
	sort.Slice(files, func(i, j int) bool { return files[i].mod.After(files[j].mod) })
	for _, f := range files[keep:] {
		_ = os.Remove(filepath.Join(dir, f.name))
	}
}

func writeTempOlcrtcConfig(prefix string, cfg olcrtcRuntimeConfig) (string, error) {
	data, err := yaml.Marshal(cfg)
	if err != nil {
		return "", fmt.Errorf("marshal olcrtc config: %w", err)
	}
	dir := managerRunDir()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", fmt.Errorf("mkdir manager run dir: %w", err)
	}
	pruneManagerRunDir(dir, 32)
	file, err := os.CreateTemp(dir, prefix+"-*.yaml")
	if err != nil {
		return "", fmt.Errorf("create olcrtc config: %w", err)
	}
	path := file.Name()
	if _, err := file.Write(data); err != nil {
		_ = file.Close()
		_ = os.Remove(path)
		return "", fmt.Errorf("write olcrtc config: %w", err)
	}
	if err := file.Close(); err != nil {
		_ = os.Remove(path)
		return "", fmt.Errorf("close olcrtc config: %w", err)
	}
	return path, nil
}

func randomHex(size int) (string, error) {
	buf := make([]byte, size)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("generate key: %w", err)
	}
	const hex = "0123456789abcdef"
	out := make([]byte, len(buf)*2)
	for i, b := range buf {
		out[i*2] = hex[b>>4]
		out[i*2+1] = hex[b&0x0f]
	}
	return string(out), nil
}

func cleanPayload(payload map[string]string) map[string]string {
	if len(payload) == 0 {
		return nil
	}
	cleaned := make(map[string]string)
	for key, value := range payload {
		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)
		if key == "" || value == "" {
			continue
		}
		cleaned[key] = value
	}
	if len(cleaned) == 0 {
		return nil
	}
	return cleaned
}

func normalizeQuota(q Quota) Quota {
	q.ExpiresAt = strings.TrimSpace(q.ExpiresAt)
	if q.UsedBytes == 0 && q.UsedGB > 0 {
		q.UsedBytes = uint64(q.UsedGB) * 1024 * 1024 * 1024
	}
	if q.UsedBytes > 0 {
		q.UsedGB = int(q.UsedBytes / (1024 * 1024 * 1024))
	}
	return q
}

func validateQuota(q Quota) error {
	if q.SpeedMbps < 0 {
		return errors.New("quota.speed_mbps must be non-negative")
	}
	if q.TrafficGB < 0 {
		return errors.New("quota.traffic_gb must be non-negative")
	}
	if q.UsedGB < 0 {
		return errors.New("quota.used_gb must be non-negative")
	}
	if q.ExpiresAt != "" {
		if _, err := time.Parse("2006-01-02", q.ExpiresAt); err != nil {
			return errors.New("quota.expires_at must use YYYY-MM-DD")
		}
	}
	return nil
}

func quotaStatus(q Quota, now time.Time) string {
	if q.ExpiresAt != "" {
		expires, err := time.Parse("2006-01-02", q.ExpiresAt)
		if err == nil && now.After(expires.Add(24*time.Hour-time.Nanosecond)) {
			return "expired"
		}
	}
	if q.TrafficGB > 0 && quotaUsedBytes(q) >= quotaTrafficBytes(q) {
		return "traffic_exceeded"
	}
	return "active"
}

func quotaUsedBytes(q Quota) uint64 {
	if q.UsedBytes > 0 {
		return q.UsedBytes
	}
	if q.UsedGB > 0 {
		return uint64(q.UsedGB) * 1024 * 1024 * 1024
	}
	return 0
}

func quotaTrafficBytes(q Quota) uint64 {
	if q.TrafficGB <= 0 {
		return 0
	}
	return uint64(q.TrafficGB) * 1024 * 1024 * 1024
}

func activeLocations(cfg Config, now time.Time) []Location {
	quotas := make(map[string]Quota, len(cfg.Clients))
	for _, client := range cfg.Clients {
		quotas[client.ClientID] = client.Quota
	}
	out := make([]Location, 0, len(cfg.Locations))
	for _, loc := range cfg.Locations {
		if quotaStatus(quotas[loc.ClientID], now) != "active" {
			continue
		}
		out = append(out, loc)
	}
	return out
}

type logBuffer struct {
	mu    sync.RWMutex
	lines []LogLine
	next  int
	full  bool
}

func newLogBuffer(size int) *logBuffer {
	return &logBuffer{lines: make([]LogLine, size)}
}

func (b *logBuffer) Append(stream, line string) {
	if b == nil || len(b.lines) == 0 {
		return
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	b.lines[b.next] = LogLine{
		Time:   time.Now().UTC().Format(time.RFC3339),
		Stream: stream,
		Line:   line,
	}
	b.next = (b.next + 1) % len(b.lines)
	if b.next == 0 {
		b.full = true
	}
}

func (b *logBuffer) Snapshot() []LogLine {
	if b == nil {
		return nil
	}
	b.mu.RLock()
	defer b.mu.RUnlock()
	if !b.full {
		return append([]LogLine(nil), b.lines[:b.next]...)
	}
	out := make([]LogLine, 0, len(b.lines))
	out = append(out, b.lines[b.next:]...)
	out = append(out, b.lines[:b.next]...)
	return out
}

func (b *logBuffer) Count() int {
	if b == nil {
		return 0
	}
	b.mu.RLock()
	defer b.mu.RUnlock()
	if b.full {
		return len(b.lines)
	}
	return b.next
}

type logWriter struct {
	stream string
	buffer *logBuffer
}

func (w logWriter) Write(p []byte) (int, error) {
	scanner := bufio.NewScanner(bytes.NewReader(p))
	for scanner.Scan() {
		w.buffer.Append(w.stream, scanner.Text())
	}
	return len(p), nil
}

func (p *process) state() RuntimeState {
	p.mu.RLock()
	defer p.mu.RUnlock()

	state := RuntimeState{
		Status:   "exited",
		Running:  p.running,
		LogCount: p.logs.Count(),
		Restarts: p.restarts,
	}
	if p.running {
		state.Status = "running"
	}
	if !p.started.IsZero() {
		state.StartedAt = p.started.UTC().Format(time.RFC3339)
	}
	if !p.exited.IsZero() {
		state.ExitedAt = p.exited.UTC().Format(time.RFC3339)
	}
	if p.exitErr != "" {
		state.ExitError = p.exitErr
	}
	if p.cmd != nil && p.cmd.Process != nil && p.running {
		state.PID = p.cmd.Process.Pid
		state.MemoryBytes = processMemoryBytes(state.PID)
	}
	return state
}

func processMemoryBytes(pid int) uint64 {
	data, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "status"))
	if err != nil {
		return 0
	}
	return parseProcStatusMemoryBytes(data)
}

func parseProcStatusMemoryBytes(data []byte) uint64 {
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if !strings.HasPrefix(line, "VmRSS:") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			return 0
		}
		kb, err := strconv.ParseUint(fields[1], 10, 64)
		if err != nil {
			return 0
		}
		return kb * 1024
	}
	return 0
}

func (p *process) markExited(err error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.running = false
	p.exited = time.Now()
	if err != nil {
		p.exitErr = err.Error()
	}
}

type Metrics struct {
	Runtime  string        `json:"runtime"`
	Go       GoMetrics     `json:"go"`
	Memory   MemoryMetrics `json:"memory"`
	Manager  RuntimeState  `json:"manager"`
	Children []ChildMetric `json:"children"`
}

type GoMetrics struct {
	Version    string `json:"version"`
	OS         string `json:"os"`
	Arch       string `json:"arch"`
	Goroutines int    `json:"goroutines"`
}

type MemoryMetrics struct {
	AllocBytes      uint64 `json:"alloc_bytes"`
	SysBytes        uint64 `json:"sys_bytes"`
	HeapAllocBytes  uint64 `json:"heap_alloc_bytes"`
	HeapInuseBytes  uint64 `json:"heap_inuse_bytes"`
	StackInuseBytes uint64 `json:"stack_inuse_bytes"`
}

type ChildMetric struct {
	ClientID  string       `json:"client_id"`
	RoomID    string       `json:"room_id"`
	Transport string       `json:"transport"`
	Name      string       `json:"name"`
	Runtime   RuntimeState `json:"runtime"`
}

func collectMetrics(supervisor *Supervisor) Metrics {
	var mem runtime.MemStats
	runtime.ReadMemStats(&mem)

	metrics := Metrics{
		Runtime: time.Now().UTC().Format(time.RFC3339),
		Go: GoMetrics{
			Version:    runtime.Version(),
			OS:         runtime.GOOS,
			Arch:       runtime.GOARCH,
			Goroutines: runtime.NumGoroutine(),
		},
		Memory: MemoryMetrics{
			AllocBytes:      mem.Alloc,
			SysBytes:        mem.Sys,
			HeapAllocBytes:  mem.HeapAlloc,
			HeapInuseBytes:  mem.HeapInuse,
			StackInuseBytes: mem.StackInuse,
		},
		Manager: RuntimeState{
			Status:    "running",
			Running:   true,
			PID:       os.Getpid(),
			StartedAt: managerStartedAt.UTC().Format(time.RFC3339),
		},
	}

	supervisor.mu.RLock()
	defer supervisor.mu.RUnlock()
	metrics.Children = make([]ChildMetric, 0, len(supervisor.processes))
	for _, p := range supervisor.processes {
		metrics.Children = append(metrics.Children, ChildMetric{
			ClientID:  p.location.ClientID,
			RoomID:    p.location.Endpoint.RoomID,
			Transport: p.location.Transport.Type,
			Name:      p.location.Name,
			Runtime:   p.state(),
		})
	}
	sort.Slice(metrics.Children, func(i, j int) bool {
		return strings.Join([]string{metrics.Children[i].ClientID, metrics.Children[i].RoomID, metrics.Children[i].Transport}, ":") <
			strings.Join([]string{metrics.Children[j].ClientID, metrics.Children[j].RoomID, metrics.Children[j].Transport}, ":")
	})
	return metrics
}

type quotaRule struct {
	ClientID string
	ClassID  uint32
	Cgroup   string
	Last     uint64
	Dev      string
	Iface    string
}

type QuotaEnforcer struct {
	configPath string
	supervisor *Supervisor
	mu         sync.Mutex
	rules      map[string]quotaRule
}

func NewQuotaEnforcer(configPath string, supervisor *Supervisor) *QuotaEnforcer {
	q := &QuotaEnforcer{
		configPath: configPath,
		supervisor: supervisor,
		rules:      make(map[string]quotaRule),
	}
	q.cleanupStale(context.Background())
	return q
}

func (q *QuotaEnforcer) Run(ctx context.Context) {
	timer := time.NewTimer(10 * time.Second)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
			if err := q.Collect(ctx); err != nil {
				log.Printf("quota accounting collect failed: %v", err)
			}
			timer.Reset(30 * time.Second)
		}
	}
}

func (q *QuotaEnforcer) Register(loc Location, quota Quota, p *process) error {
	if p == nil || p.cmd == nil || p.cmd.Process == nil {
		return errors.New("process is not running")
	}
	key := locationKey(loc)
	classID := quotaClassID(key)
	cgroup := filepath.Join("/sys/fs/cgroup/net_cls,net_prio/olcrtc-manager", quotaSafeName(key))
	dev := defaultRouteInterface(context.Background())
	iface := ""
	if p.netns != nil {
		iface = p.netns.HostIf
	}

	if p.netns != nil {
		last := uint64(0)
		if iface != "" {
			if bytes, err := interfaceTXBytes(iface); err == nil {
				last = bytes
			}
		}
		q.mu.Lock()
		if existing, ok := q.rules[key]; ok && existing.Iface == iface {
			last = existing.Last
		}
		q.rules[key] = quotaRule{ClientID: loc.ClientID, ClassID: classID, Cgroup: cgroup, Dev: dev, Iface: iface, Last: last}
		q.mu.Unlock()
		if quota.SpeedMbps > 0 {
			if err := applyNetnsSpeed(context.Background(), p.netns, quota.SpeedMbps); err != nil {
				log.Printf("speed limit unavailable for %s: %v", key, err)
			}
		} else {
			_ = runCmd(context.Background(), "tc", "qdisc", "del", "dev", p.netns.HostIf, "root")
			_ = runCmd(context.Background(), "ip", "netns", "exec", p.netns.Name, "tc", "qdisc", "del", "dev", p.netns.NsIf, "root")
		}
		return nil
	}

	q.mu.Lock()
	last := uint64(0)
	if existing, ok := q.rules[key]; ok {
		last = existing.Last
	}
	q.rules[key] = quotaRule{ClientID: loc.ClientID, ClassID: classID, Cgroup: cgroup, Dev: dev, Iface: iface, Last: last}
	q.mu.Unlock()

	if err := os.MkdirAll(cgroup, 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(cgroup, "net_cls.classid"), []byte(strconv.FormatUint(uint64(classID), 10)), 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(cgroup, "tasks"), []byte(strconv.Itoa(p.cmd.Process.Pid)), 0o644); err != nil {
		return err
	}
	q.deleteRule(context.Background(), "INPUT", classID)
	if err := q.iptables(context.Background(), "-I", "INPUT", "1", "-m", "cgroup", "--cgroup", quotaClassArg(classID), "-m", "comment", "--comment", "olcrtc-manager"); err != nil {
		return err
	}
	if quota.SpeedMbps > 0 && dev != "" && iface == "" {
		if err := q.applySpeedLimit(context.Background(), dev, classID, quota.SpeedMbps); err != nil {
			log.Printf("speed limit unavailable for %s: %v", key, err)
		}
	}
	return nil
}

func (q *QuotaEnforcer) Unregister(key string) {
	q.mu.Lock()
	rule, ok := q.rules[key]
	if ok {
		delete(q.rules, key)
	}
	q.mu.Unlock()
	if !ok {
		return
	}
	q.deleteRule(context.Background(), "INPUT", rule.ClassID)
	if rule.Dev != "" {
		q.deleteSpeedLimit(context.Background(), rule.Dev, rule.ClassID)
	}
	_ = os.Remove(filepath.Join(rule.Cgroup, "tasks"))
	_ = os.Remove(rule.Cgroup)
}

func (q *QuotaEnforcer) Collect(ctx context.Context) error {
	q.mu.Lock()
	rules := make([]quotaRule, 0, len(q.rules))
	for _, rule := range q.rules {
		rules = append(rules, rule)
	}
	q.mu.Unlock()
	if len(rules) == 0 {
		return nil
	}

	deltaByClient := make(map[string]uint64)
	for _, rule := range rules {
		bytes, err := q.ruleBytes(ctx, rule)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			return err
		}
		if bytes > rule.Last {
			deltaByClient[rule.ClientID] += bytes - rule.Last
		}
		q.updateLast(rule.ClassID, bytes)
	}
	if len(deltaByClient) == 0 {
		return nil
	}

	cfg, err := loadConfig(q.configPath)
	if err != nil {
		return err
	}
	cfg.ensureClientsFormat()
	changed := false
	for i := range cfg.Clients {
		bytes, ok := deltaByClient[cfg.Clients[i].ClientID]
		if !ok {
			continue
		}
		cfg.Clients[i].Quota.UsedBytes = quotaUsedBytes(cfg.Clients[i].Quota) + bytes
		cfg.Clients[i].Quota.UsedGB = int(cfg.Clients[i].Quota.UsedBytes / (1024 * 1024 * 1024))
		changed = true
	}
	if changed {
		cfg.Normalize()
		if err := saveConfigWithoutBackup(q.configPath, cfg); err != nil {
			return err
		}
	}
	if q.supervisor != nil {
		q.supervisor.ApplyQuotaConfig(cfg, time.Now())
	}
	return nil
}

func (q *QuotaEnforcer) updateLast(classID uint32, bytes uint64) {
	q.mu.Lock()
	defer q.mu.Unlock()
	for key, rule := range q.rules {
		if rule.ClassID == classID {
			rule.Last = bytes
			q.rules[key] = rule
			return
		}
	}
}

func (q *QuotaEnforcer) ruleBytes(ctx context.Context, rule quotaRule) (uint64, error) {
	if rule.Iface != "" {
		return interfaceTXBytes(rule.Iface)
	}
	inBytes, err := q.chainBytes(ctx, "INPUT", rule.ClassID)
	if err != nil {
		return 0, err
	}
	return inBytes, nil
}

func interfaceTXBytes(iface string) (uint64, error) {
	data, err := os.ReadFile(filepath.Join("/sys/class/net", iface, "statistics", "tx_bytes"))
	if err != nil {
		return 0, err
	}
	return strconv.ParseUint(strings.TrimSpace(string(data)), 10, 64)
}

func (q *QuotaEnforcer) chainBytes(ctx context.Context, chain string, classID uint32) (uint64, error) {
	out, err := q.iptablesOutput(ctx, "-L", chain, "-v", "-n", "-x")
	if err != nil {
		return 0, err
	}
	needle := "cgroup " + strconv.FormatUint(uint64(classID), 10)
	var total uint64
	for _, line := range strings.Split(string(out), "\n") {
		if !strings.Contains(line, needle) {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		bytes, err := strconv.ParseUint(fields[1], 10, 64)
		if err == nil {
			total += bytes
		}
	}
	return total, nil
}

func (q *QuotaEnforcer) deleteRule(ctx context.Context, chain string, classID uint32) {
	for i := 0; i < 8; i++ {
		if err := q.iptables(ctx, "-D", chain, "-m", "cgroup", "--cgroup", quotaClassArg(classID), "-m", "comment", "--comment", "olcrtc-manager"); err != nil {
			return
		}
	}
}

func (q *QuotaEnforcer) cleanupStale(ctx context.Context) {
	for _, chain := range []string{"INPUT", "OUTPUT"} {
		for i := 0; i < 64; i++ {
			line, ok := q.firstCgroupRuleLine(ctx, chain)
			if !ok {
				break
			}
			if err := q.iptables(ctx, "-D", chain, strconv.Itoa(line)); err != nil {
				break
			}
		}
	}
	if dev := defaultRouteInterface(ctx); dev != "" {
		_ = q.tc(ctx, "qdisc", "del", "dev", dev, "root")
		_ = q.tc(ctx, "qdisc", "del", "dev", dev, "ingress")
	}
	cleanupManagerNetns(ctx)
	_ = os.RemoveAll("/sys/fs/cgroup/net_cls,net_prio/olcrtc-manager")
}

func cleanupManagerNetns(ctx context.Context) {
	if out, err := exec.CommandContext(ctx, "ip", "netns", "list").Output(); err == nil {
		for _, line := range strings.Split(string(out), "\n") {
			name := strings.Fields(line)
			if len(name) == 0 || !strings.HasPrefix(name[0], "olc-") {
				continue
			}
			_ = runCmd(ctx, "ip", "netns", "del", name[0])
			_ = os.RemoveAll(filepath.Join("/etc/netns", name[0]))
		}
	}
	if out, err := exec.CommandContext(ctx, "ip", "-o", "link", "show").Output(); err == nil {
		for _, line := range strings.Split(string(out), "\n") {
			fields := strings.Fields(line)
			if len(fields) < 2 {
				continue
			}
			name := strings.TrimSuffix(fields[1], ":")
			name = strings.Split(name, "@")[0]
			if strings.HasPrefix(name, "olh") {
				_ = runCmd(ctx, "ip", "link", "del", name)
			}
		}
	}
}

func (q *QuotaEnforcer) firstCgroupRuleLine(ctx context.Context, chain string) (int, bool) {
	out, err := q.iptablesOutput(ctx, "-L", chain, "-v", "-n", "-x", "--line-numbers")
	if err != nil {
		return 0, false
	}
	for _, line := range strings.Split(string(out), "\n") {
		if !strings.Contains(line, "cgroup ") || !strings.Contains(line, "olcrtc-manager") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		n, err := strconv.Atoi(fields[0])
		if err == nil {
			return n, true
		}
	}
	return 0, false
}

func (q *QuotaEnforcer) iptables(ctx context.Context, args ...string) error {
	_, err := q.iptablesOutput(ctx, args...)
	return err
}

func (q *QuotaEnforcer) iptablesOutput(ctx context.Context, args ...string) ([]byte, error) {
	cmdCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(cmdCtx, "iptables", args...).CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("iptables %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return out, nil
}

func (q *QuotaEnforcer) applySpeedLimit(ctx context.Context, dev string, classID uint32, speedMbps int) error {
	rate := strconv.Itoa(speedMbps) + "mbit"
	class := tcClassID(classID)
	_ = q.tc(ctx, "qdisc", "add", "dev", dev, "root", "handle", "10:", "htb", "default", "ffff")
	_ = q.tc(ctx, "class", "add", "dev", dev, "parent", "10:", "classid", "10:ffff", "htb", "rate", "10gbit", "ceil", "10gbit")
	_ = q.tc(ctx, "class", "del", "dev", dev, "classid", class)
	if err := q.tc(ctx, "class", "add", "dev", dev, "parent", "10:", "classid", class, "htb", "rate", rate, "ceil", rate); err != nil {
		return err
	}
	q.ensureCgroupFilter(ctx, dev)
	return nil
}

func (q *QuotaEnforcer) deleteSpeedLimit(ctx context.Context, dev string, classID uint32) {
	class := tcClassID(classID)
	_ = q.tc(ctx, "class", "del", "dev", dev, "classid", class)
}

func (q *QuotaEnforcer) ensureCgroupFilter(ctx context.Context, dev string) {
	out, err := q.tcOutput(ctx, "filter", "show", "dev", dev, "parent", "10:")
	if err == nil && strings.Contains(string(out), "cgroup") {
		return
	}
	_ = q.tc(ctx, "filter", "add", "dev", dev, "parent", "10:", "protocol", "ip", "prio", "10", "handle", "1:", "cgroup")
	_ = q.tc(ctx, "filter", "add", "dev", dev, "parent", "10:", "protocol", "ipv6", "prio", "10", "handle", "1:", "cgroup")
}

func (q *QuotaEnforcer) tc(ctx context.Context, args ...string) error {
	_, err := q.tcOutput(ctx, args...)
	return err
}

func (q *QuotaEnforcer) tcOutput(ctx context.Context, args ...string) ([]byte, error) {
	cmdCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(cmdCtx, "tc", args...).CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("tc %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return out, nil
}

func defaultRouteInterface(ctx context.Context) string {
	cmdCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(cmdCtx, "ip", "route", "show", "default").Output()
	if err != nil {
		return ""
	}
	fields := strings.Fields(string(out))
	for i := 0; i+1 < len(fields); i++ {
		if fields[i] == "dev" {
			return fields[i+1]
		}
	}
	return ""
}

func quotaClassID(key string) uint32 {
	h := fnv.New32a()
	_, _ = h.Write([]byte(key))
	return 0x100000 + (h.Sum32() & 0x00ffff)
}

func quotaClassArg(classID uint32) string {
	return fmt.Sprintf("0x%x", classID)
}

func tcClassID(classID uint32) string {
	return fmt.Sprintf("%x:%x", classID>>16, classID&0xffff)
}

func quotaSafeName(value string) string {
	var b strings.Builder
	for _, r := range value {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
			b.WriteRune(r)
		case r == '-', r == '_':
			b.WriteRune(r)
		default:
			b.WriteByte('_')
		}
		if b.Len() >= 96 {
			break
		}
	}
	if b.Len() == 0 {
		return "location"
	}
	return b.String()
}

func saveConfig(path string, cfg Config) error {
	backupConfig(path)
	if err := writeConfig(path, cfg); err != nil {
		return err
	}
	appendAudit(path, "config_saved", "")
	return nil
}

func saveConfigWithoutBackup(path string, cfg Config) error {
	return writeConfig(path, cfg)
}

func writeConfig(path string, cfg Config) error {
	cfg.Normalize()
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal config: %w", err)
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o600); err != nil {
		return fmt.Errorf("write temp config: %w", err)
	}
	if err := os.Rename(tmp, path); err != nil {
		return fmt.Errorf("replace config: %w", err)
	}
	return nil
}

func backupConfig(path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	dir := filepath.Join(filepath.Dir(path), "backups")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return
	}
	name := "config-" + time.Now().UTC().Format("20060102-150405") + ".json"
	_ = os.WriteFile(filepath.Join(dir, name), data, 0o600)
}

func appendAudit(configPath, action, detail string) {
	entry := map[string]string{
		"time":   time.Now().UTC().Format(time.RFC3339),
		"action": action,
		"detail": detail,
	}
	data, _ := json.Marshal(entry)
	path := filepath.Join(filepath.Dir(configPath), "audit.log")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.Write(append(data, '\n'))
}

func readAudit(configPath string, limit int) []map[string]string {
	data, err := os.ReadFile(filepath.Join(filepath.Dir(configPath), "audit.log"))
	if err != nil {
		return nil
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if limit <= 0 || limit > len(lines) {
		limit = len(lines)
	}
	out := make([]map[string]string, 0, limit)
	for i := len(lines) - limit; i < len(lines); i++ {
		var entry map[string]string
		if json.Unmarshal([]byte(lines[i]), &entry) == nil {
			out = append(out, entry)
		}
	}
	return out
}

func (s *Supervisor) stopLocked(id string) {
	p, ok := s.processes[id]
	if !ok {
		return
	}
	if s.quota != nil {
		s.quota.Unregister(id)
	}
	stopProcess(p)
	delete(s.processes, id)
}

func locationsByKey(locations []Location) map[string]Location {
	byKey := make(map[string]Location, len(locations))
	for _, loc := range locations {
		byKey[locationKey(loc)] = loc
	}
	return byKey
}

func stopProcessMap(processes map[string]*process) {
	for _, p := range processes {
		stopProcess(p)
	}
}

func waitProcessStopped(ctx context.Context, p *process, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for {
		if !p.state().Running {
			return nil
		}
		if time.Now().After(deadline) {
			return errors.New("timed out waiting for olcrtc to stop")
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(100 * time.Millisecond):
		}
	}
}

type netnsRuntime struct {
	Name   string
	HostIf string
	NsIf   string
	HostIP string
	NsIP   string
	Dev    string
}

func setupNetns(ctx context.Context, loc Location) (*netnsRuntime, error) {
	key := locationKey(loc)
	token := fmt.Sprintf("%08x", quotaClassID(key)&0xffffffff)
	suffix, err := randomHex(2)
	if err != nil {
		return nil, err
	}
	ns := &netnsRuntime{
		Name:   "olc-" + token + "-" + suffix,
		HostIf: "olh" + token + suffix,
		NsIf:   "oln" + token + suffix,
		Dev:    defaultRouteInterface(ctx),
	}
	hostIP, nsIP := netnsIPs(key)
	ns.HostIP = hostIP
	ns.NsIP = nsIP
	if ns.Dev == "" {
		return nil, errors.New("default route interface not found")
	}

	cleanupNetns(ctx, ns)
	if err := runCmd(ctx, "ip", "netns", "add", ns.Name); err != nil {
		return nil, err
	}
	if err := writeNetnsResolv(ns.Name, loc.DNS); err != nil {
		cleanupNetns(ctx, ns)
		return nil, err
	}
	if err := runCmd(ctx, "ip", "link", "add", ns.HostIf, "type", "veth", "peer", "name", ns.NsIf); err != nil {
		cleanupNetns(ctx, ns)
		return nil, err
	}
	if err := runCmd(ctx, "ip", "link", "set", ns.NsIf, "netns", ns.Name); err != nil {
		cleanupNetns(ctx, ns)
		return nil, err
	}
	if err := runCmd(ctx, "ip", "addr", "add", ns.HostIP+"/30", "dev", ns.HostIf); err != nil {
		cleanupNetns(ctx, ns)
		return nil, err
	}
	if err := runCmd(ctx, "ip", "link", "set", ns.HostIf, "up"); err != nil {
		cleanupNetns(ctx, ns)
		return nil, err
	}
	if err := runCmd(ctx, "ip", "netns", "exec", ns.Name, "ip", "addr", "add", ns.NsIP+"/30", "dev", ns.NsIf); err != nil {
		cleanupNetns(ctx, ns)
		return nil, err
	}
	if err := runCmd(ctx, "ip", "netns", "exec", ns.Name, "ip", "link", "set", "lo", "up"); err != nil {
		cleanupNetns(ctx, ns)
		return nil, err
	}
	if err := runCmd(ctx, "ip", "netns", "exec", ns.Name, "ip", "link", "set", ns.NsIf, "up"); err != nil {
		cleanupNetns(ctx, ns)
		return nil, err
	}
	if err := runCmd(ctx, "ip", "netns", "exec", ns.Name, "ip", "route", "add", "default", "via", ns.HostIP); err != nil {
		cleanupNetns(ctx, ns)
		return nil, err
	}
	_ = runCmd(ctx, "sysctl", "-w", "net.ipv4.ip_forward=1")
	addNetnsFirewall(ctx, ns)

	quota := quotaForClientConfigPath(loc.ClientID)
	if quota.SpeedMbps > 0 {
		if err := applyNetnsSpeed(ctx, ns, quota.SpeedMbps); err != nil {
			log.Printf("speed limit unavailable for %s: %v", locationKey(loc), err)
		}
	}
	return ns, nil
}

func quotaForClientConfigPath(clientID string) Quota {
	if adminConfigPath == "" {
		return Quota{}
	}
	cfg, err := loadConfig(adminConfigPath)
	if err != nil {
		return Quota{}
	}
	cfg.ensureClientsFormat()
	return quotaForClient(cfg, clientID)
}

func cleanupNetns(ctx context.Context, ns *netnsRuntime) {
	if ns == nil {
		return
	}
	delNetnsFirewall(ctx, ns)
	_ = runCmd(ctx, "ip", "link", "del", ns.HostIf)
	_ = runCmd(ctx, "ip", "netns", "del", ns.Name)
	_ = os.RemoveAll(filepath.Join("/etc/netns", ns.Name))
}

func addNetnsFirewall(ctx context.Context, ns *netnsRuntime) {
	delNetnsFirewall(ctx, ns)
	_ = runCmd(ctx, "iptables", "-t", "nat", "-I", "POSTROUTING", "1", "-s", ns.NsIP+"/32", "-o", ns.Dev, "-j", "MASQUERADE", "-m", "comment", "--comment", "olcrtc-manager-netns")
	_ = runCmd(ctx, "iptables", "-I", "FORWARD", "1", "-i", ns.HostIf, "-o", ns.Dev, "-j", "ACCEPT", "-m", "comment", "--comment", "olcrtc-manager-netns")
	_ = runCmd(ctx, "iptables", "-I", "FORWARD", "1", "-i", ns.Dev, "-o", ns.HostIf, "-m", "conntrack", "--ctstate", "RELATED,ESTABLISHED", "-j", "ACCEPT", "-m", "comment", "--comment", "olcrtc-manager-netns")
}

func delNetnsFirewall(ctx context.Context, ns *netnsRuntime) {
	for i := 0; i < 8; i++ {
		if runCmd(ctx, "iptables", "-t", "nat", "-D", "POSTROUTING", "-s", ns.NsIP+"/32", "-o", ns.Dev, "-j", "MASQUERADE", "-m", "comment", "--comment", "olcrtc-manager-netns") != nil {
			break
		}
	}
	for i := 0; i < 8; i++ {
		if runCmd(ctx, "iptables", "-D", "FORWARD", "-i", ns.HostIf, "-o", ns.Dev, "-j", "ACCEPT", "-m", "comment", "--comment", "olcrtc-manager-netns") != nil {
			break
		}
	}
	for i := 0; i < 8; i++ {
		if runCmd(ctx, "iptables", "-D", "FORWARD", "-i", ns.Dev, "-o", ns.HostIf, "-m", "conntrack", "--ctstate", "RELATED,ESTABLISHED", "-j", "ACCEPT", "-m", "comment", "--comment", "olcrtc-manager-netns") != nil {
			break
		}
	}
}

func applyNetnsSpeed(ctx context.Context, ns *netnsRuntime, speedMbps int) error {
	rate := strconv.Itoa(speedMbps) + "mbit"
	if err := applyHTBSpeed(ctx, ns.HostIf, rate); err != nil {
		return err
	}
	if err := runCmd(ctx, "ip", "netns", "exec", ns.Name, "tc", "qdisc", "replace", "dev", ns.NsIf, "root", "handle", "1:", "htb", "default", "10"); err != nil {
		return err
	}
	if err := runCmd(ctx, "ip", "netns", "exec", ns.Name, "tc", "class", "replace", "dev", ns.NsIf, "parent", "1:", "classid", "1:10", "htb", "rate", rate, "ceil", rate); err != nil {
		return err
	}
	return nil
}

func applyHTBSpeed(ctx context.Context, dev, rate string) error {
	if err := runCmd(ctx, "tc", "qdisc", "replace", "dev", dev, "root", "handle", "1:", "htb", "default", "10"); err != nil {
		return err
	}
	return runCmd(ctx, "tc", "class", "replace", "dev", dev, "parent", "1:", "classid", "1:10", "htb", "rate", rate, "ceil", rate)
}

func writeNetnsResolv(nsName, dns string) error {
	host := strings.TrimSpace(dns)
	if strings.Contains(host, ":") {
		host, _, _ = net.SplitHostPort(host)
	}
	if net.ParseIP(host) == nil {
		host = "1.1.1.1"
	}
	dir := filepath.Join("/etc/netns", nsName)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "resolv.conf"), []byte("nameserver "+host+"\n"), 0o644)
}

func netnsIPs(key string) (string, string) {
	h := fnv.New32a()
	_, _ = h.Write([]byte(key))
	n := h.Sum32() % 16000
	second := 200 + int(n/4096)
	third := int(n%4096) / 16
	fourth := 1 + int(n%16)*4
	return fmt.Sprintf("10.%d.%d.%d", second, third, fourth), fmt.Sprintf("10.%d.%d.%d", second, third, fourth+1)
}

func runCmd(ctx context.Context, name string, args ...string) error {
	cmdCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(cmdCtx, name, args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return nil
}

func startInstance(ctx context.Context, olcrtcPath string, loc Location) (*process, error) {
	cfg, err := serverConfig(loc)
	if err != nil {
		return nil, fmt.Errorf("build olcrtc config for %s: %w", locationKey(loc), err)
	}
	configPath, err := writeTempOlcrtcConfig("olcrtc-manager-srv", cfg)
	if err != nil {
		return nil, err
	}
	hostNetwork := strings.EqualFold(strings.TrimSpace(os.Getenv("OLCRTC_HOST_NETWORK")), "1") ||
		strings.EqualFold(strings.TrimSpace(os.Getenv("OLCRTC_HOST_NETWORK")), "true")

	var (
		cmd *exec.Cmd
		ns  *netnsRuntime
	)
	if hostNetwork {
		cmd = exec.CommandContext(ctx, olcrtcPath, configPath)
	} else {
		ns, err = setupNetns(ctx, loc)
		if err != nil {
			_ = os.Remove(configPath)
			return nil, fmt.Errorf("setup netns for %s: %w", locationKey(loc), err)
		}
		cmdArgs := []string{"netns", "exec", ns.Name, olcrtcPath, configPath}
		cmd = exec.CommandContext(ctx, "ip", cmdArgs...)
	}
	logs := newLogBuffer(500)
	cmd.Stdout = logWriter{stream: "stdout", buffer: logs}
	cmd.Stderr = logWriter{stream: "stderr", buffer: logs}

	if err := cmd.Start(); err != nil {
		if ns != nil {
			cleanupNetns(context.Background(), ns)
		}
		_ = os.Remove(configPath)
		return nil, fmt.Errorf("start olcrtc for %s: %w", locationKey(loc), err)
	}

	startedIn := "netns"
	if hostNetwork {
		startedIn = "host"
	} else if ns != nil {
		startedIn = ns.Name
	}
	p := &process{location: loc, cmd: cmd, netns: ns, logs: logs, done: make(chan error, 1), started: time.Now(), running: true}
	log.Printf("started olcrtc for %s in %s: %s %s", locationKey(loc), startedIn, olcrtcPath, configPath)

	go func() {
		err := cmd.Wait()
		p.markExited(err)
		if ns != nil {
			cleanupNetns(context.Background(), ns)
		}
		_ = os.Remove(configPath)
		p.done <- err
	}()

	return p, nil
}

func stopProcess(p *process) {
	if p.cmd == nil || p.cmd.Process == nil {
		return
	}
	_ = p.cmd.Process.Signal(syscall.SIGTERM)
}

func isLoopbackRequest(r *http.Request) bool {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func startInstances(ctx context.Context, olcrtcPath string, locations []Location) ([]*process, error) {
	processes := make([]*process, 0, len(locations))
	for _, loc := range locations {
		p, err := startInstance(ctx, olcrtcPath, loc)
		if err != nil {
			stopInstances(processes)
			return nil, err
		}
		processes = append(processes, p)
	}
	return processes, nil
}

func stopInstances(processes []*process) {
	for _, p := range processes {
		stopProcess(p)
	}
}

func loadConfig(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("read config: %w", err)
	}

	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, fmt.Errorf("parse config: %w", err)
	}
	cfg.Normalize()
	if warns := sanitizeConfigInvalidLocations(&cfg); len(warns) > 0 {
		for _, w := range warns {
			log.Printf("config sanitize: %s", w)
		}
		_ = saveConfig(path, cfg)
	}
	return cfg, nil
}

func (c *Config) Normalize() {
	if c.Version == 0 && c.LegacyVersion != 0 {
		c.Version = c.LegacyVersion
	}

	if path, err := normalizeSubscriptionPath(c.SubscriptionPath); err == nil {
		c.SubscriptionPath = path
	}
	c.Refresh = strings.TrimSpace(c.Refresh)
	for i := range c.Clients {
		c.Clients[i].Refresh = strings.TrimSpace(c.Clients[i].Refresh)
	}

	if len(c.Clients) == 0 {
		return
	}

	locations := make([]Location, 0)
	for _, client := range c.Clients {
		for _, loc := range client.Locations {
			if loc.ClientID == "" {
				loc.ClientID = client.ClientID
			}
			locations = append(locations, loc)
		}
	}
	c.Locations = locations
}

func (c Config) Validate() error {
	if c.Port <= 0 || c.Port > 65535 {
		return fmt.Errorf("port must be between 1 and 65535, got %d", c.Port)
	}
	if _, err := normalizeSubscriptionPath(c.SubscriptionPath); err != nil {
		return fmt.Errorf("subscription_path: %w", err)
	}
	if err := validateRefresh(c.Refresh); err != nil {
		return fmt.Errorf("refresh: %w", err)
	}
	for i, client := range c.Clients {
		if err := validateRefresh(client.Refresh); err != nil {
			return fmt.Errorf("clients[%d].refresh: %w", i, err)
		}
		if err := validateQuota(client.Quota); err != nil {
			return fmt.Errorf("clients[%d].quota: %w", i, err)
		}
	}

	ids := make(map[string]struct{}, len(c.Locations))
	for i, loc := range c.Locations {
		prefix := fmt.Sprintf("locations[%d]", i)
		if loc.ClientID == "" {
			return fmt.Errorf("%s.client-id is required", prefix)
		}
		if loc.Endpoint.RoomID == "" || loc.Endpoint.RoomID == "any" {
			return fmt.Errorf("%s.endpoint.room_id must be concrete", prefix)
		}
		if loc.Endpoint.Key == "" {
			return fmt.Errorf("%s.endpoint.key is required", prefix)
		}
		if loc.Carrier == "" {
			return fmt.Errorf("%s.carrier is required", prefix)
		}
		if loc.Transport.Type == "" {
			return fmt.Errorf("%s.transport.type is required", prefix)
		}
		key := locationKey(loc)
		if _, exists := ids[key]; exists {
			return fmt.Errorf("%s location key %q is duplicated", prefix, key)
		}
		ids[key] = struct{}{}
		if !isSupported(loc.Carrier, loc.Transport.Type) {
			return fmt.Errorf("%s: unsupported carrier/transport combination %s + %s", prefix, loc.Carrier, loc.Transport.Type)
		}
		if err := validatePayload(loc.Transport); err != nil {
			return fmt.Errorf("%s.transport: %w", prefix, err)
		}
		if loc.Link == "" {
			return fmt.Errorf("%s.link is required", prefix)
		}
		if loc.Data == "" {
			return fmt.Errorf("%s.data is required", prefix)
		}
		if loc.DNS == "" {
			return fmt.Errorf("%s.dns is required", prefix)
		}
	}
	return nil
}

func locationKey(loc Location) string {
	return strings.Join([]string{loc.ClientID, loc.Endpoint.RoomID, loc.Transport.Type}, ":")
}

func isSupported(carrier, transport string) bool {
	matrix := map[string]map[string]bool{
		"telemost": {
			"datachannel":  false,
			"vp8channel":   true,
			"seichannel":   true,
			"videochannel": false,
		},
		"jazz": {
			"datachannel":  true,
			"vp8channel":   false,
			"seichannel":   false,
			"videochannel": false,
		},
		"wbstream": {
			"datachannel":  true,
			"vp8channel":   true,
			"seichannel":   true,
			"videochannel": false,
		},
		"jitsi": {
			"datachannel":  true,
			"vp8channel":   true,
			"seichannel":   true,
			"videochannel": false,
		},
	}
	return matrix[carrier][transport]
}

func validatePayload(t Transport) error {
	allowed := map[string]map[string]struct{}{
		"datachannel":  {},
		"vp8channel":   {"vp8-fps": {}, "vp8-batch": {}},
		"seichannel":   {"fps": {}, "batch": {}, "frag": {}, "ack-ms": {}},
		"videochannel": {"video-w": {}, "video-h": {}, "video-fps": {}, "video-bitrate": {}, "video-hw": {}, "video-codec": {}, "video-qr-size": {}, "video-qr-recovery": {}, "video-tile-module": {}, "video-tile-rs": {}},
	}

	keys, ok := allowed[t.Type]
	if !ok {
		return fmt.Errorf("unknown transport %q", t.Type)
	}
	for key := range t.Payload {
		if _, ok := keys[key]; !ok {
			return fmt.Errorf("unsupported payload key %q for %s", key, t.Type)
		}
	}
	if _, err := serverConfig(Location{Transport: t}); err != nil {
		return err
	}
	return nil
}

func resolveOlcrtcPath() (string, error) {
	if path := os.Getenv("OLCRTC_PATH"); path != "" {
		return path, nil
	}

	exe, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("resolve executable path: %w", err)
	}
	return filepath.Join(filepath.Dir(exe), "olcrtc"), nil
}

func envDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func defaultString(value, fallback string) string {
	if value != "" {
		return value
	}
	return fallback
}

func normalizeSubscriptionPath(path string) (string, error) {
	path = strings.TrimSpace(path)
	path = strings.Trim(path, "/")
	if path == "" {
		return "sub", nil
	}
	if strings.Contains(path, "\\") || strings.Contains(path, "?") || strings.Contains(path, "#") {
		return "", errors.New("must be a plain URL path without query or fragment")
	}
	parts := strings.Split(path, "/")
	reserved := map[string]struct{}{
		"-":      {},
		"admin":  {},
		"api":    {},
		"assets": {},
	}
	for i, part := range parts {
		if part == "" || part == "." || part == ".." {
			return "", errors.New("must not contain empty, . or .. segments")
		}
		if strings.ContainsAny(part, " \t\r\n") {
			return "", errors.New("must not contain whitespace")
		}
		if i == 0 {
			if _, ok := reserved[part]; ok {
				return "", fmt.Errorf("must not start with reserved segment %q", part)
			}
		}
	}
	return strings.Join(parts, "/"), nil
}

func validateRefresh(refresh string) error {
	if refresh == "" {
		return nil
	}
	if len(refresh) < 2 {
		return errors.New("must use intervals like 5s, 10m, 6h or 1d")
	}
	unit := refresh[len(refresh)-1]
	if unit != 's' && unit != 'm' && unit != 'h' && unit != 'd' {
		return errors.New("must end with s, m, h or d")
	}
	value := refresh[:len(refresh)-1]
	if strings.HasPrefix(value, "0") {
		return errors.New("must be greater than zero")
	}
	for _, ch := range value {
		if ch < '0' || ch > '9' {
			return errors.New("must use intervals like 5s, 10m, 6h or 1d")
		}
	}
	n, err := strconv.Atoi(value)
	if err != nil || n <= 0 {
		return errors.New("must be greater than zero")
	}
	return nil
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func subscriptionHandler(supervisor *Supervisor) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		clientID, ok := clientIDFromSubscriptionPath(r.URL.Path, supervisor.SubscriptionPath())
		if !ok {
			http.NotFound(w, r)
			return
		}

		sub, ok := supervisor.SubscriptionForClient(clientID, time.Now())
		if !ok {
			http.NotFound(w, r)
			return
		}

		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = w.Write([]byte(sub))
	})
}

func adminAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, pass := adminCredentials(configPathFromRequest(r))
		if user == "" || pass == "" {
			writeJSONStatus(w, http.StatusUnauthorized, map[string]any{"setup_required": true})
			return
		}
		if cookie, err := r.Cookie("olcrtc_session"); err == nil && adminSessions.Valid(cookie.Value) {
			next.ServeHTTP(w, r)
			return
		}
		remote := remoteHost(r)
		if authLimiter.Blocked(remote) {
			http.Error(w, "too many auth failures", http.StatusTooManyRequests)
			return
		}
		gotUser, gotPass, ok := r.BasicAuth()
		userOK := subtle.ConstantTimeCompare([]byte(gotUser), []byte(user)) == 1
		passOK := subtle.ConstantTimeCompare([]byte(gotPass), []byte(pass)) == 1
		if !ok || !userOK || !passOK {
			authLimiter.Fail(remote)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		authLimiter.Reset(remote)
		next.ServeHTTP(w, r)
	})
}

func configPathFromRequest(r *http.Request) string {
	if value, ok := r.Context().Value(configPathContextKey{}).(string); ok {
		return value
	}
	return adminConfigPath
}

type configPathContextKey struct{}

func authMeHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		user, pass := adminCredentials(configPath)
		if user == "" || pass == "" {
			writeJSON(w, map[string]any{"authenticated": false, "setup_required": true})
			return
		}
		if cookie, err := r.Cookie("olcrtc_session"); err == nil && adminSessions.Valid(cookie.Value) {
			writeJSON(w, map[string]any{"authenticated": true, "user": user})
			return
		}
		writeJSONStatus(w, http.StatusUnauthorized, map[string]any{"authenticated": false})
	}
}

func loginHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req struct {
			User     string `json:"user"`
			Password string `json:"password"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		user, pass := adminCredentials(configPath)
		if user == "" || pass == "" {
			writeJSONStatus(w, http.StatusConflict, map[string]any{"setup_required": true})
			return
		}
		remote := remoteHost(r)
		if authLimiter.Blocked(remote) {
			http.Error(w, "too many auth failures", http.StatusTooManyRequests)
			return
		}
		userOK := subtle.ConstantTimeCompare([]byte(req.User), []byte(user)) == 1
		passOK := subtle.ConstantTimeCompare([]byte(req.Password), []byte(pass)) == 1
		if user == "" || pass == "" || !userOK || !passOK {
			authLimiter.Fail(remote)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		authLimiter.Reset(remote)
		token, err := adminSessions.Create()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		setSessionCookie(w, token)
		writeJSON(w, map[string]any{"authenticated": true, "user": user})
	}
}

func setupHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if user, pass := adminCredentials(configPath); user != "" && pass != "" {
			writeJSONStatus(w, http.StatusConflict, map[string]any{"setup_required": false})
			return
		}
		var req struct {
			User     string `json:"user"`
			Password string `json:"password"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		req.User = strings.TrimSpace(req.User)
		if req.User == "" {
			req.User = "admin"
		}
		if len(req.Password) < 8 {
			http.Error(w, "password must contain at least 8 characters", http.StatusBadRequest)
			return
		}
		if err := updatePanelEnvPassword(configPath, req.User, req.Password); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		token, err := adminSessions.Create()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		setSessionCookie(w, token)
		writeJSON(w, map[string]any{"authenticated": true, "user": req.User})
	}
}

func setSessionCookie(w http.ResponseWriter, token string) {
	http.SetCookie(w, &http.Cookie{
		Name:     "olcrtc_session",
		Value:    token,
		Path:     "/",
		MaxAge:   int(adminSessionTTL.Seconds()),
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
}

func logoutHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if cookie, err := r.Cookie("olcrtc_session"); err == nil {
		adminSessions.Delete(cookie.Value)
	}
	http.SetCookie(w, &http.Cookie{Name: "olcrtc_session", Value: "", Path: "/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode})
	w.WriteHeader(http.StatusNoContent)
}

func changePasswordHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req struct {
			CurrentPassword string `json:"current_password"`
			NewPassword     string `json:"new_password"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		user, pass := adminCredentials(configPath)
		if subtle.ConstantTimeCompare([]byte(req.CurrentPassword), []byte(pass)) != 1 {
			http.Error(w, "current password is invalid", http.StatusUnauthorized)
			return
		}
		if len(req.NewPassword) < 8 {
			http.Error(w, "new password must contain at least 8 characters", http.StatusBadRequest)
			return
		}
		if err := updatePanelEnvPassword(configPath, user, req.NewPassword); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		adminSessions.Clear()
		writeJSON(w, map[string]any{"changed": true})
	}
}

func adminCredentials(configPath string) (string, string) {
	user := os.Getenv("OLCRTC_MANAGER_USER")
	pass := os.Getenv("OLCRTC_MANAGER_PASS")
	envPath := panelEnvPath(configPath)
	if values, err := readEnvFile(envPath); err == nil {
		user = defaultString(values["OLCRTC_MANAGER_USER"], user)
		pass = defaultString(values["OLCRTC_MANAGER_PASS"], pass)
	}
	return user, pass
}

func currentAdminUser(configPath string) string {
	user, _ := adminCredentials(configPath)
	return user
}

func panelEnvPath(configPath string) string {
	if path := os.Getenv("OLCRTC_MANAGER_ENV_FILE"); path != "" {
		return path
	}
	if configPath != "" {
		return filepath.Join(filepath.Dir(configPath), "panel.env")
	}
	return "/etc/olcrtc-manager/panel.env"
}

func readEnvFile(path string) (map[string]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	values := make(map[string]string)
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") || !strings.Contains(line, "=") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		values[strings.TrimSpace(parts[0])] = strings.Trim(strings.TrimSpace(parts[1]), `"'`)
	}
	return values, nil
}

func updatePanelEnvPassword(configPath, user, pass string) error {
	path := panelEnvPath(configPath)
	values, _ := readEnvFile(path)
	if values == nil {
		values = make(map[string]string)
	}
	values["OLCRTC_MANAGER_USER"] = defaultString(user, "admin")
	values["OLCRTC_MANAGER_PASS"] = pass
	data := fmt.Sprintf("OLCRTC_MANAGER_USER=%s\nOLCRTC_MANAGER_PASS=%s\n", shellQuote(values["OLCRTC_MANAGER_USER"]), shellQuote(values["OLCRTC_MANAGER_PASS"]))
	return os.WriteFile(path, []byte(data), 0o600)
}

func shellQuote(value string) string {
	if value == "" {
		return "''"
	}
	return "'" + strings.ReplaceAll(value, "'", "'\"'\"'") + "'"
}

type authLimiterState struct {
	count int
	until time.Time
}

type authLimiterType struct {
	mu    sync.Mutex
	state map[string]authLimiterState
}

func newAuthLimiter() *authLimiterType {
	return &authLimiterType{state: make(map[string]authLimiterState)}
}

func (l *authLimiterType) Blocked(remote string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	state := l.state[remote]
	if time.Now().Before(state.until) {
		return true
	}
	return false
}

func (l *authLimiterType) Fail(remote string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	state := l.state[remote]
	state.count++
	if state.count >= 5 {
		state.until = time.Now().Add(time.Minute)
	}
	l.state[remote] = state
}

func (l *authLimiterType) Reset(remote string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.state, remote)
}


const adminSessionTTL = 30 * 24 * time.Hour

func sessionFilePath(configPath string) string {
	if v := strings.TrimSpace(os.Getenv("OLCRTC_MANAGER_SESSIONS")); v != "" {
		return v
	}
	return filepath.Join("/var/lib/olcrtc", "manager-sessions.json")
}

func (s *sessionStore) loadFromDisk() {
	path := s.persistPath
	if path == "" {
		return
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	var raw map[string]string
	if json.Unmarshal(data, &raw) != nil {
		return
	}
	now := time.Now()
	s.mu.Lock()
	defer s.mu.Unlock()
	for token, exp := range raw {
		if t, err := time.Parse(time.RFC3339, exp); err == nil && now.Before(t) {
			s.sessions[token] = t
		}
	}
}

func (s *sessionStore) persistLocked() {
	if s.persistPath == "" {
		return
	}
	raw := make(map[string]string, len(s.sessions))
	for token, exp := range s.sessions {
		raw[token] = exp.UTC().Format(time.RFC3339)
	}
	data, err := json.Marshal(raw)
	if err != nil {
		return
	}
	_ = os.MkdirAll(filepath.Dir(s.persistPath), 0o700)
	_ = os.WriteFile(s.persistPath, data, 0o600)
}

type sessionStore struct {
	mu          sync.Mutex
	sessions    map[string]time.Time
	persistPath string
}

func newSessionStore() *sessionStore {
	s := &sessionStore{sessions: make(map[string]time.Time), persistPath: sessionFilePath("")}
	s.loadFromDisk()
	return s
}

func newSessionStoreForConfig(configPath string) *sessionStore {
	s := &sessionStore{sessions: make(map[string]time.Time), persistPath: sessionFilePath(configPath)}
	s.loadFromDisk()
	return s
}

func (s *sessionStore) Create() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	token := hex.EncodeToString(buf)
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sessions[token] = time.Now().Add(adminSessionTTL)
	s.persistLocked()
	return token, nil
}

func (s *sessionStore) Valid(token string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	expires, ok := s.sessions[token]
	if !ok {
		return false
	}
	if time.Now().After(expires) {
		delete(s.sessions, token)
		return false
	}
	return true
}

func (s *sessionStore) Delete(token string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.sessions, token)
	s.persistLocked()
}

func (s *sessionStore) Clear() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sessions = make(map[string]time.Time)
	s.persistLocked()
}

func remoteHost(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func adminFileServer() (http.Handler, error) {
	dist, err := fs.Sub(adminAssets, "web/dist")
	if err != nil {
		return nil, fmt.Errorf("load admin assets: %w", err)
	}
	return http.FileServer(http.FS(dist)), nil
}

func adminPageHandler(files http.Handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		r.URL.Path = "/"
		files.ServeHTTP(w, r)
	}
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}

func writeJSONStatus(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data: https://api.qrserver.com; style-src 'self' 'unsafe-inline'; script-src 'self'")
		next.ServeHTTP(w, r)
	})
}

func clientIDFromPath(path string) (string, bool) {
	clientID := strings.Trim(path, "/")
	if clientID == "" || strings.Contains(clientID, "/") {
		return "", false
	}
	return clientID, true
}

func clientIDFromSubscriptionPath(path, subscriptionPath string) (string, bool) {
	subscriptionPath, err := normalizeSubscriptionPath(subscriptionPath)
	if err != nil {
		return "", false
	}
	if subscriptionPath == "" {
		return clientIDFromPath(path)
	}
	prefix := "/" + subscriptionPath + "/"
	if !strings.HasPrefix(path, prefix) {
		return "", false
	}
	return clientIDFromPath(strings.TrimPrefix(path, "/"+subscriptionPath))
}

func subscription(cfg Config, now time.Time) string {
	return subscriptionForLocations(cfg.Name, cfg.Refresh, cfg.Locations, Quota{}, now)
}

func subscriptionForClient(cfg Config, clientID string, now time.Time) (string, bool) {
	for _, client := range cfg.Clients {
		if client.ClientID == clientID {
			refresh := effectiveRefresh(cfg.Refresh, client.Refresh)
			if len(client.Locations) == 0 {
				return "", false
			}
			if quotaStatus(client.Quota, now) != "active" {
				return subscriptionForLocations(cfg.Name, refresh, nil, client.Quota, now), true
			}
			return subscriptionForLocations(cfg.Name, refresh, client.Locations, client.Quota, now), true
		}
	}
	locations := make([]Location, 0)
	for _, loc := range cfg.Locations {
		if loc.ClientID == clientID {
			locations = append(locations, loc)
		}
	}
	if len(locations) == 0 {
		return "", false
	}
	return subscriptionForLocations(cfg.Name, cfg.Refresh, locations, Quota{}, now), true
}

func effectiveRefresh(globalRefresh, clientRefresh string) string {
	if strings.TrimSpace(clientRefresh) != "" {
		return strings.TrimSpace(clientRefresh)
	}
	return strings.TrimSpace(globalRefresh)
}

func subscriptionForLocations(name, refresh string, locations []Location, quota Quota, now time.Time) string {
	var b bytes.Buffer
	if name != "" {
		fmt.Fprintf(&b, "#name: %s\n", name)
	}
	fmt.Fprintf(&b, "#update: %d\n", now.Unix())
	if refresh != "" {
		fmt.Fprintf(&b, "#refresh: %s\n", refresh)
	}
	fmt.Fprintln(&b)
	if quota.SpeedMbps > 0 {
		fmt.Fprintf(&b, "#quota-speed-mbps: %d\n", quota.SpeedMbps)
	}
	if quota.TrafficGB > 0 {
		fmt.Fprintf(&b, "#quota-traffic-gb: %d\n", quota.TrafficGB)
		fmt.Fprintf(&b, "#quota-used-gb: %d\n", quota.UsedGB)
		fmt.Fprintf(&b, "#quota-used-bytes: %d\n", quotaUsedBytes(quota))
	}
	if quota.ExpiresAt != "" {
		fmt.Fprintf(&b, "#quota-expires-at: %s\n", quota.ExpiresAt)
	}
	if quota.SpeedMbps > 0 || quota.TrafficGB > 0 || quota.ExpiresAt != "" {
		fmt.Fprintf(&b, "#quota-status: %s\n\n", quotaStatus(quota, now))
	}

	for _, loc := range locations {
		fmt.Fprintln(&b, locationURI(loc))
		if loc.Name != "" {
			fmt.Fprintf(&b, "##name: %s\n", loc.Name)
		}
		fmt.Fprintln(&b)
	}
	return b.String()
}

func locationURI(loc Location) string {
	payload := payloadString(loc.Transport.Payload)
	return fmt.Sprintf("olcrtc://%s?%s%s@%s#%s$%s",
		loc.Carrier,
		loc.Transport.Type,
		payload,
		loc.Endpoint.RoomID,
		loc.Endpoint.Key,
		loc.Name,
	)
}

func payloadString(payload map[string]string) string {
	if len(payload) == 0 {
		return ""
	}

	parts := make([]string, 0, len(payload))
	for _, key := range sortedKeys(payload) {
		parts = append(parts, key+"="+payload[key])
	}
	return "<" + strings.Join(parts, "&") + ">"
}

func sortedKeys(m map[string]string) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}


// featureNames is the whitelist of allowed toggles. Any other value is rejected
// before invoking the helper script — prevents argument injection into bash.
var featureNames = []string{"zapret", "tor", "split", "webtunnel", "warp", "olcrtc"}

func featureScriptPath() string {
	if p := os.Getenv("OLC_FEATURE_SCRIPT"); p != "" {
		return p
	}
	candidates := []string{
		"/opt/Olc-cost-l/scripts/olc-feature.sh",
		"/usr/local/bin/olc-feature",
	}
	for _, c := range candidates {
		if info, err := os.Stat(c); err == nil && !info.IsDir() {
			return c
		}
	}
	return ""
}

func readFeatureFlags() map[string]bool {
	flags := map[string]bool{}
	for _, n := range featureNames {
		flags[n] = true
	}
	data, err := os.ReadFile("/etc/olcrtc-manager/features.env")
	if err != nil {
		return flags
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		eq := strings.IndexByte(line, '=')
		if eq < 0 {
			continue
		}
		key := strings.TrimSpace(line[:eq])
		val := strings.Trim(strings.TrimSpace(line[eq+1:]), "\"'")
		switch key {
		case "OLCRTC_ENABLE_ZAPRET":
			flags["zapret"] = val != "0"
		case "OLCRTC_ENABLE_TOR":
			flags["tor"] = val != "0"
		case "OLCRTC_ENABLE_SPLIT":
			flags["split"] = val != "0"
		case "OLCRTC_ENABLE_WEBTUNNEL":
			flags["webtunnel"] = val != "0"
		case "OLCRTC_ENABLE_WARP":
			flags["warp"] = val != "0"
		}
	}
	return flags
}

func featureLiveStatus() map[string]string {
	out := map[string]string{}
	units := map[string]string{
		"tor":      "tor@default",
		"zapret":   "zapret",
		"manager":  "olcrtc-manager",
	}
	for name, unit := range units {
		cmd := exec.Command("systemctl", "is-active", unit)
		b, _ := cmd.Output()
		out[name] = strings.TrimSpace(string(b))
	}
	out["nfqws"] = "unknown"
	if b, err := exec.Command("pidof", "nfqws").Output(); err == nil && len(strings.TrimSpace(string(b))) > 0 {
		out["nfqws"] = "running"
	} else {
		out["nfqws"] = "stopped"
	}
	out["warp"] = "missing"
	if _, err := exec.LookPath("warp-cli"); err == nil {
		cmd := exec.Command("warp-cli", "status")
		b, _ := cmd.CombinedOutput()
		out["warp"] = strings.TrimSpace(string(b))
		if len(out["warp"]) > 80 {
			out["warp"] = out["warp"][:80] + "..."
		}
	}
	out["webtunnel"] = "missing"
	for _, c := range []string{"/usr/bin/webtunnel-client", "/usr/local/bin/webtunnel-client"} {
		if info, err := os.Stat(c); err == nil && !info.IsDir() {
			out["webtunnel"] = filepath.Base(c) + " present"
			break
		}
	}
	return out
}




func githubTokenFromEnv() string {
	for _, key := range []string{"GITHUB_TOKEN", "GH_TOKEN", "OLCRTC_GITHUB_TOKEN"} {
		if v := strings.TrimSpace(os.Getenv(key)); v != "" {
			return v
		}
	}
	for _, path := range []string{"/etc/olcrtc-manager/github.env", "/etc/olcrtc-manager/panel.env"} {
		b, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(b), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			if strings.HasPrefix(line, "export ") {
				line = strings.TrimPrefix(line, "export ")
			}
			parts := strings.SplitN(line, "=", 2)
			if len(parts) != 2 {
				continue
			}
			k := strings.TrimSpace(parts[0])
			v := strings.Trim(strings.TrimSpace(parts[1]), `"'`)
			if k == "GITHUB_TOKEN" || k == "GH_TOKEN" || k == "OLCRTC_GITHUB_TOKEN" {
				return v
			}
		}
	}
	return ""
}

func releaseInfoFromVersion(ver map[string]any) (tag, name string) {
	rel, _ := ver["release"].(map[string]any)
	if rel == nil {
		return "", ""
	}
	tag, _ = rel["tag"].(string)
	tag = strings.TrimSpace(tag)
	if tag == "" {
		return "", ""
	}
	return tag, normalizeVerTag(tag)
}

func reconcileStaleUpdateJob() {
	if panelUpdateLocked() {
		return
	}
	var st map[string]any
	if !readJSONFile(panelUpdateStatus, &st) {
		return
	}
	if st["status"] != "running" {
		return
	}
	st["status"] = "failed"
	st["error"] = "зависло (процесс обновления прерван) — повторите «Обновить с GitHub»"
	st["exit_code"] = 1
	b, _ := json.Marshal(st)
	_ = os.WriteFile(panelUpdateStatus, b, 0644)
}

func normalizeVerTag(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(strings.ToLower(s), "v")
	return s
}

func versionNewer(current, latest string) bool {
	c := normalizeVerTag(current)
	l := normalizeVerTag(latest)
	if c == "" || l == "" || c == l {
		return false
	}
	if strings.Contains(c, "-alpha.") && strings.Contains(l, "-alpha.") {
		cp := strings.SplitN(c, "-alpha.", 2)
		lp := strings.SplitN(l, "-alpha.", 2)
		if len(cp) == 2 && len(lp) == 2 && cp[0] == lp[0] {
			return cp[1] < lp[1]
		}
	}
	return strings.Compare(l, c) > 0
}

func githubRepoFromVersion(ver map[string]any) string {
	raw, _ := ver["repo"].(string)
	raw = strings.TrimSpace(raw)
	raw = strings.TrimPrefix(raw, "https://github.com/")
	raw = strings.TrimPrefix(raw, "http://github.com/")
	return strings.TrimSuffix(raw, "/")
}

func gitIsAncestor(repo, older, newer string) bool {
	if repo == "" || older == "" || newer == "" || older == newer {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", "-c", "safe.directory="+repo, "-C", repo, "merge-base", "--is-ancestor", older, newer)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	return cmd.Run() == nil
}

func gitLocalBehindRemote(repo, local, remote string) bool {
	return gitIsAncestor(repo, local, remote) && local != remote
}

func gitLocalAheadOfRemote(repo, local, remote string) bool {
	return gitIsAncestor(repo, remote, local) && local != remote
}

func githubReleaseRequest(ctx context.Context, url string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "olcrtc-manager-panel")
	if tok := githubTokenFromEnv(); tok != "" {
		req.Header.Set("Authorization", "Bearer "+tok)
	}
	return http.DefaultClient.Do(req)
}

func fetchLatestGitHubReleaseList(ownerRepo string) (tag, name string) {
	if ownerRepo == "" {
		return "", ""
	}
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	// /releases/latest is empty when all releases are prerelease — use list
	url := "https://api.github.com/repos/" + ownerRepo + "/releases?per_page=5"
	resp, err := githubReleaseRequest(ctx, url)
	if err != nil {
		return "", ""
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", ""
	}
	var list []struct {
		TagName string `json:"tag_name"`
		Name    string `json:"name"`
		Draft   bool   `json:"draft"`
	}
	if json.NewDecoder(resp.Body).Decode(&list) != nil || len(list) == 0 {
		return "", ""
	}
	for _, rel := range list {
		if rel.Draft {
			continue
		}
		tag := strings.TrimSpace(rel.TagName)
		if tag != "" {
			name := strings.TrimSpace(rel.Name)
			if name == "" {
				name = normalizeVerTag(tag)
			}
			return tag, name
		}
	}
	return "", ""
}

func fetchLatestGitHubRelease(ownerRepo string) (tag, name string) {
	return fetchLatestGitHubReleaseList(ownerRepo)
}

func computeUpdateStatus(repo string) map[string]any {
	ver := readVersionJSON()
	panelVer, _ := ver["panel"].(string)
	ownerRepo := githubRepoFromVersion(ver)
	_ = runGitShort(repo, "fetch", "origin", "main")
	local := runGitShort(repo, "rev-parse", "HEAD")
	remote := runGitShort(repo, "rev-parse", "origin/main")
	installedTag, installedName := releaseInfoFromVersion(ver)
	relTag, relName := fetchLatestGitHubRelease(ownerRepo)
	if relTag == "" && installedTag != "" {
		relTag, relName = installedTag, installedName
	}
	gitBehind := gitLocalBehindRemote(repo, local, remote)
	gitAhead := gitLocalAheadOfRemote(repo, local, remote)
	releaseNewer := relTag != "" && panelVer != "" && versionNewer(panelVer, relTag)
	updateAvailable := releaseNewer || gitBehind
	updateSource := "none"
	if releaseNewer {
		updateSource = "release"
	} else if gitBehind {
		updateSource = "git"
	}
	return map[string]any{
		"local_sha":              local,
		"remote_sha":             remote,
		"panel_version":          panelVer,
		"installed_release_tag":  installedTag,
		"latest_release_tag":     relTag,
		"latest_release_name":    relName,
		"latest_release_version": normalizeVerTag(relTag),
		"update_available":       updateAvailable,
		"update_source":          updateSource,
		"git_behind":             gitBehind,
		"git_ahead":              gitAhead,
	}
}

func readVersionJSON() map[string]any {
	out := map[string]any{"panel": "0.0.0", "channel": "alpha"}
	for _, p := range []string{
		"/opt/Olc-cost-l/version.json",
		"/opt/olcrtc/version.json",
	} {
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		var v map[string]any
		if json.Unmarshal(b, &v) == nil {
			return v
		}
	}
	return out
}

func readDeployProfileID() string {
	for _, p := range []string{"/etc/olcrtc-manager/deploy-profile.json"} {
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		var v struct {
			ProfileID string `json:"profile_id"`
		}
		if json.Unmarshal(b, &v) == nil && v.ProfileID != "" {
			return v.ProfileID
		}
	}
	return ""
}


func componentRemovedMarker(name string) bool {
	_, err := os.Stat(filepath.Join("/var/lib/olcrtc/component-removed", name))
	return err == nil
}

func componentInstalled(name string) bool {
	if componentRemovedMarker(name) {
		return false
	}
	switch name {
	case "zapret":
		if _, err := os.Stat("/opt/zapret/nfq/nfqws"); err == nil {
			return true
		}
		return false

	case "warp":
		_, err := exec.LookPath("warp-cli")
		return err == nil
	case "tor":
		if _, err := os.Stat("/etc/tor/torrc"); err == nil {
			return true
		}
		return false
	case "split":
		if _, err := os.Stat("/var/lib/olcrtc/lists"); err == nil {
			return true
		}
		return false
	case "bridges", "webtunnel":
		if _, err := os.Stat("/usr/bin/webtunnel-client"); err == nil {
			return true
		}
		if _, err := os.Stat("/etc/tor/bridges.conf"); err == nil {
			return true
		}
		return false
	default:
		return false
	}
}

func loadFeatureFlagsMap() map[string]bool {
	flags := map[string]bool{"zapret": true, "tor": true, "split": true, "webtunnel": true, "warp": false}
	path := "/etc/olcrtc-manager/features.env"
	b, err := os.ReadFile(path)
	if err != nil {
		return flags
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key, val := strings.TrimSpace(parts[0]), strings.TrimSpace(parts[1])
		enabled := val == "1" || strings.EqualFold(val, "true")
		switch key {
		case "OLCRTC_ENABLE_ZAPRET":
			flags["zapret"] = enabled
		case "OLCRTC_ENABLE_TOR":
			flags["tor"] = enabled
		case "OLCRTC_ENABLE_SPLIT":
			flags["split"] = enabled
		case "OLCRTC_ENABLE_WEBTUNNEL":
			flags["webtunnel"] = enabled
		case "OLCRTC_ENABLE_WARP":
			flags["warp"] = enabled
		}
	}
	return flags
}


func readTextFile(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return string(b)
}

func writeTextFile(path, body string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(body), 0644)
}

func torSocksPort() string {
	b := readTextFile("/etc/tor/torrc")
	for _, line := range strings.Split(b, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "SocksPort ") {
			return strings.TrimSpace(strings.TrimPrefix(line, "SocksPort"))
		}
	}
	return "9050"
}



func deployProfileComponent(key string) bool {
	b, err := os.ReadFile("/etc/olcrtc-manager/deploy-profile.json")
	if err != nil {
		return false
	}
	var v struct {
		Components map[string]bool `json:"components"`
	}
	if json.Unmarshal(b, &v) != nil {
		return false
	}
	return v.Components[key]
}

func warpConnected() bool {
	cmd := exec.Command("warp-cli", "status")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToLower(string(out)), "connected")
}

func warpSettingsGet() map[string]any {
	env := readPanelEnvMap()
	proxy := env["OLCRTC_WARP_PROXY"]
	if strings.TrimSpace(proxy) == "" {
		proxy = "127.0.0.1:40000"
	}
	mode := env["OLCRTC_WARP_MODE"]
	if strings.TrimSpace(mode) == "" {
		mode = "proxy"
	}
	license := env["OLCRTC_WARP_LICENSE"]
	autoconnect := env["OLCRTC_WARP_AUTOCONNECT"] != "0"
	plus := env["OLCRTC_WARP_PLUS"] == "1"
	return map[string]any{
		"proxy":              proxy,
		"mode":               mode,
		"license_key":        license,
		"autoconnect":        autoconnect,
		"warp_plus":          plus,
		"installed":          componentInstalled("warp"),
		"connected":          warpConnected(),
		"conflicts_with_tor": true,
		"profile_enabled":    deployProfileComponent("warp"),
	}
}

func warpSettingsPut(body map[string]any) error {
	if v, ok := body["proxy"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_WARP_PROXY", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["mode"].(string); ok {
		m := strings.TrimSpace(v)
		if m == "" {
			m = "proxy"
		}
		if m != "proxy" {
			return fmt.Errorf("unsafe warp mode %q blocked; only proxy mode is allowed", m)
		}
		if err := setPanelEnvKey("OLCRTC_WARP_MODE", m); err != nil {
			return err
		}
	}
	if v, ok := body["license_key"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_WARP_LICENSE", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["autoconnect"].(bool); ok {
		val := "0"
		if v {
			val = "1"
		}
		if err := setPanelEnvKey("OLCRTC_WARP_AUTOCONNECT", val); err != nil {
			return err
		}
	}
	if v, ok := body["warp_plus"].(bool); ok {
		val := "0"
		if v {
			val = "1"
		}
		if err := setPanelEnvKey("OLCRTC_WARP_PLUS", val); err != nil {
			return err
		}
	}
	return nil
}

func readPanelEnvMap() map[string]string {
	out := map[string]string{}
	b, err := os.ReadFile("/etc/olcrtc-manager/panel.env")
	if err != nil {
		return out
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			out[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		}
	}
	return out
}

func setPanelEnvKey(key, val string) error {
	allowed := map[string]bool{
		"OLCRTC_JITSI_INSECURE_TLS": true,
		"OLCRTC_PUBLIC_URL":         true,
		"OLCRTC_DIRECT_DOMAINS":     true,
		"OLCRTC_DIRECT_CIDRS":       true,
		"OLCRTC_BLOCKED_TOR_DOMAINS": true,
		"OLCRTC_FORCE_TOR_DOMAINS":  true,
		"OLCRTC_WEBRTC_PROXY":  true,
		"OLCRTC_TOR_PROXY":  true,
		"OLCRTC_DEFAULT_TRANSPORT":  true,
		"OLCRTC_DEFAULT_CARRIER":  true,
		"OLCRTC_SOCKS_PROXY":  true,
		"OLCRTC_WARP_PROXY":  true,
		"OLC_PANEL_LANG":          true,
	}
	if !allowed[key] {
		return fmt.Errorf("key %q not allowed", key)
	}
	path := "/etc/olcrtc-manager/panel.env"
	var lines []string
	if b, err := os.ReadFile(path); err == nil {
		lines = strings.Split(string(b), "\n")
	}
	found := false
	prefix := key + "="
	for i, line := range lines {
		if strings.HasPrefix(strings.TrimSpace(line), prefix) {
			lines[i] = key + "=" + val
			found = true
			break
		}
	}
	if !found {
		lines = append(lines, key+"="+val)
	}
	body := strings.Join(lines, "\n")
	if !strings.HasSuffix(body, "\n") {
		body += "\n"
	}
	return os.WriteFile(path, []byte(body), 0644)
}

func olcrtcSettingsGet() map[string]any {
	env := readPanelEnvMap()
	pins := readPins(olcRepoRoot())
	sha := ""
	if o, ok := pins["olcrtc"].(map[string]any); ok {
		if s, ok := o["pinned_sha"].(string); ok {
			sha = s
		}
	}
	return map[string]any{
		"jitsi_insecure_tls": env["OLCRTC_JITSI_INSECURE_TLS"] == "1",
		"public_url":         env["OLCRTC_PUBLIC_URL"],
		"direct_domains_file": env["OLCRTC_DIRECT_DOMAINS"],
		"direct_cidrs_file":   env["OLCRTC_DIRECT_CIDRS"],
		"blocked_tor_file":    env["OLCRTC_BLOCKED_TOR_DOMAINS"],
		"force_tor_file":      env["OLCRTC_FORCE_TOR_DOMAINS"],
		"warp_proxy":          env["OLCRTC_WARP_PROXY"],
		"socks_proxy":         env["OLCRTC_SOCKS_PROXY"],
		"default_carrier":     env["OLCRTC_DEFAULT_CARRIER"],
		"default_transport":   env["OLCRTC_DEFAULT_TRANSPORT"],
		"default_link":        env["OLCRTC_DEFAULT_LINK"],
		"tor_proxy":           env["OLCRTC_TOR_PROXY"],
		"webrtc_proxy":        env["OLCRTC_WEBRTC_PROXY"],
		"olcrtc_branch":        "master",
		"olcrtc_pinned_sha":  sha,
		"upstream_notes":     "",
	}
}


func defaultBridgeProfiles() map[string]any {
	return map[string]any{
		"active_profile": "system",
		"system": map[string]any{
			"id":           "system",
			"label":        "Оригинальный",
			"types":        "obfs4,webtunnel",
			"auto_update":  true,
			"readonly":     true,
		},
		"profiles": []any{},
	}
}

func readBridgeProfiles() map[string]any {
	out := defaultBridgeProfiles()
	var stored map[string]any
	if readJSONFile(bridgeProfilesPath, &stored) {
		for k, v := range stored {
			out[k] = v
		}
	}
	return out
}

func writeBridgeProfiles(data map[string]any) error {
	if err := os.MkdirAll(filepath.Dir(bridgeProfilesPath), 0755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(bridgeProfilesPath, b, 0644)
}


func readBridgePoolStatus() map[string]any {
	var st map[string]any
	if readJSONFile(bridgePoolStatusFile, &st) {
		st["webtunnel_client"] = fileExists("/usr/bin/webtunnel-client") || fileExists("/usr/local/bin/webtunnel-client")
		status, _ := st["status"].(string)
		logPath, _ := st["log_path"].(string)
		if logPath == "" {
			logPath = "/var/log/olcrtc-bridge-pool.log"
		}
		if status == "running" || status == "done" || status == "error" {
			if tail := tailLogFile(logPath, 120); len(tail) > 0 {
				st["log_tail"] = tail
			}
		}
		return st
	}
	return map[string]any{"status": "idle", "webtunnel_client": fileExists("/usr/bin/webtunnel-client")}
}


func appendBridgePoolLog(line string) {
	line = strings.TrimSpace(line)
	if line == "" {
		return
	}
	f, err := os.OpenFile("/var/log/olcrtc-bridge-pool.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	if !strings.HasSuffix(line, "\n") {
		line += "\n"
	}
	_, _ = f.WriteString(line)
}

func writeBridgePoolStatus(st map[string]any) {
	b, err := json.MarshalIndent(st, "", "  ")
	if err != nil {
		return
	}
	_ = os.MkdirAll(filepath.Dir(bridgePoolStatusFile), 0755)
	_ = os.WriteFile(bridgePoolStatusFile, b, 0644)
}

func tailLogFile(path string, n int) []string {
	lines, err := tailFileLines(path, n)
	if err != nil {
		return nil
	}
	return lines
}

func bridgePoolStats() map[string]any {
	stats := map[string]any{"obfs4": 0, "webtunnel": 0, "other": 0, "total": 0}
	pool := "/var/lib/olcrtc/tor-bridges-pool.txt"
	b, err := os.ReadFile(pool)
	if err != nil {
		return stats
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "Bridge ") {
			continue
		}
		stats["total"] = stats["total"].(int) + 1
		low := strings.ToLower(line)
		switch {
		case strings.Contains(low, " webtunnel "):
			stats["webtunnel"] = stats["webtunnel"].(int) + 1
		case strings.Contains(low, " obfs4 "):
			stats["obfs4"] = stats["obfs4"].(int) + 1
		default:
			stats["other"] = stats["other"].(int) + 1
		}
	}
	return stats
}

func setBridgeAutoCron(enabled bool) {
	if enabled {
		cron := "15 3 * * * root " + filepath.Join(olcRepoRoot(), "scripts/tor-bridge-pool.sh") + " --types obfs4,webtunnel >>/var/log/olcrtc-bridge-pool.log 2>&1\n"
		_ = writeTextFile(bridgeCronPath, cron)
	} else {
		_ = os.Remove(bridgeCronPath)
	}
}

func runBridgePoolRefresh(types string) {
	types = strings.TrimSpace(types)
	if types == "" {
		types = "obfs4,webtunnel"
	}
	writeBridgePoolStatus(map[string]any{
		"status":     "running",
		"started_at": time.Now().Format(time.RFC3339),
		"types":      types,
		"log_path":   "/var/log/olcrtc-bridge-pool.log",
	})
	go func() {
		repo := olcRepoRoot()
		script := filepath.Join(repo, "scripts/tor-bridge-pool.sh")
		if strings.Contains(strings.ToLower(types), "webtunnel") {
			if !fileExists("/usr/bin/webtunnel-client") && !fileExists("/usr/local/bin/webtunnel-client") {
				wt := filepath.Join(repo, "scripts/install-tor-pluggable-transports.sh")
				if _, err := os.Stat(wt); err == nil {
					appendBridgePoolLog("[bridge-pool] installing webtunnel-client (mirror-cry first)...")
					wtCmd := exec.Command("bash", wt)
					wtCmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
					out, wtErr := wtCmd.CombinedOutput()
					if len(out) > 0 {
						appendBridgePoolLog(string(out))
					}
					if wtErr != nil {
						appendBridgePoolLog("[bridge-pool] webtunnel install error: " + wtErr.Error())
					}
				}
			}
		}
		ctx, cancel := context.WithTimeout(context.Background(), 25*time.Minute)
		defer cancel()
		// Full pipeline: fetch + probe + apply → /etc/tor/bridges.conf (not --fetch-only).
		cmd := exec.CommandContext(ctx, "bash", script, "--types", types)
		cmd.Env = append(os.Environ(),
			"PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin",
			"BRIDGE_TYPES="+types,
			"FETCH_MAX_AGE_SEC=0",
			"LOG_FILE=/var/log/olcrtc-bridge-pool.log",
		)
		out, err := cmd.CombinedOutput()
		st := map[string]any{
			"status":           "done",
			"finished_at":      time.Now().Format(time.RFC3339),
			"types":            types,
			"pool_stats":       bridgePoolStats(),
			"webtunnel_client": fileExists("/usr/bin/webtunnel-client"),
			"log_tail":         tailLogFile("/var/log/olcrtc-bridge-pool.log", 40),
		}
		if err != nil {
			st["status"] = "error"
			st["error"] = strings.TrimSpace(err.Error())
			if len(out) > 0 {
				st["output"] = string(out)
			}
		}
		writeBridgePoolStatus(st)
	}()
}


func profileBridgeLinesFromBody(profile map[string]any) []string {
	out := []string{}
	if b, ok := profile["bridges"].(string); ok {
		for _, line := range strings.Split(b, "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			if !strings.HasPrefix(line, "Bridge ") {
				line = "Bridge " + line
			}
			out = append(out, line)
		}
	}
	return out
}

func fetchProfileBridgeLines(profile map[string]any) []string {
	out := profileBridgeLinesFromBody(profile)
	urls, ok := profile["urls"].([]any)
	if !ok {
		return out
	}
	client := http.Client{Timeout: 20 * time.Second}
	for _, u := range urls {
		url, _ := u.(string)
		url = strings.TrimSpace(url)
		if url == "" {
			continue
		}
		resp, err := client.Get(url)
		if err != nil || resp.StatusCode >= 300 {
			if resp != nil {
				resp.Body.Close()
			}
			continue
		}
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 2*1024*1024))
		resp.Body.Close()
		for _, line := range strings.Split(string(b), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			if !strings.HasPrefix(line, "Bridge ") {
				line = "Bridge " + line
			}
			out = append(out, line)
		}
	}
	return out
}

func applyActiveBridgeProfile(profiles map[string]any) error {
	active, _ := profiles["active_profile"].(string)
	if active == "" || active == "system" {
		sys, _ := profiles["system"].(map[string]any)
		types, _ := sys["types"].(string)
		if strings.TrimSpace(types) == "" {
			types = "obfs4,webtunnel"
		}
		runBridgePoolRefresh(types)
		return nil
	}
	profs, _ := profiles["profiles"].([]any)
	var selected map[string]any
	for _, p := range profs {
		m, _ := p.(map[string]any)
		if m != nil && fmt.Sprint(m["id"]) == active {
			selected = m
			break
		}
	}
	if selected == nil {
		return nil
	}
	lines := fetchProfileBridgeLines(selected)
	if len(lines) == 0 {
		return nil
	}
	userPath := "/var/lib/olcrtc/tor-user-bridges.txt"
	body := strings.Join(lines, "\n") + "\n"
	if err := writeTextFile(userPath, body); err != nil {
		return err
	}
	types, _ := selected["types"].(string)
	if strings.TrimSpace(types) == "" {
		types = "obfs4,webtunnel"
	}
	runBridgePoolRefresh(types)
	return nil
}


func firstNonEmpty(v, fallback string) string {
	v = strings.TrimSpace(v)
	if v != "" {
		return v
	}
	return fallback
}

func componentSettingsGet(name string) (map[string]any, error) {
	switch name {
	case "zapret":
		strategy := ""
		if b := readTextFile(filepath.Join(olcRepoRoot(), "data/zapret4rocket/config.default")); b != "" {
			strategy = "z4r-config.default"
		}
		zapretCfg := readTextFile(filepath.Join(olcRepoRoot(), "data/zapret-olcrtc.config"))
		if zapretCfg == "" {
			zapretCfg = readTextFile(filepath.Join(olcRepoRoot(), "data/zapret4rocket/config.default"))
		}
		if len(zapretCfg) > 1200 {
			zapretCfg = zapretCfg[:1200] + "\n..."
		}
		return map[string]any{
			"auto_sync":       fileExists("/etc/cron.d/olcrtc-zapret-sync") || fileExists("/etc/cron.d/zapret-sync"),
			"exclude_domains": readTextFile("/var/lib/olcrtc/zapret-custom/exclude-domains.txt"),
			"force_domains":   readTextFile("/var/lib/olcrtc/zapret-custom/force-domains.txt"),
			"community_sync": fileExists("/var/lib/olcrtc/lists"),
			"zapret_full":     fileExists("/opt/zapret/nfq/nfqws"),
			"strategy":         strategy,
			"strategy_presets": func() []map[string]string { _, p := zapretStrategyState(); return p }(),
			"strategy_current": func() string { c, _ := zapretStrategyState(); return c }(),
			"nfqws_running":   fileExists("/run/zapret/nfqws.pid") || fileExists("/opt/zapret/nfq/nfqws"),
			"nfqws_config":    zapretCfg,
			"hostlist_user":   "/opt/zapret/ipset/zapret-hosts-user.txt",
			"desync_mark":     "0x40000000",
		}, nil
	case "tor":
		return map[string]any{
			"socks_port":         torSocksPort(),
			"exit_nodes":         grepTorrcLine("ExitNodes"),
			"exclude_exit_nodes": grepTorrcLine("ExcludeExitNodes"),
			"strict_nodes":       grepTorrcLine("StrictNodes"),
			"bridges_enabled":    fileExists("/etc/tor/bridges.conf"),
			"socks_listen":       grepTorrcLine("SocksPort"),
			"socks_listen_address": grepTorrcLine("SocksListenAddress"),
			"dns_port":           grepTorrcLine("DNSPort"),
			"test_socks":         grepTorrcLine("TestSocks"),
			"safe_socks":         grepTorrcLine("SafeSocks"),
			"client_transport":   readTextFile("/etc/tor/bridges.conf"),
			"webtunnel_client":   fileExists("/usr/bin/webtunnel-client"),
		}, nil
	case "split":
		env := readPanelEnvMap()
		return map[string]any{
			"custom_direct_domains": readTextFile("/var/lib/olcrtc/lists/custom-direct-domains.txt"),
			"panel_hosts":           readTextFile("/var/lib/olcrtc/lists/panel-carrier-hosts.txt"),
			"panel_cidrs":           readTextFile("/var/lib/olcrtc/lists/panel-carrier-cidrs.txt"),
			"generated_domains":     readTextFile("/var/lib/olcrtc/lists/panel-carrier-generated-domains.txt"),
			"generated_cidrs":       readTextFile("/var/lib/olcrtc/lists/panel-carrier-generated-cidrs.txt"),
			"discovery":             splitDiscoveryManifest(),
			"force_tor_domains":     readSplitRulesWithSeed("/var/lib/olcrtc/force-tor-domains.txt", "data/global-force-tor-domains.txt"),
			"blocked_tor_domains":   readSplitRulesWithSeed("/var/lib/olcrtc/ru-blocked-tor-domains.txt", "data/ru-blocked-tor-seed.txt"),
			"ru_direct_count":       countLines("/var/lib/olcrtc/ru-direct-domains.txt"),
			"direct_cidrs_file":     env["OLCRTC_DIRECT_CIDRS"],
			"cidr_only":             splitCidrOnlyEnabled(),
		}, nil
	case "olcrtc":
		return olcrtcSettingsGet(), nil

	case "warp":
		env := readPanelEnvMap()
		installed := fileExists("/usr/bin/warp-cli") || fileExists("/usr/local/bin/warp-cli")
		connected := false
		if installed {
			out, _ := exec.Command("warp-cli", "status").CombinedOutput()
			s := strings.ToLower(string(out))
			connected = strings.Contains(s, "connected")
		}
		mode := strings.TrimSpace(env["OLCRTC_WARP_MODE"])
		if mode == "" {
			mode = "proxy"
		}
		return map[string]any{
			"proxy":           firstNonEmpty(strings.TrimSpace(env["OLCRTC_WARP_PROXY"]), "127.0.0.1:40000"),
			"mode":            mode,
			"autoconnect":     env["OLCRTC_WARP_AUTOCONNECT"] != "0",
			"warp_plus":       env["OLCRTC_WARP_PLUS"] == "1" || strings.EqualFold(env["OLCRTC_WARP_PLUS"], "true"),
			"license_key":     strings.TrimSpace(env["OLCRTC_WARP_LICENSE"]),
			"installed":       installed,
			"connected":       connected,
			"profile_enabled": readFeatureFlags()["warp"],
		}, nil
	case "bridges":
		bp := readBridgeProfiles()
		active := map[string]any{}
		if id, ok := bp["active_profile"].(string); ok {
			if id == "system" {
				active = bp["system"].(map[string]any)
			} else if profs, ok := bp["profiles"].([]any); ok {
				for _, pr := range profs {
					m, _ := pr.(map[string]any)
					if m != nil && m["id"] == id {
						active = m
						break
					}
				}
			}
		}
		return map[string]any{
			"bridges_conf":    readTextFile("/etc/tor/bridges.conf"),
			"webtunnel":       fileExists("/usr/bin/webtunnel-client"),
			"pool_job":        readBridgePoolStatus(),
			"pool_stats":      bridgePoolStats(),
			"profiles":        bp,
			"active_profile":  active,
		}, nil
	default:
		return nil, fmt.Errorf("unknown component %q", name)
	}
}


func patchTorrcKey(key, val string) error {
	path := "/etc/tor/torrc"
	lines := strings.Split(readTextFile(path), "\n")
	found := false
	prefix := key
	for i, line := range lines {
		trim := strings.TrimSpace(line)
		if strings.HasPrefix(trim, prefix) {
			if val == "" {
				lines[i] = "# " + trim + " # cleared by panel"
			} else {
				lines[i] = prefix + " " + val
			}
			found = true
			break
		}
	}
	if !found && val != "" {
		lines = append(lines, prefix+" "+val)
	}
	return writeTextFile(path, strings.Join(lines, "\n"))
}

func grepTorrcLine(key string) string {
	for _, line := range strings.Split(readTextFile("/etc/tor/torrc"), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, key) {
			return strings.TrimSpace(strings.TrimPrefix(line, key))
		}
	}
	return ""
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func countLines(path string) int {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	n := 0
	for _, line := range strings.Split(string(b), "\n") {
		if strings.TrimSpace(line) != "" && !strings.HasPrefix(strings.TrimSpace(line), "#") {
			n++
		}
	}
	return n
}

func readSplitRulesWithSeed(path, seedPath string) string {
	value := strings.TrimSpace(readTextFile(path))
	if value != "" {
		return value
	}
	return readTextFile(filepath.Join(olcRepoRoot(), seedPath))
}


func olcrtcSettingsPut(body map[string]any) error {
	if v, ok := body["jitsi_insecure_tls"].(bool); ok {
		val := "0"
		if v {
			val = "1"
		}
		if err := setPanelEnvKey("OLCRTC_JITSI_INSECURE_TLS", val); err != nil {
			return err
		}
	}
	if v, ok := body["public_url"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_PUBLIC_URL", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["warp_proxy"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_WARP_PROXY", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["socks_proxy"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_SOCKS_PROXY", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["default_carrier"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_DEFAULT_CARRIER", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["default_transport"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_DEFAULT_TRANSPORT", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["default_link"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_DEFAULT_LINK", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["tor_proxy"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_TOR_PROXY", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["webrtc_proxy"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_WEBRTC_PROXY", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	return nil
}

func componentSettingsPut(name string, body map[string]any) error {
	if name == "warp" {
		return warpSettingsPut(body)
	}
	if name == "olcrtc" {
		return olcrtcSettingsPut(body)
	}
	switch name {
	case "zapret":
		if v, ok := body["exclude_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/zapret-custom/exclude-domains.txt", v); err != nil {
				return err
			}
		}
		if v, ok := body["force_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/zapret-custom/force-domains.txt", v); err != nil {
				return err
			}
		}
		if v, ok := body["nfqws_config"].(string); ok {
			cfgPath := filepath.Join(olcRepoRoot(), "data/zapret-olcrtc.config")
			if err := writeTextFile(cfgPath, strings.TrimSpace(v)+"\n"); err != nil {
				return err
			}
		}
		if v, ok := body["strategy_id"].(string); ok && strings.TrimSpace(v) != "" {
			script := filepath.Join(olcRepoRoot(), "scripts/olc-zapret-apply-strategy.sh")
			if _, err := os.Stat(script); err == nil {
				go func(id string) {
					ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
					defer cancel()
					cmd := exec.CommandContext(ctx, "bash", script, strings.TrimSpace(id))
					cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
					_, _ = cmd.CombinedOutput()
				}(v)
			}
		}
		if v, ok := body["reinstall"].(bool); ok && v {
			script := filepath.Join(olcRepoRoot(), "scripts/olc-component-job.sh")
			if _, err := os.Stat(script); err == nil {
				go func() {
					ctx, cancel := context.WithTimeout(context.Background(), 20*time.Minute)
					defer cancel()
					cmd := exec.CommandContext(ctx, "bash", script, "zapret", "install")
					cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin", "OLCRTC_ZAPRET_REINSTALL=1")
					_, _ = cmd.CombinedOutput()
				}()
			}
		}
		if v, ok := body["auto_sync"].(bool); ok {
			const cronPath = "/etc/cron.d/olcrtc-zapret-sync"
			if v {
				cron := "10 4 * * 0 root /opt/Olc-cost-l/scripts/zapret-sync-excludes.sh --reload-zapret >>/var/log/olcrtc-zapret-sync.log 2>&1\n"
				if err := writeTextFile(cronPath, cron); err != nil {
					return err
				}
			} else {
				_ = os.Remove(cronPath)
			}
		}
		return nil

	case "warp":
		if v, ok := body["proxy"].(string); ok {
			if err := setPanelEnvKey("OLCRTC_WARP_PROXY", strings.TrimSpace(v)); err != nil {
				return err
			}
		}
		if v, ok := body["mode"].(string); ok {
			mv := strings.TrimSpace(v)
			if mv == "" {
				mv = "proxy"
			}
			if err := setPanelEnvKey("OLCRTC_WARP_MODE", mv); err != nil {
				return err
			}
		}
		if v, ok := body["autoconnect"].(bool); ok {
			val := "0"
			if v {
				val = "1"
			}
			if err := setPanelEnvKey("OLCRTC_WARP_AUTOCONNECT", val); err != nil {
				return err
			}
		}
		if v, ok := body["warp_plus"].(bool); ok {
			val := "0"
			if v {
				val = "1"
			}
			if err := setPanelEnvKey("OLCRTC_WARP_PLUS", val); err != nil {
				return err
			}
		}
		if v, ok := body["license_key"].(string); ok {
			if err := setPanelEnvKey("OLCRTC_WARP_LICENSE", strings.TrimSpace(v)); err != nil {
				return err
			}
		}
		return nil
	case "tor":
		if v, ok := body["strict_nodes"].(string); ok {
			_ = patchTorrcKey("StrictNodes", strings.TrimSpace(v))
		}
		if v, ok := body["socks_listen"].(string); ok {
			_ = patchTorrcKey("SocksPort", strings.TrimSpace(v))
		}
		if v, ok := body["exit_nodes"].(string); ok {
			if err := writeTextFile("/etc/olcrtc-manager/tor-exit.env", "OLCRTC_TOR_EXIT_NODES="+strings.TrimSpace(v)+"\n"); err != nil {
				return err
			}
		}
		if v, ok := body["exclude_exit_nodes"].(string); ok {
			if err := writeTextFile("/etc/olcrtc-manager/tor-exit-exclude.env", "OLCRTC_TOR_EXCLUDE_EXIT="+strings.TrimSpace(v)+"\n"); err != nil {
				return err
			}
		}
		return nil
	case "split":
		if v, ok := body["force_tor_domains"].(string); ok {
			_ = writeTextFile("/var/lib/olcrtc/force-tor-domains.txt", v)
		}
		if v, ok := body["blocked_tor_domains"].(string); ok {
			_ = writeTextFile("/var/lib/olcrtc/ru-blocked-tor-domains.txt", v)
		}
		if v, ok := body["custom_direct_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/lists/custom-direct-domains.txt", v); err != nil {
				return err
			}
		}
		if v, ok := body["panel_hosts"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/lists/panel-carrier-hosts.txt", v); err != nil {
				return err
			}
		}
		if v, ok := body["panel_cidrs"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/lists/panel-carrier-cidrs.txt", v); err != nil {
				return err
			}
		}
		if v, ok := body["cidr_only"].(bool); ok {
			val := "0"
			if v {
				val = "1"
			}
			_ = patchPanelEnvKey("OLCRTC_SPLIT_CIDR_ONLY", val)
		}
		if _, err := runSplitTool(context.Background(), []string{"rebuild"}, nil, time.Minute); err != nil {
			log.Printf("split rebuild after settings save: %v", err)
		}
		return nil
	case "bridges":

		if raw, ok := body["bridge_profiles"].(map[string]any); ok {
			cur := readBridgeProfiles()
			for k, v := range raw {
				if k == "system" {
					if sm, ok := v.(map[string]any); ok {
						if sys, ok := cur["system"].(map[string]any); ok {
							if t, ok := sm["types"].(string); ok {
								sys["types"] = t
							}
							if au, ok := sm["auto_update"].(bool); ok {
								sys["auto_update"] = au
								setBridgeAutoCron(au)
							}
							cur["system"] = sys
						}
					}
					continue
				}
				cur[k] = v
			}
			if ap, ok := body["active_profile"].(string); ok {
				cur["active_profile"] = ap
			}
			if err := writeBridgeProfiles(cur); err != nil {
				return err
			}
			return applyActiveBridgeProfile(cur)
		}
		if v, ok := body["custom_bridge"].(string); ok && strings.TrimSpace(v) != "" {
			line := strings.TrimSpace(v)
			if !strings.HasPrefix(line, "Bridge ") {
				line = "Bridge " + line
			}
			f, err := os.OpenFile("/etc/tor/bridges.conf", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
			if err != nil {
				return err
			}
			defer f.Close()
			_, err = fmt.Fprintf(f, "\n%s\n", line)
			return err
		}
		return nil
	default:
		return fmt.Errorf("unknown component %q", name)
	}
}

// component-settings-v3
// component-settings-v4
// component-settings-v5


func patchPanelEnvKey(key, val string) error {
	path := "/etc/olcrtc-manager/panel.env"
	lines := strings.Split(readTextFile(path), "\n")
	prefix := key + "="
	found := false
	for i, line := range lines {
		if strings.HasPrefix(strings.TrimSpace(line), prefix) {
			lines[i] = prefix + val
			found = true
			break
		}
	}
	if !found {
		lines = append(lines, prefix+val)
	}
	return writeTextFile(path, strings.Join(lines, "\n")+"\n")
}

func zapretStrategyState() (current string, presets []map[string]string) {
	current = strings.TrimSpace(readTextFile("/etc/olcrtc-manager/zapret.strategy"))
	if current == "" {
		if fileExists(filepath.Join(olcRepoRoot(), "data/zapret4rocket/config.default")) {
			current = "z4r-default"
		} else {
			current = "olcrtc-minimal"
		}
	}
	presets = []map[string]string{
		{"id": "olcrtc-minimal", "label": "Olc minimal (лёгкий)"},
		{"id": "z4r-default", "label": "zapret4rocket config.default"},
	}
	dir := filepath.Join(olcRepoRoot(), "data/zapret-strategies")
	if ents, err := os.ReadDir(dir); err == nil {
		for _, e := range ents {
			if e.IsDir() || !strings.HasSuffix(e.Name(), ".config") {
				continue
			}
			id := strings.TrimSuffix(e.Name(), ".config")
			presets = append(presets, map[string]string{"id": id, "label": "custom: " + id})
		}
	}
	return current, presets
}

func splitCidrOnlyEnabled() bool {
	env := readPanelEnvMap()
	if v := strings.TrimSpace(env["OLCRTC_SPLIT_CIDR_ONLY"]); v == "1" || strings.EqualFold(v, "true") {
		return true
	}
	cidr := env["OLCRTC_DIRECT_CIDRS"]
	return strings.Contains(cidr, "ru-cidrs") && !strings.Contains(cidr, "direct-all")
}


func splitSettingsActionHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	action := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/settings/split/"), "/")
	var body map[string]any
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&body)
	}
	if body == nil {
		body = map[string]any{}
	}
	switch action {
	case "analyze":
		target, _ := body["target"].(string)
		target = strings.TrimSpace(target)
		if target == "" {
			http.Error(w, "target is required", http.StatusBadRequest)
			return
		}
		out, err := runSplitTool(r.Context(), []string{"analyze", target}, nil, 25*time.Second)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, map[string]any{"status": "ok", "result": out})
	case "apply-analysis":
		out, err := runSplitTool(r.Context(), []string{"apply-analysis"}, body, 90*time.Second)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		componentSettingsAfterSave("zapret", map[string]any{})
		writeJSON(w, map[string]any{"status": "ok", "result": out, "settings": mustComponentSettings("split")})
	case "sync-config":
		out, err := runSplitTool(context.Background(), []string{"sync-config", "/etc/olcrtc-manager/config.json"}, nil, 2*time.Minute)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		componentSettingsAfterSave("zapret", map[string]any{})
		writeJSON(w, map[string]any{"status": "ok", "result": out, "settings": mustComponentSettings("split")})
	case "sync-logs":
		out, err := runSplitTool(r.Context(), []string{"sync-logs"}, nil, 90*time.Second)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		componentSettingsAfterSave("zapret", map[string]any{})
		writeJSON(w, map[string]any{"status": "ok", "result": out, "settings": mustComponentSettings("split")})
	case "apply-routing":
		applySplitRoutingToInstances("split apply-routing")
		writeJSON(w, map[string]any{"status": "ok", "routing_reloaded": splitRoutingReloadSupported(), "instances_restarted": !splitRoutingReloadSupported()})
	default:
		http.NotFound(w, r)
	}
}

func mustComponentSettings(name string) map[string]any {
	out, err := componentSettingsGet(name)
	if err != nil {
		return map[string]any{"error": err.Error()}
	}
	return out
}

func splitRoutingReloadSupported() bool {
	_, err := os.Stat("/var/lib/olcrtc/.split-routing-reload")
	return err == nil
}

func applySplitRoutingToInstances(reason string) {
	if panelSupervisor == nil {
		return
	}
	splitReloadMu.Lock()
	if time.Since(splitReloadLast) < 10*time.Second {
		splitReloadMu.Unlock()
		log.Printf("split: routing reload debounced (%s)", reason)
		return
	}
	splitReloadLast = time.Now()
	splitReloadMu.Unlock()
	useReload := splitRoutingReloadSupported()
	go func() {
		panelSupervisor.mu.RLock()
		procs := make([]*process, 0, len(panelSupervisor.processes))
		for _, p := range panelSupervisor.processes {
			procs = append(procs, p)
		}
		panelSupervisor.mu.RUnlock()
		if len(procs) == 0 {
			return
		}
		if useReload {
			n := 0
			for _, p := range procs {
				if p == nil || p.cmd == nil || p.cmd.Process == nil {
					continue
				}
				if err := p.cmd.Process.Signal(syscall.SIGUSR1); err == nil {
					n++
				} else {
					log.Printf("split reload signal %s/%s: %v", p.location.ClientID, p.location.Endpoint.RoomID, err)
				}
			}
			log.Printf("split: routing reload (SIGUSR1) sent to %d instance(s) (%s)", n, reason)
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
		defer cancel()
		for _, p := range procs {
			if p == nil {
				continue
			}
			if err := panelSupervisor.Restart(ctx, p.location.ClientID, p.location.Endpoint.RoomID, p.location.Transport.Type); err != nil {
				log.Printf("split restart %s/%s: %v", p.location.ClientID, p.location.Endpoint.RoomID, err)
			}
		}
		log.Printf("split: restarted %d running instance(s) (%s)", len(procs), reason)
	}()
}

func componentSettingsAfterSave(name string, body map[string]any) {
	repo := olcRepoRoot()
	switch name {
	case "zapret":
		script := filepath.Join(repo, "scripts/zapret-sync-excludes.sh")
		if _, err := os.Stat(script); err == nil {
			go func() {
				ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
				defer cancel()
				cmd := exec.CommandContext(ctx, "bash", script, "--reload-zapret")
				cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
				_, _ = cmd.CombinedOutput()
			}()
		}
	case "split":
		if v, ok := body["refresh_lists"].(bool); ok && v {
			script := filepath.Join(repo, "scripts/setup-split-ru.sh")
			go func() {
				ctx, cancel := context.WithTimeout(context.Background(), 15*time.Minute)
				defer cancel()
				cmd := exec.CommandContext(ctx, "bash", script)
				cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
				_, _ = cmd.CombinedOutput()
			}()
		}
	case "tor":
		if v, ok := body["exit_nodes"].(string); ok {
			_ = writeTextFile("/etc/olcrtc-manager/tor-exit.env", "OLCRTC_TOR_EXIT_NODES="+strings.TrimSpace(v)+"\n")
			script := filepath.Join(repo, "scripts/configure-tor-exit.sh")
			if _, err := os.Stat(script); err == nil {
				go func() {
					ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
					defer cancel()
					cmd := exec.CommandContext(ctx, "bash", "-c", "set -a; source /etc/olcrtc-manager/tor-exit.env 2>/dev/null; source /etc/olcrtc-manager/tor-exit-exclude.env 2>/dev/null; set +a; bash "+script)
					cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
					_, _ = cmd.CombinedOutput()
				}()
			}
		}
	}
}

func componentSettingsHandler() http.HandlerFunc {
	allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true, "olcrtc": true, "warp": true}
	return func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(r.URL.Path, "/api/settings/")
		name = strings.TrimSpace(strings.Trim(name, "/"))
		if !allowed[name] {
			http.Error(w, "unknown component", http.StatusBadRequest)
			return
		}
		switch r.Method {
		case http.MethodGet:
			out, err := componentSettingsGet(name)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, map[string]any{"component": name, "settings": out})
		case http.MethodPut:
			var body map[string]any
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			if name == "bridges" {
				if action, ok := body["action"].(string); ok && action == "refresh_pool" {
					types := "obfs4,webtunnel"
					if v, ok := body["types"].(string); ok && strings.TrimSpace(v) != "" {
						types = strings.TrimSpace(v)
					}
					runBridgePoolRefresh(types)
					writeJSON(w, map[string]any{"status": "ok", "pool_job": readBridgePoolStatus()})
					return
				}
			}
			if err := componentSettingsPut(name, body); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			componentSettingsAfterSave(name, body)
			writeJSON(w, map[string]string{"status": "ok"})
		default:
			w.Header().Set("Allow", "GET, PUT")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}
}


func capabilitiesHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		flags := loadFeatureFlagsMap()
		ver := readVersionJSON()
		profile := readDeployProfileID()
		type comp struct {
			Installed    bool     `json:"installed"`
			Enabled      bool     `json:"enabled"`
			Configurable bool     `json:"configurable"`
			Label        string   `json:"label,omitempty"`
			Requires     []string `json:"requires,omitempty"`
		}
		components := map[string]comp{
			"zapret": {
				Installed: componentInstalled("zapret"), Enabled: flags["zapret"],
				Configurable: componentInstalled("zapret"), Label: "Zapret",
			},
			"tor": {
				Installed: componentInstalled("tor"), Enabled: flags["tor"],
				Configurable: componentInstalled("tor"), Label: "Tor",
			},
			"split": {
				Installed: componentInstalled("split"), Enabled: flags["split"],
				Configurable: componentInstalled("split"), Label: "Split",
				Requires: []string{"tor"},
			},
			"bridges": {
				Installed: componentInstalled("bridges"), Enabled: flags["webtunnel"],
				Configurable: componentInstalled("tor"), Label: "Мосты", Requires: []string{"tor"},
			},
			"warp": {
				Installed: componentInstalled("warp"), Enabled: flags["warp"],
				Configurable: componentInstalled("warp"), Label: "WARP",
			},
		}
		writeJSON(w, map[string]any{
			"panel_version":  ver["panel"],
			"channel":        ver["channel"],
			"deploy_profile": profile,
			"components":     components,
		})
	}
}



func featuresToggleSucceeded(name string, wantEnabled bool, scriptErr error, output string) bool {
	if scriptErr == nil {
		return true
	}
	flags := readFeatureFlags()
	if flags[name] == wantEnabled {
		return true
	}
	msg := scriptErr.Error() + " " + output
	if strings.Contains(msg, "signal: terminated") && flags[name] == wantEnabled {
		return true
	}
	if name == "split" && wantEnabled && flags["split"] {
		return true
	}
	if name == "tor" && !wantEnabled && !flags["tor"] {
		return true
	}
	if name == "warp" && wantEnabled && flags["warp"] {
		return true
	}
	return false
}


func featureLogPaths(name string) []string {
	switch name {
	case "zapret":
		return []string{
			"/var/log/olcrtc-zapret-sync.log",
			"/var/log/olcrtc-component-zapret-install.log",
			"/var/log/olcrtc-component-zapret-uninstall.log",
		}
	case "tor":
		return []string{"/var/log/olcrtc-healthcheck.log", "/var/log/tor/log"}
	case "split":
		return []string{
			"/var/log/olcrtc-zapret-sync.log",
			"/var/log/olcrtc-healthcheck.log",
			"/var/log/olcrtc-component-split-install.log",
			"/var/log/olcrtc-component-split-uninstall.log",
		}
	case "webtunnel":
		return []string{
			"/var/log/olcrtc-bridge-pool.log",
			"/var/log/olcrtc-bridge-monitor.log",
			"/var/log/olcrtc-component-bridges-install.log",
			"/var/log/olcrtc-component-bridges-uninstall.log",
		}
	case "warp":
		return []string{
			"/var/log/olcrtc-warp-install.log",
			"/var/log/olcrtc-component-warp-install.log",
			"/var/log/olcrtc-component-warp-uninstall.log",
		}
	case "olcrtc":
		return []string{
			"/var/log/olcrtc-healthcheck.log",
			"/var/log/olcrtc-panel-update.log",
			"/var/log/olcrtc-feature-restart.log",
		}
	default:
		return nil
	}
}


func tailJournalUnit(unit string, maxLines int) ([]string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "journalctl", "-u", unit, "-n", fmt.Sprintf("%d", maxLines), "--no-pager", "-o", "cat")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return nil, err
	}
	text := strings.TrimSpace(string(out))
	if text == "" {
		return nil, fmt.Errorf("empty journal")
	}
	lines := strings.Split(text, "\n")
	if len(lines) > maxLines {
		lines = lines[len(lines)-maxLines:]
	}
	return lines, nil
}

func tailFileLines(path string, maxLines int) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var lines []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
		if len(lines) > maxLines*2 {
			lines = lines[len(lines)-maxLines:]
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if len(lines) > maxLines {
		lines = lines[len(lines)-maxLines:]
	}
	return lines, nil
}

func featuresLogsHandler() func(w http.ResponseWriter, r *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		name := strings.TrimPrefix(r.URL.Path, "/api/features/logs/")
		name = strings.TrimSpace(strings.Trim(name, "/"))
		allowed := false
		for _, n := range featureNames {
			if n == name {
				allowed = true
				break
			}
		}
		if !allowed && (name == "olcrtc" || name == "warp") {
			allowed = true
		}
		if !allowed && name == "olcrtc" {
			allowed = true
		}
		if !allowed {
			http.Error(w, "unknown feature", http.StatusBadRequest)
			return
		}
		var usedPath string
		var lines []string
		for _, path := range featureLogPaths(name) {
			if st, err := os.Stat(path); err != nil || st.Size() == 0 {
				continue
			}
			got, err := tailFileLines(path, 200)
			if err != nil || len(got) == 0 {
				continue
			}
			usedPath = path
			lines = got
			break
		}
		if lines == nil {
			paths := featureLogPaths(name)
			msg := fmt.Sprintf("(log file not found for %s — tried: %s)", name, strings.Join(paths, ", "))
			if len(paths) == 0 {
				msg = fmt.Sprintf("(no log paths configured for %s)", name)
			}
			lines = []string{msg}
		}
		writeJSON(w, map[string]any{"feature": name, "path": usedPath, "lines": lines})
	}
}

func featuresListHandler() func(w http.ResponseWriter, r *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		writeJSON(w, map[string]any{
			"flags":  readFeatureFlags(),
			"live":   featureLiveStatus(),
			"script": featureScriptPath(),
		})
	}
}

func featuresToggleHandler() func(w http.ResponseWriter, r *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		name := strings.TrimPrefix(r.URL.Path, "/api/features/")
		name = strings.TrimSpace(name)
		allowed := false
		for _, n := range featureNames {
			if n == name {
				allowed = true
				break
			}
		}
		if !allowed {
			http.Error(w, "unknown feature", http.StatusBadRequest)
			return
		}
		var body struct {
			Enabled bool `json:"enabled"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "invalid json body: "+err.Error(), http.StatusBadRequest)
			return
		}
		script := featureScriptPath()
		if script == "" {
			http.Error(w, "olc-feature.sh not installed", http.StatusServiceUnavailable)
			return
		}
		arg := "off"
		if body.Enabled {
			arg = "on"
		}
		if name == "webtunnel" && body.Enabled {
			flagsNow := readFeatureFlags()
			if !flagsNow["tor"] {
				http.Error(w, "bridges require tor enabled", http.StatusBadRequest)
				return
			}
		}
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Minute)
		defer cancel()
		cmd := exec.CommandContext(ctx, "bash", script, name, arg)
		cmd.Env = append(os.Environ(),
			"PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin",
			"OLC_FEATURE_NO_MANAGER_RESTART=0",
		)
		out, err := cmd.CombinedOutput()
		result := map[string]any{
			"feature": name,
			"enabled": body.Enabled,
			"output":  string(out),
			"flags":   readFeatureFlags(),
		}
		if err != nil {
			result["error"] = err.Error()
			if !featuresToggleSucceeded(name, body.Enabled, err, string(out)) {
				w.WriteHeader(http.StatusInternalServerError)
			} else {
				result["warning"] = "toggle applied; manager may restart in a few seconds"
			}
		}
		writeJSON(w, result)
	}
}

func countPatchScripts(repo string) int {
	n := 0
	dir := filepath.Join(repo, "scripts")
	ents, err := os.ReadDir(dir)
	if err != nil {
		return 0
	}
	for _, e := range ents {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if strings.HasPrefix(name, "patch-olcrtc") && strings.HasSuffix(name, ".sh") {
			n++
		}
	}
	return n
}

func readPins(repo string) map[string]any {
	out := map[string]any{}
	path := filepath.Join(repo, "data/upstream-pins.json")
	b, err := os.ReadFile(path)
	if err != nil {
		return out
	}
	_ = json.Unmarshal(b, &out)
	return out
}

func notificationStats() map[string]any {
	st := map[string]any{"total": 0, "unread": 0, "errors": 0, "warnings": 0}
	var list []map[string]any
	if readJSONFile(panelNotifFile, &list) {
		st["total"] = len(list)
		for _, n := range list {
			if read, ok := n["read"].(bool); ok && !read {
				st["unread"] = st["unread"].(int) + 1
			}
			switch n["severity"] {
			case "error":
				st["errors"] = st["errors"].(int) + 1
			case "warning":
				st["warnings"] = st["warnings"].(int) + 1
			}
		}
	}
	return st
}



func displayFeatureFlags() map[string]bool {
	raw := readFeatureFlags()
	out := map[string]bool{
		"zapret":  raw["zapret"],
		"tor":     raw["tor"],
		"split":   raw["split"],
		"bridges": raw["webtunnel"],
		"warp":    raw["warp"],
		"olcrtc":  raw["olcrtc"],
	}
	return out
}

func componentStackStatus() map[string]any {
	flags := readFeatureFlags()
	installed := map[string]bool{
		"zapret":  componentInstalled("zapret"),
		"tor":     componentInstalled("tor"),
		"split":   componentInstalled("split"),
		"bridges": componentInstalled("bridges"),
	}
	labels := map[string]string{
		"zapret": "Zapret", "tor": "Tor", "split": "Split", "bridges": "Мосты",
	}
	optional := []string{"warp"}
	on := 0
	total := 0
	items := []map[string]any{}
	for _, id := range []string{"zapret", "tor", "split", "bridges"} {
		total++
		enabled := flags[id]
		if id == "bridges" {
			enabled = flags["webtunnel"]
		}
		if enabled {
			on++
		}
		items = append(items, map[string]any{
			"id": id, "label": labels[id], "enabled": enabled, "installed": installed[id],
		})
	}
	for _, id := range optional {
		items = append(items, map[string]any{
			"id": id, "label": "WARP", "enabled": flags[id], "installed": componentInstalled("warp"), "optional": true,
		})
	}
	return map[string]any{
		"enabled": on, "total": total, "items": items,
		"note": "Сервисы стека Olc-cost-l (Zapret, Tor, Split, Мосты). WARP — опционально.",
	}
}

func projectStatusHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	repo := olcRepoRoot()
	upd := computeUpdateStatus(repo)
	local, _ := upd["local_sha"].(string)
	remote, _ := upd["remote_sha"].(string)
	ver := readVersionJSON()
	stackManifest, _ := ver["stack"].(map[string]any)
	pins := readPins(repo)
	notif := notificationStats()
	locked := panelUpdateLocked()
	var updateJob map[string]any
	readJSONFile(panelUpdateStatus, &updateJob)

	stack := componentStackStatus()
	patchTotal := countPatchScripts(repo)
	patchApplied := patchTotal
	if _, err := os.Stat("/usr/local/bin/olcrtc-manager"); err != nil {
		patchApplied = 0
	}

	writeJSON(w, map[string]any{
		"panel_version":   ver["panel"],
		"channel":         ver["channel"],
		"stack_manifest":  stackManifest,
		"repo_path":       repo,
		"local_sha":       local,
		"remote_sha":      remote,
		"update_available":   upd["update_available"],
		"update_source":      upd["update_source"],
		"git_behind":         upd["git_behind"],
		"git_ahead":          upd["git_ahead"],
		"installed_release_tag": upd["installed_release_tag"],
		"latest_release_tag": upd["latest_release_tag"],
		"latest_release_name": upd["latest_release_name"],
		"update_locked":   locked,
		"update_job":      updateJob,
		"deploy_profile":  readDeployProfileID(),
		"stack": stack,
		"patches": map[string]any{
			"total_scripts":    patchTotal,
			"applied_estimate": patchApplied,
			"enabled":          stack["enabled"],
			"total":            stack["total"],
			"items":            stack["items"],
		},
		"upstream_pins": pins,
		"capabilities": map[string]any{
			"components": map[string]bool{
				"zapret":  componentInstalled("zapret"),
				"tor":     componentInstalled("tor"),
				"split":   componentInstalled("split"),
				"bridges": componentInstalled("bridges"),
			},
			"flags": displayFeatureFlags(),
		},
		"notifications": notif,
		"manager": map[string]any{
			"pid": os.Getpid(),
		},
	})
}

const notificationSettingsPath = "/etc/olcrtc-manager/notification-settings.json"

func defaultNotificationSettings() map[string]any {
	return map[string]any{
		"enabled":           true,
		"scan_interval_sec": 60,
		"min_severity":      "warning",
		"show_toast":        true,
		"sources": map[string]bool{
			"instance": true,
			"olcrtc":   true,
			"tor":      true,
			"zapret":   true,
			"panel":    true,
			"split":    true,
		},
	}
}

func readNotificationSettings() map[string]any {
	out := defaultNotificationSettings()
	var stored map[string]any
	if readJSONFile(notificationSettingsPath, &stored) {
		for k, v := range stored {
			out[k] = v
		}
	}
	return out
}

func notificationSettingsHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, map[string]any{"settings": readNotificationSettings()})
	case http.MethodPut:
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		cur := readNotificationSettings()
		for k, v := range body {
			cur[k] = v
		}
		b, _ := json.MarshalIndent(cur, "", "  ")
		if err := os.WriteFile(notificationSettingsPath, b, 0644); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, map[string]any{"status": "ok", "settings": cur})
	default:
		w.Header().Set("Allow", "GET, PUT")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

const instanceDefaultsPath = "/var/lib/olcrtc/instance-defaults.json"

func readInstanceDefaults() map[string]any {
	out := map[string]any{
		"schema":     1,
		"globalPort": "",
		"carriers":   map[string]any{},
	}
	var stored map[string]any
	if readJSONFile(instanceDefaultsPath, &stored) {
		for k, v := range stored {
			out[k] = v
		}
	}
	return out
}

func instanceDefaultsHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, map[string]any{"defaults": readInstanceDefaults()})
	case http.MethodPut:
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		payload := body
		if nested, ok := body["defaults"].(map[string]any); ok {
			payload = nested
		}
		if err := os.MkdirAll(filepath.Dir(instanceDefaultsPath), 0755); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		b, err := json.MarshalIndent(payload, "", "  ")
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := os.WriteFile(instanceDefaultsPath, b, 0644); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, map[string]any{"status": "ok", "defaults": payload})
	default:
		w.Header().Set("Allow", "GET, PUT")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

// panelBackendV4 — updates, notifications, jobs, component install
const (
	panelUpdateLock  = "/var/lib/olcrtc/panel-update.lock"
	panelUpdateStatus = "/var/lib/olcrtc/panel-update-status.json"
	panelJobsDir     = "/var/lib/olcrtc/panel-jobs"
	panelNotifFile   = "/var/lib/olcrtc/notifications.json"
	bridgeProfilesPath = "/var/lib/olcrtc/bridge-profiles.json"
	bridgeCronPath     = "/etc/cron.d/olcrtc-bridge-pool"
	bridgePoolStatusFile = "/var/lib/olcrtc/bridge-pool-status.json"
)

func panelUpdateLocked() bool {
	b, err := os.ReadFile(panelUpdateLock)
	if err != nil {
		return false
	}
	p, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil || p <= 0 {
		return false
	}
	proc, err := os.FindProcess(p)
	if err != nil {
		return false
	}
	return proc.Signal(syscall.Signal(0)) == nil
}

func olcRepoRoot() string {
	for _, p := range []string{"/opt/Olc-cost-l", "/opt/olcrtc"} {
		if _, err := os.Stat(filepath.Join(p, "scripts/apply-olcrtc-patches.sh")); err == nil {
			return p
		}
	}
	return "/opt/Olc-cost-l"
}

func runGitShort(repo string, args ...string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	gitArgs := []string{"-c", "safe.directory=" + repo, "-C", repo}
	gitArgs = append(gitArgs, args...)
	cmd := exec.CommandContext(ctx, "git", gitArgs...)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func readJSONFile(path string, dest any) bool {
	b, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return json.Unmarshal(b, dest) == nil
}

func updatesCheckHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	repo := olcRepoRoot()
	st := computeUpdateStatus(repo)
	st["available"] = st["update_available"]
	st["locked"] = panelUpdateLocked()
	writeJSON(w, st)
}

func updatesStatusHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	out := map[string]any{"locked": panelUpdateLocked()}
	var st map[string]any
	if readJSONFile(panelUpdateStatus, &st) {
		out["job"] = st
	}
	writeJSON(w, out)
}


func updateGuardMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		next.ServeHTTP(w, r)
	})
}

func updatesRunHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if panelUpdateLocked() {
		http.Error(w, "update already running", http.StatusConflict)
		return
	}
	script := filepath.Join(olcRepoRoot(), "scripts/olc-panel-update-run.sh")
	if _, err := os.Stat(script); err != nil {
		http.Error(w, "update script missing", http.StatusServiceUnavailable)
		return
	}
	jobID := fmt.Sprintf("update-%d", time.Now().Unix())
	cmd := exec.Command("bash", script, jobID)
	cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
	if err := cmd.Start(); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, map[string]any{"job_id": jobID, "status": "running", "log_path": "/var/log/olcrtc-panel-update.log"})
}

func panelJobsHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rest := strings.TrimPrefix(r.URL.Path, "/api/jobs/")
		rest = strings.Trim(rest, "/")
		parts := strings.Split(rest, "/")
		if len(parts) == 0 || parts[0] == "" {
			http.NotFound(w, r)
			return
		}
		jobID := parts[0]
		path := filepath.Join(panelJobsDir, jobID+".json")
		if r.Method == http.MethodGet && len(parts) == 1 {
			var st map[string]any
			if readJSONFile(path, &st) {
				writeJSON(w, st)
				return
			}
			if readJSONFile(panelUpdateStatus, &st) && st["job_id"] == jobID {
				writeJSON(w, st)
				return
			}
			http.NotFound(w, r)
			return
		}
		if r.Method == http.MethodGet && len(parts) == 2 && parts[1] == "log" {
			logPath := "/var/log/olcrtc-panel-update.log"
			var st map[string]any
			if readJSONFile(path, &st) {
				if lp, ok := st["log_path"].(string); ok && lp != "" {
					logPath = lp
				}
			}
			b, err := os.ReadFile(logPath)
			if err != nil {
				http.Error(w, err.Error(), http.StatusNotFound)
				return
			}
			lines := strings.Split(string(b), "\n")
			if len(lines) > 500 {
				lines = lines[len(lines)-500:]
			}
			writeJSON(w, map[string]any{"lines": lines})
			return
		}
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}




func fileContainsDoneMarker(path string) bool {
	b, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return strings.Contains(string(b), "=== done ===")
}

func componentJobStale(st map[string]any, mod time.Time) bool {
	status, _ := st["status"].(string)
	if status != "done" && status != "failed" {
		return false
	}
	if raw, ok := st["finished_at"].(string); ok && raw != "" {
		if ts, err := time.Parse(time.RFC3339, raw); err == nil {
			return time.Since(ts) > 3*time.Minute
		}
	}
	return time.Since(mod) > 3*time.Minute
}

func componentsJobsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	componentFilter := strings.TrimSpace(r.URL.Query().Get("component"))
	type item struct {
		mod time.Time
		st  map[string]any
	}
	glob := filepath.Join(panelJobsDir, "*.json")
	files, _ := filepath.Glob(glob)
	out := []item{}
	for _, p := range files {
		info, err := os.Stat(p)
		if err != nil || info.IsDir() {
			continue
		}
		var st map[string]any
		if !readJSONFile(p, &st) {
			continue
		}
		if typ, _ := st["type"].(string); typ != "component" {
			continue
		}
		if componentFilter != "" {
			if c, _ := st["component"].(string); c != componentFilter {
				continue
			}
		}
		if _, ok := st["job_id"]; !ok {
			st["job_id"] = strings.TrimSuffix(filepath.Base(p), ".json")
		}
		if componentJobStale(st, info.ModTime()) {
			continue
		}
		if status, _ := st["status"].(string); status == "failed" {
			logPath, _ := st["log_path"].(string)
			if logPath != "" && fileContainsDoneMarker(logPath) {
				st["status"] = "done"
				st["exit_code"] = 0
				st["error"] = ""
				status = "done"
			}
		}
		if status, _ := st["status"].(string); (status == "done" || status == "failed") && st["finished_at"] == nil {
			st["finished_at"] = info.ModTime().Format(time.RFC3339)
		}
		out = append(out, item{mod: info.ModTime(), st: st})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].mod.After(out[j].mod) })
	jobs := make([]map[string]any, 0, len(out))
	for _, it := range out {
		jobs = append(jobs, it.st)
	}
	writeJSON(w, map[string]any{"jobs": jobs})
}

func notificationsListHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var list []map[string]any
	if !readJSONFile(panelNotifFile, &list) {
		list = []map[string]any{}
	}
	unread := 0
	for _, n := range list {
		if read, ok := n["read"].(bool); ok && !read {
			unread++
		}
	}
	writeJSON(w, map[string]any{"notifications": list, "unread": unread})
}

func notificationsScanHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	script := filepath.Join(olcRepoRoot(), "scripts/olc-error-scan.sh")
	ctx, cancel := context.WithTimeout(r.Context(), 90*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "bash", script)
	cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
	_ = cmd.Run()
	var list []map[string]any
	if !readJSONFile(panelNotifFile, &list) {
		list = []map[string]any{}
	}
	writeJSON(w, map[string]any{"notifications": list, "scanned": true})
}

func notificationsPatchHandler(w http.ResponseWriter, r *http.Request) {
	id := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/notifications/"), "/")
	if id == "" || id == "scan" {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodPatch && r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var body struct {
		Read     *bool `json:"read"`
		Dismiss  bool  `json:"dismiss"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	var list []map[string]any
	if !readJSONFile(panelNotifFile, &list) {
		list = []map[string]any{}
	}
	statePath := "/var/lib/olcrtc/notifications-state.json"
	var state map[string]any
	readJSONFile(statePath, &state)
	if state == nil {
		state = map[string]any{"seen": map[string]any{}, "dismissed": []any{}}
	}
	dismissed, _ := state["dismissed"].([]any)
	for i, n := range list {
		if n["id"] == id {
			if body.Read != nil {
				list[i]["read"] = *body.Read
			}
			if body.Dismiss {
				if cid, ok := n["catalog_id"].(string); ok {
					dismissed = append(dismissed, cid)
				}
				list = append(list[:i], list[i+1:]...)
			}
			break
		}
	}
	state["dismissed"] = dismissed
	b, _ := json.Marshal(list)
	_ = os.WriteFile(panelNotifFile, b, 0644)
	sb, _ := json.Marshal(state)
	_ = os.WriteFile(statePath, sb, 0644)
	writeJSON(w, map[string]string{"status": "ok"})
}

func componentsActionHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if panelUpdateLocked() {
		http.Error(w, "panel update in progress", http.StatusConflict)
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/api/components/")
	parts := strings.Split(strings.Trim(rest, "/"), "/")
	if len(parts) < 2 {
		http.Error(w, "expected /api/components/{name}/{install|uninstall}", http.StatusBadRequest)
		return
	}
	name, action := parts[0], parts[1]
	allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true, "olcrtc": true, "warp": true}
	if !allowed[name] || (action != "install" && action != "uninstall") {
		http.Error(w, "unknown component or action", http.StatusBadRequest)
		return
	}
	script := filepath.Join(olcRepoRoot(), "scripts/olc-component-job.sh")
	jobID := fmt.Sprintf("%s-%s-%d", name, action, time.Now().Unix())
	cmd := exec.Command("bash", script, name, action, jobID)
	cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
	if err := cmd.Start(); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, map[string]any{
		"job_id": jobID, "component": name, "action": action, "status": "running",
		"log_path": fmt.Sprintf("/var/log/olcrtc-component-%s-%s.log", name, action),
	})
}


/* olc-jitsi-preflight-v1 */
/* olc-jitsi-preflight-v2 */
/* olc-jitsi-preflight-v3 */
/* olc-jitsi-preflight-v4 */
type jitsiPreflightResponse struct {
	OK      bool     `json:"ok"`
	Code    string   `json:"code"`
	Summary string   `json:"summary"`
	Details []string `json:"details"`
	Host    string   `json:"host,omitempty"`
	Room    string   `json:"room,omitempty"`
	WSURL   string   `json:"ws_url,omitempty"`
	WSCode  int      `json:"ws_status,omitempty"`
	BOSHURL string   `json:"bosh_url,omitempty"`
	BOSHCode int     `json:"bosh_status,omitempty"`
	BridgePostJoinRisk bool   `json:"bridge_postjoin_risk,omitempty"`
	BridgePostJoinNote string `json:"bridge_postjoin_note,omitempty"`
}

func jitsiPreflightHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	roomID := strings.TrimSpace(r.URL.Query().Get("room_id"))
	writeJSON(w, preflightJitsiRoom(roomID))
}

func preflightJitsiRoom(roomID string) jitsiPreflightResponse {
	out := jitsiPreflightResponse{
		OK:      false,
		Code:    "invalid",
		Summary: "Некорректный room id",
		Details: []string{"Укажите ссылку вида https://host/room"},
	}
	raw := strings.TrimSpace(roomID)
	if raw == "" {
		return out
	}
	if !strings.Contains(raw, "://") {
		raw = "https://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil || strings.TrimSpace(u.Host) == "" {
		out.Details = []string{"Не удалось разобрать URL комнаты"}
		return out
	}
	room := strings.Trim(strings.TrimSpace(u.Path), "/")
	if room == "" {
		out.Code = "invalid-room"
		out.Summary = "Для Jitsi нужен URL с названием комнаты"
		out.Details = []string{"Пример: https://meet.example.org/my-room"}
		return out
	}
	out.Host = u.Host
	out.Room = room
	hostOnly := u.Hostname()
	if ip := net.ParseIP(hostOnly); ip != nil {
		out.BridgePostJoinRisk = true
		out.BridgePostJoinNote = "IP-хост: после join обязательно проверьте bridge websocket в runtime-логе"
	}

	tr := &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}
	client := &http.Client{Timeout: 10 * time.Second, Transport: tr}
	base := u.Scheme + "://" + u.Host

	configJS := ""
	if resp, e := client.Get(base + "/config.js"); e == nil {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 512*1024))
		_ = resp.Body.Close()
		configJS = string(b)
	}
	resolve := func(v string) string {
		v = strings.TrimSpace(v)
		switch {
		case v == "":
			return ""
		case strings.HasPrefix(v, "http://") || strings.HasPrefix(v, "https://") || strings.HasPrefix(v, "ws://") || strings.HasPrefix(v, "wss://"):
			return v
		case strings.HasPrefix(v, "//"):
			return "https:" + v
		case strings.HasPrefix(v, "/"):
			return base + v
		default:
			return base + "/" + strings.TrimPrefix(v, "/")
		}
	}
	reWS := regexp.MustCompile(`websocket:\s*['"]([^'"]+)['"]`)
	altWS := ""
	if m := reWS.FindStringSubmatch(configJS); len(m) == 2 {
		altWS = resolve(m[1])
	}
	mainWS := base + "/xmpp-websocket"
	reBOSH := regexp.MustCompile(`bosh:\s*['"]([^'"]+)['"]`)
	boshURL := base + "/http-bind"
	if m := reBOSH.FindStringSubmatch(configJS); len(m) == 2 {
		boshURL = resolve(m[1])
	}

	out.WSURL = mainWS
	if altWS != "" && altWS != mainWS {
		out.WSURL = mainWS + " | alt: " + altWS
	}
	out.BOSHURL = boshURL

	probe := func(target string, ws bool) int {
		req, _ := http.NewRequest(http.MethodGet, target, nil)
		if ws {
			req.Header.Set("Connection", "Upgrade")
			req.Header.Set("Upgrade", "websocket")
			req.Header.Set("Sec-WebSocket-Version", "13")
			req.Header.Set("Sec-WebSocket-Key", "SGVsbG9Xb3JsZDEyMzQ=")
		}
		resp, e := client.Do(req)
		if e != nil {
			return 0
		}
		_ = resp.Body.Close()
		return resp.StatusCode
	}

	mainWSCode := probe(mainWS, true)
	altWSCode := 0
	if altWS != "" && altWS != mainWS {
		altWSCode = probe(altWS, true)
	}
	boshCode := probe(boshURL, false)
	out.WSCode = mainWSCode
	out.BOSHCode = boshCode

	if mainWSCode == 404 {
		if altWSCode == 101 || altWSCode == 200 || altWSCode == 426 {
			out.OK = true
			out.Code = "ok-alt-websocket"
			out.Summary = "Стандартный /xmpp-websocket не отвечает, но альтернативный endpoint живой"
			out.Details = []string{fmt.Sprintf("/xmpp-websocket=%d, alt=%d", mainWSCode, altWSCode)}
			return out
		}
		out.Code = "jitsi-websocket-404"
		out.Summary = "Jitsi WebSocket endpoint не найден (404)"
		out.Details = []string{
			fmt.Sprintf("/xmpp-websocket=%d", mainWSCode),
			"Для этого хоста runtime join обычно падает на xmpp dial / websocket handshake",
		}
		return out
	}

	// Important: many self-hosted Jitsi return 501 on websocket upgrade,
	// but still support BOSH (/http-bind) and can work in runtime.
	if mainWSCode == 501 && boshCode == 200 {
		out.OK = true
		out.Code = "ok-bosh-only"
		out.Summary = "WebSocket upgrade (501), но BOSH доступен — хост потенциально рабочий"
		out.Details = []string{
			fmt.Sprintf("/xmpp-websocket=%d, bosh=%d", mainWSCode, boshCode),
			"Проверяйте финальный статус по runtime-логу (join/token/jingle), а не только по preflight",
		}
		return out
	}

	if mainWSCode == 101 || mainWSCode == 200 || mainWSCode == 426 {
		out.OK = true
		out.Code = "ok"
		out.Summary = "Базовая Jitsi-проверка пройдена"
		out.Details = []string{fmt.Sprintf("/xmpp-websocket=%d, bosh=%d", mainWSCode, boshCode)}
		if out.BridgePostJoinRisk || mainWSCode == 200 {
			out.BridgePostJoinRisk = true
			if out.BridgePostJoinNote == "" {
				out.BridgePostJoinNote = "Проверяйте post-join в runtime: bridge websocket должен дать HTTP 101 (а не 200)"
			}
			out.Details = append(out.Details, "Bridge WS compatibility: ориентир в runtime - \"bridge open\" / \"Link connected\"")
		}
		return out
	}

	out.OK = true
	out.Code = "weak-signal"
	out.Summary = "Предпроверка не нашла явного блокера, но результат не окончательный"
	out.Details = []string{
		fmt.Sprintf("/xmpp-websocket=%d, bosh=%d", mainWSCode, boshCode),
		"Финальный статус определяется runtime-логом jitsi join",
		"Bridge WS compatibility (post-join): ошибка \"expected 101 but got 200\" = инстанс нерабочий",
	}
	if out.BridgePostJoinNote == "" {
		out.BridgePostJoinRisk = true
		out.BridgePostJoinNote = "Проверьте post-join runtime-лог: при проблеме будет \"expected handshake response status code 101 but got 200\""
	}
	return out
}

