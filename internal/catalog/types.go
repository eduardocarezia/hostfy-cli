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
	Dependencies []string          `json:"dependencies,omitempty"`

	// Formato legado (single container) - mantido para compatibilidade
	Image       string            `json:"image,omitempty"`
	Port        int               `json:"port,omitempty"`
	ConsolePort int               `json:"console_port,omitempty"`
	Command     string            `json:"command,omitempty"`
	Env         map[string]string `json:"env,omitempty"`
	Volumes     []string          `json:"volumes,omitempty"`
	Traefik     *TraefikConfig    `json:"traefik,omitempty"`

	// Formato Stack (múltiplos containers)
	Containers []Container       `json:"containers,omitempty"`
	SharedEnv  map[string]string `json:"shared_env,omitempty"`

	// Comum a ambos
	UserEnv []UserEnvVar `json:"user_env,omitempty"`
}

// Container representa um container individual dentro de uma Stack
type Container struct {
	Name      string            `json:"name"`
	Image     string            `json:"image"`
	Port      int               `json:"port,omitempty"`
	Command   string            `json:"command,omitempty"`
	Env       map[string]string `json:"env,omitempty"`
	Volumes   []string          `json:"volumes,omitempty"`
	Traefik   *TraefikConfig    `json:"traefik,omitempty"`
	IsMain    bool              `json:"is_main,omitempty"`    // Container principal (recebe domínio base)
	UserEnv   []UserEnvVar      `json:"user_env,omitempty"`   // Variáveis específicas deste container
}

// IsStack retorna true se o app usa formato de múltiplos containers
func (a *App) IsStack() bool {
	return len(a.Containers) > 0
}

// GetMainContainer retorna o container principal da stack
func (a *App) GetMainContainer() *Container {
	for i := range a.Containers {
		if a.Containers[i].IsMain {
			return &a.Containers[i]
		}
	}
	// Se nenhum marcado como main, retorna o primeiro
	if len(a.Containers) > 0 {
		return &a.Containers[0]
	}
	return nil
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
