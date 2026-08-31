package db

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
)

func NewPostgres(ctx context.Context, url string) (*pgxpool.Pool, error) {
	config, err := pgxpool.ParseConfig(url)
	if err != nil {
		return nil, err
	}

	config.MaxConns = 20
	config.MinConns = 5
	config.MaxConnIdleTime = 5 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, err
	}

	if err := pool.Ping(ctx); err != nil {
		return nil, err
	}

	return pool, nil
}

func PingConnection(ctx context.Context, pool *pgxpool.Pool) {
	if err := pool.Ping(ctx); err != nil {
		log.Fatal().Err(err).Msg("failed to connect to postgres")
	}
	log.Info().Msg("postgres connected successfully")
}
