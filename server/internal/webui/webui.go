package webui

import (
	"embed"
	"io/fs"
	"net/http"
	"strings"
)

//go:embed static/*
var staticFS embed.FS

// WithAdminUI monta la web UI admin su /admin/ e fa da proxy verso il bearer token.
func WithAdminUI(next http.Handler, adminToken string) http.Handler {
	sub, err := fs.Sub(staticFS, "static")
	if err != nil {
		panic(err)
	}
	fileServer := http.StripPrefix("/admin/", http.FileServer(http.FS(sub)))

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Redirect automatico dalla root alla web UI admin.
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
