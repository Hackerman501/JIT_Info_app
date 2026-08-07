#ifndef JITPROBE_H
#define JITPROBE_H

/*
 * Probes whether the current process may create writable + executable memory
 * (i.e. JIT works). Returns:
 *   0   -> RW -> RX transition granted (JIT allowed)
 *  -2   -> mmap() failed
 *  -3   -> mprotect(PROT_READ | PROT_EXEC) rejected (JIT blocked)
 */
int jit_probe(void);

#endif /* JITPROBE_H */
