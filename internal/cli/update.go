package cli

import (
	"fmt"
	"strings"

	"github.com/hostfy/cli/internal/docker"
	"github.com/hostfy/cli/internal/storage"
	"github.com/hostfy/cli/internal/traefik"
	"github.com/hostfy/cli/internal/ui"
	"github.com/spf13/cobra"
)

var updateCmd = &cobra.Command{
	Use:   "update <app>",
	Short: "Atualiza configurações de um app instalado",
	Long:  `Altera variáveis de ambiente ou domínio de um app já instalado.`,
	Args:  cobra.ExactArgs(1),
	RunE:  runUpdate,
}

var (
	updateEnv    []string
	updateDomain string
)

func init() {
	updateCmd.Flags().StringSliceVar(&updateEnv, "env", []string{}, "Variáveis de ambiente para alterar (KEY=VALUE)")
	updateCmd.Flags().StringVar(&updateDomain, "domain", "", "Novo domínio")
}

func runUpdate(cmd *cobra.Command, args []string) error {
	appName := args[0]

	// Carregar config do app
	appConfig, err := storage.LoadApp(appName)
	if err != nil {
		ui.Error(fmt.Sprintf("App '%s' não encontrado", appName))
		return err
	}

	if len(updateEnv) == 0 && updateDomain == "" {
		ui.Warning("Nenhuma alteração especificada. Use --env ou --domain")
		return nil
	}

	progress := ui.NewProgress(3)

	// 1. Aplicar alterações
	progress.Step("Atualizando configuração...")

	changes := []string{}

	// Atualizar envs
	for _, e := range updateEnv {
		parts := strings.SplitN(e, "=", 2)
		if len(parts) == 2 {
			appConfig.Env[parts[0]] = parts[1]
			changes = append(changes, fmt.Sprintf("%s = %s", parts[0], parts[1]))
		}
	}

	// Atualizar domínio
	oldDomain := appConfig.Domain
	if updateDomain != "" && updateDomain != appConfig.Domain {
		appConfig.Domain = updateDomain
		changes = append(changes, fmt.Sprintf("domain: %s → %s", oldDomain, updateDomain))
	}

	// 2. Recriar container com novas configs
	progress.Step("Aplicando alterações...")

	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	// Parar e remover container antigo
	dockerClient.StopContainer(appName)
	dockerClient.RemoveContainer(appName, true)

	// Buscar info do catálogo para port
	catalogApp, _ := storage.LoadApp(appName)
	port := 80 // default
	if catalogApp != nil {
		// Tentar obter port do catálogo
		// Por enquanto usar 80 como fallback
	}

	// Gerar novos labels
	labels := traefik.GenerateLabels(appName, appConfig.Domain, port)

	// Recriar container
	containerCfg := &docker.ContainerConfig{
		Name:    appName,
		Image:   appConfig.Image,
		Env:     appConfig.Env,
		Labels:  labels,
		Restart: "always",
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

	appConfig.ContainerID = containerID

	// 3. Salvar nova config
	progress.Step("Salvando configuração...")
	if err := storage.SaveApp(appConfig); err != nil {
		ui.Error("Erro ao salvar configuração: " + err.Error())
		return err
	}

	ui.Success(fmt.Sprintf("%s atualizado!", appName))

	fmt.Println()
	fmt.Println("  Alterações:")
	for _, c := range changes {
		fmt.Printf("    %s %s\n", ui.Green("•"), c)
	}
	fmt.Println()

	if updateDomain != "" {
		fmt.Printf("  %s Atualize o DNS: %s → IP_DO_SERVIDOR\n", ui.Yellow("⚠"), updateDomain)
		fmt.Println()
	}

	return nil
}
