// Static file server with per-request latency (simulates Wi-Fi) that logs
// every request, used by the AVI emulator probe.
package main

import (
	"flag"
	"log"
	"net/http"
	"sync/atomic"
	"time"
)

func main() {
	dir := flag.String("dir", ".", "")
	listen := flag.String("listen", ":8431", "")
	lat := flag.Duration("latency", 30*time.Millisecond, "")
	flag.Parse()
	var n int64
	fs := http.FileServer(http.Dir(*dir))
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		c := atomic.AddInt64(&n, 1)
		time.Sleep(*lat)
		log.Printf("REQ %d %s %s range=%q", c, r.Method, r.URL.Path, r.Header.Get("Range"))
		fs.ServeHTTP(w, r)
	})
	log.Fatal(http.ListenAndServe(*listen, nil))
}
