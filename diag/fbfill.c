/* fbfill RRGGBB [fbdev]  - paint the whole framebuffer one colour (16/32 bpp). */
#include <fcntl.h>
#include <linux/fb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: fbfill RRGGBB [/dev/fb0]\n"); return 2; }
    unsigned rgb = (unsigned)strtoul(argv[1], NULL, 16);
    const char *dev = argc > 2 ? argv[2] : "/dev/fb0";
    int fd = open(dev, O_RDWR);
    if (fd < 0) { perror(dev); return 1; }
    struct fb_var_screeninfo v; struct fb_fix_screeninfo f;
    if (ioctl(fd, FBIOGET_VSCREENINFO, &v) || ioctl(fd, FBIOGET_FSCREENINFO, &f)) { perror("ioctl"); return 1; }
    unsigned r = (rgb >> 16) & 255, g = (rgb >> 8) & 255, b = rgb & 255;
    size_t len = f.smem_len; unsigned char *m = mmap(0, len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (m == MAP_FAILED) { perror("mmap"); return 1; }
    if (v.bits_per_pixel == 32) {
        unsigned px = (255u << v.transp.offset) | (r << v.red.offset) | (g << v.green.offset) | (b << v.blue.offset);
        for (size_t i = 0; i + 4 <= len; i += 4) memcpy(m + i, &px, 4);
    } else if (v.bits_per_pixel == 16) {
        unsigned short px = (unsigned short)(((r >> 3) << v.red.offset) | ((g >> 2) << v.green.offset) | ((b >> 3) << v.blue.offset));
        for (size_t i = 0; i + 2 <= len; i += 2) memcpy(m + i, &px, 2);
    } else { fprintf(stderr, "unsupported bpp %u\n", v.bits_per_pixel); return 1; }
    msync(m, len, MS_SYNC); munmap(m, len);
    v.yoffset = 0; ioctl(fd, FBIOPAN_DISPLAY, &v);
    close(fd);
    printf("%ux%u @%ubpp filled %06x\n", v.xres, v.yres, v.bits_per_pixel, rgb);
    return 0;
}
