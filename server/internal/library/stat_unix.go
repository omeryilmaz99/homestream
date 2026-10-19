//go:build unix

package library

import (
	"os"
	"syscall"
)

type fileKey struct{ dev, ino uint64 }

func statKey(p string) (fileKey, bool) {
	st, err := os.Stat(p)
	if err != nil {
		return fileKey{}, false
	}
	if s, ok := st.Sys().(*syscall.Stat_t); ok {
		return fileKey{uint64(s.Dev), uint64(s.Ino)}, true
	}
	return fileKey{}, false
}
