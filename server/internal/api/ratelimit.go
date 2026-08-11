package api

import (
	"sync"
	"time"
)

// RateLimiter is a fixed-window per-IP limiter.
type RateLimiter struct {
	mu      sync.Mutex
	limit   int
	window  time.Duration
	buckets map[string]*bucket
}

type bucket struct {
	count   int
	windowStart time.Time
}

// NewRateLimiter creates a limiter with `limit` requests per `window` per IP.
func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		limit:   limit,
		window:  window,
		buckets: make(map[string]*bucket),
	}
}

// Allow returns true if the IP can make another request.
func (r *RateLimiter) Allow(ip string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()

	now := time.Now()
	b, ok := r.buckets[ip]
	if !ok || now.Sub(b.windowStart) >= r.window {
		r.buckets[ip] = &bucket{count: 1, windowStart: now}
		return true
	}
	if b.count >= r.limit {
		return false
	}
	b.count++
	return true
}
