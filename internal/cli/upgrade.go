package cli

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var upgradeCmd = &cobra.Command{
	Use:   "upgrade",
	Short: "Atualiza o hostfy CLI para a versão mais recente",
	Long:  `Baixa o código fonte e recompila o hostfy CLI.`,
	RunE:  runUpgrade,
}

var (
	upgradeForce bool
)

const (
	githubRepo = "eduardocarezia/hostfy-cli"
	versionURL = "https://raw.githubusercontent.com/eduardocarezia/hostfy-cli/main/VERSION"
)

func init() {
	upgradeCmd.Flags().BoolVar(&upgradeForce, "force", false, "Força a reinstalação mesmo se já estiver na última versão")
}

func runUpgrade(cmd *cobra.Command, args []string) error {
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
