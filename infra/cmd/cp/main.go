package main

import (
	"context"
	"fmt"
	"io"
	"net"

	"github.com/rs/zerolog/log"
	"google.golang.org/grpc"
	"runvey.io/infra/gen/proto"
	"runvey.io/infra/internal/config"
	"runvey.io/infra/internal/platform/db"
	"runvey.io/infra/internal/platform/logger"
)

type server struct {
	proto.UnimplementedAgentServiceServer
}

func (s *server) Connect(stream proto.AgentService_ConnectServer) error {
	for {
		req, err := stream.Recv()
		if err == io.EOF {
			return nil
		}

		if err != nil {
			log.Info().Err(err).Msg("error")
			return err
		}

		log.Info().Any("h", req).Msg("one agent connected")

		if req != nil {
		}
	}
}

func main() {
	cfg, err := config.Load()
	if err != nil {
		fmt.Println(err)
	}

	log.Logger = logger.New(cfg.Mode)

	pool, err := db.NewPostgres(context.Background(), cfg.PostgresURL)
	if err != nil {
		panic(err)
	}
	db.PingConnection(context.Background(), pool)

	lis, err := net.Listen("tcp", cfg.Port)
	if err != nil {
		log.Fatal().Err(err).Msgf("failed to start tcp on %s", cfg.Port)
	}

	grpcServer := grpc.NewServer()
	proto.RegisterAgentServiceServer(grpcServer, &server{})

	if err := grpcServer.Serve(lis); err != nil {
		log.Fatal().Err(err).Msg("failed to serve grpc")
	}
}
