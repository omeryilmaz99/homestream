package api

import (
	"context"
	"encoding/json"
	"log"
	"net"
	"strconv"
	"strings"
)

// RunDiscovery answers HOMESTREAM_DISCOVER UDP broadcasts until ctx is done.
func (s *Server) RunDiscovery(ctx context.Context, port int) {
	conn, err := net.ListenPacket("udp4", ":"+strconv.Itoa(port))
	if err != nil {
		log.Printf("discovery: cannot listen on udp/%d: %v (clients must enter the address manually)", port, err)
		return
	}
	log.Printf("discovery: listening on udp/%d", port)
	go func() {
		<-ctx.Done()
		conn.Close()
	}()
	buf := make([]byte, 512)
	for {
		n, addr, err := conn.ReadFrom(buf)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			continue
		}
		if strings.TrimSpace(string(buf[:n])) != "HOMESTREAM_DISCOVER" {
			continue
		}
		resp, _ := json.Marshal(map[string]any{
			"app": "homestream", "id": s.ServerID, "name": s.ServerName(), "port": s.Port, "version": s.Version,
		})
		_, _ = conn.WriteTo(resp, addr)
	}
}
