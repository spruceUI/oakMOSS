#!/bin/sh
# oakMOSS debug text (docs/boot-screens.md), the equivalent of dArkMoss's darkmoss.debug: with an
# oakmoss-debug file on SD1's SPRUCEOS partition, the kernel log and the boot log scroll on the
# panel (oakmoss-fbtext) in place of the boot screens, until the launcher takes the panel.
#   oakmoss-debug-text.sh start             /etc/init.d/debugtext, first in the boot
#   oakmoss-debug-text.sh stop              runmagicx.sh, before an update, a no-frontend screen or the launcher
#   oakmoss-debug-text.sh shutdown <kind>   /etc/init.d/shutdownframe: the kernel log again, from now on
# Only on the boards with the boot screens, never in a charger boot. The same file turns the debug
# records on (runmagicx.sh, oakmoss-debug.sh).
export PATH=/usr/magicx/bin:$PATH
FLAG=/tmp/oakmoss-debug-text		# a debug-text boot: the boot screens stay off (charge-screen.sh)
PID=/tmp/oakmoss-debug-text.pid
MNT=/tmp/oakmoss-debug-text.mnt
BOOTLOG=/mnt/UDISK/oakmoss-boot.log

title() { echo "oakMOSS debug $1: $(cat /usr/magicx/device 2>/dev/null) $(cat /usr/magicx/version 2>/dev/null), kernel $(uname -r)"; }

# The switch: SD1's SPRUCEOS (the GPT name oakmoss-sd1part gives it), mounted read-only for the look,
# so nothing is written to the card before the card election.
switch_on() {
	for u in /sys/class/block/mmcblk*p*/uevent; do
		grep -qx 'PARTNAME=SPRUCEOS' "$u" 2>/dev/null || continue
		d=${u%/uevent}
		mkdir -p "$MNT" && mount -t vfat -o ro "/dev/${d##*/}" "$MNT" 2>/dev/null || continue
		[ -e "$MNT/oakmoss-debug" ]; on=$?
		umount "$MNT"; rmdir "$MNT"
		return $on
	done
	return 1
}

stop_text() {
	[ -f "$PID" ] && kill "$(cat "$PID")" 2>/dev/null
	rm -f "$PID"
}

case $1 in
start)
	[ -f /usr/magicx/share/charge/boot-loading.rgba.gz ] && command -v oakmoss-fbtext >/dev/null || exit 0
	case " $(cat /proc/cmdline 2>/dev/null) " in *" androidboot.mode=charger "*) exit 0 ;; esac
	switch_on || exit 0
	: > "$FLAG"
	oakmoss-fbtext -t "$(title boot)" -k 0 -f "$BOOTLOG" </dev/null >/dev/null 2>&1 &
	echo $! > "$PID"
	;;
stop)
	stop_text
	;;
shutdown)
	# The kernel log only: an open boot log would keep UDISK from unmounting.
	[ -e "$FLAG" ] || exit 0
	stop_text
	oakmoss-fbtext -t "$(title "$2")" -k "$(cut -d' ' -f1 /proc/uptime)" </dev/null >/dev/null 2>&1 &
	;;
*)
	echo "usage: $0 start | stop | shutdown <kind>" >&2
	exit 2
	;;
esac
exit 0
