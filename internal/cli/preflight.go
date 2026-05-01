package cli

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"

	"github.com/eduardocarezia/hostfy-cli/internal/ui"
)

const (
	preflightGoVersion       = "1.25.0"
	preflightGoMinMajor      = 1
	preflightGoMinMinor      = 25
	preflightGoInstallPath   = "/usr/local/go"
	preflightGoBinary        = "/usr/local/go/bin/go"
	preflightDockerDropinDir = "/etc/systemd/system/docker.service.d"
	preflightDockerDropin    = "/etc/systemd/system/docker.service.d/api-version.conf"
)

// EnsurePreflight garante que Docker e Go estão instalados e atualizados.
// Equivalente às verificações do scripts/install.sh.
// Requer root (necessário para escrever em /usr/local e systemctl).
func EnsurePreflight() error {
	if runtime.GOOS != "linux" {
		return fmt.Errorf("preflight só é suportado em Linux")
	}
	if os.Geteuid() != 0 {
		return fmt.Errorf("preflight requer root (rode com sudo)")
	}
	if err := ensureDocker(); err != nil {
		return err
	}
	if err := ensureGo(); err != nil {
		return err
	}
	return nil
}

// ensureDocker verifica/instala Docker e configura DOCKER_MIN_API_VERSION.
func ensureDocker() error {
	ui.Info("Verificando Docker...")

	if _, err := exec.LookPath("docker"); err != nil {
		ui.Info("Docker não encontrado, instalando...")
		install := exec.Command("bash", "-c", "curl -fsSL https://get.docker.com | sh")
		install.Stdout = os.Stdout
		install.Stderr = os.Stderr
		if err := install.Run(); err != nil {
			return fmt.Errorf("falha ao instalar Docker: %w", err)
		}
		_ = exec.Command("systemctl", "enable", "docker").Run()
		_ = exec.Command("systemctl", "start", "docker").Run()
		ui.Success("Docker instalado")
	} else {
		ui.Info("Docker já instalado")
	}

	// Garantir que o daemon está rodando
	if err := exec.Command("docker", "info").Run(); err != nil {
		ui.Info("Iniciando Docker...")
		_ = exec.Command("systemctl", "start", "docker").Run()
	}

	// Configurar drop-in com DOCKER_MIN_API_VERSION (idempotente)
	if !preflightDropinUpToDate() {
		ui.Info("Configurando compatibilidade Docker API...")
		if err := os.MkdirAll(preflightDockerDropinDir, 0755); err != nil {
			return fmt.Errorf("falha ao criar dir do drop-in: %w", err)
		}
		content := "[Service]\nEnvironment=\"DOCKER_MIN_API_VERSION=1.24\"\n"
		if err := os.WriteFile(preflightDockerDropin, []byte(content), 0644); err != nil {
			return fmt.Errorf("falha ao escrever drop-in: %w", err)
		}
		_ = exec.Command("systemctl", "daemon-reload").Run()
		_ = exec.Command("systemctl", "restart", "docker").Run()
		ui.Success("Docker API configurado")
	}

	return nil
}

func preflightDropinUpToDate() bool {
	data, err := os.ReadFile(preflightDockerDropin)
	if err != nil {
		return false
	}
	return strings.Contains(string(data), "DOCKER_MIN_API_VERSION=1.24")
}

// ensureGo verifica versão do Go em /usr/local/go e instala/atualiza se < 1.22.
func ensureGo() error {
	ui.Info("Verificando Go...")

	needInstall := true
	if _, err := os.Stat(preflightGoBinary); err == nil {
		major, minor, ok := parseGoVersion(preflightGoBinary)
		if ok {
			if major > preflightGoMinMajor || (major == preflightGoMinMajor && minor >= preflightGoMinMinor) {
				ui.Info(fmt.Sprintf("Go %d.%d ok", major, minor))
				needInstall = false
			} else {
				ui.Warning(fmt.Sprintf("Go %d.%d antigo, atualizando para %s", major, minor, preflightGoVersion))
			}
		}
	}

	if !needInstall {
		return nil
	}

	arch := preflightArch()
	if arch == "" {
		return fmt.Errorf("arquitetura %s não suportada", runtime.GOARCH)
	}

	ui.Info(fmt.Sprintf("Instalando Go %s...", preflightGoVersion))
	url := fmt.Sprintf("https://go.dev/dl/go%s.linux-%s.tar.gz", preflightGoVersion, arch)
	tarball := "/tmp/hostfy-go.tar.gz"

	dl := exec.Command("curl", "-fsSL", url, "-o", tarball)
	dl.Stdout = os.Stdout
	dl.Stderr = os.Stderr
	if err := dl.Run(); err != nil {
		return fmt.Errorf("falha ao baixar Go: %w", err)
	}
	defer os.Remove(tarball)

	if err := os.RemoveAll(preflightGoInstallPath); err != nil {
		return fmt.Errorf("falha ao remover Go antigo: %w", err)
	}

	ext := exec.Command("tar", "-C", "/usr/local", "-xzf", tarball)
	ext.Stdout = os.Stdout
	ext.Stderr = os.Stderr
	if err := ext.Run(); err != nil {
		return fmt.Errorf("falha ao extrair Go: %w", err)
	}

	ui.Success(fmt.Sprintf("Go %s instalado", preflightGoVersion))
	return nil
}

func parseGoVersion(goBinary string) (major, minor int, ok bool) {
	out, err := exec.Command(goBinary, "version").Output()
	if err != nil {
		return 0, 0, false
	}
	// Formato: "go version go1.22.10 linux/amd64"
	fields := strings.Fields(string(out))
	if len(fields) < 3 {
		return 0, 0, false
	}
	ver := strings.TrimPrefix(fields[2], "go")
	parts := strings.Split(ver, ".")
	if len(parts) < 2 {
		return 0, 0, false
	}
	maj, err1 := strconv.Atoi(parts[0])
	min, err2 := strconv.Atoi(parts[1])
	if err1 != nil || err2 != nil {
		return 0, 0, false
	}
	return maj, min, true
}

func preflightArch() string {
	switch runtime.GOARCH {
	case "amd64":
		return "amd64"
	case "arm64":
		return "arm64"
	case "arm":
		return "arm"
	}
	return ""
}
