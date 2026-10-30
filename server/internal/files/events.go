package files

import (
	"context"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"
)

// The apps keep one Server-Sent Events stream open. It carries
//   hello   {id}                       right after connecting
//   ping    {t}                        every 10 s (the app notices a dead link)
//   change  {dir}                      a watched folder changed (by anyone)
//   job     {…}                        server copy/move progress
//   disks   null                       a disk was plugged in / removed / ejected
//   sessions null                      a device logged in or out
//   revoked null                       this device's login was removed

type client struct {
	id      string
	session string
	ch      chan []byte
	done    chan struct{}
	mu      sync.Mutex
	watch   map[string]bool
}

type hub struct {
	s       *Service
	mu      sync.Mutex
	clients map[string]*client
	sigs    map[string]uint64
}

func newHub(s *Service) *hub {
	return &hub{s: s, clients: map[string]*client{}, sigs: map[string]uint64{}}
}

func encodeEvent(name string, v any) []byte {
	data, _ := json.Marshal(v)
	return []byte("event: " + name + "\ndata: " + string(data) + "\n\n")
}

func (c *client) send(msg []byte) {
	select {
	case c.ch <- msg:
	default: // a slow client misses events; it reloads on reconnect anyway
	}
}

func (h *hub) broadcast(name string, v any) {
	msg := encodeEvent(name, v)
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, c := range h.clients {
		c.send(msg)
	}
}

func (h *hub) notifyChange(dirs ...string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, d := range dirs {
		delete(h.sigs, d) // re-read on the next poll, without sending twice
		msg := encodeEvent("change", map[string]string{"dir": d})
		for _, c := range h.clients {
			c.mu.Lock()
			w := c.watch[d]
			c.mu.Unlock()
			if w {
				c.send(msg)
			}
		}
	}
}

func (h *hub) closeSession(id string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, c := range h.clients {
		if c.session == id {
			c.send(encodeEvent("revoked", nil))
			go func(c *client) {
				time.Sleep(500 * time.Millisecond)
				select {
				case <-c.done:
				default:
					close(c.done)
				}
			}(c)
		}
	}
}

func (h *hub) onlineSessions() map[string]bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	out := map[string]bool{}
	for _, c := range h.clients {
		out[c.session] = true
	}
	return out
}

func dirSignature(p string) uint64 {
	f, err := os.Open(p)
	if err != nil {
		return 1
	}
	defer f.Close()
	h := fnv.New64a()
	if st, err := f.Stat(); err == nil {
		fmt.Fprint(h, st.ModTime().UnixNano())
	}
	des, _ := f.ReadDir(5000)
	for _, de := range des {
		h.Write([]byte(de.Name()))
		if info, err := de.Info(); err == nil {
			fmt.Fprint(h, info.Size(), info.ModTime().UnixNano())
		}
	}
	return h.Sum64()
}

// run polls the folders the apps are looking at, so changes made outside
// the app (Samba, SSH, the media server) show up too.
func (h *hub) run(ctx context.Context) {
	t := time.NewTicker(2 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
		h.mu.Lock()
		watched := map[string]bool{}
		for _, c := range h.clients {
			c.mu.Lock()
			for d := range c.watch {
				watched[d] = true
			}
			c.mu.Unlock()
		}
		h.mu.Unlock()
		for d := range watched {
			sig := dirSignature(d)
			h.mu.Lock()
			old, ok := h.sigs[d]
			h.sigs[d] = sig
			h.mu.Unlock()
			if ok && old != sig {
				h.notifyChangeOnly(d)
			}
		}
		h.mu.Lock()
		for d := range h.sigs {
			if !watched[d] {
				delete(h.sigs, d)
			}
		}
		h.mu.Unlock()
	}
}

func (h *hub) notifyChangeOnly(d string) {
	msg := encodeEvent("change", map[string]string{"dir": d})
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, c := range h.clients {
		c.mu.Lock()
		w := c.watch[d]
		c.mu.Unlock()
		if w {
			c.send(msg)
		}
	}
}

func cleanWatch(list []string) map[string]bool {
	m := map[string]bool{}
	for _, d := range list {
		if p, ok := cleanPath(d); ok && len(m) < 16 {
			m[filepath.Clean(p)] = true
		}
	}
	return m
}

func (s *Service) handleEvents(w http.ResponseWriter, r *http.Request) {
	rc := http.NewResponseController(w)
	ss := sessionFrom(r)
	c := &client{id: randomHex(6), session: ss.ID, ch: make(chan []byte, 256), done: make(chan struct{}),
		watch: cleanWatch(r.URL.Query()["watch"])}
	h := w.Header()
	h.Set("Content-Type", "text/event-stream; charset=utf-8")
	h.Set("Cache-Control", "no-store")
	h.Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	write := func(b []byte) error {
		_ = rc.SetWriteDeadline(time.Now().Add(30 * time.Second))
		if _, err := w.Write(b); err != nil {
			return err
		}
		return rc.Flush()
	}
	if write(encodeEvent("hello", map[string]any{"id": c.id, "session": ss.ID, "server": s.serverInfo()})) != nil {
		return
	}
	s.hub.mu.Lock()
	s.hub.clients[c.id] = c
	s.hub.mu.Unlock()
	s.hub.broadcast("sessions", nil)
	defer func() {
		s.hub.mu.Lock()
		delete(s.hub.clients, c.id)
		s.hub.mu.Unlock()
		s.hub.broadcast("sessions", nil)
	}()
	ping := time.NewTicker(10 * time.Second)
	defer ping.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-s.ctx.Done():
			return
		case <-c.done:
			return
		case msg := <-c.ch:
			if write(msg) != nil {
				return
			}
		case now := <-ping.C:
			if write(encodeEvent("ping", map[string]string{"t": strconv.FormatInt(now.UnixMilli(), 10)})) != nil {
				return
			}
		}
	}
}

func (s *Service) handleWatch(w http.ResponseWriter, r *http.Request) {
	var b struct {
		Dirs []string `json:"dirs"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	s.hub.mu.Lock()
	c := s.hub.clients[r.PathValue("id")]
	s.hub.mu.Unlock()
	if c == nil || c.session != sessionFrom(r).ID {
		writeError(w, http.StatusNotFound, "Bağlantı bulunamadı")
		return
	}
	m := cleanWatch(b.Dirs)
	c.mu.Lock()
	c.watch = m
	c.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}
