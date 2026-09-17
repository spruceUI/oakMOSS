/* egltest: the smallest possible EGL bring-up, for boards without a console.
 * dlopens libEGL, asks for the default display, initialises it, prints every
 * step and eglGetError(). The PowerVR userland prints its own diagnostics to
 * stderr along the way, which is the text nobody else captures. Build:
 *   aarch64-none-linux-gnu-gcc -O -o egltest egltest.c -ldl        (dynamic, glibc as the base) */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
typedef void *EGLDisplay; typedef unsigned EGLBoolean; typedef int EGLint;
int main(int argc, char **argv) {
    const char *lib = argc > 1 ? argv[1] : "libEGL.so.1";
    void *h = dlopen(lib, RTLD_NOW);
    if (!h) { printf("dlopen %s: %s\n", lib, dlerror()); return 2; }
    EGLDisplay (*getDisplay)(void *) = dlsym(h, "eglGetDisplay");
    EGLBoolean (*init)(EGLDisplay, EGLint *, EGLint *) = dlsym(h, "eglInitialize");
    EGLint (*getError)(void) = dlsym(h, "eglGetError");
    const char *(*query)(EGLDisplay, EGLint) = dlsym(h, "eglQueryString");
    if (!getDisplay || !init || !getError) { printf("missing EGL entry points in %s\n", lib); return 2; }
    printf("dlopen %s ok\n", lib); fflush(stdout);
    EGLDisplay d = getDisplay((void *)0);
    printf("eglGetDisplay(EGL_DEFAULT_DISPLAY) = %p, error 0x%x\n", d, getError()); fflush(stdout);
    if (!d) return 3;
    EGLint maj = 0, min = 0;
    EGLBoolean ok = init(d, &maj, &min);
    printf("eglInitialize = %u (%d.%d), error 0x%x\n", ok, maj, min, getError()); fflush(stdout);
    if (ok && query) {
        printf("vendor: %s\nversion: %s\nextensions: %s\n", query(d, 0x3053), query(d, 0x3054), query(d, 0x3055));
    }
    return ok ? 0 : 4;
}
