#include "jitprobe.h"

#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

#ifndef MAP_ANON
#define MAP_ANON MAP_ANONYMOUS
#endif

static sigjmp_buf jit_jmp;
static volatile int jit_trapped = 0;

static void jit_signal_handler(int sig) {
    jit_trapped = sig;
    siglongjmp(jit_jmp, 1);
}

int jit_probe(void) {
    struct sigaction sa;
    struct sigaction old_ill, old_seg, old_bus, old_trp;

    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = jit_signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_NODEFER;

    sigaction(SIGILL,  &sa, &old_ill);
    sigaction(SIGSEGV, &sa, &old_seg);
    sigaction(SIGBUS,  &sa, &old_bus);
    sigaction(SIGTRAP, &sa, &old_trp);

    jit_trapped = 0;

    if (sigsetjmp(jit_jmp, 1) != 0) {
        int trapped = jit_trapped;
        sigaction(SIGILL,  &old_ill, NULL);
        sigaction(SIGSEGV, &old_seg, NULL);
        sigaction(SIGBUS,  &old_bus, NULL);
        sigaction(SIGTRAP, &old_trp, NULL);
        return trapped;
    }

    void *page = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANON, -1, 0);
    if (page == MAP_FAILED) {
        sigaction(SIGILL,  &old_ill, NULL);
        sigaction(SIGSEGV, &old_seg, NULL);
        sigaction(SIGBUS,  &old_bus, NULL);
        sigaction(SIGTRAP, &old_trp, NULL);
        return -2;
    }

    /* ARM64: RET (return to caller), executes fine iff JIT is allowed */
    uint32_t ret_insn = 0xD65F03C0;
    memcpy(page, &ret_insn, sizeof(ret_insn));
    __builtin___clear_cache(page, (char *)page + 4096);

    if (mprotect(page, 4096, PROT_READ | PROT_EXEC) != 0) {
        munmap(page, 4096);
        sigaction(SIGILL,  &old_ill, NULL);
        sigaction(SIGSEGV, &old_seg, NULL);
        sigaction(SIGBUS,  &old_bus, NULL);
        sigaction(SIGTRAP, &old_trp, NULL);
        return -3;
    }

    void (*fn)(void) = (void (*)(void))page;
    fn();

    munmap(page, 4096);
    sigaction(SIGILL,  &old_ill, NULL);
    sigaction(SIGSEGV, &old_seg, NULL);
    sigaction(SIGBUS,  &old_bus, NULL);
    sigaction(SIGTRAP, &old_trp, NULL);
    return 0;
}
