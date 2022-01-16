# A Condensation store on a remote SFTP folder.
# INCLUDE SFTPStore/Connection.pm
# INCLUDE SFTPStore/PosixPermissions.pm
use Digest::SHA;
use parent 'CDS::Store';

sub forUrl($class, $url // return) {
	$url =~ /^sftp:\/\/([^\/]*)(\/.*)$/ || return;
	return $class->new($1, $2);
}

sub new($class, $endPoint, $folder) {
	return bless {endPoint => $endPoint, folder => $folder};
}

sub id($o) { 'sftp://'.$o:endPoint.$o:folder }
sub endPoint;
sub folder;

sub connection($o) {
	return $o:connection if exists $o:connection;
	$o:connection = CDS::SFTPStore::Connection->forEndpoint($o:endPoint);
	return $o:connection;
}

sub permissions($o) {
	return $o:permissions if exists $o:permissions;
	$o:permissions = CDS::SFTPStore::PosixPermissions->forStat($o->connection->stat($o:folder.'/accounts'));
	return $o:permissions;
}

sub get($o, $hash, $keyPair) {
	my $connection = $o->connection // return undef, 'No connection.';
	my $hashHex = $hash->hex;
	my $file = $o:folder.'/objects/'.substr($hashHex, 0, 2).'/'.substr($hashHex, 2);
	return CDS::Object->fromBytes($connection->readFileBytes($file));
}

sub put($o, $hash, $object, $keyPair) {
	my $connection = $o->connection // return 'No connection.';
	my $permissions = $o->permissions;
	my $uid = $permissions->uid;
	my $gid = $permissions->gid;

	# Book the object if it exists
	my $hashHex = $hash->hex;
	my $folder = $o:folder.'/objects/'.substr($hashHex, 0, 2);
	my $file = $folder.'/'.substr($hashHex, 2);
	$connection->touch($file) && return;

	# Write the file and move it to the right place
	$connection->mkdir($folder, $uid, $gid, $permissions->objectFolderMode);
	my $temporaryFile = $connection->writeTemporaryFile($folder, $uid, $gid, $permissions->objectFileMode, $object->bytes) || return 'Failed to write object.';
	$connection->rename($temporaryFile, $file) || return 'Failed to rename object.';
	return;
}

sub book($o, $hash, $keyPair) {
	my $connection = $o->connection // return undef, 'No connection.';
	my $hashHex = $hash->hex;
	my $folder = $o:folder.'/objects/'.substr($hashHex, 0, 2);
	my $file = $folder.'/'.substr($hashHex, 2);
	$connection->touch($file) && return 1;
	return;
}

sub list($o, $accountHash, $boxLabel, $timeout, $keyPair) {
	return undef, 'Box not found.' if ! CDS->isValidBoxLabel($boxLabel);

	# Prepare
	my $connection = $o->connection // return undef, 'No connection.';
	my $boxFolder = $o:folder.'/accounts/'.$accountHash->hex.'/'.$boxLabel;

	# List
	my $hashes = [];
	for my $file ($connection->files($boxFolder)) {
		push @$hashes, CDS::Hash->fromHex(substr($file:name, 0, 64)) || next;
	}

	return $hashes;
}

sub add($o, $accountHash, $boxLabel, $hash, $keyPair) {
	my $connection = $o->connection // return 'No connection.';
	my $permissions = $o->permissions;
	my $uid = $permissions->uid;
	my $gid = $permissions->gid;

	next if ! CDS->isValidBoxLabel($boxLabel);
	my $accountFolder = $o:folder.'/accounts/'.$accountHash->hex;
	$connection->mkdir($accountFolder, $uid, $gid, $permissions->accountFolderMode);
	my $boxFolder = $accountFolder.'/'.$boxLabel;
	$connection->mkdir($boxFolder, $uid, $gid, $permissions->boxFolderMode($boxLabel));
	my $boxFileMode = $permissions->boxFileMode($boxLabel);

	my $file = $connection->writeTemporaryFile($boxFolder, $uid, $gid, $boxFileMode) || return 'Failed to write file.';
	$connection->rename($file, $boxFolder.'/'.$hash->hex) || return 'Failed to rename file.';
	return;
}

sub remove($o, $accountHash, $boxLabel, $hash, $keyPair) {
	my $connection = $o->connection // return 'No connection.';
	my $permissions = $o->permissions;
	my $uid = $permissions->uid;
	my $gid = $permissions->gid;

	next if ! CDS->isValidBoxLabel($boxLabel);
	my $accountFolder = $o:folder.'/accounts/'.$accountHash->hex;
	my $boxFolder = $accountFolder.'/'.$boxLabel;
	$connection->unlink($boxFolder.'/'.$hash->hex);
	return;
}

sub modify($o, $modifications, $keyPair) {
	return $modifications->executeIndividually($o, $keyPair);
}

# System administration functions

sub accounts($o) {
	return	grep { defined $_ }
			map { CDS::Hash->fromHex($_->{name}) }
			$o->connection->files($o:folder.'/accounts');
}

sub addAccount($o, $accountHash) {
	my $connection = $o->connection;
	my $permissions = $o->permissions;
	my $accountFolder = $o:folder.'/accounts/'.$accountHash->hex;
	$connection->mkdir($accountFolder, $permissions->uid, $permissions->gid, $permissions->accountFolder);
	return $connection->exists($accountFolder);
}

sub removeAccount($o, $accountHash) {
	my $connection = $o->connection;
	my $accountFolder = $o:folder.'/accounts/'.$accountHash->hex;
	my $trashFolder = $o:folder.'/accounts/.deleted-'.CDS->randomHex(16);
	$connection->rename($accountFolder, $trashFolder);
	$connection->unlink($trashFolder);
	return ! $connection->exists($accountFolder);
}
