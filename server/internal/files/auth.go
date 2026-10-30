package files

import (
	"context"
	"net/http"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

type ctxKey struct{}

func sessionFrom(r *http.Request) *session {
	ss, _ := r.Context().Value(ctxKey{}).(*session)
	return ss
}

func bearer(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if t, ok := strings.CutPrefix(h, "Bearer "); ok {
		return strings.TrimSpace(t)
	}
	// downloads and thumbnails opened as plain URLs
	return strings.TrimSpace(r.URL.Query().Get("token"))
}

// auth wraps a handler so it only runs with a valid session token.
func (s *Service) auth(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		tok := bearer(r)
		if tok == "" {
			writeError(w, http.StatusUnauthorized, "Oturum açılmadı")
			return
		}
		hash := hashToken(tok)
		s.mu.Lock()
		ss := s.sessions[hash]
		if ss != nil {
			now := time.Now().Unix()
			ss.LastSeen = now
			ss.LastIP = clientIP(r)
			if now-ss.saved > 60 {
				ss.saved = now
				id, ip := ss.ID, ss.LastIP
				go func() {
					_, _ = s.cfg.DB.Exec(`UPDATE file_sessions SET last_seen=?, last_ip=? WHERE id=?`, now, ip, id)
				}()
			}
		}
		s.mu.Unlock()
		if ss == nil {
			writeError(w, http.StatusUnauthorized, "Oturumun süresi doldu ya da kapatıldı, yeniden giriş yap")
			return
		}
		h(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, ss)))
	}
}

func (s *Service) serverInfo() map[string]any {
	return map[string]any{"id": s.cfg.ServerID, "name": s.cfg.ServerName(), "version": s.cfg.Version}
}

func trimDevice(v string, def string) string {
	v = strings.TrimSpace(v)
	if v == "" {
		return def
	}
	if utf8.RuneCountInString(v) > 60 {
		v = string([]rune(v)[:60])
	}
	return v
}

func (s *Service) handleLogin(w http.ResponseWriter, r *http.Request) {
	var b struct {
		Password string `json:"password"`
		Device   string `json:"device"`
		Platform string `json:"platform"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	ip := clientIP(r)
	s.mu.Lock()
	f := s.fails[ip]
	if f != nil && time.Now().Before(f.until) {
		wait := int(time.Until(f.until).Seconds()) + 1
		s.mu.Unlock()
		w.Header().Set("Retry-After", itoa(wait))
		writeError(w, http.StatusTooManyRequests, "Çok fazla yanlış deneme. "+itoa(wait)+" saniye sonra tekrar dene.")
		return
	}
	s.mu.Unlock()

	if s.cfg.CheckPassword == nil || !s.cfg.CheckPassword(strings.TrimSpace(b.Password)) {
		s.mu.Lock()
		if f == nil {
			f = &failInfo{}
			s.fails[ip] = f
		}
		f.n++
		if f.n >= 5 {
			// 30 s, then 60 s, 120 s … up to 15 min
			d := 30 * time.Second << min(f.n-5, 5)
			f.until = time.Now().Add(min(d, 15*time.Minute))
		}
		s.mu.Unlock()
		time.Sleep(400 * time.Millisecond) // slows down guessing
		writeError(w, http.StatusForbidden, "Şifre yanlış")
		return
	}

	tok := randomHex(32)
	now := time.Now().Unix()
	ss := &session{ID: randomHex(6), Device: trimDevice(b.Device, "Cihaz"), Platform: trimDevice(b.Platform, ""),
		Created: now, LastSeen: now, LastIP: ip, hash: hashToken(tok), saved: now}
	if _, err := s.cfg.DB.Exec(`INSERT INTO file_sessions (token_hash, id, device, platform, created, last_seen, last_ip) VALUES (?,?,?,?,?,?,?)`,
		ss.hash, ss.ID, ss.Device, ss.Platform, ss.Created, ss.LastSeen, ss.LastIP); err != nil {
		writeError(w, http.StatusInternalServerError, "Oturum kaydedilemedi")
		return
	}
	s.mu.Lock()
	delete(s.fails, ip)
	s.sessions[ss.hash] = ss
	s.mu.Unlock()
	s.hub.broadcast("sessions", nil)
	writeJSON(w, http.StatusOK, map[string]any{"token": tok, "session": ss, "server": s.serverInfo()})
}

func (s *Service) handleLogout(w http.ResponseWriter, r *http.Request) {
	s.removeSession(sessionFrom(r).ID)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Service) removeSession(id string) bool {
	s.mu.Lock()
	found := false
	for h, ss := range s.sessions {
		if ss.ID == id {
			delete(s.sessions, h)
			found = true
		}
	}
	s.mu.Unlock()
	if found {
		_, _ = s.cfg.DB.Exec(`DELETE FROM file_sessions WHERE id=?`, id)
		s.hub.closeSession(id)
		s.hub.broadcast("sessions", nil)
	}
	return found
}

func (s *Service) handleSession(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"session": sessionFrom(r), "server": s.serverInfo()})
}

func (s *Service) handleRevoke(w http.ResponseWriter, r *http.Request) {
	if !s.removeSession(r.PathValue("id")) {
		writeError(w, http.StatusNotFound, "Oturum bulunamadı")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

type sessionJSON struct {
	session
	Online  bool `json:"online"`
	Current bool `json:"current"`
}

func (s *Service) sessionList(cur *session) []sessionJSON {
	online := s.hub.onlineSessions()
	s.mu.Lock()
	out := make([]sessionJSON, 0, len(s.sessions))
	for _, ss := range s.sessions {
		out = append(out, sessionJSON{session: *ss, Online: online[ss.ID], Current: cur != nil && cur.ID == ss.ID})
	}
	s.mu.Unlock()
	sort.Slice(out, func(i, j int) bool {
		if out[i].Online != out[j].Online {
			return out[i].Online
		}
		return out[i].LastSeen > out[j].LastSeen
	})
	return out
}
