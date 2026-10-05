#
# Copyright (C) 2006-2015 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

# oakMOSS (sdk-patches/openssl-1.1.1w replaces the SDK's 1.1.0i package): OpenSSL 1.1.1w,
# the last 1.1.1 release, keeps the libssl.so.1.1 / libcrypto.so.1.1 sonames and is a
# superset of 1.1.0i. spruce's own 1.1.1 copies (libcurl, libssl, libssh) need version
# OPENSSL_1_1_1 and the ENGINE, COMP, Camellia, SEED and IDEA functions; whenever this
# library loads first they could not start against 1.1.0i (configs/ext-armgnu13.config
# turns those options on). Configure and compile follow OpenWrt 22.03's 1.1.1w package
# (--libdir=lib, --cross-compile-prefix, parallel make); patches/ are OpenWrt 22.03's
# 100/110/120/130. The SDK's 1.1.0 patches are not carried: its AF_ALG CTS and no-rsa
# patches serve options oakMOSS does not build, 180 patches a file 1.1.1 does not have
# and 200 is upstream since 1.1.1. scripts/lib.sh pins the tarball (OPENSSL_*),
# fetch-inputs.sh downloads it and apply-sdk-mods.sh stages it into dl/.
PKG_NAME:=openssl
PKG_BASE:=1.1.1
PKG_BUGFIX:=w
PKG_VERSION:=$(PKG_BASE)$(PKG_BUGFIX)
PKG_RELEASE:=1
PKG_USE_MIPS16:=0

PKG_BUILD_PARALLEL:=1
HOST_BUILD_PARALLEL:=0

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:= \
	https://www.openssl.org/source/old/$(PKG_BASE)/ \
	https://github.com/openssl/openssl/releases/download/OpenSSL_$(subst .,_,$(PKG_VERSION))/
PKG_HASH:=cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8

HOST_BUILD_DIR:=$(COMPILE_DIR_HOST)/$(PKG_NAME)-$(PKG_VERSION)

PKG_LICENSE:=OpenSSL
PKG_LICENSE_FILES:=LICENSE
PKG_CPE_ID:=cpe:/a:openssl:openssl
PKG_CONFIG_DEPENDS:= \
	CONFIG_OPENSSL_ENGINE \
	CONFIG_OPENSSL_ENGINE_AFALG \
	CONFIG_OPENSSL_ENGINE_CRYPTO \
	CONFIG_OPENSSL_ENGINE_DIGEST \
	CONFIG_OPENSSL_ENGINE_PADLOCK \
	CONFIG_OPENSSL_NO_SSE2 \
	CONFIG_OPENSSL_OPTIMIZE_SPEED \
	CONFIG_OPENSSL_WITH_ASM \
	CONFIG_OPENSSL_WITH_ASYNC \
	CONFIG_OPENSSL_WITH_CAMELLIA \
	CONFIG_OPENSSL_WITH_CMS \
	CONFIG_OPENSSL_WITH_COMPRESSION \
	CONFIG_OPENSSL_WITH_DEPRECATED \
	CONFIG_OPENSSL_WITH_DTLS \
	CONFIG_OPENSSL_WITH_EC \
	CONFIG_OPENSSL_WITH_EC2M \
	CONFIG_OPENSSL_WITH_GOST \
	CONFIG_OPENSSL_WITH_IDEA \
	CONFIG_OPENSSL_WITH_MDC2 \
	CONFIG_OPENSSL_WITH_PSK \
	CONFIG_OPENSSL_WITH_RFC3779 \
	CONFIG_OPENSSL_WITH_SEED \
	CONFIG_OPENSSL_WITH_SRP \
	CONFIG_OPENSSL_WITH_WHIRLPOOL

include $(BUILD_DIR)/package.mk
include $(BUILD_DIR)/host-build.mk

ifneq ($(CONFIG_CCACHE),)
HOSTCC=$(HOSTCC_NOCACHE)
HOSTCXX=$(HOSTCXX_NOCACHE)
endif

define Package/openssl/Default
  TITLE:=Open source SSL toolkit
  URL:=http://www.openssl.org/
  SECTION:=libs
  CATEGORY:=Libraries
endef

define Package/libopenssl/config
source "$(SOURCE)/Config.in"
endef

define Package/openssl/Default/description
The OpenSSL Project is a collaborative effort to develop a robust,
commercial-grade, full-featured, and Open Source toolkit implementing the
Transport Layer Security (TLS) and Secure Sockets Layer (SSL) protocols as well
as a full-strength general-purpose cryptography library.
endef

define Package/libopenssl
$(call Package/openssl/Default)
  SUBMENU:=SSL
  DEPENDS:=+OPENSSL_WITH_COMPRESSION:zlib
  TITLE+= (libraries)
  ABI_VERSION:=$(PKG_VERSION)
  MENU:=1
endef

define Package/libopenssl/description
$(call Package/openssl/Default/description)
This package contains the OpenSSL shared libraries, needed by other programs.
endef

define Package/openssl-util
  $(call Package/openssl/Default)
  SECTION:=utils
  CATEGORY:=Utilities
  DEPENDS:=+libopenssl
  TITLE+= (utility)
endef

define Package/openssl-util/conffiles
/etc/ssl/openssl.cnf
endef

define Package/openssl-util/description
$(call Package/openssl/Default/description)
This package contains the OpenSSL command-line utility.
endef

define Package/openssl-util-test
  $(call Package/openssl/Default)
  SECTION:=utils
  CATEGORY:=Utilities
  DEPENDS:=+libopenssl
  TITLE+= (utility)
endef

define Package/openssl-util-test/description
$(call Package/openssl/Default/description)
This package contains the OpenSSL test utility.
endef

define Package/libopenssl-afalg
  $(call Package/openssl/Default)
  SUBMENU:=SSL
  TITLE:=AFALG hardware acceleration engine
  DEPENDS:=libopenssl @OPENSSL_ENGINE +@KERNEL_AIO @!LINUX_3_18 @LINUX_4_4||@LINUX_4_9
endef

define Package/libopenssl-padlock
  $(call Package/openssl/Default)
  SUBMENU:=SSL
  TITLE:=VIA Padlock hardware acceleration engine
  DEPENDS:=libopenssl @OPENSSL_ENGINE @TARGET_x86
endef

OPENSSL_OPTIONS:= shared no-err no-ssl3-method no-tls1-method no-tls1_1-method

ifndef CONFIG_OPENSSL_WITH_EC
  OPENSSL_OPTIONS += no-ec
endif

ifndef CONFIG_OPENSSL_WITH_EC2M
  OPENSSL_OPTIONS += no-ec2m
endif

ifndef CONFIG_OPENSSL_WITH_CAMELLIA
  OPENSSL_OPTIONS += no-camellia
endif

ifndef CONFIG_OPENSSL_WITH_IDEA
  OPENSSL_OPTIONS += no-idea
endif

ifndef CONFIG_OPENSSL_WITH_SEED
  OPENSSL_OPTIONS += no-seed
endif

ifndef CONFIG_OPENSSL_WITH_MDC2
  OPENSSL_OPTIONS += no-mdc2
endif

ifndef CONFIG_OPENSSL_WITH_WHIRLPOOL
  OPENSSL_OPTIONS += no-whirlpool
endif

ifndef CONFIG_OPENSSL_WITH_CMS
  OPENSSL_OPTIONS += no-cms
endif

ifndef CONFIG_OPENSSL_WITH_RFC3779
  OPENSSL_OPTIONS += no-rfc3779
endif

ifndef CONFIG_OPENSSL_WITH_DEPRECATED
  OPENSSL_OPTIONS += no-deprecated
endif

ifeq ($(CONFIG_OPENSSL_OPTIMIZE_SPEED),y)
  TARGET_CFLAGS := $(filter-out -O%,$(TARGET_CFLAGS)) -O3
  OPENSSL_OPTIONS += -DOPENSSL_SMALL_FOOTPRINT
endif

ifdef CONFIG_OPENSSL_ENGINE

  ifdef CONFIG_OPENSSL_ENGINE_CRYPTO
    OPENSSL_OPTIONS += -DHAVE_CRYPTODEV
    ifdef CONFIG_OPENSSL_ENGINE_DIGEST
      OPENSSL_OPTIONS += -DUSE_CRYPTODEV_DIGESTS
    endif
  endif

  ifndef CONFIG_OPENSSL_DYNAMIC_ENGINE
    OPENSSL_OPTIONS += no-dynamic-engine
  endif

  ifndef CONFIG_PACKAGE_libopenssl-afalg
    OPENSSL_OPTIONS += no-afalgeng
  else
    ifneq ($(CONFIG_PLATFORM_v5)$(CONFIG_PLATFORM_r328s2)$(CONFIG_PLATFORM_r328s3)$(CONFIG_PLATFORM_r18)$(CONFIG_PLATFORM_r329),)
      OPENSSL_OPTIONS += -DSUPPORT_CE_V3_1
    else
      OPENSSL_OPTIONS += -DSUPPORT_CE_V3_2
    endif
    ifdef CONFIG_OPENSSL_AFALG_ZERO_COPY
      OPENSSL_OPTIONS += -DALG_ZERO_COPY
    endif
  endif
  ifndef CONFIG_PACKAGE_libopenssl-padlock
    OPENSSL_OPTIONS += no-hw-padlock
  endif
else
  OPENSSL_OPTIONS += no-engine
endif

ifndef CONFIG_OPENSSL_WITH_ASYNC
  OPENSSL_OPTIONS += no-async
endif

ifndef CONFIG_OPENSSL_WITH_GOST
  OPENSSL_OPTIONS += no-gost
endif

ifndef CONFIG_OPENSSL_WITH_DTLS
  OPENSSL_OPTIONS += no-dtls
endif
ifdef CONFIG_OPENSSL_WITH_COMPRESSION
  OPENSSL_OPTIONS += zlib-dynamic
else
  OPENSSL_OPTIONS += no-comp
endif

ifndef CONFIG_OPENSSL_WITH_PSK
  OPENSSL_OPTIONS += no-psk
endif

ifndef CONFIG_OPENSSL_WITH_SRP
  OPENSSL_OPTIONS += no-srp
endif

ifndef CONFIG_OPENSSL_WITH_ASM
  OPENSSL_OPTIONS += no-asm
endif

ifdef CONFIG_OPENSSL_NO_SSE2
  OPENSSL_OPTIONS += no-sse2
endif

ifndef CONFIG_OPENSSL_WITH_RSA
  OPENSSL_OPTIONS += no-rsa
endif

ifndef CONFIG_OPENSSL_WITH_DES
  OPENSSL_OPTIONS += no-des
endif

ifdef CONFIG_OPENSSL_COMPAT_API
  OPENSSL_OPTIONS += --api=$(CONFIG_OPENSSL_COMPAT_API)
endif

ifndef CONFIG_PACKAGE_openssl-util-test
  OPENSSL_OPTIONS += no-unit-test
endif

ifdef CONFIG_OPENSSL_LEAST_ALG
OPENSSL_OPTIONS += \
no-asm \
no-idea \
no-camellia \
no-seed \
no-bf \
no-blake2 \
no-capieng \
no-chacha \
no-cmac \
no-cms \
no-crypto-mdebug \
no-crypto-mdebug-backtrace \
no-ct \
no-dgram \
no-dso \
no-ec_nistp_64_gcc_128 \
no-egd \
no-filenames \
no-fuzz-libfuzzer \
no-fuzz-afl \
no-gost \
no-heartbeats \
no-msan \
no-ocb \
no-ocsp \
no-poly1305 \
no-rdrand \
no-rmd160 \
no-scrypt \
no-sctp \
no-srtp \
no-ssl \
no-ssl3 \
no-ssl-trace \
no-tls \
no-cast \
no-rc2 \
no-rc4 \
no-rc5 \
no-md2 \
no-md4 \
no-ripemd \
no-mdc2 \
no-dsa \
no-dh \
no-ec \
no-ecdsa \
no-ecdh \
no-ssl2 \
no-ssl3 \
no-zlib \
no-zlib-dynamic \
no-comp \
no-ts \
no-ubsan \
no-asan \
no-ui \
no-whirlpool \
no-rfc3779 \
no-weak-ssl-ciphers
endif

ifeq ($(TARGET_ARCH), riscv)
OPENSSL_TARGET:=linux-generic64
else
OPENSSL_TARGET:=linux-$(CONFIG_ARCH)-openwrt
endif

ifeq ($(CONFIG_x86_64)$(CONFIG_mips64)$(CONFIG_mips64el),y)
  OPENSSL_MAKEFLAGS += LIBDIR=lib
endif

STAMP_CONFIGURED := $(STAMP_CONFIGURED)_$(word 1,$(shell echo $(OPENSSL_OPTIONS) | md5sum))

HOST_CPPFLAGS += $(HOST_FPIC)
OPENSSL_HOST_TARGET:=linux-x86_64

define Build/Configure
	(cd $(PKG_BUILD_DIR); \
		./Configure $(OPENSSL_TARGET) \
			--prefix=/usr \
			--libdir=lib \
			--openssldir=/etc/ssl \
			--cross-compile-prefix="$(TARGET_CROSS)" \
			$(TARGET_CFLAGS) \
			$(TARGET_CPPFLAGS) \
			$(TARGET_LDFLAGS) \
			$(OPENSSL_OPTIONS) && \
		{ [ -f $(STAMP_CONFIGURED) ] || make clean; } \
	)
endef

TARGET_CFLAGS += $(FPIC) -I$(CURDIR)/include -ffunction-sections -fdata-sections
TARGET_LDFLAGS += -Wl,--gc-sections

define Build/Compile
	+$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		OPENWRT_OPTIMIZATION_FLAGS="$(TARGET_CFLAGS)" \
		$(OPENSSL_MAKEFLAGS) \
		all
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		DESTDIR="$(PKG_INSTALL_DIR)" \
		$(OPENSSL_MAKEFLAGS) \
		install_sw install_ssldirs
endef

define Build/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_BUILD_DIR)/usr/lib/{libssl,libcrypto].so* $(1)/usr/lib/
	$(if $(CONFIG_OPENSSL_ENGINE),$(INSTALL_DIR) $(1)/usr/lib/engines-1.1)
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_INSTALL_DIR)/usr/include/openssl $(1)/usr/include/
	$(INSTALL_DIR) $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/lib{crypto,ssl}.{a,so*} $(1)/usr/lib/
	$(INSTALL_DIR) $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/{openssl,libcrypto,libssl}.pc $(1)/usr/lib/pkgconfig/
	[ -n "$(TARGET_LDFLAGS)" ] && $(SED) 's#$(TARGET_LDFLAGS)##g' $(1)/usr/lib/pkgconfig/{openssl,libcrypto,libssl}.pc || true
endef

define Package/libopenssl/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libcrypto.so* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libssl.so* $(1)/usr/lib/
	$(if $(CONFIG_OPENSSL_ENGINE),$(INSTALL_DIR) $(1)/usr/lib/engines-1.1)
endef

define Package/openssl-util/install
	$(INSTALL_DIR) $(1)/etc/ssl
	$(CP) $(PKG_INSTALL_DIR)/etc/ssl/openssl.cnf $(1)/etc/ssl/
	$(INSTALL_DIR) $(1)/etc/ssl/certs
	$(INSTALL_DIR) $(1)/etc/ssl/private
	chmod 0700 $(1)/etc/ssl/private
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/openssl $(1)/usr/bin/
endef

define Package/openssl-util-test/install
	true
endef

ifeq ($(CONFIG_OPENSSL_DYNAMIC_ENGINE),y)
define Package/libopenssl-afalg/install
	$(INSTALL_DIR) $(1)/usr/lib/engines-1.1
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/lib/engines-1.1/afalg.so $(1)/usr/lib/engines-1.1
endef
endif

define Package/libopenssl-padlock/install
	$(INSTALL_DIR) $(1)/usr/lib/engines-1.1
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/lib/engines-1.1/padlock.so $(1)/usr/lib/engines-1.1
endef

define Host/Configure
	[ -f $(HOST_STAMP_CONFIGURED) ] || { \
		rm -f $(HOST_BUILD_DIR)/*.so.* $(HOST_BUILD_DIR)/*.a; \
		find $(HOST_BUILD_DIR) -name \*.o | xargs rm -f; \
	}
	(cd $(HOST_BUILD_DIR); \
		./Configure "$(OPENSSL_HOST_TARGET)" \
			--prefix=/ \
			--openssldir=/etc/ssl \
			$(HOST_CPPFLAGS) \
			$(HOST_LDFLAGS) -ldl \
			$(OPENSSL_NO_CIPHERS) \
			shared zlib-dynamic \
	)
endef

define Host/Compile
	+$(MAKE) $(PKG_JOBS) -C $(HOST_BUILD_DIR) \
		CC="$(HOSTCC)" \
		all
#	+$(MAKE) -C $(HOST_BUILD_DIR) \
#		CC="$(HOSTCC)" \
#		install_sw install_ssldirs
endef

define Host/Install
	$(MAKE) -C $(HOST_BUILD_DIR) \
		CC="$(HOSTCC)" \
		DESTDIR="$(STAGING_DIR)/host" \
		install_sw install_ssldirs

	$(INSTALL_DIR) $(STAGING_DIR)/host/lib
	$(INSTALL_DIR) $(STAGING_DIR)/host/lib/pkgconfig
	$(CP) $(STAGING_DIR)/host/lib64/lib{crypto,ssl}.{a,so*} $(STAGING_DIR)/host/lib
	$(CP) $(STAGING_DIR)/host/lib64/pkgconfig/{openssl,libcrypto,libssl}.pc $(STAGING_DIR)/host/lib/pkgconfig/
endef

$(eval $(call HostBuild))
$(eval $(call BuildPackage,libopenssl))
$(eval $(call BuildPackage,libopenssl-afalg))
$(eval $(call BuildPackage,libopenssl-padlock))
$(eval $(call BuildPackage,openssl-util))
$(eval $(call BuildPackage,openssl-util-test))

