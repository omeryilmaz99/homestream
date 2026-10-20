// Command homestream-server is the Home Stream media server.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"homestream/internal/api"
	"homestream/internal/library"
	"homestream/internal/store"
)

var version = "dev"

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func main() {
	log.SetFlags(0) // journald adds timestamps
	if os.Getenv("INVOCATION_ID") == "" {
		log.SetFlags(log.LstdFlags)
	}
	home, _ := os.UserHomeDir()
	host, _ := os.Hostname()
	defPort, _ := strconv.Atoi(envOr("HOMESTREAM_PORT", "8420"))
	defDisc, _ := strconv.Atoi(envOr("HOMESTREAM_DISCOVERY_PORT", "8421"))

	port := flag.Int("port", defPort, "HTTP port (HOMESTREAM_PORT)")
	discPort := flag.Int("discovery-port", defDisc, "UDP discovery port (HOMESTREAM_DISCOVERY_PORT)")
	dataDir := flag.String("data", envOr("HOMESTREAM_DATA", "/var/lib/homestream"), "data directory for database and image cache (HOMESTREAM_DATA)")
	libDir := flag.String("library", envOr("HOMESTREAM_LIBRARY", filepath.Join(home, "HomeStream")), "default library folder (HOMESTREAM_LIBRARY)")
	drives := flag.String("drives", envOr("HOMESTREAM_DRIVES", ""), "folder whose sub-folders are auto-mounted disks; each is added to the library (HOMESTREAM_DRIVES)")
	name := flag.String("name", envOr("HOMESTREAM_NAME", host), "server name shown in the apps (HOMESTREAM_NAME)")
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()
	if *showVersion {
		fmt.Println(version)
		return
	}
	if *name == "" {
		*name = "Home Stream"
	}

	if abs, err := filepath.Abs(*libDir); err == nil {
		*libDir = abs
	}
	if abs, err := filepath.Abs(*dataDir); err == nil {
		*dataDir = abs
	}
	if err := os.MkdirAll(*dataDir, 0o755); err != nil {
		log.Fatalf("cannot create data directory %s: %v (use --data or HOMESTREAM_DATA)", *dataDir, err)
	}
	if err := os.MkdirAll(*libDir, 0o755); err != nil {
		log.Printf("warning: cannot create library folder %s: %v", *libDir, err)
	}

	st, err := store.Open(filepath.Join(*dataDir, "homestream.db"))
	if err != nil {
		log.Fatalf("cannot open database: %v", err)
	}
	defer st.Close()

	serverID := st.GetSetting("serverId")
	if serverID == "" {
		serverID = store.RandomHex(8)
		_ = st.SetSetting("serverId", serverID)
	}
	if err := st.EnsureDefaultFolder(*libDir, filepath.Base(*libDir)); err != nil {
		log.Fatalf("cannot register library folder: %v", err)
	}

	ffprobe, ffmpeg, nice := library.LookTools()
	if ffprobe == "" || ffmpeg == "" {
		log.Printf("warning: ffmpeg/ffprobe not found; durations and thumbnails are disabled (sudo apt install ffmpeg)")
	}
	lib := library.New(library.Config{
		DataDir: *dataDir, DefaultLibrary: *libDir,
		FFprobe: ffprobe, FFmpeg: ffmpeg, Nice: nice,
		TMDBBaseURL:   os.Getenv("HOMESTREAM_TMDB_BASE"),
		TMDBImageBase: os.Getenv("HOMESTREAM_TMDB_IMAGE_BASE"),
	}, st)

	srv := &api.Server{Lib: lib, St: st, Version: version, DefaultName: *name, Port: *port, ServerID: serverID}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	ln, err := net.Listen("tcp", ":"+strconv.Itoa(*port))
	if err != nil {
		log.Fatalf("cannot listen on port %d: %v", *port, err)
	}
	httpSrv := &http.Server{
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 15 * time.Second,
		IdleTimeout:       2 * time.Minute,
		// no WriteTimeout: streams may run for hours
	}
	log.Printf("Home Stream %s: %q listening on :%d, library %s, data %s", version, srv.ServerName(), *port, *libDir, *dataDir)

	go lib.Run(ctx)
	go lib.WatchDrives(ctx, *drives)
	go srv.RunDiscovery(ctx, *discPort)

	errc := make(chan error, 1)
	go func() { errc <- httpSrv.Serve(ln) }()
	select {
	case <-ctx.Done():
		log.Printf("shutting down")
	case err := <-errc:
		if !errors.Is(err, http.ErrServerClosed) {
			log.Printf("http server: %v", err)
		}
	}
	shCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := httpSrv.Shutdown(shCtx); err != nil {
		_ = httpSrv.Close()
	}
}
