// Start UTM's own QEMU outside UTM. UTM ships QEMU as a framework that its sandboxed helper
// loads and runs; this does the same from a terminal: load the framework, hand it the
// command line, run its main loop. utm-qemu.sh compiles it and signs it with the hypervisor
// entitlement, which Apple's Hypervisor framework requires.
//
// usage: utm-qemu QEMU_FRAMEWORK_BINARY [QEMU arguments...]
#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s QEMU_FRAMEWORK_BINARY [QEMU arguments...]\n", argv[0]);
    return 1;
  }
  void *qemu = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!qemu) {
    fprintf(stderr, "dlopen: %s\n", dlerror());
    return 1;
  }
  void (*qemu_init)(int, char **) = (void (*)(int, char **))dlsym(qemu, "qemu_init");
  int (*qemu_main_loop)(void) = (int (*)(void))dlsym(qemu, "qemu_main_loop");
  if (!qemu_init || !qemu_main_loop) {
    fprintf(stderr, "dlsym: %s\n", dlerror());
    return 1;
  }
  // QEMU reads its own name from argv[0]; drop the framework path from the command line.
  argv[1] = argv[0];
  qemu_init(argc - 1, argv + 1);
  return qemu_main_loop();
}
