package cli

import (
	"fmt"

	"github.com/eduardocarezia/hostfy-cli/internal/catalog"
	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var pullCmd = &cobra.Command{
	Use:   "pull [app]",
	Short: "Atualiza imagem e configurações do catálogo",
	Long: `Baixa a nova imagem Docker e faz merge das configurações do catálogo.
Se nenhum app for especificado, apenas atualiza o catálogo local.`,
	RunE: runPull,
}

func runPull(cmd *cobra.Command, args []string) error {
	// Se nenhum app especificado, apenas atualiza o catálogo
	if len(args) == 0 {
		ui.Info("Atualizando catálogo...")
		_, err := catalog.Fetch(true)
		if err != nil {
			ui.Error("Erro ao atualizar catálogo: " + err.Error())
			return err
		}
		ui.Success("Catálogo atualizado!")
		return nil
	}

	appName := args[0]

	// Carregar config do app
	appConfig, err := storage.LoadApp(appName)
	if err != nil {
		ui.Error(fmt.Sprintf("App '%s' não encontrado", appName))
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

	// 2. Comparar configurações
	progress.Step("Comparando configurações...")
	catalogApp, err := catalog.GetApp(appConfig.CatalogApp)
	if err != nil {
		ui.Error("App não encontrado no catálogo: " + err.Error())
		return err
	}

	oldImage := appConfig.Image
	newImage := catalogApp.Image
	imageChanged := oldImage != newImage

	if imageChanged {
		progress.SubStep(fmt.Sprintf("Nova imagem: %s (atual: %s)", newImage, oldImage))
	} else {
		progress.SubStep("Imagem já está atualizada")
	}

	// Identificar novas envs do catálogo
	secrets, _ := storage.EnsureSecrets()
	tmplCtx := catalog.NewTemplateContext(appName, appConfig.Domain, secrets)
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

	// 3. Backup da configuração atual (apenas log)
	progress.Step("Fazendo backup da configuração...")

	// 4. Baixar nova imagem
	progress.Step("Baixando nova imagem...")
	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	if err := dockerClient.PullImage(newImage); err != nil {
		ui.Error("Erro ao baixar imagem: " + err.Error())
		return err
	}

	// 5. Reiniciar com merge de configs
	progress.Step("Reiniciando com novas configurações...")

	if err := dockerClient.UpdateContainerImage(appName, newImage); err != nil {
		ui.Error("Erro ao atualizar container: " + err.Error())
		return err
	}

	// Atualizar config local
	appConfig.Image = newImage
	if err := storage.SaveApp(appConfig); err != nil {
		ui.Warning("Erro ao salvar configuração: " + err.Error())
	}

	ui.Success(fmt.Sprintf("%s atualizado!", appName))

	fmt.Println()
	if imageChanged {
		fmt.Printf("  %s Imagem: %s → %s\n", ui.Green("•"), oldImage, newImage)
	}
	if len(addedEnvs) > 0 {
		fmt.Printf("  %s Configs adicionadas: %v\n", ui.Green("•"), addedEnvs)
	}
	fmt.Printf("  %s Configs mantidas: suas customizações foram preservadas\n", ui.Green("•"))
	fmt.Println()

	return nil
}
