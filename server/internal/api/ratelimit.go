package api

import (
	"sync"
	"time"
)

// RateLimiter is a per-IP token bucket limiter.
//
// Each IP starts with a full bucket of `limit` tokens; a token is consumed per
// allowed request and tokens are refilled at `limit` per `window`. This is
// smoother than a fixed window (no double burst at the window boundary).
// Buckets that stay idle for more than 2*`window` are removed periodically so
// the map can never grow without bound.
type RateLimiter struct {
	mu      sync.Mutex
	limit   float64
	window  time.Duration
	buckets map[string]*bucket
	lastGC  time.Time
}

type bucket struct {
	tokens    float64
	lastRefill time.Time
	lastSeen  time.Time
}

// NewRateLimiter creates a limiter with `limit` requests per `window` per IP.
func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		limit:   float64(limit),
		window:  window,
		buckets: make(map[string]*bucket),
	}
}

// Allow returns true if the IP can make another request.
func (r *RateLimiter) Allow(ip string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()

	now := time.Now()
	if now.Sub(r.lastGC) >= r.window/2 {
		r.gc(now)
	}

	b, ok := r.buckets[ip]
	if !ok {
		b = &bucket{tokens: r.limit, lastRefill: now, lastSeen: now}
		r.buckets[ip] = b
		return true
	}

	// Refill based on elapsed time, capped at the bucket capacity.
	b.tokens += now.Sub(b.lastRefill).Seconds() * (r.limit / r.window.Seconds())
	if b.tokens > r.limit {
		b.tokens = r.limit
	}
	b.lastRefill = now
	b.lastSeen = now

	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

// gc removes buckets that have been idle for more than 2*window.
func (r *RateLimiter) gc(now time.Time) {
	for ip, b := range r.buckets {
		if now.Sub(b.lastSeen) > r.window*2 {
			delete(r.buckets, ip)
		}
	}
	r.lastGC = now
}
