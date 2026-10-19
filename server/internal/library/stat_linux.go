//go:build linux

package library

import (
	"os"
	"syscall"
)

// changeTime returns the inode change time (when the file arrived on this file system).
func changeTime(fi os.FileInfo) int64 {
	if s, ok := fi.Sys().(*syscall.Stat_t); ok {
		return int64(s.Ctim.Sec)
	}
	return fi.ModTime().Unix()
}
