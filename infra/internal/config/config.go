package config

import (
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/pelletier/go-toml/v2"
)

type Duration time.Duration

func (d *Duration) UnmarshalText(b []byte) error {
	x, err := time.ParseDuration(string(b))
	if err != nil {
		return err
	}
	*d = Duration(x)
	return nil
}

type Config struct {
	Mode        Mode
	Port        string
	PostgresURL string
	RedisURL    string

	AllowedOrigins []string `toml:"origins"`

	JWTSecret       string
	AccessTokenTTL  Duration
	RefreshTokenTTL Duration
}

func Load() (Config, error) {
	configPathPtr := flag.String("config", "config.toml", "config.toml path")
	flag.Parse()

	configPath := *configPathPtr

	bytes, err := os.ReadFile(configPath)
	if err != nil {
		return Config{}, fmt.Errorf("failed to load config file: %w", err)
	}

	var cfg Config
	err = toml.Unmarshal(bytes, &cfg)
	if err != nil {
		return Config{}, err
	}

	if err := cfg.validate(); err != nil {
		return Config{}, err
	}

	return cfg, nil
}
