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
