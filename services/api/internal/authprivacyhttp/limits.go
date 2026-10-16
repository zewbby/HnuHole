package authprivacyhttp

import (
	"crypto/hmac"
	"crypto/sha256"
	"errors"
	"math"
	"net"
	"net/netip"
	"strconv"
	"sync"
	"time"
)

// NetworkLimits is independent of V's address/device budgets and of either
// service's SQL/HMAC keys. The operator supplies a distinct random Key for
// each service. Query and mutation counters cannot reset one another.
type NetworkLimits struct {
	Key              [32]byte
	MutationCapacity int
	QueryCapacity    int
	Window           time.Duration
	MaxEntries       int
}

type budget struct {
	start              time.Time
	mutations, queries int
}
type networkLimiter struct {
	mu      sync.Mutex
	config  NetworkLimits
	service Service
	entries map[[32]byte]*budget
}

func newNetworkLimiter(config NetworkLimits, service Service) (*networkLimiter, error) {
	if config.Key == ([32]byte{}) || config.MutationCapacity < 1 || config.MutationCapacity > 10000 || config.QueryCapacity < 1 || config.QueryCapacity > 10000 || config.Window <= 0 || config.Window > 5*time.Minute || config.MaxEntries < 1 || config.MaxEntries > 65536 {
		return nil, errors.New("invalid bounded network budgets")
	}
	return &networkLimiter{config: config, service: service, entries: make(map[[32]byte]*budget)}, nil
}

func canonicalNetwork(remote string) (string, error) {
	host, port, err := net.SplitHostPort(remote)
	if err != nil {
		return "", errMalformed
	}
	parsedPort, err := strconv.Atoi(port)
	if err != nil || parsedPort < 0 || parsedPort > 65535 {
		return "", errMalformed
	}
	address, err := netip.ParseAddr(host)
	if err != nil {
		return "", errMalformed
	}
	address = address.WithZone("").Unmap()
	if address.Is4() {
		return address.String(), nil
	}
	// A changing IPv6 interface identifier cannot bypass the network budget.
	return netip.PrefixFrom(address, 64).Masked().String(), nil
}

func (limiter *networkLimiter) allow(remote string, query bool) (int, error) {
	network, err := canonicalNetwork(remote)
	if err != nil {
		return 0, err
	}
	h := hmac.New(sha256.New, limiter.config.Key[:])
	h.Write([]byte("HNUHOLE/HTTP-NETWORK/V1\x00" + string(limiter.service) + "\x00"))
	h.Write([]byte(network))
	var key [32]byte
	copy(key[:], h.Sum(nil))
	at := time.Now()
	limiter.mu.Lock()
	defer limiter.mu.Unlock()
	entry := limiter.entries[key]
	if entry == nil {
		if len(limiter.entries) >= limiter.config.MaxEntries {
			for old, value := range limiter.entries {
				if at.Sub(value.start) >= limiter.config.Window {
					delete(limiter.entries, old)
				}
			}
			if len(limiter.entries) >= limiter.config.MaxEntries {
				return seconds(limiter.config.Window), nil
			}
		}
		entry = &budget{start: at}
		limiter.entries[key] = entry
	}
	if at.Sub(entry.start) >= limiter.config.Window {
		*entry = budget{start: at}
	}
	used, maximum := &entry.mutations, limiter.config.MutationCapacity
	if query {
		used, maximum = &entry.queries, limiter.config.QueryCapacity
	}
	if *used >= maximum {
		return seconds(limiter.config.Window - at.Sub(entry.start)), nil
	}
	*used++
	return 0, nil
}

func seconds(duration time.Duration) int {
	value := int(math.Ceil(duration.Seconds()))
	if value < 1 {
		return 1
	}
	if value > 300 {
		return 300
	}
	return value
}
