#
# Copyright (C) 2007-2015 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

# oakMOSS (sdk-patches/bash-5.2.37 replaces the SDK's 4.3.42 package): bash 5.2 with its official
# patches 001-037 (upstream/, applied unchanged, in order, after the unpack). The SDK's 4.3 patches
# do not carry over, and neither does tree patch 132: 5.2 ships readline 8.2, newer than the SDK's
# libreadline 6.3, so it links its own copy statically and this package no longer needs libreadline.
#
# The configure cache values are the ones a cross build cannot measure, and bash's defaults for
# them cost features: job control "missing", named pipes "missing". Process substitution goes
# through named pipes rather than /dev/fd (HAVE_DEV_FD undefined): a port script's
# `exec > >(tee log)` needs one or the other, and the image has no /dev/fd until the launcher
# makes it. The last three values (wait-status shift 8, the fnmatch equivalence-class fallback, ulimit -n) are what
# bash's own tests measured on a native glibc build; a cross build defaults them to 0, no and no.
# scripts/lib.sh pins the tarball (BASH_*), fetch-inputs.sh downloads it and
# apply-sdk-mods.sh stages it into dl/.
BASE_VERSION:=5.2

PKG_NAME:=bash
PKG_PATCHLEVEL:=37
PKG_VERSION:=$(BASE_VERSION).$(PKG_PATCHLEVEL)
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(BASE_VERSION).tar.gz
PKG_SOURCE_URL:=@GNU/bash
PKG_MD5SUM:=cfb4cf795fc239667f187b3d6b3d396f
PKG_BUILD_DIR:=$(COMPILE_DIR)/$(PKG_NAME)-$(BASE_VERSION)

PKG_LICENSE:=GPL-3.0+
PKG_LICENSE_FILES:=COPYING
PKG_MAINTAINER:=Marcel Denia <naoir@gmx.net>

PKG_CHECK_FORMAT_SECURITY:=0
include $(BUILD_DIR)/package.mk

define Package/bash
  SECTION:=utils
  CATEGORY:=Utilities
  SUBMENU:=Shells
  TITLE:=The GNU Bourne Again SHell
  DEPENDS:=+libncurses
  URL:=http://www.gnu.org/software/bash/
endef

define Package/bash/description
  Bash is an sh-compatible command language interpreter that executes
  commands read from the standard input or from a file. Bash also
  incorporates useful features from the Korn and C shells (ksh and csh).
endef

define Build/Prepare
	$(call Build/Prepare/Default)
	cat $(sort $(wildcard $(CURDIR)/upstream/bash52-*)) | $(PATCH) -d $(PKG_BUILD_DIR) -p0 -s
endef

CONFIGURE_VARS += \
	bash_cv_job_control_missing=present \
	bash_cv_sys_named_pipes=present \
	bash_cv_dev_fd=absent \
	bash_cv_getcwd_malloc=yes \
	bash_cv_printf_a_format=yes \
	bash_cv_func_sigsetjmp=present \
	bash_cv_func_strcoll_broken=no \
	bash_cv_func_ctype_nonascii=no \
	bash_cv_wcontinued_broken=no \
	bash_cv_unusable_rtsigs=no \
	bash_cv_wexitstatus_offset=8 \
	bash_cv_fnmatch_equiv_fallback=yes \
	bash_cv_ulimit_maxfds=yes

define Build/Configure
	$(call Build/Configure/Default, \
		--without-bash-malloc \
		--disable-nls \
		--bindir=/bin \
	)
endef

# The readline libraries by path: with -lreadline the toolchain wrapper finds the staging directory's
# libreadline 6.3 first, which has none of the 8.x functions bash 5.2 calls.
# Only the shell: `make install` would go on to the manual and the info pages, which a cross
# build cannot make and an image does not carry.
define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/builtins LDFLAGS_FOR_BUILD= mkbuiltins
	$(MAKE) -C $(PKG_BUILD_DIR) SHELL="/bin/bash" \
		READLINE_LIB=./lib/readline/libreadline.a HISTORY_LIB=./lib/readline/libhistory.a bash
endef

define Package/bash/postinst
#!/bin/sh
grep bash $${IPKG_INSTROOT}/etc/shells || \
	echo "/bin/bash" >> $${IPKG_INSTROOT}/etc/shells
	echo "/bin/rbash" >> $${IPKG_INSTROOT}/etc/shells
endef

define Package/bash/install
	$(INSTALL_DIR) $(1)/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bash $(1)/bin/
	ln -sf bash $(1)/bin/rbash
endef


$(eval $(call BuildPackage,bash))
