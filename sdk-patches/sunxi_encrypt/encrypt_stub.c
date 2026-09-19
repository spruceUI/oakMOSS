/* sunxi_encrypt stand-in for boards that have no matching MagicX object.
 *
 * MagicX's prebuilt drivers/char/sunxi_encrypt/encrypt (one per board) is an
 * authentication driver: at probe it checks the board it is running on and, when
 * the answer does not match what was compiled into it, restarts the kernel. A
 * kernel linked with another board's object therefore reboots forever at the
 * boot logo (XU20, 2026-09-17).
 *
 * This file provides the same misc device, /dev/sunxi_encrypt, with no chip
 * access and no restart. spruce never talks to the device; MagicX's own
 * launcher does, and it is not on these cards. oakMOSS, GPL-2.0 (a kernel
 * driver).
 */
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/uaccess.h>

static const char stub_answer[] = "oakmoss-stub\n";

static ssize_t stub_read(struct file *f, char __user *buf, size_t n, loff_t *pos)
{
	return simple_read_from_buffer(buf, n, pos, stub_answer, sizeof(stub_answer) - 1);
}

static ssize_t stub_write(struct file *f, const char __user *buf, size_t n, loff_t *pos)
{
	return n;
}

static const struct file_operations stub_fops = {
	.owner = THIS_MODULE,
	.read = stub_read,
	.write = stub_write,
	.llseek = default_llseek,
};

static struct miscdevice stub_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "sunxi_encrypt",
	.fops = &stub_fops,
};

static int __init stub_init(void)
{
	int ret = misc_register(&stub_dev);

	pr_info("sunxi_encrypt: oakMOSS stand-in registered (no chip check)\n");
	return ret;
}

static void __exit stub_exit(void)
{
	misc_deregister(&stub_dev);
}

module_init(stub_init);
module_exit(stub_exit);
MODULE_LICENSE("GPL");
