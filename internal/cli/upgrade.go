package cli

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"runtime"
	"strings"

	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var upgradeCmd = &cobra.Command{
	Use:   "upgrade",
	Short: "Atualiza o hostfy CLI para a versão mais recente",
	Long:  `Baixa e instala a versão mais recente do hostfy CLI.`,
	RunE:  runUpgrade,
}

var (
	upgradeForce bool
)

const (
	// URL base para download dos binários
	downloadBaseURL = "https://github.com/eduardocarezia/hostfy-cli/releases/latest/download"
	versionURL      = "https://raw.githubusercontent.com/eduardocarezia/hostfy-cli/main/VERSION"
)

func init() {
	upgradeCmd.Flags().BoolVar(&upgradeForce, "force", false, "Força a reinstalação mesmo se já estiver na última versão")
}

func runUpgrade(cmd *cobra.Command, args []string) error {
	progress := ui.NewProgress(4)

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
		// Se não conseguir verificar versão, tenta baixar direto
		progress.SubStep("Não foi possível verificar versão, tentando download...")
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

	// 3. Baixar nova versão
	progress.Step("Baixando nova versão...")

	downloadURL := fmt.Sprintf("%s/%s", downloadBaseURL, getAssetName())
	progress.SubStep(fmt.Sprintf("Baixando de: %s", downloadURL))

	tmpFile, err := downloadFile(downloadURL)
	if err != nil {
		ui.Error("Erro ao baixar: " + err.Error())
		return err
	}
	defer os.Remove(tmpFile)

	// 4. Instalar
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
	if err := copyFile(tmpFile, execPath); err != nil {
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

func getAssetName() string {
	osName := runtime.GOOS
	arch := runtime.GOARCH

	return fmt.Sprintf("hostfy-%s-%s", osName, arch)
}

func downloadFile(url string) (string, error) {
	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	tmpFile, err := os.CreateTemp("", "hostfy-*")
	if err != nil {
		return "", err
	}
	defer tmpFile.Close()

	_, err = io.Copy(tmpFile, resp.Body)
	if err != nil {
		os.Remove(tmpFile.Name())
		return "", err
	}

	return tmpFile.Name(), nil
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
