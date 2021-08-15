#-------------------------------------------------------------------------------
#
#  Copyright (C) 2013,2014,2017 Curt Brune <curt@cumulusnetworks.com>
#  Copyright (C) 2014,2015,2016,2017 david_yang <david_yang@accton.com>
#
#  SPDX-License-Identifier:     GPL-2.0
#
#-------------------------------------------------------------------------------
#
# makefile fragment that defines the build of the onie cross-compiled U-Boot
#

ATF_VERSION		?= 2.5
ATF_TARBALL		= v2.5.tar.gz
ATF_TARBALL_URLS	+= $(ONIE_MIRROR) https://github.com/ARM-software/arm-trusted-firmware/archive/refs/tags/
ATF_BUILD_DIR		= $(MBUILDDIR)/atf
ATF_DIR		= $(ATF_BUILD_DIR)/atf-$(ATF_VERSION)

ATF_SRCPATCHDIR	= $(PATCHDIR)/atf/$(ATF_VERSION)
ATF_CMNPATCHDIR	= $(PATCHDIR)/atf/common
ATF_PATCHDIR		= $(ATF_BUILD_DIR)/patch
ATF_DOWNLOAD_STAMP	= $(DOWNLOADDIR)/atf-download-$(ATF_VERSION)
ATF_SOURCE_STAMP	= $(STAMPDIR)/atf-source
ATF_PATCH_STAMP	= $(STAMPDIR)/atf-patch
ATF_BUILD_STAMP	= $(STAMPDIR)/atf-build
ATF_INSTALL_STAMP	= $(STAMPDIR)/atf-install
ATF_STAMP		= $(ATF_SOURCE_STAMP) \
			  $(ATF_PATCH_STAMP) \
			  $(ATF_BUILD_STAMP) \
			  $(ATF_INSTALL_STAMP)

#UBOOT			= $(ATF_INSTALL_STAMP)

ATF_NAME		= $(shell echo $(MACHINE_PREFIX) | tr [:lower:] [:upper:])
ATF_MACHINE		?= $(ATF_NAME)
ATF_BL1_BIN		= $(ATF_BUILD_DIR)/build/$(ATF_MACHINE)/release/bl1.bin
ATF_FIP_BIN		= $(ATF_BUILD_DIR)/build/$(ATF_MACHINE)/release/fip.bin
ATF_INSTALL_IMAGE	= $(IMAGEDIR)/$(MACHINE_PREFIX).atf
#UPDATER_UBOOT		= $(MBUILDDIR)/u-boot.bin


ATF_IDENT_STRING	?= ONIE $(LSB_RELEASE_TAG)

PHONY += atf atf-download atf-source atf-patch atf-build \
	 atf-install atf-clean atf-download-clean

#-------------------------------------------------------------------------------

atf: $(ATF_STAMP)

DOWNLOAD += $(ATF_DOWNLOAD_STAMP)
atf-download: $(ATF_DOWNLOAD_STAMP)
$(ATF_DOWNLOAD_STAMP): $(PROJECT_STAMP)
	$(Q) rm -f $@ && eval $(PROFILE_STAMP)
	$(Q) echo "==== Getting upstream atf ===="
	$(Q) $(SCRIPTDIR)/fetch-package $(DOWNLOADDIR) $(UPSTREAMDIR) \
		$(ATF_TARBALL) $(ATF_TARBALL_URLS)
	$(Q) touch $@

SOURCE += $(ATF_PATCH_STAMP)
atf-source: $(ATF_SOURCE_STAMP)
$(ATF_SOURCE_STAMP): $(TREE_STAMP) | $(ATF_DOWNLOAD_STAMP)
	$(Q) rm -f $@ && eval $(PROFILE_STAMP)
	$(Q) echo "==== Extracting upstream ATF ===="
	$(Q) $(SCRIPTDIR)/extract-package $(ATF_BUILD_DIR) $(DOWNLOADDIR)/$(ATF_TARBALL)
	$(Q) touch $@

#
# The atf patches are made up of a base set of platform independent
# patches with the current machine's platform dependent patches on
# top.
#
atf-patch: $(ATF_PATCH_STAMP)
$(ATF_PATCH_STAMP): $(ATF_CMNPATCHDIR)/* $(ATF_SRCPATCHDIR)/* $(MACHINEDIR)/atf/* $(ATF_SOURCE_STAMP)
	$(Q) rm -f $@ && eval $(PROFILE_STAMP)
	$(Q) echo "==== Patching atf ===="
	$(Q) [ -r $(MACHINEDIR)/atf/series ] || \
		(echo "Unable to find machine dependent atf patch series: $(MACHINEDIR)/atf/series" && \
		exit 1)
	$(Q) mkdir -p $(ATF_PATCHDIR)
	$(Q) cp $(ATF_SRCPATCHDIR)/series $(ATF_PATCHDIR)
	$(Q) $(SCRIPTDIR)/cp-machine-patches $(ATF_PATCHDIR) $(ATF_SRCPATCHDIR)/series	\
		$(ATF_SRCPATCHDIR) $(ATF_CMNPATCHDIR)
	$(Q) cat $(MACHINEDIR)/atf/series >> $(ATF_PATCHDIR)/series
	$(Q) $(SCRIPTDIR)/cp-machine-patches $(ATF_PATCHDIR) $(MACHINEDIR)/atf/series	\
		$(MACHINEDIR)/atf $(MACHINEROOT)/atf
	$(Q) $(SCRIPTDIR)/apply-patch-series $(ATF_PATCHDIR)/series $(ATF_DIR)
	$(Q) echo "#include <version.h>" > $(ATF_DIR)/include/configs/onie_version.h
	$(Q) echo "#define ONIE_VERSION \
		\"onie_version=$(LSB_RELEASE_TAG)\\0\"	\
		\"onie_vendor_id=$(VENDOR_ID)\\0\"	\
		\"onie_platform=$(PLATFORM)\\0\"	\
		\"onie_machine=$(MACHINE)\\0\"		\
		\"platform=$(MACHINE)\\0\"		\
		\"onie_machine_rev=$(MACHINE_REV)\\0\"	\
		\"dhcp_vendor-class-identifier=$(PLATFORM)\\0\"	\
		\"dhcp_user-class=$(PLATFORM)_uboot\\0\"	\
		\"onie_build_date=$(ONIE_BUILD_DATE)\\0\"	\
		\"onie_ATF_version=\" U_BOOT_VERSION_STRING \"\\0\" \
		\"ver=\" U_BOOT_VERSION_STRING \"\\0\" \
		" >> $(ATF_DIR)/include/configs/onie_version.h
	$(Q) echo '#define CONFIG_IDENT_STRING " - $(ATF_IDENT_STRING)"' \
		>> $(ATF_DIR)/include/configs/onie_version.h
	$(Q) echo '#define PLATFORM_STRING "$(PLATFORM)"' \
		>> $(ATF_DIR)/include/configs/onie_version.h
	$(Q) touch $@

ifndef MAKE_CLEAN
ATF_NEW = $(shell test -d $(ATF_DIR) && test -f $(ATF_BUILD_STAMP) && \
	       find -L $(ATF_DIR) -newer $(ATF_BUILD_STAMP) -print -quit)
endif

$(ATF_IMAGE): $(ATF_PATCH_STAMP) $(ATF_NEW) | $(XTOOLS_BUILD_STAMP)
	$(Q) echo "==== Building atf ($(ATF_MACHINE)) ===="
	$(Q) PATH='$(CROSSBIN):$(PATH)' $(MAKE) -C $(ATF_DIR)		\
		CROSS_COMPILE=$(CROSSPREFIX) O=$(ATF_BUILD_DIR)/$(ATF_MACHINE) \
		$(ATF_MACHINE)_config
	$(Q) PATH='$(CROSSBIN):$(PATH)' $(MAKE) -C $(ATF_DIR)		\
		CROSS_COMPILE=$(CROSSPREFIX) O=$(ATF_BUILD_DIR)/$(ATF_MACHINE) \
		$(ATF_TARGET)

atf-build: $(ATF_BUILD_STAMP)
$(ATF_BUILD_STAMP): $(ATF_IMAGE)
	$(Q) rm -f $@ && eval $(PROFILE_STAMP)
	$(Q) touch $@

atf-install: $(ATF_INSTALL_STAMP)
$(ATF_INSTALL_STAMP): $(ATF_BUILD_STAMP)
	$(Q) echo "==== Installing atf ($(MACHINE_PREFIX)) ===="
	$(Q) cp -v $(ATF_IMAGE) $(ATF_INSTALL_IMAGE)
	$(Q) chmod a-x $(ATF_INSTALL_IMAGE)
	$(Q) ln -sf $(ATF_BIN) $(MBUILDDIR)/u-boot.bin
ifeq ($(ATF_PBL_ENABLE),yes)
	$(Q) ln -sf $(ATF_PBL) $(MBUILDDIR)/u-boot.pbl
endif
	$(Q) touch $@

MACHINE_CLEAN += atf-clean
atf-clean:
	$(Q) rm -rf $(ATF_BUILD_DIR)
	$(Q) rm -f $(ATF_STAMP)
	$(Q) rm -f $(ATF_INSTALL_IMAGE)
	$(Q) echo "=== Finished making $@ for $(PLATFORM)"

DOWNLOAD_CLEAN += atf-download-clean
atf-download-clean:
	$(Q) rm -f $(ATF_DOWNLOAD_STAMP) $(DOWNLOADDIR)/$(ATF_TARBALL)

#-------------------------------------------------------------------------------
#
# Local Variables:
# mode: makefile-gmake
# End:
