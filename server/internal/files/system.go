package files

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ---------- system status ----------

type sysSampler struct {
	mu       sync.Mutex
	cpuAt    time.Time
	cpuIdle  uint64
	cpuTotal uint64
	cpuPct   float64
	netAt    time.Time
	netRx    uint64
	netTx    uint64
	rxRate   float64
	txRate   float64
}

func readCPU() (idle, total uint64) {
	b, err := os.ReadFile("/proc/stat")
	if err != nil {
		return 0, 0
	}
	line, _, _ := bytes.Cut(b, []byte("\n"))
	f := strings.Fields(string(line))
	if len(f) < 5 || f[0] != "cpu" {
		return 0, 0
	}
	for i, v := range f[1:] {
		n, _ := strconv.ParseUint(v, 10, 64)
		total += n
		if i == 3 || i == 4 { // idle + iowait
			idle += n
		}
	}
	return idle, total
}

func readNet() (rx, tx uint64) {
	b, err := os.ReadFile("/proc/net/dev")
	if err != nil {
		return 0, 0
	}
	for _, line := range strings.Split(string(b), "\n")[2:] {
		name, rest, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		name = strings.TrimSpace(name)
		if name == "lo" || strings.HasPrefix(name, "docker") || strings.HasPrefix(name, "veth") || strings.HasPrefix(name, "br-") {
			continue
		}
		f := strings.Fields(rest)
		if len(f) >= 9 {
			r, _ := strconv.ParseUint(f[0], 10, 64)
			t, _ := strconv.ParseUint(f[8], 10, 64)
			rx += r
			tx += t
		}
	}
	return
}

func (s *sysSampler) sample() (cpu, rx, tx float64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	if now.Sub(s.cpuAt) > 900*time.Millisecond {
		idle, total := readCPU()
		if s.cpuTotal > 0 && total > s.cpuTotal {
			dt := float64(total - s.cpuTotal)
			s.cpuPct = 100 * (1 - float64(idle-s.cpuIdle)/dt)
		}
		s.cpuIdle, s.cpuTotal, s.cpuAt = idle, total, now
		r, t := readNet()
		if !s.netAt.IsZero() {
			sec := now.Sub(s.netAt).Seconds()
			if r >= s.netRx && t >= s.netTx && sec > 0 {
				s.rxRate = float64(r-s.netRx) / sec
				s.txRate = float64(t-s.netTx) / sec
			}
		}
		s.netRx, s.netTx, s.netAt = r, t, now
	}
	return s.cpuPct, s.rxRate, s.txRate
}

func meminfo() (total, avail uint64) {
	b, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(b), "\n") {
		f := strings.Fields(line)
		if len(f) < 2 {
			continue
		}
		n, _ := strconv.ParseUint(f[1], 10, 64)
		switch f[0] {
		case "MemTotal:":
			total = n * 1024
		case "MemAvailable:":
			avail = n * 1024
		}
	}
	return
}

func temperature() float64 {
	best := 0.0
	zones, _ := filepath.Glob("/sys/class/thermal/thermal_zone*")
	for _, z := range zones {
		t, _ := os.ReadFile(filepath.Join(z, "type"))
		typ := strings.TrimSpace(string(t))
		v, err := os.ReadFile(filepath.Join(z, "temp"))
		if err != nil {
			continue
		}
		n, err := strconv.ParseFloat(strings.TrimSpace(string(v)), 64)
		if err != nil || n <= 0 {
			continue
		}
		c := n / 1000
		// the CPU package sensor wins
		if strings.Contains(typ, "pkg") || strings.Contains(typ, "cpu") || strings.Contains(typ, "k10temp") {
			return c
		}
		if c > best {
			best = c
		}
	}
	if best == 0 {
		hw, _ := filepath.Glob("/sys/class/hwmon/hwmon*/temp1_input")
		for _, h := range hw {
			v, _ := os.ReadFile(h)
			if n, err := strconv.ParseFloat(strings.TrimSpace(string(v)), 64); err == nil && n/1000 > best {
				best = n / 1000
			}
		}
	}
	return best
}

func osName() string {
	b, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return runtime.GOOS
	}
	for _, line := range strings.Split(string(b), "\n") {
		if v, ok := strings.CutPrefix(line, "PRETTY_NAME="); ok {
			return strings.Trim(v, `"`)
		}
	}
	return runtime.GOOS
}

func lanIPs() []string {
	var out []string
	ifs, _ := netInterfaces()
	for _, ip := range ifs {
		out = append(out, ip)
	}
	return out
}

func (s *Service) handleSystem(w http.ResponseWriter, r *http.Request) {
	cpu, rx, tx := s.sys.sample()
	memTotal, memAvail := meminfo()
	var load [3]float64
	if b, err := os.ReadFile("/proc/loadavg"); err == nil {
		f := strings.Fields(string(b))
		for i := 0; i < 3 && i < len(f); i++ {
			load[i], _ = strconv.ParseFloat(f[i], 64)
		}
	}
	var uptime float64
	if b, err := os.ReadFile("/proc/uptime"); err == nil {
		f := strings.Fields(string(b))
		if len(f) > 0 {
			uptime, _ = strconv.ParseFloat(f[0], 64)
		}
	}
	host, _ := os.Hostname()
	total, free := diskSpace(s.cfg.Home)
	writeJSON(w, http.StatusOK, map[string]any{
		"hostname": host, "os": osName(), "arch": runtime.GOARCH, "cpus": runtime.NumCPU(),
		"cpu": cpu, "load": load, "memTotal": memTotal, "memAvailable": memAvail,
		"uptime": uptime, "temperature": temperature(), "rxRate": rx, "txRate": tx,
		"homeTotal": total, "homeFree": free, "ips": lanIPs(), "server": s.serverInfo(),
	})
}

// ---------- disks ----------

type diskJSON struct {
	Name       string     `json:"name"`
	Path       string     `json:"path"` // /dev/sdb
	Model      string     `json:"model"`
	Size       uint64     `json:"size"`
	Removable  bool       `json:"removable"`
	Transport  string     `json:"transport"` // usb | sata | nvme …
	System     bool       `json:"system"`    // holds the running system
	Partitions []partJSON `json:"partitions"`
}

type partJSON struct {
	Name       string `json:"name"`
	Path       string `json:"path"`
	Label      string `json:"label"`
	FS         string `json:"fs"`
	Size       uint64 `json:"size"`
	Mountpoint string `json:"mountpoint"`
	Total      uint64 `json:"total"`
	Free       uint64 `json:"free"`
	CanEject   bool   `json:"canEject"`
	CanMount   bool   `json:"canMount"`
}

type lsblkDev struct {
	Name       string     `json:"name"`
	Path       string     `json:"path"`
	Type       string     `json:"type"`
	Size       any        `json:"size"`
	FSType     *string    `json:"fstype"`
	Label      *string    `json:"label"`
	Mountpoint *string    `json:"mountpoint"`
	Model      *string    `json:"model"`
	Tran       *string    `json:"tran"`
	RM         any        `json:"rm"`
	Children   []lsblkDev `json:"children"`
}

func str(p *string) string {
	if p == nil {
		return ""
	}
	return strings.TrimSpace(*p)
}

func num(v any) uint64 {
	switch t := v.(type) {
	case float64:
		return uint64(t)
	case string:
		n, _ := strconv.ParseUint(t, 10, 64)
		return n
	}
	return 0
}

func truthy(v any) bool {
	switch t := v.(type) {
	case bool:
		return t
	case string:
		return t == "1" || t == "true"
	case float64:
		return t == 1
	}
	return false
}

var systemMounts = map[string]bool{"/": true, "/boot": true, "/boot/efi": true, "/home": true, "/var": true, "/usr": true, "[SWAP]": true}

func (s *Service) disks() []diskJSON {
	out := []diskJSON{}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	b, err := exec.CommandContext(ctx, "lsblk", "-J", "-b", "-o", "NAME,PATH,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINT,MODEL,TRAN,RM").Output()
	if err != nil {
		// no lsblk: show the mounted disks at least
		for _, m := range mounts() {
			t, f := diskSpace(m.Dir)
			out = append(out, diskJSON{Name: filepath.Base(m.Dev), Path: m.Dev, Size: t, Removable: m.removable,
				System: systemMounts[m.Dir],
				Partitions: []partJSON{{Name: filepath.Base(m.Dev), Path: m.Dev, FS: m.FS, Size: t, Mountpoint: m.Dir,
					Total: t, Free: f, CanEject: s.canEject(m.Dir)}}})
		}
		return out
	}
	var data struct {
		Blockdevices []lsblkDev `json:"blockdevices"`
	}
	if json.Unmarshal(b, &data) != nil {
		return out
	}
	for _, d := range data.Blockdevices {
		if d.Type != "disk" || strings.HasPrefix(d.Name, "loop") || strings.HasPrefix(d.Name, "zram") || strings.HasPrefix(d.Name, "ram") {
			continue
		}
		dj := diskJSON{Name: d.Name, Path: d.Path, Model: str(d.Model), Size: num(d.Size), Transport: str(d.Tran)}
		dj.Removable = truthy(d.RM) || dj.Transport == "usb"
		parts := d.Children
		if len(parts) == 0 && str(d.FSType) != "" {
			parts = []lsblkDev{d} // a disk without a partition table
		}
		var walk func(list []lsblkDev)
		walk = func(list []lsblkDev) {
			for _, p := range list {
				if len(p.Children) > 0 && p.Type != "part" {
					walk(p.Children)
				}
				mp := str(p.Mountpoint)
				if systemMounts[mp] {
					dj.System = true
				}
				pj := partJSON{Name: p.Name, Path: p.Path, Label: str(p.Label), FS: str(p.FSType), Size: num(p.Size), Mountpoint: mp}
				if mp != "" && mp != "[SWAP]" {
					pj.Total, pj.Free = diskSpace(mp)
					pj.CanEject = s.canEject(mp)
				} else if pj.FS != "" && pj.FS != "swap" && pj.FS != "LVM2_member" && pj.FS != "crypto_LUKS" && s.cfg.DrivesDir != "" {
					pj.CanMount = true
				}
				dj.Partitions = append(dj.Partitions, pj)
			}
		}
		walk(parts)
		if dj.System {
			for i := range dj.Partitions {
				dj.Partitions[i].CanMount = false
				dj.Partitions[i].CanEject = false
			}
		}
		out = append(out, dj)
	}
	sort.SliceStable(out, func(i, j int) bool { return !out[i].Removable && out[j].Removable })
	return out
}

func (s *Service) canEject(mp string) bool {
	return s.cfg.DrivesDir != "" && filepath.Dir(mp) == filepath.Clean(s.cfg.DrivesDir)
}

func (s *Service) handleDevices(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"disks": s.disks(), "sessions": s.sessionList(sessionFrom(r))})
}

func (s *Service) helper(args ...string) (string, error) {
	cmd := s.cfg.EjectCmd
	if len(cmd) == 0 {
		cmd = []string{"sudo", "-n", "/usr/local/sbin/homestream-disk"}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, cmd[0], append(cmd[1:], args...)...).CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

func (s *Service) handleEject(w http.ResponseWriter, r *http.Request) {
	var b struct {
		Path string `json:"path"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	p, ok := cleanPath(b.Path)
	if !ok || !s.canEject(p) {
		writeError(w, http.StatusBadRequest, "Bu disk uygulamadan çıkarılamaz")
		return
	}
	s.locks.Lock()
	for up := range s.pathUse {
		if strings.HasPrefix(up, p+"/") {
			s.locks.Unlock()
			writeError(w, http.StatusConflict, "Bu diske şu an dosya yükleniyor. Bitince tekrar dene.")
			return
		}
	}
	s.locks.Unlock()
	out, err := s.helper("eject", p)
	if err != nil {
		msg := "Disk çıkarılamadı"
		switch {
		case strings.Contains(out, "busy") || strings.Contains(out, "meşgul"):
			msg = "Disk kullanımda (bir dosya açık ya da film oynuyor). Kapatıp tekrar dene."
		case strings.Contains(out, "password") || strings.Contains(out, "sudo"):
			msg = "Sunucuda disk izni kurulmamış. Sunucuyu güncelle (install.sh komutunu tekrar çalıştır)."
		case out != "":
			msg += ": " + out
		}
		writeError(w, http.StatusInternalServerError, msg)
		return
	}
	s.hub.broadcast("disks", nil)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": "Disk güvenle çıkarılabilir"})
}

func (s *Service) handleMount(w http.ResponseWriter, r *http.Request) {
	var b struct {
		Device string `json:"device"`
	}
	if err := readJSON(r, &b); err != nil || !strings.HasPrefix(b.Device, "/dev/") || strings.Contains(b.Device, "..") {
		writeError(w, http.StatusBadRequest, "Geçersiz disk")
		return
	}
	out, err := s.helper("mount", b.Device)
	if err != nil {
		msg := "Disk bağlanamadı"
		if strings.Contains(out, "password") || strings.Contains(out, "sudo") {
			msg = "Sunucuda disk izni kurulmamış. Sunucuyu güncelle (install.sh komutunu tekrar çalıştır)."
		} else if out != "" {
			msg += ": " + out
		}
		writeError(w, http.StatusInternalServerError, msg)
		return
	}
	s.hub.broadcast("disks", nil)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

// watchDisks tells the apps when a disk is plugged in or removed.
func (s *Service) watchDisks(ctx context.Context) {
	key := func() string {
		var parts []string
		for _, m := range mounts() {
			parts = append(parts, m.Dev+"="+m.Dir)
		}
		if des, err := os.ReadDir("/sys/block"); err == nil {
			for _, d := range des {
				parts = append(parts, d.Name())
			}
		}
		sort.Strings(parts)
		return strings.Join(parts, "|")
	}
	last := key()
	t := time.NewTicker(4 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
		if k := key(); k != last {
			last = k
			s.hub.broadcast("disks", nil)
		}
	}
}
