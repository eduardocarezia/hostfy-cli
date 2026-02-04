package cli

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/eduardocarezia/hostfy-cli/internal/catalog"
	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/services"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/traefik"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var upgradeCmd = &cobra.Command{
	Use:   "upgrade [stack]",
	Short: "Atualiza o CLI ou uma stack instalada",
	Long: `Sem argumentos: atualiza o hostfy CLI para a versão mais recente.
Com argumento: atualiza uma stack instalada para a versão mais recente do catálogo.

Exemplos:
  hostfy upgrade          # Atualiza o CLI
  hostfy upgrade n8n      # Atualiza a stack n8n`,
	RunE: runUpgrade,
}

var (
	upgradeForce bool
)

const (
	githubRepo = "eduardocarezia/hostfy-cli"
	versionURL = "https://raw.githubusercontent.com/eduardocarezia/hostfy-cli/main/VERSION"
)

func init() {
	upgradeCmd.Flags().BoolVar(&upgradeForce, "force", false, "Força a atualização mesmo se já estiver na última versão")
}

func runUpgrade(cmd *cobra.Command, args []string) error {
	// Se tiver argumento, atualiza a stack
	if len(args) > 0 {
		return runUpgradeStack(args[0])
	}

	// Sem argumentos, atualiza o CLI
	return runUpgradeCLI()
}

// runUpgradeStack atualiza uma stack instalada
func runUpgradeStack(stackName string) error {
	// Carregar config da stack
	appConfig, err := storage.LoadApp(stackName)
	if err != nil {
		ui.Error(fmt.Sprintf("Stack '%s' não encontrada", stackName))
		return err
	}

	progress := ui.NewProgress(5)

	// 1. Buscar catálogo atualizado
	progress.Step("Buscando catálogo atualizado...")
	_, err = catalog.Fetch(true)
	if err != nil {
		ui.Error("Erro ao atualizar catálogo: " + err.Error())
		return err
	}
	progress.SubStep("Catálogo atualizado!")

	// 2. Buscar app no catálogo
	progress.Step("Comparando versões...")
	catalogApp, err := catalog.GetApp(appConfig.CatalogApp)
	if err != nil {
		ui.Error("Stack não encontrada no catálogo: " + err.Error())
		return err
	}

	// Conectar ao Docker
	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	// Verificar se é stack multi-container ou single-container
	if appConfig.IsStack && len(appConfig.Containers) > 0 {
		return upgradeMultiContainer(progress, dockerClient, appConfig, catalogApp)
	}

	return upgradeSingleContainer(progress, dockerClient, appConfig, catalogApp)
}

// upgradeSingleContainer atualiza um app single-container
func upgradeSingleContainer(progress *ui.Progress, dockerClient *docker.Client, appConfig *storage.AppConfig, catalogApp *catalog.App) error {
	oldImage := appConfig.Image
	newImage := catalogApp.Image
	imageChanged := oldImage != newImage

	if imageChanged {
		progress.SubStep(fmt.Sprintf("Nova imagem: %s", newImage))
		progress.SubStep(fmt.Sprintf("Atual: %s", oldImage))
	} else if !upgradeForce {
		progress.SubStep("Imagem já está atualizada")
		ui.Success(fmt.Sprintf("%s já está na versão mais recente!", appConfig.Name))
		return nil
	}

	// Identificar novas envs do catálogo
	secrets, _ := storage.EnsureSecrets()
	tmplCtx := catalog.NewTemplateContext(appConfig.Name, appConfig.Domain, secrets)
	newEnvs := tmplCtx.ResolveEnv(catalogApp.Env)

	addedEnvs := []string{}
	for key, value := range newEnvs {
		if _, exists := appConfig.Env[key]; !exists {
			appConfig.Env[key] = value
			addedEnvs = append(addedEnvs, key)
		}
	}

	if len(addedEnvs) > 0 {
		for _, e := range addedEnvs {
			progress.SubStep(fmt.Sprintf("Nova env: %s", e))
		}
	}

	// 3. Baixar nova imagem
	progress.Step("Baixando nova imagem...")
	if err := dockerClient.PullImage(newImage); err != nil {
		ui.Error("Erro ao baixar imagem: " + err.Error())
		return err
	}

	// 4. Parar e recriar container
	progress.Step("Recriando container...")
	dockerClient.StopContainer(appConfig.Name)
	dockerClient.RemoveContainer(appConfig.Name, true)

	// Usar port salvo na config do app
	port := appConfig.Port
	if port == 0 {
		port = catalogApp.Port
	}

	// Gerar novos labels
	labels := traefik.GenerateLabels(appConfig.Name, appConfig.Domain, port)

	// Recriar container
	containerCfg := &docker.ContainerConfig{
		Name:    appConfig.Name,
		Image:   newImage,
		Env:     appConfig.Env,
		Labels:  labels,
		Volumes: appConfig.Volumes,
		Restart: "always",
	}

	if appConfig.Command != "" {
		containerCfg.Command = parseCommand(appConfig.Command)
	}

	containerID, err := dockerClient.CreateContainer(containerCfg)
	if err != nil {
		ui.Error("Erro ao recriar container: " + err.Error())
		return err
	}

	if err := dockerClient.StartContainer(containerID); err != nil {
		ui.Error("Erro ao iniciar container: " + err.Error())
		return err
	}

	// 5. Salvar config atualizada
	progress.Step("Salvando configuração...")
	appConfig.Image = newImage
	appConfig.ContainerID = containerID
	appConfig.ImagePulledAt = time.Now().UTC().Format(time.RFC3339)
	if err := storage.SaveApp(appConfig); err != nil {
		ui.Warning("Erro ao salvar configuração: " + err.Error())
	}

	ui.Success(fmt.Sprintf("%s atualizado!", appConfig.Name))

	fmt.Println()
	if imageChanged {
		fmt.Printf("  %s Imagem: %s → %s\n", ui.Green("•"), oldImage, newImage)
	}
	if len(addedEnvs) > 0 {
		fmt.Printf("  %s Configs adicionadas: %v\n", ui.Green("•"), addedEnvs)
	}
	fmt.Printf("  %s Suas customizações foram preservadas\n", ui.Green("•"))
	fmt.Println()

	return nil
}

// upgradeMultiContainer atualiza uma stack com múltiplos containers
func upgradeMultiContainer(progress *ui.Progress, dockerClient *docker.Client, appConfig *storage.AppConfig, catalogApp *catalog.App) error {
	// Mapear containers do catálogo por nome
	catalogContainers := make(map[string]*catalog.Container)
	for i := range catalogApp.Containers {
		catalogContainers[catalogApp.Containers[i].Name] = &catalogApp.Containers[i]
	}

	// Verificar imagens que mudaram
	imagesToUpdate := []struct {
		name     string
		oldImage string
		newImage string
		index    int
	}{}

	for i, container := range appConfig.Containers {
		if catContainer, ok := catalogContainers[container.Name]; ok {
			if container.Image != catContainer.Image {
				imagesToUpdate = append(imagesToUpdate, struct {
					name     string
					oldImage string
					newImage string
					index    int
				}{
					name:     container.Name,
					oldImage: container.Image,
					newImage: catContainer.Image,
					index:    i,
				})
			}
		}
	}

	if len(imagesToUpdate) == 0 && !upgradeForce {
		progress.SubStep("Todas as imagens já estão atualizadas")
		ui.Success(fmt.Sprintf("%s já está na versão mais recente!", appConfig.Name))
		return nil
	}

	for _, img := range imagesToUpdate {
		progress.SubStep(fmt.Sprintf("%s: %s → %s", img.name, img.oldImage, img.newImage))
	}

	// Identificar novas envs compartilhadas
	secrets, _ := storage.EnsureSecrets()
	tmplCtx := catalog.NewTemplateContext(appConfig.Name, appConfig.Domain, secrets)
	newSharedEnvs := tmplCtx.ResolveEnv(catalogApp.SharedEnv)

	addedEnvs := []string{}
	if appConfig.SharedEnv == nil {
		appConfig.SharedEnv = make(map[string]string)
	}
	for key, value := range newSharedEnvs {
		if _, exists := appConfig.SharedEnv[key]; !exists {
			appConfig.SharedEnv[key] = value
			addedEnvs = append(addedEnvs, key)
		}
	}

	if len(addedEnvs) > 0 {
		for _, e := range addedEnvs {
			progress.SubStep(fmt.Sprintf("Nova env compartilhada: %s", e))
		}
	}

	// 3. Baixar novas imagens
	progress.Step("Baixando novas imagens...")
	for _, img := range imagesToUpdate {
		progress.SubStep(fmt.Sprintf("Baixando %s...", img.newImage))
		if err := dockerClient.PullImage(img.newImage); err != nil {
			ui.Error(fmt.Sprintf("Erro ao baixar %s: %s", img.newImage, err.Error()))
			return err
		}
	}

	// Se --force mas sem imagens para atualizar, baixar todas as imagens
	if len(imagesToUpdate) == 0 && upgradeForce {
		for i, container := range appConfig.Containers {
			if catContainer, ok := catalogContainers[container.Name]; ok {
				progress.SubStep(fmt.Sprintf("Baixando %s...", catContainer.Image))
				if err := dockerClient.PullImage(catContainer.Image); err != nil {
					ui.Warning(fmt.Sprintf("Erro ao baixar %s: %s", catContainer.Image, err.Error()))
				}
				appConfig.Containers[i].Image = catContainer.Image
			}
		}
	}

	// 4. Recriar containers que mudaram
	progress.Step("Recriando containers...")
	for _, img := range imagesToUpdate {
		containerConfig := &appConfig.Containers[img.index]
		fullName := fmt.Sprintf("%s_%s", appConfig.Name, containerConfig.Name)

		progress.SubStep(fmt.Sprintf("Recriando %s...", containerConfig.Name))

		// Parar e remover
		dockerClient.StopContainer(fullName)
		dockerClient.RemoveContainer(fullName, true)

		// Buscar config do catálogo
		catContainer := catalogContainers[containerConfig.Name]

		// Merge de envs: shared + container específico
		mergedEnv := make(map[string]string)
		for k, v := range appConfig.SharedEnv {
			mergedEnv[k] = v
		}
		if containerConfig.Env != nil {
			for k, v := range containerConfig.Env {
				mergedEnv[k] = v
			}
		}

		// Gerar labels se tiver domínio
		var labels map[string]string
		if containerConfig.Domain != "" && containerConfig.Port > 0 {
			labels = traefik.GenerateLabels(fullName, containerConfig.Domain, containerConfig.Port)
		}

		// Criar container
		cfg := &docker.ContainerConfig{
			Name:    fullName,
			Image:   img.newImage,
			Env:     mergedEnv,
			Labels:  labels,
			Volumes: containerConfig.Volumes,
			Restart: "always",
		}

		if containerConfig.Command != "" {
			cfg.Command = parseCommand(containerConfig.Command)
		}

		containerID, err := dockerClient.CreateContainer(cfg)
		if err != nil {
			ui.Error(fmt.Sprintf("Erro ao criar %s: %s", fullName, err.Error()))
			return err
		}

		if err := dockerClient.StartContainer(containerID); err != nil {
			ui.Error(fmt.Sprintf("Erro ao iniciar %s: %s", fullName, err.Error()))
			return err
		}

		// Atualizar config
		appConfig.Containers[img.index].Image = img.newImage
		appConfig.Containers[img.index].ContainerID = containerID

		// Aguardar container ficar pronto
		if catContainer.IsMain {
			dockerClient.WaitForHealthy(fullName, 30*time.Second)
		}
	}

	// 5. Salvar config atualizada
	progress.Step("Salvando configuração...")
	appConfig.ImagePulledAt = time.Now().UTC().Format(time.RFC3339)
	if err := storage.SaveApp(appConfig); err != nil {
		ui.Warning("Erro ao salvar configuração: " + err.Error())
	}

	ui.Success(fmt.Sprintf("%s atualizado!", appConfig.Name))

	fmt.Println()
	if len(imagesToUpdate) > 0 {
		fmt.Println("  Imagens atualizadas:")
		for _, img := range imagesToUpdate {
			fmt.Printf("    %s %s: %s → %s\n", ui.Green("•"), img.name, img.oldImage, img.newImage)
		}
	}
	if len(addedEnvs) > 0 {
		fmt.Printf("  %s Configs adicionadas: %v\n", ui.Green("•"), addedEnvs)
	}
	fmt.Printf("  %s Suas customizações foram preservadas\n", ui.Green("•"))
	fmt.Println()

	return nil
}

// runUpgradeCLI atualiza o próprio CLI
func runUpgradeCLI() error {
	progress := ui.NewProgress(5)

	// 1. Verificar versão atual
	progress.Step("Verificando versão atual...")
	currentVersion := Version
	if currentVersion == "" {
		currentVersion = "dev"
	}
	progress.SubStep(fmt.Sprintf("Versão atual: %s", currentVersion))

	// 2. Buscar última versão
	progress.Step("Buscando última versão...")
	latestVersion, err := getLatestVersion()
	if err != nil {
		progress.SubStep("Não foi possível verificar versão remota, continuando...")
		latestVersion = "latest"
	} else {
		latestVersion = strings.TrimSpace(latestVersion)
		progress.SubStep(fmt.Sprintf("Última versão: %s", latestVersion))

		// Verificar se precisa atualizar
		if !upgradeForce && currentVersion == latestVersion {
			ui.Success("Você já está na versão mais recente!")
			return nil
		}
	}

	// 3. Verificar se Go está instalado
	progress.Step("Verificando Go...")
	goPath, err := findGo()
	if err != nil {
		ui.Error("Go não encontrado. Instale Go ou use o script de instalação:")
		fmt.Println("  curl -fsSL https://raw.githubusercontent.com/eduardocarezia/hostfy-cli/main/scripts/install.sh | sudo bash")
		return err
	}
	progress.SubStep(fmt.Sprintf("Go encontrado: %s", goPath))

	// 4. Clonar e compilar
	progress.Step("Baixando e compilando...")

	tmpDir, err := os.MkdirTemp("", "hostfy-upgrade-*")
	if err != nil {
		ui.Error("Erro ao criar diretório temporário: " + err.Error())
		return err
	}
	defer os.RemoveAll(tmpDir)

	// Clone
	progress.SubStep("Clonando repositório...")
	cloneCmd := exec.Command("git", "clone", "--depth", "1", fmt.Sprintf("https://github.com/%s.git", githubRepo), tmpDir)
	if output, err := cloneCmd.CombinedOutput(); err != nil {
		ui.Error("Erro ao clonar: " + string(output))
		return err
	}

	// Go mod tidy
	progress.SubStep("Resolvendo dependências...")
	tidyCmd := exec.Command(goPath, "mod", "tidy")
	tidyCmd.Dir = tmpDir
	if output, err := tidyCmd.CombinedOutput(); err != nil {
		ui.Error("Erro ao resolver dependências: " + string(output))
		return err
	}

	// Build
	progress.SubStep("Compilando...")
	newBinary := filepath.Join(tmpDir, "hostfy-new")
	buildCmd := exec.Command(goPath, "build", "-ldflags", "-s -w", "-o", newBinary, "./cmd/hostfy")
	buildCmd.Dir = tmpDir
	if output, err := buildCmd.CombinedOutput(); err != nil {
		ui.Error("Erro ao compilar: " + string(output))
		return err
	}

	// 5. Instalar
	progress.Step("Instalando...")

	execPath, err := os.Executable()
	if err != nil {
		ui.Error("Erro ao obter caminho do executável: " + err.Error())
		return err
	}

	// Backup do binário atual
	backupPath := execPath + ".backup"
	if err := os.Rename(execPath, backupPath); err != nil {
		ui.Error("Erro ao criar backup: " + err.Error())
		return err
	}

	// Copiar novo binário
	if err := copyFile(newBinary, execPath); err != nil {
		os.Rename(backupPath, execPath)
		ui.Error("Erro ao instalar: " + err.Error())
		return err
	}

	// Dar permissão de execução
	if err := os.Chmod(execPath, 0755); err != nil {
		os.Rename(backupPath, execPath)
		ui.Error("Erro ao definir permissões: " + err.Error())
		return err
	}

	// Remover backup
	os.Remove(backupPath)

	ui.Success(fmt.Sprintf("Atualizado de %s para %s!", currentVersion, latestVersion))
	fmt.Println()
	fmt.Printf("  %s Execute 'hostfy version' para confirmar\n", ui.Green("✓"))
	fmt.Println()

	// Executar migrações pós-upgrade
	if err := runPostUpgradeMigrations(); err != nil {
		ui.Warning("Algumas migrações falharam: " + err.Error())
	}

	return nil
}

func getLatestVersion() (string, error) {
	resp, err := http.Get(versionURL)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("não foi possível obter versão: status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	return string(body), nil
}

func findGo() (string, error) {
	// Tentar encontrar go no PATH
	if path, err := exec.LookPath("go"); err == nil {
		return path, nil
	}

	// Tentar caminho padrão do install.sh
	defaultPath := "/usr/local/go/bin/go"
	if _, err := os.Stat(defaultPath); err == nil {
		return defaultPath, nil
	}

	return "", fmt.Errorf("go não encontrado")
}

func copyFile(src, dst string) error {
	source, err := os.Open(src)
	if err != nil {
		return err
	}
	defer source.Close()

	dest, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer dest.Close()

	_, err = io.Copy(dest, source)
	return err
}

// runPostUpgradeMigrations executa correções necessárias após upgrade da CLI
func runPostUpgradeMigrations() error {
	fmt.Println()
	ui.Info("Verificando migrações necessárias...")

	dockerClient, err := docker.NewClient()
	if err != nil {
		return fmt.Errorf("erro ao conectar ao Docker: %w", err)
	}
	defer dockerClient.Close()

	// Garantir que a rede existe
	if err := dockerClient.EnsureNetwork(); err != nil {
		return fmt.Errorf("erro ao criar rede: %w", err)
	}

	migrationsRan := false

	// Migração: Corrigir Redis na rede errada ou com configuração READONLY
	if migrated, err := migrateRedisNetwork(dockerClient); err != nil {
		ui.Warning("Erro ao migrar Redis: " + err.Error())
	} else if migrated {
		migrationsRan = true
	}

	// Migração: Corrigir Postgres na rede errada
	if migrated, err := migratePostgresNetwork(dockerClient); err != nil {
		ui.Warning("Erro ao migrar Postgres: " + err.Error())
	} else if migrated {
		migrationsRan = true
	}

	if migrationsRan {
		fmt.Println()
		ui.Success("Migrações concluídas!")

		// Reiniciar stacks que dependem do Redis/Postgres
		restartDependentStacks(dockerClient)
	} else {
		fmt.Printf("  %s Nenhuma migração necessária\n", ui.Green("✓"))
	}

	return nil
}

// migrateRedisNetwork verifica e corrige o container Redis
func migrateRedisNetwork(dockerClient *docker.Client) (bool, error) {
	containerName := services.RedisContainerName

	exists, err := dockerClient.ContainerExists(containerName)
	if err != nil || !exists {
		return false, nil // Redis não existe, nada a fazer
	}

	// Verificar se está na rede correta
	needsNetworkMigration, err := dockerClient.ContainerNeedsNetworkMigration(containerName, docker.NetworkName)
	if err != nil {
		return false, err
	}

	// Verificar se o Redis tem o comando bugado --replicaof
	needsCommandFix, err := dockerClient.ContainerHasBuggyCommand(containerName, "--replicaof")
	if err != nil {
		return false, err
	}

	if !needsNetworkMigration && !needsCommandFix {
		return false, nil
	}

	reason := ""
	if needsNetworkMigration && needsCommandFix {
		reason = "rede incorreta e comando --replicaof bugado"
	} else if needsNetworkMigration {
		reason = "rede incorreta"
	} else {
		reason = "comando --replicaof bugado (causa READONLY)"
	}

	fmt.Printf("  %s Migrando Redis (%s)...\n", ui.Yellow("→"), reason)

	// Parar e remover container antigo
	dockerClient.StopContainer(containerName)
	dockerClient.RemoveContainer(containerName, false) // false = manter volumes

	// Recriar com configuração correta
	redisManager := services.NewRedisManager(dockerClient)

	if err := redisManager.EnsureRunning(); err != nil {
		return false, fmt.Errorf("erro ao recriar Redis: %w", err)
	}

	fmt.Printf("  %s Redis migrado com sucesso!\n", ui.Green("✓"))
	return true, nil
}

// migratePostgresNetwork verifica e corrige o container Postgres
func migratePostgresNetwork(dockerClient *docker.Client) (bool, error) {
	containerName := services.PostgresContainerName

	exists, err := dockerClient.ContainerExists(containerName)
	if err != nil || !exists {
		return false, nil // Postgres não existe, nada a fazer
	}

	// Verificar se está na rede correta
	needsMigration, err := dockerClient.ContainerNeedsNetworkMigration(containerName, docker.NetworkName)
	if err != nil {
		return false, err
	}

	if !needsMigration {
		return false, nil
	}

	fmt.Printf("  %s Migrando Postgres para rede %s...\n", ui.Yellow("→"), docker.NetworkName)

	// Parar e remover container antigo
	dockerClient.StopContainer(containerName)
	dockerClient.RemoveContainer(containerName, false) // false = manter volumes

	// Recriar com configuração correta
	secrets, _ := storage.EnsureSecrets()
	postgresManager := services.NewPostgresManager(dockerClient, secrets)

	if err := postgresManager.EnsureRunning(); err != nil {
		return false, fmt.Errorf("erro ao recriar Postgres: %w", err)
	}

	fmt.Printf("  %s Postgres migrado com sucesso!\n", ui.Green("✓"))
	return true, nil
}

// restartDependentStacks reinicia todas as stacks instaladas que dependem de Redis/Postgres
func restartDependentStacks(dockerClient *docker.Client) {
	fmt.Println()
	ui.Info("Reiniciando stacks afetadas...")

	// Listar todas as apps instaladas
	apps, err := storage.ListApps()
	if err != nil {
		ui.Warning("Erro ao listar apps: " + err.Error())
		return
	}

	restarted := 0
	for _, appConfig := range apps {
		// Verificar se a app usa Redis ou Postgres (checando as envs)
		usesRedis := false
		usesPostgres := false

		// Verificar em Env (single container)
		for _, value := range appConfig.Env {
			if strings.Contains(value, "hostfy_redis") || strings.Contains(value, "redis://") {
				usesRedis = true
			}
			if strings.Contains(value, "hostfy_postgres") || strings.Contains(value, "postgresql://") {
				usesPostgres = true
			}
		}

		// Verificar em SharedEnv (multi-container stack)
		for _, value := range appConfig.SharedEnv {
			if strings.Contains(value, "hostfy_redis") || strings.Contains(value, "redis://") {
				usesRedis = true
			}
			if strings.Contains(value, "hostfy_postgres") || strings.Contains(value, "postgresql://") {
				usesPostgres = true
			}
		}

		if !usesRedis && !usesPostgres {
			continue
		}

		fmt.Printf("  %s Reiniciando %s...\n", ui.Yellow("→"), appConfig.Name)

		// Reiniciar containers da stack
		if appConfig.IsStack && len(appConfig.Containers) > 0 {
			for _, cont := range appConfig.Containers {
				containerName := appConfig.Name + "-" + cont.Name
				dockerClient.RestartContainer(containerName)
			}
		} else {
			dockerClient.RestartContainer(appConfig.Name)
		}

		restarted++
		fmt.Printf("  %s %s reiniciado!\n", ui.Green("✓"), appConfig.Name)
	}

	if restarted > 0 {
		fmt.Println()
		ui.Success(fmt.Sprintf("%d stack(s) reiniciada(s)!", restarted))
	}
}
