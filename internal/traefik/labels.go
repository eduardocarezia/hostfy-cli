package traefik

import (
	"fmt"
	"strings"
)

func GenerateLabels(appName, domain string, port int) map[string]string {
	safeName := strings.ReplaceAll(appName, "-", "_")

	return map[string]string{
		"traefik.enable": "true",

		// HTTP Router
		fmt.Sprintf("traefik.http.routers.%s.rule", safeName): fmt.Sprintf("Host(`%s`)", domain),
		fmt.Sprintf("traefik.http.routers.%s.entrypoints", safeName): "websecure",
		fmt.Sprintf("traefik.http.routers.%s.tls.certresolver", safeName): "hostfyresolver",

		// Service
		fmt.Sprintf("traefik.http.services.%s.loadbalancer.server.port", safeName): fmt.Sprintf("%d", port),

		// Hostfy metadata
		"hostfy.managed": "true",
		"hostfy.app":     appName,
		"hostfy.domain":  domain,
	}
}

func GenerateMultiRouteLabels(appName string, routes []struct {
	Subdomain string
	Port      int
}) map[string]string {
	labels := map[string]string{
		"traefik.enable": "true",
		"hostfy.managed": "true",
		"hostfy.app":     appName,
	}

	for i, route := range routes {
		routeName := fmt.Sprintf("%s_%d", strings.ReplaceAll(appName, "-", "_"), i)

		labels[fmt.Sprintf("traefik.http.routers.%s.rule", routeName)] = fmt.Sprintf("Host(`%s`)", route.Subdomain)
		labels[fmt.Sprintf("traefik.http.routers.%s.entrypoints", routeName)] = "websecure"
		labels[fmt.Sprintf("traefik.http.routers.%s.tls.certresolver", routeName)] = "hostfyresolver"
		labels[fmt.Sprintf("traefik.http.routers.%s.service", routeName)] = routeName
		labels[fmt.Sprintf("traefik.http.services.%s.loadbalancer.server.port", routeName)] = fmt.Sprintf("%d", route.Port)
	}

	return labels
}
