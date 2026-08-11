package api

import (
	"sync"
	"time"
)

// RateLimiter è un limite finestra fissa per-IP.
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

// NewRateLimiter crea un limiter con `limit` richieste per finestra `window` per IP.
func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		limit:   limit,
		window:  window,
		buckets: make(map[string]*bucket),
	}
}

// Allow restituisce true se l'IP può effettuare un'altra richiesta.
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
