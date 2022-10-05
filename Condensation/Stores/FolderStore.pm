# A Condensation store on a local folder.
# INCLUDE FolderStore/PosixPermissions.pm
# INCLUDE FolderStore/Watcher.pm
use Digest::SHA;
use parent 'CDS::Store';

sub forUrl($class, $url) {
	return if substr($url, 0, 8) ne 'file:///';
	return $class->new(substr($url, 7));
}

sub new($class, $folder) {
	return bless {
		folder => $folder,
		permissions => CDS::FolderStore::PosixPermissions->forFolder($folder.'/accounts'),
		};
}

sub id($o) { 'file://'.$o:folder }
sub folder;

sub permissions;
sub setPermissions($o, $permissions) { $o:permissions = $permissions; }

sub get($o, $hash, $keyPair) {
	my $hashHex = $hash->hex;
	my $file = $o:folder.'/objects/'.substr($hashHex, 0, 2).'/'.substr($hashHex, 2);
	return CDS::Object->fromBytes(CDS->readBytesFromFile($file));
}

sub book($o, $hash, $keyPair) {
	# Book the object if it exists
	my $hashHex = $hash->hex;
	my $folder = $o:folder.'/objects/'.substr($hashHex, 0, 2);
	my $file = $folder.'/'.substr($hashHex, 2);
	return 1 if -e $file && utime(undef, undef, $file);
	return;
}

sub put($o, $hash, $object, $keyPair) {
	# Book the object if it exists
	my $hashHex = $hash->hex;
	my $folder = $o:folder.'/objects/'.substr($hashHex, 0, 2);
	my $file = $folder.'/'.substr($hashHex, 2);
	return if -e $file && utime(undef, undef, $file);

	# Write the file, set the permissions, and move it to the right place
	my $permissions = $o:permissions;
	$permissions->mkdir($folder, $permissions->objectFolderMode);
	my $temporaryFile = $permissions->writeTemporaryFile($folder, $permissions->objectFileMode, $object->bytes) // return 'Failed to write object';
	rename($temporaryFile, $file) || return 'Failed to rename object.';
	return;
}

sub list($o, $accountHash, $boxLabel, $timeout, $keyPair) {
	return undef, 'Invalid box label.' if ! CDS->isValidBoxLabel($boxLabel);

	# Prepare
	my $boxFolder = $o:folder.'/accounts/'.$accountHash->hex.'/'.$boxLabel;

	# List
	return $o->listFolder($boxFolder) if ! $timeout;

	# Watch
	my $hashes;
	my $watcher = CDS::FolderStore::Watcher->new($boxFolder);
	my $watchUntil = CDS->now + $timeout;
	while (1) {
		# List
		$hashes = $o->listFolder($boxFolder);
		last if scalar @$hashes;

		# Wait
		$watcher->wait($watchUntil - CDS->now, $watchUntil) // last;
	}

	$watcher->done;
	return $hashes;
}

sub listFolder($o, $boxFolder) {	# private
	my $hashes = [];
	for my $file (CDS->listFolder($boxFolder)) {
		push @$hashes, CDS::Hash->fromHex($file) // next;
	}

	return $hashes;
}

sub add($o, $accountHash, $boxLabel, $hash, $keyPair) {
	my $permissions = $o:permissions;

	return if ! CDS->isValidBoxLabel($boxLabel);
	my $accountFolder = $o:folder.'/accounts/'.$accountHash->hex;
	$permissions->mkdir($accountFolder, $permissions->accountFolderMode);
	my $boxFolder = $accountFolder.'/'.$boxLabel;
	$permissions->mkdir($boxFolder, $permissions->boxFolderMode($boxLabel));
	my $boxFileMode = $permissions->boxFileMode($boxLabel);

	my $temporaryFile = $permissions->writeTemporaryFile($boxFolder, $boxFileMode, '') // return 'Failed to write file.';
	rename($temporaryFile, $boxFolder.'/'.$hash->hex) || return 'Failed to rename file.';
	return;
}

sub remove($o, $accountHash, $boxLabel, $hash, $keyPair) {
	return if ! CDS->isValidBoxLabel($boxLabel);
	my $accountFolder = $o:folder.'/accounts/'.$accountHash->hex;
	my $boxFolder = $accountFolder.'/'.$boxLabel;
	return if ! -d $boxFolder;
	unlink $boxFolder.'/'.$hash->hex;
	return;
}

sub modify($o, $modifications, $keyPair) {
	return $modifications->executeIndividually($o, $keyPair);
}

# Store administration functions

sub exists($o) {
	return -d $o:folder.'/accounts' && -d $o:folder.'/objects';
}

# Creates the store if it does not exist. The store folder itself must exist.
sub createIfNecessary($o) {
	my $accountsFolder = $o:folder.'/accounts';
	my $objectsFolder = $o:folder.'/objects';
	$o:permissions->mkdir($accountsFolder, $o:permissions->baseFolderMode);
	$o:permissions->mkdir($objectsFolder, $o:permissions->baseFolderMode);
	return -d $accountsFolder && -d $objectsFolder;
}

# Lists accounts. This is a non-standard extension.
sub accounts($o) {
	return	grep { defined $_ }
			map { CDS::Hash->fromHex($_) }
			CDS->listFolder($o:folder.'/accounts');
}

# Adds an account. This is a non-standard extension.
sub addAccount($o, $accountHash) {
	my $accountFolder = $o:folder.'/accounts/'.$accountHash->hex;
	$o:permissions->mkdir($accountFolder, $o:permissions->accountFolderMode);
	return -d $accountFolder;
}

# Removes an account. This is a non-standard extension.
sub removeAccount($o, $accountHash) {
	my $accountFolder = $o:folder.'/accounts/'.$accountHash->hex;
	my $trashFolder = $o:folder.'/accounts/.deleted-'.CDS->randomHex(16);
	rename $accountFolder, $trashFolder;
	system('rm', '-rf', $trashFolder);
	return ! -d $accountFolder;
}

# Checks (and optionally fixes) the POSIX permissions of all files and folders. This is a non-standard extension.
sub checkPermissions($o, $logger) {
	my $permissions = $o:permissions;

	# Check the accounts folder
	my $accountsFolder = $o:folder.'/accounts';
	$permissions->checkPermissions($accountsFolder, $permissions->baseFolderMode, $logger) || return;

	# Check the account folders
	for my $account (sort { $a cmp $b } CDS->listFolder($accountsFolder)) {
		next if $account !~ /^[0-9a-f]{64}$/;
		my $accountFolder = $accountsFolder.'/'.$account;
		$permissions->checkPermissions($accountFolder, $permissions->accountFolderMode, $logger) || return;

		# Check the box folders
		for my $boxLabel (sort { $a cmp $b } CDS->listFolder($accountFolder)) {
			next if $boxLabel =~ /^\./;
			my $boxFolder = $accountFolder.'/'.$boxLabel;
			$permissions->checkPermissions($boxFolder, $permissions->boxFolderMode($boxLabel), $logger) || return;

			# Check each file
			my $filePermissions = $permissions->boxFileMode($boxLabel);
			for my $file (sort { $a cmp $b } CDS->listFolder($boxFolder)) {
				next if $file !~ /^[0-9a-f]{64}/;
				$permissions->checkPermissions($boxFolder.'/'.$file, $filePermissions, $logger) || return;
			}
		}
	}

	# Check the objects folder
	my $objectsFolder = $o:folder.'/objects';
	my $fileMode = $permissions->objectFileMode;
	my $folderMode = $permissions->objectFolderMode;
	$permissions->checkPermissions($objectsFolder, $folderMode, $logger) || return;

	# Check the 256 sub folders
	for my $sub (sort { $a cmp $b } CDS->listFolder($objectsFolder)) {
		next if $sub !~ /^[0-9a-f][0-9a-f]$/;
		my $subFolder = $objectsFolder.'/'.$sub;
		$permissions->checkPermissions($subFolder, $folderMode, $logger) || return;

		for my $file (sort { $a cmp $b } CDS->listFolder($subFolder)) {
			next if $file !~ /^[0-9a-f]{62}/;
			$permissions->checkPermissions($subFolder.'/'.$file, $fileMode, $logger) || return;
		}
	}

	return 1;
}
