build:
    echo "build"

gen-proto:
    protoc \
        -I=infra \
        --go_out=infra/gen \
        --go_opt=paths=source_relative \
        --go-grpc_out=infra/gen \
        --go-grpc_opt=paths=source_relative \
        ./infra/proto/*.proto

send-logs:
	time bash -c '\
	for j in {1..100}; do \
		( \
			for i in {1..5000}; do \
				echo "hello $$i"; \
			done | nc -U /tmp/jxdlogs.sock > /dev/null \
		) & \
	done; \
	wait \
	'