package cli

import (
	"fmt"
	"strings"

	"github.com/hostfy/cli/internal/catalog"
	"github.com/hostfy/cli/internal/docker"
	"github.com/hostfy/cli/internal/services"
	"github.com/hostfy/cli/internal/storage"
	"github.com/hostfy/cli/internal/traefik"
	"github.com/hostfy/cli/internal/ui"
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

	// Calcular steps
	totalSteps := 7
	progress := ui.NewProgress(totalSteps)

	// 1. Buscar app no catálogo
	progress.Step(fmt.Sprintf("Buscando %s no catálogo...", appID))
	app, err := catalog.GetApp(appID)
	if err != nil {
		ui.Error(err.Error())
		return err
	}

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

	for _, dep := range app.Dependencies {
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
	resolvedEnv := tmplCtx.ResolveEnv(app.Env)

	// Adicionar envs do usuário
	for _, e := range installEnv {
		parts := strings.SplitN(e, "=", 2)
		if len(parts) == 2 {
			resolvedEnv[parts[0]] = parts[1]
		}
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

	if err := storage.SaveApp(appConfig); err != nil {
		ui.Error("Erro ao salvar configuração: " + err.Error())
		return err
	}

	// Sucesso
	ui.Success(fmt.Sprintf("%s instalado com sucesso!", stackName))

	// Mostrar credenciais
	user := ""
	pass := ""
	for _, ue := range app.UserEnv {
		if strings.Contains(strings.ToLower(ue.Key), "user") {
			user = userEnvResolved[ue.Key]
		}
		if strings.Contains(strings.ToLower(ue.Key), "password") || strings.Contains(strings.ToLower(ue.Key), "pass") {
			pass = userEnvResolved[ue.Key]
		}
	}

	ui.PrintCredentials("https://"+installDomain, user, pass)

	if user != "" || pass != "" {
		fmt.Printf("  %s Credenciais salvas. Ver novamente: %s\n", ui.Yellow("💡"), ui.Cyan("hostfy secrets "+stackName))
	}
	fmt.Printf("  %s Configure o DNS: %s → IP_DO_SERVIDOR\n", ui.Yellow("⚠"), installDomain)
	fmt.Println()

	return nil
}
