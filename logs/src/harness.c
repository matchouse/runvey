#include <stdint.h>
#include <stddef.h>
#include <unistd.h>


#ifndef __AFL_LOOP
#define __AFL_LOOP(x) for (int _i = 0; _i < 1; _i++)
#endif

// Zig exported function
void fuzz_entry(const uint8_t *data, size_t len);

int main(void) {
    static uint8_t buf[65536];

    // Persistent mode (huge performance boost)
    while (__AFL_LOOP(10000)) {
        ssize_t len = read(0, buf, sizeof(buf));
        if (len <= 0) break;

        fuzz_entry(buf, (size_t)len);
    }

    return 0;
}
