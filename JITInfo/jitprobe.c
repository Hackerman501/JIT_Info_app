#include "jitprobe.h"

#include <stdint.h>
#include <sys/mman.h>

#ifndef MAP_ANON
#define MAP_ANON MAP_ANONYMOUS
#endif

int jit_probe(void) {
    void *page = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANON, -1, 0);
    if (page == MAP_FAILED) {
        return -2;
    }

    if (mprotect(page, 4096, PROT_READ | PROT_EXEC) != 0) {
        munmap(page, 4096);
        return -3;
    }

    munmap(page, 4096);
    return 0;
}
