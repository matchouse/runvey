package main

import (
	"bufio"
	"flag"
	"fmt"
	"net"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
)

func main() {
	workers := flag.Int("workers", 100, "concurrent connections")
	msgs := flag.Int("msgs", 10000, "messages per worker")
	sock := flag.String("sock", "/tmp/jxdlogs.sock", "unix socket path")
	flag.Parse()

	var (
		wg     sync.WaitGroup
		total  int64
		failed int64
	)

	msg := "hello world"
	start := time.Now()

	for i := 0; i < *workers; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			conn, err := net.Dial("unix", *sock)
			if err != nil {
				atomic.AddInt64(&failed, 1)
				return
			}
			defer conn.Close()

			w := bufio.NewWriterSize(conn, 65536)
			count := 0
			for j := 0; j < *msgs; j++ {
				_, err := w.Write([]byte(msg + strconv.Itoa(i) + "\n"))
				if err != nil {
					break
				}
				count++
			}
			w.Flush()
			atomic.AddInt64(&total, int64(count))
		}(i)
	}

	wg.Wait()
	elapsed := time.Since(start).Seconds()

	fmt.Printf("workers:  %d\n", *workers)
	fmt.Printf("msgs:     %d\n", *msgs)
	fmt.Printf("total:    %d\n", total)
	fmt.Printf("failed:   %d\n", failed)
	fmt.Printf("elapsed:  %.3fs\n", elapsed)
	fmt.Printf("RPS:      %.0f\n", float64(total)/elapsed)
}
