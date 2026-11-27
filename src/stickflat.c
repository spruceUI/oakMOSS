/*
 * oakmoss-stickflat: a dead zone (the kernel's "flat") on a pad's stick.
 *
 *   oakmoss-stickflat <device name> <flat>
 *
 * Sets flat on every stick axis (ABS_X to ABS_RZ) the device reports, on every input
 * device with that name; exits 1 if there is none. The Zero 28 has two sticks, on
 * ABS_X/ABS_Y and ABS_Z/ABS_RZ, and the second one gets the same dead zone as the
 * first. The Zero 40's magicx-input reports flat 0, but a stick can rest
 * a few percent off centre (ABS_Y -819 to -901 on one unit), and gptokeyb2 held a
 * direction down forever. SDL reads flat as a dead zone only with
 * SDL_LINUX_JOYSTICK_DEADZONES=1, which rc.local exports when this succeeds.
 * Static, built by scripts/build.sh: the image has no evtest or Python to do it.
 */
#include <fcntl.h>
#include <glob.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/input.h>

int main(int argc, char **argv)
{
	char name[256];
	glob_t g;
	int flat, found = 0;

	if (argc != 3 || (flat = atoi(argv[2])) < 0) {
		fputs("usage: oakmoss-stickflat <device name> <flat>\n", stderr);
		return 2;
	}
	if (glob("/dev/input/event*", 0, NULL, &g))
		return 1;
	for (size_t i = 0; i < g.gl_pathc; i++) {
		int fd = open(g.gl_pathv[i], O_RDWR);

		if (fd < 0)
			continue;
		memset(name, 0, sizeof name);
		if (ioctl(fd, EVIOCGNAME(sizeof name - 1), name) >= 0 && !strcmp(name, argv[1])) {
			unsigned char bits[ABS_MAX / 8 + 1] = { 0 };

			ioctl(fd, EVIOCGBIT(EV_ABS, sizeof bits), bits);
			for (int code = ABS_X; code <= ABS_RZ; code++) {
				struct input_absinfo a;

				if (!(bits[code / 8] >> (code % 8) & 1) || ioctl(fd, EVIOCGABS(code), &a) < 0)
					continue;
				a.flat = flat;
				if (ioctl(fd, EVIOCSABS(code), &a) == 0)
					found = 1;
			}
		}
		close(fd);
	}
	globfree(&g);
	return found ? 0 : 1;
}
