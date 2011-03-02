#================
# FILE          : KIWIManager.pm
#----------------
# PROJECT       : OpenSUSE Build-Service
# COPYRIGHT     : (c) 2006 SUSE LINUX Products GmbH, Germany
#               :
# AUTHOR        : Marcus Schaefer <ms@suse.de>
#               :
# BELONGS TO    : Operating System images
#               :
# DESCRIPTION   : This module is used to support multiple
#               : package manager like smart or zypper
#               :
# STATUS        : Development
#----------------
package KIWIManager;
#==========================================
# Modules
#------------------------------------------
require Exporter;
use strict;
use Carp qw (cluck);
use FileHandle;
use File::Basename;
use Config::IniFiles;
use KIWILog;
use KIWIQX;

#==========================================
# Exports
#------------------------------------------
our @ISA    = qw (Exporter);
our @EXPORT = qw (%packageManager);

#==========================================
# Exports
#------------------------------------------
our %packageManager;
$packageManager{smart}   = "/usr/bin/smart";
$packageManager{zypper}  = "/usr/bin/zypper";
$packageManager{ensconce}= "/usr/bin/ensconce";
$packageManager{yum}     = "/usr/bin/yum";
$packageManager{default} = "smart";

#==========================================
# Constructor
#------------------------------------------
sub new { 
	# ...
	# Create a new KIWIManager object, which is used
	# to import all data needed to abstract from different
	# package managers
	# ---
	#==========================================
	# Object setup
	#------------------------------------------
	my $this  = {};
	my $class = shift;
	bless $this,$class;
	#==========================================
	# Module Parameters
	#------------------------------------------
	my $kiwi       = shift;
	my $xml        = shift;
	my $sourceRef  = shift;
	my $root       = shift;
	my $manager    = shift;
	my $targetArch = shift;
	#==========================================
	# Constructor setup
	#------------------------------------------
	if (! defined $kiwi) {
		$kiwi = new KIWILog();
	}
	if (! defined $xml) {
		$kiwi -> error  ("Missing XML description pointer");
		$kiwi -> failed ();
		return undef;
	}
	if (! defined $sourceRef) {
		$kiwi -> error  ("Missing channel description pointer");
		$kiwi -> failed ();
		return undef;
	}
	my %source = %{$sourceRef};
	if (! defined $root) {
		$kiwi -> error  ("Missing chroot path");
		$kiwi -> failed ();
		return undef;
	}
	if (! defined $manager) {
		$manager = $packageManager{default};
	}
	my $dataDir = "/var/cache/kiwi/$manager";
	if (! -d $dataDir) {
		qxx ("mkdir -p $dataDir");
	}
	my $zyppConf = "/var/cache/kiwi/zypp.conf.$$";
	qxx ("rm -f /var/cache/kiwi/zypp.conf*");
	qxx ("echo '[main]' > $zyppConf");
	$ENV{ZYPP_CONF} = $zyppConf;	
	my $zconfig = new Config::IniFiles (
		-file => $zyppConf, -allowedcommentchars => '#'
	);
	if (defined $targetArch) {
		if ($manager eq "zypper") {
			$kiwi -> info ("Setting target architecture to: $targetArch");
			$zconfig->newval('main', 'arch', $targetArch);
			$zconfig->RewriteConfig;
			$kiwi -> done ();
		} else {
			$kiwi -> warning ("Target architecture not supported for $manager");
			$kiwi -> skipped ();
		}
	}
	my @channelList = ();
	#==========================================
	# Store object data
	#------------------------------------------
	$this->{kiwi}        = $kiwi;
	$this->{channelList} = \@channelList;
	$this->{xml}         = $xml;
	$this->{source}      = \%source;
	$this->{manager}     = $manager;
	$this->{root}        = $root;
	$this->{chroot}      = 0;
	$this->{lock}        = "/var/lock/kiwi-init.lock";
	$this->{screenCall}  = $root."/screenrc.smart";
	$this->{screenCtrl}  = $root."/screenrc.ctrls";
	$this->{screenLogs}  = $kiwi -> getRootLog();
	$this->{dataDir}     = $dataDir;
	$this->{zyppconf}    = $zyppConf;
	$this->{zconfig}     = $zconfig;
	$this->{smart}       = [
		$packageManager{smart},
		"--data-dir=$dataDir",
		"-o remove-packages=false"
	];
	$this->{smartroot}   = [
		"-o rpm-root=$root"
	];
	$this->{zypper}      = [
		$packageManager{zypper},
		"--non-interactive",
		"--no-gpg-checks",
		"--reposd-dir $dataDir",
		"--cache-dir $dataDir",
		"--raw-cache-dir $dataDir"
	];
	$this->{ensconce}    = [
		$packageManager{ensconce},
		"-r $root"
	];
	$this->{yum}         = [
		$packageManager{yum},
		"-c $dataDir/yum.conf",
		"-y"
	];
	$this->{kchroot}     = [
		"chroot \"$root\""
	];
	#==========================================
	# remove pre-defined smart channels
	#------------------------------------------
	if ($manager eq "smart") {
		if (glob ("$root//etc/smart/channels/*")) {
			qxx ( "rm -f $root/etc/smart/channels/*" );
		}
	}
	#==========================================
	# create yum config if required
	#------------------------------------------
	if ($manager eq "yum") {
		$this->{yumconfig} = $this->createYumConfig();
	}
	return $this;
}

#==========================================
# switchToChroot
#------------------------------------------
sub switchToChroot {
	my $this = shift;
	$this->{chroot} = 1;
}

#==========================================
# switchToLocal
#------------------------------------------
sub switchToLocal {
	my $this = shift;
	$this->{chroot} = 0;
}

#==========================================
# setupScreen
#------------------------------------------
sub setupScreen {
	my $this = shift;
	my $kiwi = $this->{kiwi};
	my $root = $this->{root};
	#==========================================
	# screen files
	#------------------------------------------
	my $screenCall = $this->{screenCall};
	my $screenCtrl = $this->{screenCtrl};
	my $screenLogs = $this->{screenLogs};

	#==========================================
	# Initiate screen call file
	#------------------------------------------
	my $fd = new FileHandle;
	my $cd = new FileHandle;
	if ((! $fd -> open (">$screenCall")) || (! $cd -> open (">$screenCtrl"))) {
		$kiwi -> failed ();
		$kiwi -> error  ("Couldn't create call file: $!");
		$kiwi -> failed ();
		$this -> resetInstallationSource();
		return undef;
	}
	print $cd "logfile $screenLogs\n";
	print $cd "logfile flush 1\n";
	$cd -> close();

	#==========================================
	# Global exports
	#------------------------------------------
	print $fd "export PBL_SKIP_BOOT_TEST=1"."\n";

	#==========================================
	# return screen call file handle
	#------------------------------------------
	return $fd;
}

#==========================================
# setupScreenCall
#------------------------------------------
sub setupScreenCall {
	my $this = shift;
	my $kiwi = $this->{kiwi};
	my $screenCall = $this->{screenCall};
	my $screenCtrl = $this->{screenCtrl};
	my $screenLogs = $this->{screenLogs};
	my $logs = 1;
	my $code;
	my $data;
	#==========================================
	# Check log location
	#------------------------------------------
	if ((defined $main::LogFile) && ($main::LogFile eq "terminal")) {
		$logs = 0;
	}
	#==========================================
	# activate shell set -x mode
	#------------------------------------------
	my $fd = new FileHandle;
	if ($fd -> open ($screenCall)) {
		local $/; $data = <$fd>; $fd -> close();
		if ($fd -> open (">$screenCall")) {
			print $fd "set -x\n";
			print $fd $data;
			$fd -> close();
		}
	}
	qxx (" chmod 755 $screenCall ");
	if ($logs) {
		$kiwi -> closeRootChannel();
	}
	#==========================================
	# run process in screen/terminal session
	#------------------------------------------
	$this->{child} = fork();
	if (! defined $this->{child}) {
		$kiwi -> failed ();
		$kiwi -> error  ("fork failed: $!");
		$kiwi -> failed ();
		return undef;
	}
	if ($this->{child}) {
		#==========================================
		# wait for the process to finish
		#------------------------------------------
		waitpid $this->{child},0;
		$code = $? >> 8;
		$data = "";
		undef $this->{child};
		#==========================================
		# create exit code and data value if screen
		#------------------------------------------
		if ($logs) {
			$kiwi -> reopenRootChannel();
			if ($fd -> open ($screenLogs)) {
				local $/; $data = <$fd>; $fd -> close();
			}   
			if ($code == 0) {
				if (! $fd -> open ("$screenCall.exit")) {
					$code = 1;
				} else {
					$code = <$fd>; chomp $code;
					$fd -> close();
				}
			}
		}
		#==========================================
		# remove call and control files
		#------------------------------------------
		qxx (" rm -f $screenCall* ");
		qxx (" rm -f $screenCtrl ");
	} else {
		#==========================================
		# do the job in the child process
		#------------------------------------------
		if ($logs) {
			if (! exec ("screen -L -D -m -c $screenCtrl $screenCall")) {
				die ("\n*** Couldn't exec screen: $! ***\n");
			}
		} else {
			if (! exec ( $screenCall )) {
				die ("\n*** Couldn't exec shell: $! ***\n");
			}
		}
	}
	#==========================================
	# check exit code from session
	#------------------------------------------
	if ($code != 0) {
		$kiwi -> failed ();
		if (($logs) && ($data)) {
			my @lines = split ("\n",$data);
			@lines = @lines[-10,-9,-8,-7,-6,-5,-4,-3,-2,-1];
			unshift (@lines,"[*** log excerpt follows, screen ***]");
			push    (@lines,"[*** end ***]\n");
			$data = join ("\n",@lines);
			printf STDERR $data;
			$kiwi -> doNorm();
		}
		$this -> resetInstallationSource();
		if ($kiwi -> trace()) {
			$main::BT.=eval { Carp::longmess ($main::TT.$main::TL++) };
		}
		return undef;
	}
	$kiwi -> done ();
	return $this;
}

#==========================================
# setupSignatureCheck
#------------------------------------------
sub setupSignatureCheck {
	# ...
	# Check if the image description contains the signature
	# check option or not. If yes activate or deactivate it
	# according to the used package manager
	# ---
	my $this = shift;
	my $kiwi = $this->{kiwi};
	my $xml  = $this->{xml};
	my @smart   = @{$this->{smart}};
	my $manager = $this->{manager};
	my $chroot  = $this->{chroot};
	my $root    = $this->{root};
	my @kchroot = @{$this->{kchroot}};
	my $yumc    = $this->{yumconfig};
	my $data;
	my $code;
	#==========================================
	# Get signature information
	#------------------------------------------
	my $imgCheckSig = $xml -> getRPMCheckSignatures();
	$this->{imgCheckSig} = $imgCheckSig;
	#==========================================
	# smart
	#------------------------------------------
	if ($manager eq "smart") {
		my $optionName  = "rpm-check-signatures";
		my $curCheckSig = qxx ("@smart config --show $optionName|tr -d '\\n'");
		$this->{curCheckSig} = $curCheckSig;
		if (defined $imgCheckSig) {
			my $option = "$optionName=$imgCheckSig";
			if (! $chroot) {
				$kiwi -> info ("Setting RPM signature check to: $imgCheckSig");
				$data = qxx ("@smart config --set $option 2>&1");
			} else {
				$kiwi -> info ("Setting RPM signature check to: $imgCheckSig");
				$data=qxx ("@kchroot @smart config --set $option 2>&1");
			}
			$code = $? >> 8;
			if ($code != 0) {
				$kiwi -> failed ();
				$kiwi -> error  ($data);
				return undef;
			}
			$kiwi -> done ();
		}
	}
	#==========================================
	# zypper
	#------------------------------------------
	if ($manager eq "zypper") {
		# nothing to do for zypper here...
	}
	#==========================================
	# ensconce
	#------------------------------------------
	if ($manager eq "ensconce") {
		# nothing to do here for ensconce...
	}
	#==========================================
	# yum
	#------------------------------------------
	if ($manager eq "yum") {
		$data = new Config::IniFiles (
			-file => $yumc, -allowedcommentchars => '#'
		);
		my $optval = 0;
		if ($imgCheckSig eq "true") {
			$optval = 1;
		}
		$data -> newval ("main", "gpgcheck", $optval);
		$data -> RewriteConfig();
	}
	return $this;
}

#==========================================
# resetSignatureCheck
#------------------------------------------
sub resetSignatureCheck {
	# ...
	# reset the signature check option to the previos
	# value of the package manager
	# ---
	my $this   = shift;
	my $kiwi   = $this->{kiwi};
	my $chroot = $this->{chroot};
	my $manager= $this->{manager};
	my $root   = $this->{root};
	my @smart  = @{$this->{smart}};
	my @kchroot= @{$this->{kchroot}};
	my $yumc   = $this->{yumconfig};
	my $curCheckSig = $this->{curCheckSig};
	my $data;
	my $code;
	#==========================================
	# smart
	#------------------------------------------
	if ($manager eq "smart") {
		if (defined $this->{imgCheckSig}) {
			my $optionName  = "rpm-check-signatures";
			my $option = "$optionName=$curCheckSig";
			if (! $chroot) {
				$kiwi -> info ("Reset RPM signature check to: $curCheckSig");
				$data = qxx ("@smart config --set $option 2>&1");
			} else {
				$kiwi -> info ("Reset RPM signature check to: $curCheckSig");
				$data=qxx ("@kchroot @smart config --set $option 2>&1");
			}
			$code = $? >> 8;
			if ($code != 0) {
				$kiwi -> failed ();
				$kiwi -> error  ($data);
				return undef;
			}
			$kiwi -> done ();
		}
	}
	#==========================================
	# zypper
	#------------------------------------------
	if ($manager eq "zypper") {
		# nothing to do for zypper here...
	}
	#==========================================
	# ensconce
	#------------------------------------------
	if ($manager eq "ensconce") {
		# nothing to do here for ensconce...
	}
	#==========================================
	# yum
	#------------------------------------------
	if ($manager eq "yum") {
		$data = new Config::IniFiles (
			-file => $yumc, -allowedcommentchars => '#'
		);
		$data -> newval ("main", "gpgcheck", "0");
		$data -> RewriteConfig();
	}
	return $this;
}

#==========================================
# setupExcludeDocs
#------------------------------------------
sub setupExcludeDocs {
	# ...
	# Check if the image description contains the exclude
	# docs option or not. If yes activate or deactivate it
	# according to the used package manager
	# ---
	my $this = shift;
	my $kiwi = $this->{kiwi};
	my $xml  = $this->{xml};
	my @smart   = @{$this->{smart}};
	my $manager = $this->{manager};
	my $chroot  = $this->{chroot};
	my @kchroot = @{$this->{kchroot}};
	my $root    = $this->{root};
	my $data;
	my $code;
	#==========================================
	# Get docs information
	#------------------------------------------
	my $imgExclDocs = $xml -> getRPMExcludeDocs();
	$this->{imgExclDocs} = $imgExclDocs;

	#==========================================
	# smart
	#------------------------------------------
	if ($manager eq "smart") {
		my $optionName  = "rpm-excludedocs";
		my $curExclDocs = qxx (
			"@smart config --show $optionName 2>/dev/null | tr -d '\\n'"
		);
		$this->{curExclDocs} = $curExclDocs;
		if (defined $imgExclDocs) {
			my $option = "$optionName=$imgExclDocs";
			if (! $chroot) {
				$kiwi -> info ("Setting RPM doc exclusion to: $imgExclDocs");
				$data = qxx ("@smart config --set $option 2>&1");
			} else {
				$kiwi -> info ("Setting RPM doc exclusion to: $imgExclDocs");
				$data=qxx ("@kchroot @smart config --set $option 2>&1");
			}
			$code = $? >> 8;
			if ($code != 0) {
				$kiwi -> failed ();
				$kiwi -> error  ($data);
				return undef;
			}
			$kiwi -> done ();
		}
	}
	#==========================================
	# zypper
	#------------------------------------------
	if ($manager eq "zypper") {
		my $zconfig = $this->{zconfig};
		my $optionParam = 'rpm.install.excludedocs';
		my $curExclDocs = $zconfig->val('main', $optionParam);
		$this->{curExclDocs} = $curExclDocs;
		if (defined $imgExclDocs) {
			$kiwi -> info ("Setting RPM doc exclusion to: $imgExclDocs");
			$zconfig->newval('main', $optionParam, $imgExclDocs);
			$zconfig->RewriteConfig;
			$kiwi -> done ();
		}
	}
	#==========================================
	# ensconce
	#------------------------------------------
	if ($manager eq "ensconce") {
		# nothing to do here for ensconce...
	}
	#==========================================
	# yum
	#------------------------------------------
	if ($manager eq "yum") {
		# nothing to do here for yum...
	}
	return $this;
}

#==========================================
# resetExcludeDocs
#------------------------------------------
sub resetExcludeDocs {
	# ...
	# reset the signature check option to the previos
	# value of the package manager
	# ---
	my $this   = shift;
	my $kiwi   = $this->{kiwi};
	my $chroot = $this->{chroot};
	my @kchroot= @{$this->{kchroot}};
	my $manager= $this->{manager};
	my $root   = $this->{root};
	my @smart  = @{$this->{smart}};
	my $curExclDocs = $this->{curExclDocs};
	my $data;
	my $code;
	#==========================================
	# smart
	#------------------------------------------
	if ($manager eq "smart") {
		if (defined $this->{imgExclDocs}) {
			my $optionName  = "rpm-excludedocs";
			my $option = "$optionName=$curExclDocs";
			if (! $chroot) {
				$kiwi -> info ("Resetting RPM doc exclusion to: $curExclDocs");
				$data = qxx ("@smart config --set $option 2>&1");
			} else {
				$kiwi -> info ("Resetting RPM doc exclusion to: $curExclDocs");
				$data=qxx ("@kchroot @smart config --set $option 2>&1");
			}
			$code = $? >> 8;
			if ($code != 0) {
				$kiwi -> failed ();
				$kiwi -> error  ($data);
				return undef;
			}
			$kiwi -> done ();
		}
	}
	#==========================================
	# zypper
	#------------------------------------------
	if ($manager eq "zypper") {
		if (defined $this->{imgExclDocs}) {
			my $zconfig = $this->{zconfig};
			my $optionParam = 'rpm.install.excludedocs';
			if (defined $curExclDocs) {
				$kiwi -> info ("Resetting RPM doc exclusion to: $curExclDocs");
				$zconfig->newval('main', $optionParam, $curExclDocs);
			} else {
				$kiwi -> info ("Unsetting RPM doc exclusion");
				$zconfig->delval('main', $optionParam);
			}
			$zconfig->RewriteConfig;
			$kiwi -> done ();
		}
	}
	#==========================================
	# ensconce
	#------------------------------------------
	if ($manager eq "ensconce") {
		# nothing to do here for ensconce...
	}
	#==========================================
	# yum
	#------------------------------------------
	if ($manager eq "yum") {
		# nothing to do here for yum...
	}
	return $this;
}

#==========================================
# setupInstallationSource
#------------------------------------------
sub setupInstallationSource {
	# ...
	# setup an installation source to retrieve packages
	# from. multiple sources are allowed
	# ---
	my $this   = shift;
	my $kiwi   = $this->{kiwi};
	my $chroot = $this->{chroot};
	my @kchroot= @{$this->{kchroot}};
	my %source = %{$this->{source}};
	my $root   = $this->{root};
	my $manager= $this->{manager};
	my @zypper = @{$this->{zypper}};
	my @smart  = @{$this->{smart}};
	my @rootdir= @{$this->{smartroot}};
	my $dataDir= $this->{dataDir};
	my @yum    = @{$this->{yum}};
	my $data;
	my $code;
	#==========================================
	# Reset channel list
	#------------------------------------------
	my @channelList = ();

	#==========================================
	# smart
	#------------------------------------------
	if ($manager eq "smart") {
		my $stype  = "private";
		my $cmds   = "@smart channel --add";
		#==========================================
		# make sure channel list is clean
		#------------------------------------------
		my @chls = qxx ("@smart channel --show | grep ^\'\\[\'|tr -d [] 2>&1");
		foreach my $c (@chls) {
			chomp $c; qxx ("@smart channel --remove $c -y 2>&1");
		}
		#==========================================
		# re-add new channels
		#------------------------------------------
		if (! $chroot) {
			$stype = "public";
			$cmds  = "@smart @rootdir channel --add";
		}
		foreach my $chl (keys %{$source{$stype}}) {
			my @opts = @{$source{$stype}{$chl}};
			@opts = map { if (defined $_) { $_ }  } @opts;
			if (! $chroot) {
				$kiwi -> info ("Adding bootstrap smart channel: $chl");
				$data = qxx ("$cmds $chl @opts 2>&1");
				$code = $? >> 8;
			} else {
				$kiwi -> info ("Adding chroot smart channel: $chl");
				$data = qxx ("@kchroot $cmds $chl @opts 2>&1");
				$code = $? >> 8;
			}
			if ($code != 0) {
				$kiwi -> failed ();
				$kiwi -> error  ("smart: $data");
				return undef;
			}
			push (@channelList,$chl);
			$kiwi -> done ();
		}
	}
	#==========================================
	# zypper
	#------------------------------------------
	if ($manager eq "zypper") {
		my $stype = "private";
		my $prio;
		qxx ("rm -f $dataDir/*.repo");
		if (! $chroot) {
			$stype = "public";
		}
		foreach my $alias (keys %{$source{$stype}}) {
			my @sopts = @{$source{$stype}{$alias}};
			my @zopts = ();
			foreach my $opt (@sopts) {
				next if ! defined $opt;
				$opt =~ /(.*?)=(.*)/;
				my $key = $1;
				my $val = $2;
				#==========================================
				# keep packages on remote repos
				#------------------------------------------
				if ($val =~ /^'ftp:\/\/|http:\/\/|https:\/\/|opensuse:\/\//) {
					push (@zopts,"--keep-packages");
				}
				#==========================================
				# Adapt URI parameter
				#------------------------------------------
				if (($key eq "baseurl") || ($key eq "path")) {
					if ($val =~ /^'\//) {
						$val =~ s/^'(.*)'$/"file:\/\/$1"/
					}
					push (@zopts,$val);
				}
				#==========================================
				# Adapt type parameter
				#------------------------------------------
				if ($key eq "type") {
					if ($val eq "yast2") {
						$val = "YaST";
					}
					if ($val eq "rpm-dir") {
						$val = "Plaindir";
					}
					if ($val eq "rpm-md") {
						$val = "YUM";
					}
					push (@zopts,"--type $val");
				}
				#==========================================
				# Adapt priority parameter
				#------------------------------------------
				if ($key eq "priority") {
					$prio = $val;
				}
			}
			my $sadd = "addrepo -f @zopts $alias";
			if (! $chroot) {
				$kiwi -> info ("Adding bootstrap zypper service: $alias");
				$data = qxx ("@zypper --root \"$root\" $sadd 2>&1");
				$code = $? >> 8;
			} else {
				$kiwi -> info ("Adding chroot zypper service: $alias");
				$data = qxx ("@kchroot zypper --version 2>&1 | cut -c 8");
				if ($data >= 1) {
					$data = qxx ("@kchroot @zypper $sadd 2>&1");
					$code = $? >> 8;
				} else {
					$kiwi -> skipped ();
					$kiwi -> info ("image zypper version is too old");
					$kiwi -> skipped ();
					return $this;
				}
			}
			if ($code != 0) {
				$kiwi -> failed ();
				$kiwi -> error  ("zypper: $data");
				return undef;
			}
			$kiwi -> done ();
			if ( $prio ) {
				$kiwi -> info ("--> Set priority to: $prio");
				my $modrepo = "modifyrepo -p $prio $alias";
				if (! $chroot) {
					$data = qxx ("@zypper --root \"$root\" $modrepo 2>&1");
					$code = $? >> 8;
				} else {
					$data = qxx ("@kchroot @zypper $modrepo 2>&1");
					$code = $? >> 8;
				}
				if ($code != 0) {
					$kiwi -> failed ();
					$kiwi -> error  ("zypper: $data");
					return undef;
				}
				$kiwi -> done ();
			}
			push (@channelList,$alias);
		}
	}
	#==========================================
	# ensconce
	#------------------------------------------
	if ($manager eq "ensconce") {
		# Ignored for ensconce
	}
	#==========================================
	# yum
	#------------------------------------------
	if ($manager eq "yum") {
		my $stype  = "private";
		if (! $chroot) {
			$stype = "public";
		}
		foreach my $alias (keys %{$source{$stype}}) {
			my @sopts = @{$source{$stype}{$alias}};
			my $repo  = "$dataDir/$alias.repo";
			#==========================================
			# create new repo file and open it
			#------------------------------------------
			qxx ("echo '[$alias]' > $repo");
			$data = new Config::IniFiles (
				-file => $repo, -allowedcommentchars => '#'
			);
			#==========================================
			# walk through the repo options
			#------------------------------------------
			foreach my $opt (@sopts) {
				next if ! defined $opt;
				$opt =~ /(.*?)=(.*)/;
				my $key = $1;
				my $val = $2;
				#==========================================
				# Set baseurl and name parameter
				#------------------------------------------
				if (($key eq "baseurl") || ($key eq "path")) {
					if ($val =~ /^'\//) {
						$val =~ s/^'(.*)'$/"file:\/\/$1"/
					}
					$val =~ s/^\"//;
					$val =~ s/\"$//;
					$val =~ s/^\'//;
					$val =~ s/\'$//;
					$data -> newval ($alias, "name"   , $alias);
					$data -> newval ($alias, "baseurl", $val);
				}
			}
			if (! $chroot) {
				$kiwi -> info ("Adding bootstrap yum repo: $alias");
			} else {
				$kiwi -> info ("Adding chroot yum repo: $alias");
			}
			push (@channelList,$alias);
			$data -> RewriteConfig();
			$kiwi -> done();
		}
		#==========================================
		# create cache file
		#------------------------------------------
		if (! $chroot) {
			$kiwi -> info ("Creating yum metadata cache...");
			$data = qxx ("@yum makecache 2>&1");
			$code = $? >> 8;
			if ($code != 0) {
				$kiwi -> failed ();
				$kiwi -> error  ("yum: $data");
				return undef;
			}
			$kiwi -> done();
		}
	}
	$this->{channelList} = \@channelList;
	return $this;
}

#==========================================
# resetInstallationSource
#------------------------------------------
sub resetInstallationSource {
	# ...
	# clean the installation source environment
	# which means remove temporary inst-sources
	# ---
	my $this   = shift;
	my $kiwi   = $this->{kiwi};
	my $chroot = $this->{chroot};
	my @kchroot= @{$this->{kchroot}};
	my $manager= $this->{manager};
	my $root   = $this->{root};
	my @zypper = @{$this->{zypper}};
	my @smart  = @{$this->{smart}};
	my @rootdir= @{$this->{smartroot}};
	my $dataDir= $this->{dataDir};
	my @channelList = @{$this->{channelList}};
	my $data;
	my $code;
	#==========================================
	# smart
	#------------------------------------------
	if ($manager eq "smart") {
		my @list   = @channelList;
		my $cmds   = "@smart channel --remove";
		if (! $chroot) {
			$cmds="@smart @rootdir channel --remove";
		}
		if (! $chroot) {
			$kiwi -> info ("Removing smart channel(s): @channelList");
			$data = qxx ("$cmds @list -y 2>&1");
			$code = $? >> 8;
		} else {
			$kiwi -> info ("Removing smart channel(s): @channelList");
			$data = qxx ("@kchroot $cmds @list -y 2>&1");
			$code = $? >> 8;
		}
		if ($code != 0) {
			$kiwi -> failed ();
			$kiwi -> error  ($data);
			return undef;
		}
		$kiwi -> done ();
	}
	#==========================================
	# zypper
	#------------------------------------------
	if ($manager eq "zypper") {
		my @list = @channelList;
		my $cmds = "@zypper removerepo";
		if (! $chroot) {
			$cmds = "@zypper --root $root removerepo";
		}
		if (! $chroot) {
			$kiwi -> info ("Removing zypper service(s): @channelList");
			foreach my $chl (@list) {
				$data = qxx ("bash -c \"$cmds $chl 2>&1\"");
				$code = $? >> 8;
				if ($code != 0) {
					last;
				}
			}
		} else {
			$kiwi -> info ("Removing zypper service(s): @channelList");
			foreach my $chl (@list) {
				$data = qxx ("@kchroot bash -c \"$cmds $chl 2>&1\"");
				$code = $? >> 8;
				if ($code != 0) {
					last;
				}
			}
		}
		if ($code != 0) {
			$kiwi -> failed ();
			$kiwi -> error  ($data);
			return undef;
		}
		$kiwi -> done ();
	}
	#==========================================
	# ensconce
	#------------------------------------------
	if ($manager eq "ensconce") {
		# Ignored for ensconce
	}
	#==========================================
	# yum
	#------------------------------------------
	if ($manager eq "yum") {
		$kiwi -> info ("Removing yum repo(s) in: $dataDir");
		qxx ("rm -f $dataDir/*.repo 2>&1");
		$kiwi -> done ();
	}
	return $this;
}

#==========================================
# setupDownload
#------------------------------------------
sub setupDownload {
	# ...
	# download package files for later handling
	# using the package manager download functionality
	# ---
	my $this   = shift;
	my $kiwi   = $this->{kiwi};
	my $manager= $this->{manager};
	my $root   = $this->{root};
	my @smart  = @{$this->{smart}};
	my @channelList = @{$this->{channelList}};
	my $screenCall  = $this->{screenCall};
	my @pacs   = @_;
	#==========================================
	# setup screen call
	#------------------------------------------
	my $fd = $this -> setupScreen();
	if (! defined $fd) {
		return undef;
	}
	#==========================================
	# smart
	#------------------------------------------
	if ($manager eq "smart") {
		$kiwi -> info ("Downloading packages...");
		my @loadOpts = (
			"--target=$root"
		);
		#==========================================
		# Create screen call file
		#------------------------------------------
		print $fd "function clean { kill \$SPID; ";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
		print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
		print $fd "c=\$((\$c+1));done;\n";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
		print $fd "rm -f $root/etc/smart/channels/*; ";
		print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
		print $fd "trap clean INT TERM\n";
		print $fd "@smart update @channelList &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "test \$? = 0 && @smart download @pacs @loadOpts &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "ECODE=\$?\n";
		print $fd "echo \$ECODE > $screenCall.exit\n";
		print $fd "rm -f $root/etc/smart/channels/*\n";
		print $fd "exit \$ECODE\n";
		$fd -> close();
	}
	#==========================================
	# zypper
	#------------------------------------------
	if ($manager eq "zypper") {
		# FIXME
		$kiwi -> failed ();
		$kiwi -> error  ("*** not implemeted ***");
		$kiwi -> failed ();
		return undef;
	}
	#==========================================
	# ensconce
	#------------------------------------------
	if ($manager eq "ensconce") {
		# FIXME
		$kiwi -> failed ();
		$kiwi -> error  ("*** not implemeted ***");
		$kiwi -> failed ();
		return undef;
	}
	#==========================================
	# yum
	#------------------------------------------
	if ($manager eq "yum") {
		# FIXME
		$kiwi -> failed ();
		$kiwi -> error  ("*** not implemeted ***");
		$kiwi -> failed ();
		return undef;
	}
	return $this -> setupScreenCall();
}

#==========================================
# installPackages
#------------------------------------------
sub installPackages {
	# ...
	# install packages in the previosly installed root
	# system using the package manager install method
	# ---
	my $this       = shift;
	my $instPacks  = shift;
	my $kiwi       = $this->{kiwi};
	my $root       = $this->{root};
	my @kchroot    = @{$this->{kchroot}};
	my $manager    = $this->{manager};
	my @smart      = @{$this->{smart}};
	my @zypper     = @{$this->{zypper}};
	my @yum        = @{$this->{yum}};
	my $screenCall = $this->{screenCall};
	#==========================================
	# check addon packages
	#------------------------------------------
	if (! defined $instPacks) {
		return $this;
	}
	#==========================================
	# setup screen call
	#------------------------------------------
	my @addonPackages = @{$instPacks};
	my $fd = $this -> setupScreen();
	if (! defined $fd) {
		return undef;
	}
	#==========================================
	# smart
	#------------------------------------------
	if ($manager eq "smart") {
		#==========================================
		# Create screen call file
		#------------------------------------------
		$kiwi -> info ("Installing addon packages...");
		print $fd "function clean { kill \$SPID;";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
		print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
		print $fd "c=\$((\$c+1));done;\n";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
		print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
		print $fd "trap clean INT TERM\n";
		print $fd "@kchroot @smart update &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "test \$? = 0 && @kchroot @smart channel --show &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "test \$? = 0 && @kchroot @smart install -y ";
		print $fd "@addonPackages || false &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "ECODE=\$?\n";
		print $fd "echo \$ECODE > $screenCall.exit\n";
		print $fd "exit \$ECODE\n";
		$fd -> close();
	}
	#==========================================
	# zypper
	#------------------------------------------
	if ($manager eq "zypper") {
		#==========================================
		# Create screen call file
		#------------------------------------------
		$kiwi -> info ("Installing addon packages...");
		my @installOpts = (
			"--auto-agree-with-licenses"
		);
		print $fd "function clean { kill \$SPID;";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
		print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
		print $fd "c=\$((\$c+1));done;\n";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
		print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
		print $fd "trap clean INT TERM\n";
		print $fd "export ZYPP_MODALIAS_SYSFS=/tmp\n";
		print $fd "export YAST_IS_RUNNING=true\n";
		print $fd "export ZYPP_CONF=".$this->{zyppconf}."\n";
		print $fd "@kchroot @zypper install ";
		print $fd "@installOpts @addonPackages &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "ECODE=\$?\n";
		print $fd "echo \$ECODE > $screenCall.exit\n";
		print $fd "exit \$ECODE\n";
		$fd -> close();
	}
	#==========================================
	# ensconce
	#------------------------------------------
	if ($manager eq "ensconce") {
		# FIXME
		$kiwi -> failed ();
		$kiwi -> error  ("*** not implemeted ***");
		$kiwi -> failed ();
		$fd -> close();
		return undef;
	}
	#==========================================
	# yum
	#------------------------------------------
	if ($manager eq "yum") {
		#==========================================
		# Create screen call file
		#------------------------------------------
		$kiwi -> info ("Installing addon packages...");
		print $fd "function clean { kill \$SPID;";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
		print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;";
		print $fd "c=\$((\$c+1));done;\n";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
		print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
		print $fd "trap clean INT TERM\n";
		print $fd "for i in @@addonPackages;do\n";
		print $fd "\tif ! @kchroot @yum list all \$i;then\n";
		print $fd "\t\tECODE=1\n";
		print $fd "\t\techo \$ECODE > $screenCall.exit\n";
		print $fd "\t\texit \$ECODE\n";
		print $fd "\tfi\n";
		print $fd "done\n";
		print $fd "@kchroot @yum install @addonPackages &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "ECODE=\$?\n";
		print $fd "echo \$ECODE > $screenCall.exit\n";
		print $fd "exit \$ECODE\n";
		$fd -> close();
	}
	return $this -> setupScreenCall();
}

#==========================================
# removePackages
#------------------------------------------
sub removePackages {
	# ...
	# remove packages from the previosly installed root
	# system using the package manager remove method
	# ---
	my $this       = shift;
	my $removePacks= shift;
	my $kiwi       = $this->{kiwi};
	my $root       = $this->{root};
	my @kchroot    = @{$this->{kchroot}};
	my $manager    = $this->{manager};
	my @smart      = @{$this->{smart}};
	my @zypper     = @{$this->{zypper}};
	my @yum        = @{$this->{yum}};
	my $screenCall = $this->{screenCall};
	#==========================================
	# check to be removed packages
	#------------------------------------------
	if (! defined $removePacks) {
		return $this;
	}
	#==========================================
	# setup screen call
	#------------------------------------------
	my @removePackages = @{$removePacks};
	if (! @removePackages) {
		return $this;
	}
	my $fd = $this -> setupScreen();
	if (! defined $fd) {
		return undef;
	}
	#==========================================
	# smart
	#------------------------------------------
	if ($manager eq "smart") {
		#==========================================
		# Create screen call file
		#------------------------------------------
		$kiwi -> info ("Removing addon packages...");
		print $fd "function clean { kill \$SPID;";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
		print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
		print $fd "c=\$((\$c+1));done;\n";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
		print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
		print $fd "trap clean INT TERM\n";
		print $fd "@kchroot @smart update &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "test \$? = 0 && @kchroot @smart channel --show &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "test \$? = 0 && @kchroot @smart remove -y ";
		print $fd "@removePackages || false &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "ECODE=\$?\n";
		print $fd "echo \$ECODE > $screenCall.exit\n";
		print $fd "exit \$ECODE\n";
		$fd -> close();
	}
	#==========================================
	# zypper
	#------------------------------------------
	if ($manager eq "zypper") {
		#==========================================
		# Create screen call file
		#------------------------------------------
		$kiwi -> info ("Removing addon packages...");
		my @installOpts = (
			"--force-resolution"
		);
		print $fd "function clean { kill \$SPID;";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
		print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
		print $fd "c=\$((\$c+1));done;\n";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
		print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
		print $fd "trap clean INT TERM\n";
		print $fd "export ZYPP_MODALIAS_SYSFS=/tmp\n";
		print $fd "export YAST_IS_RUNNING=true\n";
		print $fd "export ZYPP_CONF=".$this->{zyppconf}."\n";
		print $fd "@kchroot @zypper remove ";
		print $fd "@installOpts @removePackages || true &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "ECODE=\$?\n";
		print $fd "echo \$ECODE > $screenCall.exit\n";
		print $fd "exit \$ECODE\n";
		$fd -> close();
	}
	#==========================================
	# ensconce
	#------------------------------------------
	if ($manager eq "ensconce") {
		# FIXME
		$kiwi -> failed ();
		$kiwi -> error  ("*** not implemeted ***");
		$kiwi -> failed ();
		$fd -> close();
		return undef;
	}
	#==========================================
	# yum
	#------------------------------------------
	if ($manager eq "yum") {
		#==========================================
		# Create screen call file
		#------------------------------------------
		$kiwi -> info ("Removing addon packages...");
		print $fd "function clean { kill \$SPID;";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
		print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;";
		print $fd "c=\$((\$c+1));done;\n";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
		print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
		print $fd "trap clean INT TERM\n";
		print $fd "@kchroot @yum remove @removePackages &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "ECODE=\$?\n";
		print $fd "echo \$ECODE > $screenCall.exit\n";
		print $fd "exit \$ECODE\n";
		$fd -> close();
	}
	return $this -> setupScreenCall();
}

#==========================================
# setupUpgrade
#------------------------------------------
sub setupUpgrade {
	# ...
	# upgrade the previosly installed root system
	# using the package manager upgrade functionality
	# ---
	my $this       = shift;
	my $addPacks   = shift;
	my $delPacks   = shift;
	my $kiwi       = $this->{kiwi};
	my $root       = $this->{root};
	my $xml        = $this->{xml};
	my @kchroot    = @{$this->{kchroot}};
	my $manager    = $this->{manager};
	my @smart      = @{$this->{smart}};
	my @zypper     = @{$this->{zypper}};
	my @yum        = @{$this->{yum}};
	my $screenCall = $this->{screenCall};
	#==========================================
	# setup screen call
	#------------------------------------------
	my $fd = $this -> setupScreen();
	if (! defined $fd) {
		return undef;
	}
	#==========================================
	# smart
	#------------------------------------------
	if ($manager eq "smart") {
		my @opts = (
			"--log-level=error",
			"-y"
		);
		my $force = $xml -> getRPMForce();
		if (defined $force) {
			push (@opts,"-o rpm-force=yes");
		}
		#==========================================
		# Create screen call file
		#------------------------------------------
		$kiwi -> info ("Upgrading image...");
		print $fd "function clean { kill \$SPID;";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
		print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;";
		print $fd "c=\$((\$c+1));done;\n";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
		print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
		print $fd "trap clean INT TERM\n";
		print $fd "@kchroot @smart update &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "test \$? = 0 && ";
		print $fd "@kchroot @smart channel --show &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		if (defined $delPacks) {
			my @removePackages = @{$delPacks};
			if (@removePackages) {
				print $fd "test \$? = 0 && @kchroot @smart remove -y ";
				print $fd "@removePackages || false &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
		}
		if (defined $addPacks) {
			my @addonPackages = @{$addPacks};
			if (@addonPackages) {
				print $fd "test \$? = 0 && @kchroot @smart upgrade @opts ";
				print $fd "|| false &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
				print $fd "test \$? = 0 && @kchroot @smart install @opts ";
				print $fd "@addonPackages || false &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
		} else {
			print $fd "test \$? = 0 && @kchroot @smart upgrade @opts &\n";
			print $fd "SPID=\$!;wait \$SPID\n";
		}
		print $fd "ECODE=\$?\n";
		print $fd "echo \$ECODE > $screenCall.exit\n";
		print $fd "exit \$ECODE\n";
		$fd -> close();
	}
	#==========================================
	# zypper
	#------------------------------------------
	if ($manager eq "zypper") {
		#==========================================
		# Create screen call file
		#------------------------------------------
		$kiwi -> info ("Upgrading image...");
		my @installOpts = (
			"--auto-agree-with-licenses"
		);
		my %pattr = $xml -> getPackageAttributes("image");
		if ($pattr{patternType} ne "plusRecommended") {
			push (@installOpts,"--no-recommends");
		}
		print $fd "ZV=\$(@kchroot zypper --version 2>&1 | cut -c 8)"."\n";
		print $fd 'if [ $ZV = 0 ];then'."\n";
		print $fd "\t".'echo "image zypper version is too old, upgrade skipped"'."\n";
		print $fd "\t"."ECODE=0\n";
		print $fd "\t"."echo \$ECODE > $screenCall.exit\n";
		print $fd "\t"."exit \$ECODE\n";
		print $fd "fi"."\n";
		print $fd "function clean { kill \$SPID;";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
		print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
		print $fd "c=\$((\$c+1));done;\n";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
		print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
		print $fd "trap clean INT TERM\n";
		print $fd "export ZYPP_MODALIAS_SYSFS=/tmp\n";
		print $fd "export YAST_IS_RUNNING=true\n";
		print $fd "export ZYPP_CONF=".$this->{zyppconf}."\n";
		if (defined $delPacks) {
			my @removePackages = @{$delPacks};
			if (@removePackages) {
				print $fd "@kchroot @zypper remove ";
				print $fd "--force-resolution @removePackages || true &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
				print $fd "test \$? = 0 && ";
			}
		}
		if (defined $addPacks) {
			my @addonPackages = @{$addPacks};
			my @newpatts = ();
			my @newprods = ();
			my @newpacks = ();
			foreach my $pac (@addonPackages) {
				if ($pac =~ /^pattern:(.*)/) {
					push @newpatts,"\"$1\"";
				} elsif ($pac =~ /^product:(.*)/) {
					push @newprods,$1;
				} else {
					push @newpacks,$pac;
				}
			}
			@addonPackages = @newpacks;
			print $fd "@kchroot @zypper dist-upgrade @installOpts &\n";
			print $fd "SPID=\$!;wait \$SPID\n";
			if (@newprods) {
				print $fd "test \$? = 0 && @kchroot @zypper install ";
				print $fd "@installOpts -t product @newprods &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
			if (@newpatts) {
				print $fd "test \$? = 0 && @kchroot @zypper install ";
				print $fd "@installOpts -t pattern @newpatts &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
			if (@addonPackages) {
				print $fd "test \$? = 0 && @kchroot @zypper install ";
				print $fd "@installOpts @addonPackages &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
		} else {
			print $fd "@kchroot @zypper dist-upgrade @installOpts &\n";
			print $fd "SPID=\$!;wait \$SPID\n";
		}
		print $fd "ECODE=\$?\n";
		print $fd "echo \$ECODE > $screenCall.exit\n";
		print $fd "exit \$ECODE\n";
		$fd -> close();
	}
	#==========================================
	# ensconce
	#------------------------------------------
	if ($manager eq "ensconce") {
		# Ignored for ensconce, always report package as installed
		print $fd "echo 0 > $screenCall.exit; exit 0\n";
		$fd -> close();
		return $this;
	}
	#==========================================
	# yum
	#------------------------------------------
	if ($manager eq "yum") {
		#==========================================
		# Create screen call file
		#------------------------------------------
		$kiwi -> info ("Upgrading image...");
		print $fd "function clean { kill \$SPID;";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
		print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
		print $fd "c=\$((\$c+1));done;\n";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
		print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
		print $fd "trap clean INT TERM\n";
		if (defined $delPacks) {
			my @removePackages = @{$delPacks};
			if (@removePackages) {
				print $fd "@kchroot @yum remove @removePackages &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
				print $fd "test \$? = 0 && ";
			}
		}
		if (defined $addPacks) {
			my @addonPackages = @{$addPacks};
			my @newpatts = ();
			my @newpacks = ();
			foreach my $pac (@addonPackages) {
				if ($pac =~ /^pattern:(.*)/) {
					push @newpatts,"\"$1\"";
				} else {
					push @newpacks,$pac;
				}
			}
			@addonPackages = @newpacks;
			print $fd "@kchroot @yum upgrade &\n";
			print $fd "SPID=\$!;wait \$SPID\n";
			if (@newpatts) {
				print $fd "for i in @newpatts;do\n";
				print $fd "\tif ! @kchroot @yum grouplist | grep -q \"\$i\";then\n";
				print $fd "\t\tECODE=1\n";
				print $fd "\t\techo \$ECODE > $screenCall.exit\n";
				print $fd "\t\texit \$ECODE\n";
				print $fd "\tfi\n";
				print $fd "done\n";
				print $fd "test \$? = 0 && @kchroot @yum groupinstall @newpatts &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
			if (@addonPackages) {
				print $fd "for i in @@addonPackages;do\n";
				print $fd "\tif ! @kchroot @yum list all \$i;then\n";
				print $fd "\t\tECODE=1\n";
				print $fd "\t\techo \$ECODE > $screenCall.exit\n";
				print $fd "\t\texit \$ECODE\n";
				print $fd "\tfi\n";
				print $fd "done\n";
				print $fd "test \$? = 0 && @kchroot @yum install @addonPackages &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
		} else {
			print $fd "@kchroot @yum upgrade &\n";
			print $fd "SPID=\$!;wait \$SPID\n";
		}
		print $fd "ECODE=\$?\n";
		print $fd "echo \$ECODE > $screenCall.exit\n";
		print $fd "exit \$ECODE\n";
		$fd -> close();
	}
	return $this -> setupScreenCall();
}

#==========================================
# setupInstallPackages
#------------------------------------------
sub setupInstallPackages {
	# ...
	# create the install packages list from the information
	# of the package types image, xen and vmware. Store
	# the result in the object pointer
	# ---
	my $this   = shift;
	my $kiwi   = $this->{kiwi};
	my $xml    = $this->{xml};
	#==========================================
	# check cached result
	#------------------------------------------
	if (defined $this->{packlist}) {
		return @{$this->{packlist}};
	}
	#==========================================
	# Get image package list
	#------------------------------------------
	my @packList = $xml -> getInstallList();
	#==========================================
	# Get type specific packages if set
	#------------------------------------------
	my @typeList = $xml -> getTypeList();
	if (@typeList) {
		push @packList,@typeList;
	}
	$this->{packlist} = \@packList;
	return @packList;
}

#==========================================
# setupArchives
#------------------------------------------
sub setupArchives {
	# ...
	# install the given tar archives into the
	# root system
	# ---
	my $this    = shift;
	my $idesc   = shift;
	my @tars    = @_;
	my $kiwi    = $this->{kiwi};
	my $chroot  = $this->{chroot};
	my @kchroot = @{$this->{kchroot}};
	my $root    = $this->{root};
	my $screenCall = $this->{screenCall};
	#==========================================
	# check for empty list
	#------------------------------------------
	if (! @tars) {
		return $this;
	}
	#==========================================
	# check for chroot
	#------------------------------------------
	if ($chroot) {
		$kiwi -> error ("Can't access archives in chroot");
		return undef;
	}
	#==========================================
	# override path to image description
	#------------------------------------------
	if ((defined $main::ImageDescription) && (-d $main::ImageDescription)) {
		$idesc = $main::ImageDescription;
	}
	#==========================================
	# check for archive files
	#------------------------------------------
	foreach my $tar (@tars) {
		if (! -f "$idesc/$tar") {
			$kiwi -> error ("Can't find $idesc/$tar");
			return undef;
		}
	}
	#==========================================
	# setup screen call
	#------------------------------------------
	my $fd = $this -> setupScreen();
	if (! defined $fd) {
		return undef;
	}
	$kiwi -> info ("Installing raw archives in: $root...");
	#==========================================
	# Create screen call file
	#------------------------------------------
	print $fd "function clean { kill \$SPID;";
	print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
	print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
	print $fd "c=\$((\$c+1));done;\n";
	print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
	print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
	print $fd "trap clean INT TERM\n";
	print $fd "for i in @tars;do\n";
	print $fd "   tar -tf $idesc/\$i >> $root/bootincluded_archives.filelist\n";
	print $fd "   if ! tar -C $root -xvf $idesc/\$i;then\n";
	print $fd "       ECODE=\$?\n";
	print $fd "       echo \$ECODE > $screenCall.exit\n";
	print $fd "       exit \$ECODE\n";
	print $fd "   fi\n";
	print $fd "done\n";
	print $fd "echo 0 > $screenCall.exit\n";
	print $fd "exit 0\n";
	$fd -> close();
	#==========================================
	# Call it
	#------------------------------------------
	return $this -> setupScreenCall();
}

#==========================================
# setupRootSystem
#------------------------------------------
sub setupRootSystem {
	# ...
	# install the bootstrap system to be able to
	# chroot into this minimal image
	# ---
	my $this        = shift;
	my @packs       = @_;
	my $kiwi        = $this->{kiwi};
	my $chroot      = $this->{chroot};
	my @kchroot     = @{$this->{kchroot}};
	my $root        = $this->{root};
	my $xml         = $this->{xml};
	my $manager     = $this->{manager};
	my @zypper      = @{$this->{zypper}};
	my @smart       = @{$this->{smart}};
	my @rootdir     = @{$this->{smartroot}};
	my @ensconce    = @{$this->{ensconce}};
	my @channelList = @{$this->{channelList}};
	my $screenCall  = $this->{screenCall};
	my @yum         = @{$this->{yum}};
	my %source      = %{$this->{source}};
	#==========================================
	# search for licenses on media
	#------------------------------------------
	if (! $chroot) {
		my $license = "license.tar.gz";
		foreach my $alias (keys %{$source{public}}) {
			my $repo = $alias;
			foreach my $opt (@{$source{public}{$alias}}) {
				$opt =~ /(.*?)=(.*)/;
				my $key = $1;
				my $val = $2;
				if (($key eq "baseurl") || ($key eq "path")) {
					if ($val =~ /^'\//) {
						$val =~ s/^'(.*)'$/"file:\/\/$1"/
					}
					$repo = $val;
				}
			}
			KIWIXML::getInstSourceFile (
				$kiwi,$repo."/".$license,$root."/".$license
			);
			last if -e $root."/".$license;
		}
	}
	#==========================================
	# setup screen call
	#------------------------------------------
	my $fd = $this -> setupScreen();
	if (! defined $fd) {
		return undef;
	}
	#==========================================
	# smart
	#------------------------------------------
	if ($manager eq "smart") {
		if (! $chroot) {
			#==========================================
			# setup install options outside of chroot
			#------------------------------------------
			my @installOpts = (
				"--explain",
				"--log-level=error",
				"-y"
			);
			my $force = $xml -> getRPMForce();
			if (defined $force) {
				push (@installOpts,"-o rpm-force=yes");
			}
			#==========================================
			# Add package manager to package list
			#------------------------------------------
			if ($this -> setupInstallPackages()) {
				push (@packs,$manager);
			}
			#==========================================
			# Setup baselibs
			#------------------------------------------
			$kiwi -> info ("Setting up bootstrap baselibs...");
			if (! $this -> rpmLibs()) {
				$kiwi -> failed();
				return undef;
			}
			$kiwi -> done();
			$kiwi -> info ("Initializing image system on: $root...");
			#==========================================
			# Create screen call file
			#------------------------------------------
			print $fd "function clean { kill \$SPID;";
			print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
			print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
			print $fd "c=\$((\$c+1));done;\n";
			print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
			print $fd "rm -f $root/etc/smart/channels/*; ";
			print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
			print $fd "trap clean INT TERM\n";
			print $fd "@smart @rootdir channel --show &\n";
			print $fd "SPID=\$!;wait \$SPID\n";
			print $fd "test \$? = 0 && @smart @rootdir update ";
			print $fd "@channelList || false &\n";
			print $fd "SPID=\$!;wait \$SPID\n";
			print $fd "test \$? = 0 && @smart @rootdir install ";
			print $fd "@packs @installOpts &\n";
			print $fd "SPID=\$!;wait \$SPID\n";
			print $fd "ECODE=\$?\n";
			print $fd "echo \$ECODE > $screenCall.exit\n";
			print $fd "rm -f $root/etc/smart/channels/*\n";
			print $fd "exit \$ECODE\n";
		} else {
			#==========================================
			# setup install options inside of chroot
			#------------------------------------------
			my @install = @packs;
			my @installOpts = (
				"--explain",
				"--log-level=error",
				"-y"
			);
			my $force = $xml -> getRPMForce();
			if (defined $force) {
				push (@installOpts,"-o rpm-force=yes");
			}
			#==========================================
			# Create screen call file
			#------------------------------------------
			$kiwi -> info ("Installing image packages...");
			print $fd "function clean { kill \$SPID;";
			print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
			print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
			print $fd "c=\$((\$c+1));done;\n";
			print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
			print $fd "echo 1 > $screenCall.exit;exit 1; }\n";
			print $fd "trap clean INT TERM\n";
			print $fd "@kchroot @smart update &\n";
			print $fd "SPID=\$!;wait \$SPID\n";
			print $fd "test \$? = 0 && @kchroot @smart channel --show &\n";
			print $fd "SPID=\$!;wait \$SPID\n";
			print $fd "test \$? = 0 && @kchroot @smart install ";
			print $fd "@install @installOpts &\n";
			print $fd "SPID=\$!;wait \$SPID\n";
			print $fd "ECODE=\$?\n";
			print $fd "echo \$ECODE > $screenCall.exit\n";
			print $fd "exit \$ECODE\n";
		}
		$fd -> close();
	}
	#==========================================
	# zypper
	#------------------------------------------
	if ($manager eq "zypper") {
		if (! $chroot) {
			#==========================================
			# setup install options outside of chroot
			#------------------------------------------
			my @installOpts = (
				"--auto-agree-with-licenses"
			);
			my %pattr = $xml -> getPackageAttributes("bootstrap");
			if ($pattr{patternType} ne "plusRecommended") {
				push (@installOpts,"--no-recommends");
			}
			#==========================================
			# Add package manager to package list
			#------------------------------------------
			if ($this -> setupInstallPackages()) {
				push (@packs,$manager);
			}
			#==========================================
			# Setup baselibs
			#------------------------------------------
			$kiwi -> info ("Setting up bootstrap baselibs...");
			if (! $this -> rpmLibs()) {
				$kiwi -> failed();
				return undef;
			}
			$kiwi -> done();
			$kiwi -> info ("Initializing image system on: $root...");
			#==========================================
			# check input list for pattern names
			#------------------------------------------
			my @newpacks = ();
			my @newpatts = ();
			my @newprods = ();
			foreach my $pac (@packs) {
				if ($pac =~ /^pattern:(.*)/) {
					push @newpatts,"\"$1\"";
				} elsif ($pac =~ /^product:(.*)/) {
					push @newprods,$1;
				} else {
					push @newpacks,$pac;
				}
			}
			@packs = @newpacks;
			#==========================================
			# Create screen call file
			#------------------------------------------
			mkdir "$root/tmp";
			print $fd "function clean { kill \$SPID;";
			print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
			print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
			print $fd "c=\$((\$c+1));done;\n";
			print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
			print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
			print $fd "trap clean INT TERM\n";
			print $fd "export ZYPP_MODALIAS_SYSFS=/tmp\n";
			print $fd "export YAST_IS_RUNNING=true\n";
			print $fd "export ZYPP_CONF=".$root."/".$this->{zyppconf}."\n";
			if (@newprods) {
				print $fd "@zypper --root $root install ";
				print $fd "@installOpts -t product @newprods &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
			if (@newpatts) {
				if (@newprods) {
					print $fd "test \$? = 0 && ";
				}
				print $fd "@zypper --root $root install ";
				print $fd "@installOpts -t pattern @newpatts &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
			if (@packs) {
				if (@newpatts || @newprods) {
					print $fd "test \$? = 0 && ";
				}
				print $fd "@zypper --root $root install ";
				print $fd "@installOpts @packs &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
			print $fd "ECODE=\$?\n";
			print $fd "echo \$ECODE > $screenCall.exit\n";
			print $fd "exit \$ECODE\n";
		} else {
			#==========================================
			# select patterns and packages
			#------------------------------------------
			my @install   = ();
			my @newpatts  = ();
			my @newprods  = ();
			foreach my $need (@packs) {
				if ($need =~ /^pattern:(.*)/) {
					push @newpatts,"\"$1\"";
					next;
				} elsif ($need =~ /^product:(.*)/) {
					push @newprods,$1;
					next;
				}
				push @install,$need;
			}
			#==========================================
			# setup install options inside of chroot
			#------------------------------------------
			my @installOpts = (
				"--auto-agree-with-licenses"
			);
			my %pattr = $xml -> getPackageAttributes("image");
			if ($pattr{patternType} ne "plusRecommended") {
				push (@installOpts,"--no-recommends");
			}
			#==========================================
			# Create screen call file
			#------------------------------------------
			$kiwi -> info ("Installing image packages...");
			print $fd "function clean { kill \$SPID;";
			print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
			print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
			print $fd "c=\$((\$c+1));done;\n";
			print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
			print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
			print $fd "trap clean INT TERM\n";
			print $fd "export ZYPP_MODALIAS_SYSFS=/tmp\n";
			print $fd "export YAST_IS_RUNNING=true\n";
			print $fd "export ZYPP_CONF=".$this->{zyppconf}."\n";
			if (@newprods) {
				print $fd "@kchroot @zypper install ";
				print $fd "@installOpts -t product @newprods &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
			if (@newpatts) {
				if (@newprods) {
					print $fd "test \$? = 0 && ";
				}
				print $fd "@kchroot @zypper install ";
				print $fd "@installOpts -t pattern @newpatts &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
			if (@install) {
				if (@newpatts || @newprods) {
					print $fd "test \$? = 0 && ";
				}
				print $fd "@kchroot @zypper install ";
				print $fd "@installOpts @install &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
			print $fd "ECODE=\$?\n";
			print $fd "echo \$ECODE > $screenCall.exit\n";
			print $fd "exit \$ECODE\n";
		}
		$fd -> close();
	}
	#==========================================
	# ensconce
	#------------------------------------------
	if ($manager eq "ensconce") {
		my $imagename = $xml -> getImageName();
		my $ensconce_args = "-i $imagename";
		if (! $chroot) {
			#==========================================
			# Setup baselibs
			#------------------------------------------
			$kiwi -> info ("Setting up bootstrap baselibs...");
			if (! $this -> rpmLibs()) {
				$kiwi -> failed();
				return undef;
			}
			$kiwi -> done();
			#==========================================
			# Ensconce options
			#------------------------------------------
			$ensconce_args .= " -b";
		}
		if (! $chroot) {
			$kiwi -> info ("Initializing image system on: $root...");
		} else {
			$kiwi -> info ("Installing image packages...");
		}
		print $fd "function clean { kill \$SPID; ";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
		print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
		print $fd "c=\$((\$c+1));done;\n";
		print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
		print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
		print $fd "trap clean INT TERM\n";
		print $fd "@ensconce $ensconce_args &\n";
		print $fd "SPID=\$!;wait \$SPID\n";
		print $fd "ECODE=\$?\n";
		print $fd "echo \$ECODE > $screenCall.exit\n";
		print $fd "exit \$ECODE\n";
		$fd -> close();
	}
	#==========================================
	# yum
	#------------------------------------------
	if ($manager eq "yum") {
		if (! $chroot) {
			#==========================================
			# Add package manager to package list
			#------------------------------------------
			if ($this -> setupInstallPackages()) {
				push (@packs,$manager);
			}
			#==========================================
			# Setup baselibs
			#------------------------------------------
			$kiwi -> info ("Setting up bootstrap baselibs...");
			if (! $this -> rpmLibs()) {
				$kiwi -> failed();
				return undef;
			}
			$kiwi -> done();
			$kiwi -> info ("Initializing image system on: $root...");
			#==========================================
			# check input list for group names
			#------------------------------------------
			my @newpacks = ();
			my @newpatts = ();
			foreach my $pac (@packs) {
				if ($pac =~ /^pattern:(.*)/) {
					push @newpatts,"\"$1\"";
				} else {
					push @newpacks,$pac;
				}
			}
			@packs = @newpacks;
			#==========================================
			# Create screen call file
			#------------------------------------------
			mkdir "$root/tmp";
			print $fd "function clean { kill \$SPID;";
			print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
			print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
			print $fd "c=\$((\$c+1));done;\n";
			print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
			print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
			print $fd "trap clean INT TERM\n";
			if (@newpatts) {
				print $fd "for i in @newpatts;do\n";
				print $fd "\tif ! @yum grouplist | grep -q \"\$i\";then\n";
				print $fd "\t\tECODE=1\n";
				print $fd "\t\techo \$ECODE > $screenCall.exit\n";
				print $fd "\t\texit \$ECODE\n";
				print $fd "\tfi\n";
				print $fd "done\n";
				print $fd "@yum --installroot=$root groupinstall @newpatts &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
			if (@packs) {
				if (@newpatts) {
					print $fd "test \$? = 0 && ";
				}
				print $fd "for i in @newpacks;do\n";
				print $fd "\tif ! @yum list all \$i;then\n";
				print $fd "\t\tECODE=1\n";
				print $fd "\t\techo \$ECODE > $screenCall.exit\n";
				print $fd "\t\texit \$ECODE\n";
				print $fd "\tfi\n";
				print $fd "done\n";
				print $fd "@yum --installroot=$root install @newpacks &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
			print $fd "ECODE=\$?\n";
			print $fd "echo \$ECODE > $screenCall.exit\n";
			print $fd "exit \$ECODE\n";
		} else {
			#==========================================
			# select groups and packages
			#------------------------------------------
			my @install   = ();
			my @newpatts  = ();
			foreach my $need (@packs) {
				if ($need =~ /^pattern:(.*)/) {
					push @newpatts,"\"$1\"";
					next;
				}
				push @install,$need;
			}
			#==========================================
			# Create screen call file
			#------------------------------------------
			$kiwi -> info ("Installing image packages...");
			print $fd "function clean { kill \$SPID;";
			print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;";
			print $fd "if [ \"\$c\" = 5 ];then kill \$SPID;break;fi;"; 
			print $fd "c=\$((\$c+1));done;\n";
			print $fd "while kill -0 \$SPID &>/dev/null; do sleep 1;done\n";
			print $fd "echo 1 > $screenCall.exit; exit 1; }\n";
			print $fd "trap clean INT TERM\n";
			print $fd "@kchroot rpm --rebuilddb &\n";
			print $fd "SPID=\$!;wait \$SPID\n";
			print $fd "test \$? = 0 && ";
			if (@newpatts) {
				print $fd "for i in @newpatts;do\n";
				print $fd "\tif ! @kchroot @yum grouplist | grep -q \"\$i\";then\n";
				print $fd "\t\tECODE=1\n";
				print $fd "\t\techo \$ECODE > $screenCall.exit\n";
				print $fd "\t\texit \$ECODE\n";
				print $fd "\tfi\n";
				print $fd "done\n";
				print $fd "@kchroot @yum groupinstall @newpatts &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
			if (@install) {
				if (@newpatts) {
					print $fd "test \$? = 0 && ";
				}
				print $fd "for i in @install;do\n";
				print $fd "\tif ! @kchroot @yum list all \$i;then\n";
				print $fd "\t\tECODE=1\n";
				print $fd "\t\techo \$ECODE > $screenCall.exit\n";
				print $fd "\t\texit \$ECODE\n";
				print $fd "\tfi\n";
				print $fd "done\n";
				print $fd "@kchroot @yum install @install &\n";
				print $fd "SPID=\$!;wait \$SPID\n";
			}
			print $fd "ECODE=\$?\n";
			print $fd "echo \$ECODE > $screenCall.exit\n";
			print $fd "exit \$ECODE\n";
		}
		$fd -> close();
	}
	#==========================================
	# run process
	#------------------------------------------
	if (! $this -> setupScreenCall()) {
		return undef;
	}
	#==========================================
	# cleanup baselibs
	#------------------------------------------
	if (! $chroot) {
		$this -> rpmLibs ("clean");
	}
	return $this;
}

#==========================================
# resetSource
#------------------------------------------
sub resetSource {
	# ...
	# cleanup source data. In case of any interrupt
	# which means remove all changes made by %source
	# ---
	my $this = shift;
	my $kiwi = $this->{kiwi};
	my %source  = %{$this->{source}};
	my $manager = $this->{manager};
	my @smart   = @{$this->{smart}};
	my @zypper  = @{$this->{zypper}};
	my $dataDir = $this->{dataDir};
	#==========================================
	# smart
	#------------------------------------------
	if ($manager eq "smart") {
		foreach my $channel (keys %{$source{public}}) {
			$kiwi -> info ("Removing smart channel: $channel\n");
			qxx ("@smart channel --remove $channel -y 2>&1");
		}
	}
	#==========================================
	# zypper
	#------------------------------------------
	if ($manager eq "zypper") {
		foreach my $channel (keys %{$source{public}}) {
			$kiwi -> info ("Removing zypper service: $channel\n");
			qxx ("@zypper removerepo $channel 2>&1");
		}
	}
	#==========================================
	# ensconce
	#------------------------------------------
	if ($manager eq "ensconce") {
		# Ignored for ensconce
	}
	#==========================================
	# yum
	#------------------------------------------
	if ($manager eq "yum") {
		$kiwi -> info ("Removing yum repo(s) in: $dataDir");
		qxx ("rm -f $dataDir/*.repo 2>&1");
	}
	return $this;
}

#==========================================
# setupPackageInfo
#------------------------------------------
sub setupPackageInfo {
	# ...
	# check if a given package is installed or not.
	# return the exit code from the call
	# ---
	my $this   = shift;
	my $pack   = shift;
	my $kiwi   = $this->{kiwi};
	my $chroot = $this->{chroot};
	my @kchroot= @{$this->{kchroot}};
	my $root   = $this->{root};
	my $manager= $this->{manager};
	my @zypper = @{$this->{zypper}};
	my @smart  = @{$this->{smart}};
	my @rootdir= @{$this->{smartroot}};
	my $data;
	my $code;
	#==========================================
	# smart
	#------------------------------------------
	if ($manager eq "smart") {
		if (! $chroot) {
			$kiwi -> info ("Checking for package: $pack");
			$data = qxx ("@smart @rootdir query --installed $pack 2>/dev/null");
			$code = $? >> 8;
		} else {
			$kiwi -> info ("Checking for package: $pack");
			$data = qxx (
				"@kchroot @smart query --installed $pack 2>/dev/null"
			);
			$code = $? >> 8;
		}
		if ($code == 0) {
			if (! grep (/$pack/,$data)) {
				$code = 1;
			}
		}
		if ($code != 0) {
			$kiwi -> failed  ();
			$kiwi -> error   ("Package $pack is not installed");
			$kiwi -> skipped ();
			return $code;
		}
		$kiwi -> done();
		return $code;
	}
	#==========================================
	# zypper + yum
	#------------------------------------------
	if (($manager eq "zypper") || ($manager eq "yum")) {
		my $str = "not installed";
		if (! $chroot) {
			$kiwi -> info ("Checking for package: $pack");
			$data = qxx (" rpm -q \"$pack\" 2>&1 ");
			$code = $? >> 8;
		} else {
			$kiwi -> info ("Checking for package: $pack");
			$data= qxx ("@kchroot rpm -q \"$pack\" 2>&1 ");
			$code= $? >> 8;
		}
		if ($code != 0) {
			$kiwi -> failed  ();
			$kiwi -> error   ("Package $pack is not installed");
			$kiwi -> skipped ();
			return 1;
		}
		$kiwi -> done();
		return 0;
	}
	#==========================================
	# ensconce
	#------------------------------------------
	if ($manager eq "ensconce") {
		# Ignored for ensconce, always report package as installed
		return 0;
	}
	return 1;
}

#==========================================
# setupPackageKeys
#------------------------------------------
sub setupPackageKeys {
	# ...
	# import package keys to avoid warnings on installation
	# of packages. This is an rpm only task and needs to be
	# enhanced for non rpm based packages
	# ---
	my $this = shift;
	my $root = $this->{root};
	my $kiwi = $this->{kiwi};
	my $data;
	my $code;
	#==========================================
	# check for rpm binary
	#------------------------------------------
	if (! -x "/bin/rpm") {
		# operates on rpm only
		return $this;
	}
	#==========================================
	# check build key and gpg
	#------------------------------------------	
	$kiwi -> info ("Importing build keys...");
	if (! -x "/usr/lib/rpm/gnupg/dumpsigs") {
		$kiwi -> skipped ();
		$kiwi -> warning ("Can't find dumpsigs on host system");
		$kiwi -> skipped ();
		return $this;
	}
	if (! -f "/usr/lib/rpm/gnupg/pubring.gpg") {
		$kiwi -> skipped ();
		$kiwi -> warning ("Can't find build keys on host system");
		$kiwi -> skipped ();
		return $this;
	}
	my $dump = "/usr/lib/rpm/gnupg/dumpsigs";
	my $sigs = "$root/rpm-sigs";
	$data = qxx ("mkdir -p $sigs && cd $sigs && $dump 2>&1");
	$code = $? >> 8;
	if ($code != 0) {
		$kiwi -> skipped ();
		$kiwi -> error  ("Can't dump pubkeys: $data");
		$kiwi -> failed ();
		qxx ("rm -rf $sigs");
		return $this;
	}
	$data.= qxx ("rpm -r $root --import $sigs/gpg-pubke* 2>&1");
	$code = $? >> 8;
	if ($code != 0) {
		$kiwi -> skipped ();
		$kiwi -> error  ("Can't import pubkeys: $data");
		$kiwi -> failed ();
		qxx ("rm -rf $sigs");
		return $this;
	}
	$kiwi -> done();
	qxx ("rm -rf $sigs");
	return $this;
}

#==========================================
# checkExclusiveLock
#------------------------------------------
sub checkExclusiveLock {
	# ...
	# During very first chroot build phase the package manager
	# requires an exclusive lock. Another kiwi process at that stage
	# will fail so we are waiting until the lock is done
	# ---
	my $this = shift;
	my $lock = $this->{lock};
	my $kiwi = $this->{kiwi};
	if (-f $lock) {
		$kiwi -> info ("Waiting for package lock to disappear...")
	} else {
		return $this;
	}
	while (-f $lock) {
		sleep (5);
	}
	$kiwi -> done();
	return $this;
}

#==========================================
# setLock
#------------------------------------------
sub setLock {
	my $this = shift;
	my $lock = $this->{lock};
	my $kiwi = $this->{kiwi};
	$kiwi -> loginfo ("Set package manager lock\n");
	qxx (" touch $lock ");
}

#==========================================
# freeLock
#------------------------------------------
sub freeLock {
	my $this = shift;
	my $lock = $this->{lock};
	my $kiwi = $this->{kiwi};
	$kiwi -> loginfo ("Release package manager lock\n");
	qxx (" rm -f $lock ");
}

#==========================================
# cleanChild
#------------------------------------------
sub cleanChild {
	my $this = shift;
	$this -> freeLock();
	if (defined $this->{child}) {
		kill 15,$this->{child};
	}
	return $this;
}

#==========================================
# removeCacheDir
#------------------------------------------
sub removeCacheDir {
	my $this    = shift;
	my $dataDir = $this->{dataDir};
	my $kiwi    = $this->{kiwi};
	my $config  = dirname ($dataDir);
	$this -> cleanChild();
	$kiwi -> loginfo ("Removing cache directory: $dataDir\n");
	qxx ("rm -rf $dataDir");
	qxx ("rm -rf $config/config");
	return $this;
}

#==========================================
# rpmLibs
#------------------------------------------
sub rpmLibs {
	# ...
	# provide required libraries in order to make
	# rpm work correctly.
	# ---
	my $this   = shift;
	my $clean  = shift;
	my $kiwi   = $this->{kiwi};
	my $root   = $this->{root};
	my $result = $this->{baselibs};
	my @kchroot= @{$this->{kchroot}};
	my @result;
	#==========================================
	# cleanup baselibs
	#------------------------------------------
	if ($clean) {
		if (! $result) {
			# no baselibs stored/copied...
			return $this;
		}
		qxx ("@kchroot rpm --rebuilddb 2>&1");
		@result = @{$result};
		my %dirlist = ();
		foreach my $l (@result) {
			my $dir = dirname ($l); $dirlist{$dir} = $dir;
			qxx ("@kchroot rpm -qf /$l &>/dev/null");
			my $code = $? >> 8;
			if ($code != 0) {
				$kiwi -> loginfo ("Cleaning baselib: $l\n");
				qxx ("rm -f $root/$l 2>&1");
			} elsif (-f "$root/$l.rpmnew") {
				$kiwi -> loginfo ("Restore rpmnew basefile: $l\n");
				qxx ("mv $root/$l.rpmnew $root/$l");
			}
		}
		foreach my $dir (keys %dirlist) {
			qxx ("rmdir $dir 2>&1");
		}
		qxx ("@kchroot ldconfig 2>&1");
		return $this;
	}
	#==========================================
	# setup baselibs
	#------------------------------------------
	my @libs = (
		'/lib/libnsl*',
		'/lib/libnss_compat*',
		'/lib/libnss_files*',
		'/lib64/libnsl*',
		'/lib64/libnss_compat*',
		'/lib64/libnss_files*'
	);
	foreach my $item (@libs) {
	foreach my $l (glob ($item)) {
		if (($l) && (-f $l)) {
			$l =~ s/^\///;
			push @result,$l;
		}
	}
	}
	if (! @result) {
		return undef;
	}
	foreach my $l (@result) {
		my $dir = dirname ($l);
		qxx ("mkdir -p $root/$dir && cp /$l $root/$l 2>&1");
	}
	$this -> {baselibs} = \@result;
	return $this;
}

#==========================================
# createYumConfig
#------------------------------------------
sub createYumConfig {
	my $this   = shift;
	my $root   = $this->{root};
	my $meta   = $this->{dataDir};
	my $config = $meta."/yum.conf";
	qxx ("echo '[main]' > $config");
	qxx ("echo 'cachedir=$meta' >> $config");
	qxx ("echo 'reposdir=$meta' >> $config");
	qxx ("echo 'keepcache=0' >> $config");
	qxx ("echo 'debuglevel=2' >> $config");
	qxx ("echo 'pkgpolicy=newest' >> $config");
	qxx ("echo 'tolerant=1' >> $config");
	qxx ("echo 'exactarch=1' >> $config");
	qxx ("echo 'obsoletes=1' >> $config");
	qxx ("echo 'plugins=1' >> $config");
	qxx ("echo 'metadata_expire=1800' >> $config");
	return $config;
}

1;
