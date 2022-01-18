# This is the Condensation Perl Module 0.23 (actor) built on 2022-01-18.
# See https://condensation.io for information about the Condensation Data System.

use strict;
use warnings;
use 5.010000;

use Digest::SHA;
use Encode;
use HTTP::Headers;
use HTTP::Request;
use LWP::UserAgent;
use Time::Local;
use utf8;
package CDS;

our $VERSION = '0.23';
our $edition = 'actor';
our $releaseDate = '2022-01-18';

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
# To converte text, use Encode::encode_utf8($text) and Encode::decode_utf8($bytes).
# To converte hex sequences, use pack('H*', $hex) and unpack('H*', $bytes).

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

sub bytesFromBoolean {
	my $class = shift;
	my $value = shift;
	 $value ? 'y' : '' }

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

sub booleanFromBytes {
	my $class = shift;
	my $bytes = shift;

	return length $bytes > 0;
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

### Open envelopes ###

sub verifyEnvelopeSignature {
	my $class = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
	my $publicKey = shift; die 'wrong type '.ref($publicKey).' for $publicKey' if defined $publicKey && ref $publicKey ne 'CDS::PublicKey';
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	# Read the signature
	my $signature = $envelope->child('signature')->bytesValue;
	return if length $signature < 1;

	# Verify the signature
	return if ! $publicKey->verifyHash($hash, $signature);
	return 1;
}

package CDS::ActorGroup;

# Members must be sorted in descending revision order, such that the member with the most recent revision is first. Members must not include any revoked actors.
sub new {
	my $class = shift;
	my $members = shift;
	my $entrustedActorsRevision = shift;
	my $entrustedActors = shift;

	# Create the cache for the "contains" method
	my $containCache = {};
	for my $member (@$members) {
		$containCache->{$member->actorOnStore->publicKey->hash->bytes} = 1;
	}

	return bless {
		members => $members,
		entrustedActorsRevision => $entrustedActorsRevision,
		entrustedActors => $entrustedActors,
		containsCache => $containCache,
		};
}

sub members {
	my $o = shift;
	 @{$o->{members}} }
sub entrustedActorsRevision { shift->{entrustedActorsRevision} }
sub entrustedActors {
	my $o = shift;
	 @{$o->{entrustedActors}} }

# Checks whether the actor group contains at least one active member.
sub isActive {
	my $o = shift;

	for my $member (@{$o->{members}}) {
		return 1 if $member->isActive;
	}
	return;
}

# Returns the most recent active member, the most recent idle member, or undef if the group is empty.
sub leader {
	my $o = shift;

	for my $member (@{$o->{members}}) {
		return $member if $member->isActive;
	}
	return $o->{members}->[0];
}

# Returns true if the account belongs to this actor group.
# Note that multiple (different) actor groups may claim that the account belongs to them. In practice, an account usually belongs to one actor group.
sub contains {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

	return exists $o->{containsCache}->{$actorHash->bytes};
}

# Returns true if the account is entrusted by this actor group.
sub entrusts {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

	for my $actor (@{$o->{entrustedActors}}) {
		return 1 if $actorHash->equals($actor->publicKey->hash);
	}
	return;
}

# Returns all public keys.
sub publicKeys {
	my $o = shift;

	my @publicKeys;
	for my $member (@{$o->{members}}) {
		push @publicKeys, $member->actorOnStore->publicKey;
	}
	for my $actor (@{$o->{entrustedActors}}) {
		push @publicKeys, $actor->actorOnStore->publicKey;
	}
	return @publicKeys;
}

# Returns an ActorGroupBuilder with all members and entrusted keys of this ActorGroup.
sub toBuilder {
	my $o = shift;

	my $builder = CDS::ActorGroupBuilder->new;
	$builder->mergeEntrustedActors($o->{entrustedActorsRevision});
	for my $member (@{$o->{members}}) {
		my $publicKey = $member->actorOnStore->publicKey;
		$builder->addKnownPublicKey($publicKey);
		$builder->addMember($publicKey->hash, $member->storeUrl, $member->revision, $member->isActive ? 'active' : 'idle');
	}
	for my $actor (@{$o->{entrustedActors}}) {
		my $publicKey = $actor->actorOnStore->publicKey;
		$builder->addKnownPublicKey($publicKey);
		$builder->addEntrustedActor($publicKey->hash, $actor->storeUrl);
	}
	return $builder;
}

package CDS::ActorGroup::EntrustedActor;

sub new {
	my $class = shift;
	my $actorOnStore = shift; die 'wrong type '.ref($actorOnStore).' for $actorOnStore' if defined $actorOnStore && ref $actorOnStore ne 'CDS::ActorOnStore';
	my $storeUrl = shift;

	return bless {
		actorOnStore => $actorOnStore,
		storeUrl => $storeUrl,
		};
}

sub actorOnStore { shift->{actorOnStore} }
sub storeUrl { shift->{storeUrl} }

package CDS::ActorGroup::Member;

sub new {
	my $class = shift;
	my $actorOnStore = shift; die 'wrong type '.ref($actorOnStore).' for $actorOnStore' if defined $actorOnStore && ref $actorOnStore ne 'CDS::ActorOnStore';
	my $storeUrl = shift;
	my $revision = shift;
	my $isActive = shift;

	return bless {
		actorOnStore => $actorOnStore,
		storeUrl => $storeUrl,
		revision => $revision,
		isActive => $isActive,
		};
}

sub actorOnStore { shift->{actorOnStore} }
sub storeUrl { shift->{storeUrl} }
sub revision { shift->{revision} }
sub isActive { shift->{isActive} }

package CDS::ActorGroupBuilder;

sub new {
	my $class = shift;

	return bless {
		knownPublicKeys => {},			# A hashref of known public keys (e.g. from the existing actor group)
		members => {},					# Members by URL
		entrustedActorsRevision => 0,	# Revision of the list of entrusted actors
		entrustedActors => {},			# Entrusted actors by hash
		};
}

sub members {
	my $o = shift;
	 values %{$o->{members}} }
sub entrustedActorsRevision { shift->{entrustedActorsRevision} }
sub entrustedActors {
	my $o = shift;
	 values %{$o->{entrustedActors}} }
sub knownPublicKeys { shift->{knownPublicKeys} }

sub addKnownPublicKey {
	my $o = shift;
	my $publicKey = shift; die 'wrong type '.ref($publicKey).' for $publicKey' if defined $publicKey && ref $publicKey ne 'CDS::PublicKey';

	$o->{publicKeys}->{$publicKey->hash->bytes} = $publicKey;
}

sub addMember {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $storeUrl = shift;
	my $revision = shift // 0;
	my $status = shift // 'active';

	my $url = $storeUrl.'/accounts/'.$hash->hex;
	my $member = $o->{members}->{$url};
	return if $member && $revision <= $member->revision;
	$o->{members}->{$url} = CDS::ActorGroupBuilder::Member->new($hash, $storeUrl, $revision, $status);
	return 1;
}

sub removeMember {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $storeUrl = shift;

	my $url = $storeUrl.'/accounts/'.$hash->hex;
	delete $o->{members}->{$url};
}

sub parseMembers {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $linkedPublicKeys = shift;

	die 'linked public keys?' if ! defined $linkedPublicKeys;
	for my $storeRecord ($record->children) {
		my $accountStoreUrl = $storeRecord->asText;

		for my $statusRecord ($storeRecord->children) {
			my $status = $statusRecord->bytes;

			for my $child ($statusRecord->children) {
				my $hash = $linkedPublicKeys ? $child->hash : CDS::Hash->fromBytes($child->bytes);
				$o->addMember($hash // next, $accountStoreUrl, $child->integerValue, $status);
			}
		}
	}
}

sub mergeEntrustedActors {
	my $o = shift;
	my $revision = shift;

	return if $revision <= $o->{entrustedActorsRevision};
	$o->{entrustedActorsRevision} = $revision;
	$o->{entrustedActors} = {};
	return 1;
}

sub addEntrustedActor {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $storeUrl = shift;

	my $actor = CDS::ActorGroupBuilder::EntrustedActor->new($hash, $storeUrl);
	$o->{entrustedActors}->{$hash->bytes} = $actor;
}

sub removeEntrustedActor {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	delete $o->{entrustedActors}->{$hash->bytes};
}

sub parseEntrustedActors {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $linkedPublicKeys = shift;

	for my $revisionRecord ($record->children) {
		next if ! $o->mergeEntrustedActors($revisionRecord->asInteger);
		$o->parseEntrustedActorList($revisionRecord, $linkedPublicKeys);
	}
}

sub parseEntrustedActorList {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $linkedPublicKeys = shift;

	die 'linked public keys?' if ! defined $linkedPublicKeys;
	for my $storeRecord ($record->children) {
		my $storeUrl = $storeRecord->asText;

		for my $child ($storeRecord->children) {
			my $hash = $linkedPublicKeys ? $child->hash : CDS::Hash->fromBytes($child->bytes);
			$o->addEntrustedActor($hash // next, $storeUrl);
		}
	}
}

sub parse {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $linkedPublicKeys = shift;

	$o->parseMembers($record->child('actor group'), $linkedPublicKeys);
	$o->parseEntrustedActors($record->child('entrusted actors'), $linkedPublicKeys);
}

sub load {
	my $o = shift;
	my $store = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $delegate = shift;

	return CDS::LoadActorGroup->load($o, $store, $keyPair, $delegate);
}

sub discover {
	my $o = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $delegate = shift;

	return CDS::DiscoverActorGroup->discover($o, $keyPair, $delegate);
}

# Serializes the actor group to a record that can be passed to parse.
sub addToRecord {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $linkedPublicKeys = shift;

	die 'linked public keys?' if ! defined $linkedPublicKeys;

	my $actorGroupRecord = $record->add('actor group');
	my $currentStoreUrl = undef;
	my $currentStoreRecord = undef;
	my $currentStatus = undef;
	my $currentStatusRecord = undef;
	for my $member (sort { $a->storeUrl cmp $b->storeUrl || CDS->booleanCompare($b->status, $a->status) } $o->members) {
		next if ! $member->revision;

		if (! defined $currentStoreUrl || $currentStoreUrl ne $member->storeUrl) {
			$currentStoreUrl = $member->storeUrl;
			$currentStoreRecord = $actorGroupRecord->addText($currentStoreUrl);
			$currentStatus = undef;
			$currentStatusRecord = undef;
		}

		if (! defined $currentStatus || $currentStatus ne $member->status) {
			$currentStatus = $member->status;
			$currentStatusRecord = $currentStoreRecord->add($currentStatus);
		}

		my $hashRecord = $linkedPublicKeys ? $currentStatusRecord->addHash($member->hash) : $currentStatusRecord->add($member->hash->bytes);
		$hashRecord->addInteger($member->revision);
	}

	if ($o->{entrustedActorsRevision}) {
		my $listRecord = $o->entrustedActorListToRecord($linkedPublicKeys);
		$record->add('entrusted actors')->addInteger($o->{entrustedActorsRevision})->addRecord($listRecord->children);
	}
}

sub toRecord {
	my $o = shift;
	my $linkedPublicKeys = shift;

	my $record = CDS::Record->new;
	$o->addToRecord($record, $linkedPublicKeys);
	return $record;
}

sub entrustedActorListToRecord {
	my $o = shift;
	my $linkedPublicKeys = shift;

	my $record = CDS::Record->new;
	my $currentStoreUrl = undef;
	my $currentStoreRecord = undef;
	for my $actor ($o->entrustedActors) {
		if (! defined $currentStoreUrl || $currentStoreUrl ne $actor->storeUrl) {
			$currentStoreUrl = $actor->storeUrl;
			$currentStoreRecord = $record->addText($currentStoreUrl);
		}

		$linkedPublicKeys ? $currentStoreRecord->addHash($actor->hash) : $currentStoreRecord->add($actor->hash->bytes);
	}

	return $record;
}

package CDS::ActorGroupBuilder::EntrustedActor;

sub new {
	my $class = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $storeUrl = shift;

	return bless {
		hash => $hash,
		storeUrl => $storeUrl,
		};
}

sub hash { shift->{hash} }
sub storeUrl { shift->{storeUrl} }

package CDS::ActorGroupBuilder::Member;

sub new {
	my $class = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $storeUrl = shift;
	my $revision = shift;
	my $status = shift;

	return bless {
		hash => $hash,
		storeUrl => $storeUrl,
		revision => $revision,
		status => $status,
		};
}

sub hash { shift->{hash} }
sub storeUrl { shift->{storeUrl} }
sub revision { shift->{revision} }
sub status { shift->{status} }

# A public key and a store.
package CDS::ActorOnStore;

sub new {
	my $class = shift;
	my $publicKey = shift; die 'wrong type '.ref($publicKey).' for $publicKey' if defined $publicKey && ref $publicKey ne 'CDS::PublicKey';
	my $store = shift;

	return bless {
		publicKey => $publicKey,
		store => $store
		};
}

sub publicKey { shift->{publicKey} }
sub store { shift->{store} }

sub equals {
	my $this = shift;
	my $that = shift;

	return 1 if ! defined $this && ! defined $that;
	return if ! defined $this || ! defined $that;
	return $this->{store}->id eq $that->{store}->id && $this->{publicKey}->{hash}->equals($that->{publicKey}->{hash});
}

package CDS::ActorWithDocument;

sub new {
	my $class = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $storageStore = shift;
	my $messagingStore = shift;
	my $messagingStoreUrl = shift;
	my $publicKeyCache = shift;

	my $o = bless {
		keyPair => $keyPair,
		storageStore => $storageStore,
		messagingStore => $messagingStore,
		messagingStoreUrl => $messagingStoreUrl,
		groupDataHandlers => [],
		}, $class;

	# Private data on the storage store
	$o->{storagePrivateRoot} = CDS::PrivateRoot->new($keyPair, $storageStore, $o);
	$o->{groupDocument} = CDS::RootDocument->new($o->{storagePrivateRoot}, 'group data');
	$o->{localDocument} = CDS::RootDocument->new($o->{storagePrivateRoot}, 'local data');

	# Private data on the messaging store
	$o->{messagingPrivateRoot} = $storageStore->id eq $messagingStore->id ? $o->{storagePrivateRoot} : CDS::PrivateRoot->new($keyPair, $messagingStore, $o);
	$o->{sentList} = CDS::SentList->new($o->{messagingPrivateRoot});
	$o->{sentListReady} = 0;

	# Group data sharing
	$o->{groupDataSharer} = CDS::GroupDataSharer->new($o);
	$o->{groupDataSharer}->addDataHandler($o->{groupDocument}->label, $o->{groupDocument});

	# Selectors
	$o->{groupRoot} = $o->{groupDocument}->root;
	$o->{localRoot} = $o->{localDocument}->root;
	$o->{publicDataSelector} = $o->{groupRoot}->child('public data');
	$o->{actorGroupSelector} = $o->{groupRoot}->child('actor group');
	$o->{actorSelector} = $o->{actorGroupSelector}->child(substr($keyPair->publicKey->hash->bytes, 0, 16));
	$o->{entrustedActorsSelector} = $o->{groupRoot}->child('entrusted actors');

	# Message reader
	my $pool = CDS::MessageBoxReaderPool->new($keyPair, $publicKeyCache, $o);
	$o->{messageBoxReader} = CDS::MessageBoxReader->new($pool, CDS::ActorOnStore->new($keyPair->publicKey, $messagingStore), CDS->HOUR);

	# Active actor group members and entrusted keys
	$o->{cachedGroupDataMembers} = {};
	$o->{cachedEntrustedKeys} = {};
	return $o;
}

sub keyPair { shift->{keyPair} }
sub storageStore { shift->{storageStore} }
sub messagingStore { shift->{messagingStore} }
sub messagingStoreUrl { shift->{messagingStoreUrl} }

sub storagePrivateRoot { shift->{storagePrivateRoot} }
sub groupDocument { shift->{groupDocument} }
sub localDocument { shift->{localDocument} }

sub messagingPrivateRoot { shift->{messagingPrivateRoot} }
sub sentList { shift->{sentList} }
sub sentListReady { shift->{sentListReady} }

sub groupDataSharer { shift->{groupDataSharer} }

sub groupRoot { shift->{groupRoot} }
sub localRoot { shift->{localRoot} }
sub publicDataSelector { shift->{publicDataSelector} }
sub actorGroupSelector { shift->{actorGroupSelector} }
sub actorSelector { shift->{actorSelector} }
sub entrustedActorsSelector { shift->{entrustedActorsSelector} }

### Our own actor ###

sub isMe {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

	return $o->{keyPair}->publicKey->hash->equals($actorHash);
}

sub setName {
	my $o = shift;
	my $name = shift;

	$o->{actorSelector}->child('name')->set($name);
}

sub getName {
	my $o = shift;

	return $o->{actorSelector}->child('name')->textValue;
}

sub updateMyRegistration {
	my $o = shift;

	$o->{actorSelector}->addObject($o->{keyPair}->publicKey->hash, $o->{keyPair}->publicKey->object);
	my $record = CDS::Record->new;
	$record->add('hash')->addHash($o->{keyPair}->publicKey->hash);
	$record->add('store')->addText($o->{messagingStoreUrl});
	$o->{actorSelector}->set($record);
}

sub setMyActiveFlag {
	my $o = shift;
	my $flag = shift;

	$o->{actorSelector}->child('active')->setBoolean($flag);
}

sub setMyGroupDataFlag {
	my $o = shift;
	my $flag = shift;

	$o->{actorSelector}->child('group data')->setBoolean($flag);
}

### Actor group

sub isGroupMember {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

	return 1 if $actorHash->equals($o->{keyPair}->publicKey->hash);
	my $memberSelector = $o->findMember($actorHash) // return;
	return ! $memberSelector->child('revoked')->isSet;
}

sub findMember {
	my $o = shift;
	my $memberHash = shift; die 'wrong type '.ref($memberHash).' for $memberHash' if defined $memberHash && ref $memberHash ne 'CDS::Hash';

	for my $child ($o->{actorGroupSelector}->children) {
		my $record = $child->record;
		my $hash = $record->child('hash')->hashValue // next;
		next if ! $hash->equals($memberHash);
		return $child;
	}

	return;
}

sub forgetOldIdleActors {
	my $o = shift;
	my $limit = shift;

	for my $child ($o->{actorGroupSelector}->children) {
		next if $child->child('active')->booleanValue;
		next if $child->child('group data')->booleanValue;
		next if $child->revision > $limit;
		$child->forgetBranch;
	}
}

### Group data members

sub getGroupDataMembers {
	my $o = shift;

	# Update the cached list
	for my $child ($o->{actorGroupSelector}->children) {
		my $record = $child->record;
		my $hash = $record->child('hash')->hashValue;
		$hash = undef if $hash->equals($o->{keyPair}->publicKey->hash);
		$hash = undef if $child->child('revoked')->isSet;
		$hash = undef if ! $child->child('group data')->isSet;

		# Remove
		if (! $hash) {
			delete $o->{cachedGroupDataMembers}->{$child->label};
			next;
		}

		# Keep
		my $member = $o->{cachedGroupDataMembers}->{$child->label};
		my $storeUrl = $record->child('store')->textValue;
		next if $member && $member->storeUrl eq $storeUrl && $member->actorOnStore->publicKey->hash->equals($hash);

		# Verify the store
		my $store = $o->onVerifyMemberStore($storeUrl, $child);
		if (! $store) {
			delete $o->{cachedGroupDataMembers}->{$child->label};
			next;
		}

		# Reuse the public key and add
		if ($member && $member->actorOnStore->publicKey->hash->equals($hash)) {
			my $actorOnStore = CDS::ActorOnStore->new($member->actorOnStore->publicKey, $store);
			$o->{cachedEntrustedKeys}->{$child->label} = {storeUrl => $storeUrl, actorOnStore => $actorOnStore};
		}

		# Get the public key and add
		my ($publicKey, $invalidReason, $storeError) = $o->{keyPair}->getPublicKey($hash, $o->{groupDocument}->unsaved);
		return if defined $storeError;
		if (defined $invalidReason) {
			delete $o->{cachedGroupDataMembers}->{$child->label};
			next;
		}

		my $actorOnStore = CDS::ActorOnStore->new($publicKey, $store);
		$o->{cachedGroupDataMembers}->{$child->label} = {storeUrl => $storeUrl, actorOnStore => $actorOnStore};
	}

	# Return the current list
	return [map { $_->{actorOnStore} } values %{$o->{cachedGroupDataMembers}}];
}

### Entrusted actors

sub entrust {
	my $o = shift;
	my $storeUrl = shift;
	my $publicKey = shift; die 'wrong type '.ref($publicKey).' for $publicKey' if defined $publicKey && ref $publicKey ne 'CDS::PublicKey';

	# TODO: this is not compatible with the Java implementation (which uses a record with "hash" and "store")
	my $selector = $o->{entrustedActorsSelector};
	my $builder = CDS::ActorGroupBuilder->new;
	$builder->parseEntrustedActorList($selector->record, 1);
	$builder->removeEntrustedActor($publicKey->hash);
	$builder->addEntrustedActor($storeUrl, $publicKey->hash);
	$selector->addObject($publicKey->hash, $publicKey->object);
	$selector->set($builder->entrustedActorListToRecord(1));
	$o->{cachedEntrustedKeys}->{$publicKey->hash->bytes} = $publicKey;
}

sub doNotEntrust {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	my $selector = $o->{entrustedActorsSelector};
	my $builder = CDS::ActorGroupBuilder->new;
	$builder->parseEntrustedActorList($selector->record, 1);
	$builder->removeEntrustedActor($hash);
	$selector->set($builder->entrustedActorListToRecord(1));
	delete $o->{cachedEntrustedKeys}->{$hash->bytes};
}

sub getEntrustedKeys {
	my $o = shift;

	my $entrustedKeys = [];
	for my $storeRecord ($o->{entrustedActorsSelector}->record->children) {
		for my $child ($storeRecord->children) {
			my $hash = $child->hash // next;
			push @$entrustedKeys, $o->getEntrustedKey($hash) // next;
		}
	}

	# We could remove unused keys from $o->{cachedEntrustedKeys} here, but since this is
	# such a rare event, and doesn't consume a lot of memory, this would be overkill.

	return $entrustedKeys;
}

sub getEntrustedKey {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	my $entrustedKey = $o->{cachedEntrustedKeys}->{$hash->bytes};
	return $entrustedKey if $entrustedKey;

	my ($publicKey, $invalidReason, $storeError) = $o->{keyPair}->getPublicKey($hash, $o->{groupDocument}->unsaved);
	return if defined $storeError;
	return if defined $invalidReason;
	$o->{cachedEntrustedKeys}->{$hash->bytes} = $publicKey;
	return $publicKey;
}

### Private data

sub procurePrivateData {
	my $o = shift;
	my $interval = shift // CDS->DAY;

	$o->{storagePrivateRoot}->procure($interval) // return;
	$o->{groupDocument}->read // return;
	$o->{localDocument}->read // return;
	return 1;
}

sub savePrivateDataAndShareGroupData {
	my $o = shift;

	$o->{localDocument}->save;
	$o->{groupDocument}->save;
	$o->groupDataSharer->share;
	my $entrustedKeys = $o->getEntrustedKeys // return;
	my ($ok, $missingHash) = $o->{storagePrivateRoot}->save($entrustedKeys);
	return 1 if $ok;
	$o->onMissingObject($missingHash) if $missingHash;
	return;
}

# abstract sub onVerifyMemberStore($storeUrl, $selector)
# abstract sub onPrivateRootReadingInvalidEntry($o, $source, $reason)
# abstract sub onMissingObject($missingHash)

### Sending messages

sub procureSentList {
	my $o = shift;
	my $interval = shift // CDS->DAY;

	$o->{messagingPrivateRoot}->procure($interval) // return;
	$o->{sentList}->read // return;
	$o->{sentListReady} = 1;
	return 1;
}

sub openMessageChannel {
	my $o = shift;
	my $label = shift;
	my $validity = shift;

	return CDS::MessageChannel->new($o, $label, $validity);
}

sub sendMessages {
	my $o = shift;

	return 1 if ! $o->{sentList}->hasChanges;
	$o->{sentList}->save;
	my $entrustedKeys = $o->getEntrustedKeys // return;
	my ($ok, $missingHash) = $o->{messagingPrivateRoot}->save($entrustedKeys);
	return 1 if $ok;
	$o->onMissingObject($missingHash) if $missingHash;
	return;
}

### Receiving messages

# abstract sub onMessageBoxVerifyStore($o, $senderStoreUrl, $hash, $envelope, $senderHash)
# abstract sub onMessage($o, $message)
# abstract sub onInvalidMessage($o, $source, $reason)
# abstract sub onMessageBoxEntry($o, $message)
# abstract sub onMessageBoxInvalidEntry($o, $source, $reason)

### Announcing ###

sub announceOnAllStores {
	my $o = shift;

	$o->announce($o->{storageStore});
	$o->announce($o->{messagingStore}) if $o->{messagingStore}->id ne $o->{storageStore}->id;
}

sub announce {
	my $o = shift;
	my $store = shift;

	die 'probably calling old announce, which should now be announceOnAllStores' if ! defined $store;

	# Prepare the actor group
	my $builder = CDS::ActorGroupBuilder->new;

	my $me = $o->keyPair->publicKey->hash;
	$builder->addMember($me, $o->messagingStoreUrl, CDS->now, 'active');
	for my $child ($o->actorGroupSelector->children) {
		my $record = $child->record;
		my $hash = $record->child('hash')->hashValue // next;
		next if $hash->equals($me);
		my $storeUrl = $record->child('store')->textValue;
		my $revokedSelector = $child->child('revoked');
		my $activeSelector = $child->child('active');
		my $revision = CDS->max($child->revision, $revokedSelector->revision, $activeSelector->revision);
		my $actorStatus = $revokedSelector->booleanValue ? 'revoked' : $activeSelector->booleanValue ? 'active' : 'idle';
		$builder->addMember($hash, $storeUrl, $revision, $actorStatus);
	}

	$builder->parseEntrustedActorList($o->entrustedActorsSelector->record, 1) if $builder->mergeEntrustedActors($o->entrustedActorsSelector->revision);

	# Create the card
	my $card = $builder->toRecord(0);
	$card->add('public key')->addHash($o->{keyPair}->publicKey->hash);

	# Add the public data
	for my $child ($o->publicDataSelector->children) {
		my $childRecord = $child->record;
		$card->addRecord($childRecord->children);
	}

	# Create an unsaved state
	my $unsaved = CDS::Unsaved->new($o->publicDataSelector->document->unsaved);

	# Add the public card and the public key
	my $cardObject = $card->toObject;
	my $cardHash = $cardObject->calculateHash;
	$unsaved->state->addObject($cardHash, $cardObject);
	$unsaved->state->addObject($me, $o->keyPair->publicKey->object);

	# Prepare the public envelope
	my $envelopeObject = $o->keyPair->createPublicEnvelope($cardHash)->toObject;
	my $envelopeHash = $envelopeObject->calculateHash;

	# Upload the objects
	my ($missingObject, $transferStore, $transferError) = $o->keyPair->transfer([$cardHash], $unsaved, $store);
	return if defined $transferError;
	if ($missingObject) {
		$missingObject->{context} = 'announce on '.$store->id;
		$o->onMissingObject($missingObject);
		return;
	}

	# Prepare to modify
	my $modifications = CDS::StoreModifications->new;
	$modifications->add($me, 'public', $envelopeHash, $envelopeObject);

	# List the current cards to remove them
	# Ignore errors, in the worst case, we are going to have multiple entries in the public box
	my ($hashes, $error) = $store->list($me, 'public', 0, $o->keyPair);
	if ($hashes) {
		for my $hash (@$hashes) {
			$modifications->remove($me, 'public', $hash);
		}
	}

	# Modify the public box
	my $modifyError = $store->modify($modifications, $o->keyPair);
	return if defined $modifyError;
	return $envelopeHash, $cardHash;
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

package CDS::Configuration;

our $xdgConfigurationFolder = ($ENV{XDG_CONFIG_HOME} || $ENV{HOME}.'/.config').'/condensation';
our $xdgDataFolder = ($ENV{XDG_DATA_HOME} || $ENV{HOME}.'/.local/share').'/condensation';

sub getOrCreateDefault {
	my $class = shift;
	my $ui = shift;

	my $configuration = $class->new($ui, $xdgConfigurationFolder, $xdgDataFolder);
	$configuration->createIfNecessary();
	return $configuration;
}

sub new {
	my $class = shift;
	my $ui = shift;
	my $folder = shift;
	my $defaultStoreFolder = shift;

	return bless {ui => $ui, folder => $folder, defaultStoreFolder => $defaultStoreFolder};
}

sub ui { shift->{ui} }
sub folder { shift->{folder} }

sub createIfNecessary {
	my $o = shift;

	my $keyPairFile = $o->{folder}.'/key-pair';
	return 1 if -f $keyPairFile;

	$o->{ui}->progress('Creating configuration folders …');
	$o->createFolder($o->{folder}) // return $o->{ui}->error('Failed to create the folder "', $o->{folder}, '".');
	$o->createFolder($o->{defaultStoreFolder}) // return $o->{ui}->error('Failed to create the folder "', $o->{defaultStoreFolder}, '".');
	CDS::FolderStore->new($o->{defaultStoreFolder})->createIfNecessary;

	$o->{ui}->progress('Generating key pair …');
	my $keyPair = CDS::KeyPair->generate;
	$keyPair->writeToFile($keyPairFile) // return $o->{ui}->error('Failed to write the configuration file "', $keyPairFile, '". Make sure that this location is writable.');
	$o->{ui}->removeProgress;
	return 1;
}

sub createFolder {
	my $o = shift;
	my $folder = shift;

	for my $path (CDS->intermediateFolders($folder)) {
		mkdir $path;
	}

	return -d $folder;
}

sub file {
	my $o = shift;
	my $filename = shift;

	return $o->{folder}.'/'.$filename;
}

sub messagingStoreUrl {
	my $o = shift;

	return $o->readFirstLine('messaging-store') // 'file://'.$o->{defaultStoreFolder};
}

sub storageStoreUrl {
	my $o = shift;

	return $o->readFirstLine('store') // 'file://'.$o->{defaultStoreFolder};
}

sub setMessagingStoreUrl {
	my $o = shift;
	my $storeUrl = shift;

	CDS->writeTextToFile($o->file('messaging-store'), $storeUrl);
}

sub setStorageStoreUrl {
	my $o = shift;
	my $storeUrl = shift;

	CDS->writeTextToFile($o->file('store'), $storeUrl);
}

sub keyPair {
	my $o = shift;

	return CDS::KeyPair->fromFile($o->file('key-pair'));
}

sub setKeyPair {
	my $o = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	$keyPair->writeToFile($o->file('key-pair'));
}

sub readFirstLine {
	my $o = shift;
	my $file = shift;

	my $content = CDS->readTextFromFile($o->file($file)) // return;
	$content = $1 if $content =~ /^(.*)\n/;
	$content = $1 if $content =~ /^\s*(.*?)\s*$/;
	return $content;
}

package CDS::DetachedDocument;

use parent -norequire, 'CDS::Document';

sub new {
	my $class = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return $class->SUPER::new($keyPair, CDS::InMemoryStore->create);
}

sub savingDone {
	my $o = shift;
	my $revision = shift;
	my $newPart = shift;
	my $obsoleteParts = shift;

	# We don't do anything
	$o->{unsaved}->savingDone;
}

package CDS::DiscoverActorGroup;

sub discover {
	my $class = shift;
	my $builder = shift; die 'wrong type '.ref($builder).' for $builder' if defined $builder && ref $builder ne 'CDS::ActorGroupBuilder';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $delegate = shift;

	my $o = bless {
		knownPublicKeys => $builder->knownPublicKeys,	# A hashref of known public keys (e.g. from the existing actor group)
		keyPair => $keyPair,
		delegate => $delegate,							# The delegate
		nodesByUrl => {},								# Nodes on which this actor group is active, by URL
		coverage => {},									# Hashes that belong to this actor group
		};

	# Add all active members
	for my $member ($builder->members) {
		next if $member->status ne 'active';
		my $node = $o->node($member->hash, $member->storeUrl);
		if ($node->{revision} < $member->revision) {
			$node->{revision} = $member->revision;
			$node->{status} = 'active';
		}

		$o->{coverage}->{$member->hash->bytes} = 1;
	}

	# Determine the revision at start
	my $revisionAtStart = 0;
	for my $node (values %{$o->{nodesByUrl}}) {
		$revisionAtStart = $node->{revision} if $revisionAtStart < $node->{revision};
	}

	# Reload the cards of all known accounts
	for my $node (values %{$o->{nodesByUrl}}) {
		$node->discover;
	}

	# From here, try extending to other accounts
	while ($o->extend) {}

	# Compile the list of actors and cards
	my @members;
	my @cards;
	for my $node (values %{$o->{nodesByUrl}}) {
		next if ! $node->{reachable};
		next if ! $node->{attachedToUs};
		next if ! $node->{actorOnStore};
		next if ! $node->isActiveOrIdle;
		#-- member ++ $node->{actorHash}->hex ++ $node->{cardsRead} ++ $node->{cards} // 'undef' ++ $node->{actorOnStore} // 'undef'
		push @members, CDS::ActorGroup::Member->new($node->{actorOnStore}, $node->{storeUrl}, $node->{revision}, $node->isActive);
		push @cards, @{$node->{cards}};
	}

	# Get the newest list of entrusted actors
	my $parser = CDS::ActorGroupBuilder->new;
	for my $card (@cards) {
		$parser->parseEntrustedActors($card->card->child('entrusted actors'), 0);
	}

	# Get the entrusted actors
	my $entrustedActors = [];
	for my $actor ($parser->entrustedActors) {
		my $store = $o->{delegate}->onDiscoverActorGroupVerifyStore($actor->storeUrl);
		next if ! $store;

		my $knownPublicKey = $o->{knownPublicKeys}->{$actor->hash->bytes};
		if ($knownPublicKey) {
			push @$entrustedActors, CDS::ActorGroup::EntrustedActor->new(CDS::ActorOnStore->new($knownPublicKey, $store), $actor->storeUrl);
			next;
		}

		my ($publicKey, $invalidReason, $storeError) = $keyPair->getPublicKey($actor->hash, $store);

		if (defined $invalidReason) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidPublicKey($actor->hash, $store, $invalidReason);
			next;
		}

		if (defined $storeError) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupStoreError($store, $storeError);
			next;
		}

		push @$entrustedActors, CDS::ActorGroup::EntrustedActor->new(CDS::ActorOnStore->new($publicKey, $store), $actor->storeUrl);
	}

	my $members = [sort { $b->{revision} <=> $a->{revision} || $b->{status} cmp $a->{status} } @members];
	return CDS::ActorGroup->new($members, $parser->entrustedActorsRevision, $entrustedActors), [@cards], [grep { $_->{attachedToUs} } values %{$o->{nodesByUrl}}];
}

sub node {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';
	my $storeUrl = shift;
		# private
	my $url = $storeUrl.'/accounts/'.$actorHash->hex;
	my $node = $o->{nodesByUrl}->{$url};
	return $node if $node;
	return $o->{nodesByUrl}->{$url} = CDS::DiscoverActorGroup::Node->new($o, $actorHash, $storeUrl);
}

sub covers {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	 $o->{coverage}->{$hash->bytes} }

sub extend {
	my $o = shift;

	# Start with the newest node
	my $mainNode;
	my $mainRevision = -1;
	for my $node (values %{$o->{nodesByUrl}}) {
		next if ! $node->{attachedToUs};
		next if $node->{revision} <= $mainRevision;
		$mainNode = $node;
		$mainRevision = $node->{revision};
	}

	return 0 if ! $mainNode;

	# Reset the reachable flag
	for my $node (values %{$o->{nodesByUrl}}) {
		$node->{reachable} = 0;
	}
	$mainNode->{reachable} = 1;

	# Traverse the graph along active links to find accounts to discover.
	my @toDiscover;
	my @toCheck = ($mainNode);
	while (1) {
		my $currentNode = shift(@toCheck) // last;
		for my $link (@{$currentNode->{links}}) {
			my $node = $link->{node};
			next if $node->{reachable};
			my $prospectiveStatus = $link->{revision} > $node->{revision} ? $link->{status} : $node->{status};
			next if $prospectiveStatus ne 'active';
			$node->{reachable} = 1;
			push @toCheck, $node if $node->{attachedToUs};
			push @toDiscover, $node if ! $node->{attachedToUs};
		}
	}

	# Discover these accounts
	my $hasChanges = 0;
	for my $node (sort { $b->{revision} <=> $a->{revision} } @toDiscover) {
		$node->discover;
		next if ! $node->{attachedToUs};
		$hasChanges = 1;
	}

	return $hasChanges;
}

package CDS::DiscoverActorGroup::Card;

sub new {
	my $class = shift;
	my $storeUrl = shift;
	my $actorOnStore = shift; die 'wrong type '.ref($actorOnStore).' for $actorOnStore' if defined $actorOnStore && ref $actorOnStore ne 'CDS::ActorOnStore';
	my $envelopeHash = shift; die 'wrong type '.ref($envelopeHash).' for $envelopeHash' if defined $envelopeHash && ref $envelopeHash ne 'CDS::Hash';
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
	my $cardHash = shift; die 'wrong type '.ref($cardHash).' for $cardHash' if defined $cardHash && ref $cardHash ne 'CDS::Hash';
	my $card = shift;

	return bless {
		storeUrl => $storeUrl,
		actorOnStore => $actorOnStore,
		envelopeHash => $envelopeHash,
		envelope => $envelope,
		cardHash => $cardHash,
		card => $card,
		};
}

sub storeUrl { shift->{storeUrl} }
sub actorOnStore { shift->{actorOnStore} }
sub envelopeHash { shift->{envelopeHash} }
sub envelope { shift->{envelope} }
sub cardHash { shift->{cardHash} }
sub card { shift->{card} }

package CDS::DiscoverActorGroup::Link;

sub new {
	my $class = shift;
	my $node = shift;
	my $revision = shift;
	my $status = shift;

	bless {
		node => $node,
		revision => $revision,
		status => $status,
		};
}

sub node { shift->{node} }
sub revision { shift->{revision} }
sub status { shift->{status} }

package CDS::DiscoverActorGroup::Node;

sub new {
	my $class = shift;
	my $discoverer = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';
	my $storeUrl = shift;

	return bless {
		discoverer => $discoverer,
		actorHash => $actorHash,
		storeUrl => $storeUrl,
		revision => -1,
		status => 'idle',
		reachable => 0,				# whether this node is reachable from the main node
		store => undef,
		actorOnStore => undef,
		links => [],				# all links found in the cards
		attachedToUs => 0,			# whether the account belongs to us
		cardsRead => 0,
		cards => [],
		};
}

sub cards {
	my $o = shift;
	 @{$o->{cards}} }
sub isActive {
	my $o = shift;
	 $o->{status} eq 'active' }
sub isActiveOrIdle {
	my $o = shift;
	 $o->{status} eq 'active' || $o->{status} eq 'idle' }

sub actorHash { shift->{actorHash} }
sub storeUrl { shift->{storeUrl} }
sub revision { shift->{revision} }
sub status { shift->{status} }
sub attachedToUs { shift->{attachedToUs} }
sub links {
	my $o = shift;
	 @{$o->{links}} }

sub discover {
	my $o = shift;

	#-- discover ++ $o->{actorHash}->hex
	$o->readCards;
	$o->attach;
}

sub readCards {
	my $o = shift;

	return if $o->{cardsRead};
	$o->{cardsRead} = 1;
	#-- read cards of ++ $o->{actorHash}->hex

	# Get the store
	my $store = $o->{discoverer}->{delegate}->onDiscoverActorGroupVerifyStore($o->{storeUrl}, $o->{actorHash}) // return;

	# Get the public key if necessary
	if (! $o->{actorOnStore}) {
		my $publicKey = $o->{discoverer}->{knownPublicKeys}->{$o->{actorHash}->bytes};
		if (! $publicKey) {
			my ($downloadedPublicKey, $invalidReason, $storeError) = $o->{discoverer}->{keyPair}->getPublicKey($o->{actorHash}, $store);
			return $o->{discoverer}->{delegate}->onDiscoverActorGroupStoreError($store, $storeError) if defined $storeError;
			return $o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidPublicKey($o->{actorHash}, $store, $invalidReason) if defined $invalidReason;
			$publicKey = $downloadedPublicKey;
		}

		$o->{actorOnStore} = CDS::ActorOnStore->new($publicKey, $store);
	}

	# List the public box
	my ($hashes, $storeError) = $store->list($o->{actorHash}, 'public', 0, $o->{discoverer}->{keyPair});
	return $o->{discoverer}->{delegate}->onDiscoverActorGroupStoreError($store, $storeError) if defined $storeError;

	for my $envelopeHash (@$hashes) {
		# Open the envelope
		my ($object, $storeError) = $store->get($envelopeHash, $o->{discoverer}->{keyPair});
		return $o->{discoverer}->{delegate}->onDiscoverActorGroupStoreError($store, $storeError) if defined $storeError;
		if (! $object) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidCard($o->{actorOnStore}, $envelopeHash, 'Envelope object not found.');
			next;
		}

		my $envelope = CDS::Record->fromObject($object);
		if (! $envelope) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidCard($o->{actorOnStore}, $envelopeHash, 'Envelope is not a record.');
			next;
		}

		my $cardHash = $envelope->child('content')->hashValue;
		if (! $cardHash) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidCard($o->{actorOnStore}, $envelopeHash, 'Missing content hash.');
			next;
		}

		if (! CDS->verifyEnvelopeSignature($envelope, $o->{actorOnStore}->publicKey, $cardHash)) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidCard($o->{actorOnStore}, $envelopeHash, 'Invalid signature.');
			next;
		}

		# Read the card
		my ($cardObject, $storeError1) = $store->get($cardHash, $o->{discoverer}->{keyPair});
		return $o->{discoverer}->{delegate}->onDiscoverActorGroupStoreError($store, $storeError) if defined $storeError1;
		if (! $cardObject) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidCard($o->{actorOnStore}, $envelopeHash, 'Card object not found.');
			next;
		}

		my $card = CDS::Record->fromObject($cardObject);
		if (! $card) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidCard($o->{actorOnStore}, $envelopeHash, 'Card is not a record.');
			next;
		}

		# Add the card to the list of cards
		push @{$o->{cards}}, CDS::DiscoverActorGroup::Card->new($o->{storeUrl}, $o->{actorOnStore}, $envelopeHash, $envelope, $cardHash, $card);

		# Parse the account list
		my $builder = CDS::ActorGroupBuilder->new;
		$builder->parseMembers($card->child('actor group'), 0);
		for my $member ($builder->members) {
			my $node = $o->{discoverer}->node($member->hash, $member->storeUrl);
			#-- new link ++ $o->{actorHash}->hex ++ $status ++ $hash->hex
			push @{$o->{links}}, CDS::DiscoverActorGroup::Link->new($node, $member->revision, $member->status);
		}
	}
}

sub attach {
	my $o = shift;

	return if $o->{attachedToUs};
	return if ! $o->hasLinkToUs;

	# Attach this node
	$o->{attachedToUs} = 1;

	# Merge all links
	for my $link (@{$o->{links}}) {
		$link->{node}->merge($link->{revision}, $link->{status});
	}

	# Add the hash to the coverage
	$o->{discoverer}->{coverage}->{$o->{actorHash}->bytes} = 1;
}

sub merge {
	my $o = shift;
	my $revision = shift;
	my $status = shift;

	return if $o->{revision} >= $revision;
	$o->{revision} = $revision;
	$o->{status} = $status;
}

sub hasLinkToUs {
	my $o = shift;

	return 1 if $o->{discoverer}->covers($o->{actorHash});
	for my $link (@{$o->{links}}) {
		return 1 if $o->{discoverer}->covers($link->{node}->{actorHash});
	}
	return;
}

package CDS::Document;

sub new {
	my $class = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $store = shift;

	my $o = bless {
		keyPair => $keyPair,
		unsaved => CDS::Unsaved->new($store),
		itemsBySelector => {},
		parts => {},
		hasPartsToMerge => 0,
		}, $class;

	$o->{root} = CDS::Selector->root($o);
	$o->{changes} = CDS::Document::Part->new;
	return $o;
}

sub keyPair { shift->{keyPair} }
sub unsaved { shift->{unsaved} }
sub parts {
	my $o = shift;
	 values %{$o->{parts}} }
sub hasPartsToMerge { shift->{hasPartsToMerge} }

### Items

sub root { shift->{root} }
sub rootItem {
	my $o = shift;
	 $o->getOrCreate($o->{root}) }

sub get {
	my $o = shift;
	my $selector = shift; die 'wrong type '.ref($selector).' for $selector' if defined $selector && ref $selector ne 'CDS::Selector';
	 $o->{itemsBySelector}->{$selector->{id}} }

sub getOrCreate {
	my $o = shift;
	my $selector = shift; die 'wrong type '.ref($selector).' for $selector' if defined $selector && ref $selector ne 'CDS::Selector';

	my $item = $o->{itemsBySelector}->{$selector->{id}};
	$o->{itemsBySelector}->{$selector->{id}} = $item = CDS::Document::Item->new($selector) if ! $item;
	return $item;
}

sub prune {
	my $o = shift;
	 $o->rootItem->pruneTree; }

### Merging

sub merge {
	my $o = shift;

	for my $hashAndKey (@_) {
		next if ! $hashAndKey;
		next if $o->{parts}->{$hashAndKey->hash->bytes};
		my $part = CDS::Document::Part->new;
		$part->{hashAndKey} = $hashAndKey;
		$o->{parts}->{$hashAndKey->hash->bytes} = $part;
		$o->{hasPartsToMerge} = 1;
	}
}

sub read {
	my $o = shift;

	return 1 if ! $o->{hasPartsToMerge};

	# Load the parts
	for my $part (values %{$o->{parts}}) {
		next if $part->{isMerged};
		next if $part->{loadedRecord};

		my ($record, $object, $invalidReason, $storeError) = $o->{keyPair}->getAndDecryptRecord($part->{hashAndKey}, $o->{unsaved});
		return if defined $storeError;

		delete $o->{parts}->{$part->{hashAndKey}->hash->bytes} if defined $invalidReason;
		$part->{loadedRecord} = $record;
	}

	# Merge the loaded parts
	for my $part (values %{$o->{parts}}) {
		next if $part->{isMerged};
		next if ! $part->{loadedRecord};
		my $oldFormat = $part->{loadedRecord}->child('client')->textValue =~ /0.19/ ? 1 : 0;
		$o->mergeNode($part, $o->{root}, $part->{loadedRecord}->child('root'), $oldFormat);
		delete $part->{loadedRecord};
		$part->{isMerged} = 1;
	}

	$o->{hasPartsToMerge} = 0;
	return 1;
}

sub mergeNode {
	my $o = shift;
	my $part = shift;
	my $selector = shift; die 'wrong type '.ref($selector).' for $selector' if defined $selector && ref $selector ne 'CDS::Selector';
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $oldFormat = shift;

	# Prepare
	my @children = $record->children;
	return if ! scalar @children;
	my $item = $o->getOrCreate($selector);

	# Merge value
	my $valueRecord = shift @children;
	$valueRecord = $valueRecord->firstChild if $oldFormat;
	$item->mergeValue($part, $valueRecord->asInteger, $valueRecord);

	# Merge children
	for my $child (@children) { $o->mergeNode($part, $selector->child($child->bytes), $child, $oldFormat); }
}

# *** Saving
# Call $document->save at any time to save the current state (if necessary).

# This is called by the items whenever some data changes.
sub dataChanged {
	my $o = shift;
	 }

sub save {
	my $o = shift;

	$o->{unsaved}->startSaving;
	my $revision = CDS->now;
	my $newPart = undef;

	#-- saving ++ $o->{changes}->{count}
	if ($o->{changes}->{count}) {
		# Take the changes
		$newPart = $o->{changes};
		$o->{changes} = CDS::Document::Part->new;

		# Select all parts smaller than 2 * changes
		$newPart->{selected} = 1;
		my $count = $newPart->{count};
		while (1) {
			my $addedPart = 0;
			for my $part (values %{$o->{parts}}) {
				#-- candidate ++ $part->{count} ++ $count
				next if ! $part->{isMerged} || $part->{selected} || $part->{count} >= $count * 2;
				$count += $part->{count};
				$part->{selected} = 1;
				$addedPart = 1;
			}

			last if ! $addedPart;
		}

		# Include the selected items
		for my $item (values %{$o->{itemsBySelector}}) {
			next if ! $item->{part}->{selected};
			$item->setPart($newPart);
			$item->createSaveRecord;
		}

		my $record = CDS::Record->new;
		$record->add('created')->addInteger($revision);
		$record->add('client')->add(CDS->version);
		$record->addRecord($o->rootItem->createSaveRecord);

		# Detach the save records
		for my $item (values %{$o->{itemsBySelector}}) {
			$item->detachSaveRecord;
		}

		# Serialize and encrypt the record
		my $key = CDS->randomKey;
		my $newObject = $record->toObject->crypt($key);
		$newPart->{hashAndKey} = CDS::HashAndKey->new($newObject->calculateHash, $key);
		$newPart->{isMerged} = 1;
		$newPart->{selected} = 0;
		$o->{parts}->{$newPart->{hashAndKey}->hash->bytes} = $newPart;
		#-- added ++ $o->{parts} ++ scalar keys %{$o->{parts}} ++ $newPart->{count}
		$o->{unsaved}->{savingState}->addObject($newPart->{hashAndKey}->hash, $newObject);
	}

	# Remove obsolete parts
	my $obsoleteParts = [];
	for my $part (values %{$o->{parts}}) {
		next if ! $part->{isMerged};
		next if $part->{count};
		push @$obsoleteParts, $part;
		delete $o->{parts}->{$part->{hashAndKey}->hash->bytes};
	}

	# Commit
	#-- saving done ++ $revision ++ $newPart ++ $obsoleteParts
	return $o->savingDone($revision, $newPart, $obsoleteParts);
}

package CDS::Document::Item;

sub new {
	my $class = shift;
	my $selector = shift; die 'wrong type '.ref($selector).' for $selector' if defined $selector && ref $selector ne 'CDS::Selector';

	my $parentSelector = $selector->parent;
	my $parent = $parentSelector ? $selector->document->getOrCreate($parentSelector) : undef;

	my $o = bless {
		document => $selector->document,
		selector => $selector,
		parent => $parent,
		children => [],
		part => undef,
		revision => 0,
		record => CDS::Record->new
		};

	push @{$parent->{children}}, $o if $parent;
	return $o;
}

sub pruneTree {
	my $o = shift;

	# Try to remove children
	for my $child (@{$o->{children}}) { $child->pruneTree; }

	# Don't remove the root item
	return if ! $o->{parent};

	# Don't remove if the item has children, or a value
	return if scalar @{$o->{children}};
	return if $o->{revision} > 0;

	# Remove this from the tree
	$o->{parent}->{children} = [grep { $_ != $o } @{$o->{parent}->{children}}];

	# Remove this from the document hash
	delete $o->{document}->{itemsBySelector}->{$o->{selector}->{id}};
}

# Low-level part change.
sub setPart {
	my $o = shift;
	my $part = shift;

	$o->{part}->{count} -= 1 if $o->{part};
	$o->{part} = $part;
	$o->{part}->{count} += 1 if $o->{part};
}

# Merge a value

sub mergeValue {
	my $o = shift;
	my $part = shift;
	my $revision = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	return if $revision <= 0;
	return if $revision < $o->{revision};
	return if $revision == $o->{revision} && $part->{size} < $o->{part}->{size};
	$o->setPart($part);
	$o->{revision} = $revision;
	$o->{record} = $record;
	$o->{document}->dataChanged;
	return 1;
}

sub forget {
	my $o = shift;

	return if $o->{revision} <= 0;
	$o->{revision} = 0;
	$o->{record} = CDS::Record->new;
	$o->setPart;
}

# Saving

sub createSaveRecord {
	my $o = shift;

	return $o->{saveRecord} if $o->{saveRecord};
	$o->{saveRecord} = $o->{parent} ? $o->{parent}->createSaveRecord->add($o->{selector}->{label}) : CDS::Record->new('root');
	if ($o->{part}->{selected}) {
		CDS->log('Item saving zero revision of ', $o->{selector}->label) if $o->{revision} <= 0;
		$o->{saveRecord}->addInteger($o->{revision})->addRecord($o->{record}->children);
	} else {
		$o->{saveRecord}->add('');
	}
	return $o->{saveRecord};
}

sub detachSaveRecord {
	my $o = shift;

	return if ! $o->{saveRecord};
	delete $o->{saveRecord};
	$o->{parent}->detachSaveRecord if $o->{parent};
}

package CDS::Document::Part;

sub new {
	my $class = shift;

	return bless {
		isMerged => 0,
		hashAndKey => undef,
		size => 0,
		count => 0,
		selected => 0,
		};
}

# In this implementation, we only keep track of the number of values of the list, but
# not of the corresponding items. This saves memory (~100 MiB for 1M items), but takes
# more time (0.5 s for 1M items) when saving. Since command line programs usually write
# the document only once, this is acceptable. Reading the tree anyway takes about 10
# times more time.

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

package CDS::GroupDataSharer;

sub new {
	my $class = shift;
	my $actor = shift;

	my $o = bless {
		actor => $actor,
		label => 'shared group data',
		dataHandlers => {},
		messageChannel => CDS::MessageChannel->new($actor, 'group data', CDS->MONTH),
		revision => 0,
		version => '',
		}, $class;

	$actor->storagePrivateRoot->addDataHandler($o->{label}, $o);
	return $o;
}

### Group data handlers

sub addDataHandler {
	my $o = shift;
	my $label = shift;
	my $dataHandler = shift;

	$o->{dataHandlers}->{$label} = $dataHandler;
}

sub removeDataHandler {
	my $o = shift;
	my $label = shift;
	my $dataHandler = shift;

	my $registered = $o->{dataHandlers}->{$label};
	return if $registered != $dataHandler;
	delete $o->{dataHandlers}->{$label};
}

### MergeableData interface

sub addDataTo {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	return if ! $o->{revision};
	$record->addInteger($o->{revision})->add($o->{version});
}

sub mergeData {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	for my $child ($record->children) {
		my $revision = $child->asInteger;
		next if $revision <= $o->{revision};

		$o->{revision} = $revision;
		$o->{version} = $child->bytesValue;
	}
}

sub mergeExternalData {
	my $o = shift;
	my $store = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';

	$o->mergeData($record);
	return if ! $source;
	$source->keep;
	$o->{actor}->storagePrivateRoot->unsaved->state->addMergedSource($source);
}

### Sending messages

sub createMessage {
	my $o = shift;

	my $message = CDS::Record->new;
	my $data = $message->add('group data');
	for my $label (keys %{$o->{dataHandlers}}) {
		my $dataHandler = $o->{dataHandlers}->{$label};
		$dataHandler->addDataTo($data->add($label));
	}
	return $message;
}

sub share {
	my $o = shift;

	# Get the group data members
	my $members = $o->{actor}->getGroupDataMembers // return;
	return 1 if ! scalar @$members;

	# Create the group data message, and check if it changed
	my $message = $o->createMessage;
	my $versionHash = $message->toObject->calculateHash;
	return if $versionHash->bytes eq $o->{version};

	$o->{revision} = CDS->now;
	$o->{version} = $versionHash->bytes;
	$o->{actor}->storagePrivateRoot->dataChanged;

	# Procure the sent list
	$o->{actor}->procureSentList // return;

	# Get the entrusted keys
	my $entrustedKeys = $o->{actor}->getEntrustedKeys // return;

	# Transfer the data
	$o->{messageChannel}->addTransfer([$message->dependentHashes], $o->{actor}->storagePrivateRoot->unsaved, 'group data message');

	# Send the message
	$o->{messageChannel}->setRecipients($members, $entrustedKeys);
	my ($submission, $missingObject) = $o->{messageChannel}->submit($message, $o);
	$o->{actor}->onMissingObject($missingObject) if $missingObject;
	return if ! $submission;
	return 1;
}

sub onMessageChannelSubmissionCancelled {
	my $o = shift;
	 }

sub onMessageChannelSubmissionRecipientDone {
	my $o = shift;
	my $recipientActorOnStore = shift; die 'wrong type '.ref($recipientActorOnStore).' for $recipientActorOnStore' if defined $recipientActorOnStore && ref $recipientActorOnStore ne 'CDS::ActorOnStore';
	 }

sub onMessageChannelSubmissionRecipientFailed {
	my $o = shift;
	my $recipientActorOnStore = shift; die 'wrong type '.ref($recipientActorOnStore).' for $recipientActorOnStore' if defined $recipientActorOnStore && ref $recipientActorOnStore ne 'CDS::ActorOnStore';
	 }

sub onMessageChannelSubmissionDone {
	my $o = shift;
	my $succeeded = shift;
	my $failed = shift;
	 }

### Receiving messages

sub processGroupDataMessage {
	my $o = shift;
	my $message = shift;
	my $section = shift;

	if (! $o->{actor}->isGroupMember($message->sender->publicKey->hash)) {
		# TODO:
		# If the sender is not a known group member, we should run actor group discovery on the sender. He may be part of us, but we don't know that yet.
		# At the very least, we should keep this message, and reconsider it if the actor group changes within the next few minutes (e.g. through another message).
		return;
	}

	for my $child ($section->children) {
		my $dataHandler = $o->{dataHandlers}->{$child->bytes} // next;
		$dataHandler->mergeExternalData($message->sender->store, $child, $message->source);
	}

	return 1;
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
	for my $entry (values @{$o->{objects}}) {
		$entry->{inUse} = 0;
	}

	# Mark all objects newer than the grace time
	for my $entry (values @{$o->{objects}}) {
		$o->markEntry($entry) if $entry->{booked} > $graceTime;
	}

	# Mark all objects referenced from a box
	for my $account (values @{$o->{accounts}}) {
		for my $hash (values @{$account->{messages}}) { $o->markHash($hash); }
		for my $hash (values @{$account->{private}}) { $o->markHash($hash); }
		for my $hash (values @{$account->{public}}) { $o->markHash($hash); }
	}

	# Remove empty accounts
	while (my ($key, $account) = each %{$o->{accounts}}) {
		next if scalar @{$account->{messages}};
		next if scalar @{$account->{private}};
		next if scalar @{$account->{public}};
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

sub createPublicEnvelope {
	my $o = shift;
	my $contentHash = shift; die 'wrong type '.ref($contentHash).' for $contentHash' if defined $contentHash && ref $contentHash ne 'CDS::Hash';

	my $envelope = CDS::Record->new;
	$envelope->add('content')->addHash($contentHash);
	$envelope->add('signature')->add($o->signHash($contentHash));
	return $envelope;
}

sub createPrivateEnvelope {
	my $o = shift;
	my $contentHashAndKey = shift;
	my $recipientPublicKeys = shift;

	my $envelope = CDS::Record->new;
	$envelope->add('content')->addHash($contentHashAndKey->hash);
	$o->addRecipientsToEnvelope($envelope, $contentHashAndKey->key, $recipientPublicKeys);
	$envelope->add('signature')->add($o->signHash($contentHashAndKey->hash));
	return $envelope;
}

sub createMessageEnvelope {
	my $o = shift;
	my $storeUrl = shift;
	my $messageRecord = shift; die 'wrong type '.ref($messageRecord).' for $messageRecord' if defined $messageRecord && ref $messageRecord ne 'CDS::Record';
	my $recipientPublicKeys = shift;
	my $expires = shift;

	my $contentRecord = CDS::Record->new;
	$contentRecord->add('store')->addText($storeUrl);
	$contentRecord->add('sender')->addHash($o->publicKey->hash);
	$contentRecord->addRecord($messageRecord->children);
	my $contentObject = $contentRecord->toObject;
	my $contentKey = CDS->randomKey;
	my $encryptedContent = CDS::C::aesCrypt($contentObject->bytes, $contentKey, CDS->zeroCTR);
	#my $hashToSign = $contentObject->calculateHash;	# prior to 2020-05-05
	my $hashToSign = CDS::Hash->calculateFor($encryptedContent);

	my $envelope = CDS::Record->new;
	$envelope->add('content')->add($encryptedContent);
	$o->addRecipientsToEnvelope($envelope, $contentKey, $recipientPublicKeys);
	$envelope->add('updated by')->add(substr($o->publicKey->hash->bytes, 0, 24));
	$envelope->add('expires')->addInteger($expires) if defined $expires;
	$envelope->add('signature')->add($o->signHash($hashToSign));
	return $envelope;
}

sub addRecipientsToEnvelope {
	my $o = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
	my $key = shift;
	my $recipientPublicKeys = shift;
		# private
	my $encryptedKeyRecord = $envelope->add('encrypted for');
	my $myHashBytes24 = substr($o->{publicKey}->hash->bytes, 0, 24);
	$encryptedKeyRecord->add($myHashBytes24)->add($o->{publicKey}->encrypt($key));
	for my $publicKey (@$recipientPublicKeys) {
		next if $publicKey->hash->equals($o->{publicKey}->hash);
		my $hashBytes24 = substr($publicKey->hash->bytes, 0, 24);
		$encryptedKeyRecord->add($hashBytes24)->add($publicKey->encrypt($key));
	}
}

sub generate {
	my $class = shift;

	# Generate a new private key
	my $rsaPrivateKey = CDS::C::privateKeyGenerate();

	# Serialize the public key
	my $rsaPublicKey = CDS::C::publicKeyFromPrivateKey($rsaPrivateKey);
	my $record = CDS::Record->new;
	$record->add('e')->add(CDS::C::publicKeyE($rsaPublicKey));
	$record->add('n')->add(CDS::C::publicKeyN($rsaPublicKey));
	my $publicKey = CDS::PublicKey->fromObject($record->toObject);

	# Return a new CDS::KeyPair instance
	return CDS::KeyPair->new($publicKey, $rsaPrivateKey);
}

sub fromFile {
	my $class = shift;
	my $file = shift;

	my $bytes = CDS->readBytesFromFile($file) // return;
	my $record = CDS::Record->fromObject(CDS::Object->fromBytes($bytes));
	return $class->fromRecord($record);
}

sub fromHex {
	my $class = shift;
	my $hex = shift;

	return $class->fromRecord(CDS::Record->fromObject(CDS::Object->fromBytes(pack 'H*', $hex)));
}

sub fromRecord {
	my $class = shift;
	my $record = shift // return; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	my $publicKey = CDS::PublicKey->fromObject(CDS::Object->fromBytes($record->child('public key object')->bytesValue)) // return;
	my $rsaKey = $record->child('rsa key');
	my $e = $rsaKey->child('e')->bytesValue;
	my $p = $rsaKey->child('p')->bytesValue;
	my $q = $rsaKey->child('q')->bytesValue;
	return $class->new($publicKey, CDS::C::privateKeyNew($e, $p, $q) // return);
}

sub new {
	my $class = shift;
	my $publicKey = shift; die 'wrong type '.ref($publicKey).' for $publicKey' if defined $publicKey && ref $publicKey ne 'CDS::PublicKey';
	my $rsaPrivateKey = shift;

	return bless {
		publicKey => $publicKey,			# The public key
		rsaPrivateKey => $rsaPrivateKey,	# The private key
		};
}

sub publicKey { shift->{publicKey} }
sub rsaPrivateKey { shift->{rsaPrivateKey} }

### Serialization ###

sub toRecord {
	my $o = shift;

	my $record = CDS::Record->new;
	$record->add('public key object')->add($o->{publicKey}->object->bytes);
	my $rsaKeyRecord = $record->add('rsa key');
	$rsaKeyRecord->add('e')->add(CDS::C::privateKeyE($o->{rsaPrivateKey}));
	$rsaKeyRecord->add('p')->add(CDS::C::privateKeyP($o->{rsaPrivateKey}));
	$rsaKeyRecord->add('q')->add(CDS::C::privateKeyQ($o->{rsaPrivateKey}));
	return $record;
}

sub toHex {
	my $o = shift;

	my $object = $o->toRecord->toObject;
	return unpack('H*', $object->header).unpack('H*', $object->data);
}

sub writeToFile {
	my $o = shift;
	my $file = shift;

	my $object = $o->toRecord->toObject;
	return CDS->writeBytesToFile($file, $object->bytes);
}

### Private key interface ###

sub decrypt {
	my $o = shift;
	my $bytes = shift;
		# decrypt(bytes) -> bytes
	return CDS::C::privateKeyDecrypt($o->{rsaPrivateKey}, $bytes);
}

sub sign {
	my $o = shift;
	my $digest = shift;
		# sign(bytes) -> bytes
	return CDS::C::privateKeySign($o->{rsaPrivateKey}, $digest);
}

sub signHash {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
		# signHash(hash) -> bytes
	return CDS::C::privateKeySign($o->{rsaPrivateKey}, $hash->bytes);
}

### Retrieval ###

# Retrieves an object from one of the stores, and decrypts it.
sub getAndDecrypt {
	my $o = shift;
	my $hashAndKey = shift; die 'wrong type '.ref($hashAndKey).' for $hashAndKey' if defined $hashAndKey && ref $hashAndKey ne 'CDS::HashAndKey';
	my $store = shift;

	my ($object, $error) = $store->get($hashAndKey->hash, $o);
	return undef, undef, $error if defined $error;
	return undef, 'Not found.', undef if ! $object;
	return $object->crypt($hashAndKey->key);
}

# Retrieves an object from one of the stores, and parses it as record.
sub getRecord {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $store = shift;

	my ($object, $error) = $store->get($hash, $o);
	return undef, undef, undef, $error if defined $error;
	return undef, undef, 'Not found.', undef if ! $object;
	my $record = CDS::Record->fromObject($object) // return undef, undef, 'Not a record.', undef;
	return $record, $object;
}

# Retrieves an object from one of the stores, decrypts it, and parses it as record.
sub getAndDecryptRecord {
	my $o = shift;
	my $hashAndKey = shift; die 'wrong type '.ref($hashAndKey).' for $hashAndKey' if defined $hashAndKey && ref $hashAndKey ne 'CDS::HashAndKey';
	my $store = shift;

	my ($object, $error) = $store->get($hashAndKey->hash, $o);
	return undef, undef, undef, $error if defined $error;
	return undef, undef, 'Not found.', undef if ! $object;
	my $decrypted = $object->crypt($hashAndKey->key);
	my $record = CDS::Record->fromObject($decrypted) // return undef, undef, 'Not a record.', undef;
	return $record, $object;
}

# Retrieves an public key object from one of the stores, and parses its public key.
sub getPublicKey {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $store = shift;

	my ($object, $error) = $store->get($hash, $o);
	return undef, undef, $error if defined $error;
	return undef, 'Not found.', undef if ! $object;
	return CDS::PublicKey->fromObject($object) // return undef, 'Not a public key.', undef;
}

### Equality ###

sub equals {
	my $this = shift;
	my $that = shift;

	return 1 if ! defined $this && ! defined $that;
	return if ! defined $this || ! defined $that;
	return $this->publicKey->hash->equals($that->publicKey->hash);
}

### Open envelopes ###

sub decryptKeyOnEnvelope {
	my $o = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';

	# Read the AES key
	my $hashBytes24 = substr($o->{publicKey}->hash->bytes, 0, 24);
	my $encryptedAesKey = $envelope->child('encrypted for')->child($hashBytes24)->bytesValue;
	$encryptedAesKey = $envelope->child('encrypted for')->child($o->{publicKey}->hash->bytes)->bytesValue if ! length $encryptedAesKey; # todo: remove this
	return if ! length $encryptedAesKey;

	# Decrypt the AES key
	my $aesKeyBytes = $o->decrypt($encryptedAesKey);
	return if ! $aesKeyBytes || length $aesKeyBytes != 32;

	return $aesKeyBytes;
}

package CDS::LoadActorGroup;

sub load {
	my $class = shift;
	my $builder = shift; die 'wrong type '.ref($builder).' for $builder' if defined $builder && ref $builder ne 'CDS::ActorGroupBuilder';
	my $store = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $delegate = shift;

	my $o = bless {
		store => $store,
		keyPair => $keyPair,
		knownPublicKeys => $builder->knownPublicKeys,
		};

	my $members = [];
	for my $member ($builder->members) {
		my $isActive = $member->status eq 'active';
		my $isIdle = $member->status eq 'idle';
		next if ! $isActive && ! $isIdle;

		my ($publicKey, $storeError) = $o->getPublicKey($member->hash);
		return undef, $storeError if defined $storeError;
		next if ! $publicKey;

		my $accountStore = $delegate->onLoadActorGroupVerifyStore($member->storeUrl) // next;
		my $actorOnStore = CDS::ActorOnStore->new($publicKey, $accountStore);
		push @$members, CDS::ActorGroup::Member->new($actorOnStore, $member->storeUrl, $member->revision, $isActive);
	}

	my $entrustedActors = [];
	for my $actor ($builder->entrustedActors) {
		my ($publicKey, $storeError) = $o->getPublicKey($actor->hash);
		return undef, $storeError if defined $storeError;
		next if ! $publicKey;

		my $accountStore = $delegate->onLoadActorGroupVerifyStore($actor->storeUrl) // next;
		my $actorOnStore = CDS::ActorOnStore->new($publicKey, $accountStore);
		push @$entrustedActors, CDS::ActorGroup::EntrustedActor->new($actorOnStore, $actor->storeUrl);
	}

	return CDS::ActorGroup->new($members, $builder->entrustedActorsRevision, $entrustedActors);
}

sub getPublicKey {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	my $knownPublicKey = $o->{knownPublicKeys}->{$hash->bytes};
	return $knownPublicKey if $knownPublicKey;

	my ($publicKey, $invalidReason, $storeError) = $o->{keyPair}->getPublicKey($hash, $o->{store});
	return undef, $storeError if defined $storeError;
	return if defined $invalidReason;

	$o->{knownPublicKeys}->{$hash->bytes} = $publicKey;
	return $publicKey;
};

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

# Reads the message box of an actor.
package CDS::MessageBoxReader;

sub new {
	my $class = shift;
	my $pool = shift;
	my $actorOnStore = shift; die 'wrong type '.ref($actorOnStore).' for $actorOnStore' if defined $actorOnStore && ref $actorOnStore ne 'CDS::ActorOnStore';
	my $streamTimeout = shift;

	return bless {
		pool => $pool,
		actorOnStore => $actorOnStore,
		streamCache => CDS::StreamCache->new($pool, $actorOnStore, $streamTimeout // CDS->MINUTE),
		entries => {},
		};
}

sub pool { shift->{pool} }
sub actorOnStore { shift->{actorOnStore} }

sub read {
	my $o = shift;
	my $timeout = shift // 0;

	my $store = $o->{actorOnStore}->store;
	my ($hashes, $listError) = $store->list($o->{actorOnStore}->publicKey->hash, 'messages', $timeout, $o->{pool}->{keyPair});
	return if defined $listError;

	for my $hash (@$hashes) {
		my $entry = $o->{entries}->{$hash->bytes};
		$o->{entries}->{$hash->bytes} = $entry = CDS::MessageBoxReader::Entry->new($hash) if ! $entry;
		next if $entry->{processed};

		# Check the sender store, if necessary
		if ($entry->{waitingForStore}) {
			my ($dummy, $checkError) = $entry->{waitingForStore}->get(CDS->emptyBytesHash, $o->{pool}->{keyPair});
			next if defined $checkError;
		}

		# Get the envelope
		my ($object, $getError) = $o->{actorOnStore}->store->get($entry->{hash}, $o->{pool}->{keyPair});
		return if defined $getError;

		# Mark the entry as processed
		$entry->{processed} = 1;

		if (! defined $object) {
			$o->invalid($entry, 'Envelope object not found.');
			next;
		}

		# Parse the record
		my $envelope = CDS::Record->fromObject($object);
		if (! $envelope) {
			$o->invalid($entry, 'Envelope is not a record.');
			next;
		}

		my $message =
			$envelope->contains('head') && $envelope->contains('mac') ?
				$o->readStreamMessage($entry, $envelope) :
				$o->readNormalMessage($entry, $envelope);
		next if ! $message;

		$o->{pool}->{delegate}->onMessageBoxEntry($message);
	}

	$o->{streamCache}->removeObsolete;
	return 1;
}

sub readNormalMessage {
	my $o = shift;
	my $entry = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
		# private
	# Read the embedded content object
	my $encryptedBytes = $envelope->child('content')->bytesValue;
	return $o->invalid($entry, 'Missing content object.') if ! length $encryptedBytes;

	# Decrypt the key
	my $aesKey = $o->{pool}->{keyPair}->decryptKeyOnEnvelope($envelope);
	return $o->invalid($entry, 'Not encrypted for us.') if ! $aesKey;

	# Decrypt the content
	my $contentObject = CDS::Object->fromBytes(CDS::C::aesCrypt($encryptedBytes, $aesKey, CDS->zeroCTR));
	return $o->invalid($entry, 'Invalid content object.') if ! $contentObject;

	my $content = CDS::Record->fromObject($contentObject);
	return $o->invalid($entry, 'Content object is not a record.') if ! $content;

	# Verify the sender hash
	my $senderHash = $content->child('sender')->hashValue;
	return $o->invalid($entry, 'Missing sender hash.') if ! $senderHash;

	# Verify the sender store
	my $storeRecord = $content->child('store');
	return $o->invalid($entry, 'Missing sender store.') if ! scalar $storeRecord->children;

	my $senderStoreUrl = $storeRecord->textValue;
	my $senderStore = $o->{pool}->{delegate}->onMessageBoxVerifyStore($senderStoreUrl, $entry->{hash}, $envelope, $senderHash);
	return $o->invalid($entry, 'Invalid sender store.') if ! $senderStore;

	# Retrieve the sender's public key
	my ($senderPublicKey, $invalidReason, $publicKeyStoreError) = $o->getPublicKey($senderHash, $senderStore);
	return if defined $publicKeyStoreError;
	return $o->invalid($entry, 'Failed to retrieve the sender\'s public key: '.$invalidReason) if defined $invalidReason;

	# Verify the signature
	my $signedHash = CDS::Hash->calculateFor($encryptedBytes);
	if (! CDS->verifyEnvelopeSignature($envelope, $senderPublicKey, $signedHash)) {
		# For backwards compatibility with versions before 2020-05-05
		return $o->invalid($entry, 'Invalid signature.') if ! CDS->verifyEnvelopeSignature($envelope, $senderPublicKey, $contentObject->calculateHash);
	}

	# The envelope is valid
	my $sender = CDS::ActorOnStore->new($senderPublicKey, $senderStore);
	my $source = CDS::Source->new($o->{pool}->{keyPair}, $o->{actorOnStore}, 'messages', $entry->{hash});
	return CDS::ReceivedMessage->new($o, $entry, $source, $envelope, $senderStoreUrl, $sender, $content);
}

sub readStreamMessage {
	my $o = shift;
	my $entry = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
		# private
	# Get the head
	my $head = $envelope->child('head')->hashValue;
	return $o->invalid($entry, 'Invalid head message hash.') if ! $head;

	# Get the head envelope
	my $streamHead = $o->{streamCache}->readStreamHead($head);
	return if ! $streamHead;
	return $o->invalid($entry, 'Invalid stream head: '.$streamHead->error) if $streamHead->error;

	# Read the embedded content object
	my $encryptedBytes = $envelope->child('content')->bytesValue;
	return $o->invalid($entry, 'Missing content object.') if ! length $encryptedBytes;

	# Get the CTR
	my $ctr = $envelope->child('ctr')->bytesValue;
	return $o->invalid($entry, 'Invalid CTR.') if length $ctr != 16;

	# Get the MAC
	my $mac = $envelope->child('mac')->bytesValue;
	return $o->invalid($entry, 'Invalid MAC.') if ! $mac;

	# Verify the MAC
	my $signedHash = CDS::Hash->calculateFor($encryptedBytes);
	my $expectedMac = CDS::C::aesCrypt($signedHash->bytes, $streamHead->aesKey, $ctr);
	return $o->invalid($entry, 'Invalid MAC.') if $mac ne $expectedMac;

	# Decrypt the content
	my $contentObject = CDS::Object->fromBytes(CDS::C::aesCrypt($encryptedBytes, $streamHead->aesKey, CDS::C::counterPlusInt($ctr, 2)));
	return $o->invalid($entry, 'Invalid content object.') if ! $contentObject;

	my $content = CDS::Record->fromObject($contentObject);
	return $o->invalid($entry, 'Content object is not a record.') if ! $content;

	# The envelope is valid
	my $source = CDS::Source->new($o->{pool}->{keyPair}, $o->{actorOnStore}, 'messages', $entry->{hash});
	return CDS::ReceivedMessage->new($o, $entry, $source, $envelope, $streamHead->senderStoreUrl, $streamHead->sender, $content, $streamHead);
}

sub invalid {
	my $o = shift;
	my $entry = shift;
	my $reason = shift;
		# private
	my $source = CDS::Source->new($o->{pool}->{keyPair}, $o->{actorOnStore}, 'messages', $entry->{hash});
	$o->{pool}->{delegate}->onMessageBoxInvalidEntry($source, $reason);
}

sub getPublicKey {
	my $o = shift;
	my $senderHash = shift; die 'wrong type '.ref($senderHash).' for $senderHash' if defined $senderHash && ref $senderHash ne 'CDS::Hash';
	my $senderStore = shift;
	my $senderStoreUrl = shift;
		# private
	# Use the account key if sender and recipient are the same
	return $o->{actorOnStore}->publicKey if $senderHash->equals($o->{actorOnStore}->publicKey->hash);

	# Reuse a cached public key
	my $cachedPublicKey = $o->{pool}->{publicKeyCache}->get($senderHash);
	return $cachedPublicKey if $cachedPublicKey;

	# Retrieve the sender's public key from the sender's store
	my ($publicKey, $invalidReason, $storeError) = $o->{pool}->{keyPair}->getPublicKey($senderHash, $senderStore);
	return undef, undef, $storeError if defined $storeError;
	return undef, $invalidReason if defined $invalidReason;
	$o->{pool}->{publicKeyCache}->add($publicKey);
	return $publicKey;
}

package CDS::MessageBoxReader::Entry;

sub new {
	my $class = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	return bless {
		hash => $hash,
		processed => 0,
		};
}

package CDS::MessageBoxReaderPool;

sub new {
	my $class = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $publicKeyCache = shift;
	my $delegate = shift;

	return bless {
		keyPair => $keyPair,
		publicKeyCache => $publicKeyCache,
		delegate => $delegate,
		};
}

sub keyPair { shift->{keyPair} }
sub publicKeyCache { shift->{publicKeyCache} }

# Delegate
# onMessageBoxVerifyStore($senderStoreUrl, $hash, $envelope, $senderHash)
# onMessageBoxEntry($receivedMessage)
# onMessageBoxStream($receivedMessage)
# onMessageBoxInvalidEntry($source, $reason)

package CDS::MessageChannel;

sub new {
	my $class = shift;
	my $actor = shift;
	my $label = shift;
	my $validity = shift;

	my $o = bless {
		actor => $actor,
		label => $label,
		validity => $validity,
		};

	$o->{unsaved} = CDS::Unsaved->new($actor->sentList->unsaved);
	$o->{transfers} = [];
	$o->{recipients} = [];
	$o->{entrustedKeys} = [];
	$o->{obsoleteHashes} = {};
	$o->{currentSubmissionId} = 0;
	return $o;
}

sub actor { shift->{actor} }
sub label { shift->{label} }
sub validity { shift->{validity} }
sub unsaved { shift->{unsaved} }
sub item {
	my $o = shift;
	 $o->{actor}->sentList->getOrCreate($o->{label}) }
sub recipients {
	my $o = shift;
	 @{$o->{recipients}} }
sub entrustedKeys {
	my $o = shift;
	 @{$o->{entrustedKeys}} }

sub addObject {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

	$o->{unsaved}->state->addObject($hash, $object);
}

sub addTransfer {
	my $o = shift;
	my $hashes = shift;
	my $sourceStore = shift;
	my $context = shift;

	return if ! scalar @$hashes;
	push @{$o->{transfers}}, {hashes => $hashes, sourceStore => $sourceStore, context => $context};
}

sub setRecipientActorGroup {
	my $o = shift;
	my $actorGroup = shift; die 'wrong type '.ref($actorGroup).' for $actorGroup' if defined $actorGroup && ref $actorGroup ne 'CDS::ActorGroup';

	$o->{recipients} = [map { $_->actorOnStore } $actorGroup->members];
	$o->{entrustedKeys} = [map { $_->actorOnStore->publicKey } $actorGroup->entrustedActors];
}

sub setRecipients {
	my $o = shift;
	my $recipients = shift;
	my $entrustedKeys = shift;

	$o->{recipients} = $recipients;
	$o->{entrustedKeys} = $entrustedKeys;
}

sub submit {
	my $o = shift;
	my $message = shift;
	my $done = shift;

	# Check if the sent list has been loaded
	return if ! $o->{actor}->sentListReady;

	# Transfer
	my $transfers = $o->{transfers};
	$o->{transfers} = [];
	for my $transfer (@$transfers) {
		my ($missingObject, $store, $error) = $o->{actor}->keyPair->transfer($transfer->{hashes}, $transfer->{sourceStore}, $o->{actor}->messagingPrivateRoot->unsaved);
		return if defined $error;

		if ($missingObject) {
			$missingObject->{context} = $transfer->{context};
			return undef, $missingObject;
		}
	}

	# Send the message
	return CDS::MessageChannel::Submission->new($o, $message, $done);
}

sub clear {
	my $o = shift;

	$o->item->clear(CDS->now + $o->{validity});
}

package CDS::MessageChannel::Submission;

sub new {
	my $class = shift;
	my $channel = shift;
	my $message = shift;
	my $done = shift;

	$channel->{currentSubmissionId} += 1;

	my $o = bless {
		channel => $channel,
		message => $message,
		done => $done,
		submissionId => $channel->{currentSubmissionId},
		recipients => [$channel->recipients],
		entrustedKeys => [$channel->entrustedKeys],
		expires => CDS->now + $channel->validity,
		};

	# Add the current envelope hash to the obsolete hashes
	my $item = $channel->item;
	$channel->{obsoleteHashes}->{$item->envelopeHash->bytes} = $item->envelopeHash if $item->envelopeHash;
	$o->{obsoleteHashesSnapshot} = [values %{$channel->{obsoleteHashes}}];

	# Create an envelope
	my $publicKeys = [];
	push @$publicKeys, $channel->{actor}->keyPair->publicKey;
	push @$publicKeys, map { $_->publicKey } @{$o->{recipients}};
	push @$publicKeys, @{$o->{entrustedKeys}};
	$o->{envelopeObject} = $channel->{actor}->keyPair->createMessageEnvelope($channel->{actor}->messagingStoreUrl, $message, $publicKeys, $o->{expires})->toObject;
	$o->{envelopeHash} = $o->{envelopeObject}->calculateHash;

	# Set the new item and wait until it gets saved
	$channel->{unsaved}->startSaving;
	$channel->{unsaved}->savingState->addDataSavedHandler($o);
	$channel->{actor}->sentList->unsaved->state->merge($channel->{unsaved}->savingState);
	$item->set($o->{expires}, $o->{envelopeHash}, $message);
	$channel->{unsaved}->savingDone;

	return $o;
}

sub channel { shift->{channel} }
sub message { shift->{message} }
sub recipients {
	my $o = shift;
	 @{$o->{recipients}} }
sub entrustedKeys {
	my $o = shift;
	 @{$o->{entrustedKeys}} }
sub expires { shift->{expires} }
sub envelopeObject { shift->{envelopeObject} }
sub envelopeHash { shift->{envelopeHash} }

sub onDataSaved {
	my $o = shift;

	# If we are not the head any more, give up
	return $o->{done}->onMessageChannelSubmissionCancelled if $o->{submissionId} != $o->{channel}->{currentSubmissionId};
	$o->{channel}->{obsoleteHashes}->{$o->{envelopeHash}->bytes} = $o->{envelopeHash};

	# Process all recipients
	my $succeeded = 0;
	my $failed = 0;
	for my $recipient (@{$o->{recipients}}) {
		my $modifications = CDS::StoreModifications->new;

		# Prepare the list of removals
		my $removals = [];
		for my $hash (@{$o->{obsoleteHashesSnapshot}}) {
			$modifications->remove($recipient->publicKey->hash, 'messages', $hash);
		}

		# Add the message entry
		$modifications->add($recipient->publicKey->hash, 'messages', $o->{envelopeHash}, $o->{envelopeObject});
		my $error = $recipient->store->modify($modifications, $o->{channel}->{actor}->keyPair);

		if (defined $error) {
			$failed += 1;
			$o->{done}->onMessageChannelSubmissionRecipientFailed($recipient, $error);
		} else {
			$succeeded += 1;
			$o->{done}->onMessageChannelSubmissionRecipientDone($recipient);
		}
	}

	if ($failed == 0 || scalar keys %{$o->{obsoleteHashes}} > 64) {
		for my $hash (@{$o->{obsoleteHashesSnapshot}}) {
			delete $o->{channel}->{obsoleteHashes}->{$hash->bytes};
		}
	}

	$o->{done}->onMessageChannelSubmissionDone($succeeded, $failed);
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

package CDS::NewAnnounce;

sub new {
	my $class = shift;
	my $messagingStore = shift;

	my $o = bless {
		messagingStore => $messagingStore,
		unsaved => CDS::Unsaved->new($messagingStore->store),
		transfers => [],
		card => CDS::Record->new,
		};

	my $publicKey = $messagingStore->actor->keyPair->publicKey;
	$o->{card}->add('public key')->addHash($publicKey->hash);
	$o->addObject($publicKey->hash, $publicKey->object);
	return $o;
}

sub messagingStore { shift->{messagingStore} }
sub card { shift->{card} }

sub addObject {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

	$o->{unsaved}->state->addObject($hash, $object);
}

sub addTransfer {
	my $o = shift;
	my $hashes = shift;
	my $sourceStore = shift;
	my $context = shift;

	return if ! scalar @$hashes;
	push @{$o->{transfers}}, {hashes => $hashes, sourceStore => $sourceStore, context => $context};
}

sub addActorGroup {
	my $o = shift;
	my $actorGroupBuilder = shift;

	$actorGroupBuilder->addToRecord($o->{card}, 0);
}

sub submit {
	my $o = shift;

	my $keyPair = $o->{messagingStore}->actor->keyPair;

	# Create the public card
	my $cardObject = $o->{card}->toObject;
	my $cardHash = $cardObject->calculateHash;
	$o->addObject($cardHash, $cardObject);

	# Prepare the public envelope
	my $me = $keyPair->publicKey->hash;
	my $envelopeObject = $keyPair->createPublicEnvelope($cardHash)->toObject;
	my $envelopeHash = $envelopeObject->calculateHash;
	$o->addTransfer([$cardHash], $o->{unsaved}, 'Announcing');

	# Transfer all trees
	for my $transfer (@{$o->{transfers}}) {
		my ($missingObject, $store, $error) = $keyPair->transfer($transfer->{hashes}, $transfer->{sourceStore}, $o->{messagingStore}->store);
		return if defined $error;

		if ($missingObject) {
			$missingObject->{context} = $transfer->{context};
			return undef, $missingObject;
		}
	}

	# Prepare a modification
	my $modifications = CDS::StoreModifications->new;
	$modifications->add($me, 'public', $envelopeHash, $envelopeObject);

	# List the current cards to remove them
	# Ignore errors, in the worst case, we are going to have multiple entries in the public box
	my ($hashes, $error) = $o->{messagingStore}->store->list($me, 'public', 0, $keyPair);
	if ($hashes) {
		for my $hash (@$hashes) {
			$modifications->remove($me, 'public', $hash);
		}
	}

	# Modify the public box
	my $modifyError = $o->{messagingStore}->store->modify($modifications, $keyPair);
	return if defined $modifyError;
	return $envelopeHash, $cardHash;
}

package CDS::NewMessagingStore;

sub new {
	my $class = shift;
	my $actor = shift;
	my $store = shift;

	return bless {
		actor => $actor,
		store => $store,
		};
}

sub actor { shift->{actor} }
sub store { shift->{store} }

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

# Reads the private box of an actor.
package CDS::PrivateBoxReader;

sub new {
	my $class = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $store = shift;
	my $delegate = shift;

	return bless {
		keyPair => $keyPair,
		actorOnStore => CDS::ActorOnStore->new($keyPair->publicKey, $store),
		delegate => $delegate,
		entries => {},
		};
}

sub keyPair { shift->{keyPair} }
sub actorOnStore { shift->{actorOnStore} }
sub delegate { shift->{delegate} }

sub read {
	my $o = shift;

	my $store = $o->{actorOnStore}->store;
	my ($hashes, $listError) = $store->list($o->{actorOnStore}->publicKey->hash, 'private', 0, $o->{keyPair});
	return if defined $listError;

	# Keep track of the processed entries
	my $newEntries = {};
	for my $hash (@$hashes) {
		$newEntries->{$hash->bytes} = $o->{entries}->{$hash->bytes} // {hash => $hash, processed => 0};
	}
	$o->{entries} = $newEntries;

	# Process new entries
	for my $entry (values %$newEntries) {
		next if $entry->{processed};

		# Get the envelope
		my ($object, $getError) = $store->get($entry->{hash}, $o->{keyPair});
		return if defined $getError;

		if (! defined $object) {
			$o->invalid($entry, 'Envelope object not found.');
			next;
		}

		# Parse the record
		my $envelope = CDS::Record->fromObject($object);
		if (! $envelope) {
			$o->invalid($entry, 'Envelope is not a record.');
			next;
		}

		# Read the content hash
		my $contentHash = $envelope->child('content')->hashValue;
		if (! $contentHash) {
			$o->invalid($entry, 'Missing content hash.');
			next;
		}

		# Verify the signature
		if (! CDS->verifyEnvelopeSignature($envelope, $o->{keyPair}->publicKey, $contentHash)) {
			$o->invalid($entry, 'Invalid signature.');
			next;
		}

		# Decrypt the key
		my $aesKey = $o->{keyPair}->decryptKeyOnEnvelope($envelope);
		if (! $aesKey) {
			$o->invalid($entry, 'Not encrypted for us.');
			next;
		}

		# Retrieve the content
		my $contentHashAndKey = CDS::HashAndKey->new($contentHash, $aesKey);
		my ($contentRecord, $contentObject, $contentInvalidReason, $contentStoreError) = $o->{keyPair}->getAndDecryptRecord($contentHashAndKey, $store);
		return if defined $contentStoreError;

		if (defined $contentInvalidReason) {
			$o->invalid($entry, $contentInvalidReason);
			next;
		}

		$entry->{processed} = 1;
		my $source = CDS::Source->new($o->{keyPair}, $o->{actorOnStore}, 'private', $entry->{hash});
		$o->{delegate}->onPrivateBoxEntry($source, $envelope, $contentHashAndKey, $contentRecord);
	}

	return 1;
}

sub invalid {
	my $o = shift;
	my $entry = shift;
	my $reason = shift;

	$entry->{processed} = 1;
	my $source = CDS::Source->new($o->{actorOnStore}, 'private', $entry->{hash});
	$o->{delegate}->onPrivateBoxInvalidEntry($source, $reason);
}

# Delegate
# onPrivateBoxEntry($source, $envelope, $contentHashAndKey, $contentRecord)
# onPrivateBoxInvalidEntry($source, $reason)

package CDS::PrivateRoot;

sub new {
	my $class = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $store = shift;
	my $delegate = shift;

	my $o = bless {
		unsaved => CDS::Unsaved->new($store),
		delegate => $delegate,
		dataHandlers => {},
		hasChanges => 0,
		procured => 0,
		mergedEntries => [],
		};

	$o->{privateBoxReader} = CDS::PrivateBoxReader->new($keyPair, $store, $o);
	return $o;
}

sub delegate { shift->{delegate} }
sub privateBoxReader { shift->{privateBoxReader} }
sub unsaved { shift->{unsaved} }
sub hasChanges { shift->{hasChanges} }
sub procured { shift->{procured} }

sub addDataHandler {
	my $o = shift;
	my $label = shift;
	my $dataHandler = shift;

	$o->{dataHandlers}->{$label} = $dataHandler;
}

sub removeDataHandler {
	my $o = shift;
	my $label = shift;
	my $dataHandler = shift;

	my $registered = $o->{dataHandlers}->{$label};
	return if $registered != $dataHandler;
	delete $o->{dataHandlers}->{$label};
}

# *** Procurement

sub procure {
	my $o = shift;
	my $interval = shift;

	my $now = CDS->now;
	return $o->{procured} if $o->{procured} + $interval > $now;
	$o->{privateBoxReader}->read // return;
	$o->{procured} = $now;
	return $now;
}

# *** Merging

sub onPrivateBoxEntry {
	my $o = shift;
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
	my $contentHashAndKey = shift;
	my $content = shift;

	for my $section ($content->children) {
		my $dataHandler = $o->{dataHandlers}->{$section->bytes} // next;
		$dataHandler->mergeData($section);
	}

	push @{$o->{mergedEntries}}, $source->hash;
}

sub onPrivateBoxInvalidEntry {
	my $o = shift;
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';
	my $reason = shift;

	$o->{delegate}->onPrivateRootReadingInvalidEntry($source, $reason);
	$source->discard;
}

# *** Saving

sub dataChanged {
	my $o = shift;

	$o->{hasChanges} = 1;
}

sub save {
	my $o = shift;
	my $entrustedKeys = shift;

	$o->{unsaved}->startSaving;
	return $o->savingSucceeded if ! $o->{hasChanges};
	$o->{hasChanges} = 0;

	# Create the record
	my $record = CDS::Record->new;
	$record->add('created')->addInteger(CDS->now);
	$record->add('client')->add(CDS->version);
	for my $label (keys %{$o->{dataHandlers}}) {
		my $dataHandler = $o->{dataHandlers}->{$label};
		$dataHandler->addDataTo($record->add($label));
	}

	# Submit the object
	my $key = CDS->randomKey;
	my $object = $record->toObject->crypt($key);
	my $hash = $object->calculateHash;
	$o->{unsaved}->savingState->addObject($hash, $object);
	my $hashAndKey = CDS::HashAndKey->new($hash, $key);

	# Create the envelope
	my $keyPair = $o->{privateBoxReader}->keyPair;
	my $publicKeys = [$keyPair->publicKey, @$entrustedKeys];
	my $envelopeObject = $keyPair->createPrivateEnvelope($hashAndKey, $publicKeys)->toObject;
	my $envelopeHash = $envelopeObject->calculateHash;
	$o->{unsaved}->savingState->addObject($envelopeHash, $envelopeObject);

	# Transfer
	my ($missing, $store, $storeError) = $keyPair->transfer([$hash], $o->{unsaved}, $o->{privateBoxReader}->actorOnStore->store);
	return $o->savingFailed($missing) if defined $missing || defined $storeError;

	# Modify the private box
	my $modifications = CDS::StoreModifications->new;
	$modifications->add($keyPair->publicKey->hash, 'private', $envelopeHash, $envelopeObject);
	for my $hash (@{$o->{mergedEntries}}) {
		$modifications->remove($keyPair->publicKey->hash, 'private', $hash);
	}

	my $modifyError = $o->{privateBoxReader}->actorOnStore->store->modify($modifications, $keyPair);
	return $o->savingFailed if defined $modifyError;

	# Set the new merged hashes
	$o->{mergedEntries} = [$envelopeHash];
	return $o->savingSucceeded;
}

sub savingSucceeded {
	my $o = shift;

	# Discard all merged sources
	for my $source ($o->{unsaved}->savingState->mergedSources) {
		$source->discard;
	}

	# Call all data saved handlers
	for my $handler ($o->{unsaved}->savingState->dataSavedHandlers) {
		$handler->onDataSaved;
	}

	$o->{unsaved}->savingDone;
	return 1;
}

sub savingFailed {
	my $o = shift;
	my $missing = shift;
		# private
	$o->{unsaved}->savingFailed;
	$o->{hasChanges} = 1;
	return undef, $missing;
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

package CDS::PublicKeyCache;

sub new {
	my $class = shift;
	my $maxSize = shift;

	return bless {
		cache => {},
		maxSize => $maxSize,
		};
}

sub add {
	my $o = shift;
	my $publicKey = shift; die 'wrong type '.ref($publicKey).' for $publicKey' if defined $publicKey && ref $publicKey ne 'CDS::PublicKey';

	$o->{cache}->{$publicKey->hash->bytes} = {publicKey => $publicKey, lastAccess => CDS->now};
	$o->deleteOldest;
	return;
}

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	my $entry = $o->{cache}->{$hash->bytes} // return;
	$entry->{lastAccess} = CDS->now;
	return $entry->{publicKey};
}

sub deleteOldest {
	my $o = shift;
		# private
	return if scalar values %{$o->{cache}} < $o->{maxSize};

	my @entries = sort { $a->{lastAccess} <=> $b->{lastAccess} } values %{$o->{cache}};
	my $toRemove = int(scalar(@entries) - $o->{maxSize} / 2);
	for my $entry (@entries) {
		$toRemove -= 1;
		last if $toRemove <= 0;
		delete $o->{cache}->{$entry->{publicKey}->hash->bytes};
	}
}

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

package CDS::ReceivedMessage;

sub new {
	my $class = shift;
	my $messageBoxReader = shift;
	my $entry = shift;
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
	my $senderStoreUrl = shift;
	my $sender = shift;
	my $content = shift;
	my $streamHead = shift;

	return bless {
		messageBoxReader => $messageBoxReader,
		entry => $entry,
		source => $source,
		envelope => $envelope,
		senderStoreUrl => $senderStoreUrl,
		sender => $sender,
		content => $content,
		streamHead => $streamHead,
		isDone => 0,
		};
}

sub source { shift->{source} }
sub envelope { shift->{envelope} }
sub senderStoreUrl { shift->{senderStoreUrl} }
sub sender { shift->{sender} }
sub content { shift->{content} }

sub waitForSenderStore {
	my $o = shift;

	$o->{entry}->{waitingForStore} = $o->sender->store;
}

sub skip {
	my $o = shift;

	$o->{entry}->{processed} = 0;
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

package CDS::RootDocument;

use parent -norequire, 'CDS::Document';

sub new {
	my $class = shift;
	my $privateRoot = shift;
	my $label = shift;

	my $o = $class->SUPER::new($privateRoot->privateBoxReader->keyPair, $privateRoot->unsaved);
	$o->{privateRoot} = $privateRoot;
	$o->{label} = $label;
	$privateRoot->addDataHandler($label, $o);

	# State
	$o->{dataSharingMessage} = undef;
	return $o;
}

sub privateRoot { shift->{privateRoot} }
sub label { shift->{label} }

sub savingDone {
	my $o = shift;
	my $revision = shift;
	my $newPart = shift;
	my $obsoleteParts = shift;

	$o->{privateRoot}->unsaved->state->merge($o->{unsaved}->savingState);
	$o->{unsaved}->savingDone;
	$o->{privateRoot}->dataChanged if $newPart || scalar @$obsoleteParts;
}

sub addDataTo {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	for my $part (sort { $a->{hashAndKey}->hash->bytes cmp $b->{hashAndKey}->hash->bytes } values %{$o->{parts}}) {
		$record->addHashAndKey($part->{hashAndKey});
	}
}
sub mergeData {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	my @hashesAndKeys;
	for my $child ($record->children) {
		push @hashesAndKeys, $child->asHashAndKey // next;
	}

	$o->merge(@hashesAndKeys);
}

sub mergeExternalData {
	my $o = shift;
	my $store = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';

	my @hashes;
	my @hashesAndKeys;
	for my $child ($record->children) {
		my $hashAndKey = $child->asHashAndKey // next;
		next if $o->{parts}->{$hashAndKey->hash->bytes};
		push @hashes, $hashAndKey->hash;
		push @hashesAndKeys, $hashAndKey;
	}

	my ($missing, $transferStore, $storeError) = $o->{keyPair}->transfer([@hashes], $store, $o->{privateRoot}->unsaved);
	return if defined $storeError;
	return if $missing;

	if ($source) {
		$source->keep;
		$o->{privateRoot}->unsaved->state->addMergedSource($source);
	}

	$o->merge(@hashesAndKeys);
	return 1;
}

package CDS::Selector;

sub root {
	my $class = shift;
	my $document = shift;

	return bless {document => $document, id => 'ROOT', label => ''};
}

sub document { shift->{document} }
sub parent { shift->{parent} }
sub label { shift->{label} }

sub child {
	my $o = shift;
	my $label = shift;

	return bless {
		document => $o->{document},
		id => $o->{id}.'/'.unpack('H*', $label),
		parent => $o,
		label => $label,
		};
}

sub childWithText {
	my $o = shift;
	my $label = shift;

	return $o->child(Encode::encode_utf8($label // ''));
}

sub children {
	my $o = shift;

	my $item = $o->{document}->get($o) // return;
	return map { $_->{selector} } @{$item->{children}};
}

# Value

sub revision {
	my $o = shift;

	my $item = $o->{document}->get($o) // return 0;
	return $item->{revision};
}

sub isSet {
	my $o = shift;

	my $item = $o->{document}->get($o) // return;
	return scalar $item->{record}->children > 0;
}

sub record {
	my $o = shift;

	my $item = $o->{document}->get($o) // return CDS::Record->new;
	return $item->{record};
}

sub set {
	my $o = shift;
	my $record = shift // return; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	my $now = CDS->now;
	my $item = $o->{document}->getOrCreate($o);
	$item->mergeValue($o->{document}->{changes}, $item->{revision} >= $now ? $item->{revision} + 1 : $now, $record);
}

sub merge {
	my $o = shift;
	my $revision = shift;
	my $record = shift // return; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	my $item = $o->{document}->getOrCreate($o);
	return $item->mergeValue($o->{document}->{changes}, $revision, $record);
}

sub clear {
	my $o = shift;
	 $o->set(CDS::Record->new) }

sub clearInThePast {
	my $o = shift;

	$o->merge($o->revision + 1, CDS::Record->new) if $o->isSet;
}

sub forget {
	my $o = shift;

	my $item = $o->{document}->get($o) // return;
	$item->forget;
}

sub forgetBranch {
	my $o = shift;

	for my $child ($o->children) { $child->forgetBranch; }
	$o->forget;
}

# Convenience methods (simple interface)

sub firstValue {
	my $o = shift;

	my $item = $o->{document}->get($o) // return CDS::Record->new;
	return $item->{record}->firstChild;
}

sub bytesValue {
	my $o = shift;
	 $o->firstValue->bytes }
sub hashValue {
	my $o = shift;
	 $o->firstValue->hash }
sub textValue {
	my $o = shift;
	 $o->firstValue->asText }
sub unsignedValue {
	my $o = shift;
	 $o->firstValue->asUnsigned }
sub integerValue {
	my $o = shift;
	 $o->firstValue->asInteger }
sub booleanValue {
	my $o = shift;
	 $o->firstValue->asBoolean }
sub hashAndKeyValue {
	my $o = shift;
	 $o->firstValue->asHashAndKey }

# Sets a new value unless the node has that value already.
sub setBytes {
	my $o = shift;
	my $bytes = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	my $record = CDS::Record->new;
	$record->add($bytes, $hash);
	$o->set($record);
}

sub setHash {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	 $o->setBytes('', $hash); };
sub setText {
	my $o = shift;
	my $value = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	 $o->setBytes(Encode::encode_utf8($value), $hash); };
sub setBoolean {
	my $o = shift;
	my $value = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	 $o->setBytes(CDS->bytesFromBoolean($value), $hash); };
sub setInteger {
	my $o = shift;
	my $value = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	 $o->setBytes(CDS->bytesFromInteger($value), $hash); };
sub setUnsigned {
	my $o = shift;
	my $value = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	 $o->setBytes(CDS->bytesFromUnsigned($value), $hash); };
sub setHashAndKey {
	my $o = shift;
	my $hashAndKey = shift; die 'wrong type '.ref($hashAndKey).' for $hashAndKey' if defined $hashAndKey && ref $hashAndKey ne 'CDS::HashAndKey';
	 $o->setBytes($hashAndKey->key, $hashAndKey->hash); };

# Adding objects and merged sources

sub addObject {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

	$o->{document}->{unsaved}->state->addObject($hash, $object);
}

sub addMergedSource {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	$o->{document}->{unsaved}->state->addMergedSource($hash);
}

package CDS::SentItem;

use parent -norequire, 'CDS::UnionList::Item';

sub new {
	my $class = shift;
	my $unionList = shift;
	my $id = shift;

	my $o = $class->SUPER::new($unionList, $id);
	$o->{validUntil} = 0;
	$o->{message} = CDS::Record->new;
	return $o;
}

sub validUntil { shift->{validUntil} }
sub envelopeHash {
	my $o = shift;
	 CDS::Hash->fromBytes($o->{message}->bytes) }
sub envelopeHashBytes {
	my $o = shift;
	 $o->{message}->bytes }
sub message { shift->{message} }

sub addToRecord {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	$record->add($o->{id})->addInteger($o->{validUntil})->addRecord($o->{message});
}

sub set {
	my $o = shift;
	my $validUntil = shift;
	my $envelopeHash = shift; die 'wrong type '.ref($envelopeHash).' for $envelopeHash' if defined $envelopeHash && ref $envelopeHash ne 'CDS::Hash';
	my $messageRecord = shift; die 'wrong type '.ref($messageRecord).' for $messageRecord' if defined $messageRecord && ref $messageRecord ne 'CDS::Record';

	my $message = CDS::Record->new($envelopeHash->bytes);
	$message->addRecord($messageRecord->children);
	$o->merge($o->{unionList}->{changes}, CDS->max($validUntil, $o->{validUntil} + 1), $message);
}

sub clear {
	my $o = shift;
	my $validUntil = shift;

	$o->merge($o->{unionList}->{changes}, CDS->max($validUntil, $o->{validUntil} + 1), CDS::Record->new);
}

sub merge {
	my $o = shift;
	my $part = shift;
	my $validUntil = shift;
	my $message = shift;

	return if $o->{validUntil} > $validUntil;
	return if $o->{validUntil} == $validUntil && $part->{size} < $o->{part}->{size};
	$o->{validUntil} = $validUntil;
	$o->{message} = $message;
	$o->setPart($part);
}

package CDS::SentList;

use parent -norequire, 'CDS::UnionList';

sub new {
	my $class = shift;
	my $privateRoot = shift;

	return $class->SUPER::new($privateRoot, 'sent list');
}

sub createItem {
	my $o = shift;
	my $id = shift;

	return CDS::SentItem->new($o, $id);
}

sub mergeRecord {
	my $o = shift;
	my $part = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	my $item = $o->getOrCreate($record->bytes);
	for my $child ($record->children) {
		my $validUntil = $child->asInteger;
		my $message = $child->firstChild;
		$item->merge($part, $validUntil, $message);
	}
}

sub forgetObsoleteItems {
	my $o = shift;

	my $now = CDS->now;
	my $toDelete = [];
	for my $item (values %{$o->{items}}) {
		next if $item->{validUntil} >= $now;
		$o->forgetItem($item);
	}
}

package CDS::Source;

sub new {
	my $class = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $actorOnStore = shift; die 'wrong type '.ref($actorOnStore).' for $actorOnStore' if defined $actorOnStore && ref $actorOnStore ne 'CDS::ActorOnStore';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

	return bless {
		keyPair => $keyPair,
		actorOnStore => $actorOnStore,
		boxLabel => $boxLabel,
		hash => $hash,
		referenceCount => 1,
		};
}

sub keyPair { shift->{keyPair} }
sub actorOnStore { shift->{actorOnStore} }
sub boxLabel { shift->{boxLabel} }
sub hash { shift->{hash} }
sub referenceCount { shift->{referenceCount} }

sub keep {
	my $o = shift;

	if ($o->{referenceCount} < 1) {
		warn 'The source '.$o->{actorOnStore}->publicKey->hash->hex.'/'.$o->{boxLabel}.'/'.$o->{hash}->hex.' has already been discarded, and cannot be kept any more.';
		return;
	}

	$o->{referenceCount} += 1;
}

sub discard {
	my $o = shift;

	if ($o->{referenceCount} < 1) {
		warn 'The source '.$o->{actorOnStore}->publicKey->hash->hex.'/'.$o->{boxLabel}.'/'.$o->{hash}->hex.' has already been discarded, and cannot be discarded again.';
		return;
	}

	$o->{referenceCount} -= 1;
	return if $o->{referenceCount} > 0;

	$o->{actorOnStore}->store->remove($o->{actorOnStore}->publicKey->hash, $o->{boxLabel}, $o->{hash}, $o->{keyPair});
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
	my $objectsRecord = $record->add('puts');
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
	readEntriesFromRecord($modifications->{addition}, $record->child('add')) // return;
	readEntriesFromRecord($modifications->{removal}, $record->child('remove')) // return;

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

package CDS::StreamCache;

sub new {
	my $class = shift;
	my $pool = shift;
	my $actorOnStore = shift; die 'wrong type '.ref($actorOnStore).' for $actorOnStore' if defined $actorOnStore && ref $actorOnStore ne 'CDS::ActorOnStore';
	my $timeout = shift;

	return bless {
		pool => $pool,
		actorOnStore => $actorOnStore,
		timeout => $timeout,
		cache => {},
		};
}

sub messageBoxReader { shift->{messageBoxReader} }

sub removeObsolete {
	my $o = shift;

	my $limit = CDS->now - $o->{timeout};
	for my $key (%{$o->{knownStreamHeads}}) {
		my $streamHead = $o->{knownStreamHeads}->{$key} // next;
		next if $streamHead->lastUsed < $limit;
		delete $o->{knownStreamHeads}->{$key};
	}
}

sub readStreamHead {
	my $o = shift;
	my $head = shift;

	my $streamHead = $o->{knownStreamHeads}->{$head->hex};
	if ($streamHead) {
		$streamHead->stillInUse;
		return $streamHead;
	}

	# Retrieve the head envelope
	my ($object, $getError) = $o->{actorOnStore}->store->get($head, $o->{pool}->{keyPair});
	return if defined $getError;

	# Parse the head envelope
	my $envelope = CDS::Record->fromObject($object);
	return $o->invalid($head, 'Not a record.') if ! $envelope;

	# Read the embedded content object
	my $encryptedBytes = $envelope->child('content')->bytesValue;
	return $o->invalid($head, 'Missing content object.') if ! length $encryptedBytes;

	# Decrypt the key
	my $aesKey = $o->{pool}->{keyPair}->decryptKeyOnEnvelope($envelope);
	return $o->invalid($head, 'Not encrypted for us.') if ! $aesKey;

	# Decrypt the content
	my $contentObject = CDS::Object->fromBytes(CDS::C::aesCrypt($encryptedBytes, $aesKey, CDS->zeroCTR));
	return $o->invalid($head, 'Invalid content object.') if ! $contentObject;

	my $content = CDS::Record->fromObject($contentObject);
	return $o->invalid($head, 'Content object is not a record.') if ! $content;

	# Verify the sender hash
	my $senderHash = $content->child('sender')->hashValue;
	return $o->invalid($head, 'Missing sender hash.') if ! $senderHash;

	# Verify the sender store
	my $storeRecord = $content->child('store');
	return $o->invalid($head, 'Missing sender store.') if ! scalar $storeRecord->children;

	my $senderStoreUrl = $storeRecord->textValue;
	my $senderStore = $o->{pool}->{delegate}->onMessageBoxVerifyStore($senderStoreUrl, $head, $envelope, $senderHash);
	return $o->invalid($head, 'Invalid sender store.') if ! $senderStore;

	# Retrieve the sender's public key
	my ($senderPublicKey, $invalidReason, $publicKeyStoreError) = $o->getPublicKey($senderHash, $senderStore);
	return if defined $publicKeyStoreError;
	return $o->invalid($head, 'Failed to retrieve the sender\'s public key: '.$invalidReason) if defined $invalidReason;

	# Verify the signature
	my $signedHash = CDS::Hash->calculateFor($encryptedBytes);
	return $o->invalid($head, 'Invalid signature.') if ! CDS->verifyEnvelopeSignature($envelope, $senderPublicKey, $signedHash);

	# The envelope is valid
	my $sender = CDS::ActorOnStore->new($senderPublicKey, $senderStore);
	my $newStreamHead = CDS::StreamHead->new($head, $envelope, $senderStoreUrl, $sender, $aesKey, $content);
	$o->{knownStreamHeads}->{$head->hex} = $newStreamHead;
	return $newStreamHead;
}

sub invalid {
	my $o = shift;
	my $head = shift;
	my $reason = shift;
		# private
	my $newStreamHead = CDS::StreamHead->new($head, undef, undef, undef, undef, undef, $reason);
	$o->{knownStreamHeads}->{$head->hex} = $newStreamHead;
	return $newStreamHead;
}

package CDS::StreamHead;

sub new {
	my $class = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
	my $senderStoreUrl = shift;
	my $sender = shift;
	my $content = shift;
	my $error = shift;

	return bless {
		hash => $hash,
		envelope => $envelope,
		senderStoreUrl => $senderStoreUrl,
		sender => $sender,
		content => $content,
		error => $error,
		lastUsed => CDS->now,
		};
}

sub hash { shift->{hash} }
sub envelope { shift->{envelope} }
sub senderStoreUrl { shift->{senderStoreUrl} }
sub sender { shift->{sender} }
sub content { shift->{content} }
sub error { shift->{error} }
sub isValid {
	my $o = shift;
	 ! defined $o->{error} }
sub lastUsed { shift->{lastUsed} }

sub stillInUse {
	my $o = shift;

	$o->{lastUsed} = CDS->now;
}

package CDS::SubDocument;

use parent -norequire, 'CDS::Document';

sub new {
	my $class = shift;
	my $parentSelector = shift; die 'wrong type '.ref($parentSelector).' for $parentSelector' if defined $parentSelector && ref $parentSelector ne 'CDS::Selector';

	my $o = $class->SUPER::new($parentSelector->document->keyPair, $parentSelector->document->unsaved);
	$o->{parentSelector} = $parentSelector;
	return $o;
}

sub parentSelector { shift->{parentSelector} }

sub partSelector {
	my $o = shift;
	my $hashAndKey = shift; die 'wrong type '.ref($hashAndKey).' for $hashAndKey' if defined $hashAndKey && ref $hashAndKey ne 'CDS::HashAndKey';

	$o->{parentSelector}->child(substr($hashAndKey->hash->bytes, 0, 16));
}

sub read {
	my $o = shift;

	$o->merge(map { $_->hashAndKeyValue } $o->{parentSelector}->children);
	return $o->SUPER::read;
}

sub savingDone {
	my $o = shift;
	my $revision = shift;
	my $newPart = shift;
	my $obsoleteParts = shift;

	$o->{parentSelector}->document->unsaved->state->merge($o->{unsaved}->savingState);

	# Remove obsolete parts
	for my $part (@$obsoleteParts) {
		$o->partSelector($part->{hashAndKey})->merge($revision, CDS::Record->new);
	}

	# Add the new part
	if ($newPart) {
		my $record = CDS::Record->new;
		$record->addHashAndKey($newPart->{hashAndKey});
		$o->partSelector($newPart->{hashAndKey})->merge($revision, $record);
	}

	$o->{unsaved}->savingDone;
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

package CDS::UnionList;

sub new {
	my $class = shift;
	my $privateRoot = shift;
	my $label = shift;

	my $o = bless {
		privateRoot => $privateRoot,
		label => $label,
		unsaved => CDS::Unsaved->new($privateRoot->unsaved),
		items => {},
		parts => {},
		hasPartsToMerge => 0,
		}, $class;

	$o->{unused} = CDS::UnionList::Part->new;
	$o->{changes} = CDS::UnionList::Part->new;
	$privateRoot->addDataHandler($label, $o);
	return $o;
}

sub privateRoot { shift->{privateRoot} }
sub unsaved { shift->{unsaved} }
sub items {
	my $o = shift;
	 values %{$o->{items}} }
sub parts {
	my $o = shift;
	 values %{$o->{parts}} }

sub get {
	my $o = shift;
	my $id = shift;
	 $o->{items}->{$id} }

sub getOrCreate {
	my $o = shift;
	my $id = shift;

	my $item = $o->{items}->{$id};
	return $item if $item;
	my $newItem = $o->createItem($id);
	$o->{items}->{$id} = $newItem;
	return $newItem;
}

# abstract sub createItem($o, $id)
# abstract sub forgetObsoleteItems($o)

sub forget {
	my $o = shift;
	my $id = shift;

	my $item = $o->{items}->{$id} // return;
	$item->{part}->{count} -= 1;
	delete $o->{items}->{$id};
}

sub forgetItem {
	my $o = shift;
	my $item = shift;

	$item->{part}->{count} -= 1;
	delete $o->{items}->{$item->id};
}

# *** MergeableData interface

sub addDataTo {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	for my $part (sort { $a->{hashAndKey}->hash->bytes cmp $b->{hashAndKey}->hash->bytes } values %{$o->{parts}}) {
		$record->addHashAndKey($part->{hashAndKey});
	}
}

sub mergeData {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

	my @hashesAndKeys;
	for my $child ($record->children) {
		push @hashesAndKeys, $child->asHashAndKey // next;
	}

	$o->merge(@hashesAndKeys);
}

sub mergeExternalData {
	my $o = shift;
	my $store = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';

	my @hashes;
	my @hashesAndKeys;
	for my $child ($record->children) {
		my $hashAndKey = $child->asHashAndKey // next;
		next if $o->{parts}->{$hashAndKey->hash->bytes};
		push @hashes, $hashAndKey->hash;
		push @hashesAndKeys, $hashAndKey;
	}

	my $keyPair = $o->{privateRoot}->privateBoxReader->keyPair;
	my ($missing, $transferStore, $storeError) = $keyPair->transfer([@hashes], $store, $o->{privateRoot}->unsaved);
	return if defined $storeError;
	return if $missing;

	if ($source) {
		$source->keep;
		$o->{privateRoot}->unsaved->state->addMergedSource($source);
	}

	$o->merge(@hashesAndKeys);
	return 1;
}

sub merge {
	my $o = shift;

	for my $hashAndKey (@_) {
		next if ! $hashAndKey;
		next if $o->{parts}->{$hashAndKey->hash->bytes};
		my $part = CDS::UnionList::Part->new;
		$part->{hashAndKey} = $hashAndKey;
		$o->{parts}->{$hashAndKey->hash->bytes} = $part;
		$o->{hasPartsToMerge} = 1;
	}
}

# *** Reading

sub read {
	my $o = shift;

	return 1 if ! $o->{hasPartsToMerge};

	# Load the parts
	for my $part (values %{$o->{parts}}) {
		next if $part->{isMerged};
		next if $part->{loadedRecord};

		my ($record, $object, $invalidReason, $storeError) = $o->{privateRoot}->privateBoxReader->keyPair->getAndDecryptRecord($part->{hashAndKey}, $o->{privateRoot}->unsaved);
		return if defined $storeError;

		delete $o->{parts}->{$part->{hashAndKey}->hash->bytes} if defined $invalidReason;
		$part->{loadedRecord} = $record;
	}

	# Merge the loaded parts
	for my $part (values %{$o->{parts}}) {
		next if $part->{isMerged};
		next if ! $part->{loadedRecord};

		# Merge
		for my $child ($part->{loadedRecord}->children) {
			$o->mergeRecord($part, $child);
		}

		delete $part->{loadedRecord};
		$part->{isMerged} = 1;
	}

	$o->{hasPartsToMerge} = 0;
	return 1;
}

# abstract sub mergeRecord($o, $part, $record)

# *** Saving

sub hasChanges {
	my $o = shift;
	 $o->{changes}->{count} > 0 }

sub save {
	my $o = shift;

	$o->forgetObsoleteItems;
	$o->{unsaved}->startSaving;

	if ($o->{changes}->{count}) {
		# Take the changes
		my $newPart = $o->{changes};
		$o->{changes} = CDS::UnionList::Part->new;

		# Add all changes
		my $record = CDS::Record->new;
		for my $item (values %{$o->{items}}) {
			next if $item->{part} != $newPart;
			$item->addToRecord($record);
		}

		# Select all parts smaller than 2 * count elements
		my $count = $newPart->{count};
		while (1) {
			my $addedPart = 0;
			for my $part (values %{$o->{parts}}) {
				next if ! $part->{isMerged} || $part->{selected} || $part->{count} >= $count * 2;
				$count += $part->{count};
				$part->{selected} = 1;
				$addedPart = 1;
			}

			last if ! $addedPart;
		}

		# Include the selected items
		for my $item (values %{$o->{items}}) {
			next if ! $item->{part}->{selected};
			$item->setPart($newPart);
			$item->addToRecord($record);
		}

		# Serialize the new part
		my $key = CDS->randomKey;
		my $newObject = $record->toObject->crypt($key);
		my $newHash = $newObject->calculateHash;
		$newPart->{hashAndKey} = CDS::HashAndKey->new($newHash, $key);
		$newPart->{isMerged} = 1;
		$o->{parts}->{$newHash->bytes} = $newPart;
		$o->{privateRoot}->unsaved->state->addObject($newHash, $newObject);
		$o->{privateRoot}->dataChanged;
	}

	# Remove obsolete parts
	for my $part (values %{$o->{parts}}) {
		next if ! $part->{isMerged};
		next if $part->{count};
		delete $o->{parts}->{$part->{hashAndKey}->hash->bytes};
		$o->{privateRoot}->dataChanged;
	}

	# Propagate the unsaved state
	$o->{privateRoot}->unsaved->state->merge($o->{unsaved}->savingState);
	$o->{unsaved}->savingDone;
	return 1;
}

package CDS::UnionList::Item;

sub new {
	my $class = shift;
	my $unionList = shift;
	my $id = shift;

	$unionList->{unused}->{count} += 1;
	return bless {
		unionList => $unionList,
		id => $id,
		part => $unionList->{unused},
		}, $class;
}

sub unionList { shift->{unionList} }
sub id { shift->{id} }

sub setPart {
	my $o = shift;
	my $part = shift;

	$o->{part}->{count} -= 1;
	$o->{part} = $part;
	$o->{part}->{count} += 1;
}

# abstract sub addToRecord($o, $record)

package CDS::UnionList::Part;

sub new {
	my $class = shift;

	return bless {
		isMerged => 0,
		hashAndKey => undef,
		size => 0,
		count => 0,
		selected => 0,
		};
}

package CDS::Unsaved;

use parent -norequire, 'CDS::Store';

sub new {
	my $class = shift;
	my $store = shift;

	return bless {
		state => CDS::Unsaved::State->new,
		savingState => undef,
		store => $store,
		};
}

sub state { shift->{state} }
sub savingState { shift->{savingState} }

# *** Saving, state propagation

sub isSaving {
	my $o = shift;
	 defined $o->{savingState} }

sub startSaving {
	my $o = shift;

	die 'Start saving, but already saving' if $o->{savingState};
	$o->{savingState} = $o->{state};
	$o->{state} = CDS::Unsaved::State->new;
}

sub savingDone {
	my $o = shift;

	die 'Not in saving state' if ! $o->{savingState};
	$o->{savingState} = undef;
}

sub savingFailed {
	my $o = shift;

	die 'Not in saving state' if ! $o->{savingState};
	$o->{state}->merge($o->{savingState});
	$o->{savingState} = undef;
}

# *** Store interface

sub id {
	my $o = shift;
	 'Unsaved'."\n".unpack('H*', CDS->randomBytes(16))."\n".$o->{store}->id }

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	my $stateObject = $o->{state}->{objects}->{$hash->bytes};
	return $stateObject->{object} if $stateObject;

	if ($o->{savingState}) {
		my $savingStateObject = $o->{savingState}->{objects}->{$hash->bytes};
		return $savingStateObject->{object} if $savingStateObject;
	}

	return $o->{store}->get($hash, $keyPair);
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return $o->{store}->book($hash, $keyPair);
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return $o->{store}->put($hash, $object, $keyPair);
}

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return $o->{store}->list($accountHash, $boxLabel, $timeout, $keyPair);
}

sub modify {
	my $o = shift;
	my $additions = shift;
	my $removals = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

	return $o->{store}->modify($additions, $removals, $keyPair);
}

package CDS::Unsaved::State;

sub new {
	my $class = shift;

	return bless {
		objects => {},
		mergedSources => [],
		dataSavedHandlers => [],
		};
}

sub objects { shift->{objects} }
sub mergedSources {
	my $o = shift;
	 @{$o->{mergedSources}} }
sub dataSavedHandlers {
	my $o = shift;
	 @{$o->{dataSavedHandlers}} }

sub addObject {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

	$o->{objects}->{$hash->bytes} = {hash => $hash, object => $object};
}

sub addMergedSource {
	my $o = shift;

	push @{$o->{mergedSources}}, @_;
}

sub addDataSavedHandler {
	my $o = shift;

	push @{$o->{dataSavedHandlers}}, @_;
}

sub merge {
	my $o = shift;
	my $state = shift;

	for my $key (keys %{$state->{objects}}) {
		$o->{objects}->{$key} = $state->{objects}->{$key};
	}

	push @{$o->{mergedSources}}, @{$state->{mergedSources}};
	push @{$o->{dataSavedHandlers}}, @{$state->{dataSavedHandlers}};
}

package UNKNOWN;

package CDS::C;
use Config;
use Inline (C => 'DATA', CCFLAGS => $Config{ccflags}.' -DNDEBUG -std=gnu99', OPTIMIZE => '-O3');
Inline->init;

1;

__DATA__
__C__

#line 1 "Condensation/../../c/configuration/default.inc.h"
typedef uint32_t cdsLength;
#define CDS_MAX_RECORD_DEPTH 64

#line 1 "Condensation/C.inc.c"

#line 1 "Condensation/../../c/random/dev-urandom.inc.c"
// *** Random number generation ***

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

#line 2 "Condensation/C.inc.c"

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

// Check if we are very obviously on a big-endian architecture
#if defined(__BYTE_ORDER) && __BYTE_ORDER == __BIG_ENDIAN || defined(__BIG_ENDIAN__) || defined(__ARMEB__) || defined(__THUMBEB__) || defined(__AARCH64EB__) || defined(_MIBSEB) || defined(__MIBSEB) || defined(__MIBSEB__)
#error "This library was prepared for little-endian processor architectures. Your compiler indicates that you are compiling for a big-endian architecture."
#endif

#line 3 "Condensation/C.inc.c"

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

// Local variables for modPowSmall (about 1 kB of memory).
// result will point to either bigInteger1 or bigInteger2.
struct cdsRSAModPowSmall {
	struct cdsBigInteger bigInteger1;
	struct cdsBigInteger bigInteger2;
	struct cdsBigInteger gR;
	struct cdsBigInteger * result;
};

// Local variables for modPow (about 32 kB of memory)
// result will point to either bigInteger1 or bigInteger2.
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

#line 4 "Condensation/C.inc.c"

#line 1 "Condensation/../../c/Condensation/all.inc.c"
#include <stdio.h>
#include <string.h>
#include <assert.h>


#line 1 "Condensation/../../c/Condensation/minMax.inc.c"
//static int min(int a, int b) { return a < b ? a : b; }
//static int max(int a, int b) { return a > b ? a : b; }

static cdsLength minLength(cdsLength a, cdsLength b) { return a < b ? a : b; }

//static uint32_t minU32(uint32_t a, uint32_t b) { return a < b ? a : b; }
//static uint32_t maxU32(uint32_t a, uint32_t b) { return a > b ? a : b; }

static size_t minSize(size_t a, size_t b) { return a < b ? a : b; }
//static size_t maxSize(size_t a, size_t b) {	return a > b ? a : b; }

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
// *** Hex to byte conversion

static char hexDigits[] = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'};
static uint8_t hexValues[] = {255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 255, 255, 255, 255, 255, 255, 255, 10, 11, 12, 13, 14, 15, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 10, 11, 12, 13, 14, 15, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255};

// Converts bytes to a hex string. This function does not null-terminate the string, and can therefore be used to fill a substring.
// OUT hex: the char sequence, at least 2 * length bytes long
// IN bytes: the byte sequence
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

// Converts a hex string to bytes. Conversion stops with the first invalid hex digit, or when the end of the byte sequence is reached.
// OUT bytes: the byte sequence
// IN hex: the char sequence with the hex digits, either 2 * length long or terminated by a non-hex digit (e.g., a null-terminated string)
// Returns the actual amount of bytes written.
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
// Fills the byte array with good random numbers.
struct cdsBytes cdsRandomBytes(uint8_t * buffer, cdsLength length) {
	fillRandom(buffer, length);
	return cdsBytes(buffer, length);
}

#line 8 "Condensation/../../c/Condensation/all.inc.c"


#line 1 "Condensation/../../c/Condensation/AES256/AES256.inc.c"
// *** AES 256 encryption
// AES 256 operates with a key length of 32 bytes, and a block size of 16 byte.

// AES-256 Constants
static int sbox[] = {99, 124, 119, 123, 242, 107, 111, 197, 48, 1, 103, 43, 254, 215, 171, 118, 202, 130, 201, 125, 250, 89, 71, 240, 173, 212, 162, 175, 156, 164, 114, 192, 183, 253, 147, 38, 54, 63, 247, 204, 52, 165, 229, 241, 113, 216, 49, 21, 4, 199, 35, 195, 24, 150, 5, 154, 7, 18, 128, 226, 235, 39, 178, 117, 9, 131, 44, 26, 27, 110, 90, 160, 82, 59, 214, 179, 41, 227, 47, 132, 83, 209, 0, 237, 32, 252, 177, 91, 106, 203, 190, 57, 74, 76, 88, 207, 208, 239, 170, 251, 67, 77, 51, 133, 69, 249, 2, 127, 80, 60, 159, 168, 81, 163, 64, 143, 146, 157, 56, 245, 188, 182, 218, 33, 16, 255, 243, 210, 205, 12, 19, 236, 95, 151, 68, 23, 196, 167, 126, 61, 100, 93, 25, 115, 96, 129, 79, 220, 34, 42, 144, 136, 70, 238, 184, 20, 222, 94, 11, 219, 224, 50, 58, 10, 73, 6, 36, 92, 194, 211, 172, 98, 145, 149, 228, 121, 231, 200, 55, 109, 141, 213, 78, 169, 108, 86, 244, 234, 101, 122, 174, 8, 186, 120, 37, 46, 28, 166, 180, 198, 232, 221, 116, 31, 75, 189, 139, 138, 112, 62, 181, 102, 72, 3, 246, 14, 97, 53, 87, 185, 134, 193, 29, 158, 225, 248, 152, 17, 105, 217, 142, 148, 155, 30, 135, 233, 206, 85, 40, 223, 140, 161, 137, 13, 191, 230, 66, 104, 65, 153, 45, 15, 176, 84, 187, 22};

static int xtime[] = {0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54, 56, 58, 60, 62, 64, 66, 68, 70, 72, 74, 76, 78, 80, 82, 84, 86, 88, 90, 92, 94, 96, 98, 100, 102, 104, 106, 108, 110, 112, 114, 116, 118, 120, 122, 124, 126, 128, 130, 132, 134, 136, 138, 140, 142, 144, 146, 148, 150, 152, 154, 156, 158, 160, 162, 164, 166, 168, 170, 172, 174, 176, 178, 180, 182, 184, 186, 188, 190, 192, 194, 196, 198, 200, 202, 204, 206, 208, 210, 212, 214, 216, 218, 220, 222, 224, 226, 228, 230, 232, 234, 236, 238, 240, 242, 244, 246, 248, 250, 252, 254, 27, 25, 31, 29, 19, 17, 23, 21, 11, 9, 15, 13, 3, 1, 7, 5, 59, 57, 63, 61, 51, 49, 55, 53, 43, 41, 47, 45, 35, 33, 39, 37, 91, 89, 95, 93, 83, 81, 87, 85, 75, 73, 79, 77, 67, 65, 71, 69, 123, 121, 127, 125, 115, 113, 119, 117, 107, 105, 111, 109, 99, 97, 103, 101, 155, 153, 159, 157, 147, 145, 151, 149, 139, 137, 143, 141, 131, 129, 135, 133, 187, 185, 191, 189, 179, 177, 183, 181, 171, 169, 175, 173, 163, 161, 167, 165, 219, 217, 223, 221, 211, 209, 215, 213, 203, 201, 207, 205, 195, 193, 199, 197, 251, 249, 255, 253, 243, 241, 247, 245, 235, 233, 239, 237, 227, 225, 231, 229};

static const int keyLength = 240;  // 16 * (14 + 1)

// CTR zero counter
uint8_t zeroCtrBuffer[16] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
const struct cdsBytes cdsZeroCtr = {zeroCtrBuffer, 16};

void cdsInitializeEmptyAES256(struct cdsAES256 * this) { }

// Prepares AES-256 encryption with a given key.
// IN key256: the 32 byte AES key
void cdsInitializeAES256(struct cdsAES256 * this, struct cdsBytes key256) {
	// Prepare the key
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

// Encrypts one block in-place.
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

// En- or decrypts bytes.
// IN aes: The AES instance.
// IN bytes: The bytes to be en- or decrypted.
// IN startCounter: The CTR counter for the first block (16 bytes).
// MEM buffer: A buffer of bytes.length bytes to hold the result. For in-place operation, pass bytes.data.
struct cdsBytes cdsCrypt(const struct cdsAES256 * aes, const struct cdsBytes bytes, const struct cdsBytes startCtr, uint8_t * buffer) {
	// Prepare the counter
	uint8_t counter[16];
	memcpy(counter, startCtr.data, 16);
	uint8_t encryptedCounter[16];

	// Encrypt blocks in CTR mode
	uint i = 0;
	for (; i + 16 < bytes.length; i += 16) {
		memcpy(encryptedCounter, counter, 16);
		cdsEncryptAES256Block(aes, encryptedCounter);
		for (uint n = 0; n < 16; n++) buffer[i + n] = bytes.data[i + n] ^ encryptedCounter[n];
		cdsIncrementCtr(counter);
	}

	// Encrypt the last block
	cdsEncryptAES256Block(aes, counter);
	for (uint n = 0; n < bytes.length - i; n++) buffer[i + n] = bytes.data[i + n] ^ counter[n];

	return cdsBytes(buffer, bytes.length);
}

#line 10 "Condensation/../../c/Condensation/all.inc.c"


#line 1 "Condensation/../../c/Condensation/SHA256/SHA256.inc.c"
// *** SHA 256

// Constants [4.2.2]
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

// Byte to int conversion

static uint32_t getUint32(const uint8_t * bytes) {
	return (uint32_t)(bytes[0] << 24) | (uint32_t)(bytes[1] << 16) | (uint32_t)(bytes[2] << 8) | bytes[3];
}

static void putUint32(uint8_t * bytes, uint32_t value) {
	bytes[0] = (value >> 24) & 0xff;
	bytes[1] = (value >> 16) & 0xff;
	bytes[2] = (value >> 8) & 0xff;
	bytes[3] = value & 0xff;
}

// Helper functions

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

// Hash computation [6.1.2]
static void sha256AddChunk(struct cdsSHA256 * this, const uint8_t * bytes) {
	// Prepare message schedule
	uint32_t w[64];
	for (uint8_t i = 0; i < 16; i++)
		w[i] = getUint32(bytes + i * 4);
	for (uint8_t i = 16; i < 64; i++)
		w[i] = prepareS1(w[i - 2]) + w[i - 7] + prepareS0(w[i - 15]) + w[i - 16];

	// Initialize working variables
	uint32_t s[8];
	for (uint8_t i = 0; i < 8; i++)
		s[i] = this->state[i];

	// Main loop
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

	// New intermediate hash value
	for (uint8_t i = 0; i < 8; i++)
		this->state[i] += s[i];
}

// Initial hash value [5.3.1]
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

// IN bytes: the bytes to add to the stream
// IN length: the length of the "bytes" buffer
void cdsAddBytesToSHA256(struct cdsSHA256 * this, struct cdsBytes bytes) {
	for (uint32_t i = 0; i < bytes.length; i++)
		sha256AddByte(this, bytes.data[i]);
}

// OUT result: 32 bytes for the result
void cdsFinalizeSHA256(struct cdsSHA256 * this, uint8_t * result) {
	// Message length
	uint32_t dataLength = this->length;

	// Padding
	sha256AddByte(this, 0x80);
	while (this->used != 56)
		sha256AddByte(this, 0);

	// Length in bits
	sha256AddByte(this, 0);
	sha256AddByte(this, 0);
	sha256AddByte(this, 0);
	sha256AddByte(this, (dataLength & 0xe0000000) >> 29);
	sha256AddByte(this, (dataLength & 0x1fe00000) >> 21);
	sha256AddByte(this, (dataLength & 0x001fe000) >> 13);
	sha256AddByte(this, (dataLength & 0x00001fe0) >> 5);
	sha256AddByte(this, (dataLength & 0x0000001f) << 3);

	// Write the state to the result buffer
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
// *** Element access

#define ELEMENT(x, n) x->values[n]

// Shortcuts for x[n], ...
#define X(index) ELEMENT(x, index)
#define Y(index) ELEMENT(y, index)
#define M(index) ELEMENT(m, index)
#define G(index) ELEMENT(g, index)
#define E(index) ELEMENT(e, index)
#define A(index) ELEMENT(a, index)

#line 14 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/RSA64/Math.inc.c"
// *** RSA 2048
// An integer is stored as array of uint32_t in little-endian order. The least significant bits are in element 0.
// All cdsBigIntegers have the same size in memory (CDS_BIG_INTEGER_SIZE elements), and may be allocated on the stack. Only the lower b->length elements are in use. All other elements are ignored, and may have any value. For efficiency, the code tries to keep b->length as small as possible, but it is not always a tight bound. The most significant (non-zero) element is returned by mostSignificantElement(b).

// *** General

// Resets x to zero.
static void setZero(struct cdsBigInteger * x) {
	x->length = 0;
}

// Sets x to an unsigned 32-bit integer.
static void setUint32(struct cdsBigInteger * x, uint32_t value) {
	x->length = 1;
	X(0) = value;
}

// Fills x with 32 * n random bits.
static void setRandom(struct cdsBigInteger * x, int n) {
	assert(n >= 0);
	assert(n <= CDS_BIG_INTEGER_SIZE);
	cdsRandomBytes((uint8_t *) x->values, (uint) n * 4);
	x->length = n;
}

// Returns the index of the most significant element, or -1 if x == 0.
static int mostSignificantElement(const struct cdsBigInteger * x) {
	int i = x->length - 1;
	while (i >= 0 && X(i) == 0) i -= 1;
	return i;
}

// Trims the length to avoid trailing zeros.
static void trim(struct cdsBigInteger * x) {
	while (x->length > 0 && X(x->length - 1) == 0) x->length -= 1;
}

// Expands the length to a minimum of n elements and adds zeros if necessary.
static void expand(struct cdsBigInteger * x, int n) {
	assert(n >= 0);
	assert(n <= CDS_BIG_INTEGER_SIZE);
	while (x->length < n) {
		x->length += 1;
		X(x->length - 1) = 0;
	}
}

// Returns the larger of the two length.
static int maxLength(const struct cdsBigInteger * x, const struct cdsBigInteger * y) {
	return x->length > y->length ? x->length : y->length;
}

// a <= x * 2 ^ (32 * d)
// Preconditions: x->length < CDS_BIG_INTEGER_SIZE - d
static void copyD(struct cdsBigInteger * a, const struct cdsBigInteger * x, int d) {
	a->length = x->length + d;
	for (int i = 0; i < x->length; i++) A(i + d) = X(i);
	for (int i = 0; i < d; i++) A(i) = 0;
}

// *** Conversion from and to bytes

// x <= value of the big-endian byte sequence bytes.
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

// Writes x to a big-endian byte sequence, and returns the index of the first non-zero byte.
struct cdsBytes cdsBytesFromBigInteger(struct cdsMutableBytes bytes, const struct cdsBigInteger * x) {
	uint n = bytes.length;
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

// *** Comparison

// Returns true if x is even.
static bool isEven(const struct cdsBigInteger * x) {
	return x->length == 0 || (X(0) & 1) == 0;
}

// x == 0
static bool isZero(const struct cdsBigInteger * x) {
	return mostSignificantElement(x) == -1;
}

// x == 1
static bool isOne(const struct cdsBigInteger * x) {
	return mostSignificantElement(x) == 0 && X(0) == 1;
}

// Compares x and y, and returns 0 if they are equal, -1 if x < y, and +1 if x > y.
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

// Compares x / 2 ^ (32 * d) and y
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

// *** Bit shift

// a <= x << bits
// a may be x (in-place operation), and bits may be 0.
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

// a <= x >> bits
// a may be x (in-place operation), and bits may be 0.
static void smallShiftRight(struct cdsBigInteger * a, const struct cdsBigInteger * x, int bits) {
	a->length = x->length;
	int i = 0;
	for (; i + 1 < x->length; i++)
		A(i) = (uint32_t) (X(i) >> bits | (uint64_t)X(i + 1) << (32 - bits));
	A(i) = X(i) >> bits;
}

// *** Addition, subtraction

// x + (n * y << 32 * d) => x
static void addN(struct cdsBigInteger * x, uint32_t n, const struct cdsBigInteger * y, int d) {
	int yk = mostSignificantElement(y);

	// Expand x if necessary
	if (x->length > 0 && X(x->length - 1) != 0) expand(x, x->length + 1);
	expand(x, y->length + d + 2);
	//T("x length "), TD(x->length), NL();

	// Accumulate
	uint64_t c = 0;
	int i = 0;
	for (; i <= yk; i++, d++) {
		c += X(d) + (uint64_t)n * Y(i);
		//T("d "), TD(d), T(" c "), TH(c), NL();
		X(d) = c & 0xffffffff;
		c >>= 32;
	}

	for (; c != 0; d++) {
		c += X(d);
		//T("d "), TD(d), T(" c "), TH(c), NL();
		X(d) = c & 0xffffffff;
		c >>= 32;
	}
}

// x - 1 => x
// Preconditions: x > 0
static void decrement(struct cdsBigInteger * x) {
	int64_t c = -1;
	for (int i = 0; c != 0; i++) {
		c += X(i);
		X(i) = c & 0xffffffff;
		c >>= 32;
	}
}

// x - (y << 32 * d) => x
// Preconditions: x > y
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

// x + n * y * 2 ^ (28 * d) => x
// Precondition: 0 <= n < 2 ^ 28, x > n * y * 2 ^ (28 * d)
static void subN(struct cdsBigInteger * x, uint32_t n, const struct cdsBigInteger * y, int d) {
	// Since x - n * y = x - (r - (r - n)) * y = x + (r - n) * y - r * y, we can carry out this subtraction using one addN followed by a simple subtraction.
	// We use r = 2 ^ 32 = 0x100000000
	uint32_t nNeg = (uint32_t) (0x100000000 - n);
	addN(x, nNeg, y, d);
	subD(x, y, d + 1);
}

// *** Multiplication

// a + x * y => a
static void mul(struct cdsBigInteger * a, const struct cdsBigInteger * x, const struct cdsBigInteger * y) {
	for (int i = 0; i < y->length; i++)
		if (Y(i) != 0) addN(a, Y(i), x, i);
	trim(a);
}

// a + x * x => a
// Specializing this yields a performance improvement of 15 - 20 % on modPow using 2048 bit coefficients.
static void sqr(struct cdsBigInteger * a, const struct cdsBigInteger * x) {
	int xk = mostSignificantElement(x);
	expand(a, a->length + 1);
	expand(a, (xk + 1) << 1);
	for (int i = 0; i <= xk; i++) {
		if (X(i) == 0) continue;

		// Diagonal element
		int r = i;
		int w = i + r;
		uint64_t cSum = A(w) + (uint64_t)X(r) * X(i);
		A(w) = cSum & 0xffffffff;
		//T("s "), TBI(a), T(" "), TH(cSum), T(" r "), TD(r), T(" w "), TD(w), T(" i "), TD(i), NL();
		cSum >>= 32;
		w++;
		r++;

		// All other elements
		// c + A(w) + 2 * X(r) * X(i) may overflow. We therefore have to calculate this in two steps.
		// We still save a lot with respect to mul(...), since the element multiplication X(r) * X(i) is carried out only once.
		uint64_t cProduct = 0;
		for (; r <= xk; w++, r++) {
			cProduct += (uint64_t)X(r) * X(i);
			cSum += A(w) + ((cProduct & 0xffffffff) << 1);
			A(w) = cSum & 0xffffffff;
			//T("n "), TBI(a), T(" "), TH(cSum), T(" p "), TH(cProduct), T(" = "), TH(X(r)), T(" * "), TH(X(i)), T(" r "), TD(r), T(" w "), TD(w), NL();
			cProduct >>= 32;
			cSum >>= 32;
		}
		for (; cSum != 0 || cProduct != 0; w++) {
			cSum += A(w) + ((cProduct & 0xffffffff) << 1);
			A(w) = cSum & 0xffffffff;
			//T("w "), TBI(a), T(" "), TH(cSum), T(" p "), TH(cProduct), T(" r "), TD(r), T(" w "), TD(w), NL();
			cProduct >>= 32;
			cSum >>= 32;
		}
	}
	trim(a);
}

// *** Classic modulo

// x % m => x
// This algorithm resembles HAC 14.20.
static void mod(struct cdsBigInteger * x, const struct cdsBigInteger * m) {
	// Determine the normalization shift using the most significant element of y (ym)
	int yk = mostSignificantElement(m);
	uint32_t mse = M(yk);
	int shift = 0;
	while ((mse & 0x80000000) == 0) {
		mse <<= 1;
		shift += 1;
	}

	// Normalize m << shift => y
	struct cdsBigInteger bi = CDS_BIG_INTEGER_ZERO;
	struct cdsBigInteger * y = &bi;
	smallShiftLeft(y, m, shift);
	//T("shift "), TD(shift), NL();
	//T("y "), TBI(y), NL();
	//T("m "), TBI(m), NL();

	// Normalize x << shift => x
	if (shift > 0) smallShiftLeft(x, x, shift);

	// Make sure that x[xk + 1] exists (and is 0) in the first iteration
	int xk = mostSignificantElement(x);
	expand(x, xk + 2);

	// Maximum length of the quotient
	//q->length = xk - yk + 1;		// enable quotient here

	// Calculate x % y => x
	uint64_t div = Y(yk) + 1;
	for (int d = xk - yk; d >= 0; d--) {
		// Approach:
		// Let Y be y * 2 ^ (32 * d).
		// We are trying to iteratively subtract n * Y from x, such that x >= 0 and x < Y.
		// Thanks to the normalization step, Y(yk) >= 0x80000000, and div / Y(yk) = 1 + 0x80000001/0x80000000. Hence, this converges quickly.
		// Without normalization, the convergence could be very bad, i.e. progressing just 1 bit at a time.
		// This is slightly worse than HAC 14.20, but avoids overshooting.

		// Start with a zero quotient
		//Q(d) = 0;		// enable quotient here

		// We can subtract at least xmsb / div
		uint64_t xmsb = ((uint64_t)X(yk + d + 1) << 32) + X(yk + d);
		if (xmsb > div) {
			uint64_t n = xmsb / div;
			//T("  "), TBI(x), T(" - 10000^"), TH(d), T(" * "), TH(n), T(" * "), TBI(y);
			subN(x, (uint32_t) n, y, d);
			//Q(d) += n;	// enable quotient here
		}

		// Check if we can subtract Y a few more times
		while (compareShifted(x, y, d) >= 0) {
			//T("    "), TBI(x), T(" - 10000^"), TH(d), T(" * "), TBI(y), NL();
			subD(x, y, d);
			//T(" - "), TBI(x), NL();
			//Q(d) += 1;	// enable quotient here
		}

		// For maximum performance, keep x as small as possible (it can never grow)
		while (xk >= 0 && X(xk) == 0) xk -= 1;
		x->length = xk + 2;
	}

	// Remove normalization: x >> shift => x
	if (shift > 0) smallShiftRight(x, x, shift);
	trim(x);
	//trim(q);	// enable quotient here
}

// *** Montgomery exponentiation
// We are using radix 2^32 = 0x100000000.
// In all these function, m must be odd. For RSA, this is always the case, as m = p * q, the product of two large prime numbers p and q.

// Returns mp = -(q ^ -1) mod 0x100000000, where q = m mod 0x100000000.
// x must be odd, and m is therefore odd as well.
// This is a fast version, based on the fact that
//       y = x^-1 mod m ====> y(2 - xy) = x^-1 mod m^2.
// Hence we can work our way up from 2^2 to 2^32
static uint32_t montInverse(const struct cdsBigInteger * m) {
	uint64_t q = M(0);
	uint32_t mp = q & 0x3;		// mp = q^-1 mod 2^2 (for odd q)
	mp = (mp * (2 - (q & 0xf) * mp)) & 0xf;	// mp = q^-1 mod 2^4
	mp = (mp * (2 - (q & 0xff) * mp)) & 0xff;	// mp = q^-1 mod 2^8
	mp = (mp * (2 - (q & 0xffff) * mp)) & 0xffff;	// mp = q^-1 mod 2^16
	mp = (mp * (2 - ((q * mp) & 0xffffffff))) & 0xffffffff;	// mp = q^-1 mod 2^32
	return mp > 0 ? (uint32_t) (0x100000000 - mp) : -mp;
}

// Montgomery conversion
// xR mod m => a
static void montConversion(struct cdsBigInteger * a, const struct cdsBigInteger * x, const struct cdsBigInteger * m) {
	// Prepare xR, with R = radix ^ l such that R > m
	int mk = mostSignificantElement(m);
	copyD(a, x, mk + 1);

	// a % m => a
	mod(a, m);
}

// Montgomery conversion for x = 1
// R mod m => ans
static void montConversionOne(struct cdsBigInteger * a, const struct cdsBigInteger * m) {
	// Prepare R, with R = radix ^ l such that R > m
	int mk = mostSignificantElement(m);
	setZero(a);
	expand(a, mk + 2);
	A(mk + 1) = 1;

	// a % m => a
	mod(a, m);
}

// Mongomery reduction (HAC 14.32)
// x * R mod m => ans
// mp is the precalculated negative inverse of m.
static void montReduction(struct cdsBigInteger * x, const struct cdsBigInteger * m, uint32_t mp) {
	int mk = mostSignificantElement(m);
	for (int i = 0; i <= mk; i++) {
		uint32_t u = ((uint64_t)X(0) * mp) & 0xffffffff;
		//T("verify "), TBI(x), T(" + "), TH(u), T(" * "), TBI(m);

		// x <= (x + u * m) >> 32
		addN(x, u, m, 0);
		//T(" - "), TBI(x), NL();
		for (int n = 0; n + 1 < x->length; n++) X(n) = X(n + 1);
		x->length -= 1;
		//T("xs "), TBI(x), NL();
	}

	if (compare(x, m) >= 0) subD(x, m, 0);
	assert(compare(x, m) < 0);
	trim(x);
}

// Montgomery multiplication (HAC 14.36)
// x * y * R mod m => a
// mp is the precalculated negative inverse of m.
// x < m, y < m.
// This is about 5 - 10 % faster than mul() followed by montReduction().
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

		// a = (a + X(i) * y + u * m) >> 32
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

// Montgomery exponentiation for small e (HAC 14.94, i.e. HAC 14.79 using Montgomery)
// g ^ e mod m => this->result
// This is used for RSA public key exponentiation, where e is typically 0x10001.
// m must be odd, 0 < g < m, and e > 0.
static void modPowSmallExp(struct cdsRSAModPowSmall * this, const struct cdsBigInteger * g, const struct cdsBigInteger * e, const struct cdsBigInteger * m) {
	// Convert to Montgomery
	uint32_t mp = montInverse(m);
	struct cdsBigInteger * gR = &this->gR;
	montConversion(gR, g, m);

	// Find the first non-zero bit of e
	int ek = mostSignificantElement(e);
	uint32_t eMask = 0x80000000;
	while ((E(ek) & eMask) == 0) eMask >>= 1;
	//console.log(TBI(ans), TBI(g), TBI(gR), TBI(e), ek, eMask, TBI(m), mp);

	// Exponentiation for the first bit
	struct cdsBigInteger * aR = &this->bigInteger1;
	copyD(aR, gR, 0);

	// Exponentiation for all other bits
	struct cdsBigInteger * tR = &this->bigInteger2;
	while (true) {
		// Move to the next bit of e
		eMask >>= 1;
		if (eMask == 0) {
			if (ek == 0) break;
			ek -= 1;
			eMask = 0x80000000;
		}

		// aR * aR * R^-1 => tR
		setZero(tR);
		sqr(tR, aR);
		montReduction(tR, m, mp);

		if (E(ek) & eMask) {
			// tR * gR * R^-1 => ans if the bit is set
			setZero(aR);
			montMul(aR, tR, gR, m, mp);
		} else {
			// tR => aR (simply by swapping the two) if the bit is not set
			struct cdsBigInteger * temp = aR;
			aR = tR;
			tR = temp;
		}
	}

	// Revert back to normal form
	montReduction(aR, m, mp);
	this->result = aR;
}

// tR => aR by swapping the two
static void modPowBigSwap(struct cdsRSAModPowBig * this) {
	struct cdsBigInteger * temp = this->aR;
	this->aR = this->tR;
	this->tR = temp;
}

// aR * aR * R^-1 => aR
static void modPowBigSqrAR(struct cdsRSAModPowBig * this) {
	setZero(this->tR);
	assert(mostSignificantElement(this->aR) < 64);
	sqr(this->tR, this->aR);
	montReduction(this->tR, this->m, this->mp);
	assert(mostSignificantElement(this->tR) < 64);
	modPowBigSwap(this);
}

// Flushes the currently selected bits from e, and resets the selection.
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

// Returns the result of the operation. The returned result points to a value within "this".
static void modPowBigResult(struct cdsRSAModPowBig * this) {
	// Revert back to normal form
	copyD(this->tR, this->aR, 0);
	montReduction(this->tR, this->m, this->mp);
	this->result = this->tR;
}

// Exponentiation (HAC 14.85 using Montgomery)
// g ^ e mod m => ans
// m must be odd (which is always the case in RSA), x > 0, and e > 0.
static void modPowBigExp(struct cdsRSAModPowBig * this, const struct cdsBigInteger * g, const struct cdsBigInteger * e, const struct cdsBigInteger * m) {
	// Prepare
	this->m = m;
	this->mp = montInverse(m);

	// Precomputation for 6 bits
	montConversion(this->gR + 1, g, m);
	montMul(this->gR + 2, this->gR + 1, this->gR + 1, m, this->mp);
	for (int i = 3; i < 64; i += 2)
		montMul(this->gR + i, this->gR + (i - 2), this->gR + 2, m, this->mp);

	// Start with R mod m
	this->aR = &this->bigInteger1;
	montConversionOne(this->aR, this->m);
	assert(mostSignificantElement(this->aR) < 64);

	// Find the first non-zero bit of e
	int ek = mostSignificantElement(e);
	uint32_t eMask = 0x80000000;
	while ((E(ek) & eMask) == 0) eMask >>= 1;

	// Start by selecting that one bit
	this->selection = 1;	// = usableSelection * 2 ^ zeroBits
	this->usableSelection = 1;
	this->usableBits = 1;
	this->zeroBits = 0;

	// Process all other bits
	this->tR = &this->bigInteger2;
	while (true) {
		// Move to the next bit of e
		eMask >>= 1;
		if (eMask == 0) {
			if (ek == 0) break;
			ek -= 1;
			eMask = 0x80000000;
		}

		// Update the selection, and flush it whenever necessary
		if (E(ek) & eMask) {
			// Add a 1 to the selection
			if (this->selection > 31) modPowBigFlushSelection(this);
			this->selection = this->selection * 2 + 1;
			this->usableSelection = this->selection;
			this->usableBits += this->zeroBits + 1;
			this->zeroBits = 0;
		} else if (this->usableBits == 0) {
			// Apply a 0 bit directly if there is no selection
			modPowBigSqrAR(this);
		} else {
			// Add a 0 to the selection
			this->selection *= 2;
			this->zeroBits += 1;
		}
	}

	// Flush any started selection
	if (this->usableBits > 0) modPowBigFlushSelection(this);
}

// *** GCD and modulo inverse

// Returns the sign.
static uint32_t sign(const struct cdsBigInteger * x) {
	return x->length > 0 && X(x->length - 1) & 0x80000000 ? 0xffffffff : 0;
}

// Expands a signed integer to n elements.
static void expandS(struct cdsBigInteger * x, int n) {
	assert(n <= CDS_BIG_INTEGER_SIZE);
	uint32_t filler = sign(x);
	while (x->length < n) {
		x->length += 1;
		X(x->length - 1) = filler;
	}
}

// Trims the length of a signed integer to avoid trailing zeros.
static void trimS(struct cdsBigInteger * x) {
	uint32_t filler = sign(x);
	while (x->length > 1 && X(x->length - 1) == filler && ((X(x->length - 1) ^ X(x->length - 2)) & 0x80000000) == 0) x->length -= 1;
}

// x += y
// x is considered a signed integer, and y an unsigned integer.
static void addSU(struct cdsBigInteger * x, struct cdsBigInteger * y) {
	//TBIS(x), T(" + "), TBI(y);
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
	//T(" - "), TBIS(x), T(" # addSU"), NL();
}

// x -= y
// Both x and y are considered a signed integers.
static void subSS(struct cdsBigInteger * x, struct cdsBigInteger * y) {
	//TBIS(x), T(" - "), TBIS(y);
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
	//T(" - "), TBIS(x), T(" # subSS"), NL();
}

// x >>= 1
// x is considered a signed integer.
static void halveS(struct cdsBigInteger * x) {
	//TBIS(x);
	int i = 0;
	for (; i + 1 < x->length; i++)
		X(i) = X(i) >> 1 | X(i + 1) << 31;
	X(i) = (uint32_t)((int32_t)X(i) >> 1);
	trimS(x);
	//T("/2 - "), TBIS(x), T(" # halveS"), NL();
}

// Extended GCD (HAC 14.61, but with -b)
// Given x and y, calculates a, b and gcd, such that ax - by = gcd.
// Preconditions: x > 0, y > 0, either x or y or both need to be odd
// Postconditions: a and b are signed integers, gcd is an unsigned integer
static void egcd(struct cdsBigInteger * x, struct cdsBigInteger * y, struct cdsBigInteger * a, struct cdsBigInteger * b, struct cdsBigInteger * gcd) {
	// u and v are unsigned integers
	struct cdsBigInteger * u = gcd;
	struct cdsBigInteger v = CDS_BIG_INTEGER_ZERO;

	// A, B, C and D are signed integers
	struct cdsBigInteger * A = a;
	struct cdsBigInteger * B = b;
	struct cdsBigInteger C = CDS_BIG_INTEGER_ZERO;
	struct cdsBigInteger D = CDS_BIG_INTEGER_ZERO;

	// Initial values
	copyD(u, x, 0);
	copyD(&v, y, 0);

	// Initial solution
	// A * x - B * y = u ==> A = 1 and B = 0
	// C * x - D * y = v ==> C = 0 and D = -1
	setUint32(A, 1);
	setZero(B);
	setZero(&C);
	setUint32(&D, 0xffffffff);

	// Modify the solution until u == v
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

// x^-1 mod m => a
// Preconditions: x > 0, m > 0, either x or m odd
static bool modInverse(struct cdsBigInteger * a, struct cdsBigInteger * x, struct cdsBigInteger * m) {
	// Apply the extended GCD
	struct cdsBigInteger b = CDS_BIG_INTEGER_ZERO;
	struct cdsBigInteger gcd = CDS_BIG_INTEGER_ZERO;
	egcd(x, m, a, &b, &gcd);

	// If gcd != 1, the inverse does not exist
	if (! isOne(&gcd)) return false;

	// Move a into [0, m[, and make it an unsigned integer
	while (sign(a) != 0) addSU(a, m);
	trim(a);
	return true;
}

// *** Primality test

// Decomposes x = 2^s * r.
// Returns s, and modifies x in-place, so that it holds r when returning.
static int removeFactorsOf2(struct cdsBigInteger * x) {
	// Look for the smallest non-zero element
	int d = 0;
	while (X(d) == 0) d += 1;
	if (d > 0) {
		for (int i = 0; i + d < x->length; i++) X(i) = X(i + d);
		x->length = x->length - d;
	}

	// Check if x == 0
	if (x->length == 0) return 0;

	// Look for the smallest non-zero bit
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

// Miller-Rabin primality test (HAC 4.24)
static bool millerRabin(struct cdsBigInteger * x, struct cdsRSAModPowBig * modPowBig) {
	// Calculate x - 1
	struct cdsBigInteger x1 = CDS_BIG_INTEGER_ZERO;
	copyD(&x1, x, 0);
	decrement(&x1);

	// Decomposition of x - 1 == 2^s * r such that r is odd
	struct cdsBigInteger r = CDS_BIG_INTEGER_ZERO;
	copyD(&r, &x1, 0);
	int s = removeFactorsOf2(&r);

	// Repeat twice, so that the probability that x is composite is approx. 2^-80
	int repeat = 2;
	int xk = mostSignificantElement(x);
	struct cdsBigInteger a = CDS_BIG_INTEGER_ZERO;
	for (int i = 0; i < repeat; i++) {
		// Pick a random a > 1
		setRandom(&a, xk - 1);
		while (isZero(&a) || isOne(&a)) setRandom(&a, xk - 1);

		// Check if a^r mod x == 1 or a^r mod x == -1
		modPowBigExp(modPowBig, &a, &r, x);
		modPowBigResult(modPowBig);
		if (isOne(modPowBig->result) || compare(modPowBig->result, &x1) == 0) continue;

		// Check if a^(r * 2^j) mod x == -1
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

// Returns x % y, where y is a 32-bit integer
static uint32_t modInt(struct cdsBigInteger * x, uint32_t y) {
	uint64_t c = 0;
	for (int i = mostSignificantElement(x); i >= 0; i--)
		c = ((c << 32) + X(i)) % y;
	return (uint32_t)c;
}

// *** Key generation

#ifndef KEY_GENERATION_RESET_WATCHDOG
#define KEY_GENERATION_RESET_WATCHDOG() ;
#endif

static const int elementsFor1024Bits = 32;
static const int elementsFor2048Bits = 64;
static int bitCount4[] = {0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4};

// Returns the number of 1's in an integer.
static int bitCount(uint32_t n) {
	int count = 0;
	for (; n != 0; n >>= 4)
		count += bitCount4[n & 0xf];
	return count;
}

// GCD (HAC 14.54)
// x <= y <= GCD(x, y)
// Preconditions: x > 0, y > 0, either x or y or both need to be odd.
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

static void markInSieve(uint8_t * sieve, uint s, uint interval) {
	for (; s < 4096; s += interval) sieve[s] = 1;
}

// Fills x with a random prime, with x - 1 relatively prime to this->e.
static void randomPrime1024(struct cdsBigInteger * x, struct cdsBigInteger * e, struct cdsRSAModPowBig * modPowBig) {
	uint8_t sieve[4096];
	while (true) {
		// Generate a random 1024 bit odd integer start
		struct cdsBigInteger start = CDS_BIG_INTEGER_ZERO;
		setRandom(&start, elementsFor1024Bits);
		start.values[0] |= 1;
		start.values[elementsFor1024Bits - 1] |= 0x80000000;

		// Reset the sieve
		KEY_GENERATION_RESET_WATCHDOG();
		memset(sieve, 0, 4096);

		// Check all odd numbers between start and start + 4096 for primality and suitability for RSA
		for (uint n = 0; n < 4096; n += 2) {
			if (sieve[n]) continue;

			// x <= start + n
			setUint32(x, n);
			addN(x, 1, &start, 0);
			trim(x);

			// Check if x is prime

#line 1 "Condensation/../../c/Condensation/RSA64/primality.inc.c"
// This code was generated using generate-primality-check
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

			// Check if x mod e != 1
			struct cdsBigInteger xme = CDS_BIG_INTEGER_ZERO;
			copyD(&xme, x, 0);
			mod(&xme, e);
			if (isOne(&xme)) continue;

			// Check if gcd(x - 1, e) == 1
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

// Generates a 2048 bit key.
static void generateKey(struct cdsRSAPrivateKey * this, struct cdsRSAModPowBig * modPowBig) {
	// Prepare
	struct cdsBigInteger * e = &this->rsaPublicKey.e;
	struct cdsBigInteger * p = &this->p;
	struct cdsBigInteger * q = &this->q;
	struct cdsBigInteger n = CDS_BIG_INTEGER_ZERO;
	struct cdsBigInteger n3 = CDS_BIG_INTEGER_ZERO;

	setUint32(e, 0x10001);
	while (true) {
		// Pick a first prime
		randomPrime1024(p, e, modPowBig);
		//T("p "), TBI(p), NL();

		while (true) {
			// Pick a second prime
			randomPrime1024(q, e, modPowBig);
			//T("q "), TBI(q), NL();

			// Make p the bigger of the two primes
			if (compare(p, q) < 0) {
				struct cdsBigInteger * temp = p;
				p = q;
				q = temp;
			}

			// Some implementations check if p - q > 2^800 (or a similar value), since pq
			// may be easy to factorize if p ~ q. However, the probability of this is less
			// than 2^-200, and therefore completely negligible.
			// For comparison, note that the Miller-Rabin primality test leaves a 2^-80
			// chance that either p or q are composite.

			// Calculate the modulus n = p * q
			setZero(&n);
			mul(&n, p, q);
			//T("n "), TBI(n), NL();

			// If the modulus is too small, use the larger of the two primes, and continue
			if (mostSignificantElement(&n) != elementsFor2048Bits - 1 || (n.values[elementsFor2048Bits - 1] & 0x80000000) == 0) continue;

			// p and q appear to be OK
			break;
		}

		// Check if the NAF weight is high enough, since low-weight composites may be weak
		// See "The number field sieve for integers of low weight" by Oliver Schirokauer.
		setZero(&n3);
		addN(&n3, 3, &n, 0);
		//T("n3 "), TBI(n3), NL();
		int nk = elementsFor2048Bits - 1;  // == mostSignificantElement(n), a condition for quitting the while loop above
		int nafCount = 0;
		for (int i = 0; i <= nk; i++) nafCount += bitCount(n.values[i] ^ n3.values[i]);
		if (nk + 1 < n3.length) nafCount += bitCount(n3.values[nk + 1]);
		//T("nafCount "), TD(nafCount), NL();
		if (nafCount < 512) continue;

		// We are done
		break;
	}
}

#line 15 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/RSA64/Encoding.inc.c"
// *** OAEP and PSS encoding
#include <string.h>

static const uint emLength = 256;    // = 2048 / 8
static const uint hashLength = 32;
static const uint8_t OAEPZeroLabelHash[] = {0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14, 0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24, 0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c, 0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55};

// The first mask.length bytes of mgf1(seed) => mask
// IN seed: the seed to use, max. 4092 bytes
// OUT mask: the generated mask, whereby the length must be a multiple of 32
static void maskGenerationFunction1(struct cdsBytes seed, struct cdsMutableBytes mask) {
	struct cdsSHA256 sha256;
	uint8_t counter[4] = {0, 0, 0, 0};
	uint blocks = mask.length / 32;
	for (uint i = 0; i < blocks; i++) {
		counter[3] = i;
		cdsInitializeSHA256(&sha256);
		cdsAddBytesToSHA256(&sha256, seed);
		cdsAddBytesToSHA256(&sha256, cdsBytes(counter, 4));
		cdsFinalizeSHA256(&sha256, mask.data + i * 32);
	}
}

// SHA256(8 zeros | digest | salt) => h
// IN digest: max. 256 bytes
// IN salt: max. 222 bytes
// OUT h: 32 bytes
static void pssHash(struct cdsBytes digest, struct cdsBytes salt, uint8_t * h) {
	uint8_t sequence[8 + 256 + 222];
	uint sequenceLength = 8 + digest.length + salt.length;
	memset(sequence, 0, 8);
	memcpy(sequence + 8, digest.data, digest.length);
	memcpy(sequence + 8 + digest.length, salt.data, salt.length);
	cdsSHA256(cdsBytes(sequence, sequenceLength), h);
}

// Verfies a signature for digest.
// IN digest: the signed digest, max. 256 bytes
// IN pss: the PSS bytes, 256 bytes
static bool verifyPSS(struct cdsBytes digest, struct cdsBytes pss) {
	assert(digest.length <= 256);
	assert(pss.length == 256);
	const uint8_t * em = pss.data;

	// Check the last byte
	if (em[emLength - 1] != 0xbc) return false;

	// Unmask the salt: zeros | 0x01 | salt = maskedDB ^ mask
	uint dbLength = emLength - hashLength - 1;	// 223
	uint8_t mask[224];	// rounded up to the next multiple of 32
	maskGenerationFunction1(cdsBytes(em + (emLength - hashLength - 1), hashLength), cdsMutableBytes(mask, 224));
	uint8_t unmasked[224];
	for (uint i = 0; i < dbLength; i++) unmasked[i] = em[i] ^ mask[i];

	// The first byte may be incomplete
	unmasked[0] &= 0x7f;

	// Remove leading zeros
	uint n = 0;
	while (unmasked[n] == 0 && n < dbLength) n++;

	// The first unmasked byte must be 0x01
	if (unmasked[n] != 0x01) return false;
	n++;

	// The rest is salt (max. 222 bytes)
	struct cdsBytes salt = cdsBytes(unmasked + n, dbLength - n);

	// Calculate H = SHA256(8 zeros | digest | salt)
	uint8_t h[hashLength];
	pssHash(digest, salt, h);

	// Verify H
	for (uint i = 0; i < 32; i++)
		if (h[i] != em[dbLength + i]) return false;

	return true;
}

// Returns PSS(digest).
// IN digest: the digest to sign, max. 256 bytes
// MEM em: 256 bytes to place the return value
static struct cdsBytes generatePSS(struct cdsBytes digest, uint8_t * em) {
	assert(digest.length <= 256);
	uint dbLength = emLength - hashLength - 1;	// 223

	// Prepare the salt
	uint8_t saltBuffer[32];
	struct cdsBytes salt = cdsRandomBytes(saltBuffer, 32);

	// Calculate H = SHA256(8 zeros | digest | salt), and prepare the message = maskedDB | H | 0xbc
	em[emLength - 1] = 0xbc;
	pssHash(digest, salt, em + dbLength);

	// Write maskedDB = (zeros | 0x01 | salt) ^ mask
	uint8_t mask[224];
	maskGenerationFunction1(cdsBytes(em + dbLength, hashLength), cdsMutableBytes(mask, 224));

	// Zeros
	uint n = 0;
	for (; n < dbLength - salt.length - 1; n++)
		em[n] = mask[n];

	// 0x01
	em[n] = 0x01 ^ mask[n];
	n++;

	// Salt
	for (uint i = 0; i < salt.length; i++, n++)
		em[n] = salt.data[i] ^ mask[n];

	// Set the first bit to 0, because the signature can only be 2048 - 1 bit long
	em[0] &= 0x7f;

	return cdsBytes(em, emLength);
}

// Returns OAEP(message).
// IN message: the message to pad, max. 190 bytes
// MEM em: 256 bytes to place the return value
static struct cdsBytes encodeOAEP(struct cdsBytes message, uint8_t * em) {
	// Create DB = labelHash | zeros | 0x01 | message
	uint dbLength = emLength - hashLength - 1;	// 223
	uint8_t db[dbLength];
	memcpy(db, OAEPZeroLabelHash, 32);
	memset(db + 32, 0, dbLength - 32 - message.length - 1);
	db[dbLength - message.length - 1] = 0x01;
	memcpy(db + (dbLength - message.length), message.data, message.length);

	// Create seed
	uint8_t seedBuffer[hashLength];
	struct cdsBytes seed = cdsRandomBytes(seedBuffer, hashLength);

	// Write maskedDB = DB ^ MGF1(seed)
	uint8_t dbMask[224];
	maskGenerationFunction1(seed, cdsMutableBytes(dbMask, 224));
	uint n = hashLength + 1;
	for (uint i = 0; i < dbLength; i++, n++)
		em[n] = db[i] ^ dbMask[i];

	// Write maskedSeed = seed ^ MGF1(maskedDB)
	uint8_t seedMask[hashLength];
	maskGenerationFunction1(cdsBytes(em + hashLength + 1, dbLength), cdsMutableBytes(seedMask, hashLength));
	em[0] = 0;
	n = 1;
	for (uint i = 0; i < hashLength; i++, n++)
		em[n] = seed.data[i] ^ seedMask[i];

	return cdsBytes(em, emLength);
}

// Returns OAEP^-1(emBytes).
// IN oaep: the padded bytes, 256 bytes
// MEM message: 256 bytes used to place the return value
static struct cdsBytes decodeOAEP(struct cdsBytes oaep, uint8_t * message) {
	assert(oaep.length == 256);
	const uint8_t * em = oaep.data;

	// Extract the seed
	uint dbLength = emLength - hashLength - 1;	// 223
	uint8_t seedMask[hashLength];
	maskGenerationFunction1(cdsBytes(em + hashLength + 1, dbLength), cdsMutableBytes(seedMask, hashLength));
	uint8_t seed[hashLength];
	uint n = 1;
	for (uint i = 0; i < hashLength; i++, n++)
		seed[i] = em[n] ^ seedMask[i];

	// Prepare the DB mask
	uint8_t dbMask[224];
	maskGenerationFunction1(cdsBytes(seed, hashLength), cdsMutableBytes(dbMask, 224));

	// To guard against timing attacks, we just keep a correct flag, and continue processing
	// even if the sequence is clearly wrong. (Note that on some systems, the compiler might
	// optimize this and return directly whenever we set correct = false.)
	bool correct = true;

	// Verify the label hash
	uint i = 0;
	for (; i < 32; n++, i++) {
		//T("i "), TD(i), T(" n "), TD(n), T(" c "), TD(correct), T(" | "), TD(OAEPZeroLabelHash[i]), T(" == "), TD(em[n] ^ dbMask[i]), T(" == "), TD(em[n]), T(" ^ "), TD(dbMask[i]), NL();
		if (OAEPZeroLabelHash[i] != (em[n] ^ dbMask[i])) correct = false;
	}

	// Consume the PS (zeros)
	for (; em[n] == dbMask[i] && n < emLength; n++) i++;

	// Consume the 0x01 byte
	if (n >= emLength || (em[n] ^ dbMask[i]) != 0x01) correct = false;
	n++;
	i++;

	// Unmask the message
	uint messageLength = emLength - n;
	for (uint k = 0; n < emLength; n++, i++, k++)
		message[k] = em[n] ^ dbMask[i];

	return correct ? cdsBytes(message, messageLength) : cdsEmpty;
}

#line 16 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/RSA64/PrivateKey.inc.c"
// *** RSA Private Key

// Precalculates all parameters required in privateCrypt.
static void precalculateCrtParameters(struct cdsRSAPrivateKey * this) {
	// n = p * q
	setZero(&this->rsaPublicKey.n);
	mul(&this->rsaPublicKey.n, &this->p, &this->q);

	// p1 = p - 1
	struct cdsBigInteger p1 = CDS_BIG_INTEGER_ZERO;
	copyD(&p1, &this->p, 0);
	decrement(&p1);

	// q1 = q - 1
	struct cdsBigInteger q1 = CDS_BIG_INTEGER_ZERO;
	copyD(&q1, &this->q, 0);
	decrement(&q1);

	// phi = p1 * q1
	struct cdsBigInteger phi = CDS_BIG_INTEGER_ZERO;
	mul(&phi, &p1, &q1);

	// d = modInverse(e, phi)
	modInverse(&this->d, &this->rsaPublicKey.e, &phi);

	// dp = d % p1
	copyD(&this->dp, &this->d, 0);
	mod(&this->dp, &p1);

	// dq = d % q1
	copyD(&this->dq, &this->d, 0);
	mod(&this->dq, &q1);

	// pInv = modInverse(p, q)
	modInverse(&this->pInv, &this->p, &this->q);

	// qInv = modInverse(q, p)
	modInverse(&this->qInv, &this->q, &this->p);
}

// Initializes a private key with an e, p, and q. All other key parameters are calculated.
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

// Initializes a private key with an e, p, and q. All other key parameters are calculated.
void cdsInitializePrivateKey(struct cdsRSAPrivateKey * this, const struct cdsBytes e, const struct cdsBytes p, const struct cdsBytes q) {
	cdsBigIntegerFromBytes(&this->rsaPublicKey.e, e);
	cdsBigIntegerFromBytes(&this->p, p);
	cdsBigIntegerFromBytes(&this->q, q);
	this->isValid = ! isZero(&this->rsaPublicKey.e) && mostSignificantElement(&this->p) + 1 == elementsFor1024Bits && mostSignificantElement(&this->q) + 1 == elementsFor1024Bits;
	this->rsaPublicKey.isValid = this->isValid;
	if (this->isValid) precalculateCrtParameters(this);
}

// Crypts using the private part of the key.
// IN inputBytes: the bytes to crypt
// MEM resultBuffer: 256 bytes to place the result
static struct cdsBytes privateCrypt(const struct cdsRSAPrivateKey * this, const struct cdsBytes inputBytes, uint8_t * resultBuffer, struct cdsRSAPrivateCryptMemory * memory) {
	// Convert the input bytes to a big integer
	cdsBigIntegerFromBytes(&memory->input, inputBytes);

	// mP = ((input mod p) ^ dP)) mod p
	copyD(&memory->imodp, &memory->input, 0);
	mod(&memory->imodp, &this->p);
	modPowBigExp(&memory->modPowBig, &memory->imodp, &this->dp, &this->p);
	modPowBigResult(&memory->modPowBig);
	copyD(&memory->mP, memory->modPowBig.result, 0);

	// mQ = ((input mod q) ^ dQ)) mod q
	copyD(&memory->imodq, &memory->input, 0);
	mod(&memory->imodq, &this->q);
	modPowBigExp(&memory->modPowBig, &memory->imodq, &this->dq, &this->q);
	modPowBigResult(&memory->modPowBig);
	copyD(&memory->mQ, memory->modPowBig.result, 0);

	if (compare(&memory->mP, &memory->mQ) > 0) {
		// h = qInv * (mP - mQ) mod p
		copyD(&memory->difference, &memory->mP, 0);
		subD(&memory->difference, &memory->mQ, 0);
		setZero(&memory->h);
		mul(&memory->h, &this->qInv, &memory->difference);
		mod(&memory->h, &this->p);

		// result = mQ + h * q
		copyD(&memory->result, &memory->mQ, 0);
		mul(&memory->result, &memory->h, &this->q);
	} else {
		// h = pInv * (mQ - mP) mod q
		copyD(&memory->difference, &memory->mQ, 0);
		subD(&memory->difference, &memory->mP, 0);
		setZero(&memory->h);
		mul(&memory->h, &this->pInv, &memory->difference);
		mod(&memory->h, &this->q);

		// result = mP + h * p
		copyD(&memory->result, &memory->mP, 0);
		mul(&memory->result, &memory->h, &this->p);
	}

	// Convert the result to bytes
	cdsBytesFromBigInteger(cdsMutableBytes(resultBuffer, 256), &memory->result);
	return cdsBytes(resultBuffer, 256);
};

// Signs a short digest, such as a SHA256 hash.
// IN digest: the digest to sign, max. 190 bytes
// MEM resultBuffer: 256 bytes to place the return value
struct cdsBytes cdsSignWithMemory(const struct cdsRSAPrivateKey * this, const struct cdsBytes digest, uint8_t * resultBuffer, struct cdsRSAPrivateCryptMemory * memory) {
	// Encode the digest using PSS
	uint8_t buffer[256];
	struct cdsBytes pss = generatePSS(digest, buffer);
	//T("sign pss "), TB(pss), NL();

	// Encrypt the PSS using the private key
	return privateCrypt(this, pss, resultBuffer, memory);
};

struct cdsBytes cdsSign(const struct cdsRSAPrivateKey * this, const struct cdsBytes digest, uint8_t * resultBuffer) {
	struct cdsRSAPrivateCryptMemory memory;
	return cdsSignWithMemory(this, digest, resultBuffer, &memory);
}

// Decrypts an encrypted message.
// IN encrypted: the encrypted bytes
// MEM resultBuffer: 256 bytes to place the return value
struct cdsBytes cdsDecryptWithMemory(const struct cdsRSAPrivateKey * this, const struct cdsBytes encrypted, uint8_t * resultBuffer, struct cdsRSAPrivateCryptMemory * memory) {
	// Decrypt
	uint8_t buffer[256];
	struct cdsBytes oaep = privateCrypt(this, encrypted, buffer, memory);
	//T("decrypt oaep "), TB(oaep), NL();

	// Extract the message from the OAEP envelope
	return decodeOAEP(oaep, resultBuffer);
};

struct cdsBytes cdsDecrypt(const struct cdsRSAPrivateKey * this, const struct cdsBytes encrypted, uint8_t * resultBuffer) {
	struct cdsRSAPrivateCryptMemory memory;
	return cdsDecryptWithMemory(this, encrypted, resultBuffer, &memory);
}


#line 17 "Condensation/../../c/Condensation/all.inc.c"

#line 1 "Condensation/../../c/Condensation/RSA64/PublicKey.inc.c"
// *** RSA Public Key

void cdsInitializeEmptyPublicKey(struct cdsRSAPublicKey * this) {
	this->isValid = false;
}

// Initializes a public key with e and n.
void cdsInitializePublicKey(struct cdsRSAPublicKey * this, const struct cdsBytes e, const struct cdsBytes n) {
	cdsBigIntegerFromBytes(&this->e, e);
	cdsBigIntegerFromBytes(&this->n, n);
	this->isValid = ! isZero(&this->e) && mostSignificantElement(&this->n) + 1 == elementsFor2048Bits;
}

// Crypts using the public part of the key.
// IN inputBytes: the bytes to crypt
// MEM resultBuffer: 256 bytes to place the result
static struct cdsBytes publicCrypt(const struct cdsRSAPublicKey * this, const struct cdsBytes inputBytes, uint8_t * resultBuffer, struct cdsRSAPublicCryptMemory * memory) {
	// Convert the input bytes to a big integer
	cdsBigIntegerFromBytes(&memory->input, inputBytes);
	//T("publicCrypt input "), TBI(&input), NL();

	// Calculate
	modPowSmallExp(&memory->modPowSmall, &memory->input, &this->e, &this->n);
	//T("publicCrypt result "), TBI(modPow.result), NL();

	// Convert the result to bytes
	cdsBytesFromBigInteger(cdsMutableBytes(resultBuffer, 256), memory->modPowSmall.result);
	return cdsBytes(resultBuffer, 256);
}

bool cdsVerifyWithMemory(const struct cdsRSAPublicKey * this, const struct cdsBytes digest, const struct cdsBytes signature, struct cdsRSAPublicCryptMemory * memory) {
	// Decrypt the signature using the public key
	uint8_t buffer[256];
	struct cdsBytes pss = publicCrypt(this, signature, buffer, memory);
	//T("verify pss "), TB(pss), NL();

	// Verify if the PSS is valid
	return verifyPSS(digest, pss);
}

// Verifies a signature.
// IN digest: the signed digest, max. 256 bytes
// IN signature: the signature (usually 256 bytes)
bool cdsVerify(const struct cdsRSAPublicKey * this, const struct cdsBytes digest, const struct cdsBytes signature) {
	struct cdsRSAPublicCryptMemory memory;
	return cdsVerifyWithMemory(this, digest, signature, &memory);
}

struct cdsBytes cdsEncryptWithMemory(const struct cdsRSAPublicKey * this, const struct cdsBytes message, uint8_t * resultBuffer, struct cdsRSAPublicCryptMemory * memory) {
	// Encode the message using OAEP
	uint8_t buffer[256];
	struct cdsBytes oaep = encodeOAEP(message, buffer);
	//T("encrypt oaep "), TB(oaep), NL();

	// Encrypt
	return publicCrypt(this, oaep, resultBuffer, memory);
}

// Encrypts a short message, such as a SHA256 hash.
// IN message: the message to encrypt, max. 190 bytes
// MEM resultBuffer: 256 bytes to place the result
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
struct cdsRecord cdsEmptyRecord = {cdsEmpty, NULL, NULL, NULL};

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
	// We check for the maximum header length of 9 bytes
	if (this->used + 9 + length > this->bytes.length) return cdsMutableBytes(NULL, 0);

	// Handle the tree
	if (this->nextIsChild && this->level < CDS_MAX_RECORD_DEPTH - 1) {
		// This is the first child of the previous record
		this->nextIsChild -= 1;
		this->bytes.data[this->levelPositions[this->level]] |= 0b01000000;
		this->level += 1;
	} else if (this->level == 0) {
		// Start a new record
		this->level = 1;
	} else {
		// This is the next sibling at this level
		this->bytes.data[this->levelPositions[this->level]] |= 0b10000000;
	}

	// Start a new node
	this->levelPositions[this->level] = this->used;

	// Header
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

	// Data
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
	// Prepare the root
	records[0].bytes = cdsEmpty;
	records[0].hash = NULL;
	records[0].nextSibling = NULL;
	records[0].firstChild = NULL;

	// Read the header
	uint32_t hashesCount = cdsGetUint32BE(bytes.data);
	cdsLength pos = 4 + (cdsLength) hashesCount * 32;
	if (pos > bytes.length) return records;

	// Parse all records
	int usedRecords = 1;
	int level = 1;
	struct cdsRecord * lastSibling[CDS_MAX_RECORD_DEPTH] = {records, NULL, };
	bool hasMoreSiblings[CDS_MAX_RECORD_DEPTH] = {true, };

	while (pos < bytes.length) {
		// Flags
		int flags = bytes.data[pos];
		pos += 1;

		// Data
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
		//T("Record"), TD(level), TH(flags), TD(pos), TB(cdsByteSlice(bytes, pos, byteLength)), NL();
		//printf("Record level %d flags %d pos %d\n", level, flags, pos);
		records[usedRecords].bytes = cdsByteSlice(bytes, pos, byteLength);
		pos += byteLength;

		if (flags & 0x20) {
			// Hash
			if (pos + 4 > bytes.length) break;
			uint32_t hashIndex = cdsGetUint32BE(bytes.data + pos);
			pos += 4;
			if (hashIndex > hashesCount) break;
			records[usedRecords].hash = bytes.data + 4 + hashIndex * 32;
			//T("  Hash"), TD(hashIndex), TB(cdsBytes(records[usedRecords].hash, 32)), NL();
		} else {
			// No hash
			records[usedRecords].hash = NULL;
		}

		records[usedRecords].firstChild = NULL;
		records[usedRecords].nextSibling = NULL;

		// Link sibling or parent
		if (lastSibling[level])
			lastSibling[level]->nextSibling = records + usedRecords;
		else
			lastSibling[level - 1]->firstChild = records + usedRecords;

		lastSibling[level] = records + usedRecords;
		hasMoreSiblings[level] = flags & 0x80 ? true : false;

		if (flags & 0x40) {
			// Move down to children
			level += 1;
			if (level >= 64) break;
			lastSibling[level] = NULL;
		} else {
			// Move up to parents
			while (! hasMoreSiblings[level])
				level -= 1;
		}

		// Add this record
		usedRecords += 1;
		if (usedRecords >= length) break;

		// The record ends here
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
	//printf("obj byte length %d\n", this->publicKeyObject.length);

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

#line 5 "Condensation/C.inc.c"
#include <stdlib.h>
#include <stdint.h>

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

// *** Random bytes ***

// Generates max. 256 random bytes
SV * randomBytes(SV * svCount) {
	int count = SvIV(svCount);
	if (count > 256) count = 256;
	if (count < 0) count = 0;
	uint8_t buffer[256];
	return svFromBytes(cdsRandomBytes(buffer, count));
}

// *** SHA256 ***

SV * sha256(SV * svBytes) {
	uint8_t buffer[32];
	struct cdsBytes hash = cdsSHA256(bytesFromSV(svBytes), buffer);
	return svFromBytes(hash);
}

// *** AES ***

SV * aesCrypt(SV * svBytes, SV * svKey, SV * svStartCounter) {
	// Prepare the input
	struct cdsBytes bytes = bytesFromSV(svBytes);
	struct cdsBytes key = bytesFromSV(svKey);
	if (key.length != 32) return &PL_sv_undef;
	struct cdsBytes startCounter = bytesFromSV(svStartCounter);
	if (startCounter.length != 16) return &PL_sv_undef;

	// Crypt
	SV * svResult = newSV(bytes.length < 1 ? 1 : bytes.length);	// newSV(0) has different semantics
	struct cdsAES256 aes;
	cdsInitializeAES256(&aes, key);
	cdsCrypt(&aes, bytes, startCounter, (uint8_t *) SvPVX(svResult));

	// Set the "string" bit, and the length
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

// *** RSA Private Key ***

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

// *** RSA Public Key ***

static struct cdsRSAPublicKey * publicKeyFromSV(SV * sv) {
	if (! SvPOK(sv)) return NULL;
	STRLEN length;
	struct cdsRSAPublicKey * key = (struct cdsRSAPublicKey *) SvPV(sv, length);
	return length == sizeof(struct cdsRSAPublicKey) ? key : NULL;
}

SV * publicKeyFromPrivateKey(SV * svPrivateKey) {
	struct cdsRSAPrivateKey * key = privateKeyFromSV(svPrivateKey);

	// Make a copy of the public key
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

// *** Performance timer ***

SV * performanceStart() {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
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
	clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
	time_t dsec = ts.tv_sec - this->tv_sec;
	long dnano = ts.tv_nsec - this->tv_nsec;

	long diff = (long) dsec * 1000 * 1000 + dnano / 1000;
	return newSViv(diff);
}