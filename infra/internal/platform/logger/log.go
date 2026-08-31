package logger

import (
	"io"
	"os"
	"time"

	"github.com/rs/zerolog"
	"runvey.io/infra/internal/config"
)

func New(mode config.Mode) zerolog.Logger {
	var output io.Writer = os.Stdout

	if mode == config.EnvDevelopment {
		output = zerolog.ConsoleWriter{
			Out:        os.Stdout,
			TimeFormat: time.RFC3339,
		}
	}

	logger := zerolog.New(output).With().Timestamp().Logger()

	if mode == config.EnvDevelopment {
		logger = logger.With().Caller().Logger()
	}

	return logger
}
