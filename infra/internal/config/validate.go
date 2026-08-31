package config

import (
	"fmt"

	"github.com/jackc/pgx/v5"
)

func (cfg Config) validate() error {
	if !cfg.Mode.IsValid() {
		return fmt.Errorf("invalid mode")
	}
	_, err := pgx.ParseConfig(cfg.PostgresURL)

	if err != nil {
		return fmt.Errorf("Postgres URL is invalid: %w", err)
	}

	return nil
}
