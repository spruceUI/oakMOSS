/*
 * oakmoss-backlight: the panel's raw backlight value, through the display driver's ioctls.
 *
 *   oakmoss-backlight             print it (0..255)
 *   oakmoss-backlight <0..255>    set it
 *
 * Raw: on the Zero 40 and the XU20 a higher value is darker (docs/hardware-notes.md).
 * Static, built by scripts/build.sh: nothing else in the image reaches /dev/disp.
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/ioctl.h>

#define DISP_LCD_SET_BRIGHTNESS 0x102	/* include/video/sunxi_display2.h */
#define DISP_LCD_GET_BRIGHTNESS 0x103

static int usage(void)
{
	fputs("usage: oakmoss-backlight [0..255]\n", stderr);
	return 2;
}

int main(int argc, char **argv)
{
	unsigned long arg[4] = { 0 };	/* screen 0, then the value */
	char *end;
	int fd, ret;

	if (argc > 2)
		return usage();
	if (argc == 2) {
		arg[1] = strtoul(argv[1], &end, 10);
		if (end == argv[1] || *end || arg[1] > 255)
			return usage();
	}
	fd = open("/dev/disp", O_RDWR);
	if (fd < 0) {
		perror("oakmoss-backlight: /dev/disp");
		return 1;
	}
	/* The driver answers a get with the value itself. */
	ret = ioctl(fd, argc == 2 ? DISP_LCD_SET_BRIGHTNESS : DISP_LCD_GET_BRIGHTNESS, arg);
	close(fd);
	if (ret < 0) {
		perror("oakmoss-backlight");
		return 1;
	}
	if (argc == 1)
		printf("%d\n", ret);
	return 0;
}
