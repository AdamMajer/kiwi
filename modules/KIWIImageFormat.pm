#================
# FILE          : KIWIImageFormat.pm
#----------------
# PROJECT       : OpenSUSE Build-Service
# COPYRIGHT     : (c) 2006 SUSE LINUX Products GmbH, Germany
#               :
# AUTHOR        : Marcus Schaefer <ms@suse.de>
#               :
# BELONGS TO    : Operating System images
#               :
# DESCRIPTION   : This module is used to provide methods for
#               : creating image output formats based on the
#               : raw output file like vmdk, ovf, hyperV
#               : and more
#               : 
#               :
# STATUS        : Development
#----------------
package KIWIImageFormat;
#==========================================
# Modules
#------------------------------------------
use strict;
use KIWILog;
use KIWIQX;
use File::Basename;
use KIWIBoot;

#==========================================
# Constructor
#------------------------------------------
sub new {
	# ...
	# Create a new KIWIImageFormat object which is used
	# to gather information required for the format conversion 
	# ---
	#==========================================
	# Object setup
	#------------------------------------------
	my $this  = {};
	my $class = shift;
	bless $this,$class;
	#==========================================
	# Module Parameters [ mandatory ]
	#------------------------------------------
	my $kiwi   = shift;
	my $image  = shift;
	#==========================================
	# Module Parameters [ optional ]
	#------------------------------------------
	my $format = shift;
	my $xml    = shift;
	#==========================================
	# Constructor setup
	#------------------------------------------
	my $code;
	my $data;
	if (! defined $kiwi) {
		$kiwi = new KIWILog();
	}
	#==========================================
	# check image file
	#------------------------------------------
	if (! (-f $image || -b $image)) {
		$kiwi -> error ("no such image file: $image");
		$kiwi -> failed ();
		return undef;
	} 
	#==========================================
	# read XML if required
	#------------------------------------------
	if (! defined $xml) {
		my $boot = new KIWIBoot (
			$kiwi,undef,$image,undef,undef,undef,\@main::ProfilesOrig
		);
		if ($boot) {
			$xml = $boot->{xml};
			$boot -> cleanLoop();
			$boot -> cleanTmp();
		}
		if (! defined $xml) {
			$kiwi -> error  ("Can't load XML configuration, not an image ?");
			$kiwi -> failed ();
			return undef;
		}
	}
	#==========================================
	# check format
	#------------------------------------------
	my $type = $xml -> getImageTypeAndAttributes();
	if (! defined $format) {
		if (($type) && ($type->{format})) {
			$format = $type->{format};
		}
	}
	#==========================================
	# Read some XML data
	#------------------------------------------
	my %xenref = $xml -> getXenConfig();
	my %vmwref = $xml -> getVMwareConfig();
	#==========================================
	# Store object data
	#------------------------------------------
	$this->{xenref}  = \%xenref;
	$this->{vmwref}  = \%vmwref;
	$this->{kiwi}    = $kiwi;
	$this->{xml}     = $xml;
	$this->{format}  = $format;
	$this->{image}   = $image;
	$this->{type}    = $type;
	$this->{imgtype} = $type->{type};
	return $this;
}

#==========================================
# createFormat
#------------------------------------------
sub createFormat {
	my $this   = shift;
	my $kiwi   = $this->{kiwi};
	my $format = $this->{format};
	my $image  = $this->{image};
	my $imgtype= $this->{imgtype};
	#==========================================
	# check if format is a disk
	#------------------------------------------
	if (! defined $format) {
		$kiwi -> warning ("No format for $imgtype conversion specified");
		$kiwi -> skipped ();
		return undef;
	} else {
		my $data = qxx ("parted $image print 2>&1");
		my $code = $? >> 8;
		if ($code != 0) {
			$kiwi -> error  ("system image is not a disk");
			$kiwi -> failed ();
			return undef
		}
	}
	#==========================================
	# convert disk into specified format
	#------------------------------------------
	if ($format eq "vmdk") {
		$kiwi -> info ("Starting $imgtype => $format conversion\n");
		return $this -> createVMDK();
	} elsif ($format eq "ovf") {
		$kiwi -> info ("Starting $imgtype => $format conversion\n");
		return $this -> createOVF();
	} elsif ($format eq "qcow2") {
		$kiwi -> info ("Starting $imgtype => $format conversion\n");
		return $this -> createQCOW2();
	} else {
		$kiwi -> warning (
			"Can't convert image type $imgtype to $format format"
		);
		$kiwi -> skipped ();
	}
	return undef;
}

#==========================================
# createMaschineConfiguration
#------------------------------------------
sub createMaschineConfiguration {
	my $this   = shift;
	my $kiwi   = $this->{kiwi};
	my $format = $this->{format};
	my $imgtype= $this->{imgtype};
	my $xml    = $this->{xml};
	my %type   = %{$this->{type}};
	my $xenref = $this->{xenref};
	my %xenc   = %{$xenref};
	my $xend   = "dom0";
	if (defined $xenc{xen_domain}) {
		$xend = $xenc{xen_domain};
	}
	if (($type{type}) && ($type{type} eq "xen")) {
		$kiwi -> info ("Starting $imgtype image machine configuration\n");
		return $this -> createXENConfiguration();
	} elsif (
		($type{bootprofile}) && ($type{bootprofile} eq "xen") &&
		($xend eq "domU")
	) {
		$kiwi -> info ("Starting $imgtype image machine configuration\n");
		return $this -> createXENConfiguration();
	} elsif ($format eq "vmdk") {
		$kiwi -> info ("Starting $imgtype image machine configuration\n");
		return $this -> createVMwareConfiguration();
	} elsif ($format eq "ovf") {
		$kiwi -> info ("Starting $imgtype image machine configuration\n");
		return $this -> createOVFConfiguration();
	} else {
		$kiwi -> warning (
			"Can't create machine configuration for $imgtype image"
		);
		$kiwi -> skipped ();
	}
	return undef;
}

#==========================================
# createOVF
#------------------------------------------
sub createOVF {
	my $this   = shift;
	my $kiwi   = $this->{kiwi};
	my $format = $this->{format};
	my $ovftool = "/usr/bin/ovftool";
	my $vmdk;
	my $vmxf;
	my $source;
	my $target;
	#==========================================
	# check for ovftool
	#------------------------------------------
	if (! -x $ovftool) {
		$kiwi -> error  ("Can't find $ovftool, is it installed ?");
		$kiwi -> failed ();
		return undef;
	}
	#==========================================
	# create vmdk first, required for ovf
	#------------------------------------------
	$this->{format}	= "vmdk";
	$vmdk = $this->createVMDK();
	$vmxf = $this->createMaschineConfiguration();
	#==========================================
	# create ovf from the vmdk
	#------------------------------------------
	if ((-e $vmdk) && (-e $vmxf)) {
		$source = $vmxf;
		$target = $vmxf;
		$target =~ s/\.vmx$/\.$format/;
		$this->{format} = $format;
		$kiwi -> info ("Creating $format image...");
		# /.../
		# temporary hack, because ovftool is not able to handle
		# scsi-hardDisk correctly at the moment
		# ---- beg ----
		qxx ("sed -i -e 's;scsi-hardDisk;disk;' $source");
		# ---- end ----
		my $status = qxx ("rm -rf $target; mkdir -p $target 2>&1");
		my $result = $? >> 8;
		if ($result != 0) {
			$kiwi -> failed ();
			$kiwi -> error  ("Couldn't create OVF directory: $status");
			$kiwi -> failed ();
			return undef;
		}
		my $output = basename $target;
		$status= qxx (
			"$ovftool -o -q $source $target/$output 2>&1"
		);
		$result = $? >> 8;
		# --- beg ----
		qxx ("sed -i -e 's;disk;scsi-hardDisk;' $source");
		qxx ("rm -rf $main::Destination/*.lck 2>&1");
		# --- end ----
		if ($result != 0) {
			$kiwi -> failed ();
			$kiwi -> error  ("Couldn't create OVF image: $status");
			$kiwi -> failed ();
			return undef;
		}
		$kiwi -> done();
	} else {
		$kiwi -> error  ("Required vmdk files not present");
		$kiwi -> failed ();
		return undef;
	}
	return $target;
}

#==========================================
# createVMDK
#------------------------------------------
sub createVMDK {
	my $this   = shift;
	my $kiwi   = $this->{kiwi};
	my $format = $this->{format};
	my %vmwc   = %{$this->{vmwref}};
	my $source = $this->{image};
	my $target = $source;
	my $convert;
	my $status;
	my $result;
	$kiwi -> info ("Creating $format image...");
	$target  =~ s/\.raw$/\.$format/;
	$convert = "convert -f raw $source -O $format";
	if (($vmwc{vmware_disktype}) && ($vmwc{vmware_disktype}=~/^scsi/)) {
		$status = qxx ("qemu-img $convert -s $target 2>&1");
	} else {
		$status = qxx ("qemu-img $convert $target 2>&1");
	}
	$result = $? >> 8;
	if ($result != 0) {
		$kiwi -> failed ();
		$kiwi -> error  ("Couldn't create $format image: $status");
		$kiwi -> failed ();
		return undef;
	}
	$kiwi -> done ();
	return $target;
}

#==========================================
# createQCOW2
#------------------------------------------
sub createQCOW2 {
	my $this = shift;
	my $kiwi   = $this->{kiwi};
	my $format = $this->{format};
	my $source = $this->{image};
	my $target = $source;
	my $status;
	my $result;
	$kiwi -> info ("Creating $format image...");
	$target  =~ s/\.raw$/\.$format/;
	$status = qxx ("qemu-img -f raw $source -O $format $target 2>&1");
	$result = $? >> 8;
	if ($result != 0) {
		$kiwi -> failed ();
		$kiwi -> error  ("Couldn't create $format image: $status");
		$kiwi -> failed ();
		return undef;
	}
	$kiwi -> done ();
	return $target;
}

#==========================================
# createXENConfiguration
#------------------------------------------
sub createXENConfiguration {
	my $this   = shift;
	my $kiwi   = $this->{kiwi};
	my $xml    = $this->{xml};
	my $xenref = $this->{xenref};
	my %type   = %{$this->{type}};
	my $dest   = dirname  $this->{image};
	my $base   = basename $this->{image};
	my %xenconfig = %{$xenref};
	my $format;
	my $file;
	my $FD;
	$kiwi -> info ("Creating image Xen configuration file...");
	#==========================================
	# setup config file name from image name
	#------------------------------------------
	my $image = $base;
	if ($base =~ /(.*)\.(.*?)$/) {
		$image  = $1;
		$format = $2;
		$base   = $image.".xenconfig";
	}
	$file = $dest."/".$base;
	unlink $file;
	#==========================================
	# find kernel
	#------------------------------------------
	my $kernel;
	my $initrd;
	foreach my $k (glob ($dest."/*.kernel")) {
		if (-l $k) {
			$kernel = readlink ($k);
			$kernel = basename ($kernel);
			last;
		}
	}
	if (! -e "$dest/$kernel") {
		$kiwi -> skipped ();
		$kiwi -> warning ("Can't find kernel in $dest");
		$kiwi -> skipped ();
		return $file;
	}
	#==========================================
	# find initrd
	#------------------------------------------
	foreach my $i (glob ($dest."/*.splash.gz")) {
		$initrd = $i;
		$initrd = basename ($initrd);
		last;
	}
	if (! -e "$dest/$initrd") {
		$kiwi -> skipped ();
		$kiwi -> warning ("Can't find initrd in $dest");
		$kiwi -> skipped ();
		return $file;
	}
	#==========================================
	# check XML configuration data
	#------------------------------------------
	if ((! %xenconfig) || (! $xenconfig{xen_diskdevice})) {
		$kiwi -> skipped ();
		$kiwi -> warning ("Not enough or missing Xen machine config data");
		$kiwi -> skipped ();
		return $file;
	}
	#==========================================
	# Create config file
	#------------------------------------------
	if (! open ($FD,">$file")) {
		$kiwi -> skipped ();
		$kiwi -> warning  ("Couldn't create xenconfig file: $!");
		$kiwi -> skipped ();
		return $file;
	}
	#==========================================
	# global setup
	#------------------------------------------
	my $device = $xenconfig{xen_diskdevice};
	$device =~ s/\/dev\///;
	my $part = $device."1";
	if ($type{type} eq "xen") {
		$device = $device."1";
	}
	my $memory = $xenconfig{xen_memory};
	if ($type{type} ne "xen") {
		$image .= ".".$format;
	}
	print $FD '#  -*- mode: python; -*-'."\n";
	print $FD "name=\"".$this->{xml}->getImageDisplayName()."\"\n";
	if ($type{type} eq "xen") {
		print $FD 'kernel="'.$kernel.'"'."\n";
		print $FD 'ramdisk="'.$initrd.'"'."\n";
	}
	print $FD 'memory='.$memory."\n";
	if ($type{type} ne "xen") {
		my $tap = $format;
		if ($tap eq "raw") {
			$tap = "aio";
		}
		print $FD 'disk=[ "tap:'.$tap.':'.$image.','.$device.',w" ]'."\n";
	} else {
		print $FD 'disk=[ "file:'.$image.','.$part.',w" ]'."\n";
	}
	#==========================================
	# network setup
	#------------------------------------------
	my $vifcount = -1;
	foreach my $bname (keys %{$xenconfig{xen_bridge}}) {
		$vifcount++;
		my $mac = $xenconfig{xen_bridge}{$bname};
		my $vif = '"bridge='.$bname.'"';
		if ($bname eq "undef") {
			$vif = '""';
		}
		if ($mac) {
			$vif = '"mac='.$mac.',bridge='.$bname.'"';
			if ($bname eq "undef") {
				$vif = '"mac='.$mac.'"';
			}
		}
		if ($vifcount == 0) {
			print $FD "vif=[ ".$vif;
		} else {
			print $FD ", ".$vif;
		}
	}
	if ($vifcount >= 0) {
		print $FD " ]"."\n";
	}
	#==========================================
	# xen console
	#------------------------------------------
	if ($type{type} eq "xen") {
		print $FD 'root="'.$part.' ro"'."\n";
	}
	#==========================================
	# xen virtual framebuffer
	#------------------------------------------
	print $FD 'vfb = ["type=vnc,vncunused=1,vnclisten=0.0.0.0"]'."\n";
	close $FD;
	$kiwi -> done();
	return $file;
}

#==========================================
# createVMwareConfiguration
#------------------------------------------
sub createVMwareConfiguration {
	my $this   = shift;
	my $kiwi   = $this->{kiwi};
	my $xml    = $this->{xml};
	my $vmwref = $this->{vmwref};
	my $dest   = dirname  $this->{image};
	my $base   = basename $this->{image};
	my $file;
	my $FD;
	$kiwi -> info ("Creating image VMware configuration file...");
	#==========================================
	# setup config file name from image name
	#------------------------------------------
	my $image = $base;
	if ($base =~ /(.*)\.(.*?)$/) {
		$image = $1;
		$base  = $image.".vmx";
	}
	$file = $dest."/".$base;
	unlink $file;
	#==========================================
	# check XML configuration data
	#------------------------------------------
	my %vmwconfig = %{$vmwref};
	if ((! %vmwconfig) || (! $vmwconfig{vmware_disktype})) {
		$kiwi -> skipped ();
		$kiwi -> warning ("Not enough or Missing VMware machine config data");
		$kiwi -> skipped ();
		return $file;
	}
	#==========================================
	# Create config file
	#------------------------------------------
	if (! open ($FD,">$file")) {
		$kiwi -> skipped ();
		$kiwi -> warning ("Couldn't create VMware config file: $!");
		$kiwi -> skipped ();
		return $file;
	}
	#==========================================
	# global setup
	#------------------------------------------
	print $FD '#!/usr/bin/env vmware'."\n";
	print $FD 'config.version = "8"'."\n";
	print $FD 'tools.syncTime = "true"'."\n";
	print $FD 'uuid.action = "create"'."\n";
	if ($vmwconfig{vmware_hwver}) {
		print $FD 'virtualHW.version = "'.$vmwconfig{vmware_hwver}.'"'."\n";
	} else {
		print $FD 'virtualHW.version = "4"'."\n";
	}
	print $FD 'displayName = "'.$image.'"'."\n";
	print $FD 'memsize = "'.$vmwconfig{vmware_memory}.'"'."\n";
	print $FD 'guestOS = "'.$vmwconfig{vmware_guest}.'"'."\n";
	#==========================================
	# storage setup
	#------------------------------------------
	if (defined $vmwconfig{vmware_disktype}) {
		my $type   = $vmwconfig{vmware_disktype};
		my $device = $vmwconfig{vmware_disktype}.$vmwconfig{vmware_diskid};
		if ($type eq "ide") {
			# IDE Interface...
			print $FD $device.':0.present = "true"'."\n";
			print $FD $device.':0.fileName= "'.$image.'.vmdk"'."\n";
			print $FD $device.':0.redo = ""'."\n";
		} else {
			# SCSI Interface...
			print $FD $device.'.present = "true"'."\n";
			print $FD $device.'.sharedBus = "none"'."\n";
			print $FD $device.'.virtualDev = "lsilogic"'."\n";
			print $FD $device.':0.present = "true"'."\n";
			print $FD $device.':0.fileName = "'.$image.'.vmdk"'."\n";
			print $FD $device.':0.deviceType = "scsi-hardDisk"'."\n";
		}
	}
	#==========================================
	# network setup
	#------------------------------------------
	if (defined $vmwconfig{vmware_niciface}) {
		my $driver = $vmwconfig{vmware_nicdriver};
		my $mode   = $vmwconfig{vmware_nicmode};
		my $nic    = "ethernet".$vmwconfig{vmware_niciface};
		print $FD $nic.'.present = "true"'."\n";
		print $FD $nic.'.addressType = "generated"'."\n";
		if ($driver) {
			print $FD $nic.'.virtualDev = "'.$driver.'"'."\n";
		}
		if ($mode) {
			print $FD $nic.'.connectionType = "'.$mode.'"'."\n";
		}
		if ($vmwconfig{vmware_arch} =~ /64$/) {
			print $FD $nic.'.allow64bitVmxnet = "true"'."\n";
		}
	}
	#==========================================
	# CD/DVD drive setup
	#------------------------------------------
	if (defined $vmwconfig{vmware_cdtype}) {
		my $device = $vmwconfig{vmware_cdtype}.$vmwconfig{vmware_cdid};
		print $FD $device.':0.present = "true"'."\n";
		print $FD $device.':0.deviceType = "cdrom-raw"'."\n";
		print $FD $device.':0.autodetect = "true"'."\n";
		print $FD $device.':0.startConnected = "true"'."\n";
	}
	#==========================================
	# USB setup
	#------------------------------------------
	print $FD 'usb.present = "true"'."\n";
	#==========================================
	# Power Management setup
	#------------------------------------------
	print $FD 'priority.grabbed = "normal"'."\n";
	print $FD 'priority.ungrabbed = "normal"'."\n";
	print $FD 'powerType.powerOff = "soft"'."\n";
	print $FD 'powerType.powerOn  = "soft"'."\n";
	print $FD 'powerType.suspend  = "soft"'."\n";
	print $FD 'powerType.reset    = "soft"'."\n";
	close $FD;
	chmod 0755,$file;
	$kiwi -> done();
	return $file;
}

#==========================================
# createOVFConfiguration
#------------------------------------------
sub createOVFConfiguration {
	# TODO
	my $this = shift;
	return $this;
}

1;

# vim: set noexpandtab:
