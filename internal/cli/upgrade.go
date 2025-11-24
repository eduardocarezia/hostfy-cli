package cli

import (
	"encoding/json"
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
	Long:  `Baixa e instala a versão mais recente do hostfy CLI do GitHub.`,
	RunE:  runUpgrade,
}

var (
	upgradeForce bool
)

const (
	githubRepo    = "eduardocarezia/hostfy-cli"
	releaseAPIURL = "https://api.github.com/repos/" + githubRepo + "/releases/latest"
)

func init() {
	upgradeCmd.Flags().BoolVar(&upgradeForce, "force", false, "Força a reinstalação mesmo se já estiver na última versão")
}

type GitHubRelease struct {
	TagName string `json:"tag_name"`
	Assets  []struct {
		Name               string `json:"name"`
		BrowserDownloadURL string `json:"browser_download_url"`
	} `json:"assets"`
}

func runUpgrade(cmd *cobra.Command, args []string) error {
	progress := ui.NewProgress(4)

	// 1. Verificar versão atual
	progress.Step("Verificando versão atual...")
	currentVersion := Version // Vem do main.go via ldflags
	if currentVersion == "" {
		currentVersion = "dev"
	}
	progress.SubStep(fmt.Sprintf("Versão atual: %s", currentVersion))

	// 2. Buscar última versão no GitHub
	progress.Step("Buscando última versão...")
	release, err := getLatestRelease()
	if err != nil {
		ui.Error("Erro ao buscar releases: " + err.Error())
		return err
	}

	latestVersion := strings.TrimPrefix(release.TagName, "v")
	progress.SubStep(fmt.Sprintf("Última versão: %s", latestVersion))

	// Verificar se precisa atualizar
	if !upgradeForce && currentVersion == latestVersion {
		ui.Success("Você já está na versão mais recente!")
		return nil
	}

	// 3. Baixar nova versão
	progress.Step("Baixando nova versão...")

	// Determinar asset correto para a plataforma
	assetName := getAssetName()
	var downloadURL string
	for _, asset := range release.Assets {
		if asset.Name == assetName {
			downloadURL = asset.BrowserDownloadURL
			break
		}
	}

	if downloadURL == "" {
		ui.Error(fmt.Sprintf("Binário não encontrado para %s/%s", runtime.GOOS, runtime.GOARCH))
		return fmt.Errorf("asset não encontrado: %s", assetName)
	}

	// Baixar para arquivo temporário
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
		// Restaurar backup em caso de erro
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

func getLatestRelease() (*GitHubRelease, error) {
	resp, err := http.Get(releaseAPIURL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("GitHub API retornou status %d", resp.StatusCode)
	}

	var release GitHubRelease
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return nil, err
	}

	return &release, nil
}

func getAssetName() string {
	os := runtime.GOOS
	arch := runtime.GOARCH

	return fmt.Sprintf("hostfy-%s-%s", os, arch)
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
