package cli

import (
	"fmt"

	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/services"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var dbCmd = &cobra.Command{
	Use:   "db",
	Short: "Gerencia databases do PostgreSQL",
	Long:  `Comandos para gerenciar databases do PostgreSQL gerenciado pelo Hostfy.`,
}

var dbListCmd = &cobra.Command{
	Use:   "list",
	Short: "Lista todos os databases",
	RunE:  runDbList,
}

var dbRemoveCmd = &cobra.Command{
	Use:   "remove <database>",
	Short: "Remove um database",
	Long: `Remove um database do PostgreSQL.

ATENÇÃO: Esta ação é irreversível! Todos os dados serão perdidos.

Exemplos:
  hostfy db remove n8n_db
  hostfy db remove --force n8n_db`,
	Args: cobra.ExactArgs(1),
	RunE: runDbRemove,
}

var (
	dbRemoveForce bool
)

func init() {
	dbRemoveCmd.Flags().BoolVar(&dbRemoveForce, "force", false, "Remove sem confirmação")

	dbCmd.AddCommand(dbListCmd)
	dbCmd.AddCommand(dbRemoveCmd)
}

func runDbList(cmd *cobra.Command, args []string) error {
	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	secrets, err := storage.LoadSecrets()
	if err != nil {
		ui.Error("Erro ao carregar secrets: " + err.Error())
		return err
	}

	pgManager := services.NewPostgresManager(dockerClient, secrets)

	// Verificar se postgres está rodando
	running, _ := pgManager.IsRunning()
	if !running {
		ui.Error("PostgreSQL não está rodando. Execute 'hostfy start' primeiro.")
		return fmt.Errorf("postgres não está rodando")
	}

	ui.Info("Databases no PostgreSQL:")
	fmt.Println()

	dbs, err := pgManager.ListDatabases()
	if err != nil {
		ui.Error("Erro ao listar databases: " + err.Error())
		return err
	}

	if len(dbs) == 0 {
		fmt.Println("  Nenhum database encontrado.")
		return nil
	}

	// Carregar apps para identificar quais databases estão em uso
	apps, _ := storage.ListApps()
	usedDbs := make(map[string]string)
	for _, app := range apps {
		if app.Database != "" {
			usedDbs[app.Database] = app.Name
		}
	}

	for _, db := range dbs {
		if appName, ok := usedDbs[db]; ok {
			fmt.Printf("  • %s %s\n", db, ui.Green(fmt.Sprintf("(usado por %s)", appName)))
		} else {
			fmt.Printf("  • %s %s\n", db, ui.Yellow("(órfão)"))
		}
	}
	fmt.Println()

	return nil
}

func runDbRemove(cmd *cobra.Command, args []string) error {
	dbName := args[0]

	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	secrets, err := storage.LoadSecrets()
	if err != nil {
		ui.Error("Erro ao carregar secrets: " + err.Error())
		return err
	}

	pgManager := services.NewPostgresManager(dockerClient, secrets)

	// Verificar se postgres está rodando
	running, _ := pgManager.IsRunning()
	if !running {
		ui.Error("PostgreSQL não está rodando. Execute 'hostfy start' primeiro.")
		return fmt.Errorf("postgres não está rodando")
	}

	// Verificar se o database existe
	dbs, err := pgManager.ListDatabases()
	if err != nil {
		ui.Error("Erro ao listar databases: " + err.Error())
		return err
	}

	found := false
	for _, db := range dbs {
		if db == dbName {
			found = true
			break
		}
	}

	if !found {
		ui.Error(fmt.Sprintf("Database '%s' não encontrado", dbName))
		return fmt.Errorf("database não encontrado")
	}

	// Verificar se está em uso por algum app
	apps, _ := storage.ListApps()
	for _, app := range apps {
		if app.Database == dbName {
			ui.Error(fmt.Sprintf("Database '%s' está em uso pelo app '%s'", dbName, app.Name))
			ui.Info("Use 'hostfy remove " + app.Name + "' para remover o app e o database juntos.")
			return fmt.Errorf("database em uso")
		}
	}

	// Confirmação
	if !dbRemoveForce {
		ui.Warning(fmt.Sprintf("Você está prestes a remover o database '%s'", dbName))
		ui.Warning("Esta ação é IRREVERSÍVEL! Todos os dados serão perdidos.")
		fmt.Println()
		fmt.Print("Digite o nome do database para confirmar: ")
		var confirmation string
		fmt.Scanln(&confirmation)
		if confirmation != dbName {
			ui.Info("Operação cancelada.")
			return nil
		}
	}

	ui.Info(fmt.Sprintf("Removendo database '%s'...", dbName))

	if err := pgManager.DropDatabase(dbName); err != nil {
		ui.Error("Erro ao remover database: " + err.Error())
		return err
	}

	ui.Success(fmt.Sprintf("Database '%s' removido com sucesso!", dbName))
	return nil
}
