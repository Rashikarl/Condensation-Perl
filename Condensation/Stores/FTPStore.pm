# A Condensation store on a remote FTP folder.
# INCLUDE FTPStore/Connection.pm
use Digest::SHA;
use parent 'CDS::Store';

sub forUrl($class, $url // return) {
	return $class->new($1, '/') if $url =~ /^ftp:\/\/([^\/]*)$/;
	return $class->new($1, $2) if $url =~ /^ftp:\/\/([^\/]*)(\/.*)$/;
	return;
}

sub new($class, $endPoint, $folder) {
	return bless {endPoint => $endPoint, folder => $folder};
}

sub id($o) { 'ftp://'.$o:endPoint.$o:folder }
sub endPoint;
sub folder;

sub connection($o) {
	return $o:connection if exists $o:connection;
	$o:connection = CDS::FTPStore::Connection->forEndpoint($o:endPoint);
	return $o:connection;
}

sub get($o, $hash, $keyPair) {
	my $connection = $o->connection // return undef, 'No connection.';

	my $hashHex = $hash->hex;
	my $file = $o:folder.'/objects/'.substr($hashHex, 0, 2).'/'.substr($hashHex, 2);
	return CDS::Object->fromBytes($connection->readFileBytes($file));
}

sub put($o, $hash, $object, $keyPair) {
	my $connection = $o->connection // return 'No connection.';

	# Check if that object exists already
	my $hashHex = $hash->hex;
	my $folder = $o:folder.'/objects/'.substr($hashHex, 0, 2);
	my $file = $folder.'/'.substr($hashHex, 2);
	$connection->touch($file) && return;

	# Write the file and move it to the right place
	$connection->mkdir($folder);
	my $temporaryFile = $connection->writeTemporaryFile($folder, $object->bytes) || return 'Failed to write object.';
	$connection->rename($temporaryFile, $file) || return 'Failed to rename object.';
	return;
}

sub book($o, $hash, $keyPair) {
	my $connection = $o->connection // return undef, 'No connection.';

	# Check if that object exists
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
		push @$hashes, CDS::Hash->fromHex(substr($file, 0, 64)) || next;
	}

	return $hashes;
}

sub add($o, $accountHash, $boxLabel, $hash, $keyPair) {
	my $connection = $o->connection // return 'No connection.';

	next if ! CDS->isValidBoxLabel($boxLabel);
	my $accountFolder = $o:folder.'/accounts/'.$accountHash->hex;
	$connection->mkdir($accountFolder);
	my $boxFolder = $accountFolder.'/'.$boxLabel;
	$connection->mkdir($boxFolder);

	my $file = $connection->writeTemporaryFile($boxFolder) || return 'Failed to write file.';
	$connection->rename($file, $boxFolder.'/'.$hash->hex) || return 'Failed to rename file.';
	return;
}

sub remove($o, $accountHash, $boxLabel, $hash, $keyPair) {
	my $connection = $o->connection // return 'No connection.';

	next if ! CDS->isValidBoxLabel($boxLabel);
	my $accountFolder = $o:folder.'/accounts/'.$accountHash->hex;
	my $boxFolder = $accountFolder.'/'.$boxLabel;
	$connection->delete($boxFolder.'/'.$hash->hex);
	return;
}

sub modify($o, $modifications, $keyPair) {
	return $modifications->executeIndividually($o, $keyPair);
}

# System administration functions

sub accounts($o) {
	return	grep { defined $_ }
			map { CDS::Hash->fromHex($_) }
			$o->connection->files($o:folder.'/accounts');
}

sub addAccount($o, $accountHash) {
	my $connection = $o->connection;
	my $accountFolder = $o:folder.'/accounts/'.$accountHash->hex;
	$connection->mkdir($accountFolder);
	return $connection->exists($accountFolder);
}

sub removeAccount($o, $accountHash) {
	my $accountFolder = $o:folder.'/accounts/'.$accountHash->hex;
	my $connection = $o->connection;
	my $trashFolder = $o:folder.'/accounts/.deleted-'.CDS->randomHex(16);
	$connection->rename($accountFolder, $trashFolder);
	$connection->unlink($trashFolder);
	return ! $connection->exists($accountFolder);
}
