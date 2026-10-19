//go:build !unix

package library

type fileKey struct{ p string }

func statKey(p string) (fileKey, bool) { return fileKey{p}, true }
