package webui

import (
	"embed"
	"io/fs"
	"net/http"
	"strings"
)

//go:embed static/*
var staticFS embed.FS

// Asset returns the content of an embedded static file. It is used by the
// tests to assert that the admin UI never renders server data as markup.
func Asset(name string) ([]byte, error) {
	return fs.ReadFile(staticFS, "static/"+name)
}

// WithAdminUI mounts the admin web UI on /admin/ and proxies to the bearer token.
func WithAdminUI(next http.Handler, adminToken string) http.Handler {
	sub, err := fs.Sub(staticFS, "static")
	if err != nil {
		panic(err)
	}
	fileServer := http.StripPrefix("/admin/", http.FileServer(http.FS(sub)))

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Automatic redirect from the root to the admin web UI.
		if r.URL.Path == "/" || r.URL.Path == "/index.html" {
			http.Redirect(w, r, "/admin/", http.StatusFound)
			return
		}
		if !strings.HasPrefix(r.URL.Path, "/admin") {
			next.ServeHTTP(w, r)
			return
		}
		// /admin -> /admin/
		if r.URL.Path == "/admin" {
			http.Redirect(w, r, "/admin/", http.StatusFound)
			return
		}
		fileServer.ServeHTTP(w, r)
	})
}
