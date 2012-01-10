#================
# FILE          : KIWISatSolver.pm
#----------------
# PROJECT       : OpenSUSE Build-Service
# COPYRIGHT     : (c) 2006 SUSE LINUX Products GmbH, Germany
#               :
# AUTHOR        : Marcus Schaefer <ms@suse.de>
#               :
# BELONGS TO    : Operating System images
#               :
# DESCRIPTION   : This module is used to integrate the sat solver
#               : for suse pattern and package solving tasks.
#               : it is used for package managers which doesn't know
#               : about patterns and also for the kiwi info module
#               :
# STATUS        : Development
#----------------
package KIWISatSolver;
#==========================================
# Modules
#------------------------------------------
use strict;
use Carp qw (cluck);
use KIWILog;
use KIWIQX;

#==========================================
# Plugins
#------------------------------------------
BEGIN {
	$KIWISatSolver::haveSaT = 1;
	eval {
		require KIWI::SaT;
		KIWI::SaT -> import;
	};
	if ($@) {
		$KIWISatSolver::haveSaT = 0;
	}
	if (! $KIWISatSolver::haveSaT) {
		package KIWI::SaT;
	}
}

#==========================================
# Constructor
#------------------------------------------
sub new {
	# ...
	# Construct a new KIWISatSolver object if satsolver is present.
	# The solver object is used to queue product, pattern, and package solve
	# requests which gets solved by the contents of a sat solvable
	# which is either created by the repository metadata contents
	# or used directly from the repository if it is provided
	# ---
	#==========================================
	# Object setup
	#------------------------------------------
	my $this  = {};
	my $class = shift;
	bless  $this,$class;
	#==========================================
	# Module Parameters
	#------------------------------------------
	my $kiwi    = shift;
	my $pref    = shift;
	my $urlref  = shift;
	my $solvep  = shift;
	my $repo    = shift;
	my $pool    = shift;
	my $quiet   = shift;
	my $ptype   = shift;
	#==========================================
	# Constructor setup
	#------------------------------------------
	my $solver;    # sat solver object
	my $queue;     # sat job queue
	my @solved;    # solve result
	my @jobFailed; # failed jobs
	if (! defined $kiwi) {
		$kiwi = new KIWILog("tiny");
	}
	if ((! defined $repo) || (! defined $pool)) {
		if (! defined $quiet) {
			$kiwi -> info ("Setting up SaT solver [legacy]...\n");
		}
	}
	if (! $KIWISatSolver::haveSaT) {
		$kiwi -> error ("--> No SaT plugin installed");
		$kiwi -> failed ();
		return undef;
	}
	if (! defined $pref) {
		$kiwi -> error ("--> Invalid package/pattern/product reference");
		$kiwi -> failed ();
		return undef;
	}
	if (! defined $urlref) {
		$kiwi -> error ("--> Invalid repository URL reference");
		$kiwi -> failed ();
		return undef;
	}
	#==========================================
	# Create and cache sat solvable
	#------------------------------------------
	if ((! defined $repo) || (! defined $pool)) {
		my $solvable = KIWIXML::getInstSourceSatSolvable ($kiwi,$urlref);
		if (! defined $solvable) {
			return undef;
		}
		#==========================================
		# Create SaT repository and job queue
		#------------------------------------------
		$pool = new KIWI::SaT::_Pool;
		foreach my $solv (keys %{$solvable}) {
			my $FD;
			if (! open ($FD, '<' ,$solv)) {
				$kiwi -> error  ("--> Couldn't open solvable: $solv");
				$kiwi -> failed ();
				return;
			}
			$repo = $pool -> createRepo(
				$solvable->{$solv}
			);
			$repo -> addSolvable (*FD);
			close $FD;
		}
		#==========================================
		# merge all solvables into one
		#------------------------------------------
		my $merged= "/var/cache/kiwi/satsolver/merged.solv";
		my @files = keys %{$solvable};
		if (@files > 1) {
			qxx ("mergesolv @files > $merged");
		} else {
			qxx ("cp @files $merged 2>&1");
		}
		my $code = $? >> 8;
		if ($code != 0) {
			$kiwi -> error  ("--> Couldn't merge/copy solv files");
			$kiwi -> failed ();
			return;
		}
		$this->{solfile} = $merged;
	}
	$solver = new KIWI::SaT::Solver ($pool);
	$pool -> initializeLookupTable();
	$queue = new KIWI::SaT::Queue;
	foreach my $p (@{$pref}) {
		my @names = $p;
		if (! defined $solvep) {
			push (@names, "pattern:".$p);
			push (@names, "patterns-openSUSE-".$p);
		}
		my $id   = 0;
		my $item = "";
		foreach my $name (@names) {
			$id = $pool -> selectSolvable ($repo,$solver,$name);
			$item = $name;
			next if ! $id;
			$queue -> queuePush ( $KIWI::SaT::SOLVER_INSTALL_SOLVABLE );
			$queue -> queuePush ( $id );
			last;
		}
		if (! $id) {
			if (! defined $quiet) {
				$kiwi -> warning ("--> Failed to queue job: $item");
				$kiwi -> skipped ();
			}
			push @jobFailed, $item;
		}
	}
	#==========================================
	# Store object data
	#------------------------------------------
	$this->{kiwi}    = $kiwi;
	$this->{queue}   = $queue;
	$this->{solver}  = $solver;
	$this->{failed}  = \@jobFailed;
	#==========================================
	# Solve the job(s)
	#------------------------------------------
	$solver -> solve ($queue);
	if ($this -> getProblemsCount()) {
		my $solution = $this -> getSolutions();
		if (! defined $quiet) {
			$kiwi -> warning ("--> Solver Problems:\n$solution");
		}
		$this->{problem} = "$solution";
	}
	my $size = $solver -> getInstallSizeKBytes();
	my $list = $solver -> getInstallList ($pool);
	my @plist= ();
	my %slist= ();
	if ($list) {
		foreach my $package (keys %{$list}) {
			push (@plist,$package);
			$slist{$package} = $list->{$package};
		}
		foreach my $name (@plist) {
			if ($name =~ /^(pattern|product):(.*)/) {
				my $type = $1;
				my $text = $2;
				if (! defined $quiet) {
					$kiwi -> info ("Including $type $text");
					$kiwi -> done ();
				}
			} else {
				push (@solved,$name);
			}
		}
	}
	#==========================================
	# Store object data
	#------------------------------------------
	$this->{size}    = $size;
	$this->{urllist} = $urlref;
	$this->{plist}   = $pref;
	$this->{repo}    = $repo;
	$this->{pool}    = $pool;
	$this->{result}  = \@solved;
	$this->{meta}    = \%slist;
	return $this;
}

#==========================================
# getProblemInfo
#------------------------------------------
sub getProblemInfo {
	# /.../
	# return problem solution text
	# ----
	my $this = shift;
	return $this->{problem};
}

#==========================================
# getFailedJobs
#------------------------------------------
sub getFailedJobs {
	# /.../
	# return package names of failed jobs
	# ----
	my $this = shift;
	return $this->{failed};
}

#==========================================
# getSolfile
#------------------------------------------
sub getSolfile {
	# /.../
	# return satsolver index file created or used
	# by an object of this class
	# ----
	my $this = shift;
	return $this->{solfile};
}

#==========================================
# getRepo
#------------------------------------------
sub getRepo {
	# /.../
	# return satsolver repo object
	# ----
	my $this = shift;
	return $this->{repo};
}

#==========================================
# getPool
#------------------------------------------
sub getPool {
	# /.../
	# return satsolver pool object
	# ----
	my $this = shift;
	return $this->{pool};
}

#==========================================
# getProblemsCount
#------------------------------------------
sub getProblemsCount {
	my $this   = shift;
	my $solver = $this->{solver};
	return $solver->getProblemsCount();
}

#==========================================
# getSolutions
#------------------------------------------
sub getSolutions {
	my $this   = shift;
	my $kiwi   = $this->{kiwi};
	my $solver = $this->{solver};
	my $queue  = $this->{queue};
	my $oldout;
	if (! $solver->getProblemsCount()) {
		return undef;
	}
	my $solution = $solver->getSolutions ($queue);
	local $/;
	if (! open (FD, "<$solution")) {
		$kiwi -> error  ("Can't open $solution for reading: $!");
		$kiwi -> failed ();
		unlink $solution;
		return undef;
	}
	my $result = <FD>; close FD;
	unlink $solution;
	return $result;
}

#==========================================
# getInstallSizeKBytes
#------------------------------------------
sub getInstallSizeKBytes {
	# /.../
	# return install size in kB of the solved
	# package list
	# ----
	my $this = shift;
	return $this->{size};
}

#==========================================
# getMetaData
#------------------------------------------
sub getMetaData {
	# /.../
	# return meta data hash, containing the install
	# size per package
	# ----
	my $this = shift;
	return %{$this->{meta}};
}

#==========================================
# getPackages
#------------------------------------------
sub getPackages {
	# /.../
	# return solved list
	# ----
	my $this   = shift;
	my $result = $this->{result};
	my @result = ();
	if (defined $result) {
		return @{$result};
	}
	return @result;
}

#==========================================
# Destructor
#------------------------------------------
sub DESTROY {
	my $this = shift;
	unlink $this->{solfile};
	return $this;
}

1;
