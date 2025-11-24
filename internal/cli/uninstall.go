package cli

import (
	"github.com/spf13/cobra"
)

var uninstallCmd = &cobra.Command{
	Use:   "uninstall <app>",
	Short: "Remove um app instalado (alias para 'remove')",
	Long:  `Remove um app instalado. Por padrão mantém os dados (volumes). Use --purge para remover tudo.`,
	Args:  cobra.ExactArgs(1),
	RunE:  runRemove,
}

func init() {
	// Usa a mesma variável removePurge de remove.go
	uninstallCmd.Flags().BoolVar(&removePurge, "purge", false, "Remove também os dados (volumes e database)")
}
