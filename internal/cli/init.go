package cli

import (
	"github.com/hostfy/cli/internal/docker"
	"github.com/hostfy/cli/internal/storage"
	"github.com/hostfy/cli/internal/traefik"
	"github.com/hostfy/cli/internal/ui"
	"github.com/spf13/cobra"
)

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Inicializa o hostfy no servidor",
	Long:  `Configura o hostfy, cria a rede Docker e inicia o Traefik.`,
	RunE:  runInit,
}

var (
	initCatalogURL string
)

func init() {
	initCmd.Flags().StringVar(&initCatalogURL, "catalog-url", "", "URL customizada do catálogo")
}

func runInit(cmd *cobra.Command, args []string) error {
	progress := ui.NewProgress(4)

	// 1. Criar diretórios e config
	progress.Step("Criando configuração...")
	if err := storage.EnsureDirectories(); err != nil {
		ui.Error("Erro ao criar diretórios: " + err.Error())
		return err
	}

	cfg, err := storage.LoadConfig()
	if err != nil {
		ui.Error("Erro ao carregar config: " + err.Error())
		return err
	}

	if initCatalogURL != "" {
		cfg.CatalogURL = initCatalogURL
	}

	if err := storage.SaveConfig(cfg); err != nil {
		ui.Error("Erro ao salvar config: " + err.Error())
		return err
	}

	// 2. Gerar secrets
	progress.Step("Gerando secrets do sistema...")
	_, err = storage.EnsureSecrets()
	if err != nil {
		ui.Error("Erro ao gerar secrets: " + err.Error())
		return err
	}

	// 3. Criar rede Docker
	progress.Step("Configurando rede Docker...")
	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	if err := dockerClient.EnsureNetwork(); err != nil {
		ui.Error("Erro ao criar rede: " + err.Error())
		return err
	}

	// 4. Iniciar Traefik
	progress.Step("Iniciando Traefik...")
	traefikManager := traefik.NewManager(dockerClient)
	if err := traefikManager.Start(); err != nil {
		ui.Error("Erro ao iniciar Traefik: " + err.Error())
		return err
	}

	ui.Success("hostfy inicializado com sucesso!")
	ui.PrintBox("Próximos passos", []string{
		"1. Veja apps disponíveis:",
		"   hostfy catalog",
		"",
		"2. Instale seu primeiro app:",
		"   hostfy install n8n --domain n8n.seudominio.com",
		"",
		"3. Configure o DNS na Cloudflare apontando para este servidor",
	})

	return nil
}
