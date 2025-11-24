package cli

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/eduardocarezia/hostfy-cli/internal/catalog"
	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/services"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/traefik"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var installCmd = &cobra.Command{
	Use:   "install <app>",
	Short: "Instala um app do catálogo",
	Long:  `Instala um app do catálogo com todas as suas dependências.`,
	Args:  cobra.ExactArgs(1),
	RunE:  runInstall,
}

var (
	installDomain string
	installName   string
	installEnv    []string
)

func init() {
	installCmd.Flags().StringVar(&installDomain, "domain", "", "Domínio para o app (obrigatório)")
	installCmd.Flags().StringVar(&installName, "name", "", "Nome customizado para a stack")
	installCmd.Flags().StringSliceVar(&installEnv, "env", []string{}, "Variáveis de ambiente extras (KEY=VALUE)")
	installCmd.MarkFlagRequired("domain")
}

func runInstall(cmd *cobra.Command, args []string) error {
	appID := args[0]
	stackName := installName
	if stackName == "" {
		stackName = appID
	}

	// Verificar se já existe
	if storage.AppExists(stackName) {
		ui.Error(fmt.Sprintf("App '%s' já existe. Use --name para criar outra instância.", stackName))
		return fmt.Errorf("app já existe")
	}

	// 1. Buscar app no catálogo
	app, err := catalog.GetApp(appID)
	if err != nil {
		ui.Error(err.Error())
		return err
	}

	// Verificar se é Stack ou single container
	if app.IsStack() {
		return installStack(app, appID, stackName)
	}
	return installSingle(app, appID, stackName)
}

// installStack instala uma stack com múltiplos containers
func installStack(app *catalog.App, appID, stackName string) error {
	containerCount := len(app.Containers)
	totalSteps := 5 + containerCount // deps + db + config + N containers + save
	progress := ui.NewProgress(totalSteps)

	progress.Step(fmt.Sprintf("Instalando stack %s (%d containers)...", app.Name, containerCount))

	// 1. Conectar ao Docker
	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	// 2. Verificar e instalar dependências
	progress.Step("Verificando dependências...")
	secrets, err := storage.EnsureSecrets()
	if err != nil {
		ui.Error("Erro ao carregar secrets: " + err.Error())
		return err
	}

	if err := ensureDependencies(app.Dependencies, dockerClient, secrets, progress); err != nil {
		return err
	}

	// 3. Criar database se necessário
	dbName := ""
	for _, dep := range app.Dependencies {
		if dep == "postgres" {
			progress.Step("Criando database...")
			dbName = strings.ReplaceAll(stackName, "-", "_") + "_db"
			pgManager := services.NewPostgresManager(dockerClient, secrets)
			if err := pgManager.CreateDatabase(dbName); err != nil {
				ui.Error("Erro ao criar database: " + err.Error())
				return err
			}
			break
		}
	}
	if dbName == "" {
		progress.Step("Configurando stack...")
	}

	// 4. Preparar contexto de templates
	tmplCtx := catalog.NewTemplateContext(stackName, installDomain, secrets)

	// Verificar secrets de instalação anterior
	if storage.AppSecretsBackupExists(stackName) {
		backup, err := storage.LoadAppSecretsBackup(stackName)
		if err == nil && backup.CatalogApp == appID {
			tmplCtx.SetPreservedSecrets(backup.Secrets)
			progress.SubStep("Reutilizando secrets de instalação anterior")
		}
	}

	// Resolver shared_env uma vez (para compartilhar entre containers)
	resolvedSharedEnv := tmplCtx.ResolveEnv(app.SharedEnv)

	// Adicionar envs do usuário (--env flags)
	userEnvOverrides := parseUserEnvFlags(installEnv)
	for k, v := range userEnvOverrides {
		resolvedSharedEnv[k] = v
	}

	// Resolver user_env do app (nível stack)
	userEnvResolved := make(map[string]string)
	for _, ue := range app.UserEnv {
		value := tmplCtx.ResolveEnv(map[string]string{"val": ue.Default})["val"]
		resolvedSharedEnv[ue.Key] = value
		userEnvResolved[ue.Key] = value
	}

	// 5. Criar cada container da stack
	appConfig := storage.NewAppConfig(stackName, appID, installDomain, "")
	appConfig.IsStack = true
	appConfig.Database = dbName
	appConfig.SharedEnv = resolvedSharedEnv
	appConfig.Containers = make([]storage.ContainerConfig, 0, containerCount)

	var domainsCreated []string

	for i, container := range app.Containers {
		containerName := fmt.Sprintf("%s-%s", stackName, container.Name)

		// Determinar domínio do container
		containerDomain := ""
		if container.IsMain {
			containerDomain = installDomain
		} else if container.Traefik != nil && len(container.Traefik.Routes) > 0 {
			// Usar rota customizada do Traefik, resolvendo variáveis do shared_env
			subdomain := container.Traefik.Routes[0].Subdomain
			// Primeiro resolve templates básicos
			resolved := tmplCtx.ResolveEnv(map[string]string{"d": subdomain})["d"]
			// Depois resolve referências a variáveis do shared_env
			containerDomain = resolveEnvReferences(resolved, resolvedSharedEnv)
		}

		progress.Step(fmt.Sprintf("Iniciando container %d/%d: %s...", i+1, containerCount, container.Name))

		// Pull da imagem
		if err := dockerClient.PullImage(container.Image); err != nil {
			ui.Error(fmt.Sprintf("Erro ao baixar imagem %s: %s", container.Image, err.Error()))
			return err
		}

		// Merge envs: shared + container specific
		containerEnv := make(map[string]string)
		for k, v := range resolvedSharedEnv {
			containerEnv[k] = v
		}
		resolvedContainerEnv := tmplCtx.ResolveEnv(container.Env)
		for k, v := range resolvedContainerEnv {
			containerEnv[k] = v
		}

		// Resolver user_env do container
		for _, ue := range container.UserEnv {
			value := tmplCtx.ResolveEnv(map[string]string{"val": ue.Default})["val"]
			containerEnv[ue.Key] = value
			userEnvResolved[ue.Key] = value
		}

		// Resolver volumes
		resolvedVolumes := tmplCtx.ResolveVolumes(container.Volumes)

		// Configurar Traefik labels
		var labels map[string]string
		if containerDomain != "" && container.Port > 0 {
			labels = traefik.GenerateLabels(containerName, containerDomain, container.Port)
			domainsCreated = append(domainsCreated, containerDomain)
		}

		// Preparar command
		var command []string
		if container.Command != "" {
			command = strings.Fields(container.Command)
		}

		// Criar container
		containerCfg := &docker.ContainerConfig{
			Name:    containerName,
			Image:   container.Image,
			Env:     containerEnv,
			Volumes: resolvedVolumes,
			Labels:  labels,
			Command: command,
			Restart: "always",
		}

		containerID, err := dockerClient.CreateContainer(containerCfg)
		if err != nil {
			ui.Error(fmt.Sprintf("Erro ao criar container %s: %s", containerName, err.Error()))
			return err
		}

		if err := dockerClient.StartContainer(containerID); err != nil {
			ui.Error(fmt.Sprintf("Erro ao iniciar container %s: %s", containerName, err.Error()))
			return err
		}

		progress.SubStep(fmt.Sprintf("%s: rodando ✓", container.Name))

		// Salvar configuração do container
		appConfig.Containers = append(appConfig.Containers, storage.ContainerConfig{
			Name:        container.Name,
			ContainerID: containerID,
			Image:       container.Image,
			Domain:      containerDomain,
			Port:        container.Port,
			Command:     container.Command,
			Env:         containerEnv,
			Volumes:     resolvedVolumes,
			IsMain:      container.IsMain,
		})
	}

	// 6. Salvar configuração
	progress.Step("Salvando configuração...")
	if err := storage.SaveApp(appConfig); err != nil {
		ui.Error("Erro ao salvar configuração: " + err.Error())
		return err
	}

	// Sucesso
	ui.Success(fmt.Sprintf("Stack %s instalada com sucesso! (%d containers)", stackName, containerCount))

	// Mostrar credenciais
	printCredentials(app.UserEnv, userEnvResolved, installDomain)

	// Mostrar domínios criados
	if len(domainsCreated) > 0 {
		fmt.Printf("\n  %s Configure o DNS para:\n", ui.Yellow("⚠"))
		for _, d := range domainsCreated {
			fmt.Printf("     • %s → IP_DO_SERVIDOR\n", d)
		}
	}
	fmt.Println()

	return nil
}

// installSingle instala um app single-container (modo legado)
func installSingle(app *catalog.App, appID, stackName string) error {
	totalSteps := 7
	progress := ui.NewProgress(totalSteps)

	// 1. Buscar app no catálogo
	progress.Step(fmt.Sprintf("Buscando %s no catálogo...", appID))

	// 2. Conectar ao Docker
	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	// 3. Verificar e instalar dependências
	progress.Step("Verificando dependências...")
	secrets, err := storage.EnsureSecrets()
	if err != nil {
		ui.Error("Erro ao carregar secrets: " + err.Error())
		return err
	}

	if err := ensureDependencies(app.Dependencies, dockerClient, secrets, progress); err != nil {
		return err
	}

	// 4. Criar database se necessário
	dbName := ""
	for _, dep := range app.Dependencies {
		if dep == "postgres" {
			progress.Step("Criando database...")
			dbName = strings.ReplaceAll(stackName, "-", "_") + "_db"
			pgManager := services.NewPostgresManager(dockerClient, secrets)
			if err := pgManager.CreateDatabase(dbName); err != nil {
				ui.Error("Erro ao criar database: " + err.Error())
				return err
			}
			break
		}
	}
	if dbName == "" {
		progress.Step("Configurando app...")
	}

	// 5. Preparar envs
	progress.Step("Gerando configurações...")
	tmplCtx := catalog.NewTemplateContext(stackName, installDomain, secrets)

	// Verificar se há secrets de instalação anterior
	if storage.AppSecretsBackupExists(stackName) {
		backup, err := storage.LoadAppSecretsBackup(stackName)
		if err == nil && backup.CatalogApp == appID {
			tmplCtx.SetPreservedSecrets(backup.Secrets)
			progress.SubStep("Reutilizando secrets de instalação anterior")
		}
	}

	resolvedEnv := tmplCtx.ResolveEnv(app.Env)

	// Adicionar envs do usuário
	for k, v := range parseUserEnvFlags(installEnv) {
		resolvedEnv[k] = v
	}

	// Resolver user_env com defaults
	userEnvResolved := make(map[string]string)
	for _, ue := range app.UserEnv {
		value := tmplCtx.ResolveEnv(map[string]string{"val": ue.Default})["val"]
		resolvedEnv[ue.Key] = value
		userEnvResolved[ue.Key] = value
	}

	// 6. Configurar Traefik labels
	progress.Step(fmt.Sprintf("Configurando rota %s no Traefik...", installDomain))
	labels := traefik.GenerateLabels(stackName, installDomain, app.Port)

	// 7. Criar e iniciar container
	progress.Step("Iniciando container...")

	if err := dockerClient.PullImage(app.Image); err != nil {
		ui.Error("Erro ao baixar imagem: " + err.Error())
		return err
	}

	resolvedVolumes := tmplCtx.ResolveVolumes(app.Volumes)

	var command []string
	if app.Command != "" {
		command = strings.Fields(app.Command)
	}

	containerCfg := &docker.ContainerConfig{
		Name:    stackName,
		Image:   app.Image,
		Env:     resolvedEnv,
		Volumes: resolvedVolumes,
		Labels:  labels,
		Command: command,
		Restart: "always",
	}

	containerID, err := dockerClient.CreateContainer(containerCfg)
	if err != nil {
		ui.Error("Erro ao criar container: " + err.Error())
		return err
	}

	if err := dockerClient.StartContainer(containerID); err != nil {
		ui.Error("Erro ao iniciar container: " + err.Error())
		return err
	}

	// Salvar configuração do app
	appConfig := storage.NewAppConfig(stackName, appID, installDomain, app.Image)
	appConfig.ContainerID = containerID
	appConfig.Database = dbName
	appConfig.Env = resolvedEnv
	appConfig.Volumes = resolvedVolumes
	appConfig.Command = app.Command
	appConfig.Port = app.Port

	if err := storage.SaveApp(appConfig); err != nil {
		ui.Error("Erro ao salvar configuração: " + err.Error())
		return err
	}

	// Sucesso
	ui.Success(fmt.Sprintf("%s instalado com sucesso!", stackName))

	// Mostrar credenciais
	printCredentials(app.UserEnv, userEnvResolved, installDomain)

	fmt.Printf("  %s Configure o DNS: %s → IP_DO_SERVIDOR\n", ui.Yellow("⚠"), installDomain)
	fmt.Println()

	return nil
}

// ensureDependencies verifica e instala dependências (postgres, redis)
func ensureDependencies(deps []string, dockerClient *docker.Client, secrets *storage.SystemSecrets, progress *ui.Progress) error {
	for _, dep := range deps {
		switch dep {
		case "postgres":
			pgManager := services.NewPostgresManager(dockerClient, secrets)
			running, _ := pgManager.IsRunning()
			if !running {
				progress.SubStep("postgres: não encontrado, instalando...")
				if err := pgManager.EnsureRunning(); err != nil {
					ui.Error("Erro ao iniciar Postgres: " + err.Error())
					return err
				}
			} else {
				progress.SubStep("postgres: rodando ✓")
			}
		case "redis":
			redisManager := services.NewRedisManager(dockerClient)
			running, _ := redisManager.IsRunning()
			if !running {
				progress.SubStep("redis: não encontrado, instalando...")
				if err := redisManager.EnsureRunning(); err != nil {
					ui.Error("Erro ao iniciar Redis: " + err.Error())
					return err
				}
			} else {
				progress.SubStep("redis: rodando ✓")
			}
		}
	}
	return nil
}

// parseUserEnvFlags converte --env KEY=VALUE em map
func parseUserEnvFlags(envFlags []string) map[string]string {
	result := make(map[string]string)
	for _, e := range envFlags {
		parts := strings.SplitN(e, "=", 2)
		if len(parts) == 2 {
			result[parts[0]] = parts[1]
		}
	}
	return result
}

// printCredentials exibe credenciais de acesso
func printCredentials(userEnvDefs []catalog.UserEnvVar, userEnvResolved map[string]string, domain string) {
	user := ""
	pass := ""
	for _, ue := range userEnvDefs {
		if strings.Contains(strings.ToLower(ue.Key), "user") {
			user = userEnvResolved[ue.Key]
		}
		if strings.Contains(strings.ToLower(ue.Key), "password") || strings.Contains(strings.ToLower(ue.Key), "pass") {
			pass = userEnvResolved[ue.Key]
		}
	}

	ui.PrintCredentials("https://"+domain, user, pass)

	if user != "" || pass != "" {
		fmt.Printf("  %s Credenciais salvas. Ver novamente: %s\n", ui.Yellow("💡"), ui.Cyan("hostfy secrets <nome>"))
	}
}

// resolveEnvReferences resolve referências a variáveis {{VAR}} usando um map de env
func resolveEnvReferences(value string, env map[string]string) string {
	re := regexp.MustCompile(`\{\{([^}]+)\}\}`)
	return re.ReplaceAllStringFunc(value, func(match string) string {
		key := strings.Trim(match, "{}")
		if val, ok := env[key]; ok {
			return val
		}
		return match
	})
}
