# This is the Condensation Perl Module 0.27 (http-server) built on 2022-02-10.
# See https://condensation.io for information about the Condensation Data System.

use strict;
use warnings;
use 5.010000;

=pod

=head1 CDS - Condensation Data System

Condensation is a general-purpose distributed data system with conflict-free synchronization, and inherent end-to-end security.

This is the Perl implementation. It comes with a Perl module:

    use CDS;

and a command line tool:

    cds

More information is available on L<condensation.io|https://condensation.io>.

=cut

use Digest::SHA;
use Encode;
use HTTP::Date;
use HTTP::Headers;
use HTTP::Request;
use HTTP::Server::Simple;
use LWP::UserAgent;
use Time::Local;
use utf8;
package CDS;

our $VERSION = '0.27';
our $edition = 'http-server';
our $releaseDate = '2022-02-10';

sub now { time * 1000 }

sub SECOND { 1000 }
sub MINUTE { 60 * 1000 }
sub HOUR { 60 * 60 * 1000 }
sub DAY { 24 * 60 * 60 * 1000 }
sub WEEK { 7 * 24 * 60 * 60 * 1000 }
sub MONTH { 30 * 24 * 60 * 60 * 1000 }
sub YEAR { 365 * 24 * 60 * 60 * 1000 }

# File system utility functions.

sub readBytesFromFile {
	my $class = shift;
	my $filename = shift;

	open(my $fh, '<:bytes', $filename) || return;
	local $/;
	my $content = <$fh>;
	close $fh;
	return $content;
}

sub writeBytesToFile {
	my $class = shift;
	my $filename = shift;

	open(my $fh, '>:bytes', $filename) || return;
	print $fh @_;
	close $fh;
	return 1;
}

sub readTextFromFile {
	my $class = shift;
	my $filename = shift;

	open(my $fh, '<:utf8', $filename) || return;
	local $/;
	my $content = <$fh>;
	close $fh;
	return $content;
}

sub writeTextToFile {
	my $class = shift;
	my $filename = shift;

	open(my $fh, '>:utf8', $filename) || return;
	print $fh @_;
	close $fh;
	return 1;
}

sub listFolder {
	my $class = shift;
	my $folder = shift;

	opendir(my $dh, $folder) || return;
	my @files = readdir $dh;
	closedir $dh;
	return @files;
}

sub intermediateFolders {
	my $class = shift;
	my $path = shift;

	my @paths = ($path);
	while (1) {
		$path =~ /^(.+)\/(.*?)$/ || last;
		$path = $1;
		next if ! length $2;
		unshift @paths, $path;
	}
	return @paths;
}

# This is for debugging purposes only.
sub log {
	my $class = shift;

	print STDERR @_, "\n";
}

sub min {
	my $class = shift;

	my $min = shift;
	for my $number (@_) {
		$min = $min < $number ? $min : $number;
	}

	return $min;
}

sub max {
	my $class = shift;

	my $max = shift;
	for my $number (@_) {
		$max = $max > $number ? $max : $number;
	}

	return $max;
}

sub booleanCompare {
	my $class = shift;
	my $a = shift;
	my $b = shift;
	 $a && $b ? 0 : $a ? 1 : $b ? -1 : 0 }

# Utility functions for random sequences

srand(time);
our @hexDigits = ('0'..'9', 'a'..'f');

sub randomHex {
	my $class = shift;
	my $length = shift;

	return substr(unpack('H*', CDS::C::randomBytes(int(($length + 1) / 2))), 0, $length);
}

sub randomBytes {
	my $class = shift;
	my $length = shift;

	return CDS::C::randomBytes($length);
}

sub randomKey {
	my $class = shift;

	return CDS::C::randomBytes(32);
}

sub version { 'Condensation, Perl, '.$CDS::VERSION }

# Conversion of numbers and booleans to and from bytes.
# To convert text, use Encode::encode_utf8($text) and Encode::decode_utf8($bytes).
# To convert hex sequences, use pack('H*', $hex) and unpack('H*', $bytes).

sub bytesFromBoolean {
	my $class = shift;
	my $value = shift;
	 $value ? 'y' : '' }

sub bytesFromInteger {
	my $class = shift;
	my $value = shift;

	return '' if $value >= 0 && $value < 1;
	return pack 'c', $value if $value >= -0x80 && $value < 0x80;
	return pack 's>', $value if $value >= -0x8000 && $value < 0x8000;

	# This works up to 63 bits, plus 1 sign bit
	my $bytes = pack 'q>', $value;

	my $pos = 0;
	my $first = ord(substr($bytes, 0, 1));
	if ($value > 0) {
		# Perl internally uses an unsigned 64-bit integer if the value is positive
		return "\x7f\xff\xff\xff\xff\xff\xff\xff" if $first >= 128;
		while ($first == 0) {
			my $next = ord(substr($bytes, $pos + 1, 1));
			last if $next >= 128;
			$first = $next;
			$pos += 1;
		}
	} elsif ($first == 255) {
		while ($first == 255) {
			my $next = ord(substr($bytes, $pos + 1, 1));
			last if $next < 128;
			$first = $next;
			$pos += 1;
		}
	}

	return substr($bytes, $pos);
}

sub bytesFromUnsigned {
	my $class = shift;
	my $value = shift;

	return '' if $value < 1;
	return pack 'C', $value if $value < 0x100;
	return pack 'S>', $value if $value < 0x10000;

	# This works up to 64 bits
	my $bytes = pack 'Q>', $value;
	my $pos = 0;
	$pos += 1 while substr($bytes, $pos, 1) eq "\0";
	return substr($bytes, $pos);
}

sub bytesFromFloat32 {
	my $class = shift;
	my $value = shift;
	 pack('f', $value) }
sub bytesFromFloat64 {
	my $class = shift;
	my $value = shift;
	 pack('d', $value) }

sub booleanFromBytes {
	my $class = shift;
	my $bytes = shift;

	return length $bytes > 0;
}

sub integerFromBytes {
	my $class = shift;
	my $bytes = shift;

	return 0 if ! length $bytes;
	my $value = unpack('C', substr($bytes, 0, 1));
	$value -= 0x100 if $value & 0x80;
	for my $i (1 .. length($bytes) - 1) {
		$value *= 256;
		$value += unpack('C', substr($bytes, $i, 1));
	}
	return $value;
}

sub unsignedFromBytes {
	my $class = shift;
	my $bytes = shift;

	my $value = 0;
	for my $i (0 .. length($bytes) - 1) {
		$value *= 256;
		$value += unpack('C', substr($bytes, $i, 1));
	}
	return $value;
}

sub floatFromBytes {
	my $class = shift;
	my $bytes = shift;

	return unpack('f', $bytes) if length $bytes == 4;
	return unpack('d', $bytes) if length $bytes == 8;
	return undef;
}

# Initial counter value for AES in CTR mode
sub zeroCTR { "\0" x 16 }

my $emptyBytesHash = CDS::Hash->fromHex('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
sub emptyBytesHash { $emptyBytesHash }

# Checks if a box label is valid.
sub isValidBoxLabel {
	my $class = shift;
	my $label = shift;
	 $label eq 'messages' || $label eq 'private' || $label eq 'public' }

# Groups box additions or removals by account hash and box label.
sub groupedBoxOperations {
	my $class = shift;
	my $operations = shift;

	my %byAccountHash;
	for my $operation (@$operations) {
		my $accountHashBytes = $operation->{accountHash}->bytes;
		$byAccountHash{$accountHashBytes} = {accountHash => $operation->{accountHash}, byBoxLabel => {}} if ! exists $byAccountHash{$accountHashBytes};
		my $byBoxLabel = $byAccountHash{$accountHashBytes}->{byBoxLabel};
		my $boxLabel = $operation->{boxLabel};
		$byBoxLabel->{$boxLabel} = [] if ! exists $byBoxLabel->{$boxLabel};
		push @{$byBoxLabel->{$boxLabel}}, $operation;
	}

	return values %byAccountHash;
}

package CDS::CheckSignatureStore;

sub new {
	my $o = shift;
	my $store = shift;
	my $objects = shift;

	return bless {
		store => $store,
		id => "Check signature store\n".$store->id,
		objects => $objects // {},
		};
}

sub id { shift->{id} }

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $entry = $o->{objects}->{$hash->bytes} // return $o->{store}->get($hash);
	return $entry->{object};
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return exists $o->{objects}->{$hash->bytes};
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	$o->{objects}->{$hash->bytes} = {hash => $hash, object => $object};
	return;
}

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return 'This store only handles objects.';
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return 'This store only handles objects.';
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return 'This store only handles objects.';
}

sub modify {
	my $o = shift;
	my $modifications = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return $modifications->executeIndividually($o, $keyPair);
}

package CDS::ErrorHandlingStore;

use parent -norequire, 'CDS::Store';

sub new {
	my $class = shift;
	my $store = shift;
	my $url = shift;
	my $errorHandler = shift;

	return bless {
		store => $store,
		url => $url,
		errorHandler => $errorHandler,
		}
}

sub store { shift->{store} }
sub url { shift->{url} }
sub errorHandler { shift->{errorHandler} }

sub id {
	my $o = shift;
	 'Error handling'."\n  ".$o->{store}->id }

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return undef, 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'GET');

	my ($object, $error) = $o->{store}->get($hash, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'GET', $error);
		return undef, $error;
	}

	$o->{errorHandler}->onStoreSuccess($o, 'GET');
	return $object, $error;
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return undef, 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'BOOK');

	my ($booked, $error) = $o->{store}->book($hash, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'BOOK', $error);
		return undef, $error;
	}

	$o->{errorHandler}->onStoreSuccess($o, 'BOOK');
	return $booked;
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'PUT');

	my $error = $o->{store}->put($hash, $object, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'PUT', $error);
		return $error;
	}

	$o->{errorHandler}->onStoreSuccess($o, 'PUT');
	return;
}

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return undef, 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'LIST');

	my ($hashes, $error) = $o->{store}->list($accountHash, $boxLabel, $timeout, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'LIST', $error);
		return undef, $error;
	}

	$o->{errorHandler}->onStoreSuccess($o, 'LIST');
	return $hashes;
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'ADD');

	my $error = $o->{store}->add($accountHash, $boxLabel, $hash, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'ADD', $error);
		return $error;
	}

	$o->{errorHandler}->onStoreSuccess($o, 'ADD');
	return;
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'REMOVE');

	my $error = $o->{store}->remove($accountHash, $boxLabel, $hash, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'REMOVE', $error);
		return $error;
	}

	$o->{errorHandler}->onStoreSuccess($o, 'REMOVE');
	return;
}

sub modify {
	my $o = shift;
	my $modifications = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'MODIFY');

	my $error = $o->{store}->modify($modifications, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'MODIFY', $error);
		return $error;
	}

	$o->{errorHandler}->onStoreSuccess($o, 'MODIFY');
	return;
}

# A Condensation store on a local folder.
package CDS::FolderStore;

use parent -norequire, 'CDS::Store';

sub forUrl {
	my $class = shift;
	my $url = shift;

	return if substr($url, 0, 8) ne 'file:///';
	return $class->new(substr($url, 7));
}

sub new {
	my $class = shift;
	my $folder = shift;

	return bless {
		folder => $folder,
		permissions => CDS::FolderStore::PosixPermissions->forFolder($folder.'/accounts'),
		};
}

sub id {
	my $o = shift;
	 'file://'.$o->{folder} }
sub folder { shift->{folder} }

sub permissions { shift->{permissions} }
sub setPermissions {
	my $o = shift;
	my $permissions = shift;
	 $o->{permissions} = $permissions; }

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $hashHex = $hash->hex;
	my $file = $o->{folder}.'/objects/'.substr($hashHex, 0, 2).'/'.substr($hashHex, 2);
	return CDS::Object->fromBytes(CDS->readBytesFromFile($file));
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	# Book the object if it exists
	my $hashHex = $hash->hex;
	my $folder = $o->{folder}.'/objects/'.substr($hashHex, 0, 2);
	my $file = $folder.'/'.substr($hashHex, 2);
	return 1 if -e $file && utime(undef, undef, $file);
	return;
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	# Book the object if it exists
	my $hashHex = $hash->hex;
	my $folder = $o->{folder}.'/objects/'.substr($hashHex, 0, 2);
	my $file = $folder.'/'.substr($hashHex, 2);
	return if -e $file && utime(undef, undef, $file);

	# Write the file, set the permissions, and move it to the right place
	my $permissions = $o->{permissions};
	$permissions->mkdir($folder, $permissions->objectFolderMode);
	my $temporaryFile = $permissions->writeTemporaryFile($folder, $permissions->objectFileMode, $object->bytes) // return 'Failed to write object';
	rename($temporaryFile, $file) || return 'Failed to rename object.';
	return;
}

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return undef, 'Invalid box label.' if ! CDS->isValidBoxLabel($boxLabel);

	# Prepare
	my $boxFolder = $o->{folder}.'/accounts/'.$accountHash->hex.'/'.$boxLabel;

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

sub listFolder {
	my $o = shift;
	my $boxFolder = shift;
		# private
	my $hashes = [];
	for my $file (CDS->listFolder($boxFolder)) {
		push @$hashes, CDS::Hash->fromHex($file) // next;
	}

	return $hashes;
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $permissions = $o->{permissions};

	next if ! CDS->isValidBoxLabel($boxLabel);
	my $accountFolder = $o->{folder}.'/accounts/'.$accountHash->hex;
	$permissions->mkdir($accountFolder, $permissions->accountFolderMode);
	my $boxFolder = $accountFolder.'/'.$boxLabel;
	$permissions->mkdir($boxFolder, $permissions->boxFolderMode($boxLabel));
	my $boxFileMode = $permissions->boxFileMode($boxLabel);

	my $temporaryFile = $permissions->writeTemporaryFile($boxFolder, $boxFileMode, '') // return 'Failed to write file.';
	rename($temporaryFile, $boxFolder.'/'.$hash->hex) || return 'Failed to rename file.';
	return;
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	next if ! CDS->isValidBoxLabel($boxLabel);
	my $accountFolder = $o->{folder}.'/accounts/'.$accountHash->hex;
	my $boxFolder = $accountFolder.'/'.$boxLabel;
	next if ! -d $boxFolder;
	unlink $boxFolder.'/'.$hash->hex;
	return;
}

sub modify {
	my $o = shift;
	my $modifications = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return $modifications->executeIndividually($o, $keyPair);
}

# Store administration functions

sub exists {
	my $o = shift;

	return -d $o->{folder}.'/accounts' && -d $o->{folder}.'/objects';
}

# Creates the store if it does not exist. The store folder itself must exist.
sub createIfNecessary {
	my $o = shift;

	my $accountsFolder = $o->{folder}.'/accounts';
	my $objectsFolder = $o->{folder}.'/objects';
	$o->{permissions}->mkdir($accountsFolder, $o->{permissions}->baseFolderMode);
	$o->{permissions}->mkdir($objectsFolder, $o->{permissions}->baseFolderMode);
	return -d $accountsFolder && -d $objectsFolder;
}

# Lists accounts. This is a non-standard extension.
sub accounts {
	my $o = shift;

	return	grep { defined $_ }
			map { CDS::Hash->fromHex($_) }
			CDS->listFolder($o->{folder}.'/accounts');
}

# Adds an account. This is a non-standard extension.
sub addAccount {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';

	my $accountFolder = $o->{folder}.'/accounts/'.$accountHash->hex;
	$o->{permissions}->mkdir($accountFolder, $o->{permissions}->accountFolderMode);
	return -d $accountFolder;
}

# Removes an account. This is a non-standard extension.
sub removeAccount {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';

	my $accountFolder = $o->{folder}.'/accounts/'.$accountHash->hex;
	my $trashFolder = $o->{folder}.'/accounts/.deleted-'.CDS->randomHex(16);
	rename $accountFolder, $trashFolder;
	system('rm', '-rf', $trashFolder);
	return ! -d $accountFolder;
}

# Checks (and optionally fixes) the POSIX permissions of all files and folders. This is a non-standard extension.
sub checkPermissions {
	my $o = shift;
	my $logger = shift;

	my $permissions = $o->{permissions};

	# Check the accounts folder
	my $accountsFolder = $o->{folder}.'/accounts';
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
	my $objectsFolder = $o->{folder}.'/objects';
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

# Handles POSIX permissions (user, group, and mode).
package CDS::FolderStore::PosixPermissions;

# Returns the permissions set corresponding to the mode, uid, and gid of the base folder.
# If the permissions are ambiguous, the more restrictive set is chosen.
sub forFolder {
	my $class = shift;
	my $folder = shift;

	my @s = stat $folder;
	my $mode = $s[2] // 0;

	return
		($mode & 077) == 077 ? CDS::FolderStore::PosixPermissions::World->new :
		($mode & 070) == 070 ? CDS::FolderStore::PosixPermissions::Group->new($s[5]) :
			CDS::FolderStore::PosixPermissions::User->new($s[4]);
}

sub uid { shift->{uid} }
sub gid { shift->{gid} }

sub user {
	my $o = shift;

	my $uid = $o->{uid} // return;
	return getpwuid($uid) // $uid;
}

sub group {
	my $o = shift;

	my $gid = $o->{gid} // return;
	return getgrgid($gid) // $gid;
}

sub writeTemporaryFile {
	my $o = shift;
	my $folder = shift;
	my $mode = shift;

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

sub mkdir {
	my $o = shift;
	my $folder = shift;
	my $mode = shift;

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
sub checkPermissions {
	my $o = shift;
	my $item = shift;
	my $expectedMode = shift;
	my $logger = shift;

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

# The store belongs to a group. Every user belonging to the group is treated equivalent, and users are supposed to trust each other to some extent.
# The resulting store will have files belonging to multiple users, but the same group.
package CDS::FolderStore::PosixPermissions::Group;

use parent -norequire, 'CDS::FolderStore::PosixPermissions';

sub new {
	my $class = shift;
	my $gid = shift;

	return bless {gid => $gid // $(};
}

sub target {
	my $o = shift;
	 'members of the group '.$o->group }
sub baseFolderMode { 0771 }
sub objectFolderMode { 0771 }
sub objectFileMode { 0664 }
sub accountFolderMode { 0771 }
sub boxFolderMode {
	my $o = shift;
	my $boxLabel = shift;
	 $boxLabel eq 'public' ? 0775 : 0770 }
sub boxFileMode {
	my $o = shift;
	my $boxLabel = shift;
	 $boxLabel eq 'public' ? 0664 : 0660 }

# The store belongs to a single user. Other users shall only be able to read objects and the public box, and post to the message box.
package CDS::FolderStore::PosixPermissions::User;

use parent -norequire, 'CDS::FolderStore::PosixPermissions';

sub new {
	my $class = shift;
	my $uid = shift;

	return bless {uid => $uid // $<};
}

sub target {
	my $o = shift;
	 'user '.$o->user }
sub baseFolderMode { 0711 }
sub objectFolderMode { 0711 }
sub objectFileMode { 0644 }
sub accountFolderMode { 0711 }
sub boxFolderMode {
	my $o = shift;
	my $boxLabel = shift;
	 $boxLabel eq 'public' ? 0755 : 0700 }
sub boxFileMode {
	my $o = shift;
	my $boxLabel = shift;
	 $boxLabel eq 'public' ? 0644 : 0600 }

# The store is open to everybody. This does not usually make sense, but is offered here for completeness.
# This is the simplest permission scheme.
package CDS::FolderStore::PosixPermissions::World;

use parent -norequire, 'CDS::FolderStore::PosixPermissions';

sub new {
	my $class = shift;

	return bless {};
}

sub target { 'everybody' }
sub baseFolderMode { 0777 }
sub objectFolderMode { 0777 }
sub objectFileMode { 0666 }
sub accountFolderMode { 0777 }
sub boxFolderMode { 0777 }
sub boxFileMode { 0666 }

package CDS::FolderStore::Watcher;

sub new {
	my $class = shift;
	my $folder = shift;

	return bless {folder => $folder};
}

sub wait {
	my $o = shift;
	my $remaining = shift;
	my $until = shift;

	return if $remaining <= 0;
	sleep 1;
	return 1;
}

sub done {
	my $o = shift;
	 }

package CDS::HTTPServer;

use parent -norequire, 'HTTP::Server::Simple';

sub new {
	my $class = shift;

	my $o = $class->SUPER::new(@_);
	$o->{logger} = CDS::HTTPServer::Logger->new(*STDERR);
	$o->{handlers} = [];
	return $o;
}

sub addHandler {
	my $o = shift;
	my $handler = shift;

	push @{$o->{handlers}}, $handler;
}

sub setLogger {
	my $o = shift;
	my $logger = shift;

	$o->{logger} = $logger;
}

sub logger { shift->{logger} }

sub setCorsAllowEverybody {
	my $o = shift;
	my $value = shift;

	$o->{corsAllowEverybody} = $value;
}

sub corsAllowEverybody { shift->{corsAllowEverybody} }

# *** HTTP::Server::Simple interface

sub print_banner {
	my $o = shift;

	$o->{logger}->onServerStarts($o->port);
}

sub setup {
	my $o = shift;

	my %parameters = @_;
	$o->{request} = CDS::HTTPServer::Request->new({
		logger => $o->logger,
		method => $parameters{method},
		path => $parameters{path},
		protocol => $parameters{protocol},
		queryString => $parameters{query_string},
		peerAddress => $parameters{peeraddr},
		peerPort => $parameters{peerport},
		headers => {},
		corsAllowEverybody => $o->corsAllowEverybody,
		});
}

sub headers {
	my $o = shift;
	my $headers = shift;

	while (scalar @$headers) {
		my $key = shift @$headers;
		my $value = shift @$headers;
		$o->{request}->setHeader($key, $value);
	}

	# Read the content length
	$o->{request}->setRemainingData($o->{request}->header('content-length') // 0);
}

sub handler {
	my $o = shift;

	# Start writing the log line
	$o->{logger}->onRequestStarts($o->{request});

	# Process the request
	my $responseCode = $o->process;
	$o->{logger}->onRequestDone($o->{request}, $responseCode);

	# Wrap up
	$o->{request}->dropData;
	$o->{request} = undef;
	return;
}

sub process {
	my $o = shift;

	# Run the handler
	for my $handler (@{$o->{handlers}}) {
		my $responseCode = $handler->process($o->{request}) || next;
		return $responseCode;
	}

	# Default handler
	return $o->{request}->reply404;
}

sub bad_request {
	my $o = shift;

	my $content = 'Bad Request';
	print 'HTTP/1.1 400 Bad Request', "\r\n";
	print 'Content-Length: ', length $content, "\r\n";
	print 'Content-Type: text/plain; charset=utf-8', "\r\n";
	print "\r\n";
	print $content;
	$o->{request} = undef;
}

package CDS::HTTPServer::IdentificationHandler;

sub new {
	my $class = shift;
	my $root = shift;

	return bless {root => $root};
}

sub process {
	my $o = shift;
	my $request = shift;

	my $path = $request->pathAbove($o->{root}) // return;
	return if $path ne '/';

	# Options
	return $request->replyOptions('HEAD', 'GET') if $request->method eq 'OPTIONS';

	# Get
	return $request->reply200HTML('<!DOCTYPE html><html><head><meta charset="utf-8"><title>Condensation HTTP Store</title></head><body>This is a <a href="https://condensation.io/specifications/store/http/">Condensation HTTP Store</a> server.</body></html>') if $request->method eq 'HEAD' || $request->method eq 'GET';

	return $request->reply405;
}

package CDS::HTTPServer::Logger;

sub new {
	my $class = shift;
	my $fileHandle = shift;

	return bless {
		fileHandle => $fileHandle,
		lineStarted => 0,
		};
}

sub onServerStarts {
	my $o = shift;
	my $port = shift;

	my $fh = $o->{fileHandle};
	my @t = localtime(time);
	printf $fh '%04d-%02d-%02d %02d:%02d:%02d ', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0];
	print $fh 'Server ready at http://localhost:', $port, "\n";
}

sub onRequestStarts {
	my $o = shift;
	my $request = shift;

	my $fh = $o->{fileHandle};
	my @t = localtime(time);
	printf $fh '%04d-%02d-%02d %02d:%02d:%02d ', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0];
	print $fh $request->peerAddress, ' ', $request->method, ' ', $request->path;
	$o->{lineStarted} = 1;
}

sub onRequestError {
	my $o = shift;
	my $request = shift;

	my $fh = $o->{fileHandle};
	print $fh "\n" if $o->{lineStarted};
	print $fh '  ', @_, "\n";
	$o->{lineStarted} = 0;
}

sub onRequestDone {
	my $o = shift;
	my $request = shift;
	my $responseCode = shift;

	my $fh = $o->{fileHandle};
	print $fh '  ===> ' if ! $o->{lineStarted};
	print $fh ' ', $responseCode, "\n";
	$o->{lineStarted} = 0;
}

package CDS::HTTPServer::Request;

sub new {
	my $class = shift;
	my $parameters = shift;

	return bless $parameters;
}

sub logger { shift->{logger} }
sub method { shift->{method} }
sub path { shift->{path} }
sub queryString { shift->{queryString} }
sub peerAddress { shift->{peerAddress} }
sub peerPort { shift->{peerPort} }
sub headers { shift->{headers} }
sub remainingData { shift->{remainingData} }
sub corsAllowEverybody { shift->{corsAllowEverybody} }

# *** Path

sub pathAbove {
	my $o = shift;
	my $root = shift;

	$root .= '/' if $root !~ /\/$/;
	return if substr($o->{path}, 0, length $root) ne $root;
	return substr($o->{path}, length($root) - 1);
}

# *** Request data

sub setRemainingData {
	my $o = shift;
	my $remainingData = shift;

	$o->{remainingData} = $remainingData;
}

# Reads the request data
sub readData {
	my $o = shift;

	my @buffers;
	while ($o->{remainingData} > 0) {
		my $read = sysread(STDIN, my $buffer, $o->{remainingData}) || return;
		$o->{remainingData} -= $read;
		push @buffers, $buffer;
	}

	return join('', @buffers);
}

# Read the request data and writes it directly to a file handle
sub copyDataAndCalculateHash {
	my $o = shift;
	my $fh = shift;

	my $sha = Digest::SHA->new(256);
	while ($o->{remainingData} > 0) {
		my $read = sysread(STDIN, my $buffer, $o->{remainingData}) || return;
		$o->{remainingData} -= $read;
		$sha->add($buffer);
		print $fh $buffer;
	}

	return $sha->digest;
}

# Reads and drops the request data
sub dropData {
	my $o = shift;

	while ($o->{remainingData} > 0) {
		$o->{remainingData} -= read(STDIN, my $buffer, $o->{remainingData}) || return;
	}
}

# *** Headers

sub setHeader {
	my $o = shift;
	my $key = shift;
	my $value = shift;

	$o->{headers}->{lc($key)} = $value;
}

sub header {
	my $o = shift;
	my $key = shift;

	return $o->{headers}->{lc($key)};
}

# *** Query string

sub parseQueryString {
	my $o = shift;

	return {} if ! defined $o->{queryString};

	my $values = {};
	for my $pair (split /&/, $o->{queryString}) {
		if ($pair =~ /^(.*?)=(.*)$/) {
			my $key = $1;
			my $value = $2;
			$values->{&uri_decode($key)} = &uri_decode($value);
		} else {
			$values->{&uri_decode($pair)} = 1;
		}
	}

	return $values;
}

sub uri_decode {
	my $encoded = shift;

	$encoded =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
	return $encoded;
}

# *** Condensation signature

sub checkSignature {
	my $o = shift;
	my $store = shift;
	my $contentBytesToSign = shift;

	# Check the date
	my $dateString = $o->{headers}->{'condensation-date'} // $o->{headers}->{'date'} // return;
	my $date = HTTP::Date::str2time($dateString) // return;
	my $now = time;
	return if $date < $now - 120 || $date > $now + 60;

	# Get and check the actor
	my $actorHash = CDS::Hash->fromHex($o->{headers}->{'condensation-actor'}) // return;
	my ($publicKeyObject, $error) = $store->get($actorHash);
	return if ! $publicKeyObject;
	return if ! $publicKeyObject->calculateHash->equals($actorHash);
	my $publicKey = CDS::PublicKey->fromObject($publicKeyObject) // return;

	# Text to sign
	my $bytesToSign = $dateString."\0".uc($o->{method})."\0".$o->{headers}->{'host'}.$o->{path};
	$bytesToSign .= "\0".$contentBytesToSign if defined $contentBytesToSign;
	my $hashToSign = CDS::Hash->calculateFor($bytesToSign);

	# Check the signature
	my $signatureString = $o->{headers}->{'condensation-signature'} // return;
	$signatureString =~ /^\s*([0-9a-z]{512,512})\s*$/ // return;
	my $signature = pack('H*', $1);
	return if ! $publicKey->verifyHash($hashToSign, $signature);

	# Return the verified actor hash
	return $actorHash;
}

# *** Reply functions

sub reply200 {
	my $o = shift;
	my $content = shift // '';

	return length $content ? $o->reply(200, 'OK', &textContentType, $content) : $o->reply(204, 'No Content', {});
}

sub reply200Bytes {
	my $o = shift;
	my $content = shift // '';

	return length $content ? $o->reply(200, 'OK', {'Content-Type' => 'application/octet-stream'}, $content) : $o->reply(204, 'No Content', {});
}

sub reply200HTML {
	my $o = shift;
	my $content = shift // '';

	return length $content ? $o->reply(200, 'OK', {'Content-Type' => 'text/html; charset=utf-8'}, $content) : $o->reply(204, 'No Content', {});
}

sub replyOptions {
	my $o = shift;

	my $headers = {};
	$headers->{'Allow'} = join(', ', @_, 'OPTIONS');
	$headers->{'Access-Control-Allow-Methods'} = join(', ', @_, 'OPTIONS') if $o->corsAllowEverybody && $o->{headers}->{'origin'};
	return $o->reply(200, 'OK', $headers);
}

sub replyFatalError {
	my $o = shift;

	$o->{logger}->onRequestError($o, @_);
	return $o->reply500;
}

sub reply303 {
	my $o = shift;
	my $location = shift;
	 $o->reply(303, 'See Other', {'Location' => $location}) }
sub reply400 { shift->reply(400, 'Bad Request', &textContentType, @_) }
sub reply403 { shift->reply(403, 'Forbidden', &textContentType, @_) }
sub reply404 { shift->reply(404, 'Not Found', &textContentType, @_) }
sub reply405 { shift->reply(405, 'Method Not Allowed', &textContentType, @_) }
sub reply500 { shift->reply(500, 'Internal Server Error', &textContentType, @_) }
sub reply503 { shift->reply(503, 'Service Not Available', &textContentType, @_) }

sub reply {
	my $o = shift;
	my $responseCode = shift;
	my $responseLabel = shift;
	my $headers = shift // {};
	my $content = shift // '';

	# Content-related headers
	$headers->{'Content-Length'} = length($content);

	# Origin
	if ($o->corsAllowEverybody && (my $origin = $o->{headers}->{'origin'})) {
		$headers->{'Access-Control-Allow-Origin'} = $origin;
		$headers->{'Access-Control-Allow-Headers'} = 'Content-Type';
		$headers->{'Access-Control-Max-Age'} = '86400';
	}

	# Write the reply
	print 'HTTP/1.1 ', $responseCode, ' ', $responseLabel, "\r\n";
	for my $key (keys %$headers) {
		print $key, ': ', $headers->{$key}, "\r\n";
	}
	print "\r\n";
	print $content if $o->{method} ne 'HEAD';

	# Return the response code
	return $responseCode;
}

sub textContentType { {'Content-Type' => 'text/plain; charset=utf-8'} }

package CDS::HTTPServer::StaticContentHandler;

sub new {
	my $class = shift;
	my $path = shift;
	my $content = shift;
	my $contentType = shift;

	return bless {
		path => $path,
		content => $content,
		contentType => $contentType,
		};
}

sub process {
	my $o = shift;
	my $request = shift;

	return if $request->path ne $o->{path};

	# Options
	return $request->replyOptions('HEAD', 'GET') if $request->method eq 'OPTIONS';

	# GET
	return $request->reply(200, 'OK', {'Content-Type' => $o->{contentType}}, $o->{content}) if $request->method eq 'GET';

	# Everything else
	return $request->reply405;
}

package CDS::HTTPServer::StaticFilesHandler;

sub new {
	my $class = shift;
	my $root = shift;
	my $folder = shift;
	my $defaultFile = shift // '';

	return bless {
		root => $root,
		folder => $folder,
		defaultFile => $defaultFile,
		mimeTypesByExtension => {
			'css' => 'text/css',
			'gif' => 'image/gif',
			'html' => 'text/html',
			'jpg' => 'image/jpeg',
			'jpeg' => 'image/jpeg',
			'js' => 'application/javascript',
			'mp4' => 'video/mp4',
			'ogg' => 'video/ogg',
			'pdf' => 'application/pdf',
			'png' => 'image/png',
			'svg' => 'image/svg+xml',
			'txt' => 'text/plain',
			'webm' => 'video/webm',
			'zip' => 'application/zip',
			},
		};
}

sub folder { shift->{folder} }
sub defaultFile { shift->{defaultFile} }
sub mimeTypesByExtension { shift->{mimeTypesByExtension} }

sub setContentType {
	my $o = shift;
	my $extension = shift;
	my $contentType = shift;

	$o->{mimeTypesByExtension}->{$extension} = $contentType;
}

sub process {
	my $o = shift;
	my $request = shift;

	# Options
	return $request->replyOptions('HEAD', 'GET') if $request->method eq 'OPTIONS';

	# Get
	return $o->get($request) if $request->method eq 'GET' || $request->method eq 'HEAD';

	# Anything else
	return $request->reply405;
}

sub get {
	my $o = shift;
	my $request = shift;

	my $path = $request->pathAbove($o->{root}) // return;
	return $o->deliverFileForPath($request, $path);
}

sub deliverFileForPath {
	my $o = shift;
	my $request = shift;
	my $path = shift;

	# Hidden files (starting with a dot), as well as "." and ".." never exist
	for my $segment (split /\/+/, $path) {
		return $request->reply404 if $segment =~ /^\./;
	}

	# If a folder is requested, we serve the default file
	my $file = $o->{folder}.$path;
	if (-d $file) {
		return $request->reply404 if ! length $o->{defaultFile};
		return $request->reply303($request->path.'/') if $file !~ /\/$/;
		$file .= $o->{defaultFile};
	}

	return $o->deliverFile($request, $file);
}

sub deliverFile {
	my $o = shift;
	my $request = shift;
	my $file = shift;
	my $contentType = shift // $o->guessContentType($file);

	my $bytes = $o->readFile($file) // return $request->reply404;
	return $request->reply(200, 'OK', {'Content-Type' => $contentType}, $bytes);
}

# Guesses the content type from the extension
sub guessContentType {
	my $o = shift;
	my $file = shift;

	my $extension = $file =~ /\.([A-Za-z0-9]*)$/ ? lc($1) : '';
	return $o->{mimeTypesByExtension}->{$extension} // 'application/octet-stream';
}

# Reads a file
sub readFile {
	my $o = shift;
	my $file = shift;

	open(my $fh, '<:bytes', $file) || return;
	if (! -f $fh) {
		close $fh;
		return;
	}

	local $/ = undef;
	my $bytes = <$fh>;
	close $fh;
	return $bytes;
}

package CDS::HTTPServer::StoreHandler;

sub new {
	my $class = shift;
	my $root = shift;
	my $store = shift;
	my $checkPutHash = shift;
	my $checkSignatures = shift // 1;

	return bless {
		root => $root,
		store => $store,
		checkPutHash => $checkPutHash,
		checkEnvelopeHash => $checkPutHash,
		checkSignatures => $checkSignatures,
		maximumWatchTimeout => 0,
		};
}

sub process {
	my $o = shift;
	my $request = shift;

	my $path = $request->pathAbove($o->{root}) // return;

	# Objects request
	if ($request->path =~ /^\/objects\/([0-9a-f]{64})$/) {
		my $hash = CDS::Hash->fromHex($1);
		return $o->objects($request, $hash);
	}

	# Box request
	if ($request->path =~ /^\/accounts\/([0-9a-f]{64})\/(messages|private|public)$/) {
		my $accountHash = CDS::Hash->fromHex($1);
		my $boxLabel = $2;
		return $o->box($request, $accountHash, $boxLabel);
	}

	# Box entry request
	if ($request->path =~ /^\/accounts\/([0-9a-f]{64})\/(messages|private|public)\/([0-9a-f]{64})$/) {
		my $accountHash = CDS::Hash->fromHex($1);
		my $boxLabel = $2;
		my $hash = CDS::Hash->fromHex($3);
		return $o->boxEntry($request, $accountHash, $boxLabel, $hash);
	}

	# Account request
	if ($request->path =~ /^\/accounts\/([0-9a-f]{64})$/) {
		return $request->replyOptions if $request->method eq 'OPTIONS';
		return $request->reply405;
	}

	# Accounts request
	if ($request->path =~ /^\/accounts$/) {
		return $o->accounts($request);
	}

	# Other requests on /objects or /accounts
	if ($request->path =~ /^\/(accounts|objects)(\/|$)/) {
		return $request->reply404;
	}

	# Nothing for us
	return;
}

sub objects {
	my $o = shift;
	my $request = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	# Options
	if ($request->method eq 'OPTIONS') {
		return $request->replyOptions('HEAD', 'GET', 'PUT', 'POST');
	}

	# Retrieve object
	if ($request->method eq 'HEAD' || $request->method eq 'GET') {
		my ($object, $error) = $o->{store}->get($hash);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply404 if ! $object;
		# We don't check the SHA256 sum here - this should be done by the client
		return $request->reply200Bytes($object->bytes);
	}

	# Put object
	if ($request->method eq 'PUT') {
		my $bytes = $request->readData // return $request->reply400('No data received.');
		my $object = CDS::Object->fromBytes($bytes) // return $request->reply400('Not a Condensation object.');
		return $request->reply400('SHA256 sum does not match hash.') if $o->{checkPutHash} && ! $object->calculateHash->equals($hash);

		if ($o->{checkSignatures}) {
			my $checkSignatureStore = CDS::CheckSignatureStore->new($o->{store});
			$checkSignatureStore->put($hash, $object);
			return $request->reply403 if ! $request->checkSignature($checkSignatureStore);
		}

		my $error = $o->{store}->put($hash, $object);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200;
	}

	# Book object
	if ($request->method eq 'POST') {
		return $request->reply403 if $o->{checkSignatures} && ! $request->checkSignature($o->{store});
		return $request->reply400('You cannot send data when booking an object.') if $request->remainingData;
		my ($booked, $error) = $o->{store}->book($hash);
		return $request->replyFatalError($error) if defined $error;
		return $booked ? $request->reply200 : $request->reply404;
	}

	return $request->reply405;
}

sub box {
	my $o = shift;
	my $request = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;

	# Options
	if ($request->method eq 'OPTIONS') {
		return $request->replyOptions('HEAD', 'GET', 'PUT', 'POST');
	}

	# List box
	if ($request->method eq 'HEAD' || $request->method eq 'GET') {
		my $watch = $request->headers->{'condensation-watch'} // '';
		my $timeout = $watch =~ /^(\d+)\s*ms$/ ? $1 + 0 : 0;
		$timeout = $o->{maximumWatchTimeout} if $timeout > $o->{maximumWatchTimeout};
		my ($hashes, $error) = $o->{store}->list($accountHash, $boxLabel, $timeout);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200Bytes(join('', map { $_->bytes } @$hashes));
	}

	return $request->reply405;
}

sub boxEntry {
	my $o = shift;
	my $request = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	# Options
	if ($request->method eq 'OPTIONS') {
		return $request->replyOptions('HEAD', 'PUT', 'DELETE');
	}

	# Add
	if ($request->method eq 'PUT') {
		if ($o->{checkSignatures}) {
			my $actorHash = $request->checkSignature($o->{store});
			return $request->reply403 if ! $actorHash;
			return $request->reply403 if ! $o->verifyAddition($actorHash, $accountHash, $boxLabel, $hash);
		}

		my $error = $o->{store}->add($accountHash, $boxLabel, $hash);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200;
	}

	# Remove
	if ($request->method eq 'DELETE') {
		if ($o->{checkSignatures}) {
			my $actorHash = $request->checkSignature($o->{store});
			return $request->reply403 if ! $actorHash;
			return $request->reply403 if ! $o->verifyRemoval($actorHash, $accountHash, $boxLabel, $hash);
		}

		my ($booked, $error) = $o->{store}->remove($accountHash, $boxLabel, $hash);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200;
	}

	return $request->reply405;
}

sub accounts {
	my $o = shift;
	my $request = shift;

	# Options
	if ($request->method eq 'OPTIONS') {
		return $request->replyOptions('POST');
	}

	# Modify boxes
	if ($request->method eq 'POST') {
		my $bytes = $request->readData // return $request->reply400('No data received.');
		my $modifications = CDS::StoreModifications->fromBytes($bytes);
		return $request->reply400('Invalid modifications.') if ! $modifications;

		if ($o->{checkSignatures}) {
			my $actorHash = $request->checkSignature(CDS::CheckSignatureStore->new($o->{store}, $modifications->objects), $bytes);
			return $request->reply403 if ! $actorHash;
			return $request->reply403 if ! $o->verifyModifications($actorHash, $modifications);
		}

		my $error = $o->{store}->modify($modifications);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200;
	}

	return $request->reply405;
}

sub verifyModifications {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';
	my $modifications = shift;

	for my $operation (@{$modifications->additions}) {
		return if ! $o->verifyAddition($actorHash, $operation->{accountHash}, $operation->{boxLabel}, $operation->{hash});
	}

	for my $operation (@{$modifications->removals}) {
		return if ! $o->verifyRemoval($actorHash, $operation->{accountHash}, $operation->{boxLabel}, $operation->{hash});
	}

	return 1;
}

sub verifyAddition {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	return 1 if $accountHash->equals($actorHash);
	return 1 if $boxLabel eq 'messages';
	return;
}

sub verifyRemoval {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	return 1 if $accountHash->equals($actorHash);

	# Get the envelope
	my ($bytes, $error) = $o->{store}->get($hash);
	return if defined $error;
	return 1 if ! defined $bytes;
	my $record = CDS::Record->fromObject(CDS::Object->fromBytes($bytes)) // return;

	# Allow anyone listed under "updated by"
	my $actorHashBytes24 = substr($actorHash->bytes, 0, 24);
	for my $child ($record->child('updated by')->children) {
		my $hashBytes24 = $child->bytes;
		next if length $hashBytes24 != 24;
		return 1 if $hashBytes24 eq $actorHashBytes24;
	}

	return;
}

# A Condensation store accessed through HTTP or HTTPS.
package CDS::HTTPStore;

use parent -norequire, 'CDS::Store';

sub forUrl {
	my $class = shift;
	my $url = shift;

	$url =~ /^(http|https):\/\// || return;
	return $class->new($url);
}

sub new {
	my $class = shift;
	my $url = shift;

	return bless {url => $url};
}

sub id {
	my $o = shift;
	 $o->{url} }

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $response = $o->request('GET', $o->{url}.'/objects/'.$hash->hex, HTTP::Headers->new);
	return if $response->code == 404;
	return undef, 'get ==> HTTP '.$response->status_line if ! $response->is_success;
	return CDS::Object->fromBytes($response->decoded_content(charset => 'none'));
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $headers = HTTP::Headers->new;
	$headers->header('Content-Type' => 'application/condensation-object');
	my $response = $o->request('PUT', $o->{url}.'/objects/'.$hash->hex, $headers, $keyPair, $object->bytes);
	return if $response->is_success;
	return 'put ==> HTTP '.$response->status_line;
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $response = $o->request('POST', $o->{url}.'/objects/'.$hash->hex, HTTP::Headers->new, $keyPair);
	return if $response->code == 404;
	return 1 if $response->is_success;
	return undef, 'book ==> HTTP '.$response->status_line;
}

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $boxUrl = $o->{url}.'/accounts/'.$accountHash->hex.'/'.$boxLabel;
	my $headers = HTTP::Headers->new;
	$headers->header('Condensation-Watch' => $timeout.' ms') if $timeout > 0;
	my $response = $o->request('GET', $boxUrl, $headers);
	return undef, 'list ==> HTTP '.$response->status_line if ! $response->is_success;
	my $bytes = $response->decoded_content(charset => 'none');

	if (length($bytes) % 32 != 0) {
		print STDERR 'old procotol', "\n";
		my $hashes = [];
		for my $line (split /\n/, $bytes) {
			push @$hashes, CDS::Hash->fromHex($line) // next;
		}
		return $hashes;
	}

	my $countHashes = int(length($bytes) / 32);
	return [map { CDS::Hash->fromBytes(substr($bytes, $_ * 32, 32)) } 0 .. $countHashes - 1];
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $headers = HTTP::Headers->new;
	my $response = $o->request('PUT', $o->{url}.'/accounts/'.$accountHash->hex.'/'.$boxLabel.'/'.$hash->hex, $headers, $keyPair);
	return if $response->is_success;
	return 'add ==> HTTP '.$response->status_line;
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $headers = HTTP::Headers->new;
	my $response = $o->request('DELETE', $o->{url}.'/accounts/'.$accountHash->hex.'/'.$boxLabel.'/'.$hash->hex, $headers, $keyPair);
	return if $response->is_success;
	return 'remove ==> HTTP '.$response->status_line;
}

sub modify {
	my $o = shift;
	my $modifications = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $bytes = $modifications->toRecord->toObject->bytes;
	my $headers = HTTP::Headers->new;
	$headers->header('Content-Type' => 'application/condensation-modifications');
	my $response = $o->request('POST', $o->{url}.'/accounts', $headers, $keyPair, $bytes, 1);
	return if $response->is_success;
	return 'modify ==> HTTP '.$response->status_line;
}

# Executes a HTTP request.
sub request {
	my $class = shift;
	my $method = shift;
	my $url = shift;
	my $headers = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $data = shift;
	my $signData = shift;
		# private
	$headers->date(time);
	$headers->header('User-Agent' => CDS->version);

	if ($keyPair) {
		my $hostAndPath = $url =~ /^https?:\/\/(.*)$/ ? $1 : $url;
		my $date = CDS::ISODate->millisecondString;
		my $bytesToSign = $date."\0".uc($method)."\0".$hostAndPath;
		$bytesToSign .= "\0".$data if $signData;
		my $hashBytesToSign = Digest::SHA::sha256($bytesToSign);
		my $signature = $keyPair->sign($hashBytesToSign);
		$headers->header('Condensation-Date' => $date);
		$headers->header('Condensation-Actor' => $keyPair->publicKey->hash->hex);
		$headers->header('Condensation-Signature' => unpack('H*', $signature));
	}

	return LWP::UserAgent->new->request(HTTP::Request->new($method, $url, $headers, $data));
}

# Models a hash, and offers binary and hexadecimal representation.
package CDS::Hash;

sub fromBytes {
	my $class = shift;
	my $hashBytes = shift // return;

	return if length $hashBytes != 32;
	return bless \$hashBytes;
}

sub fromHex {
	my $class = shift;
	my $hashHex = shift // return;

	$hashHex =~ /^\s*([a-fA-F0-9]{64,64})\s*$/ || return;
	my $hashBytes = pack('H*', $hashHex);
	return bless \$hashBytes;
}

sub calculateFor {
	my $class = shift;
	my $bytes = shift;

	# The Perl built-in SHA256 implementation is a tad faster than our SHA256 implementation.
	#return $class->fromBytes(CDS::C::sha256($bytes));
	return $class->fromBytes(Digest::SHA::sha256($bytes));
}

sub hex {
	my $o = shift;

	return unpack('H*', $$o);
}

sub shortHex {
	my $o = shift;

	return unpack('H*', substr($$o, 0, 8)) . '…';
}

sub bytes {
	my $o = shift;
	 $$o }

sub equals {
	my $this = shift;
	my $that = shift;

	return 1 if ! defined $this && ! defined $that;
	return if ! defined $this || ! defined $that;
	return $$this eq $$that;
}

sub cmp {
	my $this = shift;
	my $that = shift;
	 $$this cmp $$that }

# A hash with an AES key.
package CDS::HashAndKey;

sub new {
	my $class = shift;
	my $hash = shift // return; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $key = shift // return;

	return bless {
		hash => $hash,
		key => $key,
		};
}

sub hash { shift->{hash} }
sub key { shift->{key} }

package CDS::ISODate;

# Parses a date accepting various ISO variants, and calculates the timestamp using Time::Local
sub parse {
	my $class = shift;
	my $dateString = shift // return;

	if ($dateString =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/) {
		return (timegm(0, 0, 0, $3, $2 - 1, $1 - 1900) + 86400 - 30) * 1000;
	} elsif ($dateString =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(T|\s+)(\d\d):(\d\d):(\d\d|\d\d\.\d*)$/) {
		return (timelocal(0, $6, $5, $3, $2 - 1, $1 - 1900) + $7) * 1000;
	} elsif ($dateString =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(T|\s+)(\d\d):(\d\d):(\d\d|\d\d\.\d*)Z$/) {
		return (timegm(0, $6, $5, $3, $2 - 1, $1 - 1900) + $7) * 1000;
	} elsif ($dateString =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(T|\s+)(\d\d):(\d\d):(\d\d|\d\d\.\d*)+(\d\d):(\d\d)$/) {
		return (timegm(0, $6, $5, $3, $2 - 1, $1 - 1900) + $7 - $8 * 3600 - $9 * 60) * 1000;
	} elsif ($dateString =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(T|\s+)(\d\d):(\d\d):(\d\d|\d\d\.\d*)-(\d\d):(\d\d)$/) {
		return (timegm(0, $6, $5, $3, $2 - 1, $1 - 1900) + $7 + $8 * 3600 + $9 * 60) * 1000;
	} elsif ($dateString =~ /^\s*(\d+)\s*$/) {
		return $1;
	} else {
		return;
	}
}

# Returns a properly formatted string with a precision of 1 day (i.e., the "date" only)
sub dayString {
	my $class = shift;
	my $time = shift // 1000 * time;

	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3]);
}

# Returns a properly formatted string with a precision of 1 second (i.e., "time of day" and "date") using UTC
sub secondString {
	my $class = shift;
	my $time = shift // 1000 * time;

	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

# Returns a properly formatted string with a precision of 1 second (i.e., "time of day" and "date") using UTC
sub millisecondString {
	my $class = shift;
	my $time = shift // 1000 * time;

	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02dT%02d:%02d:%02d.%03dZ', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0], int($time) % 1000);
}

# Returns a properly formatted string with a precision of 1 second (i.e., "time of day" and "date") using local time
sub localSecondString {
	my $class = shift;
	my $time = shift // 1000 * time;

	my @t = localtime($time / 1000);
	return sprintf('%04d-%02d-%02dT%02d:%02d:%02d', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

package CDS::InMemoryStore;

sub create {
	my $class = shift;

	return CDS::InMemoryStore->new('inMemoryStore:'.unpack('H*', CDS->randomBytes(16)));
}

sub new {
	my $o = shift;
	my $id = shift;

	return bless {
		id => $id,
		objects => {},
		accounts => {},
		};
}

sub id { shift->{id} }

sub accountForWriting {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	my $account = $o->{accounts}->{$hash->bytes};
	return $account if $account;
	return $o->{accounts}->{$hash->bytes} = {messages => {}, private => {}, public => {}};
}

# *** Store interface

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $entry = $o->{objects}->{$hash->bytes} // return;
	return $entry->{object};
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $entry = $o->{objects}->{$hash->bytes} // return;
	$entry->{booked} = CDS->now;
	return 1;
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	$o->{objects}->{$hash->bytes} = {object => $object, booked => CDS->now};
	return;
}

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $account = $o->{accounts}->{$accountHash->bytes} // return [];
	my $box = $account->{$boxLabel} // return undef, 'Invalid box label.';
	return values %$box;
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $box = $o->accountForWriting($accountHash)->{$boxLabel} // return;
	$box->{$hash->bytes} = $hash;
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $box = $o->accountForWriting($accountHash)->{$boxLabel} // return;
	delete $box->{$hash->bytes};
}

sub modify {
	my $o = shift;
	my $modifications = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return $modifications->executeIndividually($o, $keyPair);
}

# Garbage collection

sub collectGarbage {
	my $o = shift;
	my $graceTime = shift;

	# Mark all objects as not used
	for my $entry (values %{$o->{objects}}) {
		$entry->{inUse} = 0;
	}

	# Mark all objects newer than the grace time
	for my $entry (values %{$o->{objects}}) {
		$o->markEntry($entry) if $entry->{booked} > $graceTime;
	}

	# Mark all objects referenced from a box
	for my $account (values %{$o->{accounts}}) {
		for my $hash (values %{$account->{messages}}) { $o->markHash($hash); }
		for my $hash (values %{$account->{private}}) { $o->markHash($hash); }
		for my $hash (values %{$account->{public}}) { $o->markHash($hash); }
	}

	# Remove empty accounts
	while (my ($key, $account) = each %{$o->{accounts}}) {
		next if scalar keys %{$account->{messages}};
		next if scalar keys %{$account->{private}};
		next if scalar keys %{$account->{public}};
		delete $o->{accounts}->{$key};
	}

	# Remove obsolete objects
	while (my ($key, $entry) = each %{$o->{objects}}) {
		next if $entry->{inUse};
		delete $o->{objects}->{$key};
	}
}

sub markHash {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
			# private
	my $child = $o->{objects}->{$hash->bytes} // return;
	$o->mark($child);
}

sub markEntry {
	my $o = shift;
	my $entry = shift;
			# private
	return if $entry->{inUse};
	$entry->{inUse} = 1;

	# Mark all children
	for my $hash ($entry->{object}->hashes) {
		$o->markHash($hash);
	}
}

package CDS::KeyPair;

sub transfer {
	my $o = shift;
	my $hashes = shift;
	my $sourceStore = shift;
	my $destinationStore = shift;

	for my $hash (@$hashes) {
		my ($missing, $store, $storeError) = $o->recursiveTransfer($hash, $sourceStore, $destinationStore, {});
		return $missing if $missing;
		return undef, $store, $storeError if defined $storeError;
	}

	return;
}

sub recursiveTransfer {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $sourceStore = shift;
	my $destinationStore = shift;
	my $done = shift;
		# private
	return if $done->{$hash->bytes};
	$done->{$hash->bytes} = 1;

	# Book
	my ($booked, $bookError) = $destinationStore->book($hash, $o);
	return undef, $destinationStore, $bookError if defined $bookError;
	return if $booked;

	# Get
	my ($object, $getError) = $sourceStore->get($hash, $o);
	return undef, $sourceStore, $getError if defined $getError;
	return CDS::MissingObject->new($hash, $sourceStore) if ! defined $object;

	# Process children
	for my $child ($object->hashes) {
		my ($missing, $store, $error) = $o->recursiveTransfer($child, $sourceStore, $destinationStore, $done);
		return undef, $store, $error if defined $error;
		if (defined $missing) {
			push @{$missing->{path}}, $child;
			return $missing;
		}
	}

	# Put
	my $putError = $destinationStore->put($hash, $object, $o);
	return undef, $destinationStore, $putError if defined $putError;
	return;
}

# A store that prints all accesses to a filehandle (STDERR by default).
package CDS::LogStore;

use parent -norequire, 'CDS::Store';

sub new {
	my $class = shift;
	my $store = shift;
	my $fileHandle = shift // *STDERR;
	my $prefix = shift // '';

	return bless {
		id => "Log Store\n".$store->id,
		store => $store,
		fileHandle => $fileHandle,
		prefix => '',
		};
}

sub id { shift->{id} }
sub store { shift->{store} }
sub fileHandle { shift->{fileHandle} }
sub prefix { shift->{prefix} }

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $start = CDS::C::performanceStart();
	my ($object, $error) = $o->{store}->get($hash, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('get', $hash->shortHex, defined $object ? &formatByteLength($object->byteLength).' bytes' : defined $error ? 'failed: '.$error : 'not found', $elapsed);
	return $object, $error;
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $start = CDS::C::performanceStart();
	my $error = $o->{store}->put($hash, $object, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('put', $hash->shortHex . ' ' . &formatByteLength($object->byteLength) . ' bytes', defined $error ? 'failed: '.$error : 'OK', $elapsed);
	return $error;
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $start = CDS::C::performanceStart();
	my ($booked, $error) = $o->{store}->book($hash, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('book', $hash->shortHex, defined $booked ? 'OK' : defined $error ? 'failed: '.$error : 'not found', $elapsed);
	return $booked, $error;
}

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $start = CDS::C::performanceStart();
	my ($hashes, $error) = $o->{store}->list($accountHash, $boxLabel, $timeout, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('list', $accountHash->shortHex . ' ' . $boxLabel . ($timeout ? ' ' . $timeout . ' s' : ''), defined $hashes ? scalar(@$hashes).' entries' : 'failed: '.$error, $elapsed);
	return $hashes, $error;
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $start = CDS::C::performanceStart();
	my $error = $o->{store}->add($accountHash, $boxLabel, $hash, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('add', $accountHash->shortHex . ' ' . $boxLabel . ' ' . $hash->shortHex, defined $error ? 'failed: '.$error : 'OK', $elapsed);
	return $error;
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $start = CDS::C::performanceStart();
	my $error = $o->{store}->remove($accountHash, $boxLabel, $hash, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('remove', $accountHash->shortHex . ' ' . $boxLabel . ' ' . $hash->shortHex, defined $error ? 'failed: '.$error : 'OK', $elapsed);
	return $error;
}

sub modify {
	my $o = shift;
	my $modifications = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $start = CDS::C::performanceStart();
	my $error = $o->{store}->modify($modifications, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('modify', scalar(keys %{$modifications->objects}) . ' objects ' . scalar @{$modifications->additions} . ' additions ' . scalar @{$modifications->removals} . ' removals', defined $error ? 'failed: '.$error : 'OK', $elapsed);
	return $error;
}

sub log {
	my $o = shift;
	my $cmd = shift;
	my $input = shift;
	my $output = shift;
	my $elapsed = shift;

	my $fh = $o->{fileHandle} // return;
	print $fh $o->{prefix}, &left(8, $cmd), &left(40, $input), ' => ', &left(40, $output), &formatDuration($elapsed), ' us', "\n";
}

sub left {
	my $width = shift;
	my $text = shift;
		# private
	return $text . (' ' x ($width - length $text)) if length $text < $width;
	return $text;
}

sub formatByteLength {
	my $byteLength = shift;
		# private
	my $s = ''.$byteLength;
	$s = ' ' x (9 - length $s) . $s if length $s < 9;
	my $len = length $s;
	return substr($s, 0, $len - 6).' '.substr($s, $len - 6, 3).' '.substr($s, $len - 3, 3);
}

sub formatDuration {
	my $elapsed = shift;
		# private
	my $s = ''.$elapsed;
	$s = ' ' x (9 - length $s) . $s if length $s < 9;
	my $len = length $s;
	return substr($s, 0, $len - 6).' '.substr($s, $len - 6, 3).' '.substr($s, $len - 3, 3);
}

package CDS::MissingObject;

sub new {
	my $class = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $store = shift;

	return bless {hash => $hash, store => $store, path => [], context => undef};
}

sub hash { shift->{hash} }
sub store { shift->{store} }
sub path {
	my $o = shift;
	 @{$o->{path}} }
sub context { shift->{context} }

# A Condensation object.
# A valid object starts with a 4-byte length (big-endian), followed by 32 * length bytes of hashes, followed by 0 or more bytes of data.
package CDS::Object;

sub emptyHeader { "\0\0\0\0" }

sub create {
	my $class = shift;
	my $header = shift;
	my $data = shift;

	return if length $header < 4;
	my $hashesCount = unpack('L>', substr($header, 0, 4));
	return if length $header != 4 + $hashesCount * 32;
	return bless {
		bytes => $header.$data,
		hashesCount => $hashesCount,
		header => $header,
		data => $data
		};
}

sub fromBytes {
	my $class = shift;
	my $bytes = shift // return;

	return if length $bytes < 4;

	my $hashesCount = unpack 'L>', substr($bytes, 0, 4);
	my $dataStart = $hashesCount * 32 + 4;
	return if $dataStart > length $bytes;

	return bless {
		bytes => $bytes,
		hashesCount => $hashesCount,
		header => substr($bytes, 0, $dataStart),
		data => substr($bytes, $dataStart)
		};
}

sub fromFile {
	my $class = shift;
	my $file = shift;

	return $class->fromBytes(CDS->readBytesFromFile($file));
}

sub bytes { shift->{bytes} }
sub header { shift->{header} }
sub data { shift->{data} }
sub hashesCount { shift->{hashesCount} }
sub byteLength {
	my $o = shift;
	 length($o->{header}) + length($o->{data}) }

sub calculateHash {
	my $o = shift;

	return CDS::Hash->calculateFor($o->{bytes});
}

sub hashes {
	my $o = shift;

	return map { CDS::Hash->fromBytes(substr($o->{header}, $_ * 32 + 4, 32)) } 0 .. $o->{hashesCount} - 1;
}

sub hashAtIndex {
	my $o = shift;
	my $index = shift // return;

	return if $index < 0 || $index >= $o->{hashesCount};
	return CDS::Hash->fromBytes(substr($o->{header}, $index * 32 + 4, 32));
}

sub crypt {
	my $o = shift;
	my $key = shift;

	return CDS::Object->create($o->{header}, CDS::C::aesCrypt($o->{data}, $key, CDS->zeroCTR));
}

sub writeToFile {
	my $o = shift;
	my $file = shift;

	return CDS->writeBytesToFile($file, $o->{bytes});
}

# A store using a cache store to deliver frequently accessed objects faster, and a backend store.
package CDS::ObjectCache;

use parent -norequire, 'CDS::Store';

sub new {
	my $class = shift;
	my $backend = shift;
	my $cache = shift;

	return bless {
		id => "Object Cache\n".$backend->id."\n".$cache->id,
		backend => $backend,
		cache => $cache,
		};
}

sub id { shift->{id} }
sub backend { shift->{backend} }
sub cache { shift->{cache} }

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $objectFromCache = $o->{cache}->get($hash);
	return $objectFromCache if $objectFromCache;

	my ($object, $error) = $o->{backend}->get($hash, $keyPair);
	return undef, $error if ! defined $object;
	$o->{cache}->put($hash, $object, undef);
	return $object;
}

sub put {
	my $o = shift;

	# The important thing is that the backend succeeds. The cache is a nice-to-have.
	$o->{cache}->put(@_);
	return $o->{backend}->put(@_);
}

sub book {
	my $o = shift;

	# The important thing is that the backend succeeds. The cache is a nice-to-have.
	$o->{cache}->book(@_);
	return $o->{backend}->book(@_);
}

sub list {
	my $o = shift;

	# Just pass this through to the backend.
	return $o->{backend}->list(@_);
}

sub add {
	my $o = shift;

	# Just pass this through to the backend.
	return $o->{backend}->add(@_);
}

sub remove {
	my $o = shift;

	# Just pass this through to the backend.
	return $o->{backend}->remove(@_);
}

sub modify {
	my $o = shift;

	# Just pass this through to the backend.
	return $o->{backend}->modify(@_);
}

# A public key of somebody.
package CDS::PublicKey;

sub fromObject {
	my $class = shift;
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

	my $record = CDS::Record->fromObject($object) // return;
	my $rsaPublicKey = CDS::C::publicKeyNew($record->child('e')->bytesValue, $record->child('n')->bytesValue) // return;
	return bless {
		hash => $object->calculateHash,
		rsaPublicKey => $rsaPublicKey,
		object => $object,
		lastAccess => 0,	# used by PublicKeyCache
		};
}

sub object { shift->{object} }
sub bytes {
	my $o = shift;
	 $o->{object}->bytes }

### Public key interface ###

sub hash { shift->{hash} }
sub encrypt {
	my $o = shift;
	my $bytes = shift;
	 CDS::C::publicKeyEncrypt($o->{rsaPublicKey}, $bytes) }
sub verifyHash {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $signature = shift;
	 CDS::C::publicKeyVerify($o->{rsaPublicKey}, $hash->bytes, $signature) }

package CDS::PutTree;

sub new {
	my $o = shift;
	my $store = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $commitPool = shift;

	return bless {
		store => $store,
		commitPool => $commitPool,
		keyPair => $keyPair,
		done => {},
		};
}

sub put {
	my $o = shift;
	my $hash = shift // return; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	return if $o->{done}->{$hash->bytes};

	# Get the item
	my $hashAndObject = $o->{commitPool}->object($hash) // return;

	# Upload all children
	for my $hash ($hashAndObject->object->hashes) {
		my $error = $o->put($hash);
		return $error if defined $error;
	}

	# Upload this object
	my $error = $o->{store}->put($hashAndObject->hash, $hashAndObject->object, $o->{keyPair});
	return $error if defined $error;
	$o->{done}->{$hash->bytes} = 1;
	return;
}

# A record is a tree, whereby each nodes holds a byte sequence and an optional hash.
# Child nodes are ordered, although the order does not always matter.
package CDS::Record;

sub fromObject {
	my $class = shift;
	my $object = shift // return; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

	my $root = CDS::Record->new;
	$root->addFromObject($object) // return;
	return $root;
}

sub new {
	my $class = shift;
	my $bytes = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	bless {
		bytes => $bytes // '',
		hash => $hash,
		children => [],
		};
}

# *** Adding

# Adds a record
sub add {
	my $o = shift;
	my $bytes = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	my $record = CDS::Record->new($bytes, $hash);
	push @{$o->{children}}, $record;
	return $record;
}

sub addText {
	my $o = shift;
	my $value = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	 $o->add(Encode::encode_utf8($value // ''), $hash) }
sub addBoolean {
	my $o = shift;
	my $value = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	 $o->add(CDS->bytesFromBoolean($value), $hash) }
sub addInteger {
	my $o = shift;
	my $value = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	 $o->add(CDS->bytesFromInteger($value // 0), $hash) }
sub addUnsigned {
	my $o = shift;
	my $value = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	 $o->add(CDS->bytesFromUnsigned($value // 0), $hash) }
sub addFloat32 {
	my $o = shift;
	my $value = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	 $o->add(CDS->bytesFromFloat32($value // 0), $hash) }
sub addFloat64 {
	my $o = shift;
	my $value = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	 $o->add(CDS->bytesFromFloat64($value // 0), $hash) }
sub addHash {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	 $o->add('', $hash) }
sub addHashAndKey {
	my $o = shift;
	my $hashAndKey = shift; die 'wrong type '.ref($hashAndKey).' for $hashAndKey' if defined $hashAndKey && ref $hashAndKey ne 'CDS::HashAndKey';
	 $hashAndKey ? $o->add($hashAndKey->key, $hashAndKey->hash) : $o->add('') }
sub addRecord {
	my $o = shift;
	 push @{$o->{children}}, @_; return; }

sub addFromObject {
	my $o = shift;
	my $object = shift // return; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

	return 1 if ! length $object->data;
	return CDS::RecordReader->new($object)->readChildren($o);
}

# *** Set value

sub set {
	my $o = shift;
	my $bytes = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	$o->{bytes} = $bytes;
	$o->{hash} = $hash;
	return;
}

# *** Querying

# Returns true if the record contains a child with the indicated bytes.
sub contains {
	my $o = shift;
	my $bytes = shift;

	for my $child (@{$o->{children}}) {
		return 1 if $child->{bytes} eq $bytes;
	}
	return;
}

# Returns the child record for the given bytes. If no record with these bytes exists, a record with these bytes is returned (but not added).
sub child {
	my $o = shift;
	my $bytes = shift;

	for my $child (@{$o->{children}}) {
		return $child if $child->{bytes} eq $bytes;
	}
	return $o->new($bytes);
}

# Returns the first child, or an empty record.
sub firstChild {
	my $o = shift;
	 $o->{children}->[0] // $o->new }

# Returns the nth child, or an empty record.
sub nthChild {
	my $o = shift;
	my $i = shift;
	 $o->{children}->[$i] // $o->new }

sub containsText {
	my $o = shift;
	my $text = shift;
	 $o->contains(Encode::encode_utf8($text // '')) }
sub childWithText {
	my $o = shift;
	my $text = shift;
	 $o->child(Encode::encode_utf8($text // '')) }

# *** Get value

sub bytes { shift->{bytes} }
sub hash { shift->{hash} }
sub children {
	my $o = shift;
	 @{$o->{children}} }

sub asText {
	my $o = shift;
	 Encode::decode_utf8($o->{bytes}) // '' }
sub asBoolean {
	my $o = shift;
	 CDS->booleanFromBytes($o->{bytes}) }
sub asInteger {
	my $o = shift;
	 CDS->integerFromBytes($o->{bytes}) // 0 }
sub asUnsigned {
	my $o = shift;
	 CDS->unsignedFromBytes($o->{bytes}) // 0 }
sub asFloat {
	my $o = shift;
	 CDS->floatFromBytes($o->{bytes}) // 0 }

sub asHashAndKey {
	my $o = shift;

	return if ! $o->{hash};
	return if length $o->{bytes} != 32;
	return CDS::HashAndKey->new($o->{hash}, $o->{bytes});
}

sub bytesValue {
	my $o = shift;
	 $o->firstChild->bytes }
sub hashValue {
	my $o = shift;
	 $o->firstChild->hash }
sub textValue {
	my $o = shift;
	 $o->firstChild->asText }
sub booleanValue {
	my $o = shift;
	 $o->firstChild->asBoolean }
sub integerValue {
	my $o = shift;
	 $o->firstChild->asInteger }
sub unsignedValue {
	my $o = shift;
	 $o->firstChild->asUnsigned }
sub floatValue {
	my $o = shift;
	 $o->firstChild->asFloat }
sub hashAndKeyValue {
	my $o = shift;
	 $o->firstChild->asHashAndKey }

# *** Dependent hashes

sub dependentHashes {
	my $o = shift;

	my $hashes = {};
	$o->traverseHashes($hashes);
	return values %$hashes;
}

sub traverseHashes {
	my $o = shift;
	my $hashes = shift;
		# private
	$hashes->{$o->{hash}->bytes} = $o->{hash} if $o->{hash};
	for my $child (@{$o->{children}}) {
		$child->traverseHashes($hashes);
	}
}

# *** Size

sub countEntries {
	my $o = shift;

	my $count = 1;
	for my $child (@{$o->{children}}) { $count += $child->countEntries; }
	return $count;
}

sub calculateSize {
	my $o = shift;

	return 4 + $o->calculateSizeContribution;
}

sub calculateSizeContribution {
	my $o = shift;
		# private
	my $byteLength = length $o->{bytes};
	my $size = $byteLength < 30 ? 1 : $byteLength < 286 ? 2 : 9;
	$size += $byteLength;
	$size += 32 + 4 if $o->{hash};
	for my $child (@{$o->{children}}) {
		$size += $child->calculateSizeContribution;
	}
	return $size;
}

# *** Serialization

# Serializes this record into a Condensation object.
sub toObject {
	my $o = shift;

	my $writer = CDS::RecordWriter->new;
	$writer->writeChildren($o);
	return CDS::Object->create($writer->header, $writer->data);
}

package CDS::RecordReader;

sub new {
	my $class = shift;
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

	return bless {
		object => $object,
		data => $object->data,
		pos => 0,
		hasError => 0
		};
}

sub hasError { shift->{hasError} }

sub readChildren {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	while (1) {
		# Flags
		my $flags = $o->readUnsigned8 // return;

		# Data
		my $length = $flags & 0x1f;
		my $byteLength = $length == 30 ? 30 + ($o->readUnsigned8 // return) : $length == 31 ? ($o->readUnsigned64 // return) : $length;
		my $bytes = $o->readBytes($byteLength);
		my $hash = $flags & 0x20 ? $o->{object}->hashAtIndex($o->readUnsigned32 // return) : undef;
		return if $o->{hasError};

		# Children
		my $child = $record->add($bytes, $hash);
		return if $flags & 0x40 && ! $o->readChildren($child);
		return 1 if ! ($flags & 0x80);
	}
}

sub use {
	my $o = shift;
	my $length = shift;

	my $start = $o->{pos};
	$o->{pos} += $length;
	return substr($o->{data}, $start, $length) if $o->{pos} <= length $o->{data};
	$o->{hasError} = 1;
	return;
}

sub readUnsigned8 {
	my $o = shift;
	 unpack('C', $o->use(1) // return) }
sub readUnsigned32 {
	my $o = shift;
	 unpack('L>', $o->use(4) // return) }
sub readUnsigned64 {
	my $o = shift;
	 unpack('Q>', $o->use(8) // return) }
sub readBytes {
	my $o = shift;
	my $length = shift;
	 $o->use($length) }
sub trailer {
	my $o = shift;
	 substr($o->{data}, $o->{pos}) }

package CDS::RecordWriter;

sub new {
	my $class = shift;

	return bless {
		hashesCount => 0,
		hashes => '',
		data => ''
		};
}

sub header {
	my $o = shift;
	 pack('L>', $o->{hashesCount}).$o->{hashes} }
sub data { shift->{data} }

sub writeChildren {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	my @children = @{$record->{children}};
	return if ! scalar @children;
	my $lastChild = pop @children;
	for my $child (@children) { $o->writeNode($child, 1); }
	$o->writeNode($lastChild, 0);
}

sub writeNode {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $hasMoreSiblings = shift;

	# Flags
	my $byteLength = length $record->{bytes};
	my $flags = $byteLength < 30 ? $byteLength : $byteLength < 286 ? 30 : 31;
	$flags |= 0x20 if defined $record->{hash};
	my $countChildren = scalar @{$record->{children}};
	$flags |= 0x40 if $countChildren;
	$flags |= 0x80 if $hasMoreSiblings;
	$o->writeUnsigned8($flags);

	# Data
	$o->writeUnsigned8($byteLength - 30) if ($flags & 0x1f) == 30;
	$o->writeUnsigned64($byteLength) if ($flags & 0x1f) == 31;
	$o->writeBytes($record->{bytes});
	$o->writeUnsigned32($o->addHash($record->{hash})) if $flags & 0x20;

	# Children
	$o->writeChildren($record);
}

sub writeUnsigned8 {
	my $o = shift;
	my $value = shift;
	 $o->{data} .= pack('C', $value) }
sub writeUnsigned32 {
	my $o = shift;
	my $value = shift;
	 $o->{data} .= pack('L>', $value) }
sub writeUnsigned64 {
	my $o = shift;
	my $value = shift;
	 $o->{data} .= pack('Q>', $value) }

sub writeBytes {
	my $o = shift;
	my $bytes = shift;

	warn $bytes.' is a utf8 string, not a byte string.' if utf8::is_utf8($bytes);
	$o->{data} .= $bytes;
}

sub addHash {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	my $index = $o->{hashesCount};
	$o->{hashes} .= $hash->bytes;
	$o->{hashesCount} += 1;
	return $index;
}

# A store mapping objects and accounts to a group of stores.
package CDS::SplitStore;

use parent -norequire, 'CDS::Store';

sub new {
	my $class = shift;
	my $key = shift;

	return bless {
		id => 'Split Store\n'.unpack('H*', CDS::C::aesCrypt(CDS->zeroCTR, $key, CDS->zeroCTR)),
		key => $key,
		accountStores => [],
		objectStores => [],
		};
}

sub id { shift->{id} }

### Store configuration

sub assignAccounts {
	my $o = shift;
	my $fromIndex = shift;
	my $toIndex = shift;
	my $store = shift;

	for my $i ($fromIndex .. $toIndex) {
		$o->{accountStores}->[$i] = $store;
	}
}

sub assignObjects {
	my $o = shift;
	my $fromIndex = shift;
	my $toIndex = shift;
	my $store = shift;

	for my $i ($fromIndex .. $toIndex) {
		$o->{objectStores}->[$i] = $store;
	}
}

sub objectStore {
	my $o = shift;
	my $index = shift;
	 $o->{objectStores}->[$index] }
sub accountStore {
	my $o = shift;
	my $index = shift;
	 $o->{accountStores}->[$index] }

### Hash encryption

our $zeroCounter = "\0" x 16;

sub storeIndex {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	# To avoid attacks on a single store, the hash is encrypted with a key known to the operator only
	my $encryptedBytes = CDS::C::aesCrypt(substr($hash->bytes, 0, 16), $o->{key}, $zeroCounter);

	# Use the first byte as store index
	return ord(substr($encryptedBytes, 0, 1));
}

### Store interface

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $store = $o->objectStore($o->storeIndex($hash)) // return undef, 'No store assigned.';
	return $store->get($hash, $keyPair);
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $store = $o->objectStore($o->storeIndex($hash)) // return undef, 'No store assigned.';
	return $store->put($hash, $object, $keyPair);
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $store = $o->objectStore($o->storeIndex($hash)) // return undef, 'No store assigned.';
	return $store->book($hash, $keyPair);
}

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $store = $o->accountStore($o->storeIndex($accountHash)) // return undef, 'No store assigned.';
	return $store->list($accountHash, $boxLabel, $timeout, $keyPair);
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $store = $o->accountStore($o->storeIndex($accountHash)) // return 'No store assigned.';
	return $store->add($accountHash, $boxLabel, $hash, $keyPair);
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $store = $o->accountStore($o->storeIndex($accountHash)) // return 'No store assigned.';
	return $store->remove($accountHash, $boxLabel, $hash, $keyPair);
}

sub modify {
	my $o = shift;
	my $modifications = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	# Put objects
	my %objectsByStoreId;
	for my $entry (values %{$modifications->objects}) {
		my $store = $o->objectStore($o->storeIndex($entry->{hash}));
		my $target = $objectsByStoreId{$store->id};
		$objectsByStoreId{$store->id} = $target = {store => $store, modifications => CDS::StoreModifications->new};
		$target->modifications->put($entry->{hash}, $entry->{object});
	}

	for my $item (values %objectsByStoreId) {
		my $error = $item->{store}->modify($item->{modifications}, $keyPair);
		return $error if $error;
	}

	# Add box entries
	my %additionsByStoreId;
	for my $operation (@{$modifications->additions}) {
		my $store = $o->accountStore($o->storeIndex($operation->{accountHash}));
		my $target = $additionsByStoreId{$store->id};
		$additionsByStoreId{$store->id} = $target = {store => $store, modifications => CDS::StoreModifications->new};
		$target->modifications->add($operation->{accountHash}, $operation->{boxLabel}, $operation->{hash});
	}

	for my $item (values %additionsByStoreId) {
		my $error = $item->{store}->modify($item->{modifications}, $keyPair);
		return $error if $error;
	}

	# Remove box entries (but ignore errors)
	my %removalsByStoreId;
	for my $operation (@$modifications->removals) {
		my $store = $o->accountStore($o->storeIndex($operation->{accountHash}));
		my $target = $removalsByStoreId{$store->id};
		$removalsByStoreId{$store->id} = $target = {store => $store, modifications => CDS::StoreModifications->new};
		$target->modifications->add($operation->{accountHash}, $operation->{boxLabel}, $operation->{hash});
	}

	for my $item (values %removalsByStoreId) {
		$item->{store}->modify($item->{modifications}, $keyPair);
	}

	return;
}

# General
# sub id($o)				# () => String
package CDS::Store;

# Object store functions
# sub get($o, $hash, $keyPair)				# Hash, KeyPair? => Object?, String?
# sub put($o, $hash, $object, $keyPair)		# Hash, Object, KeyPair? => String?
# sub book($o, $hash, $keyPair)				# Hash, KeyPair? => 1?, String?

# Account store functions
# sub list($o, $accountHash, $boxLabel, $timeout, $keyPair)		# Hash, String, Duration, KeyPair? => @$Hash, String?
# sub add($o, $accountHash, $boxLabel, $hash, $keyPair)			# Hash, String, Hash, KeyPair? => String?
# sub remove($o, $accountHash, $boxLabel, $hash, $keyPair)		# Hash, String, Hash, KeyPair? => String?
# sub modify($o, $storeModifications, $keyPair)					# StoreModifications, KeyPair? => String?

package CDS::StoreModifications;

sub new {
	my $class = shift;

	return bless {
		objects => {},
		additions => [],
		removals => [],
		};
}

sub objects { shift->{objects} }
sub additions { shift->{additions} }
sub removals { shift->{removals} }

sub isEmpty {
	my $o = shift;

	return if scalar keys %{$o->{objects}};
	return if scalar @{$o->{additions}};
	return if scalar @{$o->{removals}};
	return 1;
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

	$o->{objects}->{$hash->bytes} = {hash => $hash, object => $object};
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

	$o->put($hash, $object) if $object;
	push @{$o->{additions}}, {accountHash => $accountHash, boxLabel => $boxLabel, hash => $hash};
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	push @{$o->{removals}}, {accountHash => $accountHash, boxLabel => $boxLabel, hash => $hash};
}

sub executeIndividually {
	my $o = shift;
	my $store = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	# Process objects
	for my $entry (values %{$o->{objects}}) {
		my $error = $store->put($entry->{hash}, $entry->{object}, $keyPair);
		return $error if $error;
	}

	# Process additions
	for my $entry (@{$o->{additions}}) {
		my $error = $store->add($entry->{accountHash}, $entry->{boxLabel}, $entry->{hash}, $keyPair);
		return $error if $error;
	}

	# Process removals (and ignore errors)
	for my $entry (@{$o->{removals}}) {
		$store->remove($entry->{accountHash}, $entry->{boxLabel}, $entry->{hash}, $keyPair);
	}

	return;
}

# Returns a text representation of box additions and removals.
sub toRecord {
	my $o = shift;

	my $record = CDS::Record->new;

	# Objects
	my $objectsRecord = $record->add('put');
	for my $entry (values %{$o->{objects}}) {
		$objectsRecord->add($entry->{hash}->bytes)->add($entry->{object}->bytes);
	}

	# Box additions and removals
	&addEntriesToRecord($o->{additions}, $record->add('add'));
	&addEntriesToRecord($o->{removals}, $record->add('remove'));

	return $record;
}

sub addEntriesToRecord {
	my $unsortedEntries = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
		# private
	my @additions = sort { ($a->{accountHash}->bytes cmp $b->{accountHash}->bytes) || ($a->{boxLabel} cmp $b->{boxLabel}) } @$unsortedEntries;
	my $entry = shift @additions;
	while (defined $entry) {
		my $accountHash = $entry->{accountHash};
		my $accountRecord = $record->add($accountHash->bytes);

		while (defined $entry && $entry->{accountHash}->bytes eq $accountHash->bytes) {
			my $boxLabel = $entry->{boxLabel};
			my $boxRecord = $accountRecord->add($boxLabel);

			while (defined $entry && $entry->{boxLabel} eq $boxLabel) {
				$boxRecord->add($entry->{hash}->bytes);
				$entry = shift @additions;
			}
		}
	}
}

sub fromBytes {
	my $class = shift;
	my $bytes = shift;

	my $object = CDS::Object->fromBytes($bytes) // return;
	my $record = CDS::Record->fromObject($object) // return;
	return $class->fromRecord($record);
}

sub fromRecord {
	my $class = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	my $modifications = $class->new;

	# Read objects (and "envelopes" entries used before 2022-01)
	for my $objectRecord ($record->child('put')->children, $record->child('envelopes')->children) {
		my $hash = CDS::Hash->fromBytes($objectRecord->bytes) // return;
		my $object = CDS::Object->fromBytes($objectRecord->firstChild->bytes) // return;
		#return if $o->{checkEnvelopeHash} && ! $object->calculateHash->equals($hash);
		$modifications->put($hash, $object);
	}

	# Read additions and removals
	&readEntriesFromRecord($modifications->{additions}, $record->child('add')) // return;
	&readEntriesFromRecord($modifications->{removals}, $record->child('remove')) // return;

	return $modifications;
}

sub readEntriesFromRecord {
	my $entries = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
		# private
	for my $accountHashRecord ($record->children) {
		my $accountHash = CDS::Hash->fromBytes($accountHashRecord->bytes) // return;
		for my $boxLabelRecord ($accountHashRecord->children) {
			my $boxLabel = $boxLabelRecord->bytes;
			return if ! CDS->isValidBoxLabel($boxLabel);

			for my $hashRecord ($boxLabelRecord->children) {
				my $hash = CDS::Hash->fromBytes($hashRecord->bytes) // return;
				push @$entries, {accountHash => $accountHash, boxLabel => $boxLabel, hash => $hash};
			}
		}
	}

	return 1;
}

# Useful functions to display textual information on the terminal
package CDS::UI;

sub new {
	my $class = shift;
	my $fileHandle = shift // *STDOUT;
	my $pure = shift;

	binmode $fileHandle, ":utf8";
	return bless {
		fileHandle => $fileHandle,
		pure => $pure,
		indentCount => 0,
		indent => '',
		valueIndent => 16,
		hasSpace => 0,
		hasError => 0,
		hasWarning => 0,
		};
}

sub fileHandle { shift->{fileHandle} }

### Indent

sub pushIndent {
	my $o = shift;

	$o->{indentCount} += 1;
	$o->{indent} = '  ' x $o->{indentCount};
	return;
}

sub popIndent {
	my $o = shift;

	$o->{indentCount} -= 1;
	$o->{indent} = '  ' x $o->{indentCount};
	return;
}

sub valueIndent {
	my $o = shift;
	my $width = shift;

	$o->{valueIndent} = $width;
}

### Low-level (non-semantic) output

sub print {
	my $o = shift;

	my $fh = $o->{fileHandle} // return;
	print $fh @_;
}

sub raw {
	my $o = shift;

	$o->removeProgress;
	my $fh = $o->{fileHandle} // return;
	binmode $fh, ":bytes";
	print $fh @_;
	binmode $fh, ":utf8";
	$o->{hasSpace} = 0;
	return;
}

sub space {
	my $o = shift;

	$o->removeProgress;
	return if $o->{hasSpace};
	$o->{hasSpace} = 1;
	$o->print("\n");
	return;
}

# A line of text (without word-wrap).
sub line {
	my $o = shift;

	$o->removeProgress;
	my $span = CDS::UI::Span->new(@_);
	$o->print($o->{indent});
	$span->printTo($o);
	$o->print(chr(0x1b), '[0m', "\n");
	$o->{hasSpace} = 0;
	return;
}

# A line of word-wrapped text.
sub p {
	my $o = shift;

	$o->removeProgress;
	my $span = CDS::UI::Span->new(@_);
	$span->wordWrap({lineLength => 0, maxLength => 100 - length $o->{indent}, indent => $o->{indent}});
	$o->print($o->{indent});
	$span->printTo($o);
	$o->print(chr(0x1b), '[0m', "\n");
	$o->{hasSpace} = 0;
	return;
}

# Line showing the progress.
sub progress {
	my $o = shift;

	return if $o->{pure};
	$| = 1;
	$o->{hasProgress} = 1;
	my $text = '  '.join('', @_);
	$text = substr($text, 0, 79).'…' if length $text > 80;
	$text .= ' ' x (80 - length $text) if length $text < 80;
	$o->print($text, "\r");
}

# Progress line removal.
sub removeProgress {
	my $o = shift;

	return if $o->{pure};
	return if ! $o->{hasProgress};
	$o->print(' ' x 80, "\r");
	$o->{hasProgress} = 0;
	$| = 0;
}

### Low-level (non-semantic) formatting

sub span {
	my $o = shift;
	 CDS::UI::Span->new(@_) }

sub bold {
	my $o = shift;

	my $span = CDS::UI::Span->new(@_);
	$span->{bold} = 1;
	return $span;
}

sub underlined {
	my $o = shift;

	my $span = CDS::UI::Span->new(@_);
	$span->{underlined} = 1;
	return $span;
}

sub foreground {
	my $o = shift;
	my $foreground = shift;

	my $span = CDS::UI::Span->new(@_);
	$span->{foreground} = $foreground;
	return $span;
}

sub background {
	my $o = shift;
	my $background = shift;

	my $span = CDS::UI::Span->new(@_);
	$span->{background} = $background;
	return $span;
}

sub red {
	my $o = shift;
	 $o->foreground(196, @_) }		# for failure
sub green {
	my $o = shift;
	 $o->foreground(40, @_) }		# for success
sub orange {
	my $o = shift;
	 $o->foreground(166, @_) }	# for warnings
sub blue {
	my $o = shift;
	 $o->foreground(33, @_) }		# to highlight something (selection)
sub violet {
	my $o = shift;
	 $o->foreground(93, @_) }	# to highlight something (selection)
sub gold {
	my $o = shift;
	 $o->foreground(238, @_) }		# for commands that can be executed
sub gray {
	my $o = shift;
	 $o->foreground(246, @_) }		# for additional (less important) information

sub darkBold {
	my $o = shift;

	my $span = CDS::UI::Span->new(@_);
	$span->{bold} = 1;
	$span->{foreground} = 240;
	return $span;
}

### Semantic output

sub title {
	my $o = shift;
	 $o->line($o->bold(@_)) }

sub left {
	my $o = shift;
	my $width = shift;
	my $text = shift;

	return substr($text, 0, $width - 1).'…' if length $text > $width;
	return $text . ' ' x ($width - length $text);
}

sub right {
	my $o = shift;
	my $width = shift;
	my $text = shift;

	return substr($text, 0, $width - 1).'…' if length $text > $width;
	return ' ' x ($width - length $text) . $text;
}

sub keyValue {
	my $o = shift;
	my $key = shift;
	my $firstLine = shift;

	my $indent = $o->{valueIndent} - length $o->{indent};
	$key = substr($key, 0, $indent - 2).'…' if defined $firstLine && length $key >= $indent;
	$key .= ' ' x ($indent - length $key);
	$o->line($o->gray($key), $firstLine);
	my $noKey = ' ' x $indent;
	for my $line (@_) { $o->line($noKey, $line); }
	return;
}

sub command {
	my $o = shift;
	 $o->line($o->bold(@_)) }

sub verbose {
	my $o = shift;
	 $o->line($o->foreground(45, @_)) if $o->{verbose} }

sub pGreen {
	my $o = shift;

	$o->p($o->green(@_));
	return;
}

sub pOrange {
	my $o = shift;

	$o->p($o->orange(@_));
	return;
}

sub pRed {
	my $o = shift;

	$o->p($o->red(@_));
	return;
}

### Warnings and errors

sub hasWarning { shift->{hasWarning} }
sub hasError { shift->{hasError} }

sub warning {
	my $o = shift;

	$o->{hasWarning} = 1;
	$o->p($o->orange(@_));
	return;
}

sub error {
	my $o = shift;

	$o->{hasError} = 1;
	my $span = CDS::UI::Span->new(@_);
	$span->{background} = 196;
	$span->{foreground} = 15;
	$span->{bold} = 1;
	$o->line($span);
	return;
}

### Semantic formatting

sub a {
	my $o = shift;
	 $o->underlined(@_) }

### Human readable formats

sub niceBytes {
	my $o = shift;
	my $bytes = shift;
	my $maxLength = shift;

	my $length = length $bytes;
	my $text = defined $maxLength && $length > $maxLength ? substr($bytes, 0, $maxLength - 1).'…' : $bytes;
	$text =~ s/[\x00-\x1f\x7f-\xff]/./g;
	return $text;
}

sub niceFileSize {
	my $o = shift;
	my $fileSize = shift;

	return $fileSize.' bytes' if $fileSize < 1000;
	return sprintf('%0.1f', $fileSize / 1000).' KB' if $fileSize < 10000;
	return sprintf('%0.0f', $fileSize / 1000).' KB' if $fileSize < 1000000;
	return sprintf('%0.1f', $fileSize / 1000000).' MB' if $fileSize < 10000000;
	return sprintf('%0.0f', $fileSize / 1000000).' MB' if $fileSize < 1000000000;
	return sprintf('%0.1f', $fileSize / 1000000000).' GB' if $fileSize < 10000000000;
	return sprintf('%0.0f', $fileSize / 1000000000).' GB';
}

sub niceDateTimeLocal {
	my $o = shift;
	my $time = shift // time() * 1000;

	my @t = localtime($time / 1000);
	return sprintf('%04d-%02d-%02d %02d:%02d:%02d', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

sub niceDateTime {
	my $o = shift;
	my $time = shift // time() * 1000;

	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02d %02d:%02d:%02d UTC', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

sub niceDate {
	my $o = shift;
	my $time = shift // time() * 1000;

	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3]);
}

sub niceTime {
	my $o = shift;
	my $time = shift // time() * 1000;

	my @t = gmtime($time / 1000);
	return sprintf('%02d:%02d:%02d UTC', $t[2], $t[1], $t[0]);
}

### Special output

sub record {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $storeUrl = shift;
	 CDS::UI::Record->display($o, $record, $storeUrl) }

sub recordChildren {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $storeUrl = shift;

	for my $child ($record->children) {
		CDS::UI::Record->display($o, $child, $storeUrl);
	}
}

sub selector {
	my $o = shift;
	my $selector = shift; die 'wrong type '.ref($selector).' for $selector' if defined $selector && ref $selector ne 'CDS::Selector';
	my $rootLabel = shift;

	my $item = $selector->document->get($selector);
	my $revision = $item->{revision} ? $o->green('  ', $o->niceDateTime($item->{revision})) : '';

	if ($selector->{id} eq 'ROOT') {
		$o->line($o->bold($rootLabel // 'Data tree'), $revision);
		$o->recordChildren($selector->record);
		$o->selectorChildren($selector);
	} else {
		my $label = $selector->label;
		my $labelText = length $label > 64 ? substr($label, 0, 64).'…' : $label;
		$labelText =~ s/[\x00-\x1f\x7f-\xff]/·/g;
		$o->line($o->blue($labelText), $revision);

		$o->pushIndent;
		$o->recordChildren($selector->record);
		$o->selectorChildren($selector);
		$o->popIndent;
	}
}

sub selectorChildren {
	my $o = shift;
	my $selector = shift; die 'wrong type '.ref($selector).' for $selector' if defined $selector && ref $selector ne 'CDS::Selector';

	for my $child (sort { $a->{id} cmp $b->{id} } $selector->children) {
		$o->selector($child);
	}
}

sub hexDump {
	my $o = shift;
	my $bytes = shift;
	 CDS::UI::HexDump->new($o, $bytes) }

package CDS::UI::HexDump;

sub new {
	my $class = shift;
	my $ui = shift;
	my $bytes = shift;

	return bless {ui => $ui, bytes => $bytes, styleChanges => [], };
}

sub reset { chr(0x1b).'[0m' }
sub foreground {
	my $o = shift;
	my $color = shift;
	 chr(0x1b).'[0;38;5;'.$color.'m' }

sub changeStyle {
	my $o = shift;

	push @{$o->{styleChanges}}, @_;
}

sub styleHashList {
	my $o = shift;
	my $offset = shift;

	my $hashesCount = unpack('L>', substr($o->{bytes}, $offset, 4));
	my $dataStart = $offset + 4 + $hashesCount  * 32;
	return $offset if $dataStart > length $o->{bytes};

	# Styles
	my $darkGreen = $o->foreground(28);
	my $green0 = $o->foreground(40);
	my $green1 = $o->foreground(34);

	# Color the hash count
	my $pos = $offset;
	$o->changeStyle({at => $pos, style => $darkGreen, breakBefore => 1});
	$pos += 4;

	# Color the hashes
	my $alternate = 0;
	while ($hashesCount) {
		$o->changeStyle({at => $pos, style => $alternate ? $green1 : $green0, breakBefore => 1});
		$pos += 32;
		$alternate = 1 - $alternate;
		$hashesCount -= 1;
	}

	return $dataStart;
}

sub styleRecord {
	my $o = shift;
	my $offset = shift;

	# Styles
	my $blue = $o->foreground(33);
	my $black = $o->reset;
	my $violet = $o->foreground(93);
	my @styleChanges;

	# Prepare
	my $pos = $offset;
	my $hasError = 0;
	my $level = 0;

	my $use = sub { my $length = shift;
		my $start = $pos;
		$pos += $length;
		return substr($o->{bytes}, $start, $length) if $pos <= length $o->{bytes};
		$hasError = 1;
		return;
	};

	my $readUnsigned8 = sub { unpack('C', &$use(1) // return) };
	my $readUnsigned32 = sub { unpack('L>', &$use(4) // return) };
	my $readUnsigned64 = sub { unpack('Q>', &$use(8) // return) };

	# Parse all record nodes
	while ($level >= 0) {
		# Flags
		push @styleChanges, {at => $pos, style => $blue, breakBefore => 1};
		my $flags = &$readUnsigned8 // last;

		# Data
		my $length = $flags & 0x1f;
		my $byteLength = $length == 30 ? 30 + (&$readUnsigned8 // last) : $length == 31 ? (&$readUnsigned64 // last) : $length;

		if ($byteLength) {
			push @styleChanges, {at => $pos, style => $black};
			&$use($byteLength) // last;
		}

		if ($flags & 0x20) {
			push @styleChanges, {at => $pos, style => $violet};
			&$readUnsigned32 // last;
		}

		# Children
		$level += 1 if $flags & 0x40;
		$level -= 1 if ! ($flags & 0x80);
	}

	# Don't apply any styles if there are errors
	$hasError = 1 if $pos != length $o->{bytes};
	return $offset if $hasError;

	$o->changeStyle(@styleChanges);
	return $pos;
}

sub display {
	my $o = shift;

	$o->{ui}->valueIndent(8);

	my $resetStyle = chr(0x1b).'[0m';
	my $length = length($o->{bytes});
	my $lineStart = 0;
	my $currentStyle = '';

	my @styleChanges = sort { $a->{at} <=> $b->{at} } @{$o->{styleChanges}};
	push @styleChanges, {at => $length};
	my $nextChange = shift(@styleChanges);

	$o->{ui}->line($o->{ui}->gray('····   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f  0123456789abcdef'));
	while ($lineStart < $length) {
		my $hexLine = $currentStyle;
		my $textLine = $currentStyle;

		my $k = 0;
		while ($k < 16) {
			my $index = $lineStart + $k;
			last if $index >= $length;

			my $break = 0;
			while ($index >= $nextChange->{at}) {
				$currentStyle = $nextChange->{style};
				$break = $nextChange->{breakBefore} && $k > 0;
				$hexLine .= $currentStyle;
				$textLine .= $currentStyle;
				$nextChange = shift @styleChanges;
				last if $break;
			}

			last if $break;

			my $byte = substr($o->{bytes}, $lineStart + $k, 1);
			$hexLine .= ' '.unpack('H*', $byte);

			my $code = ord($byte);
			$textLine .= $code >= 32 && $code <= 126 ? $byte : '·';

			$k += 1;
		}

		$hexLine .= '   ' x (16 - $k);
		$textLine .= ' ' x (16 - $k);
		$o->{ui}->line($o->{ui}->gray(unpack('H4', pack('S>', $lineStart))), ' ', $hexLine, $resetStyle, '  ', $textLine, $resetStyle);

		$lineStart += $k;
	}
}

# Displays a record, and tries to guess the byte interpretation
package CDS::UI::Record;

sub display {
	my $class = shift;
	my $ui = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $storeUrl = shift;

	my $o = bless {
		ui => $ui,
		onStore => defined $storeUrl ? $ui->gray(' on ', $storeUrl) : '',
		};

	$o->record($record, '');
}

sub record {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $context = shift;

	my $bytes = $record->bytes;
	my $hash = $record->hash;
	my @children = $record->children;

	# Try to interpret the key / value pair with a set of heuristic rules
	my @value =
		! length $bytes && $hash ? ($o->{ui}->gold('cds show record '), $hash->hex, $o->{onStore}) :
		! length $bytes ? $o->{ui}->gray('empty') :
		length $bytes == 32 && $hash ? ($o->{ui}->gold('cds show record '), $hash->hex, $o->{onStore}, $o->{ui}->gold(' decrypted with ', unpack('H*', $bytes))) :
		$context eq 'e' ? $o->hexValue($bytes) :
		$context eq 'n' ? $o->hexValue($bytes) :
		$context eq 'p' ? $o->hexValue($bytes) :
		$context eq 'q' ? $o->hexValue($bytes) :
		$context eq 'encrypted for' ? $o->hexValue($bytes) :
		$context eq 'updated by' ? $o->hexValue($bytes) :
		$context =~ /(^| )id( |$)/ ? $o->hexValue($bytes) :
		$context =~ /(^| )key( |$)/ ? $o->hexValue($bytes) :
		$context =~ /(^| )signature( |$)/ ? $o->hexValue($bytes) :
		$context =~ /(^| )revision( |$)/ ? $o->revisionValue($bytes) :
		$context =~ /(^| )date( |$)/ ? $o->dateValue($bytes) :
		$context =~ /(^| )expires( |$)/ ? $o->dateValue($bytes) :
			$o->guessValue($bytes);

	push @value, ' ', $o->{ui}->blue($hash->hex), $o->{onStore} if $hash && ($bytes && length $bytes != 32);
	$o->{ui}->line(@value);

	# Children
	$o->{ui}->pushIndent;
	for my $child (@children) { $o->record($child, $bytes); }
	$o->{ui}->popIndent;
}

sub hexValue {
	my $o = shift;
	my $bytes = shift;

	my $length = length $bytes;
	return '#'.unpack('H*', substr($bytes, 0, $length)) if $length <= 64;
	return '#'.unpack('H*', substr($bytes, 0, 64)), '…', $o->{ui}->gray(' (', $length, ' bytes)');
}

sub guessValue {
	my $o = shift;
	my $bytes = shift;

	my $length = length $bytes;
	my $text = $length > 64 ? substr($bytes, 0, 64).'…' : $bytes;
	$text =~ s/[\x00-\x1f\x7f-\xff]/·/g;
	my @value = ($text);

	if ($length <= 8) {
		my $integer = CDS->integerFromBytes($bytes);
		push @value, $o->{ui}->gray(' = ', $integer, $o->looksLikeTimestamp($integer) ? ' = '.$o->{ui}->niceDateTime($integer).' = '.$o->{ui}->niceDateTimeLocal($integer) : '');
	}

	push @value, $o->{ui}->gray(' = ', CDS->floatFromBytes($bytes)) if $length == 4 || $length == 8;
	push @value, $o->{ui}->gray(' = ', CDS::Hash->fromBytes($bytes)->hex) if $length == 32;
	push @value, $o->{ui}->gray(' (', length $bytes, ' bytes)') if length $bytes > 64;
	return @value;
}

sub dateValue {
	my $o = shift;
	my $bytes = shift;

	my $integer = CDS->integerFromBytes($bytes);
	return $integer if ! $o->looksLikeTimestamp($integer);
	return $o->{ui}->niceDateTime($integer), '  ', $o->{ui}->gray($o->{ui}->niceDateTimeLocal($integer));
}

sub revisionValue {
	my $o = shift;
	my $bytes = shift;

	my $integer = CDS->integerFromBytes($bytes);
	return $integer if ! $o->looksLikeTimestamp($integer);
	return $o->{ui}->niceDateTime($integer);
}

sub looksLikeTimestamp {
	my $o = shift;
	my $integer = shift;

	return $integer > 100000000000 && $integer < 10000000000000;
}

package CDS::UI::Span;

sub new {
	my $class = shift;

	return bless {
		text => [@_],
		};
}

sub printTo {
	my $o = shift;
	my $ui = shift;
	my $parent = shift;

	if ($parent) {
		$o->{appliedForeground} = $o->{foreground} // $parent->{appliedForeground};
		$o->{appliedBackground} = $o->{background} // $parent->{appliedBackground};
		$o->{appliedBold} = $o->{bold} // $parent->{appliedBold} // 0;
		$o->{appliedUnderlined} = $o->{underlined} // $parent->{appliedUnderlined} // 0;
	} else {
		$o->{appliedForeground} = $o->{foreground};
		$o->{appliedBackground} = $o->{background};
		$o->{appliedBold} = $o->{bold} // 0;
		$o->{appliedUnderlined} = $o->{underlined} // 0;
	}

	my $style = chr(0x1b).'[0';
	$style .= ';1' if $o->{appliedBold};
	$style .= ';4' if $o->{appliedUnderlined};
	$style .= ';38;5;'.$o->{appliedForeground} if defined $o->{appliedForeground};
	$style .= ';48;5;'.$o->{appliedBackground} if defined $o->{appliedBackground};
	$style .= 'm';

	my $needStyle = 1;
	for my $child (@{$o->{text}}) {
		my $ref = ref $child;
		if ($ref eq 'CDS::UI::Span') {
			$child->printTo($ui, $o);
			$needStyle = 1;
			next;
		} elsif (length $ref) {
			warn 'Printing REF';
			$child = $ref;
		} elsif (! defined $child) {
			warn 'Printing UNDEF';
			$child = 'UNDEF';
		}

		if ($needStyle) {
			$ui->print($style);
			$needStyle = 0;
		}

		$ui->print($child);
	}
}

sub wordWrap {
	my $o = shift;
	my $state = shift;

	my $index = -1;
	for my $child (@{$o->{text}}) {
		$index += 1;

		next if ! defined $child;

		my $ref = ref $child;
		if ($ref eq 'CDS::UI::Span') {
			$child->wordWrap($state);
			next;
		} elsif (length $ref) {
			warn 'Printing REF';
			$child = $ref;
		} elsif (! defined $child) {
			warn 'Printing UNDEF';
			$child = 'UNDEF';
		}

		my $position = -1;
		for my $char (split //, $child) {
			$position += 1;
			$state->{lineLength} += 1;
			if ($char eq ' ' || $char eq "\t") {
				$state->{wrapSpan} = $o;
				$state->{wrapIndex} = $index;
				$state->{wrapPosition} = $position;
				$state->{wrapReturn} = $state->{lineLength};
			} elsif ($state->{wrapSpan} && $state->{lineLength} > $state->{maxLength}) {
				my $text = $state->{wrapSpan}->{text}->[$state->{wrapIndex}];
				$text = substr($text, 0, $state->{wrapPosition})."\n".$state->{indent}.substr($text, $state->{wrapPosition} + 1);
				$state->{wrapSpan}->{text}->[$state->{wrapIndex}] = $text;
				$state->{lineLength} -= $state->{wrapReturn};
				$position += length $state->{indent} if $state->{wrapSpan} == $o && $state->{wrapIndex} == $index;
				$state->{wrapSpan} = undef;
			}
		}
	}
}

package CDS::C;
use Config;
use Inline (C => 'DATA', CCFLAGS => $Config{ccflags}.' -DNDEBUG -std=gnu99', OPTIMIZE => '-O3');
Inline->init;

1;

__DATA__
__C__
#include <stdlib.h>
#include <stdint.h>


#line 1 "Condensation/../../c/configuration/default.inc.h"
typedef uint32_t cdsLength;
#define CDS_MAX_RECORD_DEPTH 64

#line 4 "Condensation/C.inc.c"

#line 1 "Condensation/../../c/random/multi-os.inc.c"
#if defined(WIN32) || defined(_WIN32)

#line 1 "Condensation/../../c/random/windows.inc.c"
#define _CRT_RAND_S
#include <stdlib.h>

static void fillRandom(uint8_t * buffer, uint32_t length) {
	unsigned int value;
	for (uint32_t i = 0; i < length; i++) {
		rand_s(&value);
		buffer[i] = value & 0xff;
	}
}

#line 2 "Condensation/../../c/random/multi-os.inc.c"
#else

#line 1 "Condensation/../../c/random/dev-urandom.inc.c"
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

static void fillRandom(uint8_t * buffer, uint32_t length) {
	int fh = open("/dev/urandom", O_RDONLY | O_NONBLOCK);

	size_t count = 0;
	while (count < length) {
		ssize_t added = read(fh, buffer + count, length - count);
		if (added < 0) break;
		count += (size_t) added;
	}

	close(fh);
}

#line 4 "Condensation/../../c/random/multi-os.inc.c"
#endif

#line 5 "Condensation/C.inc.c"

#line 1 "Condensation/../../c/Condensation/littleEndian.inc.c"
static void copyReversed4(uint8_t * destination, const uint8_t * source) {
	destination[0] = source[3];
	destination[1] = source[2];
	destination[2] = source[1];
	destination[3] = source[0];
}

static void copyReversed8(uint8_t * destination, const uint8_t * source) {
	destination[0] = source[7];
	destination[1] = source[6];
	destination[2] = source[5];
	destination[3] = source[4];
	destination[4] = source[3];
	destination[5] = source[2];
	destination[6] = source[1];
	destination[7] = source[0];
}

void cdsSetUint32BE(uint8_t * bytes, uint32_t value) {
	union {
		uint8_t leBytes[4];
		uint32_t value;
	} u;

	u.value = value;
	copyReversed4(bytes, u.leBytes);
}

uint32_t cdsGetUint32BE(const uint8_t * bytes) {
	union {
		uint8_t leBytes[4];
		uint32_t value;
	} u;

	copyReversed4(u.leBytes, bytes);
	return u.value;
}

void cdsSetUint64BE(uint8_t * bytes, uint64_t value) {
	union {
		uint8_t leBytes[8];
		uint64_t value;
	} u;

	u.value = value;
	copyReversed8(bytes, u.leBytes);
}

uint64_t cdsGetUint64BE(const uint8_t * bytes) {
	union {
		uint8_t leBytes[8];
		uint64_t value;
	} u;

	copyReversed8(u.leBytes, bytes);
	return u.value;
}

void cdsSetFloat32BE(uint8_t * bytes, float value) {
	union {
		uint8_t leBytes[4];
		float value;
	} u;

	u.value = value;
	copyReversed4(bytes, u.leBytes);
}

float cdsGetFloat32BE(const uint8_t * bytes) {
	union {
		uint8_t leBytes[4];
		float value;
	} u;

	copyReversed4(u.leBytes, bytes);
	return u.value;
}

void cdsSetFloat64BE(uint8_t * bytes, double value) {
	union {
		uint8_t leBytes[4];
		float value;
	} u;

	u.value = value;
	copyReversed8(bytes, u.leBytes);
}

double cdsGetFloat64BE(const uint8_t * bytes) {
	union {
		uint8_t leBytes[8];
		double value;
	} u;

	copyReversed8(u.leBytes, bytes);
	return u.value;
}

#if defined(__BYTE_ORDER) && __BYTE_ORDER == __BIG_ENDIAN || defined(__BIG_ENDIAN__) || defined(__ARMEB__) || defined(__THUMBEB__) || defined(__AARCH64EB__) || defined(_MIBSEB) || defined(__MIBSEB) || defined(__MIBSEB__)
#error "This library was prepared for little-endian processor architectures. Your compiler indicates that you are compiling for a big-endian architecture."
#endif

#line 6 "Condensation/C.inc.c"

#line 1 "Condensation/../../c/Condensation/all.inc.h"
#include <stdint.h>
#include <stdbool.h>


#line 1 "Condensation/../../c/Condensation/public.h"
#include <stdbool.h>
#include <stdint.h>

struct cdsBytes {
	const uint8_t * data;
	cdsLength length;
};

struct cdsMutableBytes {
	uint8_t * data;
	cdsLength length;
};

extern const struct cdsBytes cdsEmpty;

#line 4 "Condensation/../../c/Condensation/all.inc.h"

#line 1 "Condensation/../../c/Condensation/AES256/public.h"
extern const struct cdsBytes cdsZeroCtr;

struct cdsAES256 {
	int key[240];
};

#line 5 "Condensation/../../c/Condensation/all.inc.h"

#line 1 "Condensation/../../c/Condensation/SHA256/public.h"
struct cdsSHA256 {
	uint32_t state[8];
	uint8_t chunk[64];
	uint8_t used;
	uint32_t length;
};

#line 6 "Condensation/../../c/Condensation/all.inc.h"

#line 1 "Condensation/../../c/Condensation/RSA64/public.h"
#define CDS_BIG_INTEGER_SIZE 132	// 2048 / 32 * 2 + 4
#define CDS_BIG_INTEGER_ZERO {}

struct cdsBigInteger {
	int length;
	uint32_t values[CDS_BIG_INTEGER_SIZE];
};

struct cdsRSAModPowSmall {
	struct cdsBigInteger bigInteger1;
	struct cdsBigInteger bigInteger2;
	struct cdsBigInteger gR;
	struct cdsBigInteger * result;
};

struct cdsRSAModPowBig {
	struct cdsBigInteger bigInteger1;
	struct cdsBigInteger bigInteger2;
	uint32_t mp;
	const struct cdsBigInteger * m;
	struct cdsBigInteger gR[64];
	struct cdsBigInteger * aR;
	struct cdsBigInteger * tR;
	int selection;
	int usableSelection;
	int usableBits;
	int zeroBits;
	struct cdsBigInteger * result;
};

struct cdsRSAPublicCryptMemory {
	struct cdsRSAModPowSmall modPowSmall;
	struct cdsBigInteger input;
};

struct cdsRSAPrivateCryptMemory {
	struct cdsRSAModPowBig modPowBig;
	struct cdsBigInteger input;
	struct cdsBigInteger imodp;
	struct cdsBigInteger mP;
	struct cdsBigInteger imodq;
	struct cdsBigInteger mQ;
	struct cdsBigInteger result;
	struct cdsBigInteger difference;
	struct cdsBigInteger h;
};

struct cdsRSAPublicKey {
	struct cdsBigInteger e;
	struct cdsBigInteger n;
	bool isValid;
};

struct cdsRSAPrivateKey {
	struct cdsRSAPublicKey rsaPublicKey;
	struct cdsBigInteger p;
	struct cdsBigInteger q;
	struct cdsBigInteger d;
	struct cdsBigInteger dp;
	struct cdsBigInteger dq;
	struct cdsBigInteger pInv;
	struct cdsBigInteger qInv;
	bool isValid;
};

#line 7 "Condensation/../../c/Condensation/all.inc.h"

#line 1 "Condensation/../../c/Condensation/Serialization/public.h"
struct cdsHash {
	uint8_t bytes[32];
};

struct cdsHashAndKey {
	struct cdsHash hash;
	struct cdsBytes key;
	uint8_t keyBytes[32];
};

typedef void (*cdsHashCallback)(struct cdsHash hash);

struct cdsObject {
	struct cdsBytes bytes;
	uint32_t hashesCount;
	struct cdsBytes header;
	struct cdsBytes data;
};

struct cdsRecordBuilder {
	struct cdsMutableBytes bytes;
	cdsLength dataOffset;
	cdsLength used;
	cdsLength hashesUsed;
	cdsLength levelPositions[CDS_MAX_RECORD_DEPTH];
	int level;
	int nextIsChild;
};

struct cdsRecord {
	struct cdsBytes bytes;
	const uint8_t * hash;
	struct cdsRecord * nextSibling;
	struct cdsRecord * firstChild;
};

#line 8 "Condensation/../../c/Condensation/all.inc.h"

#line 7 "Condensation/C.inc.c"

#line 1 "Condensation/../../c/Condensation/all.inc.c"
#include <stdio.h>
#include <string.h>
#include <assert.h>


#line 1 "Condensation/../../c/Condensation/minMax.inc.c"

static cdsLength minLength(cdsLength a, cdsLength b) { return a < b ? a : b; }


static size_t minSize(size_t a, size_t b) { return a < b ? a : b; }

#line 5 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/bytes.inc.c"
#include <arpa/inet.h>

const struct cdsBytes cdsEmpty = {NULL, 0};

struct cdsBytes cdsBytes(const uint8_t * bytes, cdsLength length) {
	return (struct cdsBytes) {
		bytes, length
		};
}

struct cdsBytes cdsByteSlice(const struct cdsBytes bytes, cdsLength offset, cdsLength length) {
	if (offset > bytes.length) return cdsEmpty;
	return (struct cdsBytes) {
		bytes.data + offset, minLength(length, bytes.length - offset)
		};
}

struct cdsBytes cdsByteSliceFrom(const struct cdsBytes bytes, cdsLength offset) {
	return (struct cdsBytes) {
		bytes.data + offset, bytes.length - offset
		};
}

struct cdsBytes cdsBytesFromText(const char * text) {
	return (struct cdsBytes) {
		(const uint8_t *) text, (cdsLength) strlen(text)
		};
}

int cdsCompareBytes(const struct cdsBytes a, const struct cdsBytes b) {
	cdsLength length = minLength(a.length, b.length);
	for (cdsLength i = 0; i < length; i++) {
		if (a.data[i] < b.data[i]) return -1;
		if (a.data[i] > b.data[i]) return 1;
	}

	if (a.length < b.length) return -1;
	if (a.length > b.length) return 1;
	return 0;
}

bool cdsEqualBytes(const struct cdsBytes a, const struct cdsBytes b) {
	if (a.length != b.length) return false;
	for (cdsLength i = 0; i < a.length; i++)
		if (a.data[i] != b.data[i]) return false;
	return true;
}

struct cdsMutableBytes cdsMutableBytes(uint8_t * bytes, cdsLength length) {
	return (struct cdsMutableBytes) {
		bytes, length
		};
}

struct cdsMutableBytes cdsMutableBytesFromText(char * text) {
	return (struct cdsMutableBytes) {
		(uint8_t *) text, (cdsLength) strlen(text)
		};
}

struct cdsBytes cdsSeal(const struct cdsMutableBytes bytes) {
	return (struct cdsBytes) {
		bytes.data, bytes.length
		};
}

struct cdsMutableBytes cdsMutableByteSlice(const struct cdsMutableBytes bytes, cdsLength offset, cdsLength length) {
	return (struct cdsMutableBytes) {
		bytes.data + offset, length
		};
}

struct cdsMutableBytes cdsMutableByteSliceFrom(const struct cdsMutableBytes bytes, cdsLength offset) {
	return (struct cdsMutableBytes) {
		bytes.data + offset, bytes.length - offset
		};
}

struct cdsMutableBytes cdsSetBytes(const struct cdsMutableBytes destination, cdsLength destinationOffset, const struct cdsBytes source) {
	cdsLength length = minLength(destination.length - destinationOffset, source.length);
	memcpy(destination.data + destinationOffset, source.data, length);
	return cdsMutableBytes(destination.data + destinationOffset, length);
}

#line 6 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/hex.inc.c"

static char hexDigits[] = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'};
static uint8_t hexValues[] = {255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 255, 255, 255, 255, 255, 255, 255, 10, 11, 12, 13, 14, 15, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 10, 11, 12, 13, 14, 15, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255};

char * cdsHexFromBytes(const struct cdsBytes bytes, char * buffer, cdsLength length) {
	if (length == 0) return buffer;

	cdsLength w = 0;
	cdsLength r = 0;
	while (r < bytes.length && w < length - 2) {
		buffer[w] = hexDigits[(bytes.data[r] >> 4) & 0xf];
		w += 1;

		buffer[w] = hexDigits[bytes.data[r] & 0xf];
		w += 1;

		r += 1;
	}

	buffer[w] = 0;
	return buffer;
}

struct cdsBytes cdsBytesFromHex(const char * hex, uint8_t * buffer, cdsLength length) {
	cdsLength i = 0;
	while (i < length) {
		uint8_t b1 = hexValues[(int)hex[i * 2]];
		if (b1 >= 16) break;

		uint8_t b2 = hexValues[(int)hex[i * 2 + 1]];
		if (b2 >= 16) break;

		buffer[i] = (b1 << 4) | b2;
		i += 1;
	}

	return cdsBytes(buffer, i);
}

#line 7 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/random.inc.c"
struct cdsBytes cdsRandomBytes(uint8_t * buffer, cdsLength length) {
	fillRandom(buffer, length);
	return cdsBytes(buffer, length);
}

#line 8 "Condensation/../../c/Condensation/all.inc.c"


#line 1 "Condensation/../../c/Condensation/AES256/AES256.inc.c"

static int sbox[] = {99, 124, 119, 123, 242, 107, 111, 197, 48, 1, 103, 43, 254, 215, 171, 118, 202, 130, 201, 125, 250, 89, 71, 240, 173, 212, 162, 175, 156, 164, 114, 192, 183, 253, 147, 38, 54, 63, 247, 204, 52, 165, 229, 241, 113, 216, 49, 21, 4, 199, 35, 195, 24, 150, 5, 154, 7, 18, 128, 226, 235, 39, 178, 117, 9, 131, 44, 26, 27, 110, 90, 160, 82, 59, 214, 179, 41, 227, 47, 132, 83, 209, 0, 237, 32, 252, 177, 91, 106, 203, 190, 57, 74, 76, 88, 207, 208, 239, 170, 251, 67, 77, 51, 133, 69, 249, 2, 127, 80, 60, 159, 168, 81, 163, 64, 143, 146, 157, 56, 245, 188, 182, 218, 33, 16, 255, 243, 210, 205, 12, 19, 236, 95, 151, 68, 23, 196, 167, 126, 61, 100, 93, 25, 115, 96, 129, 79, 220, 34, 42, 144, 136, 70, 238, 184, 20, 222, 94, 11, 219, 224, 50, 58, 10, 73, 6, 36, 92, 194, 211, 172, 98, 145, 149, 228, 121, 231, 200, 55, 109, 141, 213, 78, 169, 108, 86, 244, 234, 101, 122, 174, 8, 186, 120, 37, 46, 28, 166, 180, 198, 232, 221, 116, 31, 75, 189, 139, 138, 112, 62, 181, 102, 72, 3, 246, 14, 97, 53, 87, 185, 134, 193, 29, 158, 225, 248, 152, 17, 105, 217, 142, 148, 155, 30, 135, 233, 206, 85, 40, 223, 140, 161, 137, 13, 191, 230, 66, 104, 65, 153, 45, 15, 176, 84, 187, 22};

static int xtime[] = {0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54, 56, 58, 60, 62, 64, 66, 68, 70, 72, 74, 76, 78, 80, 82, 84, 86, 88, 90, 92, 94, 96, 98, 100, 102, 104, 106, 108, 110, 112, 114, 116, 118, 120, 122, 124, 126, 128, 130, 132, 134, 136, 138, 140, 142, 144, 146, 148, 150, 152, 154, 156, 158, 160, 162, 164, 166, 168, 170, 172, 174, 176, 178, 180, 182, 184, 186, 188, 190, 192, 194, 196, 198, 200, 202, 204, 206, 208, 210, 212, 214, 216, 218, 220, 222, 224, 226, 228, 230, 232, 234, 236, 238, 240, 242, 244, 246, 248, 250, 252, 254, 27, 25, 31, 29, 19, 17, 23, 21, 11, 9, 15, 13, 3, 1, 7, 5, 59, 57, 63, 61, 51, 49, 55, 53, 43, 41, 47, 45, 35, 33, 39, 37, 91, 89, 95, 93, 83, 81, 87, 85, 75, 73, 79, 77, 67, 65, 71, 69, 123, 121, 127, 125, 115, 113, 119, 117, 107, 105, 111, 109, 99, 97, 103, 101, 155, 153, 159, 157, 147, 145, 151, 149, 139, 137, 143, 141, 131, 129, 135, 133, 187, 185, 191, 189, 179, 177, 183, 181, 171, 169, 175, 173, 163, 161, 167, 165, 219, 217, 223, 221, 211, 209, 215, 213, 203, 201, 207, 205, 195, 193, 199, 197, 251, 249, 255, 253, 243, 241, 247, 245, 235, 233, 239, 237, 227, 225, 231, 229};

static const int keyLength = 240;  // 16 * (14 + 1)

uint8_t zeroCtrBuffer[16] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
const struct cdsBytes cdsZeroCtr = {zeroCtrBuffer, 16};

void cdsInitializeEmptyAES256(struct cdsAES256 * this) { }

void cdsInitializeAES256(struct cdsAES256 * this, struct cdsBytes key256) {
	int i = 0;
	int r = 1;
	while (i < 32) {
		this->key[i] = key256.data[i];
		i++;
	}

	while (i < keyLength) {
		int mod = i % 32;
		if (mod == 0) {
			this->key[i + 0] = this->key[i + 0 - 32] ^ sbox[this->key[i - 3]] ^ r;
			this->key[i + 1] = this->key[i + 1 - 32] ^ sbox[this->key[i - 2]];
			this->key[i + 2] = this->key[i + 2 - 32] ^ sbox[this->key[i - 1]];
			this->key[i + 3] = this->key[i + 3 - 32] ^ sbox[this->key[i - 4]];
			r <<= 1;
		} else if (mod == 16) {
			this->key[i + 0] = this->key[i + 0 - 32] ^ sbox[this->key[i - 4]];
			this->key[i + 1] = this->key[i + 1 - 32] ^ sbox[this->key[i - 3]];
			this->key[i + 2] = this->key[i + 2 - 32] ^ sbox[this->key[i - 2]];
			this->key[i + 3] = this->key[i + 3 - 32] ^ sbox[this->key[i - 1]];
		} else {
			this->key[i + 0] = this->key[i + 0 - 32] ^ this->key[i - 4];
			this->key[i + 1] = this->key[i + 1 - 32] ^ this->key[i - 3];
			this->key[i + 2] = this->key[i + 2 - 32] ^ this->key[i - 2];
			this->key[i + 3] = this->key[i + 3 - 32] ^ this->key[i - 1];
		}
		i += 4;
	}
}

static void subBytes(uint8_t * block) {
	for (int i = 0; i < 16; i++) block[i] = sbox[block[i]];
}

static void addRoundKey(const int * key, uint8_t * block, int offset) {
	for (int i = 0; i < 16; i++) block[i] ^= key[offset + i];
}

static void shiftRows(uint8_t * block) {
	int t1 = block[1];
	block[1] = block[5];
	block[5] = block[9];
	block[9] = block[13];
	block[13] = t1;
	int t2 = block[2];
	block[2] = block[10];
	block[10] = t2;
	int t3 = block[3];
	block[3] = block[15];
	block[15] = block[11];
	block[11] = block[7];
	block[7] = t3;
	int t6 = block[6];
	block[6] = block[14];
	block[14] = t6;
}

static void mixColumns(uint8_t * block) {
	for (int i = 0; i < 16; i += 4) {
		int s0 = block[i + 0];
		int s1 = block[i + 1];
		int s2 = block[i + 2];
		int s3 = block[i + 3];
		int h = s0 ^ s1 ^ s2 ^ s3;
		block[i + 0] ^= h ^ xtime[s0 ^ s1];
		block[i + 1] ^= h ^ xtime[s1 ^ s2];
		block[i + 2] ^= h ^ xtime[s2 ^ s3];
		block[i + 3] ^= h ^ xtime[s3 ^ s0];
	}
}

void cdsEncryptAES256Block(const struct cdsAES256 * this, uint8_t * block) {
	addRoundKey(this->key, block, 0);
	for (int i = 16; i < keyLength - 16; i += 16) {
		subBytes(block);
		shiftRows(block);
		mixColumns(block);
		addRoundKey(this->key, block, i);
	}
	subBytes(block);
	shiftRows(block);
	addRoundKey(this->key, block, keyLength - 16);
}

void cdsIncrementCtr(uint8_t * counter) {
	for (int n = 15; n >= 0; n--) {
		counter[n] += 1;
		if (counter[n] != 0) break;
	}
}

struct cdsBytes cdsCrypt(const struct cdsAES256 * aes, const struct cdsBytes bytes, const struct cdsBytes startCtr, uint8_t * buffer) {
	uint8_t counter[16];
	memcpy(counter, startCtr.data, 16);
	uint8_t encryptedCounter[16];

	cdsLength i = 0;
	for (; i + 16 < bytes.length; i += 16) {
		memcpy(encryptedCounter, counter, 16);
		cdsEncryptAES256Block(aes, encryptedCounter);
		for (cdsLength n = 0; n < 16; n++) buffer[i + n] = bytes.data[i + n] ^ encryptedCounter[n];
		cdsIncrementCtr(counter);
	}

	cdsEncryptAES256Block(aes, counter);
	for (cdsLength n = 0; n < bytes.length - i; n++) buffer[i + n] = bytes.data[i + n] ^ counter[n];

	return cdsBytes(buffer, bytes.length);
}

#line 10 "Condensation/../../c/Condensation/all.inc.c"


#line 1 "Condensation/../../c/Condensation/SHA256/SHA256.inc.c"

static uint32_t K[] = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};


static uint32_t getUint32(const uint8_t * bytes) {
	return (uint32_t)(bytes[0] << 24) | (uint32_t)(bytes[1] << 16) | (uint32_t)(bytes[2] << 8) | bytes[3];
}

static void putUint32(uint8_t * bytes, uint32_t value) {
	bytes[0] = (value >> 24) & 0xff;
	bytes[1] = (value >> 16) & 0xff;
	bytes[2] = (value >> 8) & 0xff;
	bytes[3] = value & 0xff;
}


static uint32_t ROTR(uint32_t x, uint32_t n) {
	return (x >> n) | (x << (32 - n));
}

static uint32_t prepareS0(uint32_t x) {
	return ROTR(x, 7) ^ ROTR(x, 18) ^ (x >> 3);
}

static uint32_t prepareS1(uint32_t x) {
	return ROTR(x, 17) ^ ROTR(x, 19) ^ (x >> 10);
}

static uint32_t roundS0(uint32_t x) {
	return ROTR(x, 2) ^ ROTR(x, 13) ^ ROTR(x, 22);
}

static uint32_t roundS1(uint32_t x) {
	return ROTR(x, 6) ^ ROTR(x, 11) ^ ROTR(x, 25);
}

static uint32_t ch(uint32_t x, uint32_t y, uint32_t z)  {
	return (x & y) ^ (~x & z);
}

static uint32_t maj(uint32_t x, uint32_t y, uint32_t z) {
	return (x & y) ^ (x & z) ^ (y & z);
}

static void sha256AddChunk(struct cdsSHA256 * this, const uint8_t * bytes) {
	uint32_t w[64];
	for (uint8_t i = 0; i < 16; i++)
		w[i] = getUint32(bytes + i * 4);
	for (uint8_t i = 16; i < 64; i++)
		w[i] = prepareS1(w[i - 2]) + w[i - 7] + prepareS0(w[i - 15]) + w[i - 16];

	uint32_t s[8];
	for (uint8_t i = 0; i < 8; i++)
		s[i] = this->state[i];

	for (uint8_t i = 0; i < 64; i++) {
		uint32_t t1 = s[7] + roundS1(s[4]) + ch(s[4], s[5], s[6]) + K[i] + w[i];
		uint32_t t2 = roundS0(s[0]) + maj(s[0], s[1], s[2]);
		s[7] = s[6];
		s[6] = s[5];
		s[5] = s[4];
		s[4] = s[3] + t1;
		s[3] = s[2];
		s[2] = s[1];
		s[1] = s[0];
		s[0] = t1 + t2;
	}

	for (uint8_t i = 0; i < 8; i++)
		this->state[i] += s[i];
}

uint32_t sha256InitialHash[] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};

void cdsInitializeSHA256(struct cdsSHA256 * this) {
	for (int i = 0; i < 8; i++)
		this->state[i] = sha256InitialHash[i];
	this->used = 0;
	this->length = 0;
}

static void sha256AddByte(struct cdsSHA256 * this, uint8_t byte) {
	this->chunk[this->used] = byte;
	this->used += 1;
	this->length += 1;
	if (this->used < 64) return;

	sha256AddChunk(this, this->chunk);
	this->used = 0;
}

void cdsAddBytesToSHA256(struct cdsSHA256 * this, struct cdsBytes bytes) {
	for (uint32_t i = 0; i < bytes.length; i++)
		sha256AddByte(this, bytes.data[i]);
}

void cdsFinalizeSHA256(struct cdsSHA256 * this, uint8_t * result) {
	uint32_t dataLength = this->length;

	sha256AddByte(this, 0x80);
	while (this->used != 56)
		sha256AddByte(this, 0);

	sha256AddByte(this, 0);
	sha256AddByte(this, 0);
	sha256AddByte(this, 0);
	sha256AddByte(this, (dataLength & 0xe0000000) >> 29);
	sha256AddByte(this, (dataLength & 0x1fe00000) >> 21);
	sha256AddByte(this, (dataLength & 0x001fe000) >> 13);
	sha256AddByte(this, (dataLength & 0x00001fe0) >> 5);
	sha256AddByte(this, (dataLength & 0x0000001f) << 3);

	for (uint8_t i = 0; i < 8; i++)
		putUint32(result + i * 4, this->state[i]);
}

struct cdsBytes cdsSHA256(const struct cdsBytes bytes, uint8_t * result) {
	struct cdsSHA256 sha;
	cdsInitializeSHA256(&sha);
	cdsAddBytesToSHA256(&sha, bytes);
	cdsFinalizeSHA256(&sha, result);
	return cdsBytes(result, 32);
}

#line 12 "Condensation/../../c/Condensation/all.inc.c"


#line 1 "Condensation/../../c/Condensation/RSA64/production.inc.c"

#define ELEMENT(x, n) x->values[n]

#define X(index) ELEMENT(x, index)
#define Y(index) ELEMENT(y, index)
#define M(index) ELEMENT(m, index)
#define G(index) ELEMENT(g, index)
#define E(index) ELEMENT(e, index)
#define A(index) ELEMENT(a, index)

#line 14 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/RSA64/Math.inc.c"


static void setZero(struct cdsBigInteger * x) {
	x->length = 0;
}

static void setUint32(struct cdsBigInteger * x, uint32_t value) {
	x->length = 1;
	X(0) = value;
}

static void setRandom(struct cdsBigInteger * x, int n) {
	assert(n >= 0);
	assert(n <= CDS_BIG_INTEGER_SIZE);
	cdsRandomBytes((uint8_t *) x->values, n * 4);
	x->length = n;
}

static int mostSignificantElement(const struct cdsBigInteger * x) {
	int i = x->length - 1;
	while (i >= 0 && X(i) == 0) i -= 1;
	return i;
}

static void trim(struct cdsBigInteger * x) {
	while (x->length > 0 && X(x->length - 1) == 0) x->length -= 1;
}

static void expand(struct cdsBigInteger * x, int n) {
	assert(n >= 0);
	assert(n <= CDS_BIG_INTEGER_SIZE);
	while (x->length < n) {
		x->length += 1;
		X(x->length - 1) = 0;
	}
}

static int maxLength(const struct cdsBigInteger * x, const struct cdsBigInteger * y) {
	return x->length > y->length ? x->length : y->length;
}

static void copyD(struct cdsBigInteger * a, const struct cdsBigInteger * x, int d) {
	a->length = x->length + d;
	for (int i = 0; i < x->length; i++) A(i + d) = X(i);
	for (int i = 0; i < d; i++) A(i) = 0;
}


void cdsBigIntegerFromBytes(struct cdsBigInteger * x, struct cdsBytes bytes) {
	x->length = CDS_BIG_INTEGER_SIZE;

	int w = 0;
	int n = (int)bytes.length;
	while (n > 3 && w < CDS_BIG_INTEGER_SIZE) {
		X(w) = ((uint32_t)bytes.data[n - 4] << 24) | ((uint32_t)bytes.data[n - 3] << 16) | ((uint32_t)bytes.data[n - 2] << 8) | (uint32_t)bytes.data[n - 1];
		n -= 4;
		w += 1;
	}

	X(w) = 0;
	if (n > 0) X(w) |= (uint32_t)bytes.data[n - 1];
	if (n > 1) X(w) |= (uint32_t)bytes.data[n - 2] << 8;
	if (n > 2) X(w) |= (uint32_t)bytes.data[n - 3] << 16;

	x->length = w + 1;
	trim(x);
}

struct cdsBytes cdsBytesFromBigInteger(struct cdsMutableBytes bytes, const struct cdsBigInteger * x) {
	uint32_t n = bytes.length;
	for (int r = 0; r < x->length; r++) {
		n -= 1;
		bytes.data[n] = X(r) & 0xff;
		if (n == 0) break;
		n -= 1;
		bytes.data[n] = (X(r) >> 8) & 0xff;
		if (n == 0) break;
		n -= 1;
		bytes.data[n] = (X(r) >> 16) & 0xff;
		if (n == 0) break;
		n -= 1;
		bytes.data[n] = (X(r) >> 24) & 0xff;
		if (n == 0) break;
	}
	memset(bytes.data, 0, n);
	while (n < bytes.length && bytes.data[n] == 0) n++;
	return cdsBytes(bytes.data + n, bytes.length - n);
}


static bool isEven(const struct cdsBigInteger * x) {
	return x->length == 0 || (X(0) & 1) == 0;
}

static bool isZero(const struct cdsBigInteger * x) {
	return mostSignificantElement(x) == -1;
}

static bool isOne(const struct cdsBigInteger * x) {
	return mostSignificantElement(x) == 0 && X(0) == 1;
}

static int compare(const struct cdsBigInteger * x, const struct cdsBigInteger * y) {
	int xk = mostSignificantElement(x);
	int yk = mostSignificantElement(y);
	if (xk < yk) return -1;
	if (xk > yk) return 1;
	for (int i = xk; i >= 0; i--) {
		if (X(i) < Y(i)) return -1;
		if (X(i) > Y(i)) return 1;
	}
	return 0;
}

static int compareShifted(const struct cdsBigInteger * x, const struct cdsBigInteger * y, int d) {
	int xk = mostSignificantElement(x);
	int yk = mostSignificantElement(y);
	if (xk < yk + d) return -1;
	if (xk > yk + d) return 1;
	for (int i = yk; i >= 0; i--) {
		if (X(i + d) < Y(i)) return -1;
		if (X(i + d) > Y(i)) return 1;
	}
	return 0;
}


static void smallShiftLeft(struct cdsBigInteger * a, const struct cdsBigInteger * x, int bits) {
	a->length = x->length;
	int i = 0;
	uint64_t cPrev = 0;
	for (; i < a->length; i++) {
		uint64_t cNext = (uint64_t)X(i) << bits;
		A(i) = (uint32_t) (cNext | cPrev);
		cPrev = cNext >> 32;
	}
	if (cPrev == 0) return;
	a->length += 1;
	A(i) = (uint32_t) cPrev;
}

static void smallShiftRight(struct cdsBigInteger * a, const struct cdsBigInteger * x, int bits) {
	a->length = x->length;
	int i = 0;
	for (; i + 1 < x->length; i++)
		A(i) = (uint32_t) (X(i) >> bits | (uint64_t)X(i + 1) << (32 - bits));
	A(i) = X(i) >> bits;
}


static void addN(struct cdsBigInteger * x, uint32_t n, const struct cdsBigInteger * y, int d) {
	int yk = mostSignificantElement(y);

	if (x->length > 0 && X(x->length - 1) != 0) expand(x, x->length + 1);
	expand(x, y->length + d + 2);

	uint64_t c = 0;
	int i = 0;
	for (; i <= yk; i++, d++) {
		c += X(d) + (uint64_t)n * Y(i);
		X(d) = c & 0xffffffff;
		c >>= 32;
	}

	for (; c != 0; d++) {
		c += X(d);
		X(d) = c & 0xffffffff;
		c >>= 32;
	}
}

static void decrement(struct cdsBigInteger * x) {
	int64_t c = -1;
	for (int i = 0; c != 0; i++) {
		c += X(i);
		X(i) = c & 0xffffffff;
		c >>= 32;
	}
}

static void subD(struct cdsBigInteger * x, const struct cdsBigInteger * y, int d) {
	int64_t c = 0;
	int i = 0;
	for (; i < y->length && i < x->length; i++, d++) {
		c += (int64_t)X(d) - Y(i);
		X(d) = c & 0xffffffff;
		c >>= 32;
	}
	for (; c != 0; d++) {
		c += (int64_t)X(d);
		X(d) = c & 0xffffffff;
		c >>= 32;
	}
}

static void subN(struct cdsBigInteger * x, uint32_t n, const struct cdsBigInteger * y, int d) {
	uint32_t nNeg = (uint32_t) (0x100000000 - n);
	addN(x, nNeg, y, d);
	subD(x, y, d + 1);
}


static void mul(struct cdsBigInteger * a, const struct cdsBigInteger * x, const struct cdsBigInteger * y) {
	for (int i = 0; i < y->length; i++)
		if (Y(i) != 0) addN(a, Y(i), x, i);
	trim(a);
}

static void sqr(struct cdsBigInteger * a, const struct cdsBigInteger * x) {
	int xk = mostSignificantElement(x);
	expand(a, a->length + 1);
	expand(a, (xk + 1) << 1);
	for (int i = 0; i <= xk; i++) {
		if (X(i) == 0) continue;

		int r = i;
		int w = i + r;
		uint64_t cSum = A(w) + (uint64_t)X(r) * X(i);
		A(w) = cSum & 0xffffffff;
		cSum >>= 32;
		w++;
		r++;

		uint64_t cProduct = 0;
		for (; r <= xk; w++, r++) {
			cProduct += (uint64_t)X(r) * X(i);
			cSum += A(w) + ((cProduct & 0xffffffff) << 1);
			A(w) = cSum & 0xffffffff;
			cProduct >>= 32;
			cSum >>= 32;
		}
		for (; cSum != 0 || cProduct != 0; w++) {
			cSum += A(w) + ((cProduct & 0xffffffff) << 1);
			A(w) = cSum & 0xffffffff;
			cProduct >>= 32;
			cSum >>= 32;
		}
	}
	trim(a);
}


static void mod(struct cdsBigInteger * x, const struct cdsBigInteger * m) {
	int yk = mostSignificantElement(m);
	uint32_t mse = M(yk);
	int shift = 0;
	while ((mse & 0x80000000) == 0) {
		mse <<= 1;
		shift += 1;
	}

	struct cdsBigInteger bi = CDS_BIG_INTEGER_ZERO;
	struct cdsBigInteger * y = &bi;
	smallShiftLeft(y, m, shift);

	if (shift > 0) smallShiftLeft(x, x, shift);

	int xk = mostSignificantElement(x);
	expand(x, xk + 2);


	uint64_t div = Y(yk) + 1;
	for (int d = xk - yk; d >= 0; d--) {


		uint64_t xmsb = ((uint64_t)X(yk + d + 1) << 32) + X(yk + d);
		if (xmsb > div) {
			uint64_t n = xmsb / div;
			subN(x, (uint32_t) n, y, d);
		}

		while (compareShifted(x, y, d) >= 0) {
			subD(x, y, d);
		}

		while (xk >= 0 && X(xk) == 0) xk -= 1;
		x->length = xk + 2;
	}

	if (shift > 0) smallShiftRight(x, x, shift);
	trim(x);
}


static uint32_t montInverse(const struct cdsBigInteger * m) {
	uint64_t q = M(0);
	uint32_t mp = q & 0x3;		// mp = q^-1 mod 2^2 (for odd q)
	mp = (mp * (2 - (q & 0xf) * mp)) & 0xf;	// mp = q^-1 mod 2^4
	mp = (mp * (2 - (q & 0xff) * mp)) & 0xff;	// mp = q^-1 mod 2^8
	mp = (mp * (2 - (q & 0xffff) * mp)) & 0xffff;	// mp = q^-1 mod 2^16
	mp = (mp * (2 - ((q * mp) & 0xffffffff))) & 0xffffffff;	// mp = q^-1 mod 2^32
	return mp > 0 ? (uint32_t) (0x100000000 - mp) : -mp;
}

static void montConversion(struct cdsBigInteger * a, const struct cdsBigInteger * x, const struct cdsBigInteger * m) {
	int mk = mostSignificantElement(m);
	copyD(a, x, mk + 1);

	mod(a, m);
}

static void montConversionOne(struct cdsBigInteger * a, const struct cdsBigInteger * m) {
	int mk = mostSignificantElement(m);
	setZero(a);
	expand(a, mk + 2);
	A(mk + 1) = 1;

	mod(a, m);
}

static void montReduction(struct cdsBigInteger * x, const struct cdsBigInteger * m, uint32_t mp) {
	int mk = mostSignificantElement(m);
	for (int i = 0; i <= mk; i++) {
		uint32_t u = ((uint64_t)X(0) * mp) & 0xffffffff;

		addN(x, u, m, 0);
		for (int n = 0; n + 1 < x->length; n++) X(n) = X(n + 1);
		x->length -= 1;
	}

	if (compare(x, m) >= 0) subD(x, m, 0);
	assert(compare(x, m) < 0);
	trim(x);
}

static void montMul(struct cdsBigInteger * a, struct cdsBigInteger * x, struct cdsBigInteger * y, const struct cdsBigInteger * m, uint32_t mp) {
	int mk = mostSignificantElement(m);
	assert(mostSignificantElement(x) <= mk);
	assert(mostSignificantElement(y) <= mk);
	setZero(a);
	expand(a, mk + 2);
	expand(x, mk + 1);
	expand(y, mk + 1);
	for (int i = 0; i <= mk; i++) {
		uint64_t cProduct = (uint64_t)X(i) * Y(0);
		uint64_t u = (A(0) + cProduct) & 0xffffffff;
		u = (u * mp) & 0xffffffff;

		uint64_t cSum = A(0) + (cProduct & 0xffffffff) + u * M(0);
		cProduct >>= 32;
		cSum >>= 32;
		int n = 1;
		for (; n <= mk; n++) {
			cProduct += (uint64_t)X(i) * Y(n);
			cSum += A(n) + (cProduct & 0xffffffff) + u * M(n);
			A(n - 1) = cSum & 0xffffffff;
			cProduct >>= 32;
			cSum >>= 32;
		}
		cSum += A(n) + (cProduct & 0xffffffff);
		A(n - 1) = cSum & 0xffffffff;
		cProduct >>= 32;
		cSum >>= 32;
		cSum += cProduct & 0xffffffff;
		A(n) = cSum & 0xffffffff;
	}

	if (compare(a, m) >= 0) subD(a, m, 0);
	trim(a);
}

static void modPowSmallExp(struct cdsRSAModPowSmall * this, const struct cdsBigInteger * g, const struct cdsBigInteger * e, const struct cdsBigInteger * m) {
	uint32_t mp = montInverse(m);
	struct cdsBigInteger * gR = &this->gR;
	montConversion(gR, g, m);

	int ek = mostSignificantElement(e);
	uint32_t eMask = 0x80000000;
	while ((E(ek) & eMask) == 0) eMask >>= 1;

	struct cdsBigInteger * aR = &this->bigInteger1;
	copyD(aR, gR, 0);

	struct cdsBigInteger * tR = &this->bigInteger2;
	while (true) {
		eMask >>= 1;
		if (eMask == 0) {
			if (ek == 0) break;
			ek -= 1;
			eMask = 0x80000000;
		}

		setZero(tR);
		sqr(tR, aR);
		montReduction(tR, m, mp);

		if (E(ek) & eMask) {
			setZero(aR);
			montMul(aR, tR, gR, m, mp);
		} else {
			struct cdsBigInteger * temp = aR;
			aR = tR;
			tR = temp;
		}
	}

	montReduction(aR, m, mp);
	this->result = aR;
}

static void modPowBigSwap(struct cdsRSAModPowBig * this) {
	struct cdsBigInteger * temp = this->aR;
	this->aR = this->tR;
	this->tR = temp;
}

static void modPowBigSqrAR(struct cdsRSAModPowBig * this) {
	setZero(this->tR);
	assert(mostSignificantElement(this->aR) < 64);
	sqr(this->tR, this->aR);
	montReduction(this->tR, this->m, this->mp);
	assert(mostSignificantElement(this->tR) < 64);
	modPowBigSwap(this);
}

static void modPowBigFlushSelection(struct cdsRSAModPowBig * this) {
	for (; this->usableBits > 0; this->usableBits--) modPowBigSqrAR(this);
	setZero(this->tR);
	montMul(this->tR, this->aR, this->gR + this->usableSelection, this->m, this->mp);
	assert(mostSignificantElement(this->tR) < 64);
	modPowBigSwap(this);
	for (; this->zeroBits > 0; this->zeroBits--) modPowBigSqrAR(this);

	this->selection = 0;
	this->usableSelection = 0;
}

static void modPowBigResult(struct cdsRSAModPowBig * this) {
	copyD(this->tR, this->aR, 0);
	montReduction(this->tR, this->m, this->mp);
	this->result = this->tR;
}

static void modPowBigExp(struct cdsRSAModPowBig * this, const struct cdsBigInteger * g, const struct cdsBigInteger * e, const struct cdsBigInteger * m) {
	this->m = m;
	this->mp = montInverse(m);

	montConversion(this->gR + 1, g, m);
	montMul(this->gR + 2, this->gR + 1, this->gR + 1, m, this->mp);
	for (int i = 3; i < 64; i += 2)
		montMul(this->gR + i, this->gR + (i - 2), this->gR + 2, m, this->mp);

	this->aR = &this->bigInteger1;
	montConversionOne(this->aR, this->m);
	assert(mostSignificantElement(this->aR) < 64);

	int ek = mostSignificantElement(e);
	uint32_t eMask = 0x80000000;
	while ((E(ek) & eMask) == 0) eMask >>= 1;

	this->selection = 1;	// = usableSelection * 2 ^ zeroBits
	this->usableSelection = 1;
	this->usableBits = 1;
	this->zeroBits = 0;

	this->tR = &this->bigInteger2;
	while (true) {
		eMask >>= 1;
		if (eMask == 0) {
			if (ek == 0) break;
			ek -= 1;
			eMask = 0x80000000;
		}

		if (E(ek) & eMask) {
			if (this->selection > 31) modPowBigFlushSelection(this);
			this->selection = this->selection * 2 + 1;
			this->usableSelection = this->selection;
			this->usableBits += this->zeroBits + 1;
			this->zeroBits = 0;
		} else if (this->usableBits == 0) {
			modPowBigSqrAR(this);
		} else {
			this->selection *= 2;
			this->zeroBits += 1;
		}
	}

	if (this->usableBits > 0) modPowBigFlushSelection(this);
}


static uint32_t sign(const struct cdsBigInteger * x) {
	return x->length > 0 && X(x->length - 1) & 0x80000000 ? 0xffffffff : 0;
}

static void expandS(struct cdsBigInteger * x, int n) {
	assert(n <= CDS_BIG_INTEGER_SIZE);
	uint32_t filler = sign(x);
	while (x->length < n) {
		x->length += 1;
		X(x->length - 1) = filler;
	}
}

static void trimS(struct cdsBigInteger * x) {
	uint32_t filler = sign(x);
	while (x->length > 1 && X(x->length - 1) == filler && ((X(x->length - 1) ^ X(x->length - 2)) & 0x80000000) == 0) x->length -= 1;
}

static void addSU(struct cdsBigInteger * x, struct cdsBigInteger * y) {
	expandS(x, maxLength(x, y) + 1);
	uint64_t c = 0;
	int i = 0;
	for (; i < y->length; i++) {
		c += (uint64_t)X(i) + Y(i);
		X(i) = c & 0xffffffff;
		c >>= 32;
	}
	for (; i < x->length && c != 0; i++) {
		c += (uint64_t)X(i);
		X(i) = c & 0xffffffff;
		c >>= 32;
	}
	trimS(x);
}

static void subSS(struct cdsBigInteger * x, struct cdsBigInteger * y) {
	expandS(x, maxLength(x, y) + 1);
	int64_t c = 0;
	int i = 0;
	for (; i < y->length; i++) {
		c += (int64_t)X(i) - (int64_t)Y(i);
		X(i) = c & 0xffffffff;
		c >>= 32;
	}
	int64_t filler = (int64_t)sign(y);
	for (; i < x->length; i++) {
		c += (int64_t)X(i) - filler;
		X(i) = c & 0xffffffff;
		c >>= 32;
	}
	trimS(x);
}

static void halveS(struct cdsBigInteger * x) {
	int i = 0;
	for (; i + 1 < x->length; i++)
		X(i) = X(i) >> 1 | X(i + 1) << 31;
	X(i) = (uint32_t)((int32_t)X(i) >> 1);
	trimS(x);
}

static void egcd(struct cdsBigInteger * x, struct cdsBigInteger * y, struct cdsBigInteger * a, struct cdsBigInteger * b, struct cdsBigInteger * gcd) {
	struct cdsBigInteger * u = gcd;
	struct cdsBigInteger v = CDS_BIG_INTEGER_ZERO;

	struct cdsBigInteger * A = a;
	struct cdsBigInteger * B = b;
	struct cdsBigInteger C = CDS_BIG_INTEGER_ZERO;
	struct cdsBigInteger D = CDS_BIG_INTEGER_ZERO;

	copyD(u, x, 0);
	copyD(&v, y, 0);

	setUint32(A, 1);
	setZero(B);
	setZero(&C);
	setUint32(&D, 0xffffffff);

	while (true) {
		while (isEven(u)) {
			smallShiftRight(u, u, 1);
			if (isEven(A) && isEven(B)) {
				halveS(A);
				halveS(B);
			} else {
				addSU(A, y);
				halveS(A);
				addSU(B, x);
				halveS(B);
			}
		}

		while (isEven(&v)) {
			smallShiftRight(&v, &v, 1);
			if (isEven(&C) && isEven(&D)) {
				halveS(&C);
				halveS(&D);
			} else {
				addSU(&C, y);
				halveS(&C);
				addSU(&D, x);
				halveS(&D);
			}
		}

		trim(u);
		trim(&v);
		int cmp = compare(u, &v);
		if (cmp == 0) return;

		if (cmp > 0) {
			subD(u, &v, 0);
			trim(u);
			subSS(A, &C);
			subSS(B, &D);
		} else {
			subD(&v, u, 0);
			trim(&v);
			subSS(&C, A);
			subSS(&D, B);
		}
	}
}

static bool modInverse(struct cdsBigInteger * a, struct cdsBigInteger * x, struct cdsBigInteger * m) {
	struct cdsBigInteger b = CDS_BIG_INTEGER_ZERO;
	struct cdsBigInteger gcd = CDS_BIG_INTEGER_ZERO;
	egcd(x, m, a, &b, &gcd);

	if (! isOne(&gcd)) return false;

	while (sign(a) != 0) addSU(a, m);
	trim(a);
	return true;
}


static int removeFactorsOf2(struct cdsBigInteger * x) {
	int d = 0;
	while (X(d) == 0) d += 1;
	if (d > 0) {
		for (int i = 0; i + d < x->length; i++) X(i) = X(i + d);
		x->length = x->length - d;
	}

	if (x->length == 0) return 0;

	int s = 0;
	uint32_t x0 = X(0);
	if ((x0 & 0xffff) == 0) {
		s += 14;
		x0 >>= 16;
	}
	if ((x0 & 0xff) == 0) {
		s += 7;
		x0 >>= 8;
	}
	if ((x0 & 0xf) == 0) {
		s += 4;
		x0 >>= 4;
	}
	if ((x0 & 0x3) == 0) {
		s += 2;
		x0 >>= 2;
	}
	if ((x0 & 0x1) == 0) s += 1;
	if (s > 0) smallShiftRight(x, x, s);
	trim(x);
	return s + 32 * d;
}

static bool millerRabin(struct cdsBigInteger * x, struct cdsRSAModPowBig * modPowBig) {
	struct cdsBigInteger x1 = CDS_BIG_INTEGER_ZERO;
	copyD(&x1, x, 0);
	decrement(&x1);

	struct cdsBigInteger r = CDS_BIG_INTEGER_ZERO;
	copyD(&r, &x1, 0);
	int s = removeFactorsOf2(&r);

	int repeat = 2;
	int xk = mostSignificantElement(x);
	struct cdsBigInteger a = CDS_BIG_INTEGER_ZERO;
	for (int i = 0; i < repeat; i++) {
		setRandom(&a, xk - 1);
		while (isZero(&a) || isOne(&a)) setRandom(&a, xk - 1);

		modPowBigExp(modPowBig, &a, &r, x);
		modPowBigResult(modPowBig);
		if (isOne(modPowBig->result) || compare(modPowBig->result, &x1) == 0) continue;

		int j = 1;
		for (; j < s; j++) {
			modPowBigSqrAR(modPowBig);
			modPowBigResult(modPowBig);
			if (isOne(modPowBig->result)) return false;
			if (compare(modPowBig->result, &x1) == 0) break;
		}
		if (j == s) return false;
	}

	return true;
}

static uint32_t modInt(struct cdsBigInteger * x, uint32_t y) {
	uint64_t c = 0;
	for (int i = mostSignificantElement(x); i >= 0; i--)
		c = ((c << 32) + X(i)) % y;
	return (uint32_t)c;
}


#ifndef KEY_GENERATION_RESET_WATCHDOG
#define KEY_GENERATION_RESET_WATCHDOG() ;
#endif

static const int elementsFor1024Bits = 32;
static const int elementsFor2048Bits = 64;
static int bitCount4[] = {0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4};

static int bitCount(uint32_t n) {
	int count = 0;
	for (; n != 0; n >>= 4)
		count += bitCount4[n & 0xf];
	return count;
}

static void gcd(struct cdsBigInteger * x, struct cdsBigInteger * y) {
	removeFactorsOf2(x);
	removeFactorsOf2(y);
	while (true) {
		int cmp = compare(x, y);
		if (cmp == 0) return;

		if (cmp > 0) {
			subD(x, y, 0);
			removeFactorsOf2(x);
			trim(x);
		} else {
			subD(y, x, 0);
			removeFactorsOf2(y);
			trim(y);
		}
	}
}

static void markInSieve(uint8_t * sieve, uint16_t s, uint16_t interval) {
	for (; s < 4096; s += interval) sieve[s] = 1;
}

static void randomPrime1024(struct cdsBigInteger * x, struct cdsBigInteger * e, struct cdsRSAModPowBig * modPowBig) {
	uint8_t sieve[4096];
	while (true) {
		struct cdsBigInteger start = CDS_BIG_INTEGER_ZERO;
		setRandom(&start, elementsFor1024Bits);
		start.values[0] |= 1;
		start.values[elementsFor1024Bits - 1] |= 0x80000000;

		KEY_GENERATION_RESET_WATCHDOG();
		memset(sieve, 0, 4096);

		for (uint16_t n = 0; n < 4096; n += 2) {
			if (sieve[n]) continue;

			setUint32(x, n);
			addN(x, 1, &start, 0);
			trim(x);


#line 1 "Condensation/../../c/Condensation/RSA64/primality.inc.c"
uint32_t m = modInt(x, 3234846615);
if (m % 3 == 0) {
	markInSieve(sieve, n, 3);
	continue;
}
if (m % 5 == 0) {
	markInSieve(sieve, n, 5);
	continue;
}
if (m % 7 == 0) {
	markInSieve(sieve, n, 7);
	continue;
}
if (m % 11 == 0) {
	markInSieve(sieve, n, 11);
	continue;
}
if (m % 13 == 0) {
	markInSieve(sieve, n, 13);
	continue;
}
if (m % 17 == 0) {
	markInSieve(sieve, n, 17);
	continue;
}
if (m % 19 == 0) {
	markInSieve(sieve, n, 19);
	continue;
}
if (m % 23 == 0) {
	markInSieve(sieve, n, 23);
	continue;
}
if (m % 29 == 0) {
	markInSieve(sieve, n, 29);
	continue;
}
m = modInt(x, 95041567);
if (m % 31 == 0) {
	markInSieve(sieve, n, 31);
	continue;
}
if (m % 37 == 0) {
	markInSieve(sieve, n, 37);
	continue;
}
if (m % 41 == 0) {
	markInSieve(sieve, n, 41);
	continue;
}
if (m % 43 == 0) {
	markInSieve(sieve, n, 43);
	continue;
}
if (m % 47 == 0) {
	markInSieve(sieve, n, 47);
	continue;
}
m = modInt(x, 907383479);
if (m % 53 == 0) {
	markInSieve(sieve, n, 53);
	continue;
}
if (m % 59 == 0) {
	markInSieve(sieve, n, 59);
	continue;
}
if (m % 61 == 0) {
	markInSieve(sieve, n, 61);
	continue;
}
if (m % 67 == 0) {
	markInSieve(sieve, n, 67);
	continue;
}
if (m % 71 == 0) {
	markInSieve(sieve, n, 71);
	continue;
}
m = modInt(x, 4132280413);
if (m % 73 == 0) {
	markInSieve(sieve, n, 73);
	continue;
}
if (m % 79 == 0) {
	markInSieve(sieve, n, 79);
	continue;
}
if (m % 83 == 0) {
	markInSieve(sieve, n, 83);
	continue;
}
if (m % 89 == 0) {
	markInSieve(sieve, n, 89);
	continue;
}
if (m % 97 == 0) {
	markInSieve(sieve, n, 97);
	continue;
}
m = modInt(x, 121330189);
if (m % 101 == 0) {
	markInSieve(sieve, n, 101);
	continue;
}
if (m % 103 == 0) {
	markInSieve(sieve, n, 103);
	continue;
}
if (m % 107 == 0) {
	markInSieve(sieve, n, 107);
	continue;
}
if (m % 109 == 0) {
	markInSieve(sieve, n, 109);
	continue;
}
m = modInt(x, 257557397);
if (m % 113 == 0) {
	markInSieve(sieve, n, 113);
	continue;
}
if (m % 127 == 0) {
	markInSieve(sieve, n, 127);
	continue;
}
if (m % 131 == 0) {
	markInSieve(sieve, n, 131);
	continue;
}
if (m % 137 == 0) {
	markInSieve(sieve, n, 137);
	continue;
}
m = modInt(x, 490995677);
if (m % 139 == 0) {
	markInSieve(sieve, n, 139);
	continue;
}
if (m % 149 == 0) {
	markInSieve(sieve, n, 149);
	continue;
}
if (m % 151 == 0) {
	markInSieve(sieve, n, 151);
	continue;
}
if (m % 157 == 0) {
	markInSieve(sieve, n, 157);
	continue;
}
m = modInt(x, 842952707);
if (m % 163 == 0) {
	markInSieve(sieve, n, 163);
	continue;
}
if (m % 167 == 0) {
	markInSieve(sieve, n, 167);
	continue;
}
if (m % 173 == 0) {
	markInSieve(sieve, n, 173);
	continue;
}
if (m % 179 == 0) {
	markInSieve(sieve, n, 179);
	continue;
}
m = modInt(x, 1314423991);
if (m % 181 == 0) {
	markInSieve(sieve, n, 181);
	continue;
}
if (m % 191 == 0) {
	markInSieve(sieve, n, 191);
	continue;
}
if (m % 193 == 0) {
	markInSieve(sieve, n, 193);
	continue;
}
if (m % 197 == 0) {
	markInSieve(sieve, n, 197);
	continue;
}
m = modInt(x, 2125525169);
if (m % 199 == 0) {
	markInSieve(sieve, n, 199);
	continue;
}
if (m % 211 == 0) {
	markInSieve(sieve, n, 211);
	continue;
}
if (m % 223 == 0) {
	markInSieve(sieve, n, 223);
	continue;
}
if (m % 227 == 0) {
	markInSieve(sieve, n, 227);
	continue;
}
m = modInt(x, 3073309843);
if (m % 229 == 0) {
	markInSieve(sieve, n, 229);
	continue;
}
if (m % 233 == 0) {
	markInSieve(sieve, n, 233);
	continue;
}
if (m % 239 == 0) {
	markInSieve(sieve, n, 239);
	continue;
}
if (m % 241 == 0) {
	markInSieve(sieve, n, 241);
	continue;
}
m = modInt(x, 16965341);
if (m % 251 == 0) {
	markInSieve(sieve, n, 251);
	continue;
}
if (m % 257 == 0) {
	markInSieve(sieve, n, 257);
	continue;
}
if (m % 263 == 0) {
	markInSieve(sieve, n, 263);
	continue;
}
m = modInt(x, 20193023);
if (m % 269 == 0) {
	markInSieve(sieve, n, 269);
	continue;
}
if (m % 271 == 0) {
	markInSieve(sieve, n, 271);
	continue;
}
if (m % 277 == 0) {
	markInSieve(sieve, n, 277);
	continue;
}
m = modInt(x, 23300239);
if (m % 281 == 0) {
	markInSieve(sieve, n, 281);
	continue;
}
if (m % 283 == 0) {
	markInSieve(sieve, n, 283);
	continue;
}
if (m % 293 == 0) {
	markInSieve(sieve, n, 293);
	continue;
}
m = modInt(x, 29884301);
if (m % 307 == 0) {
	markInSieve(sieve, n, 307);
	continue;
}
if (m % 311 == 0) {
	markInSieve(sieve, n, 311);
	continue;
}
if (m % 313 == 0) {
	markInSieve(sieve, n, 313);
	continue;
}
m = modInt(x, 35360399);
if (m % 317 == 0) {
	markInSieve(sieve, n, 317);
	continue;
}
if (m % 331 == 0) {
	markInSieve(sieve, n, 331);
	continue;
}
if (m % 337 == 0) {
	markInSieve(sieve, n, 337);
	continue;
}
m = modInt(x, 42749359);
if (m % 347 == 0) {
	markInSieve(sieve, n, 347);
	continue;
}
if (m % 349 == 0) {
	markInSieve(sieve, n, 349);
	continue;
}
if (m % 353 == 0) {
	markInSieve(sieve, n, 353);
	continue;
}
m = modInt(x, 49143869);
if (m % 359 == 0) {
	markInSieve(sieve, n, 359);
	continue;
}
if (m % 367 == 0) {
	markInSieve(sieve, n, 367);
	continue;
}
if (m % 373 == 0) {
	markInSieve(sieve, n, 373);
	continue;
}
m = modInt(x, 56466073);
if (m % 379 == 0) {
	markInSieve(sieve, n, 379);
	continue;
}
if (m % 383 == 0) {
	markInSieve(sieve, n, 383);
	continue;
}
if (m % 389 == 0) {
	markInSieve(sieve, n, 389);
	continue;
}
m = modInt(x, 65111573);
if (m % 397 == 0) {
	markInSieve(sieve, n, 397);
	continue;
}
if (m % 401 == 0) {
	markInSieve(sieve, n, 401);
	continue;
}
if (m % 409 == 0) {
	markInSieve(sieve, n, 409);
	continue;
}
m = modInt(x, 76027969);
if (m % 419 == 0) {
	markInSieve(sieve, n, 419);
	continue;
}
if (m % 421 == 0) {
	markInSieve(sieve, n, 421);
	continue;
}
if (m % 431 == 0) {
	markInSieve(sieve, n, 431);
	continue;
}
m = modInt(x, 84208541);
if (m % 433 == 0) {
	markInSieve(sieve, n, 433);
	continue;
}
if (m % 439 == 0) {
	markInSieve(sieve, n, 439);
	continue;
}
if (m % 443 == 0) {
	markInSieve(sieve, n, 443);
	continue;
}
m = modInt(x, 94593973);
if (m % 449 == 0) {
	markInSieve(sieve, n, 449);
	continue;
}
if (m % 457 == 0) {
	markInSieve(sieve, n, 457);
	continue;
}
if (m % 461 == 0) {
	markInSieve(sieve, n, 461);
	continue;
}
m = modInt(x, 103569859);
if (m % 463 == 0) {
	markInSieve(sieve, n, 463);
	continue;
}
if (m % 467 == 0) {
	markInSieve(sieve, n, 467);
	continue;
}
if (m % 479 == 0) {
	markInSieve(sieve, n, 479);
	continue;
}
m = modInt(x, 119319383);
if (m % 487 == 0) {
	markInSieve(sieve, n, 487);
	continue;
}
if (m % 491 == 0) {
	markInSieve(sieve, n, 491);
	continue;
}
if (m % 499 == 0) {
	markInSieve(sieve, n, 499);
	continue;
}
m = modInt(x, 133390067);
if (m % 503 == 0) {
	markInSieve(sieve, n, 503);
	continue;
}
if (m % 509 == 0) {
	markInSieve(sieve, n, 509);
	continue;
}
if (m % 521 == 0) {
	markInSieve(sieve, n, 521);
	continue;
}
m = modInt(x, 154769821);
if (m % 523 == 0) {
	markInSieve(sieve, n, 523);
	continue;
}
if (m % 541 == 0) {
	markInSieve(sieve, n, 541);
	continue;
}
if (m % 547 == 0) {
	markInSieve(sieve, n, 547);
	continue;
}
m = modInt(x, 178433279);
if (m % 557 == 0) {
	markInSieve(sieve, n, 557);
	continue;
}
if (m % 563 == 0) {
	markInSieve(sieve, n, 563);
	continue;
}
if (m % 569 == 0) {
	markInSieve(sieve, n, 569);
	continue;
}
m = modInt(x, 193397129);
if (m % 571 == 0) {
	markInSieve(sieve, n, 571);
	continue;
}
if (m % 577 == 0) {
	markInSieve(sieve, n, 577);
	continue;
}
if (m % 587 == 0) {
	markInSieve(sieve, n, 587);
	continue;
}
m = modInt(x, 213479407);
if (m % 593 == 0) {
	markInSieve(sieve, n, 593);
	continue;
}
if (m % 599 == 0) {
	markInSieve(sieve, n, 599);
	continue;
}
if (m % 601 == 0) {
	markInSieve(sieve, n, 601);
	continue;
}
m = modInt(x, 229580147);
if (m % 607 == 0) {
	markInSieve(sieve, n, 607);
	continue;
}
if (m % 613 == 0) {
	markInSieve(sieve, n, 613);
	continue;
}
if (m % 617 == 0) {
	markInSieve(sieve, n, 617);
	continue;
}
m = modInt(x, 250367549);
if (m % 619 == 0) {
	markInSieve(sieve, n, 619);
	continue;
}
if (m % 631 == 0) {
	markInSieve(sieve, n, 631);
	continue;
}
if (m % 641 == 0) {
	markInSieve(sieve, n, 641);
	continue;
}
m = modInt(x, 271661713);
if (m % 643 == 0) {
	markInSieve(sieve, n, 643);
	continue;
}
if (m % 647 == 0) {
	markInSieve(sieve, n, 647);
	continue;
}
if (m % 653 == 0) {
	markInSieve(sieve, n, 653);
	continue;
}
m = modInt(x, 293158127);
if (m % 659 == 0) {
	markInSieve(sieve, n, 659);
	continue;
}
if (m % 661 == 0) {
	markInSieve(sieve, n, 661);
	continue;
}
if (m % 673 == 0) {
	markInSieve(sieve, n, 673);
	continue;
}
m = modInt(x, 319512181);
if (m % 677 == 0) {
	markInSieve(sieve, n, 677);
	continue;
}
if (m % 683 == 0) {
	markInSieve(sieve, n, 683);
	continue;
}
if (m % 691 == 0) {
	markInSieve(sieve, n, 691);
	continue;
}
m = modInt(x, 357349471);
if (m % 701 == 0) {
	markInSieve(sieve, n, 701);
	continue;
}
if (m % 709 == 0) {
	markInSieve(sieve, n, 709);
	continue;
}
if (m % 719 == 0) {
	markInSieve(sieve, n, 719);
	continue;
}
m = modInt(x, 393806449);
if (m % 727 == 0) {
	markInSieve(sieve, n, 727);
	continue;
}
if (m % 733 == 0) {
	markInSieve(sieve, n, 733);
	continue;
}
if (m % 739 == 0) {
	markInSieve(sieve, n, 739);
	continue;
}
m = modInt(x, 422400701);
if (m % 743 == 0) {
	markInSieve(sieve, n, 743);
	continue;
}
if (m % 751 == 0) {
	markInSieve(sieve, n, 751);
	continue;
}
if (m % 757 == 0) {
	markInSieve(sieve, n, 757);
	continue;
}
m = modInt(x, 452366557);
if (m % 761 == 0) {
	markInSieve(sieve, n, 761);
	continue;
}
if (m % 769 == 0) {
	markInSieve(sieve, n, 769);
	continue;
}
if (m % 773 == 0) {
	markInSieve(sieve, n, 773);
	continue;
}
m = modInt(x, 507436351);
if (m % 787 == 0) {
	markInSieve(sieve, n, 787);
	continue;
}
if (m % 797 == 0) {
	markInSieve(sieve, n, 797);
	continue;
}
if (m % 809 == 0) {
	markInSieve(sieve, n, 809);
	continue;
}
m = modInt(x, 547978913);
if (m % 811 == 0) {
	markInSieve(sieve, n, 811);
	continue;
}
if (m % 821 == 0) {
	markInSieve(sieve, n, 821);
	continue;
}
if (m % 823 == 0) {
	markInSieve(sieve, n, 823);
	continue;
}
m = modInt(x, 575204137);
if (m % 827 == 0) {
	markInSieve(sieve, n, 827);
	continue;
}
if (m % 829 == 0) {
	markInSieve(sieve, n, 829);
	continue;
}
if (m % 839 == 0) {
	markInSieve(sieve, n, 839);
	continue;
}
m = modInt(x, 627947039);
if (m % 853 == 0) {
	markInSieve(sieve, n, 853);
	continue;
}
if (m % 857 == 0) {
	markInSieve(sieve, n, 857);
	continue;
}
if (m % 859 == 0) {
	markInSieve(sieve, n, 859);
	continue;
}
m = modInt(x, 666785731);
if (m % 863 == 0) {
	markInSieve(sieve, n, 863);
	continue;
}
if (m % 877 == 0) {
	markInSieve(sieve, n, 877);
	continue;
}
if (m % 881 == 0) {
	markInSieve(sieve, n, 881);
	continue;
}
m = modInt(x, 710381447);
if (m % 883 == 0) {
	markInSieve(sieve, n, 883);
	continue;
}
if (m % 887 == 0) {
	markInSieve(sieve, n, 887);
	continue;
}
if (m % 907 == 0) {
	markInSieve(sieve, n, 907);
	continue;
}
m = modInt(x, 777767161);
if (m % 911 == 0) {
	markInSieve(sieve, n, 911);
	continue;
}
if (m % 919 == 0) {
	markInSieve(sieve, n, 919);
	continue;
}
if (m % 929 == 0) {
	markInSieve(sieve, n, 929);
	continue;
}
m = modInt(x, 834985999);
if (m % 937 == 0) {
	markInSieve(sieve, n, 937);
	continue;
}
if (m % 941 == 0) {
	markInSieve(sieve, n, 941);
	continue;
}
if (m % 947 == 0) {
	markInSieve(sieve, n, 947);
	continue;
}
m = modInt(x, 894826021);
if (m % 953 == 0) {
	markInSieve(sieve, n, 953);
	continue;
}
if (m % 967 == 0) {
	markInSieve(sieve, n, 967);
	continue;
}
if (m % 971 == 0) {
	markInSieve(sieve, n, 971);
	continue;
}
m = modInt(x, 951747481);
if (m % 977 == 0) {
	markInSieve(sieve, n, 977);
	continue;
}
if (m % 983 == 0) {
	markInSieve(sieve, n, 983);
	continue;
}
if (m % 991 == 0) {
	markInSieve(sieve, n, 991);
	continue;
}
m = modInt(x, 1019050649);
if (m % 997 == 0) {
	markInSieve(sieve, n, 997);
	continue;
}
if (m % 1009 == 0) {
	markInSieve(sieve, n, 1009);
	continue;
}
if (m % 1013 == 0) {
	markInSieve(sieve, n, 1013);
	continue;
}
m = modInt(x, 1072651369);
if (m % 1019 == 0) continue;
if (m % 1021 == 0) continue;
if (m % 1031 == 0) continue;
m = modInt(x, 1125878063);
if (m % 1033 == 0) continue;
if (m % 1039 == 0) continue;
if (m % 1049 == 0) continue;
m = modInt(x, 1185362993);
if (m % 1051 == 0) continue;
if (m % 1061 == 0) continue;
if (m % 1063 == 0) continue;
m = modInt(x, 1267745273);
if (m % 1069 == 0) continue;
if (m % 1087 == 0) continue;
if (m % 1091 == 0) continue;
m = modInt(x, 1322520163);
if (m % 1093 == 0) continue;
if (m % 1097 == 0) continue;
if (m % 1103 == 0) continue;
m = modInt(x, 1391119619);
if (m % 1109 == 0) continue;
if (m % 1117 == 0) continue;
if (m % 1123 == 0) continue;
m = modInt(x, 1498299287);
if (m % 1129 == 0) continue;
if (m % 1151 == 0) continue;
if (m % 1153 == 0) continue;
m = modInt(x, 1608372013);
if (m % 1163 == 0) continue;
if (m % 1171 == 0) continue;
if (m % 1181 == 0) continue;
m = modInt(x, 1700725291);
if (m % 1187 == 0) continue;
if (m % 1193 == 0) continue;
if (m % 1201 == 0) continue;
m = modInt(x, 1805418283);
if (m % 1213 == 0) continue;
if (m % 1217 == 0) continue;
if (m % 1223 == 0) continue;
m = modInt(x, 1871456063);
if (m % 1229 == 0) continue;
if (m % 1231 == 0) continue;
if (m % 1237 == 0) continue;
m = modInt(x, 2008071007);
if (m % 1249 == 0) continue;
if (m % 1259 == 0) continue;
if (m % 1277 == 0) continue;
m = modInt(x, 2115193573);
if (m % 1279 == 0) continue;
if (m % 1283 == 0) continue;
if (m % 1289 == 0) continue;
m = modInt(x, 2178429527);
if (m % 1291 == 0) continue;
if (m % 1297 == 0) continue;
if (m % 1301 == 0) continue;
m = modInt(x, 2246284699);
if (m % 1303 == 0) continue;
if (m % 1307 == 0) continue;
if (m % 1319 == 0) continue;
m = modInt(x, 2385788087);
if (m % 1321 == 0) continue;
if (m % 1327 == 0) continue;
if (m % 1361 == 0) continue;
m = modInt(x, 2591986471);
if (m % 1367 == 0) continue;
if (m % 1373 == 0) continue;
if (m % 1381 == 0) continue;
m = modInt(x, 2805004793);
if (m % 1399 == 0) continue;
if (m % 1409 == 0) continue;
if (m % 1423 == 0) continue;
m = modInt(x, 2922149239);
if (m % 1427 == 0) continue;
if (m % 1429 == 0) continue;
if (m % 1433 == 0) continue;
m = modInt(x, 3021320083);
if (m % 1439 == 0) continue;
if (m % 1447 == 0) continue;
if (m % 1451 == 0) continue;
m = modInt(x, 3118412617);
if (m % 1453 == 0) continue;
if (m % 1459 == 0) continue;
if (m % 1471 == 0) continue;
m = modInt(x, 3265932301);
if (m % 1481 == 0) continue;
if (m % 1483 == 0) continue;
if (m % 1487 == 0) continue;
m = modInt(x, 3332392423);
if (m % 1489 == 0) continue;
if (m % 1493 == 0) continue;
if (m % 1499 == 0) continue;
m = modInt(x, 3523218343);
if (m % 1511 == 0) continue;
if (m % 1523 == 0) continue;
if (m % 1531 == 0) continue;
m = modInt(x, 3711836171);
if (m % 1543 == 0) continue;
if (m % 1549 == 0) continue;
if (m % 1553 == 0) continue;
m = modInt(x, 3837879163);
if (m % 1559 == 0) continue;
if (m % 1567 == 0) continue;
if (m % 1571 == 0) continue;
m = modInt(x, 3991792529);
if (m % 1579 == 0) continue;
if (m % 1583 == 0) continue;
if (m % 1597 == 0) continue;
m = modInt(x, 4139646463);
if (m % 1601 == 0) continue;
if (m % 1607 == 0) continue;
if (m % 1609 == 0) continue;
m = modInt(x, 4233155587);
if (m % 1613 == 0) continue;
if (m % 1619 == 0) continue;
if (m % 1621 == 0) continue;
m = modInt(x, 2663399);
if (m % 1627 == 0) continue;
if (m % 1637 == 0) continue;
m = modInt(x, 2755591);
if (m % 1657 == 0) continue;
if (m % 1663 == 0) continue;
m = modInt(x, 2782223);
if (m % 1667 == 0) continue;
if (m % 1669 == 0) continue;
m = modInt(x, 2873021);
if (m % 1693 == 0) continue;
if (m % 1697 == 0) continue;
m = modInt(x, 2903591);
if (m % 1699 == 0) continue;
if (m % 1709 == 0) continue;
m = modInt(x, 2965283);
if (m % 1721 == 0) continue;
if (m % 1723 == 0) continue;
m = modInt(x, 3017153);
if (m % 1733 == 0) continue;
if (m % 1741 == 0) continue;
m = modInt(x, 3062491);
if (m % 1747 == 0) continue;
if (m % 1753 == 0) continue;
m = modInt(x, 3125743);
if (m % 1759 == 0) continue;
if (m % 1777 == 0) continue;
m = modInt(x, 3186221);
if (m % 1783 == 0) continue;
if (m % 1787 == 0) continue;
m = modInt(x, 3221989);
if (m % 1789 == 0) continue;
if (m % 1801 == 0) continue;
m = modInt(x, 3301453);
if (m % 1811 == 0) continue;
if (m % 1823 == 0) continue;
m = modInt(x, 3381857);
if (m % 1831 == 0) continue;
if (m % 1847 == 0) continue;
m = modInt(x, 3474487);
if (m % 1861 == 0) continue;
if (m % 1867 == 0) continue;
m = modInt(x, 3504383);
if (m % 1871 == 0) continue;
if (m % 1873 == 0) continue;
m = modInt(x, 3526883);
if (m % 1877 == 0) continue;
if (m % 1879 == 0) continue;
m = modInt(x, 3590989);
if (m % 1889 == 0) continue;
if (m % 1901 == 0) continue;
m = modInt(x, 3648091);
if (m % 1907 == 0) continue;
if (m % 1913 == 0) continue;
m = modInt(x, 3732623);
if (m % 1931 == 0) continue;
if (m % 1933 == 0) continue;
m = modInt(x, 3802499);
if (m % 1949 == 0) continue;
if (m % 1951 == 0) continue;
m = modInt(x, 3904567);
if (m % 1973 == 0) continue;
if (m % 1979 == 0) continue;
m = modInt(x, 3960091);
if (m % 1987 == 0) continue;
if (m % 1993 == 0) continue;
m = modInt(x, 3992003);
if (m % 1997 == 0) continue;
if (m % 1999 == 0) continue;

#line 955 "Condensation/../../c/Condensation/RSA64/Math.inc.c"
			KEY_GENERATION_RESET_WATCHDOG();
			if (! millerRabin(x, modPowBig)) continue;

			struct cdsBigInteger xme = CDS_BIG_INTEGER_ZERO;
			copyD(&xme, x, 0);
			mod(&xme, e);
			if (isOne(&xme)) continue;

			struct cdsBigInteger x1 = CDS_BIG_INTEGER_ZERO;
			copyD(&x1, x, 0);
			decrement(&x1);
			struct cdsBigInteger e1 = CDS_BIG_INTEGER_ZERO;
			copyD(&e1, e, 0);
			gcd(&x1, &e1);
			if (isOne(&x1)) return;
		}
	}
}

static void generateKey(struct cdsRSAPrivateKey * this, struct cdsRSAModPowBig * modPowBig) {
	struct cdsBigInteger * e = &this->rsaPublicKey.e;
	struct cdsBigInteger * p = &this->p;
	struct cdsBigInteger * q = &this->q;
	struct cdsBigInteger n = CDS_BIG_INTEGER_ZERO;
	struct cdsBigInteger n3 = CDS_BIG_INTEGER_ZERO;

	setUint32(e, 0x10001);
	while (true) {
		randomPrime1024(p, e, modPowBig);

		while (true) {
			randomPrime1024(q, e, modPowBig);

			if (compare(p, q) < 0) {
				struct cdsBigInteger * temp = p;
				p = q;
				q = temp;
			}


			setZero(&n);
			mul(&n, p, q);

			if (mostSignificantElement(&n) != elementsFor2048Bits - 1 || (n.values[elementsFor2048Bits - 1] & 0x80000000) == 0) continue;

			break;
		}

		setZero(&n3);
		addN(&n3, 3, &n, 0);
		int nk = elementsFor2048Bits - 1;  // == mostSignificantElement(n), a condition for quitting the while loop above
		int nafCount = 0;
		for (int i = 0; i <= nk; i++) nafCount += bitCount(n.values[i] ^ n3.values[i]);
		if (nk + 1 < n3.length) nafCount += bitCount(n3.values[nk + 1]);
		if (nafCount < 512) continue;

		break;
	}
}

#line 15 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/RSA64/Encoding.inc.c"
#include <string.h>

static const uint16_t emLength = 256;    // = 2048 / 8
static const uint16_t hashLength = 32;
static const uint8_t OAEPZeroLabelHash[] = {0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14, 0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24, 0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c, 0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55};

static void maskGenerationFunction1(struct cdsBytes seed, struct cdsMutableBytes mask) {
	struct cdsSHA256 sha256;
	uint8_t counter[4] = {0, 0, 0, 0};
	cdsLength blocks = mask.length / 32;
	for (cdsLength i = 0; i < blocks; i++) {
		counter[3] = i;
		cdsInitializeSHA256(&sha256);
		cdsAddBytesToSHA256(&sha256, seed);
		cdsAddBytesToSHA256(&sha256, cdsBytes(counter, 4));
		cdsFinalizeSHA256(&sha256, mask.data + i * 32);
	}
}

static void pssHash(struct cdsBytes digest, struct cdsBytes salt, uint8_t * h) {
	uint8_t sequence[8 + 256 + 222];
	cdsLength sequenceLength = 8 + digest.length + salt.length;
	memset(sequence, 0, 8);
	memcpy(sequence + 8, digest.data, digest.length);
	memcpy(sequence + 8 + digest.length, salt.data, salt.length);
	cdsSHA256(cdsBytes(sequence, sequenceLength), h);
}

static bool verifyPSS(struct cdsBytes digest, struct cdsBytes pss) {
	assert(digest.length <= 256);
	assert(pss.length == 256);
	const uint8_t * em = pss.data;

	if (em[emLength - 1] != 0xbc) return false;

	uint16_t dbLength = emLength - hashLength - 1;	// 223
	uint8_t mask[224];	// rounded up to the next multiple of 32
	maskGenerationFunction1(cdsBytes(em + (emLength - hashLength - 1), hashLength), cdsMutableBytes(mask, 224));
	uint8_t unmasked[224];
	for (uint16_t i = 0; i < dbLength; i++) unmasked[i] = em[i] ^ mask[i];

	unmasked[0] &= 0x7f;

	uint16_t n = 0;
	while (unmasked[n] == 0 && n < dbLength) n++;

	if (unmasked[n] != 0x01) return false;
	n++;

	struct cdsBytes salt = cdsBytes(unmasked + n, dbLength - n);

	uint8_t h[hashLength];
	pssHash(digest, salt, h);

	for (uint16_t i = 0; i < 32; i++)
		if (h[i] != em[dbLength + i]) return false;

	return true;
}

static struct cdsBytes generatePSS(struct cdsBytes digest, uint8_t * em) {
	assert(digest.length <= 256);
	uint16_t dbLength = emLength - hashLength - 1;	// 223

	uint8_t saltBuffer[32];
	struct cdsBytes salt = cdsRandomBytes(saltBuffer, 32);

	em[emLength - 1] = 0xbc;
	pssHash(digest, salt, em + dbLength);

	uint8_t mask[224];
	maskGenerationFunction1(cdsBytes(em + dbLength, hashLength), cdsMutableBytes(mask, 224));

	uint16_t n = 0;
	for (; n < dbLength - salt.length - 1; n++)
		em[n] = mask[n];

	em[n] = 0x01 ^ mask[n];
	n++;

	for (uint16_t i = 0; i < salt.length; i++, n++)
		em[n] = salt.data[i] ^ mask[n];

	em[0] &= 0x7f;

	return cdsBytes(em, emLength);
}

static struct cdsBytes encodeOAEP(struct cdsBytes message, uint8_t * em) {
	uint16_t dbLength = emLength - hashLength - 1;	// 223
	uint8_t db[dbLength];
	memcpy(db, OAEPZeroLabelHash, 32);
	memset(db + 32, 0, dbLength - 32 - message.length - 1);
	db[dbLength - message.length - 1] = 0x01;
	memcpy(db + (dbLength - message.length), message.data, message.length);

	uint8_t seedBuffer[hashLength];
	struct cdsBytes seed = cdsRandomBytes(seedBuffer, hashLength);

	uint8_t dbMask[224];
	maskGenerationFunction1(seed, cdsMutableBytes(dbMask, 224));
	uint16_t n = hashLength + 1;
	for (uint16_t i = 0; i < dbLength; i++, n++)
		em[n] = db[i] ^ dbMask[i];

	uint8_t seedMask[hashLength];
	maskGenerationFunction1(cdsBytes(em + hashLength + 1, dbLength), cdsMutableBytes(seedMask, hashLength));
	em[0] = 0;
	n = 1;
	for (uint16_t i = 0; i < hashLength; i++, n++)
		em[n] = seed.data[i] ^ seedMask[i];

	return cdsBytes(em, emLength);
}

static struct cdsBytes decodeOAEP(struct cdsBytes oaep, uint8_t * message) {
	assert(oaep.length == 256);
	const uint8_t * em = oaep.data;

	uint16_t dbLength = emLength - hashLength - 1;	// 223
	uint8_t seedMask[hashLength];
	maskGenerationFunction1(cdsBytes(em + hashLength + 1, dbLength), cdsMutableBytes(seedMask, hashLength));
	uint8_t seed[hashLength];
	uint16_t n = 1;
	for (uint16_t i = 0; i < hashLength; i++, n++)
		seed[i] = em[n] ^ seedMask[i];

	uint8_t dbMask[224];
	maskGenerationFunction1(cdsBytes(seed, hashLength), cdsMutableBytes(dbMask, 224));

	bool correct = true;

	uint16_t i = 0;
	for (; i < 32; n++, i++) {
		if (OAEPZeroLabelHash[i] != (em[n] ^ dbMask[i])) correct = false;
	}

	for (; em[n] == dbMask[i] && n < emLength; n++) i++;

	if (n >= emLength || (em[n] ^ dbMask[i]) != 0x01) correct = false;
	n++;
	i++;

	uint16_t messageLength = emLength - n;
	for (uint16_t k = 0; n < emLength; n++, i++, k++)
		message[k] = em[n] ^ dbMask[i];

	return correct ? cdsBytes(message, messageLength) : cdsEmpty;
}

#line 16 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/RSA64/PrivateKey.inc.c"

static void precalculateCrtParameters(struct cdsRSAPrivateKey * this) {
	setZero(&this->rsaPublicKey.n);
	mul(&this->rsaPublicKey.n, &this->p, &this->q);

	struct cdsBigInteger p1 = CDS_BIG_INTEGER_ZERO;
	copyD(&p1, &this->p, 0);
	decrement(&p1);

	struct cdsBigInteger q1 = CDS_BIG_INTEGER_ZERO;
	copyD(&q1, &this->q, 0);
	decrement(&q1);

	struct cdsBigInteger phi = CDS_BIG_INTEGER_ZERO;
	mul(&phi, &p1, &q1);

	modInverse(&this->d, &this->rsaPublicKey.e, &phi);

	copyD(&this->dp, &this->d, 0);
	mod(&this->dp, &p1);

	copyD(&this->dq, &this->d, 0);
	mod(&this->dq, &q1);

	modInverse(&this->pInv, &this->p, &this->q);

	modInverse(&this->qInv, &this->q, &this->p);
}

void cdsGeneratePrivateKeyWithMemory(struct cdsRSAPrivateKey * this, struct cdsRSAModPowBig * modPowBig) {
	generateKey(this, modPowBig);
	this->isValid = true;
	this->rsaPublicKey.isValid = true;
	precalculateCrtParameters(this);
}

void cdsGeneratePrivateKey(struct cdsRSAPrivateKey * this) {
	struct cdsRSAModPowBig modPowBig;
	cdsGeneratePrivateKeyWithMemory(this, &modPowBig);
}

void cdsInitializeEmptyPrivateKey(struct cdsRSAPrivateKey * this) {
	this->isValid = false;
	this->rsaPublicKey.isValid = false;
}

void cdsInitializePrivateKey(struct cdsRSAPrivateKey * this, const struct cdsBytes e, const struct cdsBytes p, const struct cdsBytes q) {
	cdsBigIntegerFromBytes(&this->rsaPublicKey.e, e);
	cdsBigIntegerFromBytes(&this->p, p);
	cdsBigIntegerFromBytes(&this->q, q);
	this->isValid = ! isZero(&this->rsaPublicKey.e) && mostSignificantElement(&this->p) + 1 == elementsFor1024Bits && mostSignificantElement(&this->q) + 1 == elementsFor1024Bits;
	this->rsaPublicKey.isValid = this->isValid;
	if (this->isValid) precalculateCrtParameters(this);
}

static struct cdsBytes privateCrypt(const struct cdsRSAPrivateKey * this, const struct cdsBytes inputBytes, uint8_t * resultBuffer, struct cdsRSAPrivateCryptMemory * memory) {
	cdsBigIntegerFromBytes(&memory->input, inputBytes);

	copyD(&memory->imodp, &memory->input, 0);
	mod(&memory->imodp, &this->p);
	modPowBigExp(&memory->modPowBig, &memory->imodp, &this->dp, &this->p);
	modPowBigResult(&memory->modPowBig);
	copyD(&memory->mP, memory->modPowBig.result, 0);

	copyD(&memory->imodq, &memory->input, 0);
	mod(&memory->imodq, &this->q);
	modPowBigExp(&memory->modPowBig, &memory->imodq, &this->dq, &this->q);
	modPowBigResult(&memory->modPowBig);
	copyD(&memory->mQ, memory->modPowBig.result, 0);

	if (compare(&memory->mP, &memory->mQ) > 0) {
		copyD(&memory->difference, &memory->mP, 0);
		subD(&memory->difference, &memory->mQ, 0);
		setZero(&memory->h);
		mul(&memory->h, &this->qInv, &memory->difference);
		mod(&memory->h, &this->p);

		copyD(&memory->result, &memory->mQ, 0);
		mul(&memory->result, &memory->h, &this->q);
	} else {
		copyD(&memory->difference, &memory->mQ, 0);
		subD(&memory->difference, &memory->mP, 0);
		setZero(&memory->h);
		mul(&memory->h, &this->pInv, &memory->difference);
		mod(&memory->h, &this->q);

		copyD(&memory->result, &memory->mP, 0);
		mul(&memory->result, &memory->h, &this->p);
	}

	cdsBytesFromBigInteger(cdsMutableBytes(resultBuffer, 256), &memory->result);
	return cdsBytes(resultBuffer, 256);
};

struct cdsBytes cdsSignWithMemory(const struct cdsRSAPrivateKey * this, const struct cdsBytes digest, uint8_t * resultBuffer, struct cdsRSAPrivateCryptMemory * memory) {
	uint8_t buffer[256];
	struct cdsBytes pss = generatePSS(digest, buffer);

	return privateCrypt(this, pss, resultBuffer, memory);
};

struct cdsBytes cdsSign(const struct cdsRSAPrivateKey * this, const struct cdsBytes digest, uint8_t * resultBuffer) {
	struct cdsRSAPrivateCryptMemory memory;
	return cdsSignWithMemory(this, digest, resultBuffer, &memory);
}

struct cdsBytes cdsDecryptWithMemory(const struct cdsRSAPrivateKey * this, const struct cdsBytes encrypted, uint8_t * resultBuffer, struct cdsRSAPrivateCryptMemory * memory) {
	uint8_t buffer[256];
	struct cdsBytes oaep = privateCrypt(this, encrypted, buffer, memory);

	return decodeOAEP(oaep, resultBuffer);
};

struct cdsBytes cdsDecrypt(const struct cdsRSAPrivateKey * this, const struct cdsBytes encrypted, uint8_t * resultBuffer) {
	struct cdsRSAPrivateCryptMemory memory;
	return cdsDecryptWithMemory(this, encrypted, resultBuffer, &memory);
}


#line 17 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/RSA64/PublicKey.inc.c"

void cdsInitializeEmptyPublicKey(struct cdsRSAPublicKey * this) {
	this->isValid = false;
}

void cdsInitializePublicKey(struct cdsRSAPublicKey * this, const struct cdsBytes e, const struct cdsBytes n) {
	cdsBigIntegerFromBytes(&this->e, e);
	cdsBigIntegerFromBytes(&this->n, n);
	this->isValid = ! isZero(&this->e) && mostSignificantElement(&this->n) + 1 == elementsFor2048Bits;
}

static struct cdsBytes publicCrypt(const struct cdsRSAPublicKey * this, const struct cdsBytes inputBytes, uint8_t * resultBuffer, struct cdsRSAPublicCryptMemory * memory) {
	cdsBigIntegerFromBytes(&memory->input, inputBytes);

	modPowSmallExp(&memory->modPowSmall, &memory->input, &this->e, &this->n);

	cdsBytesFromBigInteger(cdsMutableBytes(resultBuffer, 256), memory->modPowSmall.result);
	return cdsBytes(resultBuffer, 256);
}

bool cdsVerifyWithMemory(const struct cdsRSAPublicKey * this, const struct cdsBytes digest, const struct cdsBytes signature, struct cdsRSAPublicCryptMemory * memory) {
	uint8_t buffer[256];
	struct cdsBytes pss = publicCrypt(this, signature, buffer, memory);

	return verifyPSS(digest, pss);
}

bool cdsVerify(const struct cdsRSAPublicKey * this, const struct cdsBytes digest, const struct cdsBytes signature) {
	struct cdsRSAPublicCryptMemory memory;
	return cdsVerifyWithMemory(this, digest, signature, &memory);
}

struct cdsBytes cdsEncryptWithMemory(const struct cdsRSAPublicKey * this, const struct cdsBytes message, uint8_t * resultBuffer, struct cdsRSAPublicCryptMemory * memory) {
	uint8_t buffer[256];
	struct cdsBytes oaep = encodeOAEP(message, buffer);

	return publicCrypt(this, oaep, resultBuffer, memory);
}

struct cdsBytes cdsEncrypt(const struct cdsRSAPublicKey * this, const struct cdsBytes message, uint8_t * resultBuffer) {
	struct cdsRSAPublicCryptMemory memory;
	return cdsEncryptWithMemory(this, message, resultBuffer, &memory);
}

#line 18 "Condensation/../../c/Condensation/all.inc.c"


#line 1 "Condensation/../../c/Condensation/Serialization/Hash.inc.c"
struct cdsHash invalidHashForDebugging = {{0x49, 0x4e, 0x56, 0x41, 0x4c, 0x49, 0x44, 0x20, 0x48, 0x41, 0x53, 0x48, 0x20, 0x45, 0x52, 0x52, 0x4f, 0x52, 0x20, 0x49, 0x4e, 0x56, 0x41, 0x4c, 0x49, 0x44, 0x20, 0x48, 0x41, 0x53, 0x48, 0x20}};

struct cdsHash cdsHash(const uint8_t * bytes) {
	struct cdsHash hash;
	memcpy(hash.bytes, bytes, 32);
	return hash;
}

struct cdsHash cdsHashFromBytes(const struct cdsBytes hashBytes) {
	struct cdsHash hash;
	if (hashBytes.length >= 32)
		memcpy(hash.bytes, hashBytes.data, 32);
	else
		memset(hash.bytes, 0, 32);
	return hash;
}

struct cdsHash cdsHashFromBytesAtOffset(const struct cdsBytes hashBytes, cdsLength offset) {
	struct cdsHash hash;
	if (hashBytes.length >= offset + 32)
		memcpy(hash.bytes, hashBytes.data + offset, 32);
	else
		memset(hash.bytes, 0, 32);
	return hash;
}

struct cdsHash cdsHashFromHex(const char * hashHex) {
	struct cdsHash hash;
	cdsBytesFromHex(hashHex, hash.bytes, 32);
	return hash;
}

struct cdsHash cdsCalculateHash(const struct cdsBytes bytes) {
	struct cdsHash hash;
	cdsSHA256(bytes, hash.bytes);
	return hash;
}

char * cdsToHex(struct cdsHash * this, char * buffer, cdsLength length) {
	return cdsHexFromBytes(cdsBytes(this->bytes, 32), buffer, length);
}

char * cdsToShortHex(struct cdsHash * this, char * buffer, cdsLength length) {
	cdsHexFromBytes(cdsBytes(this->bytes, 4), buffer, length);
	if (length < 12) return buffer;
	buffer[8] = 0xe2;
	buffer[9] = 0x80;
	buffer[10] = 0xa6;
	buffer[11] = 0;
	return buffer;
}

struct cdsBytes cdsHashBytes(struct cdsHash * this) {
	return cdsBytes(this->bytes, 32);
}

bool cdsEqualHashes(const struct cdsHash * this, const struct cdsHash * that) {
	return memcmp(this->bytes, that->bytes, 32) == 0;
}

int cdsCompareHashes(const struct cdsHash * this, const struct cdsHash * that) {
	return memcmp(this->bytes, that->bytes, 32);
}

#line 20 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/Serialization/HashAndKey.inc.c"
void cdsInitializeEmptyHashAndKey(struct cdsHashAndKey * this) {
	this->key = cdsEmpty;
}

void cdsInitializeHashAndKey(struct cdsHashAndKey * this, struct cdsHash * hash, struct cdsBytes key) {
	memcpy(this->hash.bytes, hash->bytes, 32);
	if (key.length >= 32)
		memcpy(this->keyBytes, key.data, 32);
	else
		memset(this->keyBytes, 0, 32);
	this->key = cdsBytes(this->keyBytes, 32);
}

#line 21 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/Serialization/Object.inc.c"
void cdsInitializeEmptyObject(struct cdsObject * this) {
	this->bytes = cdsEmpty;
	this->hashesCount = 0;
	this->header = cdsEmpty;
	this->data = cdsEmpty;
}

void cdsInitializeObject(struct cdsObject * this, const struct cdsBytes bytes) {
	if (bytes.length < 4) return cdsInitializeEmptyObject(this);

	this->hashesCount = cdsGetUint32BE(bytes.data);
	cdsLength dataStart = (cdsLength) this->hashesCount * 32 + 4;
	if (dataStart > bytes.length) return cdsInitializeEmptyObject(this);

	this->bytes = bytes;
	this->header = cdsByteSlice(bytes, 0, dataStart);
	this->data = cdsByteSlice(bytes, dataStart, bytes.length - dataStart);
}

bool cdsIsValidObject(struct cdsObject * this) {
	return this->bytes.length >= 4;
}

void cdsInitializeCryptedObject(struct cdsObject * this, const struct cdsMutableBytes bytes, const struct cdsBytes key) {
	cdsInitializeObject(this, cdsSeal(bytes));
	if (! cdsIsValidObject(this)) return;

	struct cdsAES256 aes;
	cdsInitializeAES256(&aes, key);
	cdsLength dataStart = (cdsLength) this->hashesCount * 32 + 4;
	cdsCrypt(&aes, this->data, cdsZeroCtr, bytes.data + dataStart);
}

cdsLength cdsObjectByteLength(const struct cdsObject * this) {
	return this->bytes.length;
}

struct cdsHash cdsCalculateObjectHash(const struct cdsObject * this) {
	return cdsCalculateHash(this->bytes);
}

struct cdsHash cdsHashAtIndex(const struct cdsObject * this, uint32_t index) {
	if (index >= this->hashesCount) return invalidHashForDebugging;
	return cdsHashFromBytesAtOffset(this->bytes, (cdsLength) index * 32 + 4);
}

void withObjectHashes(const struct cdsObject * this, cdsHashCallback hashCallback) {
	for (uint32_t i = 0; i < this->hashesCount; i++)
		hashCallback(cdsHashAtIndex(this, i));
}

#line 22 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/Serialization/Record.inc.c"
struct cdsRecord cdsEmptyRecord = {{NULL, 0}, NULL, NULL, NULL};

struct cdsRecord * cdsChild(struct cdsRecord * this, struct cdsBytes bytes) {
	struct cdsRecord * child = this->firstChild;
	while (child) {
		if (cdsEqualBytes(child->bytes, bytes)) return child;
		child = child->nextSibling;
	}

	return &cdsEmptyRecord;
}

struct cdsRecord * cdsChildWithText(struct cdsRecord * this, const char * text) {
	return cdsChild(this, cdsBytesFromText(text));
}

bool cdsContainsChild(struct cdsRecord * this, struct cdsBytes bytes) {
	struct cdsRecord * child = this->firstChild;
	while (child) {
		if (cdsEqualBytes(child->bytes, bytes)) return true;
		child = child->nextSibling;
	}

	return false;
}

bool cdsContainsChildWithText(struct cdsRecord * this, char * text) {
	return cdsContainsChild(this, cdsBytesFromText(text));
}

struct cdsRecord * cdsFirstChild(struct cdsRecord * this) {
	if (this->firstChild) return this->firstChild;
	return &cdsEmptyRecord;
}

int cdsAsText(struct cdsRecord * this, char * buffer, int length) {
	if (length <= 0) return 0;
	size_t textLength = minSize(this->bytes.length, (size_t) length - 1);
	memcpy(buffer, this->bytes.data, textLength);
	buffer[textLength] = 0;
	return textLength;
}

bool cdsAsBoolean(struct cdsRecord * this) {
	return this->bytes.length > 0;
}

int64_t cdsAsInteger64(struct cdsRecord * this) {
	if (this->bytes.length == 0) return 0;

	int64_t value = (int64_t) this->bytes.data[0];
	if ((value & 0x80) > 0) value -= 256;
	for (cdsLength i = 1; i < this->bytes.length; i++)
		value = (value << 8) + ((int64_t) this->bytes.data[i]);

	return value;
}

uint64_t cdsAsUnsigned64(struct cdsRecord * this) {
	uint64_t value = 0;
	for (cdsLength i = 0; i < this->bytes.length; i++)
		value = (value << 8) + ((uint64_t) this->bytes.data[i]);
	return value;
}

int32_t cdsAsInteger(struct cdsRecord * this) {
	int64_t value = cdsAsInteger64(this);
	if (value < -2147483648) return -2147483648;
	if (value > 2147483647) return 2147483647;
	return (int32_t) value;
}

uint32_t cdsAsUnsigned(struct cdsRecord * this) {
	uint64_t value = cdsAsUnsigned64(this);
	if (value > 0xffffffff) return 0xffffffff;
	return (uint32_t) value;
}

bool cdsAsHash(struct cdsRecord * this, struct cdsHash * hash) {
	if (this->hash == NULL) return false;
	memcpy(hash->bytes, this->hash, 32);
	return true;
}

bool cdsAsHashAndKey(struct cdsRecord * this, struct cdsHashAndKey * hashAndKey) {
	if (this->bytes.length != 32) return false;
	if (this->hash == NULL) return false;

	memcpy(hashAndKey->hash.bytes, this->hash, 32);
	memcpy(hashAndKey->keyBytes, this->bytes.data, 32);
	hashAndKey->key = cdsBytes(hashAndKey->keyBytes, 32);
	return true;
}

void cdsAsBigInteger(struct cdsRecord * this, struct cdsBigInteger * bigInteger) {
	cdsBigIntegerFromBytes(bigInteger, this->bytes);
}

struct cdsBytes cdsBytesValue(struct cdsRecord * this) {
	if (! this->firstChild) return cdsEmpty;
	return this->firstChild->bytes;
}

int cdsTextValue(struct cdsRecord * this, char * buffer, int length) {
	if (! this->firstChild) {
		if (length > 0) buffer[0] = 0;
		return 0;
	}

	return cdsAsText(this->firstChild, buffer, length);
}

bool cdsBooleanValue(struct cdsRecord * this) {
	if (! this->firstChild) return false;
	return cdsAsBoolean(this->firstChild);
}

int32_t cdsIntegerValue(struct cdsRecord * this) {
	if (! this->firstChild) return 0;
	return cdsAsInteger(this->firstChild);
}

uint32_t cdsUnsignedValue(struct cdsRecord * this) {
	if (! this->firstChild) return 0U;
	return cdsAsUnsigned(this->firstChild);
}

int64_t cdsInteger64Value(struct cdsRecord * this) {
	if (! this->firstChild) return 0L;
	return cdsAsInteger64(this->firstChild);
}

uint64_t cdsUnsigned64Value(struct cdsRecord * this) {
	if (! this->firstChild) return 0UL;
	return cdsAsUnsigned64(this->firstChild);
}

bool cdsHashValue(struct cdsRecord * this, struct cdsHash * hash) {
	if (! this->firstChild) return false;
	return cdsAsHash(this->firstChild, hash);
}

bool cdsHashAndKeyValue(struct cdsRecord * this, struct cdsHashAndKey * hashAndKey) {
	if (! this->firstChild) return false;
	return cdsAsHashAndKey(this->firstChild, hashAndKey);
}

void cdsBigIntegerValue(struct cdsRecord * this, struct cdsBigInteger * bigInteger) {
	if (! this->firstChild) cdsBigIntegerFromBytes(bigInteger, cdsEmpty);
	cdsAsBigInteger(this->firstChild, bigInteger);
}

#line 23 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/Serialization/RecordBuilder.inc.c"
void cdsInitializeEmptyRecordBuilder(struct cdsRecordBuilder * this) {
	this->bytes = cdsMutableBytes(NULL, 0);
	this->dataOffset = 0;
	this->used = 0;
	this->hashesUsed = 0;
	this->levelPositions[0] = 0;
	this->level = 0;
	this->nextIsChild = 0;
}

void cdsInitializeRecordBuilder(struct cdsRecordBuilder * this, struct cdsMutableBytes bytes, uint32_t hashesCount) {
	this->bytes = bytes;
	cdsSetUint32BE(bytes.data, hashesCount);
	this->dataOffset = 4 + hashesCount * 32;
	this->used = this->dataOffset;
	this->hashesUsed = 0;
	this->levelPositions[0] = 0;
	this->level = 0;
	this->nextIsChild = 0;
}

cdsLength cdsRecordLength(cdsLength length) {
	return (length < 30 ? 1 : length < 255 + 30 ? 2 : 9) + length;
}

cdsLength cdsRecordWithHashLength(cdsLength length) {
	return cdsRecordLength(length) + 36;
}

struct cdsMutableBytes cdsAddRecord(struct cdsRecordBuilder * this, cdsLength length) {
	if (this->used + 9 + length > this->bytes.length) return cdsMutableBytes(NULL, 0);

	if (this->nextIsChild && this->level < CDS_MAX_RECORD_DEPTH - 1) {
		this->nextIsChild -= 1;
		this->bytes.data[this->levelPositions[this->level]] |= 0b01000000;
		this->level += 1;
	} else if (this->level == 0) {
		this->level = 1;
	} else {
		this->bytes.data[this->levelPositions[this->level]] |= 0b10000000;
	}

	this->levelPositions[this->level] = this->used;

	if (length < 30) {
		this->bytes.data[this->used] = length;
		this->used += 1;
	} else if (length < 255 + 30) {
		this->bytes.data[this->used] = 30;
		this->used += 1;
		this->bytes.data[this->used] = length - 30;
		this->used += 1;
	} else {
		this->bytes.data[this->used] = 31;

		cdsLength value = length;
		for (cdsLength i = 0; i < 8; i++) {
			this->bytes.data[this->used + 8 - i] = value & 0xff;
			value >>= 8;
		}

		this->used += 9;
	}

	struct cdsMutableBytes slice = cdsMutableByteSlice(this->bytes, this->used, length);
	this->used += length;
	return slice;
}

void cdsStartChildren(struct cdsRecordBuilder * this) {
	this->nextIsChild += 1;
}

void cdsEndChildren(struct cdsRecordBuilder * this) {
	if (this->nextIsChild) {
		this->nextIsChild -= 1;
		return;
	}

	if (this->level)
		this->level -= 1;
}

void cdsEndRecord(struct cdsRecordBuilder * this) {
	this->nextIsChild = 0;
	this->level = 0;
}

void cdsAppendHash(struct cdsRecordBuilder * this, struct cdsHash hash) {
	if (this->used + 4 > this->bytes.length) return;
	if (this->level < 0) return;
	this->bytes.data[this->levelPositions[this->level]] |= 0b00100000;
	cdsSetUint32BE(this->bytes.data + this->used, this->hashesUsed);
	this->used += 4;
	cdsSetBytes(this->bytes, 4 + 32 * this->hashesUsed, cdsBytes(hash.bytes, 32));
	this->hashesUsed += 1;
}

struct cdsMutableBytes cdsAddBytes(struct cdsRecordBuilder * this, struct cdsBytes bytes) {
	struct cdsMutableBytes slice = cdsAddRecord(this, bytes.length);
	cdsSetBytes(slice, 0, bytes);
	return slice;
}

struct cdsMutableBytes cdsAddText(struct cdsRecordBuilder * this, const char * text) {
	struct cdsBytes bytes = cdsBytesFromText(text);
	struct cdsMutableBytes slice = cdsAddRecord(this, bytes.length);
	cdsSetBytes(slice, 0, bytes);
	return slice;
}

struct cdsMutableBytes cdsAddText2(struct cdsRecordBuilder * this, const char * text1, const char * text2) {
	struct cdsBytes bytes1 = cdsBytesFromText(text1);
	struct cdsBytes bytes2 = cdsBytesFromText(text2);

	struct cdsMutableBytes slice = cdsAddRecord(this, bytes1.length + bytes2.length);
	cdsSetBytes(slice, 0, bytes1);
	cdsSetBytes(slice, bytes1.length, bytes2);
	return slice;
}

void cdsAddInteger(struct cdsRecordBuilder * this, int32_t value) {
	uint8_t bytes[4];
	cdsLength length = 0;

	if (value < 0) {
		while (length < 4) {
			bytes[3 - length] = value & 0xff;
			length++;
			if (value >= -128) break;
			value >>= 8;
		}
	} else {
		while (length < 4) {
			bytes[3 - length] = value & 0xff;
			length++;
			if (value <= 127) break;
			value >>= 8;
		}
	}

	cdsAddBytes(this, cdsBytes(bytes + 4 - length, length));
}

void cdsAddUnsigned(struct cdsRecordBuilder * this, uint32_t value) {
	uint8_t bytes[4];
	cdsLength length = 0;

	while (length < 4) {
		if (value == 0) break;
		bytes[3 - length] = value & 0xff;
		length++;
		value >>= 8;
	}

	cdsAddBytes(this, cdsBytes(bytes + 4 - length, length));
}

void cdsAddInteger64(struct cdsRecordBuilder * this, int64_t value) {
	uint8_t bytes[8];
	cdsLength length = 0;

	if (value < 0) {
		while (length < 8) {
			bytes[7 - length] = value & 0xff;
			length++;
			if (value >= -128) break;
			value >>= 8;
		}
	} else {
		while (length < 8) {
			bytes[7 - length] = value & 0xff;
			length++;
			if (value <= 127) break;
			value >>= 8;
		}
	}

	cdsAddBytes(this, cdsBytes(bytes + 8 - length, length));
}

void cdsAddUnsigned64(struct cdsRecordBuilder * this, uint64_t value) {
	uint8_t bytes[8];
	cdsLength length = 0;

	while (length < 8) {
		if (value == 0) break;
		bytes[7 - length] = value & 0xff;
		length++;
		value >>= 8;
	}

	cdsAddBytes(this, cdsBytes(bytes + 8 - length, length));
}

void cdsAddBigInteger(struct cdsRecordBuilder * this, struct cdsBigInteger * value) {
	uint8_t bytes[256];
	cdsAddBytes(this, cdsBytesFromBigInteger(cdsMutableBytes(bytes, 256), value));
}

void cdsAddFloat32(struct cdsRecordBuilder * this, float value) {
	struct cdsMutableBytes slice = cdsAddRecord(this, 4);
	cdsSetFloat32BE(slice.data, value);
}

void cdsAddFloat64(struct cdsRecordBuilder * this, double value) {
	struct cdsMutableBytes slice = cdsAddRecord(this, 8);
	cdsSetFloat64BE(slice.data, value);
}

struct cdsBytes cdsToObject(struct cdsRecordBuilder * this) {
	return cdsByteSlice(cdsSeal(this->bytes), 0, this->used);
}

struct cdsMutableBytes cdsUsedBytes(struct cdsRecordBuilder * this) {
	return cdsMutableByteSlice(this->bytes, 0, this->used);
}

struct cdsBytes cdsToCryptedObject(struct cdsRecordBuilder * this, struct cdsBytes key) {
	struct cdsAES256 aes;
	cdsInitializeAES256(&aes, key);
	cdsCrypt(&aes, cdsByteSlice(cdsSeal(this->bytes), this->dataOffset, this->used - this->dataOffset), cdsZeroCtr, this->bytes.data + this->dataOffset);
	return cdsByteSlice(cdsSeal(this->bytes), 0, this->used);
}

#line 24 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/Serialization/RecordParser.inc.c"
struct cdsRecord * cdsParseRecord(const struct cdsBytes bytes, struct cdsRecord * records, int length) {
	records[0].bytes = cdsEmpty;
	records[0].hash = NULL;
	records[0].nextSibling = NULL;
	records[0].firstChild = NULL;

	uint32_t hashesCount = cdsGetUint32BE(bytes.data);
	cdsLength pos = 4 + (cdsLength) hashesCount * 32;
	if (pos > bytes.length) return records;

	int usedRecords = 1;
	int level = 1;
	struct cdsRecord * lastSibling[CDS_MAX_RECORD_DEPTH] = {records, NULL, };
	bool hasMoreSiblings[CDS_MAX_RECORD_DEPTH] = {true, };

	while (pos < bytes.length) {
		int flags = bytes.data[pos];
		pos += 1;

		uint64_t byteLength = flags & 0x1f;
		if (byteLength == 30) {
			if (pos + 1 > bytes.length) break;
			byteLength = 30U + bytes.data[pos];
			pos += 1;
		} else if (byteLength == 31) {
			if (pos + 8 > bytes.length) break;
			byteLength = cdsGetUint64BE(bytes.data + pos);
			pos += 8;
		}

		if (pos + byteLength > bytes.length) break;
		records[usedRecords].bytes = cdsByteSlice(bytes, pos, byteLength);
		pos += byteLength;

		if (flags & 0x20) {
			if (pos + 4 > bytes.length) break;
			uint32_t hashIndex = cdsGetUint32BE(bytes.data + pos);
			pos += 4;
			if (hashIndex > hashesCount) break;
			records[usedRecords].hash = bytes.data + 4 + hashIndex * 32;
		} else {
			records[usedRecords].hash = NULL;
		}

		records[usedRecords].firstChild = NULL;
		records[usedRecords].nextSibling = NULL;

		if (lastSibling[level])
			lastSibling[level]->nextSibling = records + usedRecords;
		else
			lastSibling[level - 1]->firstChild = records + usedRecords;

		lastSibling[level] = records + usedRecords;
		hasMoreSiblings[level] = flags & 0x80 ? true : false;

		if (flags & 0x40) {
			level += 1;
			if (level >= 64) break;
			lastSibling[level] = NULL;
		} else {
			while (! hasMoreSiblings[level])
				level -= 1;
		}

		usedRecords += 1;
		if (usedRecords >= length) break;

		if (level == 0) break;
	}

	return records;
}

#line 25 "Condensation/../../c/Condensation/all.inc.c"


#line 1 "Condensation/../../c/Condensation/Actors/PrivateKey.inc.c"
struct cdsBytes cdsPrivateKeyFromBytes(struct cdsRSAPrivateKey * this, const struct cdsBytes bytes) {
	this->isValid = false;

	struct cdsRecord records[16];
	struct cdsRecord * root = cdsParseRecord(bytes, records, 16);

	struct cdsRecord * rsaKey = cdsChildWithText(root, "rsa key");
	struct cdsBytes e = cdsBytesValue(cdsChildWithText(rsaKey, "e"));
	struct cdsBytes p = cdsBytesValue(cdsChildWithText(rsaKey, "p"));
	struct cdsBytes q = cdsBytesValue(cdsChildWithText(rsaKey, "q"));
	cdsInitializePrivateKey(this, e, p, q);
	if (! this->isValid) return cdsEmpty;

	struct cdsBytes publicKeyObjectBytes = cdsBytesValue(cdsChildWithText(root, "public key object"));
	if (publicKeyObjectBytes.length > 500) return cdsEmpty;
	if (publicKeyObjectBytes.length < 100) return cdsEmpty;

	struct cdsObject publicKeyObject;
	cdsInitializeObject(&publicKeyObject, publicKeyObjectBytes);
	if (publicKeyObject.bytes.length == 0) return cdsEmpty;

	return publicKeyObjectBytes;
}

struct cdsBytes cdsSerializePrivateKey(struct cdsRSAPrivateKey * this, struct cdsBytes publicKeyObjectBytes, struct cdsMutableBytes bytes) {
	struct cdsRecordBuilder builder;
	cdsInitializeRecordBuilder(&builder, bytes, 0);

	cdsAddText(&builder, "public key object");
	cdsStartChildren(&builder);
	cdsAddBytes(&builder, publicKeyObjectBytes);
	cdsEndChildren(&builder);

	cdsAddText(&builder, "rsa key");
	cdsStartChildren(&builder);

	cdsAddText(&builder, "e");
	cdsStartChildren(&builder);
	cdsAddBigInteger(&builder, &this->rsaPublicKey.e);
	cdsEndChildren(&builder);

	cdsAddText(&builder, "p");
	cdsStartChildren(&builder);
	cdsAddBigInteger(&builder, &this->p);
	cdsEndChildren(&builder);

	cdsAddText(&builder, "q");
	cdsStartChildren(&builder);
	cdsAddBigInteger(&builder, &this->q);
	cdsEndChildren(&builder);

	cdsEndChildren(&builder);
	return cdsToObject(&builder);
}

#line 27 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/Actors/PublicKey.inc.c"
bool cdsPublicKeyFromBytes(struct cdsRSAPublicKey * this, const struct cdsBytes bytes) {
	if (bytes.length > 500) return false;
	if (bytes.length < 100) return false;

	struct cdsRecord records[16];
	struct cdsRecord * root = cdsParseRecord(bytes, records, 16);
	struct cdsBytes e = cdsBytesValue(cdsChildWithText(root, "e"));
	struct cdsBytes n = cdsBytesValue(cdsChildWithText(root, "n"));
	cdsInitializePublicKey(this, e, n);
	return this->isValid;
}

struct cdsBytes cdsSerializePublicKey(struct cdsRSAPublicKey * this, struct cdsMutableBytes bytes) {
	struct cdsRecordBuilder builder;
	cdsInitializeRecordBuilder(&builder, bytes, 0);

	cdsAddText(&builder, "e");
	cdsStartChildren(&builder);
	cdsAddBigInteger(&builder, &this->e);
	cdsEndChildren(&builder);

	cdsAddText(&builder, "n");
	cdsStartChildren(&builder);
	cdsAddBigInteger(&builder, &this->n);
	cdsEndChildren(&builder);

	return cdsToObject(&builder);
}

#line 28 "Condensation/../../c/Condensation/all.inc.c"

#line 8 "Condensation/C.inc.c"

static struct cdsBytes bytesFromSV(SV * sv) {
	if (! SvPOK(sv)) return cdsEmpty;
	return cdsBytes((const uint8_t *) SvPVX(sv), SvCUR(sv));
}

static SV * svFromBytes(struct cdsBytes bytes) {
	return newSVpvn((const char *) bytes.data, bytes.length);
}

static SV * svFromBigInteger(struct cdsBigInteger * bigInteger) {
	uint8_t buffer[256];
	struct cdsBytes bytes = cdsBytesFromBigInteger(cdsMutableBytes(buffer, 256), bigInteger);
	return newSVpvn((const char *) bytes.data, bytes.length);
}


SV * randomBytes(SV * svCount) {
	int count = SvIV(svCount);
	if (count > 256) count = 256;
	if (count < 0) count = 0;
	uint8_t buffer[256];
	return svFromBytes(cdsRandomBytes(buffer, count));
}


SV * sha256(SV * svBytes) {
	uint8_t buffer[32];
	struct cdsBytes hash = cdsSHA256(bytesFromSV(svBytes), buffer);
	return svFromBytes(hash);
}


SV * aesCrypt(SV * svBytes, SV * svKey, SV * svStartCounter) {
	struct cdsBytes bytes = bytesFromSV(svBytes);
	struct cdsBytes key = bytesFromSV(svKey);
	if (key.length != 32) return &PL_sv_undef;
	struct cdsBytes startCounter = bytesFromSV(svStartCounter);
	if (startCounter.length != 16) return &PL_sv_undef;

	SV * svResult = newSV(bytes.length < 1 ? 1 : bytes.length);	// newSV(0) has different semantics
	struct cdsAES256 aes;
	cdsInitializeAES256(&aes, key);
	cdsCrypt(&aes, bytes, startCounter, (uint8_t *) SvPVX(svResult));

	SvPOK_only(svResult);
	SvCUR_set(svResult, bytes.length);
	return svResult;
}

SV * counterPlusInt(SV * svCounter, SV * svAdd) {
	struct cdsBytes counter = bytesFromSV(svCounter);
	if (counter.length != 16) return &PL_sv_undef;
	int add = SvIV(svAdd);

	uint8_t buffer[16];
	struct cdsMutableBytes result = cdsMutableBytes(buffer, 16);
	for (int i = 15; i >= 0; i--) {
		add += counter.data[i];
		result.data[i] = add & 0xff;
		add = add >> 8;
	}

	return svFromBytes(cdsSeal(result));
}


static struct cdsRSAPrivateKey * privateKeyFromSV(SV * sv) {
	if (! SvPOK(sv)) return NULL;
	STRLEN length;
	struct cdsRSAPrivateKey * key = (struct cdsRSAPrivateKey *) SvPV(sv, length);
	return length == sizeof(struct cdsRSAPrivateKey) ? key : NULL;
}

SV * privateKeyGenerate() {
	struct cdsRSAPrivateKey key;
	cdsGeneratePrivateKey(&key);
	SV * obj = newSVpvn((char *) &key, sizeof(struct cdsRSAPrivateKey));
	SvREADONLY_on(obj);
	return obj;
}

SV * privateKeyNew(SV * svE, SV * svP, SV * svQ) {
	struct cdsRSAPrivateKey key;
	cdsInitializePrivateKey(&key, bytesFromSV(svE), bytesFromSV(svP), bytesFromSV(svQ));
	if (! key.isValid) return &PL_sv_undef;
	SV * obj = newSVpvn((char *) &key, sizeof(struct cdsRSAPrivateKey));
	SvREADONLY_on(obj);
	return obj;
}

SV * privateKeyE(SV * svThis) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;
	return svFromBigInteger(&this->rsaPublicKey.e);
}

SV * privateKeyP(SV * svThis) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;
	return svFromBigInteger(&this->p);
}

SV * privateKeyQ(SV * svThis) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;
	return svFromBigInteger(&this->q);
}

SV * privateKeyD(SV * svThis) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;
	return svFromBigInteger(&this->d);
}

SV * privateKeySign(SV * svThis, SV * svDigest) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	uint8_t buffer[256];
	struct cdsBytes signature = cdsSign(this, bytesFromSV(svDigest), buffer);
	return svFromBytes(signature);
}

SV * privateKeyVerify(SV * svThis, SV * svDigest, SV * svSignature) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	bool ok = cdsVerify(&this->rsaPublicKey, bytesFromSV(svDigest), bytesFromSV(svSignature));
	return ok ? &PL_sv_yes : &PL_sv_no;
}

SV * privateKeyEncrypt(SV * svThis, SV * svMessage) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	uint8_t buffer[256];
	struct cdsBytes encrypted = cdsEncrypt(&this->rsaPublicKey, bytesFromSV(svMessage), buffer);
	return svFromBytes(encrypted);
}

SV * privateKeyDecrypt(SV * svThis, SV * svMessage) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	uint8_t buffer[256];
	struct cdsBytes decrypted = cdsDecrypt(this, bytesFromSV(svMessage), buffer);
	return svFromBytes(decrypted);
}


static struct cdsRSAPublicKey * publicKeyFromSV(SV * sv) {
	if (! SvPOK(sv)) return NULL;
	STRLEN length;
	struct cdsRSAPublicKey * key = (struct cdsRSAPublicKey *) SvPV(sv, length);
	return length == sizeof(struct cdsRSAPublicKey) ? key : NULL;
}

SV * publicKeyFromPrivateKey(SV * svPrivateKey) {
	struct cdsRSAPrivateKey * key = privateKeyFromSV(svPrivateKey);

	struct cdsRSAPublicKey publicKey;
	memcpy(&publicKey.e, &key->rsaPublicKey.e, sizeof(struct cdsBigInteger));
	memcpy(&publicKey.n, &key->rsaPublicKey.n, sizeof(struct cdsBigInteger));

	SV * obj = newSVpvn((char *) &publicKey, sizeof(struct cdsRSAPublicKey));
	SvREADONLY_on(obj);
	return obj;
}

SV * publicKeyNew(SV * svE, SV * svN) {
	struct cdsRSAPublicKey key;
	cdsInitializePublicKey(&key, bytesFromSV(svE), bytesFromSV(svN));
	if (! key.isValid) return &PL_sv_undef;
	SV * obj = newSVpvn((char *) &key, sizeof(struct cdsRSAPublicKey));
	SvREADONLY_on(obj);
	return obj;
}

SV * publicKeyE(SV * svThis) {
	struct cdsRSAPublicKey * this = publicKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;
	return svFromBigInteger(&this->e);
}

SV * publicKeyN(SV * svThis) {
	struct cdsRSAPublicKey * this = publicKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;
	return svFromBigInteger(&this->n);
}

SV * publicKeyVerify(SV * svThis, SV * svDigest, SV * svSignature) {
	struct cdsRSAPublicKey * this = publicKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	bool ok = cdsVerify(this, bytesFromSV(svDigest), bytesFromSV(svSignature));
	return ok ? &PL_sv_yes : &PL_sv_no;
}

SV * publicKeyEncrypt(SV * svThis, SV * svMessage) {
	struct cdsRSAPublicKey * this = publicKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	uint8_t buffer[256];
	struct cdsBytes encrypted = cdsEncrypt(this, bytesFromSV(svMessage), buffer);
	return svFromBytes(encrypted);
}


SV * performanceStart() {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	SV * obj = newSVpvn((char *) &ts, sizeof(struct timespec));
	SvREADONLY_on(obj);
	return obj;
}

static struct timespec * timerFromSV(SV * sv) {
	if (! SvPOK(sv)) return NULL;
	STRLEN length;
	struct timespec * ts = (struct timespec *) SvPV(sv, length);
	return length == sizeof(struct timespec) ? ts : NULL;
}

SV * performanceElapsed(SV * svThis) {
	struct timespec * this = timerFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	time_t dsec = ts.tv_sec - this->tv_sec;
	long dnano = ts.tv_nsec - this->tv_nsec;

	long diff = (long) dsec * 1000 * 1000 + dnano / 1000;
	return newSViv(diff);
}
