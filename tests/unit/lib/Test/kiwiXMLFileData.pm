#================
# FILE          : kiwiXMLFileData.pm
#----------------
# PROJECT       : OpenSUSE Build-Service
# COPYRIGHT     : (c) 2012 SUSE LINUX Products GmbH, Germany
#               :
# AUTHOR        : Robert Schweikert <rjschwei@suse.com>
#               :
# BELONGS TO    : Operating System images
#               :
# DESCRIPTION   : Unit test implementation for the KIWIFileData module.
#               :
# STATUS        : Development
#----------------
package Test::kiwiXMLFileData;

use strict;
use warnings;

use Common::ktLog;
use Common::ktTestCase;
use base qw /Common::ktTestCase/;

use KIWIXMLFileData;

#==========================================
# Constructor
#------------------------------------------
sub new {
	# ...
	# Construct new test case
	# ---
	my $this = shift -> SUPER::new(@_);
	$this -> {kiwi} = Common::ktLog -> new();

	return $this;
}

#==========================================
# test_ctor_argsIncomplete
#------------------------------------------
sub test_ctor_argsIncomplete {
	# ...
	# Test the FileData constructor with insufficient args
	# ---
	my $this = shift;
	my $kiwi = $this -> {kiwi};
	my $fileDataObj = KIWIXMLFileData -> new($kiwi);
	my $msg = $kiwi -> getMessage();
	$this -> assert_str_equals('missingName', $fileDataObj);
	my $expected = 'missing second argument for FileData ctor';
	$this -> assert_str_equals($expected, $msg);
	my $msgT = $kiwi -> getMessageType();
	$this -> assert_str_equals('error', $msgT);
	my $state = $kiwi -> getState();
	$this -> assert_str_equals('failed', $state);
	# Test this condition last to get potential error messages
	$this -> assert_not_null($fileDataObj);
	return;
}

#==========================================
# test_ctor_unsuportedArch
#------------------------------------------
sub test_ctor_unsuportedArch {
	# ...
	# Test the FileData constructor with an unsupported architecture
	# ---
	my $this = shift;
	my $kiwi = $this -> {kiwi};
	my $fileDataObj = KIWIXMLFileData -> new($kiwi, 'soundcore.ko', 'tegra');
	my $expectedMsg = "Specified arch 'tegra' is not supported";
	my $msg = $kiwi -> getMessage();
	$this -> assert_str_equals($expectedMsg, $msg);
	my $msgT = $kiwi -> getMessageType();
	$this -> assert_str_equals('error', $msgT);
	my $state = $kiwi -> getState();
	$this -> assert_str_equals('failed', $state);
	# Test this condition last to get potential error messages
	$this -> assert_null($fileDataObj);
	return;
}

#==========================================
# test_ctor_simple
#------------------------------------------
sub test_ctor_simple {
	# ...
	# Test proper construction with only the name argument
	# ---
	my $this = shift;
	my $kiwi = $this -> {kiwi};
	my $fileDataObj = KIWIXMLFileData -> new($kiwi, 'soundcore.ko');
	my $msg = $kiwi -> getMessage();
	$this -> assert_str_equals('No messages set', $msg);
	my $msgT = $kiwi -> getMessageType();
	$this -> assert_str_equals('none', $msgT);
	my $state = $kiwi -> getState();
	$this -> assert_str_equals('No state set', $state);
	# Test this condition last to get potential error messages
	$this -> assert_not_null($fileDataObj);
	return;
}

#==========================================
# test_ctor_withArch
#------------------------------------------
sub test_ctor_withArch {
	# ...
	# Test proper construction with only the name argument
	# ---
	my $this = shift;
	my $kiwi = $this -> {kiwi};
	my $fileDataObj = KIWIXMLFileData -> new($kiwi, 'soundcore.ko', 'ppc64');
	my $msg = $kiwi -> getMessage();
	$this -> assert_str_equals('No messages set', $msg);
	my $msgT = $kiwi -> getMessageType();
	$this -> assert_str_equals('none', $msgT);
	my $state = $kiwi -> getState();
	$this -> assert_str_equals('No state set', $state);
	# Test this condition last to get potential error messages
	$this -> assert_not_null($fileDataObj);
	return;
}

#==========================================
# test_getArch
#------------------------------------------
sub test_getArch {
	# ...
	# Verify that the proper architecture value is returned.
	# ---
	my $this = shift;
	my $kiwi = $this -> {kiwi};
	my $fileDataObj = KIWIXMLFileData -> new($kiwi, 'soundcore.ko', 'ix86');
	my $msg = $kiwi -> getMessage();
	$this -> assert_str_equals('No messages set', $msg);
	my $msgT = $kiwi -> getMessageType();
	$this -> assert_str_equals('none', $msgT);
	my $state = $kiwi -> getState();
	$this -> assert_str_equals('No state set', $state);
	my $value = $fileDataObj -> getArch();
	$this -> assert_str_equals('ix86', $value);
	$msg = $kiwi -> getMessage();
	$this -> assert_str_equals('No messages set', $msg);
	$msgT = $kiwi -> getMessageType();
	$this -> assert_str_equals('none', $msgT);
	$state = $kiwi -> getState();
	$this -> assert_str_equals('No state set', $state);
	# Test this condition last to get potential error messages
	$this -> assert_not_null($fileDataObj);
	return;
}

#==========================================
# test_getName
#------------------------------------------
sub test_getName {
	# ...
	# Verify that the proper name is returned.
	# ---
	my $this = shift;
	my $kiwi = $this -> {kiwi};
	my $fileDataObj = KIWIXMLFileData -> new($kiwi, 'soundcore.ko');
	my $msg = $kiwi -> getMessage();
	$this -> assert_str_equals('No messages set', $msg);
	my $msgT = $kiwi -> getMessageType();
	$this -> assert_str_equals('none', $msgT);
	my $state = $kiwi -> getState();
	$this -> assert_str_equals('No state set', $state);
	my $value = $fileDataObj -> getName();
	$this -> assert_str_equals('soundcore.ko', $value);
	$msg = $kiwi -> getMessage();
	$this -> assert_str_equals('No messages set', $msg);
	$msgT = $kiwi -> getMessageType();
	$this -> assert_str_equals('none', $msgT);
	$state = $kiwi -> getState();
	$this -> assert_str_equals('No state set', $state);
	# Test this condition last to get potential error messages
	$this -> assert_not_null($fileDataObj);
	return;
}

#==========================================
# test_setArch
#------------------------------------------
sub test_setArch {
	# ...
	# Verify that the proper architecture value is set and returned.
	# ---
	my $this = shift;
	my $kiwi = $this -> {kiwi};
	my $fileDataObj = KIWIXMLFileData -> new($kiwi, 'soundcore.ko');
	my $msg = $kiwi -> getMessage();
	$this -> assert_str_equals('No messages set', $msg);
	my $msgT = $kiwi -> getMessageType();
	$this -> assert_str_equals('none', $msgT);
	my $state = $kiwi -> getState();
	$this -> assert_str_equals('No state set', $state);
	my $value = $fileDataObj -> setArch('x86_64');
	$this -> assert_equals(1, $value);
	$msg = $kiwi -> getMessage();
	$this -> assert_str_equals('No messages set', $msg);
	$msgT = $kiwi -> getMessageType();
	$this -> assert_str_equals('none', $msgT);
	$state = $kiwi -> getState();
	$this -> assert_str_equals('No state set', $state);
	$value = $fileDataObj -> getArch();
	$this -> assert_str_equals('x86_64', $value);
	# Test this condition last to get potential error messages
	$this -> assert_not_null($fileDataObj);
	return;
}

#==========================================
# test_setArch_invalid
#------------------------------------------
sub test_setArch_invalid {
	# ...
	# Verify proper error condition handling for setArch().
	# ---
	my $this = shift;
	my $kiwi = $this -> {kiwi};
	my $fileDataObj = KIWIXMLFileData -> new($kiwi, 'soundcore.ko');
	my $msg = $kiwi -> getMessage();
	$this -> assert_str_equals('No messages set', $msg);
	my $msgT = $kiwi -> getMessageType();
	$this -> assert_str_equals('none', $msgT);
	my $state = $kiwi -> getState();
	$this -> assert_str_equals('No state set', $state);
	my $value = $fileDataObj -> setArch('tegra');
	my $expectedMsg = "Specified arch 'tegra' is not supported";
	$msg = $kiwi -> getMessage();
	$this -> assert_str_equals($expectedMsg, $msg);
	$msgT = $kiwi -> getMessageType();
	$this -> assert_str_equals('error', $msgT);
	$state = $kiwi -> getState();
	$this -> assert_str_equals('failed', $state);
	$this -> assert_null($value);
	$value = $fileDataObj -> getArch();
	$this -> assert_null($value);
	# Test this condition last to get potential error messages
	$this -> assert_not_null($fileDataObj);
	return;
}

1;