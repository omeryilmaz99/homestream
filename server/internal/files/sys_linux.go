//go:build linux

package files

import (
	"bufio"
	"errors"
	"os"
	"strings"
	"syscall"
)

func diskSpace(p string) (total, free uint64) {
	var st syscall.Statfs_t
	if err := syscall.Statfs(p, &st); err != nil {
		return 0, 0
	}
	return st.Blocks * uint64(st.Bsize), st.Bavail * uint64(st.Bsize)
}

func writable(p string) bool { return syscall.Access(p, 2 /* W_OK */) == nil }

func isNoSpace(err error) bool {
	return errors.Is(err, syscall.ENOSPC) || errors.Is(err, syscall.EDQUOT)
}

func isReadOnly(err error) bool { return errors.Is(err, syscall.EROFS) }

func deviceOf(p string) (uint64, bool) {
	var st syscall.Stat_t
	if err := syscall.Stat(p, &st); err != nil {
		return 0, false
	}
	return uint64(st.Dev), true
}

type mountInfo struct {
	Dev, Dir, FS string
	removable    bool
}

var virtualFS = map[string]bool{"proc": true, "sysfs": true, "devtmpfs": true, "devpts": true, "tmpfs": true,
	"cgroup": true, "cgroup2": true, "securityfs": true, "pstore": true, "bpf": true, "debugfs": true, "tracefs": true,
	"mqueue": true, "hugetlbfs": true, "configfs": true, "fusectl": true, "autofs": true, "squashfs": true,
	"overlay": true, "nsfs": true, "efivarfs": true, "binfmt_misc": true, "ramfs": true, "rpc_pipefs": true}

// mounts lists real (disk or network) mounts.
func mounts() []mountInfo {
	f, err := os.Open("/proc/self/mounts")
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []mountInfo
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fl := strings.Fields(sc.Text())
		if len(fl) < 3 || virtualFS[fl[2]] {
			continue
		}
		dir := unescapeMount(fl[1])
		if strings.HasPrefix(dir, "/snap/") || strings.HasPrefix(dir, "/boot") || strings.HasPrefix(dir, "/proc") ||
			strings.HasPrefix(dir, "/sys") || strings.HasPrefix(dir, "/run") || strings.HasPrefix(dir, "/dev") {
			continue
		}
		m := mountInfo{Dev: fl[0], Dir: dir, FS: fl[2]}
		if strings.HasPrefix(m.Dev, "/dev/") {
			m.removable = isRemovable(m.Dev)
		}
		out = append(out, m)
	}
	return out
}

// unescapeMount decodes "\040" (space) and friends in /proc/mounts.
func unescapeMount(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+3 < len(s) {
			v := 0
			ok := true
			for _, c := range s[i+1 : i+4] {
				if c < '0' || c > '7' {
					ok = false
					break
				}
				v = v*8 + int(c-'0')
			}
			if ok {
				b.WriteByte(byte(v))
				i += 3
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

// mountRoot returns the mount point holding p.
func mountRoot(p string) string {
	best := ""
	for _, m := range mounts() {
		if (p == m.Dir || strings.HasPrefix(p, strings.TrimRight(m.Dir, "/")+"/")) && len(m.Dir) > len(best) {
			best = m.Dir
		}
	}
	return best
}

func isRemovable(dev string) bool {
	name := strings.TrimPrefix(dev, "/dev/")
	if t, err := os.Readlink("/sys/class/block/" + name); err == nil {
		// …/block/sdb/sdb1 → the disk is sdb
		parts := strings.Split(t, "/")
		for i := len(parts) - 1; i > 0; i-- {
			if parts[i-1] == "block" {
				name = parts[i]
				break
			}
		}
	}
	b, err := os.ReadFile("/sys/block/" + name + "/removable")
	if err == nil && strings.TrimSpace(string(b)) == "1" {
		return true
	}
	// USB disks often say removable=0: look at the bus
	if t, err := os.Readlink("/sys/block/" + name); err == nil && strings.Contains(t, "/usb") {
		return true
	}
	return false
}
