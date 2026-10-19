//go:build !linux

package library

import "os"

func changeTime(fi os.FileInfo) int64 { return fi.ModTime().Unix() }
