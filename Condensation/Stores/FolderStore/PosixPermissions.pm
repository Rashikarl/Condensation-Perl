# Handles POSIX permissions (user, group, and mode).
# INCLUDE PosixPermissions/Group.pm
# INCLUDE PosixPermissions/User.pm
# INCLUDE PosixPermissions/World.pm

# Returns the permissions set corresponding to the mode, uid, and gid of the base folder.
# If the permissions are ambiguous, the more restrictive set is chosen.
sub forFolder($class, $folder) {
	my @s = stat $folder;
	my $mode = $s[2] // 0;

	return
		($mode & 077) == 077 ? CDS::FolderStore::PosixPermissions::World->new :
		($mode & 070) == 070 ? CDS::FolderStore::PosixPermissions::Group->new($s[5]) :
			CDS::FolderStore::PosixPermissions::User->new($s[4]);
}

sub uid;
sub gid;

sub user($o) {
	my $uid = $o:uid // return;
	return getpwuid($uid) // $uid;
}

sub group($o) {
	my $gid = $o:gid // return;
	return getgrgid($gid) // $gid;
}

sub writeTemporaryFile($o, $folder, $mode) {
	# Write the file
	my $temporaryFile = $folder.'/.'.CDS->randomHex(16);
	open(my $fh, '>:bytes', $temporaryFile) || return;
	print $fh @_;
	close $fh;

	# Set the permissions
	chmod $mode, $temporaryFile;
	my $uid = $o->uid;
	my $gid = $o->gid;
	chown $uid // -1, $gid // -1, $temporaryFile if defined $uid && $uid != $< || defined $gid && $gid != $(;
	return $temporaryFile;
}

sub mkdir($o, $folder, $mode) {
	return if -d $folder;

	# Create the folder (note: mode is altered by umask)
	my $success = mkdir $folder, $mode;

	# Set the permissions
	chmod $mode, $folder;
	my $uid = $o->uid;
	my $gid = $o->gid;
	chown $uid // -1, $gid // -1, $folder if defined $uid && $uid != $< || defined $gid && $gid != $(;
	return $success;
}

# Check the permissions of a file or folder, and fix them if desired.
# A logger object is called for the different cases (access error, correct permissions, wrong permissions, error fixing permissions).
sub checkPermissions($o, $item, $expectedMode, $logger) {
	my $expectedUid = $o->uid;
	my $expectedGid = $o->gid;

	# Stat the item
	my @s = stat $item;
	return $logger->accessError($item) if ! scalar @s;
	my $mode = $s[2] & 07777;
	my $uid = $s[4];
	my $gid = $s[5];

	# Check
	my $wrongUid = defined $expectedUid && $uid != $expectedUid;
	my $wrongGid = defined $expectedGid && $gid != $expectedGid;
	my $wrongMode = $mode != $expectedMode;
	if ($wrongUid || $wrongGid || $wrongMode) {
		# Something is wrong
		$logger->wrong($item, $uid, $gid, $mode, $expectedUid, $expectedGid, $expectedMode) || return 1;

		# Fix uid and gid
		if ($wrongUid || $wrongGid) {
			my $count = chown $expectedUid // -1, $expectedGid // -1, $item;
			return $logger->setError($item) if $count < 1;
		}

		# Fix mode
		if ($wrongMode) {
			my $count = chmod $expectedMode, $item;
			return $logger->setError($item) if $count < 1;
		}
	} else {
		# Everything is OK
		$logger->correct($item, $mode, $uid, $gid);
	}

	return 1;
}
