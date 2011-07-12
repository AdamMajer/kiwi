#
# spec file for package kiwi (Version 3.74.2)
#
# Copyright (c) 2008 SUSE LINUX Products GmbH, Nuernberg, Germany.
# This file and all modifications and additions to the pristine
# package are under the same license as the package itself.
#
# Please submit bugfixes or comments via http://bugs.opensuse.org/
#

# needsrootforbuild

Url:            http://kiwi.berlios.de
%define sattools_version %(rpm -q --qf %{VERSION}-%{RELEASE} satsolver-tools)
Name:           kiwi
BuildRequires:  perl-XML-LibXML perl-libwww-perl perl-Config-IniFiles
BuildRequires:  hal-devel module-init-tools screen zlib-devel
BuildRequires:  gcc-c++ libxslt swig
%if %{suse_version} > 1020
BuildRequires:  fdupes
%endif
%ifarch %ix86 x86_64
BuildRequires:  syslinux
%endif
%if %{suse_version} > 1010
BuildRequires:  libqt4 libqt4-devel
%else
BuildRequires:  freetype2-devel libpng-devel qt qt-devel
%endif 
%if %{suse_version} > 1030
BuildRequires:  rpm-devel libexpat-devel libsatsolver-devel
%endif
%if %{suse_version} <= 1010
Requires:       qt
%endif
%ifarch %ix86 x86_64
%if %{suse_version} > 1010
Recommends:     squashfs
%endif
%endif
Requires:       perl = %{perl_version}
Requires:       perl-XML-LibXML perl-libwww-perl screen coreutils
Requires:       perl-XML-LibXML-Common perl-XML-SAX perl-Config-IniFiles
Requires:       kiwi-tools libxslt checkmedia
%ifarch %ix86 x86_64
Requires:       master-boot-code
%endif
%if %{suse_version} > 1030
Requires:       satsolver-tools
%endif
Summary:        OpenSuSE - KIWI Image System
Version:        3.74.2
Release:        80
Group:          System/Management
License:        GPL v2 or later
Source:         %{name}.tar.bz2
Source1:        %{name}-rpmlintrc
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Recommends:     smart zypper

%description
The OpenSuSE KIWI Image System provides a complete operating system
image solution for Linux supported hardware platforms as well as for
virtualization systems like Xen.

Authors:
--------
    Marcus Schaefer <ms@novell.com>

%package -n kiwi-instsource
License:        GPL v2 only
Requires:       kiwi = %{version}
Requires:       inst-source-utils createrepo
Summary:        Installation Source creation
Group:          System/Management

%description -n kiwi-instsource
This package contains modules used for installation source creation.
With those it is possible to create a valid installation repository
from blank RPM file trees. The created tree can be used directly for
the image creation process afterwards. This package allows using the
--create-instsource <path-to-config.xml> switch.

Authors:
--------
	Adrian Schroeter <adrian@novell.com>
	Jan Bornschlegel <jcborn@novell.com>

%package -n kiwi-doc
License:        LGPL v2.0 or later
Summary:        OpenSuSE - KIWI Image System Documentation
Group:          Documentation/Howto

%description -n kiwi-doc
This package contains the documentation and manual pages for the KIWI
Image System

Authors:
--------
    Thomas Schraitle
    Marcus Schaefer

%package -n kiwi-tools
License:        GPL v2 or later
Summary:        OpenSuSE - KIWI tools collection
Group:          System/Management

%description -n kiwi-tools
This package contains the OpenSuSE - KIWI tools set usable in and
outside of operating system images

Authors:
--------
    Marcus Schaefer <ms@novell.com>

%ifarch %ix86 x86_64
%package -n kiwi-pxeboot
License:        GPL v2 or later
Requires:       syslinux
Summary:        OpenSuSE - KIWI Image System PXE boot structure
Group:          System/Management

%description -n kiwi-pxeboot
PXE basic directory structure and pre-build boot images

Authors:
--------
    Marcus Schaefer <ms@novell.com>
%endif

%ifarch %ix86 x86_64
%package -n kiwi-pxeboot-prebuild
License:        GPL v2 only
Requires:       syslinux
Summary:        OpenSuSE - KIWI TFTP prebuild boot images
Group:          System/Management

%description -n kiwi-pxeboot-prebuild
This package contains the OpenSuSE - KIWI TFTP prebuild boot images

Authors:
--------
    Marcus Schaefer <ms@novell.com>
%endif

%ifarch %ix86 x86_64
%package -n kiwi-desc-isoboot
License:        GPL v2 or later
Requires:       kiwi = %{version}
Requires:       syslinux
%if %{suse_version} > 1010
Requires: genisoimage
%else
Requires: mkisofs
%endif
Summary:        OpenSuSE - KIWI Image System ISO boot
Group:          System/Management

%description -n kiwi-desc-isoboot
kiwi boot (initrd) image for activating system images on ISO media

Authors:
--------
    Marcus Schaefer <ms@novell.com>
%endif

%ifarch %ix86 x86_64
%package -n kiwi-desc-usbboot
License:        GPL v2 or later
Requires:       kiwi = %{version}
Summary:        OpenSuSE - KIWI Image System USB boot
Group:          System/Management

%description -n kiwi-desc-usbboot
kiwi boot (initrd) image for activating system images on USB stick

Authors:
--------
    Marcus Schaefer <ms@novell.com>
%endif

%ifarch %ix86 x86_64
%package -n kiwi-desc-vmxboot
License:        GPL v2 or later
Requires:       kiwi = %{version}
Requires:       qemu multipath-tools
Summary:        OpenSuSE - KIWI Image System Virtual Machine boot
Group:          System/Management

%description -n kiwi-desc-vmxboot
kiwi boot (initrd) image for activating system images on virtual disk

Authors:
--------
    Marcus Schaefer <ms@novell.com>
%endif

%ifarch %ix86 x86_64 ppc ppc64
%package -n kiwi-desc-netboot
License:        GPL v2 or later
Requires:       kiwi = %{version}
Summary:        OpenSuSE - KIWI Image System PXE network boot
Group:          System/Management

%description -n kiwi-desc-netboot
kiwi boot (initrd) image for activating system images via TFTP

Authors:
--------
    Marcus Schaefer <ms@novell.com>
%endif

%ifarch %ix86 x86_64
%package -n kiwi-desc-xenboot
License:        GPL v2 or later
Requires:       kiwi = %{version}
Summary:        OpenSuSE - KIWI Image System Xen Virtual Machine boot
Group:          System/Management

%description -n kiwi-desc-xenboot
kiwi boot (initrd) image for activating a Xen image by xm

Authors:
--------
    Marcus Schaefer <ms@novell.com>
%endif

%ifarch %ix86 x86_64
%package -n kiwi-desc-oemboot
License:        GPL v2 only
Requires:       kiwi = %{version}
Requires:       qemu multipath-tools
%if %{suse_version} > 1010
Requires: genisoimage
%else
Requires: mkisofs
%endif
Summary:        OpenSuSE - KIWI image descriptions
Group:          System/Management

%description -n kiwi-desc-oemboot
This package contains the OpenSuSE - KIWI image descriptions. Each
image description exists in a single directory and contains an oemboot
image description

Authors:
--------
    Marcus Schaefer <ms@novell.com>
%endif

%ifarch %ix86 x86_64
%package -n kiwi-templates
License:        GPL v2.0 or later
Requires:       kiwi-desc-vmxboot = %{version}
Summary:        OpenSuSE - KIWI JeOS system image templates
Group:          System/Management

%description -n kiwi-templates
This package contains system image templates to easily build
a JeOS based operating system image with kiwi 

Authors:
--------
    Marcus Schaefer
%endif

%prep
%setup -n kiwi

%build
# empty because of rpmlint warning rpm-buildroot-usage

%install
# build
export K_USER=-1 # set to -1 to prevent building boot images, set to 0 to enable
export K_ARCH=`uname -m | grep -q ^i && echo ix86 || uname -m`
test -e /.buildenv || export K_USER=-1 # no buildenv, no boot image build
test -e /.buildenv && . /.buildenv
make buildroot=$RPM_BUILD_ROOT CFLAGS="$RPM_OPT_FLAGS"
%ifarch %ix86 x86_64
if [ "$UID" = "$K_USER" ];then
	# prepare and create prebuilt PXE boot images...
	(cd tools/dbuslock && make install)
	mkdir -p $RPM_BUILD_ROOT/srv/tftpboot/pxelinux.cfg
	mkdir -p $RPM_BUILD_ROOT/srv/tftpboot/boot
	mkdir -p /usr/share/kiwi/modules
	mkdir -p /usr/share/kiwi/repo
	mkdir -p /usr/share/kiwi/image/netboot
	rm -f /usr/share/kiwi/modules/*
	for i in `find modules/ -type f`;do cp $i /usr/share/kiwi/modules;done
	cp -a system/suse-repo /usr/share/kiwi/repo
	cd modules
	pxedefault=$RPM_BUILD_ROOT/srv/tftpboot/pxelinux.cfg/default
	echo "# /.../" > $pxedefault
	echo "# KIWI boot image setup" >> $pxedefault
	echo "# select boot label according to your system image" >> $pxedefault
	echo "# ..."  >> $pxedefault
	echo "DEFAULT Local-Boot" >> $pxedefault
	images="
		netboot/suse-SLES10
	"
	for i in $images;do
		rootName=`echo $i | tr / -`
		rootName=`echo $rootName \(latest service pack\)`
		echo "#DEFAULT $rootName" >> $pxedefault
	done
	echo >> $pxedefault
	echo "LABEL Local-Boot"  >> $pxedefault
	echo "      localboot 0" >> $pxedefault
	for i in $images;do
		rootName=`echo $i | tr / -`
		../kiwi.pl --root $RPM_BUILD_ROOT/root-$rootName --prepare ../system/boot/$K_ARCH/$i --logfile terminal
		../kiwi.pl --create $RPM_BUILD_ROOT/root-$rootName \
			-d $RPM_BUILD_ROOT/srv/tftpboot/boot --logfile terminal
		rm -rf $RPM_BUILD_ROOT/root-$rootName*
		echo >> $pxedefault
		echo "LABEL $rootName" >> $pxedefault
		(
			pushd $RPM_BUILD_ROOT/srv/tftpboot/boot
			xenkernel=""
			xenloader=""
			initrd=""
			kernel=""
			for n in *$rootName*;do
				echo $n | grep -q xen$      && xenkernel=$n || true
				echo $n | grep -q xen.gz$   && xenloader=$n || true
				echo $n | grep -q [0-9].gz$ && initrd=$n    || true
				echo $n | grep -q kernel    && kernel=$n    || true
			done
			popd
			../kiwi.pl --setup-splash \
				$RPM_BUILD_ROOT/srv/tftpboot/boot/$initrd   && \
			rm -f $RPM_BUILD_ROOT/srv/tftpboot/boot/$initrd && \
			initrd=`echo $initrd | sed -e "s@.gz@.splash.gz@"`
			pushd $RPM_BUILD_ROOT/srv/tftpboot/boot
			cd $RPM_BUILD_ROOT/srv/tftpboot/boot
			if [ -n "$xenkernel" ];then
				echo "      kernel mboot.c32" >> $pxedefault
				echo "      append boot/$xenloader --- boot/$xenkernel vga=0x314 ramdisk_size=512000 ramdisk_blocksize=4096 splash=silent showopts --- boot/$initrd" >> $pxedefault
				echo "      IPAPPEND 2" >> $pxedefault
			else
				echo "      kernel boot/$kernel" >> $pxedefault
				echo "      append initrd=boot/$initrd vga=0x314 ramdisk_size=512000 ramdisk_blocksize=4096 splash=silent showopts" >> $pxedefault
				echo "      IPAPPEND 2" >> $pxedefault
			fi
			popd
		)
	done
	rm -f $RPM_BUILD_ROOT/srv/tftpboot/boot/*.md5
	rm -f $RPM_BUILD_ROOT/srv/tftpboot/boot/*.kernel
	chmod 644 $pxedefault
else
	echo "cannot build prebuild images without root privileges"
	true
fi
%endif
#install
cd $RPM_BUILD_DIR/kiwi
#mkdir -p $RPM_BUILD_ROOT/etc/permissions.d
#echo "/srv/tftpboot/upload/ root:root 0755" \
#	> $RPM_BUILD_ROOT/etc/permissions.d/kiwi
make buildroot=$RPM_BUILD_ROOT \
     doc_prefix=$RPM_BUILD_ROOT/%{_defaultdocdir} \
     man_prefix=$RPM_BUILD_ROOT/%{_mandir} \
     install
touch kiwi.loader
%ifarch %ix86 x86_64
if [ ! "$UID" = "$K_USER" ];then
	install -m 644 pxeboot/pxelinux.0.config \
		$RPM_BUILD_ROOT/srv/tftpboot/pxelinux.cfg/default
fi
%else
	# no PXE boot setup for non x86 archs
	rm -rf $RPM_BUILD_ROOT/srv/tftpboot
	rm -rf $RPM_BUILD_ROOT/etc/permissions.d/kiwi
%endif

test -f $RPM_BUILD_ROOT/srv/tftpboot/pxelinux.0 && \
	echo /srv/tftpboot/pxelinux.0 > kiwi.loader
test -f $RPM_BUILD_ROOT/srv/tftpboot/mboot.c32 && \
	echo /srv/tftpboot/mboot.c32 >> kiwi.loader
%perl_process_packlist
rm -f $RPM_BUILD_ROOT/%{perl_vendorarch}/KIWI/example.pl
./.links
%if %{suse_version} > 1020
%fdupes $RPM_BUILD_ROOT/srv/tftpboot
%fdupes $RPM_BUILD_ROOT/usr/share/kiwi/image
%fdupes $RPM_BUILD_ROOT/usr/share/doc/packages/kiwi/examples
%fdupes $RPM_BUILD_ROOT/usr/share/doc/packages/kiwi/schema
%endif
cat kiwi.loader

%clean
rm -rf $RPM_BUILD_ROOT
#=================================================
# KIWI files...      
#-------------------------------------------------

%files
%defattr(-, root, root)
%dir %{_datadir}/kiwi
%dir %{_datadir}/kiwi/image
%exclude %{_datadir}/kiwi/image/suse-11.2-JeOS
%exclude %{_datadir}/kiwi/image/suse-11.1-JeOS
%exclude %{_datadir}/kiwi/image/suse-SLE10-JeOS
%exclude %{_datadir}/kiwi/image/suse-SLE11-JeOS
%{_datadir}/kiwi/.revision
%{_datadir}/kiwi/modules
%{_datadir}/kiwi/locale
%{_datadir}/kiwi/repo
%exclude %{_datadir}/kiwi/modules/KIWIIsoLinux-AppleFileMapping.txt
%exclude %{_datadir}/kiwi/modules/KIWICollect.pm
%exclude %{_datadir}/kiwi/modules/KIWIRepoMetaHandler.pm
%exclude %{_datadir}/kiwi/modules/KIWIUtil.pm
%{_datadir}/kiwi/tests
%{_datadir}/kiwi/xsl
%{_sbindir}/kiwi
%{perl_vendorarch}/KIWI
%{perl_vendorarch}/auto/KIWI
/var/adm/perl-modules/kiwi
#=================================================
# KIWI doc...      
#-------------------------------------------------

%files -n kiwi-doc
%defattr(-, root, root)
%dir %{_defaultdocdir}/kiwi
%doc %{_mandir}/man1/kiwi.1.gz
%doc %{_mandir}/man1/KIWI::images.sh.1.gz
%doc %{_mandir}/man1/KIWI::config.sh.1.gz
%doc %{_mandir}/man1/KIWI::kiwirc.1.gz
%doc %{_defaultdocdir}/kiwi/COPYING
%doc %{_defaultdocdir}/kiwi/examples
%doc %{_defaultdocdir}/kiwi/kiwi.pdf
%doc %{_defaultdocdir}/kiwi/ChangeLog
%doc %{_defaultdocdir}/kiwi/schema
#=================================================
# KIWI instsource...      
#-------------------------------------------------

%files -n kiwi-instsource
%defattr(-, root, root)
%{_datadir}/kiwi/modules/KIWIIsoLinux-AppleFileMapping.txt
%{_datadir}/kiwi/modules/KIWICollect.pm
%{_datadir}/kiwi/modules/KIWIUtil.pm
%{_datadir}/kiwi/modules/KIWIRepoMetaHandler.pm

#=================================================
# KIWI-pxeboot files...  
# ------------------------------------------------
%ifarch %ix86 x86_64
%files -n kiwi-pxeboot -f kiwi.loader
%defattr(-, root, root)
%doc /srv/tftpboot/README
#%config /etc/permissions.d/kiwi
%dir /srv/tftpboot
%dir /srv/tftpboot/KIWI
%dir /srv/tftpboot/pxelinux.cfg
%dir /srv/tftpboot/image
%dir /srv/tftpboot/upload
%dir /srv/tftpboot/boot
/srv/tftpboot/pxelinux.cfg/default
%endif
#=================================================
# KIWI-pxeboot-prebuild files...  
# ------------------------------------------------
%ifarch %ix86 x86_64
%files -n kiwi-pxeboot-prebuild
%defattr(-, root, root)
%doc /srv/tftpboot/README.prebuild
/srv/tftpboot/boot
%endif
#=================================================
# KIWI-tools files...  
# ------------------------------------------------
%files -n kiwi-tools
%defattr(-, root, root)
%doc %{_defaultdocdir}/kiwi/README.tools
/usr/bin/*
#=================================================
# KIWI-desc-* and templates...
# ------------------------------------------------
%ifarch %ix86 x86_64
%files -n kiwi-desc-isoboot
%defattr(-, root, root)
%dir %{_datadir}/kiwi/image/isoboot
%doc %{_datadir}/kiwi/image/isoboot/README
%{_datadir}/kiwi/image/isoboot/suse*
%endif

%ifarch %ix86 x86_64
%files -n kiwi-desc-vmxboot
%defattr(-, root, root)
%dir %{_datadir}/kiwi/image/vmxboot
%doc %{_datadir}/kiwi/image/vmxboot/README
%{_datadir}/kiwi/image/vmxboot/suse*
%endif

%ifarch %ix86 x86_64
%files -n kiwi-desc-usbboot
%defattr(-, root, root)
%dir %{_datadir}/kiwi/image/usbboot
%doc %{_datadir}/kiwi/image/usbboot/README
%{_datadir}/kiwi/image/usbboot/suse*
%endif

%ifarch %ix86 x86_64 ppc ppc64
%files -n kiwi-desc-netboot
%defattr(-, root, root)
%dir %{_datadir}/kiwi/image/netboot
%doc %{_datadir}/kiwi/image/netboot/README
%{_datadir}/kiwi/image/netboot/suse*
%endif

%ifarch %ix86 x86_64
%files -n kiwi-desc-xenboot
%defattr(-, root, root)
%dir %{_datadir}/kiwi/image/xenboot
%doc %{_datadir}/kiwi/image/xenboot/README
%{_datadir}/kiwi/image/xenboot/suse*
%endif

%ifarch %ix86 x86_64
%files -n kiwi-desc-oemboot
%defattr(-, root, root)
%dir %{_datadir}/kiwi/image/oemboot
%doc %{_datadir}/kiwi/image/oemboot/README
%{_datadir}/kiwi/image/oemboot/suse*
%endif

%ifarch %ix86 x86_64
%files -n kiwi-templates
%defattr(-, root, root)
%{_datadir}/kiwi/image/suse-11.2-JeOS
%{_datadir}/kiwi/image/suse-11.1-JeOS
%{_datadir}/kiwi/image/suse-SLE10-JeOS
%{_datadir}/kiwi/image/suse-SLE11-JeOS
%endif
