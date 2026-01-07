package cli

import (
	"fmt"
	"strings"
	"time"

	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/traefik"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var updateCmd = &cobra.Command{
	Use:   "update <app>",
	Short: "Atualiza configurações de um app instalado",
	Long: `Altera variáveis de ambiente, domínio ou versão da imagem Docker de um app já instalado.

Exemplos:
  hostfy update n8n --env DEBUG=true           # Altera variável de ambiente
  hostfy update n8n --domain new.example.com   # Altera domínio
  hostfy update n8n --image v2.2.0             # Altera para tag v2.2.0
  hostfy update n8n --image latest             # Altera para tag latest

Para stacks com múltiplos containers:
  hostfy update mystack --image 7.2 --container cache   # Altera tag do container cache`,
	Args: cobra.ExactArgs(1),
	RunE: runUpdate,
}

var (
	updateEnv       []string
	updateDomain    string
	updateImage     string
	updateContainer string
)

func init() {
	updateCmd.Flags().StringSliceVar(&updateEnv, "env", []string{}, "Variáveis de ambiente para alterar (KEY=VALUE)")
	updateCmd.Flags().StringVar(&updateDomain, "domain", "", "Novo domínio")
	updateCmd.Flags().StringVar(&updateImage, "image", "", "Nova tag da imagem (ex: v2.2.0, latest)")
	updateCmd.Flags().StringVar(&updateContainer, "container", "", "Container específico para atualizar (apenas para stacks)")
}

func runUpdate(cmd *cobra.Command, args []string) error {
	appName := args[0]

	// Carregar config do app
	appConfig, err := storage.LoadApp(appName)
	if err != nil {
		ui.Error(fmt.Sprintf("App '%s' não encontrado", appName))
		return err
	}

	if len(updateEnv) == 0 && updateDomain == "" && updateImage == "" {
		ui.Warning("Nenhuma alteração especificada. Use --env, --domain ou --image")
		return nil
	}

	// Validar --container só pode ser usado com --image em stacks
	if updateContainer != "" && updateImage == "" {
		ui.Warning("--container só pode ser usado junto com --image")
		return nil
	}

	if updateContainer != "" && !appConfig.IsStack {
		ui.Warning("--container só pode ser usado em stacks com múltiplos containers")
		return nil
	}

	progress := ui.NewProgress(4)

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

		// Atualizar variáveis de ambiente que contêm o domínio antigo
		for key, value := range appConfig.Env {
			if strings.Contains(value, oldDomain) {
				newValue := strings.ReplaceAll(value, oldDomain, updateDomain)
				appConfig.Env[key] = newValue
			}
		}
	}

	// Atualizar imagem
	imageUpdated := false
	containerIndexToUpdate := -1
	var newFullImage string
	if updateImage != "" {
		if appConfig.IsStack && len(appConfig.Containers) > 0 {
			// Stack multi-container: precisa do --container ou atualizar o main
			if updateContainer != "" {
				// Encontrar container específico
				found := false
				for i, cont := range appConfig.Containers {
					if cont.Name == updateContainer {
						newFullImage = resolveImageTag(cont.Image, updateImage)
						if cont.Image != newFullImage {
							changes = append(changes, fmt.Sprintf("%s image: %s → %s", cont.Name, cont.Image, newFullImage))
							containerIndexToUpdate = i
							imageUpdated = true
						}
						found = true
						break
					}
				}
				if !found {
					ui.Error(fmt.Sprintf("Container '%s' não encontrado na stack", updateContainer))
					fmt.Println("\n  Containers disponíveis:")
					for _, cont := range appConfig.Containers {
						fmt.Printf("    • %s\n", cont.Name)
					}
					return fmt.Errorf("container não encontrado")
				}
			} else {
				// Sem --container, atualizar o container principal (IsMain)
				for i, cont := range appConfig.Containers {
					if cont.IsMain {
						newFullImage = resolveImageTag(cont.Image, updateImage)
						if cont.Image != newFullImage {
							changes = append(changes, fmt.Sprintf("%s image: %s → %s", cont.Name, cont.Image, newFullImage))
							containerIndexToUpdate = i
							imageUpdated = true
						}
						break
					}
				}
				if containerIndexToUpdate == -1 {
					// Se não tem IsMain, atualizar o primeiro
					newFullImage = resolveImageTag(appConfig.Containers[0].Image, updateImage)
					if appConfig.Containers[0].Image != newFullImage {
						changes = append(changes, fmt.Sprintf("%s image: %s → %s", appConfig.Containers[0].Name, appConfig.Containers[0].Image, newFullImage))
						containerIndexToUpdate = 0
						imageUpdated = true
					}
				}
			}
		} else {
			// Single container
			newFullImage = resolveImageTag(appConfig.Image, updateImage)
			if appConfig.Image != newFullImage {
				changes = append(changes, fmt.Sprintf("image: %s → %s", appConfig.Image, newFullImage))
				imageUpdated = true
			}
		}
	}

	// 2. Conectar ao Docker
	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	// 3. Baixar nova imagem se necessário
	if imageUpdated {
		progress.Step("Baixando nova imagem...")

		if err := dockerClient.PullImage(newFullImage); err != nil {
			ui.Error("Erro ao baixar imagem: " + err.Error())
			return err
		}
		progress.SubStep(fmt.Sprintf("Imagem %s baixada!", newFullImage))

		// Atualizar a imagem na config
		if appConfig.IsStack && containerIndexToUpdate >= 0 {
			appConfig.Containers[containerIndexToUpdate].Image = newFullImage
		} else {
			appConfig.Image = newFullImage
			appConfig.ImagePulledAt = time.Now().UTC().Format(time.RFC3339)
		}
	}

	// 4. Recriar container com novas configs
	progress.Step("Aplicando alterações...")

	// Verificar se é uma Stack (múltiplos containers)
	if appConfig.IsStack && len(appConfig.Containers) > 0 {
		// Atualizar SharedEnv com as novas variáveis
		if appConfig.SharedEnv == nil {
			appConfig.SharedEnv = make(map[string]string)
		}
		for _, e := range updateEnv {
			parts := strings.SplitN(e, "=", 2)
			if len(parts) == 2 {
				appConfig.SharedEnv[parts[0]] = parts[1]
			}
		}

		// Recriar cada container da Stack
		for i, cont := range appConfig.Containers {
			containerName := appName + "-" + cont.Name

			// Parar e remover container
			dockerClient.StopContainer(containerName)
			dockerClient.RemoveContainer(containerName, true)

			// Mesclar envs: SharedEnv + Env específico do container
			mergedEnv := make(map[string]string)
			for k, v := range appConfig.SharedEnv {
				mergedEnv[k] = v
			}
			for k, v := range cont.Env {
				mergedEnv[k] = v
			}

			// Determinar port e labels
			port := cont.Port
			if port == 0 {
				port = 80
			}

			var labels map[string]string
			if cont.IsMain {
				labels = traefik.GenerateLabels(appName, appConfig.Domain, port)
			} else if cont.Domain != "" {
				labels = traefik.GenerateLabels(containerName, cont.Domain, port)
			} else {
				labels = map[string]string{}
			}

			containerCfg := &docker.ContainerConfig{
				Name:    containerName,
				Image:   cont.Image,
				Env:     mergedEnv,
				Labels:  labels,
				Volumes: cont.Volumes,
				Restart: "always",
			}

			// Adicionar command se existir para este container
			if cont.Command != "" {
				containerCfg.Command = parseCommand(cont.Command)
			}

			containerID, err := dockerClient.CreateContainer(containerCfg)
			if err != nil {
				ui.Error(fmt.Sprintf("Erro ao recriar container %s: %s", containerName, err.Error()))
				return err
			}

			if err := dockerClient.StartContainer(containerID); err != nil {
				ui.Error(fmt.Sprintf("Erro ao iniciar container %s: %s", containerName, err.Error()))
				return err
			}

			// Atualizar ContainerID na config
			appConfig.Containers[i].ContainerID = containerID
		}
	} else {
		// App de container único
		dockerClient.StopContainer(appName)
		dockerClient.RemoveContainer(appName, true)

		// Usar port salvo na config do app
		port := appConfig.Port
		if port == 0 {
			port = 80 // fallback
		}

		// Gerar novos labels
		labels := traefik.GenerateLabels(appName, appConfig.Domain, port)

		// Recriar container com todas as configs preservadas
		containerCfg := &docker.ContainerConfig{
			Name:    appName,
			Image:   appConfig.Image,
			Env:     appConfig.Env,
			Labels:  labels,
			Volumes: appConfig.Volumes,
			Restart: "always",
		}

		// Adicionar command se existir
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

		appConfig.ContainerID = containerID
	}

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

// resolveImageTag resolve uma tag para imagem completa
// Se newTag contém "/" ou ":", assume que é uma imagem completa
// Caso contrário, extrai a base da imagem atual e concatena com a nova tag
func resolveImageTag(currentImage, newTag string) string {
	// Se contém "/" ou ":" no início, é uma imagem completa
	if strings.Contains(newTag, "/") {
		return newTag
	}

	// Extrair base da imagem atual (remover tag se existir)
	base := currentImage
	if idx := strings.LastIndex(currentImage, ":"); idx != -1 {
		base = currentImage[:idx]
	}

	return base + ":" + newTag
}
