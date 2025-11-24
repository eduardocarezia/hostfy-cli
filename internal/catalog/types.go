package catalog

type Catalog struct {
	Version   string              `json:"version"`
	UpdatedAt string              `json:"updated_at"`
	Services  map[string]Service  `json:"services"`
	Apps      map[string]App      `json:"apps"`
}

type Service struct {
	Image       string            `json:"image"`
	Restart     string            `json:"restart,omitempty"`
	Command     string            `json:"command,omitempty"`
	Env         map[string]string `json:"env,omitempty"`
	Volumes     []string          `json:"volumes,omitempty"`
	Ports       []string          `json:"ports,omitempty"`
	Healthcheck *Healthcheck      `json:"healthcheck,omitempty"`
}

type Healthcheck struct {
	Test     []string `json:"test"`
	Interval string   `json:"interval"`
	Retries  int      `json:"retries"`
}

type App struct {
	Name         string            `json:"name"`
	Description  string            `json:"description"`
	Image        string            `json:"image"`
	Port         int               `json:"port"`
	ConsolePort  int               `json:"console_port,omitempty"`
	Dependencies []string          `json:"dependencies,omitempty"`
	Command      string            `json:"command,omitempty"`
	Env          map[string]string `json:"env,omitempty"`
	Volumes      []string          `json:"volumes,omitempty"`
	UserEnv      []UserEnvVar      `json:"user_env,omitempty"`
	Traefik      *TraefikConfig    `json:"traefik,omitempty"`
}

type UserEnvVar struct {
	Key     string `json:"key"`
	Prompt  string `json:"prompt"`
	Default string `json:"default"`
}

type TraefikConfig struct {
	Routes []TraefikRoute `json:"routes,omitempty"`
}

type TraefikRoute struct {
	Subdomain string `json:"subdomain"`
	Port      int    `json:"port"`
}
