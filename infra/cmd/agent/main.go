package main

import (
	"context"
	"io"
	"os"
	"os/signal"
	"syscall"

	"github.com/rs/zerolog/log"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"runvey.io/infra/gen/proto"
)

func main() {
	conn, err := grpc.NewClient("localhost:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatal().Err(err).Msg("did not connect to grpc server")
	}
	defer conn.Close()

	client := proto.NewAgentServiceClient(conn)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancelHandle(cancel)

	stream, err := client.Connect(ctx)
	if err != nil {
		log.Fatal().Err(err).Msg("failed to connect to agent service")
	}

	err = stream.Send(&proto.AgentMessage{
		Message: &proto.AgentMessage_Hello{
			Hello: &proto.AgentHello{
				AgentId: "hi",
			},
		},
	})
	if err != nil {
		log.Info().Err(err).Msg("error")
	}

	waitc := make(chan struct{})
	go func() {
		for {
			in, err := stream.Recv()
			if err == io.EOF {
				log.Info().Msg("server closed the stream connection")
				close(waitc)
				return
			}

			if err != nil {
				log.Error().Err(err).Msg("failed to receive a message")
				close(waitc)
				return
			}

			log.Info().Msg(in.RequestId)
		}
	}()

	<-waitc
	stream.CloseSend()
	log.Info().Msg("agent successfully closed")
}

func cancelHandle(cancel context.CancelFunc) {
	// Gracefully handle sudden OS interrupts to prevent memory leaks
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-c
		cancel()
		os.Exit(1)
	}()
}
