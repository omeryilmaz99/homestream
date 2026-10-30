//go:build !linux

package files

import "os"

func diskSpace(string) (uint64, uint64) { return 0, 0 }

func writable(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.Mode().Perm()&0o200 != 0
}

func isNoSpace(error) bool  { return false }
func isReadOnly(error) bool { return false }

func deviceOf(p string) (uint64, bool) {
	_, err := os.Stat(p)
	return 0, err == nil
}

type mountInfo struct {
	Dev, Dir, FS string
	removable    bool
}

func mounts() []mountInfo     { return nil }
func mountRoot(string) string { return "" }
func isRemovable(string) bool { return false }
