/*
 * oakmoss-sd1part: the SPRUCEOS partition in SD1's free tail (docs/cards.md).
 *
 *   oakmoss-sd1part <disk>       find, reattach or add SPRUCEOS at 2 GiB
 *   oakmoss-sd1part -n <disk>    the same, writing nothing
 *
 * Prints "<state> <partition number>", state present, reattached (a FAT32 volume was already
 * at 2 GiB: the card was re-flashed after its first boot) or new (to be formatted), or
 * "none <reason>" and exits 1. The backup GPT moves to the end of the card, the hybrid MBR
 * gets an entry too (PCs read it), and the running kernel learns the partition through BLKPG.
 * Static, built by scripts/build.sh: the image has no GPT tool (util-linux 2.25 sfdisk is MBR only).
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <linux/blkpg.h>
#include <linux/fs.h>

#define SECTOR 512
#define START 4194304ULL		/* 2 GiB: clear of the image and room for it to grow */
#define MIN_SECTORS 1048576ULL		/* 512 MiB: smaller cards get no SPRUCEOS */
#define ALIGN 2048ULL			/* the end is rounded down to 1 MiB */
#define MAX_ENTRIES 256

static const char NAME[] = "SPRUCEOS";
/* Microsoft basic data, EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, so PCs mount it */
static const uint8_t BASIC_DATA[16] = { 0xa2, 0xa0, 0xd0, 0xeb, 0xe5, 0xb9, 0x33, 0x44,
					0x87, 0xc0, 0x68, 0xb6, 0xb7, 0x26, 0x99, 0xc7 };

static int fd, dry;
static uint8_t mbr[SECTOR], hdr[SECTOR], ent[MAX_ENTRIES * 128];

static uint32_t crc32(const uint8_t *p, size_t n)
{
	uint32_t c = 0xffffffff;
	while (n--) {
		c ^= *p++;
		for (int k = 0; k < 8; k++)
			c = (c >> 1) ^ (0xedb88320 & -(c & 1));
	}
	return ~c;
}

static uint32_t le32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint64_t le64(const uint8_t *p) { return le32(p) | (uint64_t)le32(p + 4) << 32; }
static void put32(uint8_t *p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = v >> (8 * i); }
static void put64(uint8_t *p, uint64_t v) { for (int i = 0; i < 8; i++) p[i] = v >> (8 * i); }

static int none(const char *why)
{
	printf("none %s\n", why);
	return 1;
}

static int rd(void *buf, size_t n, uint64_t lba)
{
	return pread(fd, buf, n, lba * SECTOR) == (ssize_t)n ? 0 : -1;
}

static int wfd = -1;
static int wr(const void *buf, size_t n, uint64_t lba)
{
	return dry || pwrite(wfd, buf, n, lba * SECTOR) == (ssize_t)n ? 0 : -1;
}

static int is_spruceos(const uint8_t *e)
{
	for (size_t i = 0; i < 36; i++) {
		uint16_t c = e[56 + 2 * i] | e[57 + 2 * i] << 8;
		if (c != (i < sizeof NAME - 1 ? (uint8_t)NAME[i] : 0))
			return 0;
	}
	return 1;
}

static int empty(const uint8_t *e)
{
	for (int i = 0; i < 16; i++)
		if (e[i])
			return 0;
	return 1;
}

/* The hybrid MBR's entry for the partition (type 0x0c, LBA only). The image's MBR has the
 * bootloader's FAT and a 0xee entry over the GPT; a purely protective MBR is left alone. */
static void mbr_entry(uint64_t start, uint64_t sectors)
{
	uint8_t *slot = NULL;
	int other = 0;
	if (start > 0xffffffffULL || mbr[510] != 0x55 || mbr[511] != 0xaa)
		return;
	for (int i = 0; i < 4; i++) {
		uint8_t *p = mbr + 446 + 16 * i;
		if (p[4] && p[4] != 0xee)
			other = 1;
		if (p[4] && le32(p + 8) == start)
			slot = p;
	}
	if (!other)
		return;
	for (int i = 0; i < 4 && !slot; i++) {
		uint8_t *p = mbr + 446 + 16 * i;
		if (!p[4] && !le32(p + 12))
			slot = p;
	}
	if (!slot)
		return;
	static const uint8_t chs[3] = { 0xfe, 0xff, 0xff };
	slot[0] = 0;
	memcpy(slot + 1, chs, 3);
	slot[4] = 0x0c;
	memcpy(slot + 5, chs, 3);
	put32(slot + 8, start);
	put32(slot + 12, sectors > 0xffffffffULL ? 0xffffffff : sectors);
}

static void seal(uint8_t *h, uint64_t my, uint64_t alt, uint64_t entries, uint32_t ecrc)
{
	put64(h + 24, my);
	put64(h + 32, alt);
	put64(h + 72, entries);
	put32(h + 88, ecrc);
	put32(h + 16, 0);
	put32(h + 16, crc32(h, le32(h + 12)));
}

int main(int argc, char **argv)
{
	int a = 1;
	if (argc > 1 && !strcmp(argv[1], "-n"))
		dry = 1, a = 2;
	if (argc != a + 1) {
		fprintf(stderr, "usage: oakmoss-sd1part [-n] <disk>\n");
		return 2;
	}
	/* Read-only until there is something to write: udev re-reads a disk closed after a write. */
	fd = open(argv[a], O_RDONLY);
	if (fd < 0)
		return none("cannot open the disk");
	struct stat st;
	uint64_t bytes = 0;
	int blk = !fstat(fd, &st) && S_ISBLK(st.st_mode);
	if (blk ? ioctl(fd, BLKGETSIZE64, &bytes) : (bytes = st.st_size, 0))
		return none("cannot size the disk");
	uint64_t disk = bytes / SECTOR;

	if (rd(mbr, SECTOR, 0) || rd(hdr, SECTOR, 1) || memcmp(hdr, "EFI PART", 8))
		return none("no GPT");
	uint32_t hsize = le32(hdr + 12), hcrc = le32(hdr + 16);
	uint8_t h[SECTOR];
	memcpy(h, hdr, SECTOR);
	put32(h + 16, 0);
	if (hsize < 92 || hsize > SECTOR || crc32(h, hsize) != hcrc)
		return none("GPT header damaged");
	uint64_t alt = le64(hdr + 32), first = le64(hdr + 40), elba = le64(hdr + 72);
	uint32_t count = le32(hdr + 80), esize = le32(hdr + 84);
	if (esize != 128 || !count || count > MAX_ENTRIES)
		return none("unexpected GPT entry layout");
	size_t elen = (size_t)count * esize;
	uint64_t esect = (elen + SECTOR - 1) / SECTOR;
	if (rd(ent, elen, elba) || crc32(ent, elen) != le32(hdr + 88))
		return none("GPT entries damaged");

	/* Where the backup goes: the end of this card. */
	uint64_t nalt = disk - 1, nbak = nalt - esect, nlast = nbak - 1;
	if (alt >= disk || alt < first)
		return none("GPT backup outside the card");

	int found = -1, free_slot = -1;
	uint64_t used = 0;
	for (uint32_t i = 0; i < count; i++) {
		uint8_t *e = ent + i * esize;
		if (empty(e)) {
			if (free_slot < 0)
				free_slot = i;
			continue;
		}
		if (is_spruceos(e)) {
			found = i;
			continue;
		}
		if (le64(e + 40) > used)
			used = le64(e + 40);
	}
	if (used >= START)
		return none("the partitions reach past 2 GiB");

	uint64_t start = START, end;
	const char *state;
	if (found >= 0) {
		uint8_t *e = ent + found * esize;
		end = le64(e + 40);
		if (le64(e + 32) != START || end > nlast || end < START)
			return none("SPRUCEOS is not where this tool puts it");
		state = "present";
	} else {
		if (nlast < START + MIN_SECTORS - 1)
			return none("the card is too small");
		if (free_slot < 0)
			return none("no free GPT entry");
		uint8_t bs[SECTOR];
		if (rd(bs, SECTOR, START))
			return none("cannot read the card at 2 GiB");
		if (bs[510] == 0x55 && bs[511] == 0xaa && !memcmp(bs + 82, "FAT32   ", 8) &&
		    (bs[11] | bs[12] << 8) == SECTOR && le32(bs + 32)) {
			end = START + le32(bs + 32) - 1;
			if (end > nlast)
				return none("the FAT32 volume at 2 GiB is larger than this card");
			state = "reattached";
		} else {
			end = (nlast + 1) / ALIGN * ALIGN - 1;
			state = "new";
		}
		found = free_slot;
		uint8_t *e = ent + found * esize;
		memset(e, 0, esize);
		memcpy(e, BASIC_DATA, 16);
		int rnd = open("/dev/urandom", O_RDONLY);
		if (rnd < 0 || read(rnd, e + 16, 16) != 16)
			return none("no random source for the partition GUID");
		close(rnd);
		e[16 + 7] = (e[16 + 7] & 0x0f) | 0x40;	/* version 4 */
		e[16 + 8] = (e[16 + 8] & 0x3f) | 0x80;
		put64(e + 32, start);
		put64(e + 40, end);
		for (size_t i = 0; i < sizeof NAME - 1; i++)
			e[56 + 2 * i] = NAME[i];
	}

	uint8_t m0[SECTOR];
	memcpy(m0, mbr, SECTOR);
	mbr_entry(start, end - start + 1);
	int changed = strcmp(state, "present") || alt != nalt || le64(hdr + 48) != nlast ||
		      memcmp(m0, mbr, SECTOR);
	if (changed) {
		/* Backup first, at the new end; then the primary; the MBR last. */
		uint32_t ecrc = crc32(ent, elen);
		uint8_t pri[SECTOR], bak[SECTOR];
		memcpy(pri, hdr, SECTOR);
		put64(pri + 48, nlast);
		memcpy(bak, pri, SECTOR);
		seal(bak, nalt, 1, nbak, ecrc);
		seal(pri, 1, nalt, elba, ecrc);
		uint8_t zero[SECTOR] = { 0 };
		if (!dry && (wfd = open(argv[a], O_RDWR)) < 0)
			return none("cannot open the disk for writing");
		if (wr(ent, elen, nbak) || wr(bak, SECTOR, nalt) || wr(ent, elen, elba) ||
		    wr(pri, SECTOR, 1) || wr(mbr, SECTOR, 0))
			return none("write failed");
		/* The old backup header, now in free space below 2 GiB, would confuse other tools. */
		if (alt != nalt && alt > used && alt < START && wr(zero, SECTOR, alt))
			return none("write failed");
		if (!dry && (fsync(wfd) || close(wfd)))
			return none("write failed");
	}

	if (blk && !dry) {
		struct blkpg_partition p = { .start = (long long)(start * SECTOR),
					     .length = (long long)((end - start + 1) * SECTOR),
					     .pno = found + 1 };
		struct blkpg_ioctl_arg arg = { .op = BLKPG_ADD_PARTITION, .datalen = sizeof p, .data = &p };
		if (ioctl(fd, BLKPG, &arg) && errno != EBUSY)
			return none("the kernel did not take the partition");
	}
	printf("%s %d\n", state, found + 1);
	return 0;
}
