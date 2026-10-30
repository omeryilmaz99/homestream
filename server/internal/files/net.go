package files

import (
	"net"
	"strings"
)

// netInterfaces returns the LAN IPv4 addresses of this machine.
func netInterfaces() ([]string, error) {
	ifs, err := net.Interfaces()
	if err != nil {
		return nil, err
	}
	var out []string
	for _, i := range ifs {
		if i.Flags&net.FlagUp == 0 || i.Flags&net.FlagLoopback != 0 ||
			strings.HasPrefix(i.Name, "docker") || strings.HasPrefix(i.Name, "veth") || strings.HasPrefix(i.Name, "br-") {
			continue
		}
		addrs, _ := i.Addrs()
		for _, a := range addrs {
			if ipn, ok := a.(*net.IPNet); ok && ipn.IP.To4() != nil {
				out = append(out, ipn.IP.String())
			}
		}
	}
	return out, nil
}
