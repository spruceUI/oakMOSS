/*
 * oakmoss-fbtext: a scrolling text screen on the framebuffer, for the debug boot
 * (oakmoss-debug-text.sh: the kernel log and the boot log in place of the boot screens).
 *
 *   oakmoss-fbtext [-t title] [-k from] [-f file] [-d /dev/fb0]
 *   oakmoss-fbtext [-t title] [-k from] [-f file] -o out.raw -g 640x480    a test: B, G, R, A rows
 *
 * -k: the kernel log (/dev/kmsg, as dmesg prints it) from uptime <from> seconds on; -f: the lines
 * added to <file>, which may appear later; neither: the lines on stdin. The title stays on the top
 * row; long lines wrap. 32 bpp only, onto both pages of a two-page framebuffer, then a flip, as
 * charge-screen.sh draws. The font is DejaVu Sans Mono in 8x16 cells (fbtext-font.h, from
 * scripts/make-fbtext-font.py). Static, built by scripts/build.sh.
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <linux/fb.h>

#include "fbtext-font.h"	/* font8x16[95][16][8]: alpha, ASCII 32-126 */

#define CW 8
#define CH 16
#define MAXCOLS 256
#define MAXROWS 128
#define LINE 4096

static const uint8_t FG[3] = { 200, 200, 200 }, BLACK[3] = { 0, 0, 0 };
static const uint8_t TITLE_FG[3] = { 0, 0, 0 }, TITLE_BG[3] = { 170, 170, 170 };

static unsigned xres, yres, cols, rows, pages = 1, line_len;
static uint32_t roff = 16, goff = 8, boff = 0, aoff = 24;
static uint8_t *screen;			/* one page, xres x yres, 4 bytes a pixel */
static char text[MAXROWS][MAXCOLS + 1];	/* the rows under the title, a ring */
static unsigned head, used;
static char title[MAXCOLS + 1];

struct src {				/* an input, read in pieces and cut into lines */
	int fd;
	size_t len;
	char buf[LINE];
};

static uint32_t pixel(const uint8_t c[3])
{
	return (uint32_t)c[0] << roff | (uint32_t)c[1] << goff | (uint32_t)c[2] << boff | 255u << aoff;
}

static void draw_row(unsigned row, const char *s, const uint8_t fg[3], const uint8_t bg[3])
{
	uint32_t back = pixel(bg);

	for (unsigned y = 0; y < CH; y++) {
		uint32_t *p = (uint32_t *)(screen + (size_t)(row * CH + y) * xres * 4);
		for (unsigned x = 0; x < cols * CW; x++)
			p[x] = back;
	}
	for (unsigned i = 0; s[i] && i < cols; i++) {
		unsigned char ch = (unsigned char)s[i];
		if (ch < 32 || ch > 126)
			ch = '?';
		for (unsigned y = 0; y < CH; y++) {
			uint32_t *p = (uint32_t *)(screen + (size_t)(row * CH + y) * xres * 4) + i * CW;
			for (unsigned x = 0; x < CW; x++) {
				unsigned a = font8x16[ch - 32][y][x];
				uint8_t c[3];
				if (!a)
					continue;
				for (int k = 0; k < 3; k++)
					c[k] = (uint8_t)((bg[k] * (255 - a) + fg[k] * a) / 255);
				p[x] = pixel(c);
			}
		}
	}
}

static void render(void)
{
	memset(screen, 0, (size_t)xres * yres * 4);
	draw_row(0, title, TITLE_FG, TITLE_BG);
	for (unsigned r = 0; r < used; r++)
		draw_row(r + 1, text[(head + MAXROWS - used + r) % MAXROWS], FG, BLACK);
}

/* One line, wrapped onto as many rows as it needs; the oldest rows scroll away. */
static void push(const char *s)
{
	size_t n = strlen(s);

	do {
		size_t k = n < cols ? n : cols;
		memcpy(text[head], s, k);
		text[head][k] = 0;
		for (size_t i = 0; i < k; i++)
			if (text[head][i] == '\t')
				text[head][i] = ' ';
		head = (head + 1) % MAXROWS;
		if (used < rows - 1)
			used++;
		s += k;
		n -= k;
	} while (n);
}

/* What arrived on a source, cut into lines: 1 data, 0 nothing yet, -1 its end (or an error). */
static int take(struct src *s)
{
	ssize_t r = read(s->fd, s->buf + s->len, sizeof s->buf - 1 - s->len);
	char *p = s->buf, *nl;

	if (r < 0)
		return errno == EAGAIN || errno == EINTR ? 0 : -1;
	if (r == 0)
		return -1;
	s->len += (size_t)r;
	while ((nl = memchr(p, '\n', s->len - (size_t)(p - s->buf)))) {
		*nl = 0;
		push(p);
		p = nl + 1;
	}
	s->len -= (size_t)(p - s->buf);
	memmove(s->buf, p, s->len);
	if (s->len == sizeof s->buf - 1) {	/* longer than the buffer: in pieces */
		s->buf[s->len] = 0;
		push(s->buf);
		s->len = 0;
	}
	return 1;
}

/* The kernel log: one record a read ("prio,seq,usec,flags;text" then " KEY=value" lines), shown
 * from usec `from` on: 1 shown, 0 skipped or nothing, -1 an error. EPIPE: records were
 * overwritten before we read them, go on. */
static int take_kmsg(int fd, unsigned long long from)
{
	char rec[LINE + 1], line[LINE + 32], *semi, *nl;
	unsigned long long us;
	ssize_t r = read(fd, rec, LINE);

	if (r < 0)
		return errno == EAGAIN || errno == EINTR || errno == EPIPE ? 0 : -1;
	if (r == 0)
		return -1;
	rec[r] = 0;
	semi = strchr(rec, ';');
	if (!semi || sscanf(rec, "%*u,%*u,%llu", &us) != 1 || us < from)
		return 0;
	if ((nl = strchr(semi + 1, '\n')))
		*nl = 0;
	snprintf(line, sizeof line, "[%5llu.%06llu] %s", us / 1000000, us % 1000000, semi + 1);
	push(line);
	return 1;
}

/* The followed file: opened once it exists (from its start if it appeared after we began, else
 * from its end), read from the start again if it shrinks; 1 when lines came. */
static int follow(struct src *s, const char *path, int *late)
{
	struct stat st;
	int any = 0;

	if (s->fd < 0) {
		if ((s->fd = open(path, O_RDONLY)) < 0) {
			*late = 1;
			return 0;
		}
		if (!*late)
			lseek(s->fd, 0, SEEK_END);
	}
	if (fstat(s->fd, &st) == 0 && st.st_size < lseek(s->fd, 0, SEEK_CUR)) {
		lseek(s->fd, 0, SEEK_SET);
		s->len = 0;
	}
	while (take(s) > 0)
		any = 1;
	return any;
}

static int ready(int fd)
{
	struct pollfd q = { .fd = fd, .events = POLLIN };

	return poll(&q, 1, 0) > 0;
}

static int show_fb(int fd, uint8_t *fb, struct fb_var_screeninfo *v)
{
	for (unsigned pg = 0; pg < pages; pg++)
		for (unsigned y = 0; y < yres; y++)
			memcpy(fb + (size_t)(pg * yres + y) * line_len, screen + (size_t)y * xres * 4, (size_t)xres * 4);
	/* a flip, so the display engine reads the new picture: to page 1 and back to page 0 */
	if (pages > 1) {
		v->yoffset = yres;
		ioctl(fd, FBIOPAN_DISPLAY, v);
	}
	v->yoffset = 0;
	return ioctl(fd, FBIOPAN_DISPLAY, v);
}

static int show_file(const char *path)
{
	FILE *f = fopen(path, "wb");

	if (!f || fwrite(screen, 4, (size_t)xres * yres, f) != (size_t)xres * yres || fclose(f)) {
		perror(path);
		return -1;
	}
	return 0;
}

static int usage(void)
{
	fputs("usage: oakmoss-fbtext [-t title] [-k from] [-f file] [-d fbdev | -o file -g WxH]\n", stderr);
	return 2;
}

int main(int argc, char **argv)
{
	const char *dev = "/dev/fb0", *out = NULL, *geom = NULL, *file = NULL;
	unsigned long long from = 0;
	struct fb_var_screeninfo v;
	struct fb_fix_screeninfo f;
	struct src in = { .fd = 0 }, fl = { .fd = -1 };
	uint8_t *fb = NULL;
	int fd = -1, opt, kfd = -1, use_kmsg = 0, late = 0, open_in = 1;

	while ((opt = getopt(argc, argv, "t:k:f:d:o:g:")) != -1) {
		switch (opt) {
		case 't': snprintf(title, sizeof title, "%s", optarg); break;
		case 'k': use_kmsg = 1; from = (unsigned long long)(strtod(optarg, NULL) * 1e6); break;
		case 'f': file = optarg; break;
		case 'd': dev = optarg; break;
		case 'o': out = optarg; break;
		case 'g': geom = optarg; break;
		default: return usage();
		}
	}
	if (optind != argc || !out != !geom)
		return usage();
	if (out) {
		if (sscanf(geom, "%ux%u", &xres, &yres) != 2 || !xres || !yres)
			return usage();
	} else {
		fd = open(dev, O_RDWR);
		if (fd < 0 || ioctl(fd, FBIOGET_VSCREENINFO, &v) || ioctl(fd, FBIOGET_FSCREENINFO, &f)) {
			perror(dev);
			return 1;
		}
		if (v.bits_per_pixel != 32) {
			fprintf(stderr, "oakmoss-fbtext: %u bpp, only 32 is drawn\n", v.bits_per_pixel);
			return 1;
		}
		xres = v.xres;
		yres = v.yres;
		line_len = f.line_length;
		pages = v.yres_virtual >= 2 * v.yres ? 2 : 1;
		roff = v.red.offset;
		goff = v.green.offset;
		boff = v.blue.offset;
		aoff = v.transp.length ? v.transp.offset : 24;
		if (line_len < xres * 4 || (size_t)line_len * yres * pages > f.smem_len) {
			fprintf(stderr, "oakmoss-fbtext: %ux%u x %u pages does not fit %u bytes\n", xres, yres, pages, f.smem_len);
			return 1;
		}
		fb = mmap(NULL, f.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
		if (fb == MAP_FAILED) {
			perror("oakmoss-fbtext: mmap");
			return 1;
		}
		ioctl(fd, FBIOBLANK, FB_BLANK_UNBLANK);
	}
	cols = xres / CW < MAXCOLS ? xres / CW : MAXCOLS;
	rows = yres / CH < MAXROWS ? yres / CH : MAXROWS;
	screen = calloc((size_t)xres * yres, 4);
	if (!screen || rows < 2) {
		fputs("oakmoss-fbtext: no room\n", stderr);
		return 1;
	}
	if (use_kmsg && (kfd = open("/dev/kmsg", O_RDONLY | O_NONBLOCK)) < 0) {
		perror("oakmoss-fbtext: /dev/kmsg");
		return 1;
	}
	if (use_kmsg || file)
		open_in = 0;

	/* Whatever has arrived, then one redraw: a burst (the kernel log so far) costs one, and an
	 * input that never pauses still gets one every 64 lines. A followed file is looked at every
	 * quarter of a second. The first pass draws the title at once. Ends with stdin's end, never
	 * while following. */
	for (int first = 1;; first = 0) {
		struct pollfd p[2] = { { .fd = open_in ? 0 : -1, .events = POLLIN },
				       { .fd = kfd, .events = POLLIN } };
		int got = first;

		if (!first && poll(p, 2, file ? 250 : -1) < 0 && errno != EINTR)
			return 1;
		for (int i = 0; i < 64; i++) {
			int any = 0;
			if (open_in && ready(0)) {
				int r = take(&in);
				if (r < 0) {
					open_in = 0;
					if (in.len) {	/* a last line without its newline */
						in.buf[in.len] = 0;
						push(in.buf);
						in.len = 0;
					}
				}
				any = got = 1;
			}
			if (kfd >= 0 && ready(kfd)) {
				int r = take_kmsg(kfd, from);
				if (r < 0) {
					close(kfd);
					kfd = -1;
				}
				got |= r > 0;
				any = 1;
			}
			if (!any)
				break;
		}
		if (file && follow(&fl, file, &late))
			got = 1;
		if (got) {
			render();
			if ((out ? show_file(out) : show_fb(fd, fb, &v)) < 0 && out)
				return 1;
		}
		if (!open_in && kfd < 0 && !file)
			return 0;
	}
}
