# This is the Condensation Perl Module 0.22 (cli) built on 2022-01-15.
# See https://condensation.io for information about the Condensation Data System.

use strict;
use warnings;
use 5.010000;
use Cwd;
use Digest::SHA;
use Encode;
use Fcntl;
use HTTP::Date;
use HTTP::Headers;
use HTTP::Request;
use HTTP::Server::Simple;
use LWP::UserAgent;
use Time::Local;
use utf8;

package CDS;

our $VERSION = '0.22';
our $edition = 'cli';
our $releaseDate = '2022-01-15';

#line 3 "Condensation/Duration.pm"
sub now { time * 1000 }

#line 5 "Condensation/Duration.pm"
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

#line 5 "Condensation/File.pm"
	open(my $fh, '<:bytes', $filename) || return;
	local $/;
	my $content = <$fh>;
	close $fh;
	return $content;
}

sub writeBytesToFile {
	my $class = shift;
	my $filename = shift;

#line 13 "Condensation/File.pm"
	open(my $fh, '>:bytes', $filename) || return;
	print $fh @_;
	close $fh;
	return 1;
}

sub readTextFromFile {
	my $class = shift;
	my $filename = shift;

#line 20 "Condensation/File.pm"
	open(my $fh, '<:utf8', $filename) || return;
	local $/;
	my $content = <$fh>;
	close $fh;
	return $content;
}

sub writeTextToFile {
	my $class = shift;
	my $filename = shift;

#line 28 "Condensation/File.pm"
	open(my $fh, '>:utf8', $filename) || return;
	print $fh @_;
	close $fh;
	return 1;
}

sub listFolder {
	my $class = shift;
	my $folder = shift;

#line 35 "Condensation/File.pm"
	opendir(my $dh, $folder) || return;
	my @files = readdir $dh;
	closedir $dh;
	return @files;
}

sub intermediateFolders {
	my $class = shift;
	my $path = shift;

#line 42 "Condensation/File.pm"
	my @paths = ($path);
	while (1) {
		$path =~ /^(.+)\/(.*?)$/ || last;
		$path = $1;
		next if ! length $2;
		unshift @paths, $path;
	}
	return @paths;
}

#line 3 "Condensation/Log.pm"
# This is for debugging purposes only.
sub log {
	my $class = shift;

#line 5 "Condensation/Log.pm"
	print STDERR @_, "\n";
}

sub min {
	my $class = shift;

#line 4 "Condensation/MinMax.pm"
	my $min = shift;
	for my $number (@_) {
		$min = $min < $number ? $min : $number;
	}

#line 9 "Condensation/MinMax.pm"
	return $min;
}

sub max {
	my $class = shift;

#line 13 "Condensation/MinMax.pm"
	my $max = shift;
	for my $number (@_) {
		$max = $max > $number ? $max : $number;
	}

#line 18 "Condensation/MinMax.pm"
	return $max;
}

sub booleanCompare {
	my $class = shift;
	my $a = shift;
	my $b = shift;
	 $a && $b ? 0 : $a ? 1 : $b ? -1 : 0 }

# Utility functions for random sequences

#line 4 "Condensation/Random.pm"
srand(time);
our @hexDigits = ('0'..'9', 'a'..'f');

sub randomHex {
	my $class = shift;
	my $length = shift;

#line 8 "Condensation/Random.pm"
	return substr(unpack('H*', CDS::C::randomBytes(int(($length + 1) / 2))), 0, $length);
}

sub randomBytes {
	my $class = shift;
	my $length = shift;

#line 12 "Condensation/Random.pm"
	return CDS::C::randomBytes($length);
}

sub randomKey {
	my $class = shift;

#line 16 "Condensation/Random.pm"
	return CDS::C::randomBytes(32);
}

#line 3 "Condensation/Version.pm"
sub version { 'Condensation, Perl, '.$CDS::VERSION }

#line 3 "Condensation/Serialization/Static.pm"
# Conversion of numbers and booleans to and from bytes.
# To converte text, use Encode::encode_utf8($text) and Encode::decode_utf8($bytes).
# To converte hex sequences, use pack('H*', $hex) and unpack('H*', $bytes).

sub bytesFromUnsigned {
	my $class = shift;
	my $value = shift;

#line 8 "Condensation/Serialization/Static.pm"
	return '' if $value < 1;
	return pack 'C', $value if $value < 0x100;
	return pack 'S>', $value if $value < 0x10000;

#line 12 "Condensation/Serialization/Static.pm"
	# This works up to 64 bits
	my $bytes = pack 'Q>', $value;
	my $pos = 0;
	$pos += 1 while substr($bytes, $pos, 1) eq "\0";
	return substr($bytes, $pos);
}

sub bytesFromInteger {
	my $class = shift;
	my $value = shift;

#line 20 "Condensation/Serialization/Static.pm"
	return '' if $value >= 0 && $value < 1;
	return pack 'c', $value if $value >= -0x80 && $value < 0x80;
	return pack 's>', $value if $value >= -0x8000 && $value < 0x8000;

#line 24 "Condensation/Serialization/Static.pm"
	# This works up to 63 bits, plus 1 sign bit
	my $bytes = pack 'q>', $value;

#line 27 "Condensation/Serialization/Static.pm"
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

#line 47 "Condensation/Serialization/Static.pm"
	return substr($bytes, $pos);
}

sub bytesFromBoolean {
	my $class = shift;
	my $value = shift;
	 $value ? 'y' : '' }

sub unsignedFromBytes {
	my $class = shift;
	my $bytes = shift;

#line 53 "Condensation/Serialization/Static.pm"
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

#line 62 "Condensation/Serialization/Static.pm"
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

#line 73 "Condensation/Serialization/Static.pm"
	return length $bytes > 0;
}

#line 76 "Condensation/Serialization/Static.pm"
# Initial counter value for AES in CTR mode
sub zeroCTR { "\0" x 16 }

#line 79 "Condensation/Serialization/Static.pm"
my $emptyBytesHash = CDS::Hash->fromHex('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
sub emptyBytesHash { $emptyBytesHash }

#line 3 "Condensation/Stores/Static.pm"
# Checks if a box label is valid.
sub isValidBoxLabel {
	my $class = shift;
	my $label = shift;
	 $label eq 'messages' || $label eq 'private' || $label eq 'public' }

#line 6 "Condensation/Stores/Static.pm"
# Groups box additions or removals by account hash and box label.
sub groupedBoxOperations {
	my $class = shift;
	my $operations = shift;

#line 8 "Condensation/Stores/Static.pm"
	my %byAccountHash;
	for my $operation (@$operations) {
		my $accountHashBytes = $operation->{accountHash}->bytes;
		$byAccountHash{$accountHashBytes} = {accountHash => $operation->{accountHash}, byBoxLabel => {}} if ! exists $byAccountHash{$accountHashBytes};
		my $byBoxLabel = $byAccountHash{$accountHashBytes}->{byBoxLabel};
		my $boxLabel = $operation->{boxLabel};
		$byBoxLabel->{$boxLabel} = [] if ! exists $byBoxLabel->{$boxLabel};
		push @{$byBoxLabel->{$boxLabel}}, $operation;
	}

#line 18 "Condensation/Stores/Static.pm"
	return values %byAccountHash;
}

#line 3 "Condensation/Actors/OpenEnvelope.pm"
### Open envelopes ###

sub verifyEnvelopeSignature {
	my $class = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
	my $publicKey = shift; die 'wrong type '.ref($publicKey).' for $publicKey' if defined $publicKey && ref $publicKey ne 'CDS::PublicKey';
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 6 "Condensation/Actors/OpenEnvelope.pm"
	# Read the signature
	my $signature = $envelope->child('signature')->bytesValue;
	return if length $signature < 1;

#line 10 "Condensation/Actors/OpenEnvelope.pm"
	# Verify the signature
	return if ! $publicKey->verifyHash($hash, $signature);
	return 1;
}

# The result of parsing an ACCOUNT token (see Token.pm).
package CDS::AccountToken;

sub new {
	my $class = shift;
	my $cliStore = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

#line 4 "Condensation/CLI/AccountToken.pm"
	return bless {
		cliStore => $cliStore,
		actorHash => $actorHash,
		};
}

#line 10 "Condensation/CLI/AccountToken.pm"
sub cliStore { shift->{cliStore} }
sub actorHash { shift->{actorHash} }
sub url {
	my $o = shift;
	 $o->{cliStore}->url.'/accounts/'.$o->{actorHash}->hex }

package CDS::ActorGroup;

#line 4 "Condensation/Actors/ActorGroup.pm"
# Members must be sorted in descending revision order, such that the member with the most recent revision is first. Members must not include any revoked actors.
sub new {
	my $class = shift;
	my $members = shift;
	my $entrustedActorsRevision = shift;
	my $entrustedActors = shift;

#line 6 "Condensation/Actors/ActorGroup.pm"
	# Create the cache for the "contains" method
	my $containCache = {};
	for my $member (@$members) {
		$containCache->{$member->actorOnStore->publicKey->hash->bytes} = 1;
	}

#line 12 "Condensation/Actors/ActorGroup.pm"
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
#line 21 "Condensation/Actors/ActorGroup.pm"
sub entrustedActorsRevision { shift->{entrustedActorsRevision} }
sub entrustedActors {
	my $o = shift;
	 @{$o->{entrustedActors}} }

#line 24 "Condensation/Actors/ActorGroup.pm"
# Checks whether the actor group contains at least one active member.
sub isActive {
	my $o = shift;

#line 26 "Condensation/Actors/ActorGroup.pm"
	for my $member (@{$o->{members}}) {
		return 1 if $member->isActive;
	}
	return;
}

#line 32 "Condensation/Actors/ActorGroup.pm"
# Returns the most recent active member, the most recent idle member, or undef if the group is empty.
sub leader {
	my $o = shift;

#line 34 "Condensation/Actors/ActorGroup.pm"
	for my $member (@{$o->{members}}) {
		return $member if $member->isActive;
	}
	return $o->{members}->[0];
}

#line 40 "Condensation/Actors/ActorGroup.pm"
# Returns true if the account belongs to this actor group.
# Note that multiple (different) actor groups may claim that the account belongs to them. In practice, an account usually belongs to one actor group.
sub contains {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

#line 43 "Condensation/Actors/ActorGroup.pm"
	return exists $o->{containsCache}->{$actorHash->bytes};
}

#line 46 "Condensation/Actors/ActorGroup.pm"
# Returns true if the account is entrusted by this actor group.
sub entrusts {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

#line 48 "Condensation/Actors/ActorGroup.pm"
	for my $actor (@{$o->{entrustedActors}}) {
		return 1 if $actorHash->equals($actor->publicKey->hash);
	}
	return;
}

#line 54 "Condensation/Actors/ActorGroup.pm"
# Returns all public keys.
sub publicKeys {
	my $o = shift;

#line 56 "Condensation/Actors/ActorGroup.pm"
	my @publicKeys;
	for my $member (@{$o->{members}}) {
		push @publicKeys, $member->actorOnStore->publicKey;
	}
	for my $actor (@{$o->{entrustedActors}}) {
		push @publicKeys, $actor->actorOnStore->publicKey;
	}
	return @publicKeys;
}

#line 66 "Condensation/Actors/ActorGroup.pm"
# Returns an ActorGroupBuilder with all members and entrusted keys of this ActorGroup.
sub toBuilder {
	my $o = shift;

#line 68 "Condensation/Actors/ActorGroup.pm"
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

#line 2 "Condensation/Actors/ActorGroup/EntrustedActor.pm"
	return bless {
		actorOnStore => $actorOnStore,
		storeUrl => $storeUrl,
		};
}

#line 8 "Condensation/Actors/ActorGroup/EntrustedActor.pm"
sub actorOnStore { shift->{actorOnStore} }
sub storeUrl { shift->{storeUrl} }

package CDS::ActorGroup::Member;

sub new {
	my $class = shift;
	my $actorOnStore = shift; die 'wrong type '.ref($actorOnStore).' for $actorOnStore' if defined $actorOnStore && ref $actorOnStore ne 'CDS::ActorOnStore';
	my $storeUrl = shift;
	my $revision = shift;
	my $isActive = shift;

#line 2 "Condensation/Actors/ActorGroup/Member.pm"
	return bless {
		actorOnStore => $actorOnStore,
		storeUrl => $storeUrl,
		revision => $revision,
		isActive => $isActive,
		};
}

#line 10 "Condensation/Actors/ActorGroup/Member.pm"
sub actorOnStore { shift->{actorOnStore} }
sub storeUrl { shift->{storeUrl} }
sub revision { shift->{revision} }
sub isActive { shift->{isActive} }

package CDS::ActorGroupBuilder;

sub new {
	my $class = shift;

#line 5 "Condensation/Actors/ActorGroupBuilder.pm"
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
#line 14 "Condensation/Actors/ActorGroupBuilder.pm"
sub entrustedActorsRevision { shift->{entrustedActorsRevision} }
sub entrustedActors {
	my $o = shift;
	 values %{$o->{entrustedActors}} }
#line 16 "Condensation/Actors/ActorGroupBuilder.pm"
sub knownPublicKeys { shift->{knownPublicKeys} }

sub addKnownPublicKey {
	my $o = shift;
	my $publicKey = shift; die 'wrong type '.ref($publicKey).' for $publicKey' if defined $publicKey && ref $publicKey ne 'CDS::PublicKey';

#line 19 "Condensation/Actors/ActorGroupBuilder.pm"
	$o->{publicKeys}->{$publicKey->hash->bytes} = $publicKey;
}

sub addMember {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $storeUrl = shift;
	my $revision = shift // 0;
	my $status = shift // 'active';

#line 23 "Condensation/Actors/ActorGroupBuilder.pm"
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

#line 31 "Condensation/Actors/ActorGroupBuilder.pm"
	my $url = $storeUrl.'/accounts/'.$hash->hex;
	delete $o->{members}->{$url};
}

sub parseMembers {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $linkedPublicKeys = shift;

#line 36 "Condensation/Actors/ActorGroupBuilder.pm"
	die 'linked public keys?' if ! defined $linkedPublicKeys;
	for my $storeRecord ($record->children) {
		my $accountStoreUrl = $storeRecord->asText;

#line 40 "Condensation/Actors/ActorGroupBuilder.pm"
		for my $statusRecord ($storeRecord->children) {
			my $status = $statusRecord->bytes;

#line 43 "Condensation/Actors/ActorGroupBuilder.pm"
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

#line 52 "Condensation/Actors/ActorGroupBuilder.pm"
	return if $revision <= $o->{entrustedActorsRevision};
	$o->{entrustedActorsRevision} = $revision;
	$o->{entrustedActors} = {};
	return 1;
}

sub addEntrustedActor {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $storeUrl = shift;

#line 59 "Condensation/Actors/ActorGroupBuilder.pm"
	my $actor = CDS::ActorGroupBuilder::EntrustedActor->new($hash, $storeUrl);
	$o->{entrustedActors}->{$hash->bytes} = $actor;
}

sub removeEntrustedActor {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 64 "Condensation/Actors/ActorGroupBuilder.pm"
	delete $o->{entrustedActors}->{$hash->bytes};
}

sub parseEntrustedActors {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $linkedPublicKeys = shift;

#line 68 "Condensation/Actors/ActorGroupBuilder.pm"
	for my $revisionRecord ($record->children) {
		next if ! $o->mergeEntrustedActors($revisionRecord->asInteger);
		$o->parseEntrustedActorList($revisionRecord, $linkedPublicKeys);
	}
}

sub parseEntrustedActorList {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $linkedPublicKeys = shift;

#line 75 "Condensation/Actors/ActorGroupBuilder.pm"
	die 'linked public keys?' if ! defined $linkedPublicKeys;
	for my $storeRecord ($record->children) {
		my $storeUrl = $storeRecord->asText;

#line 79 "Condensation/Actors/ActorGroupBuilder.pm"
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

#line 87 "Condensation/Actors/ActorGroupBuilder.pm"
	$o->parseMembers($record->child('actor group'), $linkedPublicKeys);
	$o->parseEntrustedActors($record->child('entrusted actors'), $linkedPublicKeys);
}

sub load {
	my $o = shift;
	my $store = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $delegate = shift;

#line 92 "Condensation/Actors/ActorGroupBuilder.pm"
	return CDS::LoadActorGroup->load($o, $store, $keyPair, $delegate);
}

sub discover {
	my $o = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $delegate = shift;

#line 96 "Condensation/Actors/ActorGroupBuilder.pm"
	return CDS::DiscoverActorGroup->discover($o, $keyPair, $delegate);
}

#line 99 "Condensation/Actors/ActorGroupBuilder.pm"
# Serializes the actor group to a record that can be passed to parse.
sub addToRecord {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $linkedPublicKeys = shift;

#line 101 "Condensation/Actors/ActorGroupBuilder.pm"
	die 'linked public keys?' if ! defined $linkedPublicKeys;

#line 103 "Condensation/Actors/ActorGroupBuilder.pm"
	my $actorGroupRecord = $record->add('actor group');
	my $currentStoreUrl = undef;
	my $currentStoreRecord = undef;
	my $currentStatus = undef;
	my $currentStatusRecord = undef;
	for my $member (sort { $a->storeUrl cmp $b->storeUrl || CDS->booleanCompare($b->status, $a->status) } $o->members) {
		next if ! $member->revision;

#line 111 "Condensation/Actors/ActorGroupBuilder.pm"
		if (! defined $currentStoreUrl || $currentStoreUrl ne $member->storeUrl) {
			$currentStoreUrl = $member->storeUrl;
			$currentStoreRecord = $actorGroupRecord->addText($currentStoreUrl);
			$currentStatus = undef;
			$currentStatusRecord = undef;
		}

#line 118 "Condensation/Actors/ActorGroupBuilder.pm"
		if (! defined $currentStatus || $currentStatus ne $member->status) {
			$currentStatus = $member->status;
			$currentStatusRecord = $currentStoreRecord->add($currentStatus);
		}

#line 123 "Condensation/Actors/ActorGroupBuilder.pm"
		my $hashRecord = $linkedPublicKeys ? $currentStatusRecord->addHash($member->hash) : $currentStatusRecord->add($member->hash->bytes);
		$hashRecord->addInteger($member->revision);
	}

#line 127 "Condensation/Actors/ActorGroupBuilder.pm"
	if ($o->{entrustedActorsRevision}) {
		my $listRecord = $o->entrustedActorListToRecord($linkedPublicKeys);
		$record->add('entrusted actors')->addInteger($o->{entrustedActorsRevision})->addRecord($listRecord->children);
	}
}

sub toRecord {
	my $o = shift;
	my $linkedPublicKeys = shift;

#line 134 "Condensation/Actors/ActorGroupBuilder.pm"
	my $record = CDS::Record->new;
	$o->addToRecord($record, $linkedPublicKeys);
	return $record;
}

sub entrustedActorListToRecord {
	my $o = shift;
	my $linkedPublicKeys = shift;

#line 140 "Condensation/Actors/ActorGroupBuilder.pm"
	my $record = CDS::Record->new;
	my $currentStoreUrl = undef;
	my $currentStoreRecord = undef;
	for my $actor ($o->entrustedActors) {
		if (! defined $currentStoreUrl || $currentStoreUrl ne $actor->storeUrl) {
			$currentStoreUrl = $actor->storeUrl;
			$currentStoreRecord = $record->addText($currentStoreUrl);
		}

#line 149 "Condensation/Actors/ActorGroupBuilder.pm"
		$linkedPublicKeys ? $currentStoreRecord->addHash($actor->hash) : $currentStoreRecord->add($actor->hash->bytes);
	}

#line 152 "Condensation/Actors/ActorGroupBuilder.pm"
	return $record;
}

package CDS::ActorGroupBuilder::EntrustedActor;

sub new {
	my $class = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $storeUrl = shift;

#line 2 "Condensation/Actors/ActorGroupBuilder/EntrustedActor.pm"
	return bless {
		hash => $hash,
		storeUrl => $storeUrl,
		};
}

#line 8 "Condensation/Actors/ActorGroupBuilder/EntrustedActor.pm"
sub hash { shift->{hash} }
sub storeUrl { shift->{storeUrl} }

package CDS::ActorGroupBuilder::Member;

sub new {
	my $class = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $storeUrl = shift;
	my $revision = shift;
	my $status = shift;

#line 2 "Condensation/Actors/ActorGroupBuilder/Member.pm"
	return bless {
		hash => $hash,
		storeUrl => $storeUrl,
		revision => $revision,
		status => $status,
		};
}

#line 10 "Condensation/Actors/ActorGroupBuilder/Member.pm"
sub hash { shift->{hash} }
sub storeUrl { shift->{storeUrl} }
sub revision { shift->{revision} }
sub status { shift->{status} }

# The result of parsing an ACTORGROUP token (see Token.pm).
package CDS::ActorGroupToken;

sub new {
	my $class = shift;
	my $label = shift;
	my $actorGroup = shift; die 'wrong type '.ref($actorGroup).' for $actorGroup' if defined $actorGroup && ref $actorGroup ne 'CDS::ActorGroup';

#line 4 "Condensation/CLI/ActorGroupToken.pm"
	return bless {
		label => $label,
		actorGroup => $actorGroup,
		};
}

#line 10 "Condensation/CLI/ActorGroupToken.pm"
sub label { shift->{label} }
sub actorGroup { shift->{actorGroup} }

# A public key and a store.
package CDS::ActorOnStore;

sub new {
	my $class = shift;
	my $publicKey = shift; die 'wrong type '.ref($publicKey).' for $publicKey' if defined $publicKey && ref $publicKey ne 'CDS::PublicKey';
	my $store = shift;

#line 4 "Condensation/Actors/ActorOnStore.pm"
	return bless {
		publicKey => $publicKey,
		store => $store
		};
}

#line 10 "Condensation/Actors/ActorOnStore.pm"
sub publicKey { shift->{publicKey} }
sub store { shift->{store} }

sub equals {
	my $this = shift;
	my $that = shift;

#line 14 "Condensation/Actors/ActorOnStore.pm"
	return 1 if ! defined $this && ! defined $that;
	return if ! defined $this || ! defined $that;
	return $this->{store}->id eq $that->{store}->id && $this->{publicKey}->{hash}->equals($that->{publicKey}->{hash});
}

package CDS::ActorWithDataTree;

sub new {
	my $class = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $storageStore = shift;
	my $messagingStore = shift;
	my $messagingStoreUrl = shift;
	my $publicKeyCache = shift;

#line 2 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	my $o = bless {
		keyPair => $keyPair,
		storageStore => $storageStore,
		messagingStore => $messagingStore,
		messagingStoreUrl => $messagingStoreUrl,
		groupDataHandlers => [],
		}, $class;

#line 10 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	# Private data on the storage store
	$o->{storagePrivateRoot} = CDS::PrivateRoot->new($keyPair, $storageStore, $o);
	$o->{groupDataTree} = CDS::RootDataTree->new($o->{storagePrivateRoot}, 'group data tree');
	$o->{localDataTree} = CDS::RootDataTree->new($o->{storagePrivateRoot}, 'local data tree');

#line 15 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	# Private data on the messaging store
	$o->{messagingPrivateRoot} = $storageStore->id eq $messagingStore->id ? $o->{storagePrivateRoot} : CDS::PrivateRoot->new($keyPair, $messagingStore, $o);
	$o->{sentList} = CDS::SentList->new($o->{messagingPrivateRoot});
	$o->{sentListReady} = 0;

#line 20 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	# Group data sharing
	$o->{groupDataSharer} = CDS::GroupDataSharer->new($o);
	$o->{groupDataSharer}->addDataHandler($o->{groupDataTree}->label, $o->{groupDataTree});

#line 24 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	# Selectors
	$o->{groupRoot} = $o->{groupDataTree}->root;
	$o->{localRoot} = $o->{localDataTree}->root;
	$o->{publicDataSelector} = $o->{groupRoot}->child('public data');
	$o->{actorGroupSelector} = $o->{groupRoot}->child('actor group');
	$o->{actorSelector} = $o->{actorGroupSelector}->child(substr($keyPair->publicKey->hash->bytes, 0, 16));
	$o->{entrustedActorsSelector} = $o->{groupRoot}->child('entrusted actors');

#line 32 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	# Message reader
	my $pool = CDS::MessageBoxReaderPool->new($keyPair, $publicKeyCache, $o);
	$o->{messageBoxReader} = CDS::MessageBoxReader->new($pool, CDS::ActorOnStore->new($keyPair->publicKey, $messagingStore), CDS->HOUR);

#line 36 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	# Active actor group members and entrusted keys
	$o->{cachedGroupDataMembers} = {};
	$o->{cachedEntrustedKeys} = {};
	return $o;
}

#line 42 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
sub keyPair { shift->{keyPair} }
sub storageStore { shift->{storageStore} }
sub messagingStore { shift->{messagingStore} }
sub messagingStoreUrl { shift->{messagingStoreUrl} }

#line 47 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
sub storagePrivateRoot { shift->{storagePrivateRoot} }
sub groupDataTree { shift->{groupDataTree} }
sub localDataTree { shift->{localDataTree} }

#line 51 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
sub messagingPrivateRoot { shift->{messagingPrivateRoot} }
sub sentList { shift->{sentList} }
sub sentListReady { shift->{sentListReady} }

#line 55 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
sub groupDataSharer { shift->{groupDataSharer} }

#line 57 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
sub groupRoot { shift->{groupRoot} }
sub localRoot { shift->{localRoot} }
sub publicDataSelector { shift->{publicDataSelector} }
sub actorGroupSelector { shift->{actorGroupSelector} }
sub actorSelector { shift->{actorSelector} }
sub entrustedActorsSelector { shift->{entrustedActorsSelector} }

#line 64 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
### Our own actor ###

sub isMe {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

#line 67 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	return $o->{keyPair}->publicKey->hash->equals($actorHash);
}

sub setName {
	my $o = shift;
	my $name = shift;

#line 71 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	$o->{actorSelector}->child('name')->set($name);
}

sub getName {
	my $o = shift;

#line 75 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	return $o->{actorSelector}->child('name')->textValue;
}

sub updateMyRegistration {
	my $o = shift;

#line 79 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	$o->{actorSelector}->addObject($o->{keyPair}->publicKey->hash, $o->{keyPair}->publicKey->object);
	my $record = CDS::Record->new;
	$record->add('hash')->addHash($o->{keyPair}->publicKey->hash);
	$record->add('store')->addText($o->{messagingStoreUrl});
	$o->{actorSelector}->set($record);
}

sub setMyActiveFlag {
	my $o = shift;
	my $flag = shift;

#line 87 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	$o->{actorSelector}->child('active')->setBoolean($flag);
}

sub setMyGroupDataFlag {
	my $o = shift;
	my $flag = shift;

#line 91 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	$o->{actorSelector}->child('group data')->setBoolean($flag);
}

#line 94 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
### Actor group

sub isGroupMember {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

#line 97 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	return 1 if $actorHash->equals($o->{keyPair}->publicKey->hash);
	my $memberSelector = $o->findMember($actorHash) // return;
	return ! $memberSelector->child('revoked')->isSet;
}

sub findMember {
	my $o = shift;
	my $memberHash = shift; die 'wrong type '.ref($memberHash).' for $memberHash' if defined $memberHash && ref $memberHash ne 'CDS::Hash';

#line 103 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	for my $child ($o->{actorGroupSelector}->children) {
		my $record = $child->record;
		my $hash = $record->child('hash')->hashValue // next;
		next if ! $hash->equals($memberHash);
		return $child;
	}

#line 110 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	return;
}

sub forgetOldIdleActors {
	my $o = shift;
	my $limit = shift;

#line 114 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	for my $child ($o->{actorGroupSelector}->children) {
		next if $child->child('active')->booleanValue;
		next if $child->child('group data')->booleanValue;
		next if $child->revision > $limit;
		$child->forgetBranch;
	}
}

#line 122 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
### Group data members

sub getGroupDataMembers {
	my $o = shift;

#line 125 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	# Update the cached list
	for my $child ($o->{actorGroupSelector}->children) {
		my $record = $child->record;
		my $hash = $record->child('hash')->hashValue;
		$hash = undef if $hash->equals($o->{keyPair}->publicKey->hash);
		$hash = undef if $child->child('revoked')->isSet;
		$hash = undef if ! $child->child('group data')->isSet;

#line 133 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
		# Remove
		if (! $hash) {
			delete $o->{cachedGroupDataMembers}->{$child->label};
			next;
		}

#line 139 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
		# Keep
		my $member = $o->{cachedGroupDataMembers}->{$child->label};
		my $storeUrl = $record->child('store')->textValue;
		next if $member && $member->storeUrl eq $storeUrl && $member->actorOnStore->publicKey->hash->equals($hash);

#line 144 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
		# Verify the store
		my $store = $o->onVerifyMemberStore($storeUrl, $child);
		if (! $store) {
			delete $o->{cachedGroupDataMembers}->{$child->label};
			next;
		}

#line 151 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
		# Reuse the public key and add
		if ($member && $member->actorOnStore->publicKey->hash->equals($hash)) {
			my $actorOnStore = CDS::ActorOnStore->new($member->actorOnStore->publicKey, $store);
			$o->{cachedEntrustedKeys}->{$child->label} = {storeUrl => $storeUrl, actorOnStore => $actorOnStore};
		}

#line 157 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
		# Get the public key and add
		my ($publicKey, $invalidReason, $storeError) = $o->{keyPair}->getPublicKey($hash, $o->{groupDataTree}->unsaved);
		return if defined $storeError;
		if (defined $invalidReason) {
			delete $o->{cachedGroupDataMembers}->{$child->label};
			next;
		}

#line 165 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
		my $actorOnStore = CDS::ActorOnStore->new($publicKey, $store);
		$o->{cachedGroupDataMembers}->{$child->label} = {storeUrl => $storeUrl, actorOnStore => $actorOnStore};
	}

#line 169 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	# Return the current list
	return [map { $_->{actorOnStore} } values %{$o->{cachedGroupDataMembers}}];
}

#line 173 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
### Entrusted actors

sub entrust {
	my $o = shift;
	my $storeUrl = shift;
	my $publicKey = shift; die 'wrong type '.ref($publicKey).' for $publicKey' if defined $publicKey && ref $publicKey ne 'CDS::PublicKey';

#line 176 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
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

#line 188 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	my $selector = $o->{entrustedActorsSelector};
	my $builder = CDS::ActorGroupBuilder->new;
	$builder->parseEntrustedActorList($selector->record, 1);
	$builder->removeEntrustedActor($hash);
	$selector->set($builder->entrustedActorListToRecord(1));
	delete $o->{cachedEntrustedKeys}->{$hash->bytes};
}

sub getEntrustedKeys {
	my $o = shift;

#line 197 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	my $entrustedKeys = [];
	for my $storeRecord ($o->{entrustedActorsSelector}->record->children) {
		for my $child ($storeRecord->children) {
			my $hash = $child->hash // next;
			push @$entrustedKeys, $o->getEntrustedKey($hash) // next;
		}
	}

#line 205 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	# We could remove unused keys from $o->{cachedEntrustedKeys} here, but since this is
	# such a rare event, and doesn't consume a lot of memory, this would be overkill.

#line 208 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	return $entrustedKeys;
}

sub getEntrustedKey {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 212 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	my $entrustedKey = $o->{cachedEntrustedKeys}->{$hash->bytes};
	return $entrustedKey if $entrustedKey;

#line 215 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	my ($publicKey, $invalidReason, $storeError) = $o->{keyPair}->getPublicKey($hash, $o->{groupDataTree}->unsaved);
	return if defined $storeError;
	return if defined $invalidReason;
	$o->{cachedEntrustedKeys}->{$hash->bytes} = $publicKey;
	return $publicKey;
}

#line 222 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
### Private data

sub procurePrivateData {
	my $o = shift;
	my $interval = shift // CDS->DAY;

#line 225 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	$o->{storagePrivateRoot}->procure($interval) // return;
	$o->{groupDataTree}->read // return;
	$o->{localDataTree}->read // return;
	return 1;
}

sub savePrivateDataAndShareGroupData {
	my $o = shift;

#line 232 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	$o->{localDataTree}->save;
	$o->{groupDataTree}->save;
	$o->groupDataSharer->share;
	my $entrustedKeys = $o->getEntrustedKeys // return;
	my ($ok, $missingHash) = $o->{storagePrivateRoot}->save($entrustedKeys);
	return 1 if $ok;
	$o->onMissingObject($missingHash) if $missingHash;
	return;
}

#line 242 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
# abstract sub onVerifyMemberStore($storeUrl, $selector)
# abstract sub onPrivateRootReadingInvalidEntry($o, $source, $reason)
# abstract sub onMissingObject($missingHash)

#line 246 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
### Sending messages

sub procureSentList {
	my $o = shift;
	my $interval = shift // CDS->DAY;

#line 249 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	$o->{messagingPrivateRoot}->procure($interval) // return;
	$o->{sentList}->read // return;
	$o->{sentListReady} = 1;
	return 1;
}

sub openMessageChannel {
	my $o = shift;
	my $label = shift;
	my $validity = shift;

#line 256 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	return CDS::MessageChannel->new($o, $label, $validity);
}

sub sendMessages {
	my $o = shift;

#line 260 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
	return 1 if ! $o->{sentList}->hasChanges;
	$o->{sentList}->save;
	my $entrustedKeys = $o->getEntrustedKeys // return;
	my ($ok, $missingHash) = $o->{messagingPrivateRoot}->save($entrustedKeys);
	return 1 if $ok;
	$o->onMissingObject($missingHash) if $missingHash;
	return;
}

#line 269 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
### Receiving messages

#line 271 "Condensation/ActorWithDataTree/ActorWithDataTree.pm"
# abstract sub onMessageBoxVerifyStore($o, $senderStoreUrl, $hash, $envelope, $senderHash)
# abstract sub onMessage($o, $message)
# abstract sub onInvalidMessage($o, $source, $reason)
# abstract sub onMessageBoxEntry($o, $message)
# abstract sub onMessageBoxInvalidEntry($o, $source, $reason)

#line 3 "Condensation/ActorWithDataTree/Announce.pm"
### Announcing ###

sub announceOnAllStores {
	my $o = shift;

#line 6 "Condensation/ActorWithDataTree/Announce.pm"
	$o->announce($o->{storageStore});
	$o->announce($o->{messagingStore}) if $o->{messagingStore}->id ne $o->{storageStore}->id;
}

sub announce {
	my $o = shift;
	my $store = shift;

#line 11 "Condensation/ActorWithDataTree/Announce.pm"
	die 'probably calling old announce, which should now be announceOnAllStores' if ! defined $store;

#line 13 "Condensation/ActorWithDataTree/Announce.pm"
	# Prepare the actor group
	my $builder = CDS::ActorGroupBuilder->new;

#line 16 "Condensation/ActorWithDataTree/Announce.pm"
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

#line 30 "Condensation/ActorWithDataTree/Announce.pm"
	$builder->parseEntrustedActorList($o->entrustedActorsSelector->record, 1) if $builder->mergeEntrustedActors($o->entrustedActorsSelector->revision);

#line 32 "Condensation/ActorWithDataTree/Announce.pm"
	# Create the card
	my $card = $builder->toRecord(0);
	$card->add('public key')->addHash($o->{keyPair}->publicKey->hash);

#line 36 "Condensation/ActorWithDataTree/Announce.pm"
	# Add the public data
	for my $child ($o->publicDataSelector->children) {
		my $childRecord = $child->record;
		$card->addRecord($childRecord->children);
	}

#line 42 "Condensation/ActorWithDataTree/Announce.pm"
	# Create an unsaved state
	my $unsaved = CDS::Unsaved->new($o->publicDataSelector->dataTree->unsaved);

#line 45 "Condensation/ActorWithDataTree/Announce.pm"
	# Add the public card and the public key
	my $cardObject = $card->toObject;
	my $cardHash = $cardObject->calculateHash;
	$unsaved->state->addObject($cardHash, $cardObject);
	$unsaved->state->addObject($me, $o->keyPair->publicKey->object);

#line 51 "Condensation/ActorWithDataTree/Announce.pm"
	# Prepare the public envelope
	my $envelopeObject = $o->keyPair->createPublicEnvelope($cardHash)->toObject;
	my $envelopeHash = $envelopeObject->calculateHash;

#line 55 "Condensation/ActorWithDataTree/Announce.pm"
	# Upload the objects
	my ($missingObject, $transferStore, $transferError) = $o->keyPair->transfer([$cardHash], $unsaved, $store);
	return if defined $transferError;
	if ($missingObject) {
		$missingObject->{context} = 'announce on '.$store->id;
		$o->onMissingObject($missingObject);
		return;
	}

#line 64 "Condensation/ActorWithDataTree/Announce.pm"
	# Prepare to modify
	my $modifications = CDS::StoreModifications->new;
	$modifications->add($me, 'public', $envelopeHash, $envelopeObject);

#line 68 "Condensation/ActorWithDataTree/Announce.pm"
	# List the current cards to remove them
	# Ignore errors, in the worst case, we are going to have multiple entries in the public box
	my ($hashes, $error) = $store->list($me, 'public', 0, $o->keyPair);
	if ($hashes) {
		for my $hash (@$hashes) {
			$modifications->remove($me, 'public', $hash);
		}
	}

#line 77 "Condensation/ActorWithDataTree/Announce.pm"
	# Modify the public box
	my $modifyError = $store->modify($modifications, $o->keyPair);
	return if defined $modifyError;
	return $envelopeHash, $cardHash;
}

# The result of parsing a BOX token (see Token.pm).
package CDS::BoxToken;

sub new {
	my $class = shift;
	my $accountToken = shift;
	my $boxLabel = shift;

#line 4 "Condensation/CLI/BoxToken.pm"
	return bless {
		accountToken => $accountToken,
		boxLabel => $boxLabel
		};
}

#line 10 "Condensation/CLI/BoxToken.pm"
sub accountToken { shift->{accountToken} }
sub boxLabel { shift->{boxLabel} }
sub url {
	my $o = shift;
	 $o->{accountToken}->url.'/'.$o->{boxLabel} }

package CDS::CLIActor;

use parent -norequire, 'CDS::ActorWithDataTree';

sub openOrCreateDefault {
	my $class = shift;
	my $ui = shift;

#line 4 "Condensation/CLI/CLIActor.pm"
	$class->open(CDS::Configuration->getOrCreateDefault($ui));
}

sub open {
	my $class = shift;
	my $configuration = shift;

#line 8 "Condensation/CLI/CLIActor.pm"
	# Read the store configuration
	my $ui = $configuration->ui;
	my $storeManager = CDS::CLIStoreManager->new($ui);

#line 12 "Condensation/CLI/CLIActor.pm"
	my $storageStoreUrl = $configuration->storageStoreUrl;
	my $storageStore = $storeManager->uncachedStoreForUrl($storageStoreUrl) // return $ui->error('Your storage store "', $storageStoreUrl, '" cannot be accessed. You can set this store in "', $configuration->file('store'), '".');

#line 15 "Condensation/CLI/CLIActor.pm"
	my $messagingStoreUrl = $configuration->messagingStoreUrl;
	my $messagingStore = $storeManager->uncachedStoreForUrl($messagingStoreUrl) // return $ui->error('Your messaging store "', $messagingStoreUrl, '" cannot be accessed. You can set this store in "', $configuration->file('messaging-store'), '".');

#line 18 "Condensation/CLI/CLIActor.pm"
	# Read the key pair
	my $keyPair = $configuration->keyPair // return $ui->error('Your key pair (', $configuration->file('key-pair'), ') is missing.');

#line 21 "Condensation/CLI/CLIActor.pm"
	# Create the actor
	my $publicKeyCache = CDS::PublicKeyCache->new(128);
	my $o = $class->SUPER::new($keyPair, $storageStore, $messagingStore, $messagingStoreUrl, $publicKeyCache);
	$o->{ui} = $ui;
	$o->{storeManager} = $storeManager;
	$o->{configuration} = $configuration;
	$o->{sessionRoot} = $o->localRoot->child('sessions')->child(''.getppid);
	$o->{keyPairToken} = CDS::KeyPairToken->new($configuration->file('key-pair'), $keyPair);

#line 30 "Condensation/CLI/CLIActor.pm"
	# Message handlers
	$o->{messageHandlers} = {};
	$o->setMessageHandler('sender', \&onIgnoreMessage);
	$o->setMessageHandler('store', \&onIgnoreMessage);
	$o->setMessageHandler('group data', \&onGroupDataMessage);

#line 36 "Condensation/CLI/CLIActor.pm"
	# Read the private data
	if (! $o->procurePrivateData) {
		$o->{ui}->space;
		$ui->pRed('Failed to read the local private data.');
		$o->{ui}->space;
		return;
	}

#line 44 "Condensation/CLI/CLIActor.pm"
	return $o;
}

#line 47 "Condensation/CLI/CLIActor.pm"
sub ui { shift->{ui} }
sub storeManager { shift->{storeManager} }
sub configuration { shift->{configuration} }
sub sessionRoot { shift->{sessionRoot} }
sub keyPairToken { shift->{keyPairToken} }

#line 53 "Condensation/CLI/CLIActor.pm"
### Saving

sub saveOrShowError {
	my $o = shift;

#line 56 "Condensation/CLI/CLIActor.pm"
	$o->forgetOldSessions;
	my ($ok, $missingHash) = $o->savePrivateDataAndShareGroupData;
	return if ! $ok;
	return $o->onMissingObject($missingHash) if $missingHash;
	$o->sendMessages;
	return 1;
}

sub onMissingObject {
	my $o = shift;
	my $missingObject = shift; die 'wrong type '.ref($missingObject).' for $missingObject' if defined $missingObject && ref $missingObject ne 'CDS::Object';

#line 65 "Condensation/CLI/CLIActor.pm"
	$o->{ui}->space;
	$o->{ui}->pRed('The object ', $missingObject->hash->hex, ' was missing while saving data.');
	$o->{ui}->space;
	$o->{ui}->p('This is a fatal error with two possible sources:');
	$o->{ui}->p('- A store may have lost objects, e.g. due to an error with the underlying storage, misconfiguration, or too aggressive garbage collection.');
	$o->{ui}->p('- The application is linking objects without properly storing them. This is an error in the application, that must be fixed by a developer.');
	$o->{ui}->space;
}

sub onGroupDataSharingStoreError {
	my $o = shift;
	my $recipientActorOnStore = shift; die 'wrong type '.ref($recipientActorOnStore).' for $recipientActorOnStore' if defined $recipientActorOnStore && ref $recipientActorOnStore ne 'CDS::ActorOnStore';
	my $storeError = shift;

#line 75 "Condensation/CLI/CLIActor.pm"
	$o->{ui}->space;
	$o->{ui}->pRed('Unable to share the group data with ', $recipientActorOnStore->publicKey->hash->hex, '.');
	$o->{ui}->space;
}

#line 80 "Condensation/CLI/CLIActor.pm"
### Reading

sub onPrivateRootReadingInvalidEntry {
	my $o = shift;
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';
	my $reason = shift;

#line 83 "Condensation/CLI/CLIActor.pm"
	$o->{ui}->space;
	$o->{ui}->pRed('The envelope ', $source->hash->shortHex, ' points to invalid private data (', $reason, ').');
	$o->{ui}->p('This could be due to a storage system failure, a malicious attempt to delete or modify your data, or simply an application error. To investigate what is going on, the following commands may be helpful:');
	$o->{ui}->line('  cds open envelope ', $source->hash->hex, ' from ', $source->actorOnStore->publicKey->hash->hex, ' on ', $source->actorOnStore->store->url);
	$o->{ui}->line('  cds show record ', $source->hash->hex, ' on ', $source->actorOnStore->store->url);
	$o->{ui}->line('  cds list private box of ', $source->actorOnStore->publicKey->hash->hex, ' on ', $source->actorOnStore->store->url);
	$o->{ui}->p('To remove the invalid entry, type:');
	$o->{ui}->line('  cds remove ', $source->hash->hex, ' from private box of ', $source->actorOnStore->publicKey->hash->hex, ' on ', $source->actorOnStore->store->url);
	$o->{ui}->space;
}

sub onVerifyMemberStore {
	my $o = shift;
	my $storeUrl = shift;
	my $actorSelector = shift; die 'wrong type '.ref($actorSelector).' for $actorSelector' if defined $actorSelector && ref $actorSelector ne 'CDS::Selector';
	 $o->storeForUrl($storeUrl) }

#line 96 "Condensation/CLI/CLIActor.pm"
### Announcing

sub registerIfNecessary {
	my $o = shift;

#line 99 "Condensation/CLI/CLIActor.pm"
	my $now = CDS->now;
	return if $o->{actorSelector}->revision > $now - CDS->DAY;
	$o->updateMyRegistration;
	$o->setMyActiveFlag(1);
	$o->setMyGroupDataFlag(1);
}

sub announceIfNecessary {
	my $o = shift;

#line 107 "Condensation/CLI/CLIActor.pm"
	my $state = join('', map { CDS->bytesFromUnsigned($_->revision) } sort { $a->label cmp $b->label } $o->{actorGroupSelector}->children);
	$o->announceOnStoreIfNecessary($o->{storageStore}, $state);
	$o->announceOnStoreIfNecessary($o->{messagingStore}, $state) if $o->{messagingStore}->id ne $o->{storageStore}->id;
}

sub announceOnStoreIfNecessary {
	my $o = shift;
	my $store = shift;
	my $state = shift;

#line 113 "Condensation/CLI/CLIActor.pm"
	my $stateSelector = $o->{localRoot}->child('announced')->childWithText($store->id);
	return if $stateSelector->bytesValue eq $state;
	my ($envelopeHash, $cardHash) = $o->announce($store);
	return $o->{ui}->pRed('Updating the card on ', $store->url, ' failed.') if ! $envelopeHash;
	$stateSelector->setBytes($state);
	$o->{ui}->pGreen('The card on ', $store->url, ' has been updated.');
	return 1;
}

#line 122 "Condensation/CLI/CLIActor.pm"
### Store resolving

sub storeForUrl {
	my $o = shift;
	my $url = shift;

#line 125 "Condensation/CLI/CLIActor.pm"
	my $store = &main::uncachedStoreForUrl($url) // return;
	my $progressShowingStore = CDS::UI::ProgressStore->new($store, $url, $o->{ui});
	my $cacheStore = $o->cacheStore;
	my $cachedStore = defined $cacheStore ? CDS::ObjectCache->new($progressShowingStore, $cacheStore) : $progressShowingStore;
	return CDS::ErrorHandlingStore->new($cachedStore, $url, $o->{storeManager});
}

sub cacheStore {
	my $o = shift;

#line 133 "Condensation/CLI/CLIActor.pm"
	my $selector = $o->{sessionRoot}->child('use cache');
	return if ! $selector->isSet;
	my $storeUrl = $selector->textValue;
	return $o->{cacheStore} if defined $o->{cacheStoreUrl} && $storeUrl eq $o->{cacheStoreUrl};

#line 138 "Condensation/CLI/CLIActor.pm"
	$o->{cacheStoreUrl} = $storeUrl;
	$o->{cacheStore} = &main::uncachedStoreForUrl($storeUrl);
	return $o->{cacheStore};
}

#line 143 "Condensation/CLI/CLIActor.pm"
### Processing messages

sub setMessageHandler {
	my $o = shift;
	my $type = shift;
	my $handler = shift;

#line 146 "Condensation/CLI/CLIActor.pm"
	$o->{messageHandlers}->{$type} = $handler;
}

sub readMessages {
	my $o = shift;

#line 150 "Condensation/CLI/CLIActor.pm"
	$o->{ui}->title('Messages');
	$o->{countMessages} = 0;
	$o->{messageBoxReader}->read;
	$o->{ui}->line($o->{ui}->gray('none')) if ! $o->{countMessages};
}

sub onMessageBoxVerifyStore {
	my $o = shift;
	my $senderStoreUrl = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
	my $senderHash = shift; die 'wrong type '.ref($senderHash).' for $senderHash' if defined $senderHash && ref $senderHash ne 'CDS::Hash';

#line 157 "Condensation/CLI/CLIActor.pm"
	return $o->storeForUrl($senderStoreUrl);
}

sub onMessageBoxEntry {
	my $o = shift;
	my $message = shift;

#line 161 "Condensation/CLI/CLIActor.pm"
	$o->{countMessages} += 1;

#line 163 "Condensation/CLI/CLIActor.pm"
	for my $section ($message->content->children) {
		my $type = $section->bytes;
		my $handler = $o->{messageHandlers}->{$type} // \&onUnknownMessage;
		&$handler($o, $message, $section);
	}

#line 169 "Condensation/CLI/CLIActor.pm"
#	1. message processed
#		-> source can be deleted immediately (e.g. invalid)
#			source.discard()
#		-> source has been merged, and will be deleted when changes have been saved
#			dataTree.addMergedSource(source)
#	2. wait for sender store
#		-> set entry.waitForStore = senderStore
#	3. skip
#		-> set entry.processed = false

#line 179 "Condensation/CLI/CLIActor.pm"
	my $source = $message->source;
	$message->source->discard;
}

sub onGroupDataMessage {
	my $o = shift;
	my $message = shift;
	my $section = shift;

#line 184 "Condensation/CLI/CLIActor.pm"
	my $ok = $o->{groupDataSharer}->processGroupDataMessage($message, $section);
	$o->{groupDataTree}->read;
	return $o->{ui}->line('Group data from ', $message->sender->publicKey->hash->hex) if $ok;
	$o->{ui}->line($o->{ui}->red('Group data from foreign actor ', $message->sender->publicKey->hash->hex, ' (ignored)'));
}

sub onIgnoreMessage {
	my $o = shift;
	my $message = shift;
	my $section = shift;
	 }

sub onUnknownMessage {
	my $o = shift;
	my $message = shift;
	my $section = shift;

#line 193 "Condensation/CLI/CLIActor.pm"
	$o->{ui}->line($o->{ui}->orange('Unknown message of type "', $section->asText, '" from ', $message->sender->publicKey->hash->hex));
}

sub onMessageBoxInvalidEntry {
	my $o = shift;
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';
	my $reason = shift;

#line 197 "Condensation/CLI/CLIActor.pm"
	$o->{ui}->warning('Discarding invalid message ', $source->hash->hex, ' (', $reason, ').');
	$source->discard;
}

#line 201 "Condensation/CLI/CLIActor.pm"
### Remembered values

sub labelSelector {
	my $o = shift;
	my $label = shift;

#line 204 "Condensation/CLI/CLIActor.pm"
	my $bytes = Encode::encode_utf8($label);
	return $o->groupRoot->child('labels')->child($bytes);
}

sub remembered {
	my $o = shift;
	my $label = shift;

#line 209 "Condensation/CLI/CLIActor.pm"
	return $o->labelSelector($label)->record;
}

sub remember {
	my $o = shift;
	my $label = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 213 "Condensation/CLI/CLIActor.pm"
	$o->labelSelector($label)->set($record);
}

sub rememberedRecords {
	my $o = shift;

#line 217 "Condensation/CLI/CLIActor.pm"
	my $records = {};
	for my $child ($o->{groupRoot}->child('labels')->children) {
		next if ! $child->isSet;
		my $label = Encode::decode_utf8($child->label);
		$records->{$label} = $child->record;
	}

#line 224 "Condensation/CLI/CLIActor.pm"
	return $records;
}

sub storeLabel {
	my $o = shift;
	my $storeUrl = shift;

#line 228 "Condensation/CLI/CLIActor.pm"
	my $records = $o->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if length $record->child('actor')->bytesValue;
		next if $storeUrl ne $record->child('store')->textValue;
		return $label;
	}

#line 236 "Condensation/CLI/CLIActor.pm"
	return;
}

sub actorLabel {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

#line 240 "Condensation/CLI/CLIActor.pm"
	my $records = $o->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if $actorHash->bytes ne $record->child('actor')->bytesValue;
		return $label;
	}

#line 247 "Condensation/CLI/CLIActor.pm"
	return;
}

sub actorLabelByHashStartBytes {
	my $o = shift;
	my $actorHashStartBytes = shift;

#line 251 "Condensation/CLI/CLIActor.pm"
	my $length = length $actorHashStartBytes;
	my $records = $o->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if $actorHashStartBytes ne substr($record->child('actor')->bytesValue, 0, $length);
		return $label;
	}

#line 259 "Condensation/CLI/CLIActor.pm"
	return;
}

sub accountLabel {
	my $o = shift;
	my $storeUrl = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

#line 263 "Condensation/CLI/CLIActor.pm"
	my $storeLabel;
	my $actorLabel;

#line 266 "Condensation/CLI/CLIActor.pm"
	my $records = $o->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		my $actorBytes = $record->child('actor')->bytesValue;

#line 271 "Condensation/CLI/CLIActor.pm"
		my $correctActor = $actorHash->bytes eq $actorBytes;
		$actorLabel = $label if $correctActor;

#line 274 "Condensation/CLI/CLIActor.pm"
		if ($storeUrl eq $record->child('store')->textValue) {
			return $label if $correctActor;
			$storeLabel = $label if ! length $actorBytes;
		}
	}

#line 280 "Condensation/CLI/CLIActor.pm"
	return (undef, $storeLabel, $actorLabel);
}

sub keyPairLabel {
	my $o = shift;
	my $file = shift;

#line 284 "Condensation/CLI/CLIActor.pm"
	my $records = $o->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if $file ne $record->child('key pair')->textValue;
		return $label;
	}

#line 291 "Condensation/CLI/CLIActor.pm"
	return;
}

#line 294 "Condensation/CLI/CLIActor.pm"
### References that can be used in commands

sub actorReference {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

#line 297 "Condensation/CLI/CLIActor.pm"
	return $o->actorLabel($actorHash) // $actorHash->hex;
}

sub storeReference {
	my $o = shift;
	my $store = shift;
	 $o->storeUrlReference($store->url); }

sub storeUrlReference {
	my $o = shift;
	my $storeUrl = shift;

#line 303 "Condensation/CLI/CLIActor.pm"
	return $o->storeLabel($storeUrl) // $storeUrl;
}

sub accountReference {
	my $o = shift;
	my $accountToken = shift;

#line 307 "Condensation/CLI/CLIActor.pm"
	my ($accountLabel, $storeLabel, $actorLabel) = $o->accountLabel($accountToken->{cliStore}->url, $accountToken->{actorHash});
	return $accountLabel if defined $accountLabel;
	return defined $actorLabel ? $actorLabel : $accountToken->{actorHash}->hex, ' on ', defined $storeLabel ? $storeLabel : $accountToken->{cliStore}->url;
}

sub boxReference {
	my $o = shift;
	my $boxToken = shift;

#line 313 "Condensation/CLI/CLIActor.pm"
	return $o->boxName($boxToken->{boxLabel}), ' of ', $o->accountReference($boxToken->{accountToken});
}

sub keyPairReference {
	my $o = shift;
	my $keyPairToken = shift;

#line 317 "Condensation/CLI/CLIActor.pm"
	return $o->keyPairLabel($keyPairToken->file) // $keyPairToken->file;
}

sub blueActorReference {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

#line 321 "Condensation/CLI/CLIActor.pm"
	my $label = $o->actorLabel($actorHash);
	return defined $label ? $o->{ui}->blue($label) : $actorHash->hex;
}

sub blueStoreReference {
	my $o = shift;
	my $store = shift;
	 $o->blueStoreUrlReference($store->url); }

sub blueStoreUrlReference {
	my $o = shift;
	my $storeUrl = shift;

#line 328 "Condensation/CLI/CLIActor.pm"
	my $label = $o->storeLabel($storeUrl);
	return defined $label ? $o->{ui}->blue($label) : $storeUrl;
}

sub blueAccountReference {
	my $o = shift;
	my $accountToken = shift;

#line 333 "Condensation/CLI/CLIActor.pm"
	my ($accountLabel, $storeLabel, $actorLabel) = $o->accountLabel($accountToken->{cliStore}->url, $accountToken->{actorHash});
	return $o->{ui}->blue($accountLabel) if defined $accountLabel;
	return defined $actorLabel ? $o->{ui}->blue($actorLabel) : $accountToken->{actorHash}->hex, ' on ', defined $storeLabel ? $o->{ui}->blue($storeLabel) : $accountToken->{cliStore}->url;
}

sub blueBoxReference {
	my $o = shift;
	my $boxToken = shift;

#line 339 "Condensation/CLI/CLIActor.pm"
	return $o->boxName($boxToken->{boxLabel}), ' of ', $o->blueAccountReference($boxToken->{accountToken});
}

sub blueKeyPairReference {
	my $o = shift;
	my $keyPairToken = shift;

#line 343 "Condensation/CLI/CLIActor.pm"
	my $label = $o->keyPairLabel($keyPairToken->file);
	return defined $label ? $o->{ui}->blue($label) : $keyPairToken->file;
}

sub boxName {
	my $o = shift;
	my $boxLabel = shift;

#line 348 "Condensation/CLI/CLIActor.pm"
	return 'private box' if $boxLabel eq 'private';
	return 'public box' if $boxLabel eq 'public';
	return 'message box' if $boxLabel eq 'messages';
	return $boxLabel;
}

#line 354 "Condensation/CLI/CLIActor.pm"
### Session

sub forgetOldSessions {
	my $o = shift;

#line 357 "Condensation/CLI/CLIActor.pm"
	for my $child ($o->{sessionRoot}->parent->children) {
		my $pid = $child->label;
		next if -e '/proc/'.$pid;
		$child->forgetBranch;
	}
}

sub selectedKeyPairToken {
	my $o = shift;

#line 365 "Condensation/CLI/CLIActor.pm"
	my $file = $o->{sessionRoot}->child('selected key pair')->textValue;
	return if ! length $file;
	my $keyPair = CDS::KeyPair->fromFile($file) // return;
	return CDS::KeyPairToken->new($file, $keyPair);
}

sub selectedStoreUrl {
	my $o = shift;

#line 372 "Condensation/CLI/CLIActor.pm"
	my $storeUrl = $o->{sessionRoot}->child('selected store')->textValue;
	return if ! length $storeUrl;
	return $storeUrl;
}

sub selectedStore {
	my $o = shift;

#line 378 "Condensation/CLI/CLIActor.pm"
	my $storeUrl = $o->selectedStoreUrl // return;
	return $o->storeForUrl($storeUrl);
}

sub selectedActorHash {
	my $o = shift;

#line 383 "Condensation/CLI/CLIActor.pm"
	return CDS::Hash->fromBytes($o->{sessionRoot}->child('selected actor')->bytesValue);
}

sub preferredKeyPairToken {
	my $o = shift;
	 $o->selectedKeyPairToken // $o->keyPairToken }
sub preferredStore {
	my $o = shift;
	 $o->selectedStore // $o->storageStore }
sub preferredStores {
	my $o = shift;
	 $o->selectedStore // ($o->storageStore, $o->messagingStore) }
sub preferredActorHash {
	my $o = shift;
	 $o->selectedActorHash // $o->keyPair->publicKey->hash }

#line 391 "Condensation/CLI/CLIActor.pm"
### Common functions

sub uiGetObject {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $store = shift;
	my $keyPairToken = shift;

#line 394 "Condensation/CLI/CLIActor.pm"
	my ($object, $storeError) = $store->get($hash, $keyPairToken->keyPair);
	return if defined $storeError;
	return $o->{ui}->error('The object ', $hash->hex, ' does not exist on "', $store->url, '".') if ! $object;
	return $object;
}

sub uiGetRecord {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $store = shift;
	my $keyPairToken = shift;

#line 401 "Condensation/CLI/CLIActor.pm"
	my $object = $o->uiGetObject($hash, $store, $keyPairToken) // return;
	return CDS::Record->fromObject($object) // return $o->{ui}->error('The object ', $hash->hex, ' is not a record.');
}

sub uiGetPublicKey {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $store = shift;
	my $keyPairToken = shift;

#line 406 "Condensation/CLI/CLIActor.pm"
	my $object = $o->uiGetObject($hash, $store, $keyPairToken) // return;
	return CDS::PublicKey->fromObject($object) // return $o->{ui}->error('The object ', $hash->hex, ' is not a public key.');
}

sub isEnvelope {
	my $o = shift;
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

#line 411 "Condensation/CLI/CLIActor.pm"
	my $record = CDS::Record->fromObject($object) // return;
	return if ! $record->contains('signed');
	my $signatureRecord = $record->child('signature')->firstChild;
	return if ! $signatureRecord->hash;
	return if ! length $signatureRecord->bytes;
	return 1;
}

package CDS::CLIStoreManager;

sub new {
	my $class = shift;
	my $ui = shift;

#line 2 "Condensation/CLI/CLIStoreManager.pm"
	return bless {ui => $ui, failedStores => {}};
}

#line 5 "Condensation/CLI/CLIStoreManager.pm"
sub ui { shift->{ui} }

sub uncachedStoreForUrl {
	my $o = shift;
	my $url = shift;

#line 8 "Condensation/CLI/CLIStoreManager.pm"
	my $store = &main::uncachedStoreForUrl($url) // return;
	my $progressStore = CDS::UI::ProgressStore->new($store, $url, $o->{ui});
	return CDS::ErrorHandlingStore->new($progressStore, $url, $o);
}

sub onStoreSuccess {
	my $o = shift;
	my $store = shift;
	my $function = shift;

#line 14 "Condensation/CLI/CLIStoreManager.pm"
	delete $o->{failedStores}->{$store->store->id};
}

sub onStoreError {
	my $o = shift;
	my $store = shift;
	my $function = shift;
	my $error = shift;

#line 18 "Condensation/CLI/CLIStoreManager.pm"
	$o->{failedStores}->{$store->store->id} = 1;
	$o->{ui}->error('The store "', $store->{url}, '" reports: ', $error);
}

sub hasStoreError {
	my $o = shift;
	my $store = shift;
	my $function = shift;

#line 23 "Condensation/CLI/CLIStoreManager.pm"
	return if ! $o->{failedStores}->{$store->store->id};
	$o->{ui}->error('Ignoring store "', $store->{url}, '", because it previously reported errors.');
	return 1;
}

package CDS::CheckSignatureStore;

sub new {
	my $o = shift;
	my $store = shift;
	my $objects = shift;

#line 2 "Condensation/Stores/CheckSignatureStore.pm"
	return bless {
		store => $store,
		id => "Check signature store\n".$store->id,
		objects => $objects // {},
		};
}

#line 9 "Condensation/Stores/CheckSignatureStore.pm"
sub id { shift->{id} }

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 12 "Condensation/Stores/CheckSignatureStore.pm"
	my $entry = $o->{objects}->{$hash->bytes} // return $o->{store}->get($hash);
	return $entry->{object};
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 17 "Condensation/Stores/CheckSignatureStore.pm"
	return exists $o->{objects}->{$hash->bytes};
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 21 "Condensation/Stores/CheckSignatureStore.pm"
	$o->{objects}->{$hash->bytes} = {hash => $hash, object => $object};
	return;
}

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 26 "Condensation/Stores/CheckSignatureStore.pm"
	return 'This store only handles objects.';
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 30 "Condensation/Stores/CheckSignatureStore.pm"
	return 'This store only handles objects.';
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 34 "Condensation/Stores/CheckSignatureStore.pm"
	return 'This store only handles objects.';
}

sub modify {
	my $o = shift;
	my $modifications = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 38 "Condensation/Stores/CheckSignatureStore.pm"
	return $modifications->executeIndividually($o, $keyPair);
}

# BEGIN AUTOGENERATED
package CDS::Commands::ActorGroup;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/ActorGroup.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node010 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&show});
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(0);
	my $node014 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&joinMember});
	my $node015 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&setMember});
	my $node016 = CDS::Parser::Node->new(0);
	$cds->addArrow($node001, 1, 0, 'show');
	$cds->addArrow($node003, 1, 0, 'join');
	$cds->addArrow($node004, 1, 0, 'set');
	$help->addArrow($node000, 1, 0, 'actor');
	$node000->addArrow($node009, 1, 0, 'group');
	$node001->addArrow($node002, 1, 0, 'actor');
	$node002->addArrow($node010, 1, 0, 'group');
	$node003->addArrow($node005, 1, 0, 'member');
	$node004->addArrow($node007, 1, 0, 'member');
	$node005->addDefault($node006);
	$node005->addArrow($node011, 1, 0, 'ACTOR', \&collectActor);
	$node006->addArrow($node006, 1, 0, 'ACCOUNT', \&collectAccount);
	$node006->addArrow($node014, 1, 1, 'ACCOUNT', \&collectAccount);
	$node007->addDefault($node008);
	$node008->addArrow($node008, 1, 0, 'ACTOR', \&collectActor1);
	$node008->addArrow($node013, 1, 0, 'ACTOR', \&collectActor1);
	$node011->addArrow($node012, 1, 0, 'on');
	$node012->addArrow($node014, 1, 0, 'STORE', \&collectStore);
	$node013->addArrow($node015, 1, 0, 'active', \&collectActive);
	$node013->addArrow($node015, 1, 0, 'backup', \&collectBackup);
	$node013->addArrow($node015, 1, 0, 'idle', \&collectIdle);
	$node013->addArrow($node015, 1, 0, 'revoked', \&collectRevoked);
	$node014->addArrow($node016, 1, 0, 'and');
	$node016->addDefault($node005);
}

sub collectAccount {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 48 "Condensation/CLI/Commands/ActorGroup.pm"
	push @{$o->{accountTokens}}, $value;
}

sub collectActive {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 52 "Condensation/CLI/Commands/ActorGroup.pm"
	$o->{status} = 'active';
}

sub collectActor {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 56 "Condensation/CLI/Commands/ActorGroup.pm"
	$o->{actorHash} = $value;
}

sub collectActor1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 60 "Condensation/CLI/Commands/ActorGroup.pm"
	push @{$o->{actorHashes}}, $value;
}

sub collectBackup {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 64 "Condensation/CLI/Commands/ActorGroup.pm"
	$o->{status} = 'backup';
}

sub collectIdle {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 68 "Condensation/CLI/Commands/ActorGroup.pm"
	$o->{status} = 'idle';
}

sub collectRevoked {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 72 "Condensation/CLI/Commands/ActorGroup.pm"
	$o->{status} = 'revoked';
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 76 "Condensation/CLI/Commands/ActorGroup.pm"
	push @{$o->{accountTokens}}, CDS::AccountToken->new($value, $o->{actorHash});
	delete $o->{actorHash};
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 82 "Condensation/CLI/Commands/ActorGroup.pm"
# END AUTOGENERATED

#line 84 "Condensation/CLI/Commands/ActorGroup.pm"
# HTML FOLDER NAME actor-group
# HTML TITLE Actor group
sub help {
	my $o = shift;
	my $cmd = shift;

#line 87 "Condensation/CLI/Commands/ActorGroup.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds show actor group');
	$ui->p('Shows all members of our actor group and the entrusted keys.');
	$ui->space;
	$ui->command('cds join ACCOUNT*');
	$ui->command('cds join ACTOR on STORE');
	$ui->p('Adds a member to our actor group. To complete the association, the new member must join us, too.');
	$ui->space;
	$ui->command('cds set member ACTOR* active');
	$ui->command('cds set member ACTOR* backup');
	$ui->command('cds set member ACTOR* idle');
	$ui->command('cds set member ACTOR* revoked');
	$ui->p('Changes the status of a member to one of the following:');
	$ui->p($ui->bold('Active members'), ' share the group data among themselves, and are advertised to receive messages.');
	$ui->p($ui->bold('Backup members'), ' share the group data (like active members), but are publicly advertised as not processing messages (like idle members). This is suitable for backup actors.');
	$ui->p($ui->bold('Idle members'), ' are part of the group, but advertised as not processing messages. They generally do not have the latest group data, and may have no group data at all. Idle members may reactivate themselves, or get reactivated by any active member of the group.');
	$ui->p($ui->bold('Revoked members'), ' have explicitly been removed from the group, e.g. because their private key (or device) got lost. Revoked members can be reactivated by any active member of the group.');
	$ui->p('Note that changing the status does not start or stop the corresponding actor, but just change how it is regarded by others. The status of each member should reflect its actual behavior.');
	$ui->space;
	$ui->p('After modifying the actor group members, you should "cds announce" yourself to publish the changes.');
	$ui->space;
}

sub show {
	my $o = shift;
	my $cmd = shift;

#line 112 "Condensation/CLI/Commands/ActorGroup.pm"
	my $hasMembers = 0;
	for my $actorSelector ($o->{actor}->actorGroupSelector->children) {
		my $record = $actorSelector->record;
		my $hash = $record->child('hash')->hashValue // next;
		next if substr($hash->bytes, 0, length $actorSelector->label) ne $actorSelector->label;
		my $storeUrl = $record->child('store')->textValue;
		my $revisionText = $o->{ui}->niceDateTimeLocal($actorSelector->revision);
		$o->{ui}->line($o->{ui}->gray($revisionText), '  ', $o->coloredType7($actorSelector), '  ', $hash->hex, ' on ', $storeUrl);
		$hasMembers = 1;
	}

#line 123 "Condensation/CLI/Commands/ActorGroup.pm"
	return if $hasMembers;
	$o->{ui}->line($o->{ui}->blue('(just you)'));
}

sub type {
	my $o = shift;
	my $actorSelector = shift; die 'wrong type '.ref($actorSelector).' for $actorSelector' if defined $actorSelector && ref $actorSelector ne 'CDS::Selector';

#line 128 "Condensation/CLI/Commands/ActorGroup.pm"
	my $groupData = $actorSelector->child('group data')->isSet;
	my $active = $actorSelector->child('active')->isSet;
	my $revoked = $actorSelector->child('revoked')->isSet;
	return
		$revoked ? 'revoked' :
		$active && $groupData ? 'active' :
		$groupData ? 'backup' :
		$active ? 'weird' :
			'idle';
}

sub coloredType7 {
	my $o = shift;
	my $actorSelector = shift; die 'wrong type '.ref($actorSelector).' for $actorSelector' if defined $actorSelector && ref $actorSelector ne 'CDS::Selector';

#line 140 "Condensation/CLI/Commands/ActorGroup.pm"
	my $groupData = $actorSelector->child('group data')->isSet;
	my $active = $actorSelector->child('active')->isSet;
	my $revoked = $actorSelector->child('revoked')->isSet;
	return
		$revoked ? $o->{ui}->red('revoked') :
		$active && $groupData ? $o->{ui}->green('active ') :
		$groupData ? $o->{ui}->blue('backup ') :
		$active ? $o->{ui}->orange('weird  ') :
			$o->{ui}->gray('idle   ');
}

sub joinMember {
	my $o = shift;
	my $cmd = shift;

#line 152 "Condensation/CLI/Commands/ActorGroup.pm"
	$o->{accountTokens} = [];
	$cmd->collect($o);

#line 155 "Condensation/CLI/Commands/ActorGroup.pm"
	my $selector = $o->{actor}->actorGroupSelector;
	for my $accountToken (@{$o->{accountTokens}}) {
		my $actorHash = $accountToken->actorHash;

#line 159 "Condensation/CLI/Commands/ActorGroup.pm"
		# Get the public key
		my ($publicKey, $invalidReason, $storeError) = $o->{actor}->keyPair->getPublicKey($actorHash, $accountToken->cliStore);
		if (defined $storeError) {
			$o->{ui}->pRed('Unable to get the public key of ', $actorHash->hex, ' from ', $accountToken->cliStore->url, ': ', $storeError);
			next;
		}

#line 166 "Condensation/CLI/Commands/ActorGroup.pm"
		if (defined $invalidReason) {
			$o->{ui}->pRed('Unable to get the public key of ', $actorHash->hex, ' from ', $accountToken->cliStore->url, ': ', $invalidReason);
			next;
		}

#line 171 "Condensation/CLI/Commands/ActorGroup.pm"
		# Add or update this member
		my $label = substr($actorHash->bytes, 0, 16);
		my $actorSelector = $selector->child($label);
		my $wasMember = $actorSelector->isSet;

#line 176 "Condensation/CLI/Commands/ActorGroup.pm"
		my $record = CDS::Record->new;
		$record->add('hash')->addHash($actorHash);
		$record->add('store')->addText($accountToken->cliStore->url);
		$actorSelector->set($record);
		$actorSelector->addObject($publicKey->hash, $publicKey->object);

#line 182 "Condensation/CLI/Commands/ActorGroup.pm"
		$o->{ui}->pGreen('Updated ', $o->type($actorSelector), ' member ', $actorHash->hex, '.') if $wasMember;
		$o->{ui}->pGreen('Added ', $actorHash->hex, ' as ', $o->type($actorSelector), ' member of the actor group.') if ! $wasMember;
	}

#line 186 "Condensation/CLI/Commands/ActorGroup.pm"
	# Save
	$o->{actor}->saveOrShowError;
}

sub setFlag {
	my $o = shift;
	my $actorSelector = shift; die 'wrong type '.ref($actorSelector).' for $actorSelector' if defined $actorSelector && ref $actorSelector ne 'CDS::Selector';
	my $label = shift;
	my $value = shift;

#line 191 "Condensation/CLI/Commands/ActorGroup.pm"
	my $child = $actorSelector->child($label);
	if ($value) {
		$child->setBoolean(1);
	} else {
		$child->clear;
	}
}

sub setMember {
	my $o = shift;
	my $cmd = shift;

#line 200 "Condensation/CLI/Commands/ActorGroup.pm"
	$o->{actorHashes} = [];
	$cmd->collect($o);

#line 203 "Condensation/CLI/Commands/ActorGroup.pm"
	my $selector = $o->{actor}->actorGroupSelector;
	for my $actorHash (@{$o->{actorHashes}}) {
		my $label = substr($actorHash->bytes, 0, 16);
		my $actorSelector = $selector->child($label);

#line 208 "Condensation/CLI/Commands/ActorGroup.pm"
		my $record = $actorSelector->record;
		my $hash = $record->child('hash')->hashValue;
		if (! $hash) {
			$o->{ui}->pRed($actorHash->hex, ' is not a member of our actor group.');
			next;
		}

#line 215 "Condensation/CLI/Commands/ActorGroup.pm"
		$o->setFlag($actorSelector, 'group data', $o->{status} eq 'active' || $o->{status} eq 'backup');
		$o->setFlag($actorSelector, 'active', $o->{status} eq 'active');
		$o->setFlag($actorSelector, 'revoked', $o->{status} eq 'revoked');
		$o->{ui}->pGreen($actorHash->hex, ' is now ', $o->type($actorSelector), '.');
	}

#line 221 "Condensation/CLI/Commands/ActorGroup.pm"
	# Save
	$o->{actor}->saveOrShowError;
}

# BEGIN AUTOGENERATED
package CDS::Commands::Announce;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/Announce.pm"
	my $node000 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node001 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&announceMe});
	my $node002 = CDS::Parser::Node->new(1);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(1);
	my $node014 = CDS::Parser::Node->new(0);
	my $node015 = CDS::Parser::Node->new(0);
	my $node016 = CDS::Parser::Node->new(0);
	my $node017 = CDS::Parser::Node->new(0, {constructor => \&new, function => \&announceKeyPair});
	$cds->addArrow($node001, 1, 0, 'announce');
	$cds->addArrow($node002, 1, 0, 'announce');
	$help->addArrow($node000, 1, 0, 'announce');
	$node002->addArrow($node003, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node003->addArrow($node004, 1, 0, 'on');
	$node004->addArrow($node005, 1, 0, 'STORE', \&collectStore);
	$node005->addArrow($node006, 1, 0, 'without');
	$node005->addArrow($node007, 1, 0, 'with');
	$node005->addDefault($node017);
	$node006->addArrow($node006, 1, 0, 'ACTOR', \&collectActor);
	$node006->addArrow($node017, 1, 0, 'ACTOR', \&collectActor);
	$node007->addArrow($node008, 1, 0, 'active', \&collectActive);
	$node007->addArrow($node008, 1, 0, 'entrusted', \&collectEntrusted);
	$node007->addArrow($node008, 1, 0, 'idle', \&collectIdle);
	$node007->addArrow($node008, 1, 0, 'revoked', \&collectRevoked);
	$node008->addDefault($node009);
	$node008->addDefault($node010);
	$node009->addArrow($node009, 1, 0, 'ACCOUNT', \&collectAccount);
	$node009->addArrow($node013, 1, 1, 'ACCOUNT', \&collectAccount);
	$node010->addArrow($node010, 1, 0, 'ACTOR', \&collectActor1);
	$node010->addArrow($node011, 1, 0, 'ACTOR', \&collectActor1);
	$node011->addArrow($node012, 1, 0, 'on');
	$node012->addArrow($node013, 1, 0, 'STORE', \&collectStore1);
	$node013->addArrow($node014, 1, 0, 'but');
	$node013->addArrow($node016, 1, 0, 'and');
	$node013->addDefault($node017);
	$node014->addArrow($node015, 1, 0, 'without');
	$node015->addArrow($node015, 1, 0, 'ACTOR', \&collectActor);
	$node015->addArrow($node017, 1, 0, 'ACTOR', \&collectActor);
	$node016->addDefault($node007);
}

sub collectAccount {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 55 "Condensation/CLI/Commands/Announce.pm"
	push @{$o->{with}}, {status => $o->{status}, accountToken => $value};
}

sub collectActive {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 59 "Condensation/CLI/Commands/Announce.pm"
	$o->{status} = 'active';
}

sub collectActor {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 63 "Condensation/CLI/Commands/Announce.pm"
	$o->{without}->{$value->bytes} = $value;
}

sub collectActor1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 67 "Condensation/CLI/Commands/Announce.pm"
	push @{$o->{actorHashes}}, $value;
}

sub collectEntrusted {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 71 "Condensation/CLI/Commands/Announce.pm"
	$o->{status} = 'entrusted';
}

sub collectIdle {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 75 "Condensation/CLI/Commands/Announce.pm"
	$o->{status} = 'idle';
}

sub collectKeypair {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 79 "Condensation/CLI/Commands/Announce.pm"
	$o->{keyPairToken} = $value;
}

sub collectRevoked {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 83 "Condensation/CLI/Commands/Announce.pm"
	$o->{status} = 'revoked';
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 87 "Condensation/CLI/Commands/Announce.pm"
	$o->{store} = $value;
}

sub collectStore1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 91 "Condensation/CLI/Commands/Announce.pm"
	for my $actorHash (@{$o->{actorHashes}}) {
	my $accountToken = CDS::AccountToken->new($value, $actorHash);
	push @{$o->{with}}, {status => $o->{status}, accountToken => $accountToken};
	}

#line 96 "Condensation/CLI/Commands/Announce.pm"
	$o->{actorHashes} = [];
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 101 "Condensation/CLI/Commands/Announce.pm"
# END AUTOGENERATED

#line 103 "Condensation/CLI/Commands/Announce.pm"
# HTML FOLDER NAME announce
# HTML TITLE Announce
sub help {
	my $o = shift;
	my $cmd = shift;

#line 106 "Condensation/CLI/Commands/Announce.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds announce');
	$ui->p('Announces yourself on your accounts.');
	$ui->space;
	$ui->command('cds announce KEYPAIR on STORE');
	$ui->command('… with (active|idle|revoked|entrusted) ACCOUNT*');
	$ui->command('… with (active|idle|revoked|entrusted) ACTOR* on STORE');
	$ui->command('… without ACTOR*');
	$ui->command('… with … and … and … but without …');
	$ui->p('Updates the public card of the indicated key pair on the indicated store. The indicated accounts are added or removed from the actor group on the card.');
	$ui->p('If no card exists, a minimalistic card is created.');
	$ui->p('Use this with care, as the generated card may not be compliant with the card produced by the actor.');
	$ui->space;
}

sub announceMe {
	my $o = shift;
	my $cmd = shift;

#line 123 "Condensation/CLI/Commands/Announce.pm"
	$o->announceOnStore($o->{actor}->storageStore);
	$o->announceOnStore($o->{actor}->messagingStore) if $o->{actor}->messagingStore->id ne $o->{actor}->storageStore->id;
	$o->{ui}->space;
}

sub announceOnStore {
	my $o = shift;
	my $store = shift;

#line 129 "Condensation/CLI/Commands/Announce.pm"
	$o->{ui}->space;
	$o->{ui}->title($store->url);
	my ($envelopeHash, $cardHash, $invalidReason, $storeError) = $o->{actor}->announce($store);
	return if defined $storeError;
	return $o->{ui}->pRed($invalidReason) if defined $invalidReason;
	$o->{ui}->pGreen('Announced');
}

sub announceKeyPair {
	my $o = shift;
	my $cmd = shift;

#line 138 "Condensation/CLI/Commands/Announce.pm"
	$o->{actors} = [];
	$o->{with} = [];
	$o->{without} = {};
	$o->{now} = CDS->now;
	$cmd->collect($o);

#line 144 "Condensation/CLI/Commands/Announce.pm"
	# List
	$o->{keyPair} = $o->{keyPairToken}->keyPair;
	my ($hashes, $listError) = $o->{store}->list($o->{keyPair}->publicKey->hash, 'public', 0, $o->{keyPair});
	return if defined $listError;

#line 149 "Condensation/CLI/Commands/Announce.pm"
	# Check if there are more than one cards
	if (scalar @$hashes > 1) {
		$o->{ui}->space;
		$o->{ui}->p('This account contains more than one public card:');
		$o->{ui}->pushIndent;
		for my $hash (@$hashes) {
			$o->{ui}->line($o->{ui}->gold('cds show card ', $hash->hex, ' on ', $o->{storeUrl}));
		}
		$o->{ui}->popIndent;
		$o->{ui}->p('Remove all but the most recent card. Cards can be removed as follows:');
		my $keyPairReference = $o->{actor}->blueKeyPairReference($o->{keyPairToken});
		$o->{ui}->line($o->{ui}->gold('cds remove ', 'HASH', ' on ', $o->{storeUrl}, ' using ', $keyPairReference));
		$o->{ui}->space;
		return;
	}

#line 165 "Condensation/CLI/Commands/Announce.pm"
	# Read the card
	my $cardRecord = scalar @$hashes ? $o->readCard($hashes->[0]) : CDS::Record->new;
	return if ! $cardRecord;

#line 169 "Condensation/CLI/Commands/Announce.pm"
	# Parse
	my $builder = CDS::ActorGroupBuilder->new;
	$builder->parse($cardRecord, 0);

#line 173 "Condensation/CLI/Commands/Announce.pm"
	# Apply the changes
	for my $change (@{$o->{with}}) {
		if ($change->{status} eq 'entrusted') {
			$builder->addEntrustedActor($change->{accountToken}->cliStore->url, $change->{accountToken}->actorHash);
			$builder->{entrustedActorsRevision} = $o->{now};
		} else {
			$builder->addMember($change->{accountToken}->cliStore->url, $change->{accountToken}->actorHash, $o->{now}, $change->{status});
		}
	}

#line 183 "Condensation/CLI/Commands/Announce.pm"
	for my $hash (values %{$o->{without}}) {
		$builder->removeEntrustedActor($hash)
	}

#line 187 "Condensation/CLI/Commands/Announce.pm"
	for my $member ($builder->members) {
		next if ! $o->{without}->{$member->hash->bytes};
		$builder->removeMember($member->storeUrl, $member->hash);
	}

#line 192 "Condensation/CLI/Commands/Announce.pm"
	# Write the new card
	my $newCard = $builder->toRecord(0);
	$newCard->add('public key')->addHash($o->{keyPair}->publicKey->hash);

#line 196 "Condensation/CLI/Commands/Announce.pm"
	for my $child ($cardRecord->children) {
		if ($child->bytes eq 'actor group') {
		} elsif ($child->bytes eq 'entrusted actors') {
		} elsif ($child->bytes eq 'public key') {
		} else {
			$newCard->addRecord($child);
		}
	}

#line 205 "Condensation/CLI/Commands/Announce.pm"
	$o->announce($newCard, $hashes);
}

sub readCard {
	my $o = shift;
	my $envelopeHash = shift; die 'wrong type '.ref($envelopeHash).' for $envelopeHash' if defined $envelopeHash && ref $envelopeHash ne 'CDS::Hash';

#line 209 "Condensation/CLI/Commands/Announce.pm"
	# Open the envelope
	my ($object, $storeError) = $o->{store}->get($envelopeHash, $o->{keyPair});
	return if defined $storeError;
	return $o->{ui}->error('Envelope object ', $envelopeHash->hex, ' not found.') if ! $object;

#line 214 "Condensation/CLI/Commands/Announce.pm"
	my $envelope = CDS::Record->fromObject($object) // return $o->{ui}->error($envelopeHash->hex, ' is not a record.');
	my $cardHash = $envelope->child('content')->hashValue // return $o->{ui}->error($envelopeHash->hex, ' is not a valid envelope, because it has no content hash.');
	return $o->{ui}->error($envelopeHash->hex, ' has an invalid signature.') if ! CDS->verifyEnvelopeSignature($envelope, $o->{keyPair}->publicKey, $cardHash);

#line 218 "Condensation/CLI/Commands/Announce.pm"
	# Read the card
	my ($cardObject, $storeError1) = $o->{store}->get($cardHash, $o->{keyPair});
	return if defined $storeError1;
	return $o->{ui}->error('Card object ', $cardHash->hex, ' not found.') if ! $cardObject;

#line 223 "Condensation/CLI/Commands/Announce.pm"
	return CDS::Record->fromObject($cardObject) // return $o->{ui}->error($cardHash->hex, ' is not a record.');
}

sub applyChanges {
	my $o = shift;
	my $actorGroup = shift; die 'wrong type '.ref($actorGroup).' for $actorGroup' if defined $actorGroup && ref $actorGroup ne 'CDS::ActorGroup';
	my $status = shift;
	my $accounts = shift;

#line 227 "Condensation/CLI/Commands/Announce.pm"
	for my $account (@$accounts) {
		$actorGroup->{$account->url} = {storeUrl => $account->cliStore->url, actorHash => $account->actorHash, revision => $o->{now}, status => $status};
	}
}

sub announce {
	my $o = shift;
	my $card = shift;
	my $sourceHashes = shift;

#line 233 "Condensation/CLI/Commands/Announce.pm"
	my $inMemoryStore = CDS::InMemoryStore->create;

#line 235 "Condensation/CLI/Commands/Announce.pm"
	# Serialize the card
	my $cardObject = $card->toObject;
	my $cardHash = $cardObject->calculateHash;
	$inMemoryStore->put($cardHash, $cardObject);
	$inMemoryStore->put($o->{keyPair}->publicKey->hash, $o->{keyPair}->publicKey->object);

#line 241 "Condensation/CLI/Commands/Announce.pm"
	# Prepare the public envelope
	my $envelopeObject = $o->{keyPair}->createPublicEnvelope($cardHash)->toObject;
	my $envelopeHash = $envelopeObject->calculateHash;
	$inMemoryStore->put($envelopeHash, $envelopeObject);

#line 246 "Condensation/CLI/Commands/Announce.pm"
	# Transfer
	my ($missingHash, $failedStore, $storeError) = $o->{keyPair}->transfer([$envelopeHash], $inMemoryStore, $o->{store});
	return if $storeError;
	return $o->{ui}->pRed('Object ', $missingHash, ' is missing.') if $missingHash;

#line 251 "Condensation/CLI/Commands/Announce.pm"
	# Modify
	my $modifications = CDS::StoreModifications->new;
	$modifications->add($o->{keyPair}->publicKey->hash, 'public', $envelopeHash);
	for my $hash (@$sourceHashes) {
		$modifications->remove($o->{keyPair}->publicKey->hash, 'public', $hash);
	}

#line 258 "Condensation/CLI/Commands/Announce.pm"
	my $modifyError = $o->{store}->modify($modifications, $o->{keyPair});
	return if $modifyError;

#line 261 "Condensation/CLI/Commands/Announce.pm"
	$o->{ui}->pGreen('Announced on ', $o->{store}->url, '.');
}

# BEGIN AUTOGENERATED
package CDS::Commands::Book;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/Book.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&book});
	$cds->addArrow($node000, 1, 0, 'book');
	$cds->addArrow($node001, 1, 0, 'book');
	$cds->addArrow($node002, 1, 0, 'book');
	$help->addArrow($node003, 1, 0, 'book');
	$node000->addArrow($node000, 1, 0, 'HASH', \&collectHash);
	$node000->addArrow($node004, 1, 0, 'HASH', \&collectHash);
	$node001->addArrow($node001, 1, 0, 'OBJECT', \&collectObject);
	$node001->addArrow($node006, 1, 0, 'OBJECT', \&collectObject);
	$node002->addArrow($node002, 1, 0, 'HASH', \&collectHash);
	$node002->addArrow($node006, 1, 0, 'HASH', \&collectHash);
	$node004->addArrow($node005, 1, 0, 'on');
	$node005->addArrow($node005, 1, 0, 'STORE', \&collectStore);
	$node005->addArrow($node006, 1, 0, 'STORE', \&collectStore);
}

sub collectHash {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 27 "Condensation/CLI/Commands/Book.pm"
	push @{$o->{hashes}}, $value;
}

sub collectObject {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 31 "Condensation/CLI/Commands/Book.pm"
	push @{$o->{objectTokens}}, $value;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 35 "Condensation/CLI/Commands/Book.pm"
	push @{$o->{stores}}, $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 40 "Condensation/CLI/Commands/Book.pm"
# END AUTOGENERATED

#line 42 "Condensation/CLI/Commands/Book.pm"
# HTML FOLDER NAME store-book
# HTML TITLE Book
sub help {
	my $o = shift;
	my $cmd = shift;

#line 45 "Condensation/CLI/Commands/Book.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds book OBJECT*');
	$ui->command('cds book HASH* on STORE*');
	$ui->p('Books all indicated objects and reports whether booking as successful.');
	$ui->space;
	$ui->command('cds book HASH*');
	$ui->p('As above, but uses the selected store.');
	$ui->space;
}

sub book {
	my $o = shift;
	my $cmd = shift;

#line 57 "Condensation/CLI/Commands/Book.pm"
	$o->{keyPair} = $o->{actor}->preferredKeyPairToken->keyPair;
	$o->{hashes} = [];
	$o->{stores} = [];
	$o->{objectTokens} = [];
	$cmd->collect($o);

#line 63 "Condensation/CLI/Commands/Book.pm"
	# Use the selected store
	push @{$o->{stores}}, $o->{actor}->preferredStore if ! scalar @{$o->{stores}};

#line 66 "Condensation/CLI/Commands/Book.pm"
	# Book all hashes on all stores
	my %triedStores;
	for my $store (@{$o->{stores}}) {
		next if $triedStores{$store->url};
		$triedStores{$store->url} = 1;
		for my $hash (@{$o->{hashes}}) {
			$o->process($store, $hash);
		}
	}

#line 76 "Condensation/CLI/Commands/Book.pm"
	# Book the direct object references
	for my $objectToken (@{$o->{objectTokens}}) {
		$o->process($objectToken->cliStore, $objectToken->hash);
	}

#line 81 "Condensation/CLI/Commands/Book.pm"
	# Warn the user if no key pair is selected
	return if ! $o->{hasErrors};
	return if $o->{keyPair};
	$o->{ui}->space;
	$o->{ui}->warning('Since no key pair is selected, the bookings were requested without signature. Stores are more likely to accept signed bookings. To add a signature, select a key pair using "cds use …", or create your key pair using "cds create my key pair".');
}

sub process {
	my $o = shift;
	my $store = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 89 "Condensation/CLI/Commands/Book.pm"
	# Upload the object
	my $success = $store->book($hash, $o->{keyPair});
	if ($success) {
		$o->{ui}->line($o->{ui}->green('OK          '), $hash->hex, ' on ', $store->url);
	} else {
		$o->{ui}->line($o->{ui}->red('not found   '), $hash->hex, ' on ', $store->url);
		$o->{hasErrors} = 1;
	}
}

# BEGIN AUTOGENERATED
package CDS::Commands::CheckKeyPair;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/CheckKeyPair.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node011 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&checkKeyPair});
	$cds->addArrow($node004, 1, 0, 'check');
	$cds->addArrow($node005, 1, 0, 'fix');
	$help->addArrow($node000, 1, 0, 'check');
	$help->addArrow($node001, 1, 0, 'fix');
	$node000->addArrow($node002, 1, 0, 'key');
	$node001->addArrow($node003, 1, 0, 'key');
	$node002->addArrow($node010, 1, 0, 'pair');
	$node003->addArrow($node010, 1, 0, 'pair');
	$node004->addArrow($node006, 1, 0, 'key');
	$node005->addArrow($node007, 1, 0, 'key');
	$node006->addArrow($node008, 1, 0, 'pair');
	$node007->addArrow($node009, 1, 0, 'pair');
	$node008->addArrow($node011, 1, 0, 'FILE', \&collectFile);
	$node009->addArrow($node011, 1, 0, 'FILE', \&collectFile1);
}

sub collectFile {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 33 "Condensation/CLI/Commands/CheckKeyPair.pm"
	$o->{file} = $value;
}

sub collectFile1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 37 "Condensation/CLI/Commands/CheckKeyPair.pm"
	$o->{file} = $value;
	$o->{fix} = 1;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 43 "Condensation/CLI/Commands/CheckKeyPair.pm"
# END AUTOGENERATED

#line 45 "Condensation/CLI/Commands/CheckKeyPair.pm"
# HTML FOLDER NAME check-key-pair
# HTML TITLE Check key pair
sub help {
	my $o = shift;
	my $cmd = shift;

#line 48 "Condensation/CLI/Commands/CheckKeyPair.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds check key pair FILE');
	$ui->p('Checks if the key pair FILE is complete, i.e. that a valid private key and a matching public key exists.');
	$ui->space;
}

sub checkKeyPair {
	my $o = shift;
	my $cmd = shift;

#line 56 "Condensation/CLI/Commands/CheckKeyPair.pm"
	$cmd->collect($o);

#line 58 "Condensation/CLI/Commands/CheckKeyPair.pm"
	# Check if we have a complete private key
	my $bytes = CDS->readBytesFromFile($o->{file}) // return $o->{ui}->error('The file "', $o->{file}, '" cannot be read.');
	my $record = CDS::Record->fromObject(CDS::Object->fromBytes($bytes));

#line 62 "Condensation/CLI/Commands/CheckKeyPair.pm"
	my $rsaKey = $record->child('rsa key');
	my $e = $rsaKey->child('e')->bytesValue;
	return $o->{ui}->error('The exponent "e" of the private key is missing.') if ! length $e;
	my $p = $rsaKey->child('p')->bytesValue;
	return $o->{ui}->error('The prime "p" of the private key is missing.') if ! length $p;
	my $q = $rsaKey->child('q')->bytesValue;
	return $o->{ui}->error('The prime "q" of the private key is missing.') if ! length $q;
	$o->{ui}->pGreen('The private key is complete.');

#line 71 "Condensation/CLI/Commands/CheckKeyPair.pm"
	# Derive the public key
	my $privateKey = CDS::C::privateKeyNew($e, $p, $q);
	my $publicKey = CDS::C::publicKeyFromPrivateKey($privateKey);
	my $n = CDS::C::publicKeyN($publicKey);

#line 76 "Condensation/CLI/Commands/CheckKeyPair.pm"
	# Check if we have a matching public key
	my $publicKeyObjectBytes = $record->child('public key object')->bytesValue;
	return $o->{ui}->error('The public key is missing.') if ! length $publicKeyObjectBytes;
	$o->{publicKeyObject} = CDS::Object->fromBytes($publicKeyObjectBytes) // return $o->{ui}->error('The public key is is not a valid Condensation object.');
	$o->{publicKeyHash} = $o->{publicKeyObject}->calculateHash;
	my $publicKeyRecord = CDS::Record->fromObject($o->{publicKeyObject});
	return $o->{ui}->error('The public key is not a valid record.') if ! $publicKeyRecord;
	my $publicN = $publicKeyRecord->child('n')->bytesValue;
	return $o->{ui}->error('The modulus "n" of the public key is missing.') if ! length $publicN;
	my $publicE = $publicKeyRecord->child('e')->bytesValue // $o->{ui}->error('The public key is incomplete.');
	return $o->{ui}->error('The exponent "e" of the public key is missing.') if ! length $publicE;
	return $o->{ui}->error('The exponent "e" of the public key does not match the exponent "e" of the private key.') if $publicE ne $e;
	return $o->{ui}->error('The modulus "n" of the public key does not correspond to the primes "p" and "q" of the private key.') if $publicN ne $n;
	$o->{ui}->pGreen('The public key ', $o->{publicKeyHash}->hex, ' is complete.');

#line 91 "Condensation/CLI/Commands/CheckKeyPair.pm"
	# At this point, the configuration looks good, and we can load the key pair
	CDS::KeyPair->fromRecord($record) // $o->{ui}->error('Your key pair looks complete, but could not be loaded.');
}

# BEGIN AUTOGENERATED
package CDS::Commands::CollectGarbage;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/CollectGarbage.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node004 = CDS::Parser::Node->new(0, {constructor => \&new, function => \&collectGarbage});
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0, {constructor => \&new, function => \&reportGarbage});
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&collectGarbage});
	my $node009 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&reportGarbage});
	$cds->addArrow($node001, 1, 0, 'report');
	$cds->addArrow($node002, 1, 0, 'collect');
	$help->addArrow($node000, 1, 0, 'collect');
	$node000->addArrow($node003, 1, 0, 'garbage');
	$node001->addArrow($node006, 1, 0, 'garbage');
	$node002->addArrow($node004, 1, 0, 'garbage');
	$node004->addArrow($node005, 1, 0, 'of');
	$node004->addDefault($node008);
	$node005->addArrow($node008, 1, 0, 'STORE', \&collectStore);
	$node006->addArrow($node007, 1, 0, 'of');
	$node006->addDefault($node009);
	$node007->addArrow($node009, 1, 0, 'STORE', \&collectStore);
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 29 "Condensation/CLI/Commands/CollectGarbage.pm"
	$o->{store} = $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 34 "Condensation/CLI/Commands/CollectGarbage.pm"
# END AUTOGENERATED

#line 39 "Condensation/CLI/Commands/CollectGarbage.pm"
# HTML FOLDER NAME collect-garbage
# HTML TITLE Garbage collection
sub help {
	my $o = shift;
	my $cmd = shift;

#line 42 "Condensation/CLI/Commands/CollectGarbage.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds collect garbage [of STORE]');
	$ui->p('Runs garbage collection. STORE must be a folder store. Objects not in use, and older than 1 day are removed from the store.');
	$ui->p('If no store is provided, garbage collection is run on the selected store, or the actor\'s storage store.');
	$ui->space;
	$ui->p('The store must not be written to while garbage collection is running. Objects booked during garbage collection may get deleted, and leave the store in a corrupt state. Reading from the store is fine.');
	$ui->space;
	$ui->command('cds report garbage [of STORE]');
	$ui->p('As above, but reports obsolete objects rather than deleting them. A protocol (shell script) is written to ".garbage" in the store folder.');
	$ui->space;
}

sub collectGarbage {
	my $o = shift;
	my $cmd = shift;

#line 56 "Condensation/CLI/Commands/CollectGarbage.pm"
	$cmd->collect($o);
	$o->run(CDS::Commands::CollectGarbage::Delete->new($o->{ui}));
}

sub wrapUpDeletion {
	my $o = shift;
	 }

sub reportGarbage {
	my $o = shift;
	my $cmd = shift;

#line 63 "Condensation/CLI/Commands/CollectGarbage.pm"
	$cmd->collect($o);
	$o->run(CDS::Commands::CollectGarbage::Report->new($o->{ui}));
	$o->{ui}->space;
}

#line 68 "Condensation/CLI/Commands/CollectGarbage.pm"
# Creates a folder with the selected permissions.
sub run {
	my $o = shift;
	my $handler = shift;

#line 70 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Prepare
	my $store = $o->{store} // $o->{actor}->selectedStore // $o->{actor}->storageStore;
	my $folderStore = CDS::FolderStore->forUrl($store->url) // return $o->{ui}->error('"', $store->url, '" is not a folder store.');
	$handler->initialize($folderStore) // return;

#line 75 "Condensation/CLI/Commands/CollectGarbage.pm"
	$o->{storeFolder} = $folderStore->folder;
	$o->{accountsFolder} = $folderStore->folder.'/accounts';
	$o->{objectsFolder} = $folderStore->folder.'/objects';
	my $dateLimit = time - 86400;
	my $envelopeExpirationLimit = time * 1000;

#line 81 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Read the tree index
	$o->readIndex;

#line 84 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Process all accounts
	$o->{ui}->space;
	$o->{ui}->title($o->{ui}->left(64, 'Accounts'), '   ', $o->{ui}->right(10, 'messages'), ' ', $o->{ui}->right(10, 'private'), ' ', $o->{ui}->right(10, 'public'), '   ', 'last modification');
	$o->startProgress('accounts');
	$o->{usedHashes} = {};
	$o->{missingObjects} = {};
	$o->{brokenOrigins} = {};
	my $countAccounts = 0;
	my $countKeptEnvelopes = 0;
	my $countDeletedEnvelopes = 0;
	for my $accountHash (sort { $$a cmp $$b } $folderStore->accounts) {
		# This would be the private key, but we don't use it right now
		$o->{usedHashes}->{$accountHash->hex} = 1;

#line 98 "Condensation/CLI/Commands/CollectGarbage.pm"
		my $newestDate = 0;
		my %sizeByBox;
		my $accountFolder = $o->{accountsFolder}.'/'.$accountHash->hex;
		foreach my $boxLabel (CDS->listFolder($accountFolder)) {
			next if $boxLabel =~ /^\./;
			my $boxFolder = $accountFolder.'/'.$boxLabel;
			my $date = &lastModified($boxFolder);
			$newestDate = $date if $newestDate < $date;
			my $size = 0;
			foreach my $filename (CDS->listFolder($boxFolder)) {
				next if $filename =~ /^\./;
				my $hash = pack('H*', $filename);
				my $file = $boxFolder.'/'.$filename;

#line 112 "Condensation/CLI/Commands/CollectGarbage.pm"
				my $timestamp = $o->envelopeExpiration($hash, $boxFolder);
				if ($timestamp > 0 && $timestamp < $envelopeExpirationLimit) {
					$countDeletedEnvelopes += 1;
					$handler->deleteEnvelope($file) // return;
					next;
				}

#line 119 "Condensation/CLI/Commands/CollectGarbage.pm"
				$countKeptEnvelopes += 1;
				my $date = &lastModified($file);
				$newestDate = $date if $newestDate < $date;
				$size += $o->traverse($hash, $boxFolder);
			}
			$sizeByBox{$boxLabel} = $size;
		}

#line 127 "Condensation/CLI/Commands/CollectGarbage.pm"
		$o->{ui}->line($accountHash->hex, '   ',
			$o->{ui}->right(10, $o->{ui}->niceFileSize($sizeByBox{'messages'} || 0)), ' ',
			$o->{ui}->right(10, $o->{ui}->niceFileSize($sizeByBox{'private'} || 0)), ' ',
			$o->{ui}->right(10, $o->{ui}->niceFileSize($sizeByBox{'public'} || 0)), '   ',
			$newestDate == 0 ? 'never' : $o->{ui}->niceDateTime($newestDate * 1000));

#line 133 "Condensation/CLI/Commands/CollectGarbage.pm"
		$countAccounts += 1;
	}

#line 136 "Condensation/CLI/Commands/CollectGarbage.pm"
	$o->{ui}->line($countAccounts, ' accounts traversed');
	$o->{ui}->space;

#line 139 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Mark all objects that are younger than 1 day (so that objects being uploaded right now but not linked yet remain)
	$o->{ui}->title('Objects');
	$o->startProgress('objects');

#line 143 "Condensation/CLI/Commands/CollectGarbage.pm"
	my %objects;
	my @topFolders = sort grep {$_ !~ /^\./} CDS->listFolder($o->{objectsFolder});
	foreach my $topFolder (@topFolders) {
		my @files = sort grep {$_ !~ /^\./} CDS->listFolder($o->{objectsFolder}.'/'.$topFolder);
		foreach my $filename (@files) {
			$o->incrementProgress;
			my $hash = pack 'H*', $topFolder.$filename;
			my @s = stat $o->{objectsFolder}.'/'.$topFolder.'/'.$filename;
			$objects{$hash} = $s[7];
			next if $s[9] < $dateLimit;
			$o->traverse($hash, 'recent object');
		}
	}

#line 157 "Condensation/CLI/Commands/CollectGarbage.pm"
	$o->{ui}->line(scalar keys %objects, ' objects traversed');
	$o->{ui}->space;

#line 160 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Delete all unmarked objects, and add the marked objects to the new tree index
	my $index = CDS::Record->new;
	my $countKeptObjects = 0;
	my $sizeKeptObjects = 0;
	my $countDeletedObjects = 0;
	my $sizeDeletedObjects = 0;

#line 167 "Condensation/CLI/Commands/CollectGarbage.pm"
	$handler->startDeletion;
	$o->startProgress('delete-objects');
	for my $hash (keys %objects) {
		my $size = $objects{$hash};
		if (exists $o->{usedHashes}->{$hash}) {
			$countKeptObjects += 1;
			$sizeKeptObjects += $size;
			my $entry = $o->{index}->{$hash};
			$index->addRecord($entry) if $entry;
		} else {
			$o->incrementProgress;
			$countDeletedObjects += 1;
			$sizeDeletedObjects += $size;
			my $hashHex = unpack 'H*', $hash;
			my $file = $o->{objectsFolder}.'/'.substr($hashHex, 0, 2).'/'.substr($hashHex, 2);
			$handler->deleteObject($file) // return;
		}
	}

#line 186 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Write the new tree index
	CDS->writeBytesToFile($o->{storeFolder}.'/.index-new', $index->toObject->bytes);
	rename $o->{storeFolder}.'/.index-new', $o->{storeFolder}.'/.index';

#line 190 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Show what has been done
	$o->{ui}->space;
	$o->{ui}->line($countDeletedEnvelopes, ' ', $handler->{deletedEnvelopesText});
	$o->{ui}->line($countKeptEnvelopes, ' ', $handler->{keptEnvelopesText});
	my $line1 = $countDeletedObjects.' '.$handler->{deletedObjectsText};
	my $line2 = $countKeptObjects.' '.$handler->{keptObjectsText};
	my $maxLength = CDS->max(length $line1, length $line2);
	$o->{ui}->line($o->{ui}->left($maxLength, $line1), '  ', $o->{ui}->gray($o->{ui}->niceFileSize($sizeDeletedObjects)));
	$o->{ui}->line($o->{ui}->left($maxLength, $line2), '  ', $o->{ui}->gray($o->{ui}->niceFileSize($sizeKeptObjects)));
	$o->{ui}->space;
	$handler->wrapUp;

#line 202 "Condensation/CLI/Commands/CollectGarbage.pm"
	my $missing = scalar keys %{$o->{missingObjects}};
	if ($missing) {
		$o->{ui}->warning($missing, ' objects are referenced from other objects, but missing:');

#line 206 "Condensation/CLI/Commands/CollectGarbage.pm"
		my $count = 0;
		for my $hashBytes (sort keys %{$o->{missingObjects}}) {
			$o->{ui}->warning('  ', unpack('H*', $hashBytes));

#line 210 "Condensation/CLI/Commands/CollectGarbage.pm"
			$count += 1;
			if ($missing > 10 && $count > 5) {
				$o->{ui}->warning('  …');
				last;
			}
		}

#line 217 "Condensation/CLI/Commands/CollectGarbage.pm"
		$o->{ui}->space;
		$o->{ui}->warning('The missing objects are from the following origins:');
		for my $origin (sort keys %{$o->{brokenOrigins}}) {
			$o->{ui}->line('  ', $o->{ui}->orange($origin));
		}

#line 223 "Condensation/CLI/Commands/CollectGarbage.pm"
		$o->{ui}->space;
	}
}

sub traverse {
	my $o = shift;
	my $hashBytes = shift;
	my $origin = shift;

#line 228 "Condensation/CLI/Commands/CollectGarbage.pm"
	return $o->{usedHashes}->{$hashBytes} if exists $o->{usedHashes}->{$hashBytes};

#line 230 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Get index information about the object
	my $record = $o->index($hashBytes, $origin) // return 0;
	my $size = $record->nthChild(0)->asInteger;

#line 234 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Process children
	my $pos = 0;
	my $hashes = $record->nthChild(1)->bytes;
	while ($pos < length $hashes) {
		$size += $o->traverse(substr($hashes, $pos, 32), $origin);
		$pos += 32;
	}

#line 242 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Keep the size for future use
	$o->{usedHashes}->{$hashBytes} = $size;
	return $size;
}

sub readIndex {
	my $o = shift;

#line 248 "Condensation/CLI/Commands/CollectGarbage.pm"
	$o->{index} = {};
	my $file = $o->{storeFolder}.'/.index';
	my $record = CDS::Record->fromObject(CDS::Object->fromBytes(CDS->readBytesFromFile($file))) // return;
	for my $child ($record->children) {
		$o->{index}->{$child->bytes} = $child;
	}
}

sub index {
	my $o = shift;
	my $hashBytes = shift;
	my $origin = shift;

#line 257 "Condensation/CLI/Commands/CollectGarbage.pm"
	$o->incrementProgress;

#line 259 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Report a known result
	if ($o->{missingObjects}->{$hashBytes}) {
		$o->{brokenOrigins}->{$origin} = 1;
		return;
	}

#line 265 "Condensation/CLI/Commands/CollectGarbage.pm"
	return $o->{index}->{$hashBytes} if exists $o->{index}->{$hashBytes};

#line 267 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Object file
	my $hashHex = unpack 'H*', $hashBytes;
	my $file = $o->{objectsFolder}.'/'.substr($hashHex, 0, 2).'/'.substr($hashHex, 2);

#line 271 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Size and existence
	my @s = stat $file;
	if (! scalar @s) {
		$o->{missingObjects}->{$hashBytes} = 1;
		$o->{brokenOrigins}->{$origin} = 1;
		return;
	}
	my $size = $s[7];
	return $o->{ui}->error('Unexpected: object ', $hashHex, ' has ', $size, ' bytes') if $size < 4;

#line 281 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Read header
	open O, '<', $file;
	read O, my $buffer, 4;
	my $links = unpack 'L>', $buffer;
	return $o->{ui}->error('Unexpected: object ', $hashHex, ' has ', $links, ' references') if $links > 160000;
	return $o->{ui}->error('Unexpected: object ', $hashHex, ' is too small for ', $links, ' references') if 4 + $links * 32 > $s[7];
	my $hashes = '';
	read O, $hashes, $links * 32 if $links > 0;
	close O;

#line 291 "Condensation/CLI/Commands/CollectGarbage.pm"
	return $o->{ui}->error('Incomplete read: ', length $hashes, ' out of ', $links * 32, ' bytes received.') if length $hashes != $links * 32;

#line 293 "Condensation/CLI/Commands/CollectGarbage.pm"
	my $record = CDS::Record->new($hashBytes);
	$record->addInteger($size);
	$record->add($hashes);
	return $o->{index}->{$hashBytes} = $record;
}

sub envelopeExpiration {
	my $o = shift;
	my $hashBytes = shift;
	my $origin = shift;

#line 300 "Condensation/CLI/Commands/CollectGarbage.pm"
	my $entry = $o->index($hashBytes, $origin) // return 0;
	return $entry->nthChild(2)->asInteger if scalar $entry->children > 2;

#line 303 "Condensation/CLI/Commands/CollectGarbage.pm"
	# Object file
	my $hashHex = unpack 'H*', $hashBytes;
	my $file = $o->{objectsFolder}.'/'.substr($hashHex, 0, 2).'/'.substr($hashHex, 2);
	my $record = CDS::Record->fromObject(CDS::Object->fromBytes(CDS->readBytesFromFile($file)));
	my $expires = $record->child('expires')->integerValue;
	$entry->addInteger($expires);
	return $expires;
}

sub startProgress {
	my $o = shift;
	my $title = shift;

#line 313 "Condensation/CLI/Commands/CollectGarbage.pm"
	$o->{progress} = 0;
	$o->{progressTitle} = $title;
	$o->{ui}->progress($o->{progress}, ' ', $o->{progressTitle});
}

sub incrementProgress {
	my $o = shift;

#line 319 "Condensation/CLI/Commands/CollectGarbage.pm"
	$o->{progress} += 1;
	return if $o->{progress} % 100;
	$o->{ui}->progress($o->{progress}, ' ', $o->{progressTitle});
}

sub lastModified {
	my $file = shift;

#line 325 "Condensation/CLI/Commands/CollectGarbage.pm"
	my @s = stat $file;
	return scalar @s ? $s[9] : 0;
}

package CDS::Commands::CollectGarbage::Delete;

sub new {
	my $class = shift;
	my $ui = shift;

#line 2 "Condensation/CLI/Commands/CollectGarbage/Delete.pm"
	return bless {
		ui => $ui,
		deletedEnvelopesText => 'expired envelopes deleted',
		keptEnvelopesText => 'envelopes kept',
		deletedObjectsText => 'objects deleted',
		keptObjectsText => 'objects kept',
		};
}

sub initialize {
	my $o = shift;
	my $folder = shift;
	 1 }

sub startDeletion {
	my $o = shift;

#line 14 "Condensation/CLI/Commands/CollectGarbage/Delete.pm"
	$o->{ui}->title('Deleting obsolete objects');
}

sub deleteEnvelope {
	my $o = shift;
	my $file = shift;
	 $o->deleteObject($file) }

sub deleteObject {
	my $o = shift;
	my $file = shift;

#line 20 "Condensation/CLI/Commands/CollectGarbage/Delete.pm"
	unlink $file // return $o->{ui}->error('Unable to delete "', $file, '". Giving up …');
	return 1;
}

sub wrapUp {
	my $o = shift;
	 }

package CDS::Commands::CollectGarbage::Report;

sub new {
	my $class = shift;
	my $ui = shift;

#line 2 "Condensation/CLI/Commands/CollectGarbage/Report.pm"
	return bless {
		ui => $ui,
		countReported => 0,
		deletedEnvelopesText => 'envelopes have expired',
		keptEnvelopesText => 'envelopes are in use',
		deletedObjectsText => 'objects can be deleted',
		keptObjectsText => 'objects are in use',
		};
}

sub initialize {
	my $o = shift;
	my $folderStore = shift;

#line 13 "Condensation/CLI/Commands/CollectGarbage/Report.pm"
	$o->{file} = $folderStore->folder.'/.garbage';
	open($o->{fh}, '>', $o->{file}) || return $o->{ui}->error('Failed to open ', $o->{file}, ' for writing.');
	return 1;
}

sub startDeletion {
	my $o = shift;

#line 19 "Condensation/CLI/Commands/CollectGarbage/Report.pm"
	$o->{ui}->title('Deleting obsolete objects');
}

sub deleteEnvelope {
	my $o = shift;
	my $file = shift;
	 $o->deleteObject($file) }

sub deleteObject {
	my $o = shift;
	my $file = shift;

#line 25 "Condensation/CLI/Commands/CollectGarbage/Report.pm"
	my $fh = $o->{fh};
	print $fh 'rm ', $file, "\n";
	$o->{countReported} += 1;
	print $fh 'echo ', $o->{countReported}, ' files deleted', "\n" if $o->{countReported} % 100 == 0;
	return 1;
}

sub wrapUp {
	my $o = shift;

#line 33 "Condensation/CLI/Commands/CollectGarbage/Report.pm"
	close $o->{fh};
	if ($o->{countReported} == 0) {
		unlink $o->{file};
	} else {
		$o->{ui}->space;
		$o->{ui}->p('The report was written to ', $o->{file}, '.');
		$o->{ui}->space;
	}
}

# BEGIN AUTOGENERATED
package CDS::Commands::CreateKeyPair;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/CreateKeyPair.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node006 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&createKeyPair});
	$cds->addArrow($node002, 1, 0, 'create');
	$help->addArrow($node000, 1, 0, 'create');
	$node000->addArrow($node001, 1, 0, 'key');
	$node001->addArrow($node005, 1, 0, 'pair');
	$node002->addArrow($node003, 1, 0, 'key');
	$node003->addArrow($node004, 1, 0, 'pair');
	$node004->addArrow($node006, 1, 0, 'FILENAME', \&collectFilename);
}

sub collectFilename {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 21 "Condensation/CLI/Commands/CreateKeyPair.pm"
	$o->{filename} = $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 26 "Condensation/CLI/Commands/CreateKeyPair.pm"
# END AUTOGENERATED

#line 28 "Condensation/CLI/Commands/CreateKeyPair.pm"
# HTML FOLDER NAME create-key-pair
# HTML TITLE Create key pair
sub help {
	my $o = shift;
	my $cmd = shift;

#line 31 "Condensation/CLI/Commands/CreateKeyPair.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds create key pair FILENAME');
	$ui->p('Generates a key pair, and writes it to FILENAME.');
	$ui->space;
	$ui->title('Related commands');
	$ui->line('  cds select …');
	$ui->line('  cds use …');
	$ui->line('  cds entrust …');
	$ui->line('  cds drop …');
	$ui->space;
}

sub createKeyPair {
	my $o = shift;
	my $cmd = shift;

#line 45 "Condensation/CLI/Commands/CreateKeyPair.pm"
	$cmd->collect($o);
	return $o->{ui}->error('The file "', $o->{filename}, '" exists.') if -e $o->{filename};
	my $keyPair = CDS::KeyPair->generate;
	$keyPair->writeToFile($o->{filename}) // return $o->{ui}->error('Failed to write the key pair file "', $o->{filename}, '".');
	$o->{ui}->pGreen('Key pair "', $o->{filename}, '" created.');
}

# BEGIN AUTOGENERATED
package CDS::Commands::Curl;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/Curl.pm"
	my $node000 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node001 = CDS::Parser::Node->new(1);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlGet});
	my $node014 = CDS::Parser::Node->new(0);
	my $node015 = CDS::Parser::Node->new(0);
	my $node016 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlPut});
	my $node017 = CDS::Parser::Node->new(0);
	my $node018 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlBook});
	my $node019 = CDS::Parser::Node->new(0);
	my $node020 = CDS::Parser::Node->new(0);
	my $node021 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlList});
	my $node022 = CDS::Parser::Node->new(0);
	my $node023 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlGet});
	my $node024 = CDS::Parser::Node->new(0);
	my $node025 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlPut});
	my $node026 = CDS::Parser::Node->new(0);
	my $node027 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlBook});
	my $node028 = CDS::Parser::Node->new(0);
	my $node029 = CDS::Parser::Node->new(1);
	my $node030 = CDS::Parser::Node->new(0);
	my $node031 = CDS::Parser::Node->new(0);
	my $node032 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlList});
	my $node033 = CDS::Parser::Node->new(0);
	my $node034 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlGet});
	my $node035 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlPut});
	my $node036 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlBook});
	my $node037 = CDS::Parser::Node->new(1);
	my $node038 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlList});
	my $node039 = CDS::Parser::Node->new(0);
	my $node040 = CDS::Parser::Node->new(0);
	my $node041 = CDS::Parser::Node->new(0);
	my $node042 = CDS::Parser::Node->new(0);
	my $node043 = CDS::Parser::Node->new(0);
	my $node044 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlList});
	my $node045 = CDS::Parser::Node->new(1);
	my $node046 = CDS::Parser::Node->new(0);
	my $node047 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlModify});
	my $node048 = CDS::Parser::Node->new(0);
	my $node049 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlModify});
	my $node050 = CDS::Parser::Node->new(0);
	my $node051 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&curlModify});
	$cds->addArrow($node001, 1, 0, 'curl');
	$help->addArrow($node000, 1, 0, 'curl');
	$node001->addArrow($node002, 1, 0, 'get');
	$node001->addArrow($node003, 1, 0, 'put');
	$node001->addArrow($node004, 1, 0, 'book');
	$node001->addArrow($node005, 1, 0, 'get');
	$node001->addArrow($node006, 1, 0, 'book');
	$node001->addArrow($node007, 1, 0, 'list');
	$node001->addArrow($node007, 1, 0, 'watch', \&collectWatch);
	$node001->addDefault($node011);
	$node002->addArrow($node013, 1, 0, 'HASH', \&collectHash);
	$node003->addArrow($node016, 1, 0, 'FILE', \&collectFile);
	$node004->addArrow($node018, 1, 0, 'HASH', \&collectHash);
	$node005->addArrow($node023, 1, 0, 'OBJECT', \&collectObject);
	$node006->addArrow($node027, 1, 0, 'OBJECT', \&collectObject);
	$node007->addArrow($node008, 1, 0, 'message');
	$node007->addArrow($node009, 1, 0, 'private');
	$node007->addArrow($node010, 1, 0, 'public');
	$node007->addArrow($node021, 0, 0, 'messages', \&collectMessages);
	$node007->addArrow($node021, 0, 0, 'private', \&collectPrivate);
	$node007->addArrow($node021, 0, 0, 'public', \&collectPublic);
	$node008->addArrow($node021, 1, 0, 'box', \&collectMessages);
	$node009->addArrow($node021, 1, 0, 'box', \&collectPrivate);
	$node010->addArrow($node021, 1, 0, 'box', \&collectPublic);
	$node011->addArrow($node012, 1, 0, 'remove');
	$node011->addArrow($node020, 1, 0, 'add');
	$node012->addArrow($node012, 1, 0, 'HASH', \&collectHash1);
	$node012->addArrow($node037, 1, 0, 'HASH', \&collectHash1);
	$node013->addArrow($node014, 1, 0, 'from');
	$node013->addArrow($node015, 0, 0, 'on');
	$node013->addDefault($node023);
	$node014->addArrow($node023, 1, 0, 'STORE', \&collectStore);
	$node015->addArrow($node023, 0, 0, 'STORE', \&collectStore);
	$node016->addArrow($node017, 1, 0, 'onto');
	$node016->addDefault($node025);
	$node017->addArrow($node025, 1, 0, 'STORE', \&collectStore);
	$node018->addArrow($node019, 1, 0, 'on');
	$node018->addDefault($node027);
	$node019->addArrow($node027, 1, 0, 'STORE', \&collectStore);
	$node020->addArrow($node029, 1, 0, 'FILE', \&collectFile1);
	$node020->addArrow($node029, 1, 0, 'HASH', \&collectHash2);
	$node021->addArrow($node022, 1, 0, 'of');
	$node022->addArrow($node032, 1, 0, 'ACTOR', \&collectActor);
	$node023->addArrow($node024, 1, 0, 'using');
	$node024->addArrow($node034, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node025->addArrow($node026, 1, 0, 'using');
	$node026->addArrow($node035, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node027->addArrow($node028, 1, 0, 'using');
	$node028->addArrow($node036, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node029->addDefault($node020);
	$node029->addArrow($node030, 1, 0, 'and');
	$node029->addArrow($node040, 1, 0, 'to');
	$node030->addArrow($node031, 1, 0, 'remove');
	$node031->addArrow($node031, 1, 0, 'HASH', \&collectHash1);
	$node031->addArrow($node037, 1, 0, 'HASH', \&collectHash1);
	$node032->addArrow($node033, 1, 0, 'on');
	$node033->addArrow($node038, 1, 0, 'STORE', \&collectStore);
	$node037->addArrow($node040, 1, 0, 'from');
	$node038->addArrow($node039, 1, 0, 'using');
	$node039->addArrow($node044, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node040->addArrow($node041, 1, 0, 'message');
	$node040->addArrow($node042, 1, 0, 'private');
	$node040->addArrow($node043, 1, 0, 'public');
	$node040->addArrow($node045, 0, 0, 'messages', \&collectMessages1);
	$node040->addArrow($node045, 0, 0, 'private', \&collectPrivate1);
	$node040->addArrow($node045, 0, 0, 'public', \&collectPublic1);
	$node041->addArrow($node045, 1, 0, 'box', \&collectMessages1);
	$node042->addArrow($node045, 1, 0, 'box', \&collectPrivate1);
	$node043->addArrow($node045, 1, 0, 'box', \&collectPublic1);
	$node045->addArrow($node046, 1, 0, 'of');
	$node045->addDefault($node047);
	$node046->addArrow($node047, 1, 0, 'ACTOR', \&collectActor1);
	$node047->addArrow($node011, 1, 0, 'and', \&collectAnd);
	$node047->addArrow($node048, 1, 0, 'on');
	$node048->addArrow($node049, 1, 0, 'STORE', \&collectStore);
	$node049->addArrow($node050, 1, 0, 'using');
	$node050->addArrow($node051, 1, 0, 'KEYPAIR', \&collectKeypair);
}

sub collectActor {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 136 "Condensation/CLI/Commands/Curl.pm"
	$o->{actorHash} = $value;
}

sub collectActor1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 140 "Condensation/CLI/Commands/Curl.pm"
	$o->{currentBatch}->{actorHash} = $value;
}

sub collectAnd {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 144 "Condensation/CLI/Commands/Curl.pm"
	push @{$o->{batches}}, $o->{currentBatch};
	$o->{currentBatch} = {
	addHashes => [],
	addEnvelopes => [],
	removeHashes => []
	};
}

sub collectFile {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 153 "Condensation/CLI/Commands/Curl.pm"
	$o->{file} = $value;
}

sub collectFile1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 157 "Condensation/CLI/Commands/Curl.pm"
	push @{$o->{currentBatch}->{addFiles}}, $value;
}

sub collectHash {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 161 "Condensation/CLI/Commands/Curl.pm"
	$o->{hash} = $value;
}

sub collectHash1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 165 "Condensation/CLI/Commands/Curl.pm"
	push @{$o->{currentBatch}->{removeHashes}}, $value;
}

sub collectHash2 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 169 "Condensation/CLI/Commands/Curl.pm"
	push @{$o->{currentBatch}->{addHashes}}, $value;
}

sub collectKeypair {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 173 "Condensation/CLI/Commands/Curl.pm"
	$o->{keyPairToken} = $value;
}

sub collectMessages {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 177 "Condensation/CLI/Commands/Curl.pm"
	$o->{boxLabel} = 'messages';
}

sub collectMessages1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 181 "Condensation/CLI/Commands/Curl.pm"
	$o->{currentBatch}->{boxLabel} = 'messages';
}

sub collectObject {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 185 "Condensation/CLI/Commands/Curl.pm"
	$o->{hash} = $value->hash;
	$o->{store} = $value->cliStore;
}

sub collectPrivate {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 190 "Condensation/CLI/Commands/Curl.pm"
	$o->{boxLabel} = 'private';
}

sub collectPrivate1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 194 "Condensation/CLI/Commands/Curl.pm"
	$o->{currentBatch}->{boxLabel} = 'private';
}

sub collectPublic {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 198 "Condensation/CLI/Commands/Curl.pm"
	$o->{boxLabel} = 'public';
}

sub collectPublic1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 202 "Condensation/CLI/Commands/Curl.pm"
	$o->{currentBatch}->{boxLabel} = 'public';
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 206 "Condensation/CLI/Commands/Curl.pm"
	$o->{store} = $value;
}

sub collectWatch {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 210 "Condensation/CLI/Commands/Curl.pm"
	$o->{watchTimeout} = 60000;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 215 "Condensation/CLI/Commands/Curl.pm"
# END AUTOGENERATED

#line 217 "Condensation/CLI/Commands/Curl.pm"
# HTML FOLDER NAME curl
# HTML TITLE Curl
sub help {
	my $o = shift;
	my $cmd = shift;

#line 220 "Condensation/CLI/Commands/Curl.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->p($ui->blue('cds curl'), ' prepares and executes a CURL command line for a HTTP store request. This is helpful for debugging a HTTP store implementation. Outside of low-level debugging, it is more convenient to use the "cds get|put|list|add|remove …" commands, which are richer in functionality, and work on all stores.');
	$ui->space;
	$ui->command('cds curl get OBJECT');
	$ui->command('cds curl get HASH [from|on STORE]');
	$ui->p('Downloads an object with a GET request on an object store.');
	$ui->space;
	$ui->command('cds curl put FILE [onto STORE]');
	$ui->p('Uploads an object with a PUT request on an object store.');
	$ui->space;
	$ui->command('cds curl book OBJECT');
	$ui->command('cds curl book HASH [on STORE]');
	$ui->p('Books an object with a POST request on an object store.');
	$ui->space;
	$ui->command('cds curl list message box of ACTOR [on STORE]');
	$ui->command('cds curl list private box of ACTOR [on STORE]');
	$ui->command('cds curl list public box of ACTOR [on STORE]');
	$ui->p('Lists the indicated box with a GET request on an account store.');
	$ui->space;
	$ui->command('cds curl watch message box of ACTOR [on STORE]');
	$ui->command('cds curl watch private box of ACTOR [on STORE]');
	$ui->command('cds curl watch public box of ACTOR [on STORE]');
	$ui->p('As above, but with a watch timeout of 60 second.');
	$ui->space;
	$ui->command('cds curl add (FILE|HASH)* to (message|private|public) box of ACTOR [and …] [on STORE]');
	$ui->command('cds curl remove HASH* from (message|private|public) box of ACTOR [and …] [on STORE]');
	$ui->p('Modifies the indicated boxes with a POST request on an account store. Multiple modifications to different boxes may be chained using "and". All modifications are submitted using a single request, which is optionally signed (see below).');
	$ui->space;
	$ui->command('… using KEYPAIR');
	$ui->p('Signs the request using KEYPAIR instead of the actor\'s key pair. The store may or may not verify the signature.');
	$ui->p('For debugging purposes, information about the signature is stored as ".cds-curl-bytes-to-sign", ".cds-curl-hash-to-sign", and ".cds-curl-signature" in the current folder. Note that signatures are valid for 1-2 minutes only. After that, servers will reject them to guard against replay attacks.');
	$ui->space;
}

sub curlGet {
	my $o = shift;
	my $cmd = shift;

#line 256 "Condensation/CLI/Commands/Curl.pm"
	$cmd->collect($o);
	$o->{keyPairToken} = $o->{actor}->preferredKeyPairToken if ! $o->{keyPairToken};
	$o->{store} = $o->{actor}->preferredStore if ! $o->{store};

#line 260 "Condensation/CLI/Commands/Curl.pm"
	my $objectToken = CDS::ObjectToken->new($o->{store}, $o->{hash});
	$o->curlRequest('GET', $objectToken->url, ['--output', $o->{hash}->hex]);
}

sub curlPut {
	my $o = shift;
	my $cmd = shift;

#line 265 "Condensation/CLI/Commands/Curl.pm"
	$cmd->collect($o);
	$o->{keyPairToken} = $o->{actor}->preferredKeyPairToken if ! $o->{keyPairToken};
	$o->{store} = $o->{actor}->preferredStore if ! $o->{store};

#line 269 "Condensation/CLI/Commands/Curl.pm"
	my $bytes = CDS->readBytesFromFile($o->{file}) // return $o->{ui}->error('Unable to read "', $o->{file}, '".');
	my $hash = CDS::Hash->calculateFor($bytes);
	my $objectToken = CDS::ObjectToken->new($o->{store}, $hash);
	$o->curlRequest('PUT', $objectToken->url, ['--data-binary', '@'.$o->{file}, '-H', 'Content-Type: application/condensation-object']);
}

sub curlBook {
	my $o = shift;
	my $cmd = shift;

#line 276 "Condensation/CLI/Commands/Curl.pm"
	$cmd->collect($o);
	$o->{keyPairToken} = $o->{actor}->preferredKeyPairToken if ! $o->{keyPairToken};
	$o->{store} = $o->{actor}->preferredStore if ! $o->{store};

#line 280 "Condensation/CLI/Commands/Curl.pm"
	my $objectToken = CDS::ObjectToken->new($o->{store}, $o->{hash});
	$o->curlRequest('POST', $objectToken->url, []);
}

sub curlList {
	my $o = shift;
	my $cmd = shift;

#line 285 "Condensation/CLI/Commands/Curl.pm"
	$cmd->collect($o);
	$o->{keyPairToken} = $o->{actor}->preferredKeyPairToken if ! $o->{keyPairToken};
	$o->{store} = $o->{actor}->preferredStore if ! $o->{store};
	$o->{actorHash} = $o->{actor}->preferredActorHash if ! $o->{actorHash};

#line 290 "Condensation/CLI/Commands/Curl.pm"
	my $boxToken = CDS::BoxToken->new(CDS::AccountToken->new($o->{store}, $o->{actorHash}), $o->{boxLabel});
	my $args = ['--output', '.cds-curl-list'];
	push @$args, '-H', 'Condensation-Watch: '.$o->{watchTimeout}.' ms' if $o->{watchTimeout};
	$o->curlRequest('GET', $boxToken->url, $args);
}

sub curlModify {
	my $o = shift;
	my $cmd = shift;

#line 297 "Condensation/CLI/Commands/Curl.pm"
	$o->{currentBatch} = {
		addHashes => [],
		addEnvelopes => [],
		removeHashes => [],
		};
	$o->{batches} = [];
	$cmd->collect($o);
	$o->{keyPairToken} = $o->{actor}->preferredKeyPairToken if ! $o->{keyPairToken};
	$o->{store} = $o->{actor}->preferredStore if ! $o->{store};

#line 307 "Condensation/CLI/Commands/Curl.pm"
	# Prepare the modifications
	my $modifications = CDS::StoreModifications->new;

#line 310 "Condensation/CLI/Commands/Curl.pm"
	for my $batch (@{$o->{batches}}, $o->{currentBatch}) {
		$batch->{actorHash} = $o->{actor}->preferredActorHash if ! $batch->{actorHash};

#line 313 "Condensation/CLI/Commands/Curl.pm"
		for my $hash (@{$batch->{addHashes}}) {
			$modifications->add($batch->{actorHash}, $batch->{boxLabel}, $hash);
		}

#line 317 "Condensation/CLI/Commands/Curl.pm"
		for my $file (@{$batch->{addFiles}}) {
			my $bytes = CDS->readBytesFromFile($file) // return $o->{ui}->error('Unable to read "', $file, '".');
			my $object = CDS::Object->fromBytes($bytes) // return $o->{ui}->error('"', $file, '" is not a Condensation object.');
			my $hash = $object->calculateHash;
			$o->{ui}->warning('"', $file, '" is not a valid envelope. The server may reject it.') if ! $o->{actor}->isEnvelope($object);
			$modifications->add($batch->{actorHash}, $batch->{boxLabel}, $hash, $object);
		}

#line 325 "Condensation/CLI/Commands/Curl.pm"
		for my $hash (@{$batch->{removeHashes}}) {
			$modifications->remove($batch->{actorHash}, $batch->{boxLabel}, $hash);
		}
	}

#line 330 "Condensation/CLI/Commands/Curl.pm"
	$o->{ui}->warning('You didn\'t specify any changes. The server should accept, but ignore this.') if $modifications->isEmpty;

#line 332 "Condensation/CLI/Commands/Curl.pm"
	# Write a new file
	my $modificationsObject = $modifications->toRecord->toObject;
	my $modificationsHash = $modificationsObject->calculateHash;
	my $file = '.cds-curl-modifications-'.substr($modificationsHash->hex, 0, 8);
	CDS->writeBytesToFile($file, $modificationsObject->header, $modificationsObject->data) // return $o->{ui}->error('Unable to write modifications to "', $file, '".');
	$o->{ui}->line(scalar @{$modifications->additions}, ' addition(s) and ', scalar @{$modifications->removals}, ' removal(s) written to "', $file, '".');

#line 339 "Condensation/CLI/Commands/Curl.pm"
	# Submit
	$o->curlRequest('POST', $o->{store}->url.'/accounts', ['--data-binary', '@'.$file, '-H', 'Content-Type: application/condensation-modifications'], $modificationsObject);
}

sub curlRequest {
	my $o = shift;
	my $method = shift;
	my $url = shift;
	my $curlArgs = shift;
	my $contentObjectToSign = shift;

#line 344 "Condensation/CLI/Commands/Curl.pm"
	# Parse the URL
	$url =~ /^(https?):\/\/([^\/]+)(\/.*|)$/i || return $o->{ui}->error('"', $url, '" does not look like a valid and complete http://… or https://… URL.');
	my $protocol = lc($1);
	my $host = $2;
	my $path = $3;

#line 350 "Condensation/CLI/Commands/Curl.pm"
	# Strip off user and password, if any
	my $credentials;
	if ($host =~ /^(.*)\@([^\@]*)$/) {
		$credentials = $1;
		$host = lc($2);
	} else {
		$host = lc($host);
	}

#line 359 "Condensation/CLI/Commands/Curl.pm"
	# Remove default port
	if ($host =~ /^(.*):(\d+)$/) {
		$host = $1 if $protocol eq 'http' && $2 == 80;
		$host = $1 if $protocol eq 'https' && $2 == 443;
	}

#line 365 "Condensation/CLI/Commands/Curl.pm"
	# Checks the path and warn the user if obvious things are likely to go wrong
	$o->{ui}->warning('Warning: "//" in URL may not work') if $path =~ /\/\//;
	$o->{ui}->warning('Warning: /./ or /../ in URL may not work') if $path =~ /\/\.+\//;
	$o->{ui}->warning('Warning: /. or /.. at the end of the URL may not work') if $path =~ /\/\.+$/;

#line 370 "Condensation/CLI/Commands/Curl.pm"
	# Signature

#line 372 "Condensation/CLI/Commands/Curl.pm"
	# Date
	my $dateString = CDS::ISODate->millisecondString(CDS->now);

#line 375 "Condensation/CLI/Commands/Curl.pm"
	# Text to sign
	my $bytesToSign = $dateString."\0".uc($method)."\0".$host.$path;
	$bytesToSign .= "\0".$contentObjectToSign->header.$contentObjectToSign->data if defined $contentObjectToSign;

#line 379 "Condensation/CLI/Commands/Curl.pm"
	# Signature
	my $keyPair = $o->{keyPairToken}->keyPair;
	my $hashToSign = CDS::Hash->calculateFor($bytesToSign);
	my $signature = $keyPair->signHash($hashToSign);
	push @$curlArgs, '-H', 'Condensation-Date: '.$dateString;
	push @$curlArgs, '-H', 'Condensation-Actor: '.$keyPair->publicKey->hash->hex;
	push @$curlArgs, '-H', 'Condensation-Signature: '.unpack('H*', $signature);

#line 387 "Condensation/CLI/Commands/Curl.pm"
	# Write signature information to files
	CDS->writeBytesToFile('.cds-curl-bytesToSign', $bytesToSign) || $o->{ui}->warning('Unable to write the bytes to sign to ".cds-curl-bytesToSign".');
	CDS->writeBytesToFile('.cds-curl-hashToSign', $hashToSign->bytes) || $o->{ui}->warning('Unable to write the hash to sign to ".cds-curl-hashToSign".');
	CDS->writeBytesToFile('.cds-curl-signature', $signature) || $o->{ui}->warning('Unable to write signature to ".cds-curl-signature".');

#line 392 "Condensation/CLI/Commands/Curl.pm"
	# Method
	unshift @$curlArgs, '-X', $method if $method ne 'GET';
	unshift @$curlArgs, '-#', '--dump-header', '-';

#line 396 "Condensation/CLI/Commands/Curl.pm"
	# Print
	$o->{ui}->line($o->{ui}->gold('curl', join('', map { ($_ ne '-X' && $_ ne '-' && $_ ne '--dump-header' && $_ ne '-#' && substr($_, 0, 1) eq '-' ? " \\\n     " : ' ').&withQuotesIfNecessary($_) } @$curlArgs), scalar @$curlArgs ? " \\\n     " : ' ', &withQuotesIfNecessary($url)));

#line 399 "Condensation/CLI/Commands/Curl.pm"
	# Execute
	system('curl', @$curlArgs, $url);
}

sub withQuotesIfNecessary {
	my $text = shift;

#line 404 "Condensation/CLI/Commands/Curl.pm"
	return $text =~ /[^a-zA-Z0-9\.\/\@:,_-]/ ? '\''.$text.'\'' : $text;
}

# BEGIN AUTOGENERATED
package CDS::Commands::DiscoverActorGroup;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node002 = CDS::Parser::Node->new(1);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showActorGroupCmd});
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&discover});
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&discover});
	$cds->addArrow($node000, 1, 0, 'show');
	$cds->addArrow($node002, 1, 0, 'discover');
	$help->addArrow($node001, 1, 0, 'discover');
	$help->addArrow($node001, 1, 0, 'rediscover');
	$node000->addArrow($node006, 1, 0, 'ACTORGROUP', \&collectActorgroup);
	$node002->addDefault($node003);
	$node002->addDefault($node004);
	$node002->addDefault($node005);
	$node002->addArrow($node009, 1, 0, 'me', \&collectMe);
	$node002->addArrow($node013, 1, 0, 'ACTORGROUP', \&collectActorgroup1);
	$node003->addArrow($node003, 1, 0, 'ACCOUNT', \&collectAccount);
	$node003->addArrow($node009, 1, 1, 'ACCOUNT', \&collectAccount);
	$node004->addArrow($node004, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node004->addArrow($node007, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node005->addArrow($node005, 1, 0, 'ACTOR', \&collectActor);
	$node005->addArrow($node007, 1, 0, 'ACTOR', \&collectActor);
	$node007->addArrow($node008, 1, 0, 'on');
	$node007->addDefault($node009);
	$node008->addArrow($node009, 1, 0, 'STORE', \&collectStore);
	$node009->addArrow($node010, 1, 0, 'and');
	$node010->addArrow($node011, 1, 0, 'remember');
	$node011->addArrow($node012, 1, 0, 'as');
	$node012->addArrow($node013, 1, 0, 'TEXT', \&collectText);
}

sub collectAccount {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 44 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	push @{$o->{accounts}}, $value;
}

sub collectActor {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 48 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	push @{$o->{actorHashes}}, $value;
}

sub collectActorgroup {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 52 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	$o->{actorGroupToken} = $value;
}

sub collectActorgroup1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 56 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	$o->{actorGroupToken} = $value;
	$o->{label} = $value->label;
}

sub collectKeypair {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 61 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	push @{$o->{actorHashes}}, $value->keyPair->publicKey->hash;
}

sub collectMe {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 65 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	$o->{me} = 1;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 69 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	$o->{store} = $value;
}

sub collectText {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 73 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	$o->{label} = $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 78 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
# END AUTOGENERATED

#line 80 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
# HTML FOLDER NAME discover
# HTML TITLE Discover actor groups
sub help {
	my $o = shift;
	my $cmd = shift;

#line 83 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds discover ACCOUNT');
	$ui->command('cds discover ACTOR [on STORE]');
	$ui->p('Discovers the actor group the given account belongs to. Only active group members are discovered.');
	$ui->space;
	$ui->command('cds discover ACCOUNT*');
	$ui->command('cds discover ACTOR* on STORE');
	$ui->p('Same as above, but starts discovery with multiple accounts. All accounts must belong to the same actor group.');
	$ui->p('Note that this rarely makes sense. The actor group discovery algorithm reliably discovers an actor group from a single account.');
	$ui->space;
	$ui->command('cds discover me');
	$ui->p('Discovers your own actor group.');
	$ui->space;
	$ui->command('… and remember as TEXT');
	$ui->p('The discovered actor group is remembered as TEXT. See "cds help remember" for details.');
	$ui->space;
	$ui->command('cds discover ACTORGROUP');
	$ui->p('Updates a previously remembered actor group.');
	$ui->space;
	$ui->command('cds show ACTORGROUP');
	$ui->p('Shows a previously discovered and remembered actor group.');
	$ui->space;
}

sub discover {
	my $o = shift;
	my $cmd = shift;

#line 109 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	$o->{accounts} = [];
	$o->{actorHashes} = [];
	$cmd->collect($o);

#line 113 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	# Discover
	my $builder = $o->prepareBuilder;
	my ($actorGroup, $cards, $nodes) = $builder->discover($o->{actor}->keyPair, $o);

#line 117 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	# Show the graph
	$o->{ui}->space;
	$o->{ui}->title('Graph');
	for my $node (@$nodes) {
		my $status = $node->status eq 'active' ? $o->{ui}->green('active  ') : $o->{ui}->gray('idle    ');
		$o->{ui}->line($o->{ui}->blue($node->actorHash->hex), ' on ', $node->storeUrl, '  ', $status, $o->{ui}->gray($o->{ui}->niceDateTime($node->revision)));
		$o->{ui}->pushIndent;
		for my $link ($node->links) {
			my $isMostRecentInformation = $link->revision == $link->node->revision;
			my $color = $isMostRecentInformation ? 246 : 250;
			$o->{ui}->line($link->node->actorHash->shortHex, ' on ', $link->node->storeUrl, '  ', $o->{ui}->foreground($color, $o->{ui}->left(8, $link->status), $o->{ui}->niceDateTime($link->revision)));
		}
		$o->{ui}->popIndent;
	}

#line 132 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	# Show all accounts
	$o->showActorGroup($actorGroup);

#line 135 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	# Show all cards
	$o->{ui}->space;
	$o->{ui}->title('Cards');
	for my $card (@$cards) {
		$o->{ui}->line($o->{ui}->gold('cds show record ', $card->cardHash->hex, ' on ', $card->storeUrl));
	}

#line 142 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	# Remember the actor group if desired
	if ($o->{label}) {
		my $selector = $o->{actor}->labelSelector($o->{label});

#line 146 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
		my $record = CDS::Record->new;
		my $actorGroupRecord = $record->add('actor group');
		$actorGroupRecord->add('discovered')->addInteger(CDS->now);
		$actorGroupRecord->addRecord($actorGroup->toBuilder->toRecord(1)->children);
		$selector->set($record);

#line 152 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
		for my $publicKey ($actorGroup->publicKeys) {
			$selector->addObject($publicKey->hash, $publicKey->object);
		}

#line 156 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
		$o->{actor}->saveOrShowError // return;
	}

#line 159 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	$o->{ui}->space;
}

sub prepareBuilder {
	my $o = shift;

#line 163 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	# Actor group
	return $o->{actorGroupToken}->actorGroup->toBuilder if $o->{actorGroupToken};

#line 166 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	# Other than actor group
	my $builder = CDS::ActorGroupBuilder->new;
	$builder->addKnownPublicKey($o->{actor}->keyPair->publicKey);

#line 170 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	# Me
	$builder->addMember($o->{actor}->messagingStoreUrl, $o->{actor}->keyPair->publicKey->hash) if $o->{me};

#line 173 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	# Accounts
	for my $account (@{$o->{accounts}}) {
		$builder->addMember($account->cliStore->url, $account->actorHash);
	}

#line 178 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	# Actors on store
	if (scalar @{$o->{actorHashes}}) {
		my $store = $o->{store} // $o->{actor}->preferredStore;
		for my $actorHash (@{$o->{actorHashes}}) {
			$builder->addMember($actorHash, $store->url);
		}
	}

#line 186 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	return $builder;
}

sub showActorGroupCmd {
	my $o = shift;
	my $cmd = shift;

#line 190 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	$cmd->collect($o);
	$o->showActorGroup($o->{actorGroupToken}->actorGroup);
	$o->{ui}->space;
}

sub showActorGroup {
	my $o = shift;
	my $actorGroup = shift; die 'wrong type '.ref($actorGroup).' for $actorGroup' if defined $actorGroup && ref $actorGroup ne 'CDS::ActorGroup';

#line 196 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	$o->{ui}->space;
	$o->{ui}->title(length $o->{label} ? 'Actors of '.$o->{label} : 'Actor group');
	for my $member ($actorGroup->members) {
		my $date = $member->revision ? $o->{ui}->niceDateTimeLocal($member->revision) : '                   ';
		my $status = $member->isActive ? $o->{ui}->green('active  ') : $o->{ui}->gray('idle    ');
		my $storeReference = $o->{actor}->blueStoreUrlReference($member->storeUrl);
		$o->{ui}->line($o->{ui}->gray($date), '  ', $status, '  ', $member->actorOnStore->publicKey->hash->hex, ' on ', $storeReference);
	}

#line 205 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	if ($actorGroup->entrustedActorsRevision) {
		$o->{ui}->space;
		$o->{ui}->title(length $o->{label} ? 'Actors entrusted by '.$o->{label} : 'Entrusted actors');
		$o->{ui}->line($o->{ui}->gray($o->{ui}->niceDateTimeLocal($actorGroup->entrustedActorsRevision)));
		for my $actor ($actorGroup->entrustedActors) {
			my $storeReference = $o->{actor}->storeUrlReference($actor->storeUrl);
			$o->{ui}->line($actor->actorOnStore->publicKey->hash->hex, $o->{ui}->gray(' on ', $storeReference));
		}

#line 214 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
		$o->{ui}->line($o->{ui}->gray('(none)')) if ! scalar $actorGroup->entrustedActors;
	}
}

sub onDiscoverActorGroupVerifyStore {
	my $o = shift;
	my $storeUrl = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';

#line 219 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	return $o->{actor}->storeForUrl($storeUrl);
}

sub onDiscoverActorGroupInvalidPublicKey {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';
	my $store = shift;
	my $reason = shift;

#line 223 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	$o->{ui}->warning('Public key ', $actorHash->hex, ' on ', $store->url, ' is invalid: ', $reason);
}

sub onDiscoverActorGroupInvalidCard {
	my $o = shift;
	my $actorOnStore = shift; die 'wrong type '.ref($actorOnStore).' for $actorOnStore' if defined $actorOnStore && ref $actorOnStore ne 'CDS::ActorOnStore';
	my $envelopeHash = shift; die 'wrong type '.ref($envelopeHash).' for $envelopeHash' if defined $envelopeHash && ref $envelopeHash ne 'CDS::Hash';
	my $reason = shift;

#line 227 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
	$o->{ui}->warning('Card ', $envelopeHash->hex, ' on ', $actorOnStore->store->url, ' is invalid: ', $reason);
}

sub onDiscoverActorGroupStoreError {
	my $o = shift;
	my $store = shift;
	my $error = shift;

#line 231 "Condensation/CLI/Commands/DiscoverActorGroup.pm"
}

# BEGIN AUTOGENERATED
package CDS::Commands::EntrustedActors;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/EntrustedActors.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node011 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&show});
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(0);
	my $node014 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&doNotEntrust});
	my $node015 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&entrust});
	my $node016 = CDS::Parser::Node->new(0);
	$cds->addArrow($node001, 1, 0, 'show');
	$cds->addArrow($node003, 1, 0, 'do');
	$cds->addArrow($node005, 1, 0, 'entrust');
	$help->addArrow($node000, 1, 0, 'entrusted');
	$node000->addArrow($node010, 1, 0, 'actors');
	$node001->addArrow($node002, 1, 0, 'entrusted');
	$node002->addArrow($node011, 1, 0, 'actors');
	$node003->addArrow($node004, 1, 0, 'not');
	$node004->addArrow($node008, 1, 0, 'entrust');
	$node005->addDefault($node006);
	$node005->addDefault($node007);
	$node005->addArrow($node012, 1, 0, 'ACTOR', \&collectActor);
	$node006->addArrow($node006, 1, 0, 'ACCOUNT', \&collectAccount);
	$node006->addArrow($node015, 1, 1, 'ACCOUNT', \&collectAccount);
	$node007->addArrow($node007, 1, 0, 'ACTOR', \&collectActor1);
	$node007->addArrow($node015, 1, 0, 'ACTOR', \&collectActor1);
	$node008->addDefault($node009);
	$node009->addArrow($node009, 1, 0, 'ACTOR', \&collectActor2);
	$node009->addArrow($node014, 1, 0, 'ACTOR', \&collectActor2);
	$node012->addArrow($node013, 1, 0, 'on');
	$node013->addArrow($node015, 1, 0, 'STORE', \&collectStore);
	$node015->addArrow($node016, 1, 0, 'and');
	$node016->addDefault($node005);
}

sub collectAccount {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 47 "Condensation/CLI/Commands/EntrustedActors.pm"
	push @{$o->{accountTokens}}, $value;
}

sub collectActor {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 51 "Condensation/CLI/Commands/EntrustedActors.pm"
	$o->{actorHash} = $value;
}

sub collectActor1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 55 "Condensation/CLI/Commands/EntrustedActors.pm"
	push @{$o->{accountTokens}}, CDS::AccountToken->new($o->{actor}->preferredStore, $value);
}

sub collectActor2 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 59 "Condensation/CLI/Commands/EntrustedActors.pm"
	push @{$o->{actorHashes}}, $value;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 63 "Condensation/CLI/Commands/EntrustedActors.pm"
	push @{$o->{accountTokens}}, CDS::AccountToken->new($value, $o->{actorHash});
	delete $o->{actorHash};
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 69 "Condensation/CLI/Commands/EntrustedActors.pm"
# END AUTOGENERATED

#line 71 "Condensation/CLI/Commands/EntrustedActors.pm"
# HTML FOLDER NAME entrusted-actors
# HTML TITLE Entrusted actors
sub help {
	my $o = shift;
	my $cmd = shift;

#line 74 "Condensation/CLI/Commands/EntrustedActors.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds show entrusted actors');
	$ui->p('Shows all entrusted actors.');
	$ui->space;
	$ui->command('cds entrust ACCOUNT*');
	$ui->command('cds entrust ACTOR on STORE');
	$ui->p('Adds the indicated entrusted actors. Entrusted actors can read our private data and messages. The public key of the entrusted actor must be available on the store.');
	$ui->space;
	$ui->command('cds do not entrust ACTOR*');
	$ui->p('Removes the indicated entrusted actors.');
	$ui->space;
	$ui->p('After modifying the entrusted actors, you should "cds announce" yourself to publish the changes.');
	$ui->space;
}

sub show {
	my $o = shift;
	my $cmd = shift;

#line 91 "Condensation/CLI/Commands/EntrustedActors.pm"
	my $builder = CDS::ActorGroupBuilder->new;
	$builder->parseEntrustedActorList($o->{actor}->entrustedActorsSelector->record, 1);

#line 94 "Condensation/CLI/Commands/EntrustedActors.pm"
	my @actors = $builder->entrustedActors;
	for my $actor (@actors) {
		my $storeReference = $o->{actor}->storeUrlReference($actor->storeUrl);
		$o->{ui}->line($actor->hash->hex, $o->{ui}->gray(' on ', $storeReference));
	}

#line 100 "Condensation/CLI/Commands/EntrustedActors.pm"
	return if scalar @actors;
	$o->{ui}->line($o->{ui}->gray('none'));
}

sub entrust {
	my $o = shift;
	my $cmd = shift;

#line 105 "Condensation/CLI/Commands/EntrustedActors.pm"
	$o->{accountTokens} = [];
	$cmd->collect($o);

#line 108 "Condensation/CLI/Commands/EntrustedActors.pm"
	# Get the list of currently entrusted actors
	my $entrusted = $o->createEntrustedActorsIndex;

#line 111 "Condensation/CLI/Commands/EntrustedActors.pm"
	# Add new actors
	for my $accountToken (@{$o->{accountTokens}}) {
		my $actorHash = $accountToken->actorHash;

#line 115 "Condensation/CLI/Commands/EntrustedActors.pm"
		# Check if the key is already entrusted
		if ($entrusted->{$accountToken->url}) {
			$o->{ui}->pOrange($accountToken->url, ' is already entrusted.');
			next;
		}

#line 121 "Condensation/CLI/Commands/EntrustedActors.pm"
		# Get the public key
		my ($publicKey, $invalidReason, $storeError) = $o->{actor}->keyPair->getPublicKey($actorHash, $accountToken->cliStore);
		if (defined $storeError) {
			$o->{ui}->pRed('Unable to get the public key ', $actorHash->hex, ' from ', $accountToken->cliStore->url, ': ', $storeError);
			next;
		}

#line 128 "Condensation/CLI/Commands/EntrustedActors.pm"
		if (defined $invalidReason) {
			$o->{ui}->pRed('Unable to get the public key ', $actorHash->hex, ' from ', $accountToken->cliStore->url, ': ', $invalidReason);
			next;
		}

#line 133 "Condensation/CLI/Commands/EntrustedActors.pm"
		# Add it
		$o->{actor}->entrust($accountToken->cliStore->url, $publicKey);
		$o->{ui}->pGreen($entrusted->{$actorHash->hex} ? 'Updated ' : 'Added ', $actorHash->hex, ' as entrusted actor.');
	}

#line 138 "Condensation/CLI/Commands/EntrustedActors.pm"
	# Save
	$o->{actor}->saveOrShowError;
}

sub doNotEntrust {
	my $o = shift;
	my $cmd = shift;

#line 143 "Condensation/CLI/Commands/EntrustedActors.pm"
	$o->{actorHashes} = [];
	$cmd->collect($o);

#line 146 "Condensation/CLI/Commands/EntrustedActors.pm"
	# Get the list of currently entrusted actors
	my $entrusted = $o->createEntrustedActorsIndex;

#line 149 "Condensation/CLI/Commands/EntrustedActors.pm"
	# Remove entrusted actors
	for my $actorHash (@{$o->{actorHashes}}) {
		if ($entrusted->{$actorHash->hex}) {
			$o->{actor}->doNotEntrust($actorHash);
			$o->{ui}->pGreen('Removed ', $actorHash->hex, ' from the list of entrusted actors.');
		} else {
			$o->{ui}->pOrange($actorHash->hex, ' is not entrusted.');
		}
	}

#line 159 "Condensation/CLI/Commands/EntrustedActors.pm"
	# Save
	$o->{actor}->saveOrShowError;
}

sub createEntrustedActorsIndex {
	my $o = shift;

#line 164 "Condensation/CLI/Commands/EntrustedActors.pm"
	my $builder = CDS::ActorGroupBuilder->new;
	$builder->parseEntrustedActorList($o->{actor}->entrustedActorsSelector->record, 1);

#line 167 "Condensation/CLI/Commands/EntrustedActors.pm"
	my $index = {};
	for my $actor ($builder->entrustedActors) {
		my $url = $actor->storeUrl.'/accounts/'.$actor->hash->hex;
		$index->{$actor->hash->hex} = 1;
		$index->{$url} = 1;
	}

#line 174 "Condensation/CLI/Commands/EntrustedActors.pm"
	return $index;
}

package CDS::Commands::FolderStore;

#line 4 "Condensation/CLI/Commands/FolderStore.pm"
# BEGIN AUTOGENERATED

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 7 "Condensation/CLI/Commands/FolderStore.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(0);
	my $node014 = CDS::Parser::Node->new(0);
	my $node015 = CDS::Parser::Node->new(0);
	my $node016 = CDS::Parser::Node->new(0);
	my $node017 = CDS::Parser::Node->new(0);
	my $node018 = CDS::Parser::Node->new(0);
	my $node019 = CDS::Parser::Node->new(0);
	my $node020 = CDS::Parser::Node->new(0);
	my $node021 = CDS::Parser::Node->new(0);
	my $node022 = CDS::Parser::Node->new(0);
	my $node023 = CDS::Parser::Node->new(0);
	my $node024 = CDS::Parser::Node->new(0);
	my $node025 = CDS::Parser::Node->new(1);
	my $node026 = CDS::Parser::Node->new(0);
	my $node027 = CDS::Parser::Node->new(0);
	my $node028 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node029 = CDS::Parser::Node->new(1);
	my $node030 = CDS::Parser::Node->new(0);
	my $node031 = CDS::Parser::Node->new(0);
	my $node032 = CDS::Parser::Node->new(0);
	my $node033 = CDS::Parser::Node->new(0);
	my $node034 = CDS::Parser::Node->new(0);
	my $node035 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&checkPermissions});
	my $node036 = CDS::Parser::Node->new(0);
	my $node037 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&fixPermissions});
	my $node038 = CDS::Parser::Node->new(0);
	my $node039 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showPermissions});
	my $node040 = CDS::Parser::Node->new(0);
	my $node041 = CDS::Parser::Node->new(1);
	my $node042 = CDS::Parser::Node->new(0);
	my $node043 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&addAccount});
	my $node044 = CDS::Parser::Node->new(0);
	my $node045 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&removeAccount});
	my $node046 = CDS::Parser::Node->new(0);
	my $node047 = CDS::Parser::Node->new(1);
	my $node048 = CDS::Parser::Node->new(0);
	my $node049 = CDS::Parser::Node->new(0);
	my $node050 = CDS::Parser::Node->new(0);
	my $node051 = CDS::Parser::Node->new(0);
	my $node052 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&checkPermissions});
	my $node053 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&fixPermissions});
	my $node054 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showPermissions});
	my $node055 = CDS::Parser::Node->new(1);
	my $node056 = CDS::Parser::Node->new(0);
	my $node057 = CDS::Parser::Node->new(0);
	my $node058 = CDS::Parser::Node->new(0);
	my $node059 = CDS::Parser::Node->new(0);
	my $node060 = CDS::Parser::Node->new(0);
	my $node061 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&addAccount});
	my $node062 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&removeAccount});
	my $node063 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&setPermissions});
	my $node064 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&createStore});
	$cds->addArrow($node001, 1, 0, 'create');
	$cds->addArrow($node003, 1, 0, 'check');
	$cds->addArrow($node004, 1, 0, 'fix');
	$cds->addArrow($node005, 1, 0, 'show');
	$cds->addArrow($node007, 1, 0, 'set');
	$cds->addArrow($node009, 1, 0, 'add');
	$cds->addArrow($node010, 1, 0, 'add');
	$cds->addArrow($node011, 1, 0, 'add');
	$cds->addArrow($node012, 1, 0, 'add');
	$cds->addArrow($node013, 1, 0, 'add');
	$cds->addArrow($node023, 1, 0, 'remove');
	$help->addArrow($node000, 1, 0, 'create');
	$node000->addArrow($node028, 1, 0, 'store');
	$node001->addArrow($node002, 1, 0, 'store');
	$node002->addArrow($node029, 1, 0, 'FOLDERNAME', \&collectFoldername);
	$node003->addArrow($node035, 1, 0, 'permissions');
	$node004->addArrow($node037, 1, 0, 'permissions');
	$node005->addArrow($node006, 1, 0, 'permission');
	$node006->addArrow($node039, 1, 0, 'scheme');
	$node007->addArrow($node008, 1, 0, 'permission');
	$node008->addArrow($node041, 1, 0, 'scheme');
	$node009->addArrow($node014, 1, 0, 'account');
	$node010->addArrow($node015, 1, 0, 'account');
	$node011->addArrow($node016, 1, 0, 'account');
	$node012->addArrow($node017, 1, 0, 'account');
	$node013->addArrow($node018, 1, 0, 'account');
	$node014->addArrow($node019, 1, 0, 'for');
	$node015->addArrow($node020, 1, 0, 'for');
	$node016->addArrow($node021, 1, 0, 'for');
	$node017->addArrow($node043, 1, 1, 'ACCOUNT', \&collectAccount);
	$node018->addArrow($node022, 1, 0, 'for');
	$node019->addArrow($node043, 1, 0, 'OBJECTFILE', \&collectObjectfile);
	$node020->addArrow($node043, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node021->addArrow($node025, 1, 0, 'ACTOR', \&collectActor);
	$node022->addArrow($node043, 1, 0, 'OBJECT', \&collectObject);
	$node023->addArrow($node024, 1, 0, 'account');
	$node024->addArrow($node045, 1, 0, 'HASH', \&collectHash);
	$node025->addArrow($node026, 1, 0, 'on');
	$node025->addArrow($node027, 0, 0, 'from');
	$node026->addArrow($node043, 1, 0, 'STORE', \&collectStore);
	$node027->addArrow($node043, 0, 0, 'STORE', \&collectStore);
	$node029->addArrow($node030, 1, 0, 'for');
	$node029->addArrow($node031, 1, 0, 'for');
	$node029->addArrow($node032, 1, 0, 'for');
	$node029->addDefault($node047);
	$node030->addArrow($node033, 1, 0, 'user');
	$node031->addArrow($node034, 1, 0, 'group');
	$node032->addArrow($node047, 1, 0, 'everybody', \&collectEverybody);
	$node033->addArrow($node047, 1, 0, 'USER', \&collectUser);
	$node034->addArrow($node047, 1, 0, 'GROUP', \&collectGroup);
	$node035->addArrow($node036, 1, 0, 'of');
	$node036->addArrow($node052, 1, 0, 'STORE', \&collectStore1);
	$node037->addArrow($node038, 1, 0, 'of');
	$node038->addArrow($node053, 1, 0, 'STORE', \&collectStore1);
	$node039->addArrow($node040, 1, 0, 'of');
	$node040->addArrow($node054, 1, 0, 'STORE', \&collectStore1);
	$node041->addArrow($node042, 1, 0, 'of');
	$node041->addDefault($node055);
	$node042->addArrow($node055, 1, 0, 'STORE', \&collectStore1);
	$node043->addArrow($node044, 1, 0, 'to');
	$node044->addArrow($node061, 1, 0, 'STORE', \&collectStore1);
	$node045->addArrow($node046, 1, 0, 'from');
	$node046->addArrow($node062, 1, 0, 'STORE', \&collectStore1);
	$node047->addArrow($node048, 1, 0, 'and');
	$node047->addDefault($node064);
	$node048->addArrow($node049, 1, 0, 'remember');
	$node049->addArrow($node050, 1, 0, 'it');
	$node050->addArrow($node051, 1, 0, 'as');
	$node051->addArrow($node064, 1, 0, 'TEXT', \&collectText);
	$node055->addArrow($node056, 1, 0, 'to');
	$node055->addArrow($node057, 1, 0, 'to');
	$node055->addArrow($node058, 1, 0, 'to');
	$node056->addArrow($node059, 1, 0, 'user');
	$node057->addArrow($node060, 1, 0, 'group');
	$node058->addArrow($node063, 1, 0, 'everybody', \&collectEverybody);
	$node059->addArrow($node063, 1, 0, 'USER', \&collectUser);
	$node060->addArrow($node063, 1, 0, 'GROUP', \&collectGroup);
}

sub collectAccount {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 152 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{accountToken} = $value;
}

sub collectActor {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 156 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{actorHash} = $value;
}

sub collectEverybody {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 160 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{permissions} = CDS::FolderStore::PosixPermissions::World->new;
}

sub collectFoldername {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 164 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{foldername} = $value;
}

sub collectGroup {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 168 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{permissions} = CDS::FolderStore::PosixPermissions::Group->new($o->{group});
}

sub collectHash {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 172 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{hash} = $value;
}

sub collectKeypair {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 176 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{keyPairToken} = $value;
}

sub collectObject {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 180 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{accountToken} = CDS::AccountToken->new($value->cliStore, $value->hash);
}

sub collectObjectfile {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 184 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{file} = $value;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 188 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{accountToken} = CDS::AccountToken->new($value, $o->{actorHash});
}

sub collectStore1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 192 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{store} = $value;
}

sub collectText {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 196 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{label} = $value;
}

sub collectUser {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 200 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{permissions} = CDS::FolderStore::PosixPermissions::User->new($value);
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 205 "Condensation/CLI/Commands/FolderStore.pm"
# END AUTOGENERATED

#line 212 "Condensation/CLI/Commands/FolderStore.pm"
# HTML FOLDER NAME folder-store
# HTML TITLE Folder store management
sub help {
	my $o = shift;
	my $cmd = shift;

#line 215 "Condensation/CLI/Commands/FolderStore.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds create store FOLDERNAME');
	$ui->p('Creates a new store in FOLDERNAME, and adds it to the list of known stores. If the folder does not exist, it is created. If it does exist, it must be empty.');
	$ui->space;
	$ui->p('By default, the filesystem permissions of the store are set such that only the current user can post objects and modify boxes. Other users on the system can post to the message box, list boxes, and read objects.');
	$ui->space;
	$ui->command('… for user USER');
	$ui->p('Makes the store accessible to the user USER.');
	$ui->space;
	$ui->command('… for group GROUP');
	$ui->p('Makes the store accessible to the group GROUP.');
	$ui->space;
	$ui->command('… for everybody');
	$ui->p('Makes the store accessible to everybody.');
	$ui->space;
	$ui->p('Note that the permissions only affect direct filesystem access. If your store is exposed by a server (e.g. a web server), it may be accessible to others.');
	$ui->space;
	$ui->command('… and remember it as TEXT');
	$ui->p('Remembers the store under the label TEXT. See "cds help remember" for details.');
	$ui->space;
	$ui->command('cds check permissions [of STORE]');
	$ui->p('Checks the permissions (owner, mode) of all accounts, boxes, box entries, and objects of the store, and reports any error. The permission scheme (user, group, or everybody) is derived from the "accounts" and "objects" folders.');
	$ui->p('If the store is omitted, the selected store is used.');
	$ui->space;
	$ui->command('cds fix permissions [of STORE]');
	$ui->p('Same as above, but tries to fix the permissions (chown, chmod) instead of just reporting them.');
	$ui->space;
	$ui->command('cds show permission scheme [of STORE]');
	$ui->p('Reports the permission scheme of the store.');
	$ui->space;
	$ui->command('cds set permission scheme [of STORE] to (user USER|group GROUP|everybody)');
	$ui->p('Sets the permission scheme of the stores, and changes all permissions accordingly.');
	$ui->space;
	$ui->command('cds add account ACCOUNT [to STORE]');
	$ui->command('cds add account for FILE [to STORE]');
	$ui->command('cds add account for KEYPAIR [to STORE]');
	$ui->command('cds add account for OBJECT [to STORE]');
	$ui->command('cds add account for ACTOR on STORE [to STORE]');
	$ui->p('Uploads the public key (FILE, KEYPAIR, OBJECT, ACCOUNT, or ACTOR on STORE) onto the store, and adds the corresponding account. This grants the user the right to access this account.');
	$ui->space;
	$ui->command('cds remove account HASH [from STORE]');
	$ui->p('Removes the indicated account from the store. This immediately destroys the user\'s data.');
	$ui->space;
}

sub createStore {
	my $o = shift;
	my $cmd = shift;

#line 262 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{permissions} = CDS::FolderStore::PosixPermissions::User->new;
	$cmd->collect($o);

#line 265 "Condensation/CLI/Commands/FolderStore.pm"
	# Give up if the folder is non-empty (but we accept hidden files)
	for my $file (CDS->listFolder($o->{foldername})) {
		next if $file =~ /^\./;
		$o->{ui}->pRed('The folder ', $o->{foldername}, ' is not empty. Giving up …');
		return;
	}

#line 272 "Condensation/CLI/Commands/FolderStore.pm"
	# Create the object store
	$o->create($o->{foldername}.'/objects') // return;
	$o->{ui}->pGreen('Object store created for ', $o->{permissions}->target, '.');

#line 276 "Condensation/CLI/Commands/FolderStore.pm"
	# Create the account store
	$o->create($o->{foldername}.'/accounts') // return;
	$o->{ui}->pGreen('Account store created for ', $o->{permissions}->target, '.');

#line 280 "Condensation/CLI/Commands/FolderStore.pm"
	# Return if the user does not want us to add the store
	return if ! defined $o->{label};

#line 283 "Condensation/CLI/Commands/FolderStore.pm"
	# Remember the store
	my $record = CDS::Record->new;
	$record->addText('store')->addText('file://'.$o->{foldername});
	$o->{actor}->remember($o->{label}, $record);
	$o->{actor}->saveOrShowError;
}

#line 290 "Condensation/CLI/Commands/FolderStore.pm"
# Creates a folder with the selected permissions.
sub create {
	my $o = shift;
	my $folder = shift;

#line 292 "Condensation/CLI/Commands/FolderStore.pm"
	# Create the folders to here if necessary
	for my $intermediateFolder (CDS->intermediateFolders($folder)) {
		mkdir $intermediateFolder, 0755;
	}

#line 297 "Condensation/CLI/Commands/FolderStore.pm"
	# mkdir (if it does not exist yet) and chmod (if it does exist already)
	mkdir $folder, $o->{permissions}->baseFolderMode;
	chmod $o->{permissions}->baseFolderMode, $folder;
	chown $o->{permissions}->uid // -1, $o->{permissions}->gid // -1, $folder;

#line 302 "Condensation/CLI/Commands/FolderStore.pm"
	# Check if the result is correct
	my @s = stat $folder;
	return $o->{ui}->error('Unable to create ', $o->{foldername}, '.') if ! scalar @s;
	my $mode = $s[2];
	return $o->{ui}->error($folder, ' exists, but is not a folder') if ! Fcntl::S_ISDIR($mode);
	return $o->{ui}->error('Unable to set the owning user ', $o->{permissions}->user, ' for ', $folder, '.') if defined $o->{permissions}->uid && $s[4] != $o->{permissions}->uid;
	return $o->{ui}->error('Unable to set the owning group ', $o->{permissions}->group, ' for ', $folder, '.') if defined $o->{permissions}->gid && $s[5] != $o->{permissions}->gid;
	return $o->{ui}->error('Unable to set the mode on ', $folder, '.') if ($mode & 0777) != $o->{permissions}->baseFolderMode;
	return 1;
}

sub existingFolderStoreOrShowError {
	my $o = shift;

#line 314 "Condensation/CLI/Commands/FolderStore.pm"
	my $store = $o->{store} // $o->{actor}->preferredStore;

#line 316 "Condensation/CLI/Commands/FolderStore.pm"
	my $folderStore = CDS::FolderStore->forUrl($store->url);
	if (! $folderStore) {
		$o->{ui}->error('"', $store->url, '" is not a folder store.');
		$o->{ui}->space;
		$o->{ui}->p('Account management and file system permission checks only apply to stores on the local file system. Such stores are referred to by file://… URLs, or file system paths.');
		$o->{ui}->p('To fix the permissions on a remote store, log onto that server and fix the permissions there. Note that permissions are not part of the Condensation protocol, but a property of some underlying storage systems, such as file systems.');
		$o->{ui}->space;
		return;
	}

#line 326 "Condensation/CLI/Commands/FolderStore.pm"
	if (! $folderStore->exists) {
		$o->{ui}->error('"', $folderStore->folder, '" does not exist.');
		$o->{ui}->space;
		$o->{ui}->p('The folder either does not exist, or is not a folder store. You can create this store using:');
		$o->{ui}->line($o->{ui}->gold('  cds create store ', $folderStore->folder));
		$o->{ui}->space;
		return;
	}

#line 335 "Condensation/CLI/Commands/FolderStore.pm"
	return $folderStore;
}

sub showPermissions {
	my $o = shift;
	my $cmd = shift;

#line 339 "Condensation/CLI/Commands/FolderStore.pm"
	$cmd->collect($o);
	my $folderStore = $o->existingFolderStoreOrShowError // return;
	$o->showStore($folderStore);
	$o->{ui}->space;
}

sub showStore {
	my $o = shift;
	my $folderStore = shift;

#line 346 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{ui}->space;
	$o->{ui}->title('Store');
	$o->{ui}->line($folderStore->folder);
	$o->{ui}->line('Accessible to ', $folderStore->permissions->target, '.');
}

sub setPermissions {
	my $o = shift;
	my $cmd = shift;

#line 353 "Condensation/CLI/Commands/FolderStore.pm"
	$cmd->collect($o);

#line 355 "Condensation/CLI/Commands/FolderStore.pm"
	my $folderStore = $o->existingFolderStoreOrShowError // return;
	$o->showStore($folderStore);

#line 358 "Condensation/CLI/Commands/FolderStore.pm"
	$folderStore->setPermissions($o->{permissions});
	$o->{ui}->line('Changing permissions …');
	my $logger = CDS::Commands::FolderStore::SetLogger->new($o, $folderStore->folder);
	$folderStore->checkPermissions($logger) || $o->traversalFailed($folderStore);
	$logger->summary;

#line 364 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{ui}->space;
}

sub checkPermissions {
	my $o = shift;
	my $cmd = shift;

#line 368 "Condensation/CLI/Commands/FolderStore.pm"
	$cmd->collect($o);

#line 370 "Condensation/CLI/Commands/FolderStore.pm"
	my $folderStore = $o->existingFolderStoreOrShowError // return;
	$o->showStore($folderStore);

#line 373 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{ui}->line('Checking permissions …');
	my $logger = CDS::Commands::FolderStore::CheckLogger->new($o, $folderStore->folder);
	$folderStore->checkPermissions($logger) || $o->traversalFailed($folderStore);
	$logger->summary;

#line 378 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{ui}->space;
}

sub fixPermissions {
	my $o = shift;
	my $cmd = shift;

#line 382 "Condensation/CLI/Commands/FolderStore.pm"
	$cmd->collect($o);

#line 384 "Condensation/CLI/Commands/FolderStore.pm"
	my $folderStore = $o->existingFolderStoreOrShowError // return;
	$o->showStore($folderStore);

#line 387 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{ui}->line('Fixing permissions …');
	my $logger = CDS::Commands::FolderStore::FixLogger->new($o, $folderStore->folder);
	$folderStore->checkPermissions($logger) || $o->traversalFailed($folderStore);
	$logger->summary;

#line 392 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{ui}->space;
}

sub traversalFailed {
	my $o = shift;
	my $folderStore = shift;

#line 396 "Condensation/CLI/Commands/FolderStore.pm"
	$o->{ui}->space;
	$o->{ui}->p('Traversal failed because a file or folder could not be accessed. You may have to fix the permissions manually, or run this command with other privileges.');
	$o->{ui}->p('If you have root privileges, you can take over this store using:');
	my $userName = getpwuid($<);
	my $groupName = getgrgid($();
	$o->{ui}->line($o->{ui}->gold('  sudo chown -R ', $userName, ':', $groupName, ' ', $folderStore->folder));
	$o->{ui}->p('and then set the desired permission scheme:');
	$o->{ui}->line($o->{ui}->gold('  cds set permissions of ', $folderStore->folder, ' to …'));
	$o->{ui}->space;
	exit(1);
}

sub addAccount {
	my $o = shift;
	my $cmd = shift;

#line 409 "Condensation/CLI/Commands/FolderStore.pm"
	$cmd->collect($o);

#line 411 "Condensation/CLI/Commands/FolderStore.pm"
	# Prepare
	my $folderStore = $o->existingFolderStoreOrShowError // return;
	my $publicKey = $o->publicKey // return;

#line 415 "Condensation/CLI/Commands/FolderStore.pm"
	# Upload the public key onto the store
	my $error = $folderStore->put($publicKey->hash, $publicKey->object);
	return $o->{ui}->error('Unable to upload the public key: ', $error) if $error;

#line 419 "Condensation/CLI/Commands/FolderStore.pm"
	# Create the account folder
	my $folder = $folderStore->folder.'/accounts/'.$publicKey->hash->hex;
	my $permissions = $folderStore->permissions;
	$permissions->mkdir($folder, $permissions->accountFolderMode);
	return $o->{ui}->error('Unable to create folder "', $folder, '".') if ! -d $folder;
	$o->{ui}->pGreen('Account ', $publicKey->hash->hex, ' added.');
	return 1;
}

sub publicKey {
	my $o = shift;

#line 429 "Condensation/CLI/Commands/FolderStore.pm"
	return $o->{keyPairToken}->keyPair->publicKey if $o->{keyPairToken};

#line 431 "Condensation/CLI/Commands/FolderStore.pm"
	if ($o->{file}) {
		my $bytes = CDS->readBytesFromFile($o->{file}) // return $o->{ui}->error('Cannot read "', $o->{file}, '".');
		my $object = CDS::Object->fromBytes($bytes) // return $o->{ui}->error('"', $o->{file}, '" is not a public key.');
		return CDS::PublicKey->fromObject($object) // return $o->{ui}->error('"', $o->{file}, '" is not a public key.');
	}

#line 437 "Condensation/CLI/Commands/FolderStore.pm"
	return $o->{actor}->uiGetPublicKey($o->{accountToken}->actorHash, $o->{accountToken}->cliStore, $o->{actor}->preferredKeyPairToken);
}

sub removeAccount {
	my $o = shift;
	my $cmd = shift;

#line 441 "Condensation/CLI/Commands/FolderStore.pm"
	$cmd->collect($o);

#line 443 "Condensation/CLI/Commands/FolderStore.pm"
	# Prepare the folder
	my $folderStore = $o->existingFolderStoreOrShowError // return;
	my $folder = $folderStore->folder.'/accounts/'.$o->{hash}->hex;
	my $deletedFolder = $folderStore->folder.'/accounts/deleted-'.$o->{hash}->hex;

#line 448 "Condensation/CLI/Commands/FolderStore.pm"
	# Rename, so that it is not visible any more
	$o->recursivelyDelete($deletedFolder) if -e $deletedFolder;
	return $o->{ui}->line('The account ', $o->{hash}->hex, ' does not exist.') if ! -e $folder;
	rename($folder, $deletedFolder) || return $o->{ui}->error('Unable to rename the folder "', $folder, '".');

#line 453 "Condensation/CLI/Commands/FolderStore.pm"
	# Try to delete it entirely
	$o->recursivelyDelete($deletedFolder);
	$o->{ui}->pGreen('Account ', $o->{hash}->hex, ' removed.');
	return 1;
}

sub recursivelyDelete {
	my $o = shift;
	my $folder = shift;

#line 460 "Condensation/CLI/Commands/FolderStore.pm"
	for my $filename (CDS->listFolder($folder)) {
		next if $filename =~ /^\./;
		my $file = $folder.'/'.$filename;
		if (-f $file) {
			unlink $file || $o->{ui}->pOrange('Unable to remove the file "', $file, '".');
		} elsif (-d $file) {
			$o->recursivelyDelete($file);
		}
	}

#line 470 "Condensation/CLI/Commands/FolderStore.pm"
	rmdir($folder) || $o->{ui}->pOrange('Unable to remove the folder "', $folder, '".');
}

package CDS::Commands::FolderStore::CheckLogger;

use parent -norequire, 'CDS::Commands::FolderStore::Logger';

sub finalizeWrong {
	my $o = shift;

#line 4 "Condensation/CLI/Commands/FolderStore/CheckLogger.pm"
	$o->{ui}->pRed(@_);
	return 0;
}

sub summary {
	my $o = shift;

#line 9 "Condensation/CLI/Commands/FolderStore/CheckLogger.pm"
	$o->{ui}->p(($o->{correct} + $o->{wrong}).' files and folders traversed.');
	if ($o->{wrong} > 0) {
		$o->{ui}->p($o->{wrong}, ' files and folders have wrong permissions. To fix them, run');
		$o->{ui}->line($o->{ui}->gold('  cds fix permissions of ', $o->{store}->url));
	} else {
		$o->{ui}->pGreen('All permissions are OK.');
	}
}

package CDS::Commands::FolderStore::FixLogger;

use parent -norequire, 'CDS::Commands::FolderStore::Logger';

sub finalizeWrong {
	my $o = shift;

#line 4 "Condensation/CLI/Commands/FolderStore/FixLogger.pm"
	$o->{ui}->line(@_);
	return 1;
}

sub summary {
	my $o = shift;

#line 9 "Condensation/CLI/Commands/FolderStore/FixLogger.pm"
	$o->{ui}->p(($o->{correct} + $o->{wrong}).' files and folders traversed.');
	$o->{ui}->p('The permissions of ', $o->{wrong}, ' files and folders have been fixed.') if $o->{wrong} > 0;
	$o->{ui}->pGreen('All permissions are OK.');
}

package CDS::Commands::FolderStore::Logger;

sub new {
	my $class = shift;
	my $parent = shift;
	my $baseFolder = shift;

#line 2 "Condensation/CLI/Commands/FolderStore/Logger.pm"
	return bless {
		ui => $parent->{ui},
		store => $parent->{store},
		baseFolder => $baseFolder,
		correct => 0,
		wrong => 0,
		}, $class;
}

sub correct {
	my $o = shift;

#line 12 "Condensation/CLI/Commands/FolderStore/Logger.pm"
	$o->{correct} += 1;
}

sub wrong {
	my $o = shift;
	my $item = shift;
	my $uid = shift;
	my $gid = shift;
	my $mode = shift;
	my $expectedUid = shift;
	my $expectedGid = shift;
	my $expectedMode = shift;

#line 16 "Condensation/CLI/Commands/FolderStore/Logger.pm"
	my $len = length $o->{baseFolder};
	$o->{wrong} += 1;
	$item = '…'.substr($item, $len) if length $item > $len && substr($item, 0, $len) eq $o->{baseFolder};
	my @changes;
	push @changes, 'user '.&username($uid).' -> '.&username($expectedUid) if defined $expectedUid && $uid != $expectedUid;
	push @changes, 'group '.&groupname($gid).' -> '.&groupname($expectedGid) if defined $expectedGid && $gid != $expectedGid;
	push @changes, 'mode '.sprintf('%04o -> %04o', $mode, $expectedMode) if $mode != $expectedMode;
	return $o->finalizeWrong(join(', ', @changes), "\t", $item);
}

sub username {
	my $uid = shift;

#line 27 "Condensation/CLI/Commands/FolderStore/Logger.pm"
	return getpwuid($uid) // $uid;
}

sub groupname {
	my $gid = shift;

#line 31 "Condensation/CLI/Commands/FolderStore/Logger.pm"
	return getgrgid($gid) // $gid;
}

sub accessError {
	my $o = shift;
	my $item = shift;

#line 35 "Condensation/CLI/Commands/FolderStore/Logger.pm"
	$o->{ui}->error('Error accessing ', $item, '.');
	return 0;
}

sub setError {
	my $o = shift;
	my $item = shift;

#line 40 "Condensation/CLI/Commands/FolderStore/Logger.pm"
	$o->{ui}->error('Error setting permissions of ', $item, '.');
	return 0;
}

package CDS::Commands::FolderStore::SetLogger;

use parent -norequire, 'CDS::Commands::FolderStore::Logger';

sub finalizeWrong {
	my $o = shift;

#line 4 "Condensation/CLI/Commands/FolderStore/SetLogger.pm"
	return 1;
}

sub summary {
	my $o = shift;

#line 8 "Condensation/CLI/Commands/FolderStore/SetLogger.pm"
	$o->{ui}->p(($o->{correct} + $o->{wrong}).' files and folders traversed.');
	$o->{ui}->p('The permissions of ', $o->{wrong}, ' files and folders have been adjusted.') if $o->{wrong} > 0;
	$o->{ui}->pGreen('All permissions are OK.');
}

# BEGIN AUTOGENERATED
package CDS::Commands::Get;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/Get.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(1);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(0);
	my $node014 = CDS::Parser::Node->new(0);
	my $node015 = CDS::Parser::Node->new(0);
	my $node016 = CDS::Parser::Node->new(1);
	my $node017 = CDS::Parser::Node->new(0);
	my $node018 = CDS::Parser::Node->new(0);
	my $node019 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&get});
	my $node020 = CDS::Parser::Node->new(1);
	my $node021 = CDS::Parser::Node->new(0);
	my $node022 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&get});
	$cds->addArrow($node000, 1, 0, 'get');
	$cds->addArrow($node001, 1, 0, 'save');
	$cds->addArrow($node002, 1, 0, 'get');
	$cds->addArrow($node003, 1, 0, 'get');
	$cds->addArrow($node009, 1, 0, 'save', \&collectSave);
	$help->addArrow($node005, 1, 0, 'get');
	$help->addArrow($node005, 1, 0, 'save');
	$node000->addArrow($node010, 1, 0, 'HASH', \&collectHash);
	$node001->addArrow($node004, 1, 0, 'data');
	$node002->addArrow($node006, 1, 0, 'HASH', \&collectHash1);
	$node003->addArrow($node010, 1, 0, 'OBJECT', \&collectObject);
	$node004->addArrow($node009, 1, 0, 'of', \&collectOf);
	$node006->addArrow($node007, 1, 0, 'on');
	$node006->addArrow($node008, 0, 0, 'from');
	$node007->addArrow($node010, 1, 0, 'STORE', \&collectStore);
	$node008->addArrow($node010, 0, 0, 'STORE', \&collectStore);
	$node009->addArrow($node013, 1, 0, 'HASH', \&collectHash1);
	$node009->addArrow($node016, 1, 0, 'HASH', \&collectHash);
	$node009->addArrow($node016, 1, 0, 'OBJECT', \&collectObject1);
	$node010->addArrow($node011, 1, 0, 'decrypted');
	$node010->addDefault($node019);
	$node011->addArrow($node012, 1, 0, 'with');
	$node012->addArrow($node019, 1, 0, 'AESKEY', \&collectAeskey);
	$node013->addArrow($node014, 1, 0, 'on');
	$node013->addArrow($node015, 0, 0, 'from');
	$node014->addArrow($node016, 1, 0, 'STORE', \&collectStore);
	$node015->addArrow($node016, 0, 0, 'STORE', \&collectStore);
	$node016->addArrow($node017, 1, 0, 'decrypted');
	$node016->addDefault($node020);
	$node017->addArrow($node018, 1, 0, 'with');
	$node018->addArrow($node020, 1, 0, 'AESKEY', \&collectAeskey);
	$node020->addArrow($node021, 1, 0, 'as');
	$node021->addArrow($node022, 1, 0, 'FILENAME', \&collectFilename);
}

sub collectAeskey {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 63 "Condensation/CLI/Commands/Get.pm"
	$o->{aesKey} = $value;
}

sub collectFilename {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 67 "Condensation/CLI/Commands/Get.pm"
	$o->{filename} = $value;
}

sub collectHash {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 71 "Condensation/CLI/Commands/Get.pm"
	$o->{hash} = $value;
	$o->{store} = $o->{actor}->preferredStore;
}

sub collectHash1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 76 "Condensation/CLI/Commands/Get.pm"
	$o->{hash} = $value;
}

sub collectObject {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 80 "Condensation/CLI/Commands/Get.pm"
	$o->{hash} = $value->hash;
	$o->{store} = $value->cliStore;
}

sub collectObject1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 85 "Condensation/CLI/Commands/Get.pm"
	$o->{hash} = $value->hash;
	push @{$o->{stores}}, $value->store;
}

sub collectOf {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 90 "Condensation/CLI/Commands/Get.pm"
	$o->{saveData} = 1;
}

sub collectSave {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 94 "Condensation/CLI/Commands/Get.pm"
	$o->{saveObject} = 1;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 98 "Condensation/CLI/Commands/Get.pm"
	$o->{store} = $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 103 "Condensation/CLI/Commands/Get.pm"
# END AUTOGENERATED

#line 105 "Condensation/CLI/Commands/Get.pm"
# HTML FOLDER NAME store-get
# HTML TITLE Get
sub help {
	my $o = shift;
	my $cmd = shift;

#line 108 "Condensation/CLI/Commands/Get.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds get OBJECT');
	$ui->command('cds get HASH on STORE');
	$ui->p('Downloads an object and writes it to STDOUT. If the object is not found, the program quits with exit code 1.');
	$ui->space;
	$ui->command('cds get HASH');
	$ui->p('As above, but uses the selected store.');
	$ui->space;
	$ui->command('… decrypted with AESKEY');
	$ui->p('Decrypts the object after retrieval.');
	$ui->space;
	$ui->command('cds save … as FILENAME');
	$ui->p('Saves the object to FILENAME instead of writing it to STDOUT.');
	$ui->space;
	$ui->command('cds save data of … as FILENAME');
	$ui->p('Saves the object\'s data to FILENAME.');
	$ui->space;
	$ui->title('Related commands');
	$ui->line('cds open envelope OBJECT');
	$ui->line('cds show record OBJECT [decrypted with AESKEY]');
	$ui->line('cds show hashes of OBJECT');
	$ui->space;
}

sub get {
	my $o = shift;
	my $cmd = shift;

#line 134 "Condensation/CLI/Commands/Get.pm"
	$cmd->collect($o);

#line 136 "Condensation/CLI/Commands/Get.pm"
	# Retrieve the object
	my $object = $o->{actor}->uiGetObject($o->{hash}, $o->{store}, $o->{actor}->preferredKeyPairToken) // return;

#line 139 "Condensation/CLI/Commands/Get.pm"
	# Decrypt
	$object = $object->crypt($o->{aesKey}) if defined $o->{aesKey};

#line 142 "Condensation/CLI/Commands/Get.pm"
	# Output
	if ($o->{saveData}) {
		CDS->writeBytesToFile($o->{filename}, $object->data) // return $o->{ui}->error('Failed to write data to "', $o->{filename}, '".');
		$o->{ui}->pGreen(length $object->data, ' bytes written to ', $o->{filename}, '.');
	} elsif ($o->{saveObject}) {
		CDS->writeBytesToFile($o->{filename}, $object->bytes) // return $o->{ui}->error('Failed to write object to "', $o->{filename}, '".');
		$o->{ui}->pGreen(length $object->bytes, ' bytes written to ', $o->{filename}, '.');
	} else {
		$o->{ui}->raw($object->bytes);
	}
}

# BEGIN AUTOGENERATED
package CDS::Commands::Help;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/Help.pm"
	my $node000 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node001 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&version});
	$cds->addArrow($node000, 0, 0, '--h');
	$cds->addArrow($node000, 0, 0, '--help');
	$cds->addArrow($node000, 0, 0, '-?');
	$cds->addArrow($node000, 0, 0, '-h');
	$cds->addArrow($node000, 0, 0, '-help');
	$cds->addArrow($node000, 0, 0, '/?');
	$cds->addArrow($node000, 0, 0, '/h');
	$cds->addArrow($node000, 0, 0, '/help');
	$cds->addArrow($node001, 0, 0, '--version');
	$cds->addArrow($node001, 0, 0, '-version');
	$cds->addArrow($node001, 1, 0, 'version');
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 21 "Condensation/CLI/Commands/Help.pm"
# END AUTOGENERATED

#line 23 "Condensation/CLI/Commands/Help.pm"
# HTML IGNORE
sub help {
	my $o = shift;
	my $cmd = shift;

#line 25 "Condensation/CLI/Commands/Help.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->title('Condensation CLI');
	$ui->line('Version ', $CDS::VERSION, ', ', $CDS::releaseDate, ', implementing the Condensation 1 protocol');
	$ui->space;
	$ui->p('Condensation is a distributed data system with conflict-free forward merging and end-to-end security. More information is available on ', $ui->a('https://condensation.io'), '.');
	$ui->space;
	$ui->p('The command line interface (CLI) understands english-like queries like these:');
	$ui->pushIndent;
	$ui->line($ui->blue('cds show key pair'));
	$ui->line($ui->blue('cds create key pair thomas'));
	$ui->line($ui->blue('cds get 45db86549d6d2af3a45be834f2cb0e08cdbbd7699624e7bfd947a3505e6b03e5 \\'));
	$ui->line($ui->blue('   and decrypt with 8b8b091bbe577d5e8d38eae9cd327aa8123fe402a41ea9dd16d86f42fb70cf7e'));
	$ui->popIndent;
	$ui->space;
	$ui->p('If you don\'t know how to continue a command, simply put a ? to see all valid options:');
	$ui->pushIndent;
	$ui->line($ui->blue('cds ?'));
	$ui->line($ui->blue('cds show ?'));
	$ui->popIndent;
	$ui->space;
	$ui->p('To see a list of help topics, type');
	$ui->pushIndent;
	$ui->line($ui->blue('cds help ?'));
	$ui->popIndent;
	$ui->space;
}

sub version {
	my $o = shift;
	my $cmd = shift;

#line 54 "Condensation/CLI/Commands/Help.pm"
	my $ui = $o->{ui};
	$ui->line('Condensation CLI ', $CDS::VERSION, ', ', $CDS::releaseDate);
	$ui->line('implementing the Condensation 1 protocol');
}

# BEGIN AUTOGENERATED
package CDS::Commands::List;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/List.pm"
	my $node000 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node001 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&list});
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(0);
	my $node014 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&listBoxes});
	my $node015 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&list});
	$cds->addArrow($node001, 1, 0, 'list');
	$cds->addArrow($node001, 1, 0, 'watch', \&collectWatch);
	$help->addArrow($node000, 1, 0, 'list');
	$node001->addDefault($node002);
	$node001->addArrow($node003, 1, 0, 'message');
	$node001->addArrow($node004, 1, 0, 'private');
	$node001->addArrow($node005, 1, 0, 'public');
	$node001->addArrow($node006, 0, 0, 'messages', \&collectMessages);
	$node001->addArrow($node006, 0, 0, 'private', \&collectPrivate);
	$node001->addArrow($node006, 0, 0, 'public', \&collectPublic);
	$node001->addArrow($node007, 1, 0, 'my', \&collectMy);
	$node001->addDefault($node011);
	$node002->addArrow($node002, 1, 0, 'BOX', \&collectBox);
	$node002->addArrow($node014, 1, 0, 'BOX', \&collectBox);
	$node003->addArrow($node006, 1, 0, 'box', \&collectMessages);
	$node004->addArrow($node006, 1, 0, 'box', \&collectPrivate);
	$node005->addArrow($node006, 1, 0, 'box', \&collectPublic);
	$node006->addArrow($node011, 1, 0, 'of');
	$node006->addDefault($node012);
	$node007->addArrow($node008, 1, 0, 'message');
	$node007->addArrow($node009, 1, 0, 'private');
	$node007->addArrow($node010, 1, 0, 'public');
	$node007->addArrow($node015, 1, 0, 'boxes');
	$node007->addArrow($node015, 0, 0, 'messages', \&collectMessages);
	$node007->addArrow($node015, 0, 0, 'private', \&collectPrivate);
	$node007->addArrow($node015, 0, 0, 'public', \&collectPublic);
	$node008->addArrow($node015, 1, 0, 'box', \&collectMessages);
	$node009->addArrow($node015, 1, 0, 'box', \&collectPrivate);
	$node010->addArrow($node015, 1, 0, 'box', \&collectPublic);
	$node011->addArrow($node012, 1, 0, 'ACTOR', \&collectActor);
	$node011->addArrow($node012, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node011->addArrow($node015, 1, 1, 'ACCOUNT', \&collectAccount);
	$node011->addArrow($node015, 1, 0, 'ACTORGROUP', \&collectActorgroup);
	$node012->addArrow($node013, 1, 0, 'on');
	$node012->addDefault($node015);
	$node013->addArrow($node015, 1, 0, 'STORE', \&collectStore);
}

sub collectAccount {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 59 "Condensation/CLI/Commands/List.pm"
	$o->{actorHash} = $value->actorHash;
	$o->{store} = $value->cliStore;
}

sub collectActor {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 64 "Condensation/CLI/Commands/List.pm"
	$o->{actorHash} = $value;
}

sub collectActorgroup {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 68 "Condensation/CLI/Commands/List.pm"
	$o->{actorGroup} = $value;
}

sub collectBox {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 72 "Condensation/CLI/Commands/List.pm"
	push @{$o->{boxTokens}}, $value;
}

sub collectKeypair {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 76 "Condensation/CLI/Commands/List.pm"
	$o->{actorHash} = $value->keyPair->publicKey->hash;
	$o->{keyPairToken} = $value;
}

sub collectMessages {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 81 "Condensation/CLI/Commands/List.pm"
	$o->{boxLabels} = ['messages'];
}

sub collectMy {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 85 "Condensation/CLI/Commands/List.pm"
	$o->{my} = 1;
}

sub collectPrivate {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 89 "Condensation/CLI/Commands/List.pm"
	$o->{boxLabels} = ['private'];
}

sub collectPublic {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 93 "Condensation/CLI/Commands/List.pm"
	$o->{boxLabels} = ['public'];
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 97 "Condensation/CLI/Commands/List.pm"
	$o->{store} = $value;
}

sub collectWatch {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 101 "Condensation/CLI/Commands/List.pm"
	$o->{watchTimeout} = 60000;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 106 "Condensation/CLI/Commands/List.pm"
# END AUTOGENERATED

#line 108 "Condensation/CLI/Commands/List.pm"
# HTML FOLDER NAME store-list
# HTML TITLE List
sub help {
	my $o = shift;
	my $cmd = shift;

#line 111 "Condensation/CLI/Commands/List.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds list BOX');
	$ui->p('Lists the indicated box. The object references are shown as "cds open envelope …" command, which can be executed to display the corresponding envelope. Change the command to "cds get …" to download the raw object, or "cds show record …" to show it as record.');
	$ui->space;
	$ui->command('cds list');
	$ui->p('Lists all boxes of the selected key pair.');
	$ui->space;
	$ui->command('cds list BOXLABEL');
	$ui->p('Lists only the indicated box of the selected key pair. BOXLABEL may be:');
	$ui->line('  message box');
	$ui->line('  public box');
	$ui->line('  private box');
	$ui->space;
	$ui->command('cds list my boxes');
	$ui->command('cds list my BOXLABEL');
	$ui->p('Lists your own boxes.');
	$ui->space;
	$ui->command('cds list [BOXLABEL of] ACTORGROUP|ACCOUNT');
	$ui->p('Lists boxes of an actor group, or account.');
	$ui->space;
	$ui->command('cds list [BOXLABEL of] KEYPAIR|ACTOR [on STORE]');
	$ui->p('Lists boxes of an actor on the specified or selected store.');
	$ui->space;
}

sub listBoxes {
	my $o = shift;
	my $cmd = shift;

#line 138 "Condensation/CLI/Commands/List.pm"
	$o->{boxTokens} = [];
	$o->{boxLabels} = ['messages', 'private', 'public'];
	$cmd->collect($o);

#line 142 "Condensation/CLI/Commands/List.pm"
	# Use the selected key pair to sign requests
	$o->{keyPairToken} = $o->{actor}->preferredKeyPairToken if ! $o->{keyPairToken};

#line 145 "Condensation/CLI/Commands/List.pm"
	for my $boxToken (@{$o->{boxTokens}}) {
		$o->listBox($boxToken);
	}

#line 149 "Condensation/CLI/Commands/List.pm"
	$o->{ui}->space;
}

sub list {
	my $o = shift;
	my $cmd = shift;

#line 153 "Condensation/CLI/Commands/List.pm"
	$o->{boxLabels} = ['messages', 'private', 'public'];
	$cmd->collect($o);

#line 156 "Condensation/CLI/Commands/List.pm"
	# Actor hashes
	my @actorHashes;
	my @stores;
	if ($o->{my}) {
		$o->{keyPairToken} = $o->{actor}->keyPairToken;
		push @actorHashes, $o->{keyPairToken}->keyPair->publicKey->hash;
		push @stores, $o->{actor}->storageStore, $o->{actor}->messagingStore;
	} elsif ($o->{actorHash}) {
		push @actorHashes, $o->{actorHash};
	} elsif ($o->{actorGroup}) {
		# TODO
	} else {
		push @actorHashes, $o->{actor}->preferredActorHash;
	}

#line 171 "Condensation/CLI/Commands/List.pm"
	# Stores
	push @stores, $o->{store} if $o->{store};
	push @stores, $o->{actor}->preferredStore if ! scalar @stores;

#line 175 "Condensation/CLI/Commands/List.pm"
	# Use the selected key pair to sign requests
	my $preferredKeyPairToken = $o->{actor}->preferredKeyPairToken;
	$o->{keyPairToken} = $preferredKeyPairToken if ! $o->{keyPairToken};
	$o->{keyPairContext} = $preferredKeyPairToken->keyPair->equals($o->{keyPairToken}->keyPair) ? '' : $o->{ui}->gray(' using ', $o->{actor}->keyPairReference($o->{keyPairToken}));

#line 180 "Condensation/CLI/Commands/List.pm"
	# List boxes
	for my $store (@stores) {
		for my $actorHash (@actorHashes) {
			for my $boxLabel (@{$o->{boxLabels}}) {
				$o->listBox(CDS::BoxToken->new(CDS::AccountToken->new($store, $actorHash), $boxLabel));
			}
		}
	}

#line 189 "Condensation/CLI/Commands/List.pm"
	$o->{ui}->space;
}

sub listBox {
	my $o = shift;
	my $boxToken = shift;

#line 193 "Condensation/CLI/Commands/List.pm"
	$o->{ui}->space;
	$o->{ui}->title($o->{actor}->blueBoxReference($boxToken));

#line 196 "Condensation/CLI/Commands/List.pm"
	# Query the store
	my $store = $boxToken->accountToken->cliStore;
	my ($hashes, $storeError) = $store->list($boxToken->accountToken->actorHash, $boxToken->boxLabel, $o->{watchTimeout} // 0, $o->{keyPairToken}->keyPair);
	return if defined $storeError;

#line 201 "Condensation/CLI/Commands/List.pm"
	# Print the result
	my $count = scalar @$hashes;
	return if ! $count;

#line 205 "Condensation/CLI/Commands/List.pm"
	my $context = $boxToken->boxLabel eq 'messages' ? $o->{ui}->gray(' on ', $o->{actor}->storeReference($store)) : $o->{ui}->gray(' from ', $o->{actor}->accountReference($boxToken->accountToken));
	my $keyPairContext = $boxToken->boxLabel eq 'public' ? '' : $o->{keyPairContext} // '';
	foreach my $hash (sort { $a->bytes cmp $b->bytes } @$hashes) {
		$o->{ui}->line($o->{ui}->gold('cds open envelope ', $hash->hex), $context, $keyPairContext);
	}
	$o->{ui}->line($count.' entries') if $count > 5;
}

# BEGIN AUTOGENERATED
package CDS::Commands::Modify;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/Modify.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node008 = CDS::Parser::Node->new(1);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(0);
	my $node014 = CDS::Parser::Node->new(0);
	my $node015 = CDS::Parser::Node->new(0);
	my $node016 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&modify});
	$cds->addDefault($node000);
	$help->addArrow($node007, 1, 0, 'add');
	$help->addArrow($node007, 1, 0, 'purge');
	$help->addArrow($node007, 1, 0, 'remove');
	$node000->addArrow($node001, 1, 0, 'add');
	$node000->addArrow($node002, 1, 0, 'remove');
	$node000->addArrow($node003, 1, 0, 'add');
	$node000->addArrow($node008, 1, 0, 'purge', \&collectPurge);
	$node001->addArrow($node001, 1, 0, 'HASH', \&collectHash);
	$node001->addArrow($node004, 1, 0, 'HASH', \&collectHash);
	$node002->addArrow($node002, 1, 0, 'HASH', \&collectHash1);
	$node002->addArrow($node005, 1, 0, 'HASH', \&collectHash1);
	$node003->addArrow($node003, 1, 0, 'FILE', \&collectFile);
	$node003->addArrow($node006, 1, 0, 'FILE', \&collectFile);
	$node004->addArrow($node008, 1, 0, 'to');
	$node005->addArrow($node008, 1, 0, 'from');
	$node006->addArrow($node008, 1, 0, 'to');
	$node008->addArrow($node000, 1, 0, 'and');
	$node008->addArrow($node009, 1, 0, 'message');
	$node008->addArrow($node010, 1, 0, 'private');
	$node008->addArrow($node011, 1, 0, 'public');
	$node008->addArrow($node012, 0, 0, 'messages', \&collectMessages);
	$node008->addArrow($node012, 0, 0, 'private', \&collectPrivate);
	$node008->addArrow($node012, 0, 0, 'public', \&collectPublic);
	$node008->addArrow($node016, 1, 0, 'BOX', \&collectBox);
	$node009->addArrow($node012, 1, 0, 'box', \&collectMessages);
	$node010->addArrow($node012, 1, 0, 'box', \&collectPrivate);
	$node011->addArrow($node012, 1, 0, 'box', \&collectPublic);
	$node012->addArrow($node013, 1, 0, 'of');
	$node013->addArrow($node014, 1, 0, 'ACTOR', \&collectActor);
	$node013->addArrow($node014, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node013->addArrow($node016, 1, 1, 'ACCOUNT', \&collectAccount);
	$node014->addArrow($node015, 1, 0, 'on');
	$node014->addDefault($node016);
	$node015->addArrow($node016, 1, 0, 'STORE', \&collectStore);
}

sub collectAccount {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 59 "Condensation/CLI/Commands/Modify.pm"
	$o->{boxToken} = CDS::BoxToken->new($value, $o->{boxLabel});
	delete $o->{boxLabel};
}

sub collectActor {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 64 "Condensation/CLI/Commands/Modify.pm"
	$o->{actorHash} = $value;
}

sub collectBox {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 68 "Condensation/CLI/Commands/Modify.pm"
	$o->{boxToken} = $value;
}

sub collectFile {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 72 "Condensation/CLI/Commands/Modify.pm"
	push @{$o->{fileAdditions}}, $value;
}

sub collectHash {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 76 "Condensation/CLI/Commands/Modify.pm"
	push @{$o->{additions}}, $value;
}

sub collectHash1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 80 "Condensation/CLI/Commands/Modify.pm"
	push @{$o->{removals}}, $value;
}

sub collectKeypair {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 84 "Condensation/CLI/Commands/Modify.pm"
	$o->{actorHash} = $value->publicKey->hash;
	$o->{keyPairToken} = $value;
}

sub collectMessages {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 89 "Condensation/CLI/Commands/Modify.pm"
	$o->{boxLabel} = 'messages';
}

sub collectPrivate {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 93 "Condensation/CLI/Commands/Modify.pm"
	$o->{boxLabel} = 'private';
}

sub collectPublic {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 97 "Condensation/CLI/Commands/Modify.pm"
	$o->{boxLabel} = 'public';
}

sub collectPurge {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 101 "Condensation/CLI/Commands/Modify.pm"
	$o->{purge} = 1;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 105 "Condensation/CLI/Commands/Modify.pm"
	$o->{boxToken} = CDS::BoxToken->new(CDS::AccountToken->new($value, $o->{actorHash}), $o->{boxLabel});
	delete $o->{boxLabel};
	delete $o->{actorHash};
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 112 "Condensation/CLI/Commands/Modify.pm"
# END AUTOGENERATED

#line 114 "Condensation/CLI/Commands/Modify.pm"
# HTML FOLDER NAME store-modify
# HTML TITLE Modify
sub help {
	my $o = shift;
	my $cmd = shift;

#line 117 "Condensation/CLI/Commands/Modify.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds add HASH* to BOX');
	$ui->p('Adds HASH to BOX.');
	$ui->space;
	$ui->command('cds add FILE* to BOX');
	$ui->p('Adds the envelope FILE to BOX.');
	$ui->space;
	$ui->command('cds remove HASH* from BOX');
	$ui->p('Removes HASH from BOX.');
	$ui->p('Note that the store may just mark the hash for removal, and defer its actual removal, or even cancel it. Such removals will still be reported as success.');
	$ui->space;
	$ui->command('cds purge BOX');
	$ui->p('Empties BOX, i.e., removes all its hashes.');
	$ui->space;
	$ui->command('… BOXLABEL of ACCOUNT');
	$ui->p('Modifies a box of an actor group, or account.');
	$ui->space;
	$ui->command('… BOXLABEL of KEYPAIR on STORE');
	$ui->command('… BOXLABEL of ACTOR on STORE');
	$ui->p('Modifies a box of a key pair or an actor on a specific store.');
	$ui->space;
}

sub modify {
	my $o = shift;
	my $cmd = shift;

#line 142 "Condensation/CLI/Commands/Modify.pm"
	$o->{additions} = [];
	$o->{removals} = [];
	$cmd->collect($o);

#line 146 "Condensation/CLI/Commands/Modify.pm"
	# Add a box using the selected store
	if ($o->{actorHash} && $o->{boxLabel}) {
		$o->{boxToken} = CDS::BoxToken->new(CDS::AccountToken->new($o->{actor}->preferredStore, $o->{actorHash}), $o->{boxLabel});
		delete $o->{actorHash};
		delete $o->{boxLabel};
	}

#line 153 "Condensation/CLI/Commands/Modify.pm"
	my $store = $o->{boxToken}->accountToken->cliStore;

#line 155 "Condensation/CLI/Commands/Modify.pm"
	# Prepare additions
	my $modifications = CDS::StoreModifications->new;
	for my $hash (@{$o->{additions}}) {
		$modifications->add($o->{boxToken}->accountToken->actorHash, $o->{boxToken}->boxLabel, $hash);
	}

#line 161 "Condensation/CLI/Commands/Modify.pm"
	for my $file (@{$o->{fileAdditions}}) {
		my $bytes = CDS->readBytesFromFile($file) // return $o->{ui}->error('Unable to read "', $file, '".');
		my $object = CDS::Object->fromBytes($bytes) // return $o->{ui}->error('"', $file, '" is not a Condensation object.');
		my $hash = $object->calculateHash;
		$o->{ui}->warning('"', $file, '" is not a valid envelope. The server may reject it.') if ! $o->{actor}->isEnvelope($object);
		$modifications->add($o->{boxToken}->accountToken->actorHash, $o->{boxToken}->boxLabel, $hash, $object);
	}

#line 169 "Condensation/CLI/Commands/Modify.pm"
	# Prepare removals
	my $boxRemovals = [];
	for my $hash (@{$o->{removals}}) {
		$modifications->remove($o->{boxToken}->accountToken->actorHash, $o->{boxToken}->boxLabel, $hash);
	}

#line 175 "Condensation/CLI/Commands/Modify.pm"
	# If purging is requested, list the box
	if ($o->{purge}) {
		my ($hashes, $error) = $store->list($o->{boxToken}->accountToken->actorHash, $o->{boxToken}->boxLabel, 0);
		return if defined $error;
		$o->{ui}->warning('The box is empty.') if ! scalar @$hashes;

#line 181 "Condensation/CLI/Commands/Modify.pm"
		for my $hash (@$hashes) {
			$modifications->remove($o->{boxToken}->accountToken->actorHash, $o->{boxToken}->boxLabel, $hash);
		}
	}

#line 186 "Condensation/CLI/Commands/Modify.pm"
	# Cancel if there is nothing to do
	return if $modifications->isEmpty;

#line 189 "Condensation/CLI/Commands/Modify.pm"
	# Modify the box
	my $keyPairToken = $o->{keyPairToken} // $o->{actor}->preferredKeyPairToken;
	my $error = $store->modify($modifications, $keyPairToken->keyPair);
	$o->{ui}->pGreen('Box modified.') if ! defined $error;

#line 194 "Condensation/CLI/Commands/Modify.pm"
	# Print undo information
	if ($o->{purge} && scalar @$boxRemovals) {
		$o->{ui}->space;
		$o->{ui}->line($o->{ui}->gray('To undo purging, type:'));
		$o->{ui}->line($o->{ui}->gray('  cds add ', join(" \\\n         ", map { $_->{hash}->hex } @$boxRemovals), " \\\n         to ", $o->{actor}->boxReference($o->{boxToken})));
		$o->{ui}->space;
	}
}

# BEGIN AUTOGENERATED
package CDS::Commands::OpenEnvelope;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/OpenEnvelope.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node003 = CDS::Parser::Node->new(1);
	my $node004 = CDS::Parser::Node->new(1);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(1);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(1);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&openEnvelope});
	$cds->addArrow($node001, 1, 0, 'open');
	$help->addArrow($node000, 1, 0, 'open');
	$node000->addArrow($node002, 1, 0, 'envelope');
	$node001->addArrow($node003, 1, 0, 'envelope');
	$node003->addArrow($node004, 1, 0, 'HASH', \&collectHash);
	$node003->addArrow($node007, 1, 0, 'OBJECT', \&collectObject);
	$node004->addArrow($node005, 1, 0, 'from');
	$node004->addArrow($node006, 1, 0, 'from');
	$node004->addDefault($node009);
	$node005->addArrow($node009, 1, 0, 'ACTOR', \&collectActor);
	$node006->addArrow($node011, 1, 1, 'ACCOUNT', \&collectAccount);
	$node007->addArrow($node008, 1, 0, 'from');
	$node007->addDefault($node011);
	$node008->addArrow($node011, 1, 0, 'ACTOR', \&collectActor);
	$node009->addArrow($node010, 1, 0, 'on');
	$node009->addDefault($node011);
	$node010->addArrow($node011, 1, 0, 'STORE', \&collectStore);
	$node011->addArrow($node012, 1, 0, 'using');
	$node011->addDefault($node013);
	$node012->addArrow($node013, 1, 0, 'KEYPAIR', \&collectKeypair);
}

sub collectAccount {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 41 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{senderHash} = $value->actorHash;
	$o->{store} = $value->cliStore;
}

sub collectActor {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 46 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{senderHash} = $value;
}

sub collectHash {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 50 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{hash} = $value;
	$o->{store} = $o->{actor}->preferredStore;
}

sub collectKeypair {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 55 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{keyPairToken} = $value;
}

sub collectObject {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 59 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{hash} = $value->hash;
	$o->{store} = $value->cliStore;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 64 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{store} = $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 69 "Condensation/CLI/Commands/OpenEnvelope.pm"
# END AUTOGENERATED

#line 71 "Condensation/CLI/Commands/OpenEnvelope.pm"
# HTML FOLDER NAME open-envelope
# HTML TITLE Open envelope
sub help {
	my $o = shift;
	my $cmd = shift;

#line 74 "Condensation/CLI/Commands/OpenEnvelope.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds open envelope OBJECT');
	$ui->command('cds open envelope HASH on STORE');
	$ui->p('Downloads an envelope, verifies its signatures, and tries to decrypt the AES key using the selected key pair and your own key pair.');
	$ui->p('In addition to displaying the envelope details, this command also displays the necessary "cds show record …" command to retrieve the content.');
	$ui->space;
	$ui->command('cds open envelope HASH');
	$ui->p('As above, but uses the selected store.');
	$ui->space;
	$ui->command('… from ACTOR');
	$ui->p('Assumes that the envelope was signed by ACTOR, and downloads the corresponding public key. The sender store is assumed to be the envelope\'s store. This is useful to verify public and private envelopes.');
	$ui->space;
	$ui->command('… using KEYPAIR');
	$ui->p('Tries to decrypt the AES key using this key pair, instead of the selected key pair.');
	$ui->space;
}

sub openEnvelope {
	my $o = shift;
	my $cmd = shift;

#line 93 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{keyPairToken} = $o->{actor}->preferredKeyPairToken;
	$cmd->collect($o);

#line 96 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Get the envelope
	my $envelope = $o->{actor}->uiGetRecord($o->{hash}, $o->{store}, $o->{keyPairToken}) // return;

#line 99 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Continue by envelope type
	my $contentRecord = $envelope->child('content');
	if ($contentRecord->hashValue) {
		if ($envelope->contains('encrypted for')) {
			$o->processPrivateEnvelope($envelope);
		} else {
			$o->processPublicEnvelope($envelope);
		}
	} elsif (length $contentRecord->bytesValue) {
		if ($envelope->contains('head') && $envelope->contains('mac')) {
			$o->processStreamEnvelope($envelope);
		} else {
			$o->processMessageEnvelope($envelope);
		}
	} else {
		$o->processOther($envelope);
	}
}

sub processOther {
	my $o = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';

#line 119 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->space;
	$o->{ui}->pOrange('This is not an envelope. Envelopes always have a "content" section. The raw record is shown below.');
	$o->{ui}->space;
	$o->{ui}->title('Record');
	$o->{ui}->recordChildren($envelope, $o->{actor}->storeReference($o->{store}));
	$o->{ui}->space;
}

sub processPublicEnvelope {
	my $o = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';

#line 128 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->space;
	$o->{ui}->title('Public envelope');
	$o->{ui}->line($o->{ui}->gold('cds show record ', $o->{hash}->hex, ' on ', $o->{actor}->storeReference($o->{store})));

#line 132 "Condensation/CLI/Commands/OpenEnvelope.pm"
	my $contentHash = $envelope->child('content')->hashValue;
	$o->showPublicPrivateSignature($envelope, $contentHash);

#line 135 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->space;
	$o->{ui}->title('Content');
	$o->{ui}->line($o->{ui}->gold('cds show record ', $contentHash->hex, ' on ', $o->{actor}->storeReference($o->{store})));

#line 139 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->space;
}

sub processPrivateEnvelope {
	my $o = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';

#line 143 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->space;
	$o->{ui}->title('Private envelope');
	$o->{ui}->line($o->{ui}->gold('cds show record ', $o->{hash}->hex, ' on ', $o->{actor}->storeReference($o->{store})));

#line 147 "Condensation/CLI/Commands/OpenEnvelope.pm"
	my $aesKey = $o->decryptAesKey($envelope);
	my $contentHash = $envelope->child('content')->hashValue;
	$o->showPublicPrivateSignature($envelope, $contentHash);
	$o->showEncryptedFor($envelope);

#line 152 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->space;
	if ($aesKey) {
		$o->{ui}->title('Content');
		$o->{ui}->line($o->{ui}->gold('cds show record ', $contentHash->hex, ' on ', $o->{actor}->storeReference($o->{store}), ' decrypted with ', unpack('H*', $aesKey)));
	} else {
		$o->{ui}->title('Encrypted content');
		$o->{ui}->line($o->{ui}->gold('cds get ', $contentHash->hex, ' on ', $o->{actor}->storeReference($o->{store})));
	}

#line 161 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->space;
}

sub showPublicPrivateSignature {
	my $o = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
	my $contentHash = shift; die 'wrong type '.ref($contentHash).' for $contentHash' if defined $contentHash && ref $contentHash ne 'CDS::Hash';

#line 165 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->space;
	$o->{ui}->title('Signed by');
	if ($o->{senderHash}) {
		my $accountToken = CDS::AccountToken->new($o->{store}, $o->{senderHash});
		$o->{ui}->line($o->{actor}->blueAccountReference($accountToken));
		$o->showSignature($envelope, $o->{senderHash}, $o->{store}, $contentHash);
	} else {
		$o->{ui}->p('The signer is not known. To verify the signature of a public or private envelope, you need to indicate the account on which it was found:');
		$o->{ui}->line($o->{ui}->gold('  cds show envelope ', $o->{hash}->hex, ' from ', $o->{ui}->underlined('ACTOR'), ' on ', $o->{actor}->storeReference($o->{store})));
	}
}

sub processMessageEnvelope {
	my $o = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';

#line 178 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->space;
	$o->{ui}->title('Message envelope');
	$o->{ui}->line($o->{ui}->gold('cds show record ', $o->{hash}->hex, ' on ', $o->{actor}->storeReference($o->{store})));

#line 182 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Decrypt
	my $encryptedContentBytes = $envelope->child('content')->bytesValue;
	my $aesKey = $o->decryptAesKey($envelope);
	if (! $aesKey) {
		$o->{ui}->space;
		$o->{ui}->title('Encrypted content');
		$o->{ui}->line(length $encryptedContentBytes, ' bytes');
		return $o->processMessageEnvelope2($envelope);
	}

#line 192 "Condensation/CLI/Commands/OpenEnvelope.pm"
	my $contentObject = CDS::Object->fromBytes(CDS::C::aesCrypt($encryptedContentBytes, $aesKey, CDS->zeroCTR));
	if (! $contentObject) {
		$o->{ui}->pRed('The embedded content object is invalid, or the AES key (', unpack('H*', $aesKey), ') is wrong.');
		return $o->processMessageEnvelope2($envelope);
	}

#line 198 "Condensation/CLI/Commands/OpenEnvelope.pm"
	#my $signedHash = $contentObject->calculateHash;	# before 2020-05-05
	my $signedHash = CDS::Hash->calculateFor($encryptedContentBytes);
	my $content = CDS::Record->fromObject($contentObject);
	if (! $content) {
		$o->{ui}->pRed('The embedded content object does not contain a record, or the AES key (', unpack('H*', $aesKey), ') is wrong.');
		return $o->processMessageEnvelope2($envelope);
	}

#line 206 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Sender hash
	my $senderHash = $content->child('sender')->hashValue;
	$o->{ui}->pRed('The content object is missing the sender.') if ! $senderHash;

#line 210 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Sender store
	my $senderStoreRecord = $content->child('store');
	my $senderStoreBytes = $senderStoreRecord->bytesValue;
	my $mentionsSenderStore = length $senderStoreBytes;
	$o->{ui}->pRed('The content object is missing the sender\'s store.') if ! $mentionsSenderStore;
	my $senderStore = scalar $mentionsSenderStore ? $o->{actor}->storeForUrl($senderStoreRecord->textValue) : undef;

#line 217 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Sender
	$o->{ui}->space;
	$o->{ui}->title('Signed by');
	if ($senderHash && $senderStore) {
		my $senderToken = CDS::AccountToken->new($senderStore, $senderHash);
		$o->{ui}->line($o->{actor}->blueAccountReference($senderToken));
		$o->showSignature($envelope, $senderHash, $senderStore, $signedHash);
	} elsif ($senderHash) {
		my $actorLabel = $o->{actor}->actorLabel($senderHash) // $senderHash->hex;
		if ($mentionsSenderStore) {
			$o->{ui}->line($actorLabel, ' on ', $o->{ui}->red($o->{ui}->niceBytes($senderStoreBytes, 64)));
		} else {
			$o->{ui}->line($actorLabel);
		}
		$o->{ui}->pOrange('The signature cannot be verified, because the signer\'s store is not known.');
	} elsif ($senderStore) {
		$o->{ui}->line($o->{ui}->red('?'), ' on ', $o->{actor}->storeReference($senderStore));
		$o->{ui}->pOrange('The signature cannot be verified, because the signer is not known.');
	} elsif ($mentionsSenderStore) {
		$o->{ui}->line($o->{ui}->red('?'), ' on ', $o->{ui}->red($o->{ui}->niceBytes($senderStoreBytes, 64)));
		$o->{ui}->pOrange('The signature cannot be verified, because the signer is not known.');
	} else {
		$o->{ui}->pOrange('The signature cannot be verified, because the signer is not known.');
	}

#line 242 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Content
	$o->{ui}->space;
	$o->{ui}->title('Content');
	$o->{ui}->recordChildren($content, $senderStore ? $o->{actor}->storeReference($senderStore) : undef);

#line 247 "Condensation/CLI/Commands/OpenEnvelope.pm"
	return $o->processMessageEnvelope2($envelope);
}

sub processMessageEnvelope2 {
	my $o = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';

#line 251 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Encrypted for
	$o->showEncryptedFor($envelope);

#line 254 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Updated by
	$o->{ui}->space;
	$o->{ui}->title('May be removed or updated by');

#line 258 "Condensation/CLI/Commands/OpenEnvelope.pm"
	for my $child ($envelope->child('updated by')->children) {
		$o->showActorHash24($child->bytes);
	}

#line 262 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Expires
	$o->{ui}->space;
	$o->{ui}->title('Expires');
	my $expires = $envelope->child('expires')->integerValue;
	$o->{ui}->line($expires ? $o->{ui}->niceDateTime($expires) : $o->{ui}->gray('never'));
	$o->{ui}->space;
}

sub processStreamHead {
	my $o = shift;
	my $head = shift;

#line 271 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->space;
	$o->{ui}->title('Stream head');
	return $o->{ui}->pRed('The envelope does not mention a stream head.') if ! $head;
	$o->{ui}->line($o->{ui}->gold('cds open envelope ', $head->hex, ' on ', $o->{actor}->storeReference($o->{store})));

#line 276 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Get the envelope
	my $envelope = $o->{actor}->uiGetRecord($head, $o->{store}, $o->{keyPairToken}) // return;

#line 279 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Decrypt the content
	my $encryptedContentBytes = $envelope->child('content')->bytesValue;
	my $aesKey = $o->decryptAesKey($envelope) // return;
	my $contentObject = CDS::Object->fromBytes(CDS::C::aesCrypt($encryptedContentBytes, $aesKey, CDS->zeroCTR)) // return {aesKey => $aesKey};
	my $signedHash = CDS::Hash->calculateFor($encryptedContentBytes);
	my $content = CDS::Record->fromObject($contentObject) // return {aesKey => $aesKey};

#line 286 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Sender
	my $senderHash = $content->child('sender')->hashValue;
	my $senderStoreRecord = $content->child('store');
	my $senderStore = $o->{actor}->storeForUrl($senderStoreRecord->textValue);
	return {aesKey => $aesKey, senderHash => $senderHash, senderStore => $senderStore} if ! $senderHash || ! $senderStore;

#line 292 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->pushIndent;
	$o->{ui}->space;
	$o->{ui}->title('Signed by');
	my $senderToken = CDS::AccountToken->new($senderStore, $senderHash);
	$o->{ui}->line($o->{actor}->blueAccountReference($senderToken));
	$o->showSignature($envelope, $senderHash, $senderStore, $signedHash);

#line 299 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Recipients
	$o->{ui}->space;
	$o->{ui}->title('Encrypted for');
	for my $child ($envelope->child('encrypted for')->children) {
		$o->showActorHash24($child->bytes);
	}

#line 306 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->popIndent;
	return {aesKey => $aesKey, senderHash => $senderHash, senderStore => $senderStore, isValid => 1};
}

sub processStreamEnvelope {
	my $o = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';

#line 311 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->space;
	$o->{ui}->title('Stream envelope');
	$o->{ui}->line($o->{ui}->gold('cds show record ', $o->{hash}->hex, ' on ', $o->{actor}->storeReference($o->{store})));

#line 315 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Get the head
	my $streamHead = $o->processStreamHead($envelope->child('head')->hashValue);
	$o->{ui}->pRed('The stream head cannot be opened. Open the stream head envelope for details.') if ! $streamHead || ! $streamHead->{isValid};

#line 319 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Get the content
	my $encryptedBytes = $envelope->child('content')->bytesValue;

#line 322 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Get the CTR
	$o->{ui}->space;
	$o->{ui}->title('CTR');
	my $ctr = $envelope->child('ctr')->bytesValue;
	if (length $ctr == 16) {
		$o->{ui}->line(unpack('H*', $ctr));
	} else {
		$o->{ui}->pRed('The CTR value is invalid.');
	}

#line 332 "Condensation/CLI/Commands/OpenEnvelope.pm"
	return $o->{ui}->space if ! $streamHead;
	return $o->{ui}->space if ! $streamHead->{aesKey};

#line 335 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Get and verify the MAC
	$o->{ui}->space;
	$o->{ui}->title('Message authentication (MAC)');
	my $mac = $envelope->child('mac')->bytesValue;
	my $signedHash = CDS::Hash->calculateFor($encryptedBytes);
	my $expectedMac = CDS::C::aesCrypt($signedHash->bytes, $streamHead->{aesKey}, $ctr);
	if ($mac eq $expectedMac) {
		$o->{ui}->pGreen('The MAC valid.');
	} else {
		$o->{ui}->pRed('The MAC is invalid.');
	}

#line 347 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Decrypt the content
	$o->{ui}->space;
	$o->{ui}->title('Content');
	my $contentObject = CDS::Object->fromBytes(CDS::C::aesCrypt($encryptedBytes, $streamHead->{aesKey}, CDS::C::counterPlusInt($ctr, 2)));
	if (! $contentObject) {
		$o->{ui}->pRed('The embedded content object is invalid, or the provided AES key (', unpack('H*', $streamHead->{aesKey}), ') is wrong.') ;
		$o->{ui}->space;
		return;
	}

#line 357 "Condensation/CLI/Commands/OpenEnvelope.pm"
	my $content = CDS::Record->fromObject($contentObject);
	return $o->{ui}->pRed('The content is not a record.') if ! $content;
	$o->{ui}->recordChildren($content, $streamHead->{senderStore} ? $o->{actor}->storeReference($streamHead->{senderStore}) : undef);
	$o->{ui}->space;

#line 362 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# The envelope is valid
	#my $source = CDS::Source->new($o->{pool}->{keyPair}, $o->{actorOnStore}, 'messages', $entry->{hash});
	#return CDS::ReceivedMessage->new($o, $entry, $source, $envelope, $streamHead->senderStoreUrl, $streamHead->sender, $content, $streamHead);

#line 366 "Condensation/CLI/Commands/OpenEnvelope.pm"
}

sub showActorHash24 {
	my $o = shift;
	my $actorHashBytes = shift;

#line 369 "Condensation/CLI/Commands/OpenEnvelope.pm"
	my $actorHashHex = unpack('H*', $actorHashBytes);
	return $o->{ui}->line($o->{ui}->red($actorHashHex, ' (', length $actorHashBytes, ' instead of 24 bytes)')) if length $actorHashBytes != 24;

#line 372 "Condensation/CLI/Commands/OpenEnvelope.pm"
	my $actorName = $o->{actor}->actorLabelByHashStartBytes($actorHashBytes);
	$actorHashHex .= '·' x 16;

#line 375 "Condensation/CLI/Commands/OpenEnvelope.pm"
	my $keyPairHashBytes = $o->{keyPairToken}->keyPair->publicKey->hash->bytes;
	my $isMe = substr($keyPairHashBytes, 0, 24) eq $actorHashBytes;
	$o->{ui}->line($isMe ? $o->{ui}->violet($actorHashHex) : $actorHashHex, (defined $actorName ? $o->{ui}->blue('  '.$actorName) : ''));
	return $isMe;
}

sub showSignature {
	my $o = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
	my $senderHash = shift; die 'wrong type '.ref($senderHash).' for $senderHash' if defined $senderHash && ref $senderHash ne 'CDS::Hash';
	my $senderStore = shift;
	my $signedHash = shift; die 'wrong type '.ref($signedHash).' for $signedHash' if defined $signedHash && ref $signedHash ne 'CDS::Hash';

#line 382 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Get the public key
	my $publicKey = $o->getPublicKey($senderHash, $senderStore);
	return $o->{ui}->line($o->{ui}->orange('The signature cannot be verified, because the signer\'s public key is not available.')) if ! $publicKey;

#line 386 "Condensation/CLI/Commands/OpenEnvelope.pm"
	# Verify the signature
	if (CDS->verifyEnvelopeSignature($envelope, $publicKey, $signedHash)) {
		$o->{ui}->pGreen('The signature is valid.');
	} else {
		$o->{ui}->pRed('The signature is not valid.');
	}
}

sub getPublicKey {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $store = shift;

#line 395 "Condensation/CLI/Commands/OpenEnvelope.pm"
	return $o->{keyPairToken}->keyPair->publicKey if $hash->equals($o->{keyPairToken}->keyPair->publicKey->hash);
	return $o->{actor}->uiGetPublicKey($hash, $store, $o->{keyPairToken});
}

sub showEncryptedFor {
	my $o = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';

#line 400 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->space;
	$o->{ui}->title('Encrypted for');

#line 403 "Condensation/CLI/Commands/OpenEnvelope.pm"
	my $canDecrypt = 0;
	for my $child ($envelope->child('encrypted for')->children) {
		$canDecrypt = 1 if $o->showActorHash24($child->bytes);
	}

#line 408 "Condensation/CLI/Commands/OpenEnvelope.pm"
	return if $canDecrypt;
	$o->{ui}->space;
	my $keyPairHash = $o->{keyPairToken}->keyPair->publicKey->hash;
	$o->{ui}->pOrange('This envelope is not encrypted for you (', $keyPairHash->shortHex, '). If you possess one of the keypairs mentioned above, add "… using KEYPAIR" to open this envelope.');
}

sub decryptAesKey {
	my $o = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';

#line 415 "Condensation/CLI/Commands/OpenEnvelope.pm"
	my $keyPair = $o->{keyPairToken}->keyPair;
	my $hashBytes24 = substr($keyPair->publicKey->hash->bytes, 0, 24);
	my $child = $envelope->child('encrypted for')->child($hashBytes24);

#line 419 "Condensation/CLI/Commands/OpenEnvelope.pm"
	my $encryptedAesKey = $child->bytesValue;
	return if ! length $encryptedAesKey;

#line 422 "Condensation/CLI/Commands/OpenEnvelope.pm"
	my $aesKey = $keyPair->decrypt($encryptedAesKey);
	return $aesKey if defined $aesKey && length $aesKey == 32;

#line 425 "Condensation/CLI/Commands/OpenEnvelope.pm"
	$o->{ui}->pRed('The AES key failed to decrypt. It either wasn\'t encrypted properly, or the encryption was performed with the wrong public key.');
	return;
}

# BEGIN AUTOGENERATED
package CDS::Commands::Put;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/Put.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(1);
	my $node013 = CDS::Parser::Node->new(0);
	my $node014 = CDS::Parser::Node->new(0);
	my $node015 = CDS::Parser::Node->new(0);
	my $node016 = CDS::Parser::Node->new(0);
	my $node017 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&put});
	$cds->addArrow($node000, 1, 0, 'put');
	$cds->addArrow($node001, 1, 0, 'put');
	$cds->addArrow($node002, 1, 0, 'put');
	$help->addArrow($node007, 1, 0, 'put');
	$node000->addArrow($node012, 1, 0, 'OBJECTFILE', \&collectObjectfile);
	$node001->addArrow($node003, 1, 0, 'object');
	$node002->addArrow($node004, 1, 0, 'public');
	$node003->addArrow($node008, 1, 0, 'with');
	$node004->addArrow($node005, 1, 0, 'key');
	$node005->addArrow($node006, 1, 0, 'of');
	$node006->addArrow($node012, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node008->addDefault($node009);
	$node008->addDefault($node011);
	$node009->addArrow($node009, 1, 0, 'HASH', \&collectHash);
	$node009->addArrow($node010, 1, 0, 'HASH', \&collectHash);
	$node010->addArrow($node011, 1, 0, 'and');
	$node011->addArrow($node012, 1, 0, 'FILE', \&collectFile);
	$node012->addArrow($node013, 1, 0, 'encrypted');
	$node012->addDefault($node015);
	$node013->addArrow($node014, 1, 0, 'with');
	$node014->addArrow($node015, 1, 0, 'AESKEY', \&collectAeskey);
	$node015->addArrow($node016, 1, 0, 'onto');
	$node015->addDefault($node017);
	$node016->addArrow($node016, 1, 0, 'STORE', \&collectStore);
	$node016->addArrow($node017, 1, 0, 'STORE', \&collectStore);
}

sub collectAeskey {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 50 "Condensation/CLI/Commands/Put.pm"
	$o->{aesKey} = $value;
}

sub collectFile {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 54 "Condensation/CLI/Commands/Put.pm"
	$o->{dataFile} = $value;
}

sub collectHash {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 58 "Condensation/CLI/Commands/Put.pm"
	push @{$o->{hashes}}, $value;
}

sub collectKeypair {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 62 "Condensation/CLI/Commands/Put.pm"
	$o->{object} = $value->keyPair->publicKey->object;
}

sub collectObjectfile {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 66 "Condensation/CLI/Commands/Put.pm"
	$o->{objectFile} = $value;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 70 "Condensation/CLI/Commands/Put.pm"
	push @{$o->{stores}}, $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 75 "Condensation/CLI/Commands/Put.pm"
# END AUTOGENERATED

#line 77 "Condensation/CLI/Commands/Put.pm"
# HTML FOLDER NAME store-put
# HTML TITLE Put
sub help {
	my $o = shift;
	my $cmd = shift;

#line 80 "Condensation/CLI/Commands/Put.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds put FILE* [onto STORE*]');
	$ui->p('Uploads object files onto object stores. If no stores are provided, the selected store is used. If an upload fails, the program immediately quits with exit code 1.');
	$ui->space;
	$ui->command('cds put FILE encrypted with AESKEY [onto STORE*]');
	$ui->p('Encrypts the object before the upload.');
	$ui->space;
	$ui->command('cds put object with [HASH* and] FILE …');
	$ui->p('Creates an object with the HASHes as hash list and FILE as data.');
	$ui->space;
	$ui->command('cds put public key of KEYPAIR …');
	$ui->p('Uploads the public key of the indicated key pair onto the store.');
	$ui->space;
}

sub put {
	my $o = shift;
	my $cmd = shift;

#line 97 "Condensation/CLI/Commands/Put.pm"
	$o->{hashes} = [];
	$o->{stores} = [];
	$cmd->collect($o);

#line 101 "Condensation/CLI/Commands/Put.pm"
	# Stores
	push @{$o->{stores}}, $o->{actor}->preferredStore if ! scalar @{$o->{stores}};

#line 104 "Condensation/CLI/Commands/Put.pm"
	$o->{get} = [];
	return $o->putObject($o->{object}) if $o->{object};
	return $o->putObjectFile if $o->{objectFile};
	$o->putConstructedFile;
}

sub putObjectFile {
	my $o = shift;

#line 111 "Condensation/CLI/Commands/Put.pm"
	my $object = $o->{objectFile}->object;

#line 113 "Condensation/CLI/Commands/Put.pm"
	# Display object information
	$o->{ui}->space;
	$o->{ui}->title('Uploading ', $o->{objectFile}->file, '  ', $o->{ui}->gray($o->{ui}->niceFileSize($object->byteLength)));
	$o->{ui}->line($object->hashesCount == 1 ? '1 hash' : $object->hashesCount.' hashes');
	$o->{ui}->line($o->{ui}->niceFileSize(length $object->data).' data');
	$o->{ui}->space;

#line 120 "Condensation/CLI/Commands/Put.pm"
	# Upload
	$o->putObject($object);
}

sub putConstructedFile {
	my $o = shift;

#line 125 "Condensation/CLI/Commands/Put.pm"
	# Create the object
	my $data = CDS->readBytesFromFile($o->{dataFile}) // return $o->{ui}->error('Unable to read "', $o->{dataFile}, '".');
	my $header = pack('L>', scalar @{$o->{hashes}}) . join('', map { $_->bytes } @{$o->{hashes}});
	my $object = CDS::Object->create($header, $data);

#line 130 "Condensation/CLI/Commands/Put.pm"
	# Display object information
	$o->{ui}->space;
	$o->{ui}->title('Uploading new object  ', $o->{ui}->gray($o->{ui}->niceFileSize(length $object->bytes)));
	$o->{ui}->line($object->hashesCount == 1 ? '1 hash' : $object->hashesCount.' hashes');
	$o->{ui}->line($o->{ui}->niceFileSize(length $object->data).' data from ', $o->{dataFile});
	$o->{ui}->space;

#line 137 "Condensation/CLI/Commands/Put.pm"
	# Upload
	$o->putObject($object);
}

sub putObject {
	my $o = shift;
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

#line 142 "Condensation/CLI/Commands/Put.pm"
	my $keyPair = $o->{actor}->preferredKeyPairToken->keyPair;

#line 144 "Condensation/CLI/Commands/Put.pm"
	# Encrypt it if desired
	my $objectBytes;
	if (defined $o->{aesKey}) {
		$object = $object->crypt($o->{aesKey});
		unshift @{$o->{get}}, ' decrypted with ', unpack('H*', $o->{aesKey}), ' ';
	}

#line 151 "Condensation/CLI/Commands/Put.pm"
	# Calculate the hash
	my $hash = $object->calculateHash;

#line 154 "Condensation/CLI/Commands/Put.pm"
	# Upload the object
	my $successfulStore;
	for my $store (@{$o->{stores}}) {
		my $error = $store->put($hash, $object, $keyPair);
		next if $error;
		$o->{ui}->pGreen('The object was uploaded onto ', $store->url, '.');
		$successfulStore = $store;
	}

#line 163 "Condensation/CLI/Commands/Put.pm"
	# Show the corresponding download line
	return if ! $successfulStore;
	$o->{ui}->space;
	$o->{ui}->line('To download the object, type:');
	$o->{ui}->line($o->{ui}->gold('cds get ', $hash->hex), $o->{ui}->gray(' on ', $successfulStore->url, @{$o->{get}}));
	$o->{ui}->space;
}

package CDS::Commands::Remember;

#line 3 "Condensation/CLI/Commands/Remember.pm"
# BEGIN AUTOGENERATED

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 6 "Condensation/CLI/Commands/Remember.pm"
	my $node000 = CDS::Parser::Node->new(0, {constructor => \&new, function => \&showLabels});
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&forget});
	my $node007 = CDS::Parser::Node->new(1);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&remember});
	$cds->addArrow($node000, 1, 0, 'remember');
	$cds->addArrow($node001, 1, 0, 'forget');
	$help->addArrow($node003, 1, 0, 'forget');
	$help->addArrow($node003, 1, 0, 'remember');
	$node000->addArrow($node004, 1, 0, 'ACTOR', \&collectActor);
	$node000->addArrow($node007, 1, 1, 'ACCOUNT', \&collectAccount);
	$node000->addArrow($node007, 1, 0, 'ACTOR', \&collectActor);
	$node000->addArrow($node007, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node000->addArrow($node007, 1, 0, 'STORE', \&collectStore);
	$node001->addDefault($node002);
	$node002->addArrow($node002, 1, 0, 'LABEL', \&collectLabel);
	$node002->addArrow($node006, 1, 0, 'LABEL', \&collectLabel);
	$node004->addArrow($node005, 1, 0, 'on');
	$node005->addArrow($node007, 1, 0, 'STORE', \&collectStore);
	$node007->addArrow($node008, 1, 0, 'as');
	$node008->addArrow($node009, 1, 0, 'TEXT', \&collectText);
}

sub collectAccount {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 35 "Condensation/CLI/Commands/Remember.pm"
	$o->{store} = $value->cliStore;
	$o->{actorHash} = $value->actorHash;
}

sub collectActor {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 40 "Condensation/CLI/Commands/Remember.pm"
	$o->{actorHash} = $value;
}

sub collectKeypair {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 44 "Condensation/CLI/Commands/Remember.pm"
	$o->{keyPairToken} = $value;
}

sub collectLabel {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 48 "Condensation/CLI/Commands/Remember.pm"
	push @{$o->{forget}}, $value;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 52 "Condensation/CLI/Commands/Remember.pm"
	$o->{store} = $value;
}

sub collectText {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 56 "Condensation/CLI/Commands/Remember.pm"
	$o->{label} = $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 61 "Condensation/CLI/Commands/Remember.pm"
# END AUTOGENERATED

#line 63 "Condensation/CLI/Commands/Remember.pm"
# HTML FOLDER NAME remember
# HTML TITLE Remember
sub help {
	my $o = shift;
	my $cmd = shift;

#line 66 "Condensation/CLI/Commands/Remember.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds remember');
	$ui->p('Shows all remembered values.');
	$ui->space;
	$ui->command('cds remember ACCOUNT|ACTOR|STORE|KEYPAIR as TEXT');
	$ui->command('cds remember ACTOR on STORE as TEXT');
	$ui->p('Remembers the indicated actor hash, account, store, or key pair as TEXT. This information is stored in the global state, and therefore persists until the name is deleted (cds forget …) or redefined (cds remember …).');
	$ui->space;
	$ui->p('Key pairs are stored as link (absolute path) to the key pair file, and specific to the device.');
	$ui->space;
	$ui->command('cds forget LABEL');
	$ui->p('Forgets the corresponding item.');
	$ui->space;
}

sub remember {
	my $o = shift;
	my $cmd = shift;

#line 83 "Condensation/CLI/Commands/Remember.pm"
	$cmd->collect($o);

#line 85 "Condensation/CLI/Commands/Remember.pm"
	my $record = CDS::Record->new;
	$record->add('store')->addText($o->{store}->url) if defined $o->{store};
	$record->add('actor')->add($o->{actorHash}->bytes) if defined $o->{actorHash};
	$record->add('key pair')->addText($o->{keyPairToken}->file) if defined $o->{keyPairToken};
	$o->{actor}->remember($o->{label}, $record);
	$o->{actor}->saveOrShowError;
}

sub forget {
	my $o = shift;
	my $cmd = shift;

#line 94 "Condensation/CLI/Commands/Remember.pm"
	$o->{forget} = [];
	$cmd->collect($o);

#line 97 "Condensation/CLI/Commands/Remember.pm"
	for my $label (@{$o->{forget}}) {
		$o->{actor}->groupRoot->child('labels')->child($label)->clear;
	}

#line 101 "Condensation/CLI/Commands/Remember.pm"
	$o->{actor}->saveOrShowError;
}

sub showLabels {
	my $o = shift;
	my $cmd = shift;

#line 105 "Condensation/CLI/Commands/Remember.pm"
	$o->{ui}->space;
	$o->showRememberedValues;
	$o->{ui}->space;
}

sub showRememberedValues {
	my $o = shift;

#line 111 "Condensation/CLI/Commands/Remember.pm"
	my $hasLabel = 0;
	for my $child (sort { $a->{id} cmp $b->{id} } $o->{actor}->groupRoot->child('labels')->children) {
		my $record = $child->record;
		my $label = $o->{ui}->blue($o->{ui}->left(15, Encode::decode_utf8($child->label)));

#line 116 "Condensation/CLI/Commands/Remember.pm"
		my $actorHash = CDS::Hash->fromBytes($record->child('actor')->bytesValue);
		my $storeUrl = $record->child('store')->textValue;
		my $keyPairFile = $record->child('key pair')->textValue;

#line 120 "Condensation/CLI/Commands/Remember.pm"
		if (length $keyPairFile) {
			$o->{ui}->line($label, ' ', $o->{ui}->gray('key pair'), '    ', $keyPairFile);
			$hasLabel = 1;
		}

#line 125 "Condensation/CLI/Commands/Remember.pm"
		if ($actorHash && length $storeUrl) {
			my $storeReference = $o->{actor}->blueStoreUrlReference($storeUrl);
			$o->{ui}->line($label, ' ', $o->{ui}->gray('account'), '     ', $actorHash->hex, ' on ', $storeReference);
			$hasLabel = 1;
		} elsif ($actorHash) {
			$o->{ui}->line($label, ' ', $o->{ui}->gray('actor'), '       ', $actorHash->hex);
			$hasLabel = 1;
		} elsif (length $storeUrl) {
			$o->{ui}->line($label, ' ', $o->{ui}->gray('store'), '       ', $storeUrl);
			$hasLabel = 1;
		}

#line 137 "Condensation/CLI/Commands/Remember.pm"
		$o->showActorGroupLabel($label, $record->child('actor group'));
	}

#line 140 "Condensation/CLI/Commands/Remember.pm"
	return if $hasLabel;
	$o->{ui}->line($o->{ui}->gray('none'));
}

sub showActorGroupLabel {
	my $o = shift;
	my $label = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 145 "Condensation/CLI/Commands/Remember.pm"
	return if ! $record->contains('actor group');

#line 147 "Condensation/CLI/Commands/Remember.pm"
	my $builder = CDS::ActorGroupBuilder->new;
	$builder->parse($record, 1);

#line 150 "Condensation/CLI/Commands/Remember.pm"
	my $countActive = 0;
	my $countIdle = 0;
	my $newestActive = undef;

#line 154 "Condensation/CLI/Commands/Remember.pm"
	for my $member ($builder->members) {
		my $isActive = $member->status eq 'active';
		$countActive += 1 if $isActive;
		$countIdle += 1 if $member->status eq 'idle';

#line 159 "Condensation/CLI/Commands/Remember.pm"
		next if ! $isActive;
		next if $newestActive && $member->revision <= $newestActive->revision;
		$newestActive = $member;
	}

#line 164 "Condensation/CLI/Commands/Remember.pm"
	my @line;
	push @line, $label, ' ', $o->{ui}->gray('actor group'), ' ';
	push @line, $newestActive->hash->hex, ' on ', $o->{actor}->blueStoreUrlReference($newestActive->storeUrl) if $newestActive;
	push @line, $o->{ui}->gray('(no active actor)') if ! $newestActive;
	push @line, $o->{ui}->green('  ', $countActive, ' active');
	my $discovered = $record->child('discovered')->integerValue;
	push @line, $o->{ui}->gray('  ', $o->{ui}->niceDateTimeLocal($discovered)) if $discovered;
	$o->{ui}->line(@line);
}

# BEGIN AUTOGENERATED
package CDS::Commands::Select;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/Select.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(0);
	my $node014 = CDS::Parser::Node->new(0);
	my $node015 = CDS::Parser::Node->new(0);
	my $node016 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node017 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showSelectionCmd});
	my $node018 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&unselectKeyPair});
	my $node019 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&unselectStore});
	my $node020 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&unselectActor});
	my $node021 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&unselectAll});
	my $node022 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&select});
	$cds->addArrow($node000, 1, 0, 'select');
	$cds->addArrow($node001, 1, 0, 'select');
	$cds->addArrow($node002, 1, 0, 'select');
	$cds->addArrow($node003, 1, 0, 'select');
	$cds->addArrow($node004, 1, 0, 'select');
	$cds->addArrow($node005, 1, 0, 'select');
	$cds->addArrow($node006, 1, 0, 'select');
	$cds->addArrow($node009, 1, 0, 'unselect');
	$cds->addArrow($node010, 1, 0, 'unselect');
	$cds->addArrow($node011, 1, 0, 'unselect');
	$cds->addArrow($node012, 1, 0, 'unselect');
	$cds->addArrow($node017, 1, 0, 'select');
	$help->addArrow($node016, 1, 0, 'select');
	$node000->addArrow($node022, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node001->addArrow($node022, 1, 0, 'STORE', \&collectStore);
	$node002->addArrow($node014, 1, 0, 'ACTOR', \&collectActor);
	$node003->addArrow($node007, 1, 0, 'storage');
	$node004->addArrow($node008, 1, 0, 'messaging');
	$node005->addArrow($node022, 1, 0, 'ACTOR', \&collectActor);
	$node006->addArrow($node022, 1, 1, 'ACCOUNT', \&collectAccount);
	$node007->addArrow($node022, 1, 0, 'store', \&collectStore1);
	$node008->addArrow($node022, 1, 0, 'store', \&collectStore2);
	$node009->addArrow($node013, 1, 0, 'key');
	$node010->addArrow($node019, 1, 0, 'store');
	$node011->addArrow($node020, 1, 0, 'actor');
	$node012->addArrow($node021, 1, 0, 'all');
	$node013->addArrow($node018, 1, 0, 'pair');
	$node014->addArrow($node015, 1, 0, 'on');
	$node015->addArrow($node022, 1, 0, 'STORE', \&collectStore);
}

sub collectAccount {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 59 "Condensation/CLI/Commands/Select.pm"
	$o->{store} = $value->cliStore;
	$o->{actorHash} = $value->actorHash;
}

sub collectActor {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 64 "Condensation/CLI/Commands/Select.pm"
	$o->{actorHash} = $value;
}

sub collectKeypair {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 68 "Condensation/CLI/Commands/Select.pm"
	$o->{keyPairToken} = $value;
	$o->{actorHash} = $value->keyPair->publicKey->hash;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 73 "Condensation/CLI/Commands/Select.pm"
	$o->{store} = $value;
}

sub collectStore1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 77 "Condensation/CLI/Commands/Select.pm"
	$o->{store} = $o->{actor}->storageStore;
}

sub collectStore2 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 81 "Condensation/CLI/Commands/Select.pm"
	$o->{store} = $o->{actor}->messagingStore;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 86 "Condensation/CLI/Commands/Select.pm"
# END AUTOGENERATED

#line 88 "Condensation/CLI/Commands/Select.pm"
# HTML FOLDER NAME select
# HTML TITLE Select
sub help {
	my $o = shift;
	my $cmd = shift;

#line 91 "Condensation/CLI/Commands/Select.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds select');
	$ui->p('Shows the current selection.');
	$ui->space;
	$ui->command('cds select KEYPAIR');
	$ui->p('Selects KEYPAIR on this terminal. Some commands will use this key pair by default.');
	$ui->space;
	$ui->command('cds unselect key pair');
	$ui->p('Removes the key pair selection.');
	$ui->space;
	$ui->command('cds select STORE');
	$ui->p('Selects STORE on this terminal. Some commands will use this store by default.');
	$ui->space;
	$ui->command('cds unselect store');
	$ui->p('Removes the store selection.');
	$ui->space;
	$ui->command('cds select ACTOR');
	$ui->p('Selects ACTOR on this terminal. Some commands will use this store by default.');
	$ui->space;
	$ui->command('cds unselect actor');
	$ui->p('Removes the actor selection.');
	$ui->space;
	$ui->command('cds unselect');
	$ui->p('Removes any selection.');
	$ui->space;
}

sub select {
	my $o = shift;
	my $cmd = shift;

#line 120 "Condensation/CLI/Commands/Select.pm"
	$cmd->collect($o);

#line 122 "Condensation/CLI/Commands/Select.pm"
	if ($o->{keyPairToken}) {
		$o->{actor}->sessionRoot->child('selected key pair')->setText($o->{keyPairToken}->file);
		$o->{ui}->pGreen('Key pair ', $o->{keyPairToken}->file, ' selected.');
	}

#line 127 "Condensation/CLI/Commands/Select.pm"
	if ($o->{store}) {
		$o->{actor}->sessionRoot->child('selected store')->setText($o->{store}->url);
		$o->{ui}->pGreen('Store ', $o->{store}->url, ' selected.');
	}

#line 132 "Condensation/CLI/Commands/Select.pm"
	if ($o->{actorHash}) {
		$o->{actor}->sessionRoot->child('selected actor')->setBytes($o->{actorHash}->bytes);
		$o->{ui}->pGreen('Actor ', $o->{actorHash}->hex, ' selected.');
	}

#line 137 "Condensation/CLI/Commands/Select.pm"
	$o->{actor}->saveOrShowError;
}

sub unselectKeyPair {
	my $o = shift;
	my $cmd = shift;

#line 141 "Condensation/CLI/Commands/Select.pm"
	$o->{actor}->sessionRoot->child('selected key pair')->clear;
	$o->{ui}->pGreen('Key pair selection cleared.');
	$o->{actor}->saveOrShowError;
}

sub unselectStore {
	my $o = shift;
	my $cmd = shift;

#line 147 "Condensation/CLI/Commands/Select.pm"
	$o->{actor}->sessionRoot->child('selected store')->clear;
	$o->{ui}->pGreen('Store selection cleared.');
	$o->{actor}->saveOrShowError;
}

sub unselectActor {
	my $o = shift;
	my $cmd = shift;

#line 153 "Condensation/CLI/Commands/Select.pm"
	$o->{actor}->sessionRoot->child('selected actor')->clear;
	$o->{ui}->pGreen('Actor selection cleared.');
	$o->{actor}->saveOrShowError;
}

sub unselectAll {
	my $o = shift;
	my $cmd = shift;

#line 159 "Condensation/CLI/Commands/Select.pm"
	$o->{actor}->sessionRoot->child('selected key pair')->clear;
	$o->{actor}->sessionRoot->child('selected store')->clear;
	$o->{actor}->sessionRoot->child('selected actor')->clear;
	$o->{actor}->saveOrShowError // return;
	$o->showSelection;
}

sub showSelectionCmd {
	my $o = shift;
	my $cmd = shift;

#line 167 "Condensation/CLI/Commands/Select.pm"
	$o->{ui}->space;
	$o->showSelection;
	$o->{ui}->space;
}

sub showSelection {
	my $o = shift;

#line 173 "Condensation/CLI/Commands/Select.pm"
	my $keyPairFile = $o->{actor}->sessionRoot->child('selected key pair')->textValue;
	my $storeUrl = $o->{actor}->sessionRoot->child('selected store')->textValue;
	my $actorBytes = $o->{actor}->sessionRoot->child('selected actor')->bytesValue;

#line 177 "Condensation/CLI/Commands/Select.pm"
	$o->{ui}->line($o->{ui}->darkBold('Selected key pair  '), length $keyPairFile ? $keyPairFile : $o->{ui}->gray('none'));
	$o->{ui}->line($o->{ui}->darkBold('Selected store     '), length $storeUrl ? $storeUrl : $o->{ui}->gray('none'));
	$o->{ui}->line($o->{ui}->darkBold('Selected actor     '), length $actorBytes == 32 ? unpack('H*', $actorBytes) : $o->{ui}->gray('none'));
}

# BEGIN AUTOGENERATED
package CDS::Commands::ShowCard;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/ShowCard.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node005 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showMyCard});
	my $node006 = CDS::Parser::Node->new(1);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showCard});
	$cds->addArrow($node001, 1, 0, 'show');
	$cds->addArrow($node002, 1, 0, 'show');
	$help->addArrow($node000, 1, 0, 'show');
	$node000->addArrow($node004, 1, 0, 'card');
	$node001->addArrow($node006, 1, 0, 'card');
	$node002->addArrow($node003, 1, 0, 'my');
	$node003->addArrow($node005, 1, 0, 'card');
	$node006->addArrow($node007, 1, 0, 'of');
	$node006->addArrow($node008, 1, 0, 'of');
	$node006->addArrow($node009, 1, 0, 'of');
	$node006->addArrow($node010, 1, 0, 'of');
	$node006->addDefault($node011);
	$node007->addArrow($node007, 1, 0, 'ACCOUNT', \&collectAccount);
	$node007->addArrow($node013, 1, 1, 'ACCOUNT', \&collectAccount);
	$node008->addArrow($node013, 1, 0, 'ACTORGROUP', \&collectActorgroup);
	$node009->addArrow($node011, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node010->addArrow($node011, 1, 0, 'ACTOR', \&collectActor);
	$node011->addArrow($node012, 1, 0, 'on');
	$node011->addDefault($node013);
	$node012->addArrow($node012, 1, 0, 'STORE', \&collectStore);
	$node012->addArrow($node013, 1, 0, 'STORE', \&collectStore);
}

sub collectAccount {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 42 "Condensation/CLI/Commands/ShowCard.pm"
	push @{$o->{accountTokens}}, $value;
}

sub collectActor {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 46 "Condensation/CLI/Commands/ShowCard.pm"
	$o->{actorHash} = $value;
}

sub collectActorgroup {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 50 "Condensation/CLI/Commands/ShowCard.pm"
	for my $member ($value->actorGroup->members) {
	my $actorOnStore = $member->actorOnStore;
	$o->addKnownPublicKey($actorOnStore->publicKey);
	push @{$o->{accountTokens}}, CDS::AccountToken->new($actorOnStore->store, $actorOnStore->publicKey->hash);
	}
}

sub collectKeypair {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 58 "Condensation/CLI/Commands/ShowCard.pm"
	$o->{keyPairToken} = $value;
	$o->{actorHash} = $value->keyPair->publicKey->hash;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 63 "Condensation/CLI/Commands/ShowCard.pm"
	push @{$o->{stores}}, $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 68 "Condensation/CLI/Commands/ShowCard.pm"
# END AUTOGENERATED

#line 70 "Condensation/CLI/Commands/ShowCard.pm"
# HTML FOLDER NAME show-card
# HTML TITLE Show an actor's public card
sub help {
	my $o = shift;
	my $cmd = shift;

#line 73 "Condensation/CLI/Commands/ShowCard.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds show card of ACCOUNT');
	$ui->command('cds show card of ACTOR [on STORE]');
	$ui->command('cds show card of KEYPAIR [on STORE]');
	$ui->p('Shows the card(s) of an actor.');
	$ui->space;
	$ui->command('cds show card of ACTORGROUP');
	$ui->p('Shows all cards of an actor group.');
	$ui->space;
	$ui->command('cds show card');
	$ui->p('Shows the card of the selected actor on the selected store.');
	$ui->space;
	$ui->command('cds show my card');
	$ui->p('Shows your own card.');
	$ui->space;
	$ui->p('An actor usually has one card. If no cards are shown, the corresponding actor does not exist, is not using that store, or has not properly announced itself. Two cards may exist while the actor is updating its card. Such a state is temporary, but may exist for hours or days if the actor has intermittent network access. Three or more cards may point to an error in the way the actor updates his card, an error in the synchronization code (if the account is synchronized). Two or more cards may also occur naturally when stores are merged.');
	$ui->space;
	$ui->p('A peer consists of one or more actors, which all publish their own card. The cards are usually different, but should contain consistent information.');
	$ui->space;
	$ui->p('You can publish your own card (i.e. the card of your main key pair) using');
	$ui->p('  cds announce');
	$ui->space;
}

sub showCard {
	my $o = shift;
	my $cmd = shift;

#line 99 "Condensation/CLI/Commands/ShowCard.pm"
	$o->{keyPairToken} = $o->{actor}->preferredKeyPairToken;
	$o->{stores} = [];
	$o->{accountTokens} = [];
	$o->{knownPublicKeys} = {};
	$cmd->collect($o);

#line 105 "Condensation/CLI/Commands/ShowCard.pm"
	# Use actorHash/store
	if (! scalar @{$o->{accountTokens}}) {
		$o->{actorHash} = $o->{actor}->preferredActorHash if ! $o->{actorHash};
		push @{$o->{stores}}, $o->{actor}->preferredStores if ! scalar @{$o->{stores}};
		for my $store (@{$o->{stores}}) {
			push @{$o->{accountTokens}}, CDS::AccountToken->new($store, $o->{actorHash});
		}
	}

#line 114 "Condensation/CLI/Commands/ShowCard.pm"
	# Show the cards
	$o->addKnownPublicKey($o->{keyPairToken}->keyPair->publicKey);
	$o->addKnownPublicKey($o->{actor}->keyPair->publicKey);
	for my $accountToken (@{$o->{accountTokens}}) {
		$o->processAccount($accountToken);
	}

#line 121 "Condensation/CLI/Commands/ShowCard.pm"
	$o->{ui}->space;
}

sub showMyCard {
	my $o = shift;
	my $cmd = shift;

#line 125 "Condensation/CLI/Commands/ShowCard.pm"
	$o->{keyPairToken} = $o->{actor}->preferredKeyPairToken;
	$o->processAccount(CDS::AccountToken->new($o->{actor}->messagingStore, $o->{actor}->keyPair->publicKey->hash));
	$o->processAccount(CDS::AccountToken->new($o->{actor}->storageStore, $o->{actor}->keyPair->publicKey->hash)) if $o->{actor}->storageStore->url ne $o->{actor}->messagingStore->url;
	$o->{ui}->space;
}

sub processAccount {
	my $o = shift;
	my $accountToken = shift;

#line 132 "Condensation/CLI/Commands/ShowCard.pm"
	$o->{ui}->space;

#line 134 "Condensation/CLI/Commands/ShowCard.pm"
	# Query the store
	my $store = $accountToken->cliStore;
	my ($hashes, $storeError) = $store->list($accountToken->actorHash, 'public', 0);
	if (defined $storeError) {
		$o->{ui}->title('public box of ', $o->{actor}->blueAccountReference($accountToken));
		return;
	}

#line 142 "Condensation/CLI/Commands/ShowCard.pm"
	# Print the result
	my $count = scalar @$hashes;
	$o->{ui}->title('public box of ', $o->{actor}->blueAccountReference($accountToken), '  ', $o->{ui}->blue($count == 0 ? 'no cards' : $count == 1 ? '1 card' : $count.' cards'));
	return if ! $count;

#line 147 "Condensation/CLI/Commands/ShowCard.pm"
	foreach my $hash (sort { $a->bytes cmp $b->bytes } @$hashes) {
		$o->processEntry($accountToken, $hash);
	}
}

sub processEntry {
	my $o = shift;
	my $accountToken = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 153 "Condensation/CLI/Commands/ShowCard.pm"
	my $keyPair = $o->{keyPairToken}->keyPair;
	my $store = $accountToken->cliStore;
	my $storeReference = $o->{actor}->storeReference($store);

#line 157 "Condensation/CLI/Commands/ShowCard.pm"
	# Open the envelope
	$o->{ui}->line($o->{ui}->gold('cds open envelope ', $hash->hex), $o->{ui}->gray(' from ', $accountToken->actorHash->hex, ' on ', $storeReference));

#line 160 "Condensation/CLI/Commands/ShowCard.pm"
	my $envelope = $o->{actor}->uiGetRecord($hash, $accountToken->cliStore, $o->{keyPairToken}) // return;
	my $publicKey = $o->getPublicKey($accountToken) // $o->{ui}->pRed('The owner\'s public key is missing. Skipping signature verification.');
	my $cardHash = $envelope->child('content')->hashValue // $o->{ui}->pRed('Missing content hash.');
	return $o->{ui}->pRed('Invalid signature.') if $publicKey && $cardHash && ! CDS->verifyEnvelopeSignature($envelope, $publicKey, $cardHash);

#line 165 "Condensation/CLI/Commands/ShowCard.pm"
	# Read and show the card
	return if ! $cardHash;
	$o->{ui}->line($o->{ui}->gold('cds show record ', $cardHash->hex), $o->{ui}->gray(' on ', $storeReference));
	my $card = $o->{actor}->uiGetRecord($cardHash, $accountToken->cliStore, $o->{keyPairToken}) // return;

#line 170 "Condensation/CLI/Commands/ShowCard.pm"
	$o->{ui}->pushIndent;
	$o->{ui}->recordChildren($card, $storeReference);
	$o->{ui}->popIndent;
	return;
}

sub getPublicKey {
	my $o = shift;
	my $accountToken = shift;

#line 177 "Condensation/CLI/Commands/ShowCard.pm"
	my $hash = $accountToken->actorHash;
	my $knownPublicKey = $o->{knownPublicKeys}->{$hash->bytes};
	return $knownPublicKey if $knownPublicKey;
	my $publicKey = $o->{actor}->uiGetPublicKey($hash, $accountToken->cliStore, $o->{keyPairToken}) // return;
	$o->addKnownPublicKey($publicKey);
	return $publicKey;
}

sub addKnownPublicKey {
	my $o = shift;
	my $publicKey = shift; die 'wrong type '.ref($publicKey).' for $publicKey' if defined $publicKey && ref $publicKey ne 'CDS::PublicKey';

#line 186 "Condensation/CLI/Commands/ShowCard.pm"
	$o->{knownPublicKeys}->{$publicKey->hash->bytes} = $publicKey;
}

# BEGIN AUTOGENERATED
package CDS::Commands::ShowKeyPair;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/ShowKeyPair.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node009 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showKeyPair});
	my $node010 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showMyKeyPair});
	my $node011 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showSelectedKeyPair});
	$cds->addArrow($node002, 1, 0, 'show');
	$cds->addArrow($node003, 1, 0, 'show');
	$cds->addArrow($node004, 1, 0, 'show');
	$help->addArrow($node000, 1, 0, 'show');
	$node000->addArrow($node001, 1, 0, 'key');
	$node001->addArrow($node008, 1, 0, 'pair');
	$node002->addArrow($node009, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node003->addArrow($node005, 1, 0, 'my');
	$node004->addArrow($node006, 1, 0, 'key');
	$node005->addArrow($node007, 1, 0, 'key');
	$node006->addArrow($node011, 1, 0, 'pair');
	$node007->addArrow($node010, 1, 0, 'pair');
}

sub collectKeypair {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 31 "Condensation/CLI/Commands/ShowKeyPair.pm"
	$o->{keyPairToken} = $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 36 "Condensation/CLI/Commands/ShowKeyPair.pm"
# END AUTOGENERATED

#line 38 "Condensation/CLI/Commands/ShowKeyPair.pm"
# HTML FOLDER NAME show-key-pair
# HTML TITLE Show key pair
sub help {
	my $o = shift;
	my $cmd = shift;

#line 41 "Condensation/CLI/Commands/ShowKeyPair.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds show KEYPAIR');
	$ui->command('cds show my key pair');
	$ui->command('cds show key pair');
	$ui->p('Shows information about KEYPAIR, your key pair, or the currently selected key pair (see "cds use …").');
	$ui->space;
}

sub showKeyPair {
	my $o = shift;
	my $cmd = shift;

#line 51 "Condensation/CLI/Commands/ShowKeyPair.pm"
	$cmd->collect($o);
	$o->showAll($o->{keyPairToken});
}

sub showMyKeyPair {
	my $o = shift;
	my $cmd = shift;

#line 56 "Condensation/CLI/Commands/ShowKeyPair.pm"
	$cmd->collect($o);
	$o->showAll($o->{actor}->keyPairToken);
}

sub showSelectedKeyPair {
	my $o = shift;
	my $cmd = shift;

#line 61 "Condensation/CLI/Commands/ShowKeyPair.pm"
	$cmd->collect($o);
	$o->showAll($o->{actor}->preferredKeyPairToken);
}

sub show {
	my $o = shift;
	my $keyPairToken = shift;

#line 66 "Condensation/CLI/Commands/ShowKeyPair.pm"
	$o->{ui}->line($o->{ui}->darkBold('File  '), $keyPairToken->file) if defined $keyPairToken->file;
	$o->{ui}->line($o->{ui}->darkBold('Hash  '), $keyPairToken->keyPair->publicKey->hash->hex);
}

sub showAll {
	my $o = shift;
	my $keyPairToken = shift;

#line 71 "Condensation/CLI/Commands/ShowKeyPair.pm"
	$o->{ui}->space;
	$o->{ui}->title('Key pair');
	$o->show($keyPairToken);
	$o->showPublicKeyObject($keyPairToken);
	$o->showPublicKey($keyPairToken);
	$o->showPrivateKey($keyPairToken);
	$o->{ui}->space;
}

sub showPublicKeyObject {
	my $o = shift;
	my $keyPairToken = shift;

#line 81 "Condensation/CLI/Commands/ShowKeyPair.pm"
	my $object = $keyPairToken->keyPair->publicKey->object;
	$o->{ui}->space;
	$o->{ui}->title('Public key object');
	$o->byteData('      ', $object->bytes);
}

sub showPublicKey {
	my $o = shift;
	my $keyPairToken = shift;

#line 88 "Condensation/CLI/Commands/ShowKeyPair.pm"
	my $rsaPublicKey = $keyPairToken->keyPair->publicKey->{rsaPublicKey};
	$o->{ui}->space;
	$o->{ui}->title('Public key');
	$o->byteData('e     ', CDS::C::publicKeyE($rsaPublicKey));
	$o->byteData('n     ', CDS::C::publicKeyN($rsaPublicKey));
}

sub showPrivateKey {
	my $o = shift;
	my $keyPairToken = shift;

#line 96 "Condensation/CLI/Commands/ShowKeyPair.pm"
	my $rsaPrivateKey = $keyPairToken->keyPair->{rsaPrivateKey};
	$o->{ui}->space;
	$o->{ui}->title('Private key');
	$o->byteData('e     ', CDS::C::privateKeyE($rsaPrivateKey));
	$o->byteData('p     ', CDS::C::privateKeyP($rsaPrivateKey));
	$o->byteData('q     ', CDS::C::privateKeyQ($rsaPrivateKey));
}

sub byteData {
	my $o = shift;
	my $label = shift;
	my $bytes = shift;

#line 105 "Condensation/CLI/Commands/ShowKeyPair.pm"
	my $hex = unpack('H*', $bytes);
	$o->{ui}->line($o->{ui}->darkBold($label), substr($hex, 0, 64));

#line 108 "Condensation/CLI/Commands/ShowKeyPair.pm"
	my $start = 64;
	my $spaces = ' ' x length $label;
	while ($start < length $hex) {
		$o->{ui}->line($spaces, substr($hex, $start, 64));
		$start += 64;
	}
}

# BEGIN AUTOGENERATED
package CDS::Commands::ShowMessages;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/ShowMessages.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node009 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showMessagesOfSelected});
	my $node010 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showMyMessages});
	my $node011 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showOurMessages});
	my $node012 = CDS::Parser::Node->new(1);
	my $node013 = CDS::Parser::Node->new(0);
	my $node014 = CDS::Parser::Node->new(0);
	my $node015 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showMessages});
	$cds->addArrow($node001, 1, 0, 'show');
	$cds->addArrow($node002, 1, 0, 'show');
	$cds->addArrow($node003, 1, 0, 'show');
	$cds->addArrow($node004, 1, 0, 'show');
	$help->addArrow($node000, 1, 0, 'show');
	$node000->addArrow($node008, 1, 0, 'messages');
	$node001->addArrow($node005, 1, 0, 'messages');
	$node002->addArrow($node006, 1, 0, 'my');
	$node003->addArrow($node009, 1, 0, 'messages');
	$node004->addArrow($node007, 1, 0, 'our');
	$node005->addArrow($node012, 1, 0, 'of');
	$node006->addArrow($node010, 1, 0, 'messages');
	$node007->addArrow($node011, 1, 0, 'messages');
	$node012->addArrow($node013, 1, 0, 'ACTOR', \&collectActor);
	$node012->addArrow($node013, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node012->addArrow($node015, 1, 1, 'ACCOUNT', \&collectAccount);
	$node012->addArrow($node015, 1, 0, 'ACTOR', \&collectActor1);
	$node012->addArrow($node015, 1, 0, 'ACTORGROUP', \&collectActorgroup);
	$node012->addArrow($node015, 1, 0, 'KEYPAIR', \&collectKeypair1);
	$node013->addArrow($node014, 1, 0, 'on');
	$node014->addArrow($node015, 1, 0, 'STORE', \&collectStore);
}

sub collectAccount {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 44 "Condensation/CLI/Commands/ShowMessages.pm"
	push @{$o->{accountTokens}}, $value;
}

sub collectActor {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 48 "Condensation/CLI/Commands/ShowMessages.pm"
	$o->{actorHash} = $value;
}

sub collectActor1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 52 "Condensation/CLI/Commands/ShowMessages.pm"
	push @{$o->{accountTokens}}, CDS::AccountToken->new($o->{actor}->preferredStore, $value);
}

sub collectActorgroup {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 56 "Condensation/CLI/Commands/ShowMessages.pm"
	for my $member ($value->actorGroup->members) {
	push @{$o->{accountTokens}}, CDS::AccountToken->new($member->actorOnStore->store, $member->actorOnStore->publicKey->hash);
	}
}

sub collectKeypair {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 62 "Condensation/CLI/Commands/ShowMessages.pm"
	$o->{keyPairToken} = $value;
	$o->{actorHash} = $value->keyPair->publicKey->hash;
}

sub collectKeypair1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 67 "Condensation/CLI/Commands/ShowMessages.pm"
	$o->{keyPairToken} = $value;
	push @{$o->{accountTokens}}, CDS::AccountToken->new($o->{actor}->preferredStore, $value->publicKey->hash);
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 72 "Condensation/CLI/Commands/ShowMessages.pm"
	push @{$o->{accountTokens}}, CDS::AccountToken->new($value, $o->{actorHash});
	delete $o->{actorHash};
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 78 "Condensation/CLI/Commands/ShowMessages.pm"
# END AUTOGENERATED

#line 82 "Condensation/CLI/Commands/ShowMessages.pm"
# HTML FOLDER NAME show-messages
# HTML TITLE Show messages
sub help {
	my $o = shift;
	my $cmd = shift;

#line 85 "Condensation/CLI/Commands/ShowMessages.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds show messages of ACCOUNT');
	$ui->command('cds show messages of ACTOR|KEYPAIR [on STORE]');
	$ui->p('Shows all (unprocessed) messages of an actor ordered by their envelope hash. If store is omitted, the selected store is used.');
	$ui->space;
	$ui->command('cds show messages of ACTORGROUP');
	$ui->p('Shows all messages of all actors of that group.');
	$ui->space;
	$ui->command('cds show messages');
	$ui->p('Shows the messages of the selected key pair on the selected store.');
	$ui->space;
	$ui->command('cds show my messages');
	$ui->p('Shows your messages.');
	$ui->space;
	$ui->command('cds show our messages');
	$ui->p('Shows all messages of your actor group.');
	$ui->space;
	$ui->p('Unprocessed messages are stored in the message box of an actor. Each entry points to an envelope, which in turn points to a record object. The envelope is signed by the sender, but does not hold any date. If the application relies on dates, it must include this date in the message.');
	$ui->space;
	$ui->p('While the envelope hash is stored on the actor\'s store, the envelope and the message are stored on the sender\'s store, and are downloaded from there. Depending on the reachability and responsiveness of that store, messages may not always be accessible.');
	$ui->space;
	$ui->p('Senders typically keep sent messages for about 10 days on their store. After that, the envelope hash may still be in the message box, but the actual message may have vanished.');
	$ui->space;
}

sub showMessagesOfSelected {
	my $o = shift;
	my $cmd = shift;

#line 112 "Condensation/CLI/Commands/ShowMessages.pm"
	$o->{keyPairToken} = $o->{actor}->preferredKeyPairToken;
	$o->processAccounts(CDS::AccountToken->new($o->{actor}->preferredStore, $o->{actor}->preferredActorHash));
}

sub showMyMessages {
	my $o = shift;
	my $cmd = shift;

#line 117 "Condensation/CLI/Commands/ShowMessages.pm"
	$o->{keyPairToken} = $o->{actor}->keyPairToken;
	my $actorHash = $o->{actor}->keyPair->publicKey->hash;
	my $store = $o->{actor}->messagingStore;
	$o->processAccounts(CDS::AccountToken->new($store, $actorHash));
}

sub showOurMessages {
	my $o = shift;
	my $cmd = shift;

#line 124 "Condensation/CLI/Commands/ShowMessages.pm"
	$o->{keyPairToken} = $o->{actor}->keyPairToken;

#line 126 "Condensation/CLI/Commands/ShowMessages.pm"
	my @accountTokens;
	for my $child ($o->{actor}->actorGroupSelector->children) {
		next if $child->child('revoked')->isSet;
		next if ! $child->child('active')->isSet;

#line 131 "Condensation/CLI/Commands/ShowMessages.pm"
		my $record = $child->record;
		my $actorHash = $record->child('hash')->hashValue // next;
		my $storeUrl = $record->child('store')->textValue;
		my $store = $o->{actor}->storeForUrl($storeUrl) // next;
		push @accountTokens, CDS::AccountToken->new($store, $actorHash);
	}

#line 138 "Condensation/CLI/Commands/ShowMessages.pm"
	$o->processAccounts(@accountTokens);
}

sub showMessages {
	my $o = shift;
	my $cmd = shift;

#line 142 "Condensation/CLI/Commands/ShowMessages.pm"
	$o->{accountTokens} = [];
	$cmd->collect($o);

#line 145 "Condensation/CLI/Commands/ShowMessages.pm"
	# Unless a key pair was provided, use the selected key pair
	$o->{keyPairToken} = $o->{actor}->keyPairToken if ! $o->{keyPairToken};

#line 148 "Condensation/CLI/Commands/ShowMessages.pm"
	$o->processAccounts(@{$o->{accountTokens}});
}

sub processAccounts {
	my $o = shift;

#line 152 "Condensation/CLI/Commands/ShowMessages.pm"
	# Initialize the statistics
	$o->{countValid} = 0;
	$o->{countInvalid} = 0;

#line 156 "Condensation/CLI/Commands/ShowMessages.pm"
	# Show the messages of all selected accounts
	for my $accountToken (@_) {
		CDS::Commands::ShowMessages::ProcessAccount->new($o, $accountToken);
	}

#line 161 "Condensation/CLI/Commands/ShowMessages.pm"
	# Show the statistics
	$o->{ui}->space;
	$o->{ui}->title('Total');
	$o->{ui}->line(scalar @_, ' account', scalar @_ == 1 ? '' : 's');
	$o->{ui}->line($o->{countValid}, ' message', $o->{countValid} == 1 ? '' : 's');
	$o->{ui}->line($o->{countInvalid}, ' invalid message', $o->{countInvalid} == 1 ? '' : 's') if $o->{countInvalid};
	$o->{ui}->space;
}

package CDS::Commands::ShowMessages::ProcessAccount;

sub new {
	my $class = shift;
	my $cmd = shift;
	my $accountToken = shift;

#line 2 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	my $o = bless {
		cmd => $cmd,
		accountToken => $accountToken,
		countValid => 0,
		countInvalid => 0,
		};

#line 9 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	$cmd->{ui}->space;
	$cmd->{ui}->title('Messages of ', $cmd->{actor}->blueAccountReference($accountToken));

#line 12 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	# Get the public key
	my $publicKey = $o->getPublicKey // return;

#line 15 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	# Read all messages
	my $publicKeyCache = CDS::PublicKeyCache->new(128);
	my $pool = CDS::MessageBoxReaderPool->new($cmd->{keyPairToken}->keyPair, $publicKeyCache, $o);
	my $reader = CDS::MessageBoxReader->new($pool, CDS::ActorOnStore->new($publicKey, $accountToken->cliStore));
	$reader->read;

#line 21 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	$cmd->{ui}->line($cmd->{ui}->gray('No messages.')) if $o->{countValid} + $o->{countInvalid} == 0;
}

sub getPublicKey {
	my $o = shift;

#line 25 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	# Use the keypair's public key if possible
	return $o->{cmd}->{keyPairToken}->keyPair->publicKey if $o->{accountToken}->actorHash->equals($o->{cmd}->{keyPairToken}->keyPair->publicKey->hash);

#line 28 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	# Retrieve the public key
	return $o->{cmd}->{actor}->uiGetPublicKey($o->{accountToken}->actorHash, $o->{accountToken}->cliStore, $o->{cmd}->{keyPairToken});
}

sub onMessageBoxVerifyStore {
	my $o = shift;
	my $senderStoreUrl = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
	my $senderHash = shift; die 'wrong type '.ref($senderHash).' for $senderHash' if defined $senderHash && ref $senderHash ne 'CDS::Hash';

#line 33 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	return $o->{cmd}->{actor}->storeForUrl($senderStoreUrl);
}

sub onMessageBoxEntry {
	my $o = shift;
	my $message = shift;

#line 37 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	$o->{countValid} += 1;
	$o->{cmd}->{countValid} += 1;

#line 40 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	my $ui = $o->{cmd}->{ui};
	my $sender = CDS::AccountToken->new($message->sender->store, $message->sender->publicKey->hash);

#line 43 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	$ui->space;
	$ui->title($message->source->hash->hex);
	$ui->line('from ', $o->{cmd}->{actor}->blueAccountReference($sender));
	$ui->line('for ', $o->{cmd}->{actor}->blueAccountReference($o->{accountToken}));
	$ui->space;
	$ui->recordChildren($message->content);
}

sub onMessageBoxInvalidEntry {
	my $o = shift;
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';
	my $reason = shift;

#line 52 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	$o->{countInvalid} += 1;
	$o->{cmd}->{countInvalid} += 1;

#line 55 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	my $ui = $o->{cmd}->{ui};
	my $hashHex = $source->hash->hex;
	my $storeReference = $o->{cmd}->{actor}->storeReference($o->{accountToken}->cliStore);

#line 59 "Condensation/CLI/Commands/ShowMessages/ProcessAccount.pm"
	$ui->space;
	$ui->title($hashHex);
	$ui->pOrange($reason);
	$ui->space;
	$ui->p('You may use the following commands to check out the envelope:');
	$ui->line($ui->gold('  cds open envelope ', $hashHex, ' on ', $storeReference));
	$ui->line($ui->gold('  cds show record ', $hashHex, ' on ', $storeReference));
	$ui->line($ui->gold('  cds show hashes and data of ', $hashHex, ' on ', $storeReference));
}

# BEGIN AUTOGENERATED
package CDS::Commands::ShowObject;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/ShowObject.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node005 = CDS::Parser::Node->new(1);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(1);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&show});
	$cds->addArrow($node000, 1, 0, 'show');
	$cds->addArrow($node001, 1, 0, 'show');
	$cds->addArrow($node003, 1, 0, 'show');
	$help->addArrow($node002, 1, 0, 'show');
	$node000->addArrow($node006, 1, 0, 'object', \&collectObject);
	$node001->addArrow($node006, 1, 0, 'record', \&collectRecord);
	$node002->addArrow($node004, 1, 0, 'bytes');
	$node002->addArrow($node004, 1, 0, 'data');
	$node002->addArrow($node004, 1, 0, 'hash');
	$node002->addArrow($node004, 1, 0, 'hashes');
	$node002->addArrow($node004, 1, 0, 'object');
	$node002->addArrow($node004, 1, 0, 'record');
	$node002->addArrow($node004, 1, 0, 'size');
	$node003->addArrow($node005, 1, 0, 'bytes', \&collectBytes);
	$node003->addArrow($node005, 1, 0, 'data', \&collectData);
	$node003->addArrow($node005, 1, 0, 'hash', \&collectHash);
	$node003->addArrow($node005, 1, 0, 'hashes', \&collectHashes);
	$node003->addArrow($node005, 1, 0, 'record', \&collectRecord);
	$node003->addArrow($node005, 1, 0, 'size', \&collectSize);
	$node005->addArrow($node003, 1, 0, 'and');
	$node005->addArrow($node006, 1, 0, 'of');
	$node006->addArrow($node007, 1, 0, 'HASH', \&collectHash1);
	$node006->addArrow($node010, 1, 1, 'FILE', \&collectFile);
	$node006->addArrow($node010, 1, 0, 'HASH', \&collectHash2);
	$node006->addArrow($node010, 1, 0, 'OBJECT', \&collectObject1);
	$node007->addArrow($node008, 1, 0, 'on');
	$node007->addArrow($node009, 0, 0, 'from');
	$node008->addArrow($node010, 1, 0, 'STORE', \&collectStore);
	$node009->addArrow($node010, 0, 0, 'STORE', \&collectStore);
	$node010->addArrow($node011, 1, 0, 'decrypted');
	$node010->addDefault($node013);
	$node011->addArrow($node012, 1, 0, 'with');
	$node012->addArrow($node013, 1, 0, 'AESKEY', \&collectAeskey);
}

sub collectAeskey {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 54 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{aesKey} = $value;
}

sub collectBytes {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 58 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{showBytes} = 1;
}

sub collectData {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 62 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{showData} = 1;
}

sub collectFile {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 66 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{file} = $value;
}

sub collectHash {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 70 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{showHash} = 1;
}

sub collectHash1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 74 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{hash} = $value;
}

sub collectHash2 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 78 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{hash} = $value;
	$o->{store} = $o->{actor}->preferredStore;
}

sub collectHashes {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 83 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{showHashes} = 1;
}

sub collectObject {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 87 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{showHashes} = 1;
	$o->{showData} = 1;
}

sub collectObject1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 92 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{hash} = $value->hash;
	$o->{store} = $value->cliStore;
}

sub collectRecord {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 97 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{showRecord} = 1;
}

sub collectSize {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 101 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{showSize} = 1;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 105 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{store} = $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 110 "Condensation/CLI/Commands/ShowObject.pm"
# END AUTOGENERATED

#line 112 "Condensation/CLI/Commands/ShowObject.pm"
# HTML FOLDER NAME show-object
# HTML TITLE Show objects
sub help {
	my $o = shift;
	my $cmd = shift;

#line 115 "Condensation/CLI/Commands/ShowObject.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds show record OBJECT');
	$ui->command('cds show record HASH on STORE');
	$ui->p('Downloads an object, and shows the containing record. The stores are tried in the order they are indicated, until one succeeds. If the object is not found, or not a valid Condensation object, the program quits with exit code 1.');
	$ui->space;
	$ui->line('The following object properties can be displayed:');
	$ui->line('  cds show hash of …');
	$ui->line('  cds show size of …');
	$ui->line('  cds show bytes of …');
	$ui->line('  cds show hashes of …');
	$ui->line('  cds show data of …');
	$ui->line('  cds show record …');
	$ui->space;
	$ui->p('Multiple properties may be combined with "and", e.g.:');
	$ui->line('  cds show size and hashes and record of …');
	$ui->space;
	$ui->command('cds show record HASH');
	$ui->p('As above, but uses the selected store.');
	$ui->space;
	$ui->command('cds show record FILE');
	$ui->p('As above, but loads the object from FILE rather than from an object store.');
	$ui->space;
	$ui->command('… decrypted with AESKEY');
	$ui->p('Decrypts the object after retrieval.');
	$ui->space;
	$ui->command('cds show object …');
	$ui->p('A shortcut for "cds show hashes and data of …".');
	$ui->space;
	$ui->title('Related commands');
	$ui->line('cds get OBJECT [decrypted with AESKEY]');
	$ui->line('cds save [data of] OBJECT [decrypted with AESKEY] as FILE');
	$ui->line('cds open envelope OBJECT [on STORE] [using KEYPAIR]');
	$ui->line('cds show data tree OBJECT [on STORE]');
	$ui->space;
}

sub show {
	my $o = shift;
	my $cmd = shift;

#line 153 "Condensation/CLI/Commands/ShowObject.pm"
	$cmd->collect($o);

#line 155 "Condensation/CLI/Commands/ShowObject.pm"
	# Get and decrypt the object
	$o->{object} = defined $o->{file} ? $o->loadObjectFromFile : $o->loadObjectFromStore;
	return if ! $o->{object};
	$o->{object} = $o->{object}->crypt($o->{aesKey}) if defined $o->{aesKey};

#line 160 "Condensation/CLI/Commands/ShowObject.pm"
	# Show the desired information
	$o->showHash if $o->{showHash};
	$o->showSize if $o->{showSize};
	$o->showBytes if $o->{showBytes};
	$o->showHashes if $o->{showHashes};
	$o->showData if $o->{showData};
	$o->showRecord if $o->{showRecord};
	$o->{ui}->space;
}

sub loadObjectFromFile {
	my $o = shift;

#line 171 "Condensation/CLI/Commands/ShowObject.pm"
	my $bytes = CDS->readBytesFromFile($o->{file}) // return $o->{ui}->error('Unable to read "', $o->{file}, '".');
	return CDS::Object->fromBytes($bytes) // return $o->{ui}->error('"', $o->{file}, '" does not contain a valid Condensation object.');
}

sub loadObjectFromStore {
	my $o = shift;

#line 176 "Condensation/CLI/Commands/ShowObject.pm"
	return $o->{actor}->uiGetObject($o->{hash}, $o->{store}, $o->{actor}->preferredKeyPairToken);
}

sub loadCommand {
	my $o = shift;

#line 180 "Condensation/CLI/Commands/ShowObject.pm"
	my $decryption = defined $o->{aesKey} ? ' decrypted with '.unpack('H*', $o->{aesKey}) : '';
	return $o->{file}.$decryption if defined $o->{file};
	return $o->{hash}->hex.' on '.$o->{actor}->storeReference($o->{store}).$decryption;
}

sub showHash {
	my $o = shift;

#line 186 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{ui}->space;
	$o->{ui}->title('Object hash');
	$o->{ui}->line($o->{object}->calculateHash->hex);
}

sub showSize {
	my $o = shift;

#line 192 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{ui}->space;
	$o->{ui}->title('Object size');
	$o->{ui}->line($o->{ui}->niceFileSize(length $o->{object}->bytes), ' total (', length $o->{object}->bytes, ' bytes)');
	$o->{ui}->line($o->{object}->hashesCount, ' hashes (', length $o->{object}->header, ' bytes)');
	$o->{ui}->line($o->{ui}->niceFileSize(length $o->{object}->data), ' data (', length $o->{object}->data, ' bytes)');
}

sub showBytes {
	my $o = shift;

#line 200 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{ui}->space;
	my $bytes = $o->{object}->bytes;
	$o->{ui}->title('Object bytes (', $o->{ui}->niceFileSize(length $bytes), ')');
	return if ! length $bytes;

#line 205 "Condensation/CLI/Commands/ShowObject.pm"
	my $hexDump = $o->{ui}->hexDump($bytes);
	my $dataStart = $hexDump->styleHashList(0);
	my $end = $dataStart ? $hexDump->styleRecord($dataStart) : 0;
	$hexDump->changeStyle({at => $end, style => $hexDump->reset});
	$hexDump->display;
}

sub showHashes {
	my $o = shift;

#line 213 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{ui}->space;
	my $hashesCount = $o->{object}->hashesCount;
	$o->{ui}->title($hashesCount == 1 ? '1 hash' : $hashesCount.' hashes');
	my $count = 0;
	for my $hash ($o->{object}->hashes) {
		$o->{ui}->line($o->{ui}->violet(unpack('H4', pack('S>', $count))), '  ', $hash->hex);
		$count += 1;
	}
}

sub showData {
	my $o = shift;

#line 224 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{ui}->space;
	my $data = $o->{object}->data;
	$o->{ui}->title('Data (', $o->{ui}->niceFileSize(length $data), ')');
	return if ! length $data;

#line 229 "Condensation/CLI/Commands/ShowObject.pm"
	my $hexDump = $o->{ui}->hexDump($data);
	my $end = $hexDump->styleRecord(0);
	$hexDump->changeStyle({at => $end, style => $hexDump->reset});
	$hexDump->display;
}

sub showRecord {
	my $o = shift;

#line 236 "Condensation/CLI/Commands/ShowObject.pm"
	# Title
	$o->{ui}->space;
	$o->{ui}->title('Data interpreted as record');

#line 240 "Condensation/CLI/Commands/ShowObject.pm"
	# Empty object (empty record)
	return $o->{ui}->line($o->{ui}->gray('(empty record)')) if ! length $o->{object}->data;

#line 243 "Condensation/CLI/Commands/ShowObject.pm"
	# Record
	my $record = CDS::Record->new;
	my $reader = CDS::RecordReader->new($o->{object});
	$reader->readChildren($record);
	if ($reader->hasError) {
		$o->{ui}->pRed('This is not a record.');
		$o->{ui}->space;
		$o->{ui}->p('You may use one of the following commands to check out the content:');
		$o->{ui}->line($o->{ui}->gold('  cds show object ', $o->loadCommand));
		$o->{ui}->line($o->{ui}->gold('  cds show data of ', $o->loadCommand));
		$o->{ui}->line($o->{ui}->gold('  cds save data of ', $o->loadCommand, ' as FILENAME'));
		return;
	}

#line 257 "Condensation/CLI/Commands/ShowObject.pm"
	$o->{ui}->recordChildren($record, $o->{store} ? $o->{actor}->blueStoreReference($o->{store}) : '');

#line 259 "Condensation/CLI/Commands/ShowObject.pm"
	# Trailer
	my $trailer = $reader->trailer;
	if (length $trailer) {
		$o->{ui}->space;
		$o->{ui}->pRed('This is probably not a record, because ', length $trailer, ' bytes remain behind the record. Use "cds show data of …" to investigate the raw object content. If this object is encrypted, provide the decryption key using "… and decrypted with KEY".');
		$o->{ui}->space;
	}
}

# BEGIN AUTOGENERATED
package CDS::Commands::ShowPrivateData;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/ShowPrivateData.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node013 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showGroupData});
	my $node014 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showLocalData});
	my $node015 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showSentList});
	my $node016 = CDS::Parser::Node->new(0);
	my $node017 = CDS::Parser::Node->new(0);
	my $node018 = CDS::Parser::Node->new(0);
	my $node019 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showSentList});
	$cds->addArrow($node006, 1, 0, 'show');
	$cds->addArrow($node007, 1, 0, 'show');
	$cds->addArrow($node008, 1, 0, 'show');
	$help->addArrow($node000, 1, 0, 'show');
	$help->addArrow($node001, 1, 0, 'show');
	$help->addArrow($node002, 1, 0, 'show');
	$node000->addArrow($node003, 1, 0, 'group');
	$node001->addArrow($node004, 1, 0, 'local');
	$node002->addArrow($node005, 1, 0, 'sent');
	$node003->addArrow($node012, 1, 0, 'data');
	$node004->addArrow($node012, 1, 0, 'data');
	$node005->addArrow($node012, 1, 0, 'list');
	$node006->addArrow($node009, 1, 0, 'group');
	$node007->addArrow($node010, 1, 0, 'local');
	$node008->addArrow($node011, 1, 0, 'sent');
	$node009->addArrow($node013, 1, 0, 'data');
	$node010->addArrow($node014, 1, 0, 'data');
	$node011->addArrow($node015, 1, 0, 'list');
	$node015->addArrow($node016, 1, 0, 'ordered');
	$node016->addArrow($node017, 1, 0, 'by');
	$node017->addArrow($node018, 1, 0, 'envelope');
	$node017->addArrow($node019, 1, 0, 'date', \&collectDate);
	$node017->addArrow($node019, 1, 0, 'id', \&collectId);
	$node018->addArrow($node019, 1, 0, 'hash', \&collectHash);
}

sub collectDate {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 51 "Condensation/CLI/Commands/ShowPrivateData.pm"
	$o->{orderedBy} = 'date';
}

sub collectHash {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 55 "Condensation/CLI/Commands/ShowPrivateData.pm"
	$o->{orderedBy} = 'envelope hash';
}

sub collectId {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 59 "Condensation/CLI/Commands/ShowPrivateData.pm"
	$o->{orderedBy} = 'id';
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 64 "Condensation/CLI/Commands/ShowPrivateData.pm"
# END AUTOGENERATED

#line 66 "Condensation/CLI/Commands/ShowPrivateData.pm"
# HTML FOLDER NAME show-private-data
# HTML TITLE Show the private data
sub help {
	my $o = shift;
	my $cmd = shift;

#line 69 "Condensation/CLI/Commands/ShowPrivateData.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds show group data');
	$ui->p('Shows the group data tree. This data tree is shared among all group members.');
	$ui->space;
	$ui->command('cds show local data');
	$ui->p('Shows the local data tree. This data tree is stored locally, and private to this actor.');
	$ui->space;
	$ui->command('cds show sent list');
	$ui->p('Shows the list of sent messages with their expiry date, envelope hash, and content hash.');
	$ui->space;
	$ui->command('… ordered by id');
	$ui->command('… ordered by date');
	$ui->command('… ordered by envelope hash');
	$ui->p('Sorts the list accordingly. By default, the list is sorted by id.');
	$ui->space;
}

sub showGroupData {
	my $o = shift;
	my $cmd = shift;

#line 88 "Condensation/CLI/Commands/ShowPrivateData.pm"
	$o->{ui}->space;
	$o->{ui}->selector($o->{actor}->groupRoot, 'Group data');
	$o->{ui}->space;
}

sub showLocalData {
	my $o = shift;
	my $cmd = shift;

#line 94 "Condensation/CLI/Commands/ShowPrivateData.pm"
	$o->{ui}->space;
	$o->{ui}->selector($o->{actor}->localRoot, 'Local data');
	$o->{ui}->space;
}

sub showSentList {
	my $o = shift;
	my $cmd = shift;

#line 100 "Condensation/CLI/Commands/ShowPrivateData.pm"
	$o->{orderedBy} = 'id';
	$cmd->collect($o);

#line 103 "Condensation/CLI/Commands/ShowPrivateData.pm"
	$o->{ui}->space;
	$o->{ui}->title('Sent list');

#line 106 "Condensation/CLI/Commands/ShowPrivateData.pm"
	$o->{actor}->procureSentList // return;
	my $sentList = $o->{actor}->sentList;
	my @items = sort { $a->id cmp $b->id } values %{$sentList->{items}};
	@items = sort { $a->envelopeHashBytes cmp $b->envelopeHashBytes } @items if $o->{orderedBy} eq 'envelope hash';
	@items = sort { $a->validUntil <=> $b->validUntil } @items if $o->{orderedBy} eq 'date';
	my $noHash = '-' x 64;
	for my $item (@items) {
		my $id = $item->id;
		my $envelopeHash = $item->envelopeHash;
		my $message = $item->message;
		my $label = $o->{ui}->niceBytes($id, 32);
		$o->{ui}->line($o->{ui}->gray($o->{ui}->niceDateTimeLocal($item->validUntil)), ' ', $envelopeHash ? $envelopeHash->hex : $noHash, ' ', $o->{ui}->blue($label));
		$o->{ui}->recordChildren($message);
	}

#line 121 "Condensation/CLI/Commands/ShowPrivateData.pm"
	$o->{ui}->space;
}

# BEGIN AUTOGENERATED
package CDS::Commands::ShowTree;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/ShowTree.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showTree});
	$cds->addArrow($node001, 1, 0, 'show');
	$cds->addArrow($node002, 0, 0, 'show');
	$help->addArrow($node000, 1, 0, 'show');
	$node000->addArrow($node003, 1, 0, 'tree');
	$node001->addArrow($node004, 1, 0, 'tree');
	$node002->addArrow($node004, 0, 0, 'trees');
	$node004->addDefault($node005);
	$node004->addDefault($node006);
	$node004->addDefault($node007);
	$node005->addArrow($node005, 1, 0, 'HASH', \&collectHash);
	$node005->addArrow($node010, 1, 0, 'HASH', \&collectHash);
	$node006->addArrow($node006, 1, 0, 'HASH', \&collectHash);
	$node006->addArrow($node008, 1, 0, 'HASH', \&collectHash);
	$node007->addArrow($node007, 1, 0, 'OBJECT', \&collectObject);
	$node007->addArrow($node010, 1, 0, 'OBJECT', \&collectObject);
	$node008->addArrow($node009, 1, 0, 'on');
	$node009->addArrow($node010, 1, 0, 'STORE', \&collectStore);
}

sub collectHash {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 35 "Condensation/CLI/Commands/ShowTree.pm"
	push @{$o->{hashes}}, $value;
}

sub collectObject {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 39 "Condensation/CLI/Commands/ShowTree.pm"
	push @{$o->{objectTokens}}, $value;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 43 "Condensation/CLI/Commands/ShowTree.pm"
	$o->{store} = $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 48 "Condensation/CLI/Commands/ShowTree.pm"
# END AUTOGENERATED

#line 50 "Condensation/CLI/Commands/ShowTree.pm"
# HTML FOLDER NAME show-tree
# HTML TITLE Show trees
sub help {
	my $o = shift;
	my $cmd = shift;

#line 53 "Condensation/CLI/Commands/ShowTree.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds show tree OBJECT*');
	$ui->command('cds show tree HASH* on STORE');
	$ui->p('Downloads a tree, and shows the tree hierarchy. If an object has been traversed before, it is listed as "reported above".');
	$ui->space;
	$ui->command('cds show tree HASH*');
	$ui->p('As above, but uses the selected store.');
	$ui->space;
}

sub showTree {
	my $o = shift;
	my $cmd = shift;

#line 65 "Condensation/CLI/Commands/ShowTree.pm"
	$o->{keyPairToken} = $o->{actor}->preferredKeyPairToken;
	$o->{objectTokens} = [];
	$o->{hashes} = [];
	$cmd->collect($o);

#line 70 "Condensation/CLI/Commands/ShowTree.pm"
	# Process all trees
	for my $objectToken (@{$o->{objectTokens}}) {
		$o->{ui}->space;
		$o->process($objectToken->hash, $objectToken->cliStore);
	}

#line 76 "Condensation/CLI/Commands/ShowTree.pm"
	if (scalar @{$o->{hashes}}) {
		my $store = $o->{store} // $o->{actor}->preferredStore;
		for my $hash (@{$o->{hashes}}) {
			$o->{ui}->space;
			$o->process($hash, $store);
		}
	}

#line 84 "Condensation/CLI/Commands/ShowTree.pm"
	# Report the total size
	my $totalSize = 0;
	my $totalDataSize = 0;
	map { $totalSize += $_->{size} ; $totalDataSize += $_->{dataSize} } values %{$o->{objects}};
	$o->{ui}->space;
	$o->{ui}->p(scalar keys %{$o->{objects}}, ' unique objects ', $o->{ui}->bold($o->{ui}->niceFileSize($totalSize)), $o->{ui}->gray(' (', $o->{ui}->niceFileSize($totalSize - $totalDataSize), ' header and ', $o->{ui}->niceFileSize($totalDataSize), ' data)'));
	$o->{ui}->pRed(scalar keys %{$o->{missingObjects}}, ' or more objects are missing') if scalar keys %{$o->{missingObjects}};
	$o->{ui}->space;
}

sub process {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $store = shift;

#line 95 "Condensation/CLI/Commands/ShowTree.pm"
	my $hashHex = $hash->hex;

#line 97 "Condensation/CLI/Commands/ShowTree.pm"
	# Check if we retrieved this object before
	if (exists $o->{objects}->{$hashHex}) {
		$o->{ui}->line($hash->hex, ' reported above') ;
		return 1;
	}

#line 103 "Condensation/CLI/Commands/ShowTree.pm"
	# Retrieve the object
	my ($object, $storeError) = $store->get($hash, $o->{keyPairToken}->keyPair);
	return if defined $storeError;

#line 107 "Condensation/CLI/Commands/ShowTree.pm"
	if (! $object) {
		$o->{missingObjects}->{$hashHex} = 1;
		return $o->{ui}->line($hashHex, ' ', $o->{ui}->red('is missing'));
	}

#line 112 "Condensation/CLI/Commands/ShowTree.pm"
	# Display
	my $size = $object->byteLength;
	$o->{objects}->{$hashHex} = {size => $size, dataSize => length $object->data};
	$o->{ui}->line($hashHex, ' ', $o->{ui}->bold($o->{ui}->niceFileSize($size)), ' ', $o->{ui}->gray($object->hashesCount, ' hashes'));

#line 117 "Condensation/CLI/Commands/ShowTree.pm"
	# Process all children
	$o->{ui}->pushIndent;
	foreach my $hash ($object->hashes) {
		$o->process($hash, $store) // return;
	}
	$o->{ui}->popIndent;
	return 1;
}

# BEGIN AUTOGENERATED
package CDS::Commands::StartHTTPServer;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/StartHTTPServer.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(1);
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(1);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(0);
	my $node014 = CDS::Parser::Node->new(0);
	my $node015 = CDS::Parser::Node->new(0);
	my $node016 = CDS::Parser::Node->new(1);
	my $node017 = CDS::Parser::Node->new(0);
	my $node018 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&startHttpServer});
	$cds->addArrow($node001, 1, 0, 'start');
	$help->addArrow($node000, 1, 0, 'http');
	$node000->addArrow($node005, 1, 0, 'server');
	$node001->addArrow($node002, 1, 0, 'http');
	$node002->addArrow($node003, 1, 0, 'server');
	$node003->addArrow($node004, 1, 0, 'for');
	$node004->addArrow($node006, 1, 0, 'STORE', \&collectStore);
	$node006->addArrow($node007, 1, 0, 'on');
	$node007->addArrow($node008, 1, 0, 'port');
	$node008->addArrow($node009, 1, 0, 'PORT', \&collectPort);
	$node009->addArrow($node010, 1, 0, 'at');
	$node009->addDefault($node011);
	$node010->addArrow($node011, 1, 0, 'TEXT', \&collectText);
	$node011->addArrow($node012, 1, 0, 'with');
	$node011->addDefault($node016);
	$node012->addArrow($node013, 1, 0, 'static');
	$node013->addArrow($node014, 1, 0, 'files');
	$node014->addArrow($node015, 1, 0, 'from');
	$node015->addArrow($node016, 1, 0, 'FOLDER', \&collectFolder);
	$node016->addArrow($node017, 1, 0, 'for');
	$node016->addDefault($node018);
	$node017->addArrow($node018, 1, 0, 'everybody', \&collectEverybody);
}

sub collectEverybody {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 48 "Condensation/CLI/Commands/StartHTTPServer.pm"
	$o->{corsAllowEverybody} = 1;
}

sub collectFolder {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 52 "Condensation/CLI/Commands/StartHTTPServer.pm"
	$o->{staticFolder} = $value;
}

sub collectPort {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 56 "Condensation/CLI/Commands/StartHTTPServer.pm"
	$o->{port} = $value;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 60 "Condensation/CLI/Commands/StartHTTPServer.pm"
	$o->{store} = $value;
}

sub collectText {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 64 "Condensation/CLI/Commands/StartHTTPServer.pm"
	$o->{root} = $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 69 "Condensation/CLI/Commands/StartHTTPServer.pm"
# END AUTOGENERATED

#line 73 "Condensation/CLI/Commands/StartHTTPServer.pm"
# HTML FOLDER NAME start-http-server
# HTML TITLE HTTP store server
sub help {
	my $o = shift;
	my $cmd = shift;

#line 76 "Condensation/CLI/Commands/StartHTTPServer.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds start http server for STORE on port PORT');
	$ui->p('Starts a simple HTTP server listening on port PORT. The server handles requests within /objects and /accounts, and uses STORE as backend. Requests on the root URL (/) deliver a short message.');
	$ui->p('You may need superuser (root) privileges to use the default HTTP port 80.');
	$ui->p('This server is very useful for small to medium-size projects, but not particularly efficient for large-scale applications. It makes no effort to use DMA or similar features to speed up delivery, and handles only one request at a time (single-threaded). However, when using a front-end web server with load-balancing capabilities, multiple HTTP servers for the same store may be started to handle multiple requests in parallel.');
	$ui->space;
	$ui->command('… at TEXT');
	$ui->p('As above, but makes the store accessible at /TEXT/objects and /TEXT/accounts.');
	$ui->space;
	$ui->command('… with static files from FOLDER');
	$ui->p('Delivers static files from FOLDER for URLs outside of /objects and /accounts. This is useful for self-contained web apps.');
	$ui->space;
	$ui->command('… for everybody');
	$ui->p('Sets CORS headers to allow everybody to access the store from within a web browser.');
	$ui->space;
	$ui->p('For more options, write a Perl script instantiating and configuring a CDS::HTTPServer.');
	$ui->space;
}

sub startHttpServer {
	my $o = shift;
	my $cmd = shift;

#line 97 "Condensation/CLI/Commands/StartHTTPServer.pm"
	$cmd->collect($o);

#line 99 "Condensation/CLI/Commands/StartHTTPServer.pm"
	my $httpServer = CDS::HTTPServer->new($o->{port});
	$httpServer->setLogger(CDS::Commands::StartHTTPServer::Logger->new($o->{ui}));
	$httpServer->setCorsAllowEverybody($o->{corsAllowEverybody});
	$httpServer->addHandler(CDS::HTTPServer::StoreHandler->new($o->{root} // '/', $o->{store}));
	$httpServer->addHandler(CDS::HTTPServer::IdentificationHandler->new($o->{root} // '/')) if ! defined $o->{staticFolder};
	$httpServer->addHandler(CDS::HTTPServer::StaticFilesHandler->new('/', $o->{staticFolder}, 'index.html')) if defined $o->{staticFolder};
	eval { $httpServer->run; };
	if ($@) {
		my $error = $@;
		$error = $1 if $error =~ /^(.*?)( at |\n)/;
		$o->{ui}->space;
		$o->{ui}->p('Failed to run server on port '.$o->{port}.': '.$error);
		$o->{ui}->space;
	}
}

package CDS::Commands::StartHTTPServer::Logger;

sub new {
	my $class = shift;
	my $ui = shift;

#line 2 "Condensation/CLI/Commands/StartHTTPServer/Logger.pm"
	return bless {ui => $ui};
}

sub onServerStarts {
	my $o = shift;
	my $port = shift;

#line 6 "Condensation/CLI/Commands/StartHTTPServer/Logger.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->line($o->{ui}->gray($ui->niceDateTimeLocal), '  ', $ui->green('Server ready at http://localhost:', $port));
}

sub onRequestStarts {
	my $o = shift;
	my $request = shift;
	 }

sub onRequestError {
	my $o = shift;
	my $request = shift;

#line 14 "Condensation/CLI/Commands/StartHTTPServer/Logger.pm"
	my $ui = $o->{ui};
	$ui->line($o->{ui}->gray($ui->niceDateTimeLocal), '  ', $ui->blue($ui->left(15, $request->peerAddress)), '  ', $request->method, ' ', $request->path, '  ', $ui->red(@_));
}

sub onRequestDone {
	my $o = shift;
	my $request = shift;
	my $responseCode = shift;

#line 19 "Condensation/CLI/Commands/StartHTTPServer/Logger.pm"
	my $ui = $o->{ui};
	$ui->line($o->{ui}->gray($ui->niceDateTimeLocal), '  ', $ui->blue($ui->left(15, $request->peerAddress)), '  ', $request->method, ' ', $request->path, '  ', $ui->bold($responseCode));
}

# BEGIN AUTOGENERATED
package CDS::Commands::Transfer;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/Transfer.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(1);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&transfer});
	$cds->addArrow($node000, 1, 0, 'thoroughly');
	$cds->addArrow($node001, 0, 0, 'leniently');
	$cds->addDefault($node003);
	$cds->addArrow($node003, 1, 0, 'leniently', \&collectLeniently);
	$cds->addArrow($node003, 1, 0, 'thoroughly', \&collectThoroughly);
	$help->addArrow($node002, 1, 0, 'transfer');
	$node000->addArrow($node003, 1, 0, 'leniently', \&collectLeniently1);
	$node001->addArrow($node003, 0, 0, 'thoroughly', \&collectLeniently1);
	$node003->addArrow($node004, 1, 0, 'transfer');
	$node004->addDefault($node005);
	$node004->addDefault($node006);
	$node004->addDefault($node007);
	$node005->addArrow($node005, 1, 0, 'HASH', \&collectHash);
	$node005->addArrow($node010, 1, 0, 'HASH', \&collectHash);
	$node006->addArrow($node006, 1, 0, 'OBJECT', \&collectObject);
	$node006->addArrow($node010, 1, 0, 'OBJECT', \&collectObject);
	$node007->addArrow($node007, 1, 0, 'HASH', \&collectHash);
	$node007->addArrow($node008, 1, 0, 'HASH', \&collectHash);
	$node008->addArrow($node009, 1, 0, 'from');
	$node009->addArrow($node010, 1, 0, 'STORE', \&collectStore);
	$node010->addArrow($node011, 1, 0, 'to');
	$node011->addArrow($node011, 1, 0, 'STORE', \&collectStore1);
	$node011->addArrow($node012, 1, 0, 'STORE', \&collectStore1);
}

sub collectHash {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 43 "Condensation/CLI/Commands/Transfer.pm"
	push @{$o->{hashes}}, $value;
}

sub collectLeniently {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 47 "Condensation/CLI/Commands/Transfer.pm"
	$o->{leniently} = 1;
}

sub collectLeniently1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 51 "Condensation/CLI/Commands/Transfer.pm"
	$o->{leniently} = 1;
	$o->{thoroughly} = 1;
}

sub collectObject {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 56 "Condensation/CLI/Commands/Transfer.pm"
	push @{$o->{objectTokens}}, $value;
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 60 "Condensation/CLI/Commands/Transfer.pm"
	$o->{fromStore} = $value;
}

sub collectStore1 {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 64 "Condensation/CLI/Commands/Transfer.pm"
	push @{$o->{toStores}}, $value;
}

sub collectThoroughly {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 68 "Condensation/CLI/Commands/Transfer.pm"
	$o->{thoroughly} = 1;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 73 "Condensation/CLI/Commands/Transfer.pm"
# END AUTOGENERATED

#line 75 "Condensation/CLI/Commands/Transfer.pm"
# HTML FOLDER NAME transfer
# HTML TITLE Transfer
sub help {
	my $o = shift;
	my $cmd = shift;

#line 78 "Condensation/CLI/Commands/Transfer.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds transfer OBJECT* to STORE*');
	$ui->command('cds transfer HASH* from STORE to STORE*');
	$ui->p('Copies a tree from one store to another.');
	$ui->space;
	$ui->command('cds transfer HASH* to STORE*');
	$ui->p('As above, but uses the selected store as source store.');
	$ui->space;
	$ui->command('cds ', $ui->underlined('leniently'), ' transfer …');
	$ui->p('Warns about missing objects, but ignores them and proceeds with the rest.');
	$ui->space;
	$ui->command('cds ', $ui->underlined('thoroughly'), ' transfer …');
	$ui->p('Check subtrees of objects existing at the destination. This may be used to fix missing objects on the destination store.');
	$ui->space;
}

sub transfer {
	my $o = shift;
	my $cmd = shift;

#line 96 "Condensation/CLI/Commands/Transfer.pm"
	$o->{keyPairToken} = $o->{actor}->preferredKeyPairToken;
	$o->{objectTokens} = [];
	$o->{hashes} = [];
	$o->{toStores} = [];
	$cmd->collect($o);

#line 102 "Condensation/CLI/Commands/Transfer.pm"
	# Use the selected store
	$o->{fromStore} = $o->{actor}->preferredStore if scalar @{$o->{hashes}} && ! $o->{fromStore};

#line 105 "Condensation/CLI/Commands/Transfer.pm"
	# Prepare the destination stores
	my $toStores = [];
	for my $toStore (@{$o->{toStores}}) {
		push @$toStores, {store => $toStore, storeError => undef, needed => [1]};
	}

#line 111 "Condensation/CLI/Commands/Transfer.pm"
	# Print the stores
	$o->{ui}->space;
	my $n = scalar @$toStores;
	for my $i (0 .. $n - 1) {
		my $toStore = $toStores->[$i];
		$o->{ui}->line($o->{ui}->gray(' │' x $i, ' ┌', '──' x ($n - $i), ' ', $toStore->{store}->url));
	}

#line 119 "Condensation/CLI/Commands/Transfer.pm"
	# Process all trees
	$o->{objects} = {};
	$o->{missingObjects} = {};
	for my $objectToken (@{$o->{objectTokens}}) {
		$o->{ui}->line($o->{ui}->gray(' │' x $n));
		$o->process($objectToken->hash, $objectToken->cliStore, $toStores, 1);
	}
	for my $hash (@{$o->{hashes}}) {
		$o->{ui}->line($o->{ui}->gray(' │' x $n));
		$o->process($hash, $o->{fromStore}, $toStores, 1);
	}

#line 131 "Condensation/CLI/Commands/Transfer.pm"
	# Print the stores again, with their errors
	$o->{ui}->line($o->{ui}->gray(' │' x $n));
	for my $i (reverse 0 .. $n - 1) {
		my $toStore = $toStores->[$i];
		$o->{ui}->line($o->{ui}->gray(' │' x $i, ' └', '──' x ($n - $i), ' ', $toStore->{store}->url), ' ', defined $toStore->{storeError} ? $o->{ui}->red($toStore->{storeError}) : '');
	}

#line 138 "Condensation/CLI/Commands/Transfer.pm"
	# Report the total size
	my $totalSize = 0;
	my $totalDataSize = 0;
	map { $totalSize += $_->{size} ; $totalDataSize += $_->{dataSize} } values %{$o->{objects}};
	$o->{ui}->space;
	$o->{ui}->p(scalar keys %{$o->{objects}}, ' unique objects ', $o->{ui}->bold($o->{ui}->niceFileSize($totalSize)), ' ', $o->{ui}->gray($o->{ui}->niceFileSize($totalDataSize), ' data'));
	$o->{ui}->pOrange(scalar keys %{$o->{missingObjects}}, ' or more objects are missing') if scalar keys %{$o->{missingObjects}};
	$o->{ui}->space;
}

sub process {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $fromStore = shift;
	my $toStores = shift;
	my $depth = shift;

#line 149 "Condensation/CLI/Commands/Transfer.pm"
	my $hashHex = $hash->hex;
	my $keyPair = $o->{keyPairToken}->keyPair;

#line 152 "Condensation/CLI/Commands/Transfer.pm"
	# Check if we retrieved this object before
	if (exists $o->{objects}->{$hashHex}) {
		$o->report($hash->hex, $toStores, $depth, $o->{ui}->green('copied before'));
		return 1;
	}

#line 158 "Condensation/CLI/Commands/Transfer.pm"
	# Try to book the object on all active stores
	my $countNeeded = 0;
	my $hasActiveStore = 0;
	for my $toStore (@$toStores) {
		next if defined $toStore->{storeError};
		$hasActiveStore = 1;
		next if ! $o->{thoroughly} && ! $toStore->{needed}->[$depth - 1];

#line 166 "Condensation/CLI/Commands/Transfer.pm"
		my ($found, $bookError) = $toStore->{store}->book($hash);
		if (defined $bookError) {
			$toStore->{storeError} = $bookError;
			next;
		}

#line 172 "Condensation/CLI/Commands/Transfer.pm"
		next if $found;
		$toStore->{needed}->[$depth] = 1;
		$countNeeded += 1;
	}

#line 177 "Condensation/CLI/Commands/Transfer.pm"
	# Return if all stores reported an error
	return if ! $hasActiveStore;

#line 180 "Condensation/CLI/Commands/Transfer.pm"
	# Ignore existing subtrees at the destination unless "thoroughly" is set
	if (! $o->{thoroughly} && ! $countNeeded) {
		$o->report($hashHex, $toStores, $depth, $o->{ui}->gray('skipping subtree'));
		return 1;
	}

#line 186 "Condensation/CLI/Commands/Transfer.pm"
	# Retrieve the object
	my ($object, $getError) = $fromStore->get($hash, $keyPair);
	return if defined $getError;

#line 190 "Condensation/CLI/Commands/Transfer.pm"
	if (! defined $object) {
		$o->{missingObjects}->{$hashHex} = 1;
		$o->report($hashHex, $toStores, $depth, $o->{ui}->orange('is missing'));
		return if ! $o->{leniently};
	}

#line 196 "Condensation/CLI/Commands/Transfer.pm"
	# Display
	my $size = $object->byteLength;
	$o->{objects}->{$hashHex} = {needed => $countNeeded, size => $size, dataSize => length $object->data};
	$o->report($hashHex, $toStores, $depth, $o->{ui}->bold($o->{ui}->niceFileSize($size)), ' ', $o->{ui}->gray($object->hashesCount, ' hashes'));

#line 201 "Condensation/CLI/Commands/Transfer.pm"
	# Process all children
	foreach my $hash ($object->hashes) {
		$o->process($hash, $fromStore, $toStores, $depth + 1) // return;
	}

#line 206 "Condensation/CLI/Commands/Transfer.pm"
	# Write the object to all active stores
	for my $toStore (@$toStores) {
		next if defined $toStore->{storeError};
		next if ! $toStore->{needed}->[$depth];
		my $putError = $toStore->{store}->put($hash, $object, $keyPair);
		$toStore->{storeError} = $putError if $putError;
	}

#line 214 "Condensation/CLI/Commands/Transfer.pm"
	return 1;
}

sub report {
	my $o = shift;
	my $hashHex = shift;
	my $toStores = shift;
	my $depth = shift;

#line 218 "Condensation/CLI/Commands/Transfer.pm"
	my @text;
	for my $toStore (@$toStores) {
		if ($toStore->{storeError}) {
			push @text, $o->{ui}->red(' ⨯');
		} elsif ($toStore->{needed}->[$depth]) {
			push @text, $o->{ui}->green(' +');
		} else {
			push @text, $o->{ui}->green(' ‒');
		}
	}

#line 229 "Condensation/CLI/Commands/Transfer.pm"
	push @text, ' ', '  ' x ($depth - 1), $hashHex;
	push @text, ' ', @_;
	$o->{ui}->line(@text);
}

# BEGIN AUTOGENERATED
package CDS::Commands::UseCache;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/UseCache.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node004 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&useCache});
	my $node005 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&dropCache});
	my $node006 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&cache});
	$cds->addArrow($node000, 1, 0, 'use');
	$cds->addArrow($node002, 1, 0, 'drop');
	$cds->addArrow($node006, 1, 0, 'cache');
	$help->addArrow($node003, 1, 0, 'cache');
	$node000->addArrow($node001, 1, 0, 'cache');
	$node001->addArrow($node004, 1, 0, 'STORE', \&collectStore);
	$node002->addArrow($node005, 1, 0, 'cache');
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 21 "Condensation/CLI/Commands/UseCache.pm"
	$o->{store} = $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 26 "Condensation/CLI/Commands/UseCache.pm"
# END AUTOGENERATED

#line 28 "Condensation/CLI/Commands/UseCache.pm"
# HTML FOLDER NAME use-cache
# HTML TITLE Using a cache store
sub help {
	my $o = shift;
	my $cmd = shift;

#line 31 "Condensation/CLI/Commands/UseCache.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds use cache STORE');
	$ui->p('Uses STORE to cache objects, and speed up subsequent requests of the same object. This is particularly useful when working with (slow) remote stores. The cache store should be a fast store, such as a local folder store or an in-memory store.');
	$ui->p('Cached objects are not linked to any account, and may disappear with the next garbage collection. Most stores however keep objects for a least a few hours after their last use.');
	$ui->space;
	$ui->command('cds drop cache');
	$ui->p('Stops using the cache.');
	$ui->space;
	$ui->command('cds cache');
	$ui->p('Shows which cache store is used (if any).');
	$ui->space;
}

sub useCache {
	my $o = shift;
	my $cmd = shift;

#line 46 "Condensation/CLI/Commands/UseCache.pm"
	$cmd->collect($o);

#line 48 "Condensation/CLI/Commands/UseCache.pm"
	$o->{actor}->sessionRoot->child('use cache')->setText($o->{store}->url);
	$o->{actor}->saveOrShowError // return;
	$o->{ui}->pGreen('Using store "', $o->{store}->url, '" to cache objects.');
}

sub dropCache {
	my $o = shift;
	my $cmd = shift;

#line 54 "Condensation/CLI/Commands/UseCache.pm"
	$o->{actor}->sessionRoot->child('use cache')->clear;
	$o->{actor}->saveOrShowError // return;
	$o->{ui}->pGreen('Not using any cache any more.');
}

sub cache {
	my $o = shift;
	my $cmd = shift;

#line 60 "Condensation/CLI/Commands/UseCache.pm"
	my $storeUrl = $o->{actor}->sessionRoot->child('use cache')->textValue;
	return $o->{ui}->line('Not using any cache.') if ! length $storeUrl;
	return $o->{ui}->line('Using store "', $storeUrl, '" to cache objects.');
}

# BEGIN AUTOGENERATED
package CDS::Commands::UseStore;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/UseStore.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node005 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&useStoreForMessaging});
	$cds->addArrow($node001, 1, 0, 'use');
	$help->addArrow($node000, 1, 0, 'messaging');
	$node000->addArrow($node004, 1, 0, 'store');
	$node001->addArrow($node002, 1, 0, 'STORE', \&collectStore);
	$node002->addArrow($node003, 1, 0, 'for');
	$node003->addArrow($node005, 1, 0, 'messaging');
}

sub collectStore {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 19 "Condensation/CLI/Commands/UseStore.pm"
	$o->{store} = $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 24 "Condensation/CLI/Commands/UseStore.pm"
# END AUTOGENERATED

#line 26 "Condensation/CLI/Commands/UseStore.pm"
# HTML FOLDER NAME use-store
# HTML TITLE Set the messaging store
sub help {
	my $o = shift;
	my $cmd = shift;

#line 29 "Condensation/CLI/Commands/UseStore.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds use STORE for messaging');
	$ui->p('Uses STORE to send and receive messages.');
	$ui->space;
}

sub useStoreForMessaging {
	my $o = shift;
	my $cmd = shift;

#line 37 "Condensation/CLI/Commands/UseStore.pm"
	$cmd->collect($o);

#line 39 "Condensation/CLI/Commands/UseStore.pm"
	$o->{actor}->{configuration}->setMessagingStoreUrl($o->{store}->url);
	$o->{ui}->pGreen('The messaging store is now ', $o->{store}->url);
}

# BEGIN AUTOGENERATED
package CDS::Commands::Welcome;

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 4 "Condensation/CLI/Commands/Welcome.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node007 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&suppress});
	my $node008 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&enable});
	my $node009 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&show});
	$cds->addArrow($node000, 1, 0, 'suppress');
	$cds->addArrow($node002, 1, 0, 'enable');
	$cds->addArrow($node004, 1, 0, 'show');
	$help->addArrow($node006, 1, 0, 'welcome');
	$node000->addArrow($node001, 1, 0, 'welcome');
	$node001->addArrow($node007, 1, 0, 'message');
	$node002->addArrow($node003, 1, 0, 'welcome');
	$node003->addArrow($node008, 1, 0, 'message');
	$node004->addArrow($node005, 1, 0, 'welcome');
	$node005->addArrow($node009, 1, 0, 'message');
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 28 "Condensation/CLI/Commands/Welcome.pm"
# END AUTOGENERATED

#line 30 "Condensation/CLI/Commands/Welcome.pm"
# HTML FOLDER NAME welcome
# HTML TITLE Welcome message
sub help {
	my $o = shift;
	my $cmd = shift;

#line 33 "Condensation/CLI/Commands/Welcome.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds suppress welcome message');
	$ui->p('Suppresses the welcome message when typing "cds".');
	$ui->space;
	$ui->command('cds enable welcome message');
	$ui->p('Enables the welcome message when typing "cds".');
	$ui->space;
	$ui->command('cds show welcome message');
	$ui->p('Shows the welcome message.');
	$ui->space;
}

sub suppress {
	my $o = shift;
	my $cmd = shift;

#line 47 "Condensation/CLI/Commands/Welcome.pm"
	$o->{actor}->localRoot->child('suppress welcome message')->setBoolean(1);
	$o->{actor}->saveOrShowError // return;

#line 50 "Condensation/CLI/Commands/Welcome.pm"
	$o->{ui}->space;
	$o->{ui}->p('The welcome message will not be shown any more.');
	$o->{ui}->space;
	$o->{ui}->line('You can manually display the message by typing:');
	$o->{ui}->line($o->{ui}->blue('  cds show welcome message'));
	$o->{ui}->line('or re-enable it using:');
	$o->{ui}->line($o->{ui}->blue('  cds enable welcome message'));
	$o->{ui}->space;
}

sub enable {
	my $o = shift;
	my $cmd = shift;

#line 61 "Condensation/CLI/Commands/Welcome.pm"
	$o->{actor}->localRoot->child('suppress welcome message')->clear;
	$o->{actor}->saveOrShowError // return;

#line 64 "Condensation/CLI/Commands/Welcome.pm"
	$o->{ui}->space;
	$o->{ui}->p('The welcome message will be shown when you type "cds".');
	$o->{ui}->space;
}

sub isEnabled {
	my $o = shift;
	 ! $o->{actor}->localRoot->child('suppress welcome message')->isSet }

sub show {
	my $o = shift;
	my $cmd = shift;

#line 72 "Condensation/CLI/Commands/Welcome.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->title('Hi there!');
	$ui->p('This is the command line interface (CLI) of Condensation ', $CDS::VERSION, ', ', $CDS::releaseDate, '. Condensation is a distributed data system with conflict-free forward merging and end-to-end security. More information is available on https://condensation.io.');
	$ui->space;
	$ui->p('Commands resemble short english sentences. For example, the following "sentence" will show the record of an object:');
	$ui->line($ui->blue('  cds show record 20716a57ab520e5274230391f2874658473c2874ef8b3c2b7f67bf5b3837b69c \\'));
	$ui->line($ui->blue('            from http://condensation.io'));
	$ui->p('Type a "?" to explore possible commands, e.g.');
	$ui->line($ui->blue('  cds show ?'));
	$ui->p('or use TAB or TAB-TAB for command completion.');
	$ui->space;
	$ui->p('To get help, type');
	$ui->line($ui->blue('  cds help'));
	$ui->space;
	$ui->p('To suppress this welcome message, type');
	$ui->line($ui->blue('  cds suppress welcome message'));
	$ui->space;
}

package CDS::Commands::WhatIs;

#line 3 "Condensation/CLI/Commands/WhatIs.pm"
# BEGIN AUTOGENERATED

sub register {
	my $class = shift;
	my $cds = shift;
	my $help = shift;

#line 6 "Condensation/CLI/Commands/WhatIs.pm"
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node004 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&whatIs});
	$cds->addArrow($node001, 1, 0, 'what');
	$help->addArrow($node000, 1, 0, 'what');
	$node000->addArrow($node003, 1, 0, 'is');
	$node001->addArrow($node002, 1, 0, 'is');
	$node002->addArrow($node004, 1, 0, 'TEXT', \&collectText);
}

sub collectText {
	my $o = shift;
	my $label = shift;
	my $value = shift;

#line 19 "Condensation/CLI/Commands/WhatIs.pm"
	$o->{text} = $value;
}

sub new {
	my $class = shift;
	my $actor = shift;
	 bless {actor => $actor, ui => $actor->ui} }

#line 24 "Condensation/CLI/Commands/WhatIs.pm"
# END AUTOGENERATED

#line 26 "Condensation/CLI/Commands/WhatIs.pm"
# HTML FOLDER NAME what-is
# HTML TITLE What is
sub help {
	my $o = shift;
	my $cmd = shift;

#line 29 "Condensation/CLI/Commands/WhatIs.pm"
	my $ui = $o->{ui};
	$ui->space;
	$ui->command('cds what is TEXT');
	$ui->p('Tells what TEXT could be under the current configuration.');
	$ui->space;
}

sub whatIs {
	my $o = shift;
	my $cmd = shift;

#line 37 "Condensation/CLI/Commands/WhatIs.pm"
	$cmd->collect($o);
	$o->{butNot} = [];

#line 40 "Condensation/CLI/Commands/WhatIs.pm"
	$o->{ui}->space;
	$o->{ui}->title($o->{ui}->blue($o->{text}), ' may be …');

#line 43 "Condensation/CLI/Commands/WhatIs.pm"
	$o->test('ACCOUNT', 'an ACCOUNT', sub { shift->url });
	$o->test('AESKEY', 'an AESKEY', sub { unpack('H*', shift) });
	$o->test('BOX', 'a BOX', sub { shift->url });
	$o->test('BOXLABEL', 'a BOXLABEL', sub { shift });
	$o->test('FILE', 'a FILE', \&fileResult);
	$o->test('FILENAME', 'a FILENAME', \&fileResult);
	$o->test('FOLDER', 'a FOLDER', \&fileResult);
	$o->test('GROUP', 'a GROUP on this system', sub { shift });
	$o->test('HASH', 'a HASH or ACTOR hash', sub { shift->hex });
	$o->test('KEYPAIR', 'a KEYPAIR', \&keyPairResult);
	$o->test('LABEL', 'a remembered LABEL', sub { shift });
	$o->test('OBJECT', 'an OBJECT', sub { shift->url });
	$o->test('OBJECTFILE', 'an OBJECTFILE', \&objectFileResult);
	$o->test('STORE', 'a STORE', sub { shift->url });
	$o->test('USER', 'a USER on this system', sub { shift });

#line 59 "Condensation/CLI/Commands/WhatIs.pm"
	for my $butNot (@{$o->{butNot}}) {
		$o->{ui}->space;
		$o->{ui}->line('… but not ', $butNot->{text}, ', because:');
		for my $warning (@{$butNot->{warnings}}) {
			$o->{ui}->warning($warning);
		}
	}

#line 67 "Condensation/CLI/Commands/WhatIs.pm"
	$o->{ui}->space;
}

sub test {
	my $o = shift;
	my $expect = shift;
	my $text = shift;
	my $resultHandler = shift;

#line 71 "Condensation/CLI/Commands/WhatIs.pm"
	my $token = CDS::Parser::Token->new($o->{actor}, $o->{text});
	my $result = $token->produce($expect);
	if (defined $result) {
		my $whichOne = &$resultHandler($result);
		$o->{ui}->line('… ', $text, '  ', $o->{ui}->gray($whichOne));
	} elsif (scalar @{$token->{warnings}}) {
		push @{$o->{butNot}}, {text => $text, warnings => $token->{warnings}};
	}
}

sub keyPairResult {
	my $keyPairToken = shift;

#line 82 "Condensation/CLI/Commands/WhatIs.pm"
	return $keyPairToken->file.' ('.$keyPairToken->keyPair->publicKey->hash->hex.')';
}

sub objectFileResult {
	my $objectFileToken = shift;

#line 86 "Condensation/CLI/Commands/WhatIs.pm"
	return $objectFileToken->file if $objectFileToken->object->byteLength > 1024 * 1024;
	return $objectFileToken->file.' ('.$objectFileToken->object->calculateHash->hex.')';
}

sub fileResult {
	my $file = shift;

#line 91 "Condensation/CLI/Commands/WhatIs.pm"
	my @s = stat $file;
	my $label =
		! scalar @s ? ' (non-existing)' :
		Fcntl::S_ISDIR($s[2]) ? ' (folder)' :
		Fcntl::S_ISREG($s[2]) ? ' (file, '.$s[7].' bytes)' :
		Fcntl::S_ISLNK($s[2]) ? ' (symbolic link)' :
		Fcntl::S_ISBLK($s[2]) ? ' (block device)' :
		Fcntl::S_ISCHR($s[2]) ? ' (char device)' :
		Fcntl::S_ISSOCK($s[2]) ? ' (socket)' :
		Fcntl::S_ISFIFO($s[2]) ? ' (pipe)' : ' (unknown type)';

#line 102 "Condensation/CLI/Commands/WhatIs.pm"
	return $file.$label;
}

package CDS::Configuration;

our $xdgConfigurationFolder = ($ENV{XDG_CONFIG_HOME} || $ENV{HOME}.'/.config').'/condensation';
our $xdgDataFolder = ($ENV{XDG_DATA_HOME} || $ENV{HOME}.'/.local/share').'/condensation';

sub getOrCreateDefault {
	my $class = shift;
	my $ui = shift;

#line 5 "Condensation/CLI/Configuration.pm"
	my $configuration = $class->new($ui, $xdgConfigurationFolder, $xdgDataFolder);
	$configuration->createIfNecessary();
	return $configuration;
}

sub new {
	my $class = shift;
	my $ui = shift;
	my $folder = shift;
	my $defaultStoreFolder = shift;

#line 11 "Condensation/CLI/Configuration.pm"
	return bless {ui => $ui, folder => $folder, defaultStoreFolder => $defaultStoreFolder};
}

#line 14 "Condensation/CLI/Configuration.pm"
sub ui { shift->{ui} }
sub folder { shift->{folder} }

sub createIfNecessary {
	my $o = shift;

#line 18 "Condensation/CLI/Configuration.pm"
	my $keyPairFile = $o->{folder}.'/key-pair';
	return 1 if -f $keyPairFile;

#line 21 "Condensation/CLI/Configuration.pm"
	$o->{ui}->progress('Creating configuration folders …');
	$o->createFolder($o->{folder}) // return $o->{ui}->error('Failed to create the folder "', $o->{folder}, '".');
	$o->createFolder($o->{defaultStoreFolder}) // return $o->{ui}->error('Failed to create the folder "', $o->{defaultStoreFolder}, '".');
	CDS::FolderStore->new($o->{defaultStoreFolder})->createIfNecessary;

#line 26 "Condensation/CLI/Configuration.pm"
	$o->{ui}->progress('Generating key pair …');
	my $keyPair = CDS::KeyPair->generate;
	$keyPair->writeToFile($keyPairFile) // return $o->{ui}->error('Failed to write the configuration file "', $keyPairFile, '". Make sure that this location is writable.');
	$o->{ui}->removeProgress;
	return 1;
}

sub createFolder {
	my $o = shift;
	my $folder = shift;

#line 34 "Condensation/CLI/Configuration.pm"
	for my $path (CDS->intermediateFolders($folder)) {
		mkdir $path;
	}

#line 38 "Condensation/CLI/Configuration.pm"
	return -d $folder;
}

sub file {
	my $o = shift;
	my $filename = shift;

#line 42 "Condensation/CLI/Configuration.pm"
	return $o->{folder}.'/'.$filename;
}

sub messagingStoreUrl {
	my $o = shift;

#line 46 "Condensation/CLI/Configuration.pm"
	return $o->readFirstLine('messaging-store') // 'file://'.$o->{defaultStoreFolder};
}

sub storageStoreUrl {
	my $o = shift;

#line 50 "Condensation/CLI/Configuration.pm"
	return $o->readFirstLine('store') // 'file://'.$o->{defaultStoreFolder};
}

sub setMessagingStoreUrl {
	my $o = shift;
	my $storeUrl = shift;

#line 54 "Condensation/CLI/Configuration.pm"
	CDS->writeTextToFile($o->file('messaging-store'), $storeUrl);
}

sub setStorageStoreUrl {
	my $o = shift;
	my $storeUrl = shift;

#line 58 "Condensation/CLI/Configuration.pm"
	CDS->writeTextToFile($o->file('store'), $storeUrl);
}

sub keyPair {
	my $o = shift;

#line 62 "Condensation/CLI/Configuration.pm"
	return CDS::KeyPair->fromFile($o->file('key-pair'));
}

sub setKeyPair {
	my $o = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 66 "Condensation/CLI/Configuration.pm"
	$keyPair->writeToFile($o->file('key-pair'));
}

sub readFirstLine {
	my $o = shift;
	my $file = shift;

#line 70 "Condensation/CLI/Configuration.pm"
	my $content = CDS->readTextFromFile($o->file($file)) // return;
	$content = $1 if $content =~ /^(.*)\n/;
	$content = $1 if $content =~ /^\s*(.*?)\s*$/;
	return $content;
}

package CDS::DataTree;

sub new {
	my $class = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $store = shift;

#line 5 "Condensation/DataTree/DataTree.pm"
	my $o = bless {
		keyPair => $keyPair,
		unsaved => CDS::Unsaved->new($store),
		itemsBySelector => {},
		parts => {},
		hasPartsToMerge => 0,
		}, $class;

#line 13 "Condensation/DataTree/DataTree.pm"
	$o->{root} = CDS::Selector->root($o);
	$o->{changes} = CDS::DataTree::Part->new;
	return $o;
}

#line 18 "Condensation/DataTree/DataTree.pm"
sub keyPair { shift->{keyPair} }
sub unsaved { shift->{unsaved} }
sub parts {
	my $o = shift;
	 values %{$o->{parts}} }
#line 21 "Condensation/DataTree/DataTree.pm"
sub hasPartsToMerge { shift->{hasPartsToMerge} }

#line 23 "Condensation/DataTree/DataTree.pm"
### Items

#line 25 "Condensation/DataTree/DataTree.pm"
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

#line 31 "Condensation/DataTree/DataTree.pm"
	my $item = $o->{itemsBySelector}->{$selector->{id}};
	$o->{itemsBySelector}->{$selector->{id}} = $item = CDS::DataTree::Item->new($selector) if ! $item;
	return $item;
}

sub prune {
	my $o = shift;
	 $o->rootItem->pruneTree; }

#line 38 "Condensation/DataTree/DataTree.pm"
### Merging

sub merge {
	my $o = shift;

#line 41 "Condensation/DataTree/DataTree.pm"
	for my $hashAndKey (@_) {
		next if ! $hashAndKey;
		next if $o->{parts}->{$hashAndKey->hash->bytes};
		my $part = CDS::DataTree::Part->new;
		$part->{hashAndKey} = $hashAndKey;
		$o->{parts}->{$hashAndKey->hash->bytes} = $part;
		$o->{hasPartsToMerge} = 1;
	}
}

sub read {
	my $o = shift;

#line 52 "Condensation/DataTree/DataTree.pm"
	return 1 if ! $o->{hasPartsToMerge};

#line 54 "Condensation/DataTree/DataTree.pm"
	# Load the parts
	for my $part (values %{$o->{parts}}) {
		next if $part->{isMerged};
		next if $part->{loadedRecord};

#line 59 "Condensation/DataTree/DataTree.pm"
		my ($record, $object, $invalidReason, $storeError) = $o->{keyPair}->getAndDecryptRecord($part->{hashAndKey}, $o->{unsaved});
		return if defined $storeError;

#line 62 "Condensation/DataTree/DataTree.pm"
		delete $o->{parts}->{$part->{hashAndKey}->hash->bytes} if defined $invalidReason;
		$part->{loadedRecord} = $record;
	}

#line 66 "Condensation/DataTree/DataTree.pm"
	# Merge the loaded parts
	for my $part (values %{$o->{parts}}) {
		next if $part->{isMerged};
		next if ! $part->{loadedRecord};
		my $oldFormat = $part->{loadedRecord}->child('client')->textValue =~ /0.19/ ? 1 : 0;
		$o->mergeNode($part, $o->{root}, $part->{loadedRecord}->child('root'), $oldFormat);
		delete $part->{loadedRecord};
		$part->{isMerged} = 1;
	}

#line 76 "Condensation/DataTree/DataTree.pm"
	$o->{hasPartsToMerge} = 0;
	return 1;
}

sub mergeNode {
	my $o = shift;
	my $part = shift;
	my $selector = shift; die 'wrong type '.ref($selector).' for $selector' if defined $selector && ref $selector ne 'CDS::Selector';
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $oldFormat = shift;

#line 81 "Condensation/DataTree/DataTree.pm"
	# Prepare
	my @children = $record->children;
	return if ! scalar @children;
	my $item = $o->getOrCreate($selector);

#line 86 "Condensation/DataTree/DataTree.pm"
	# Merge value
	my $valueRecord = shift @children;
	$valueRecord = $valueRecord->firstChild if $oldFormat;
	$item->mergeValue($part, $valueRecord->asInteger, $valueRecord);

#line 91 "Condensation/DataTree/DataTree.pm"
	# Merge children
	for my $child (@children) { $o->mergeNode($part, $selector->child($child->bytes), $child, $oldFormat); }
}

#line 95 "Condensation/DataTree/DataTree.pm"
# *** Saving
# Call $dataTree->save at any time to save the current state (if necessary).

#line 98 "Condensation/DataTree/DataTree.pm"
# This is called by the items whenever some data changes.
sub dataChanged {
	my $o = shift;
	 }

sub save {
	my $o = shift;

#line 102 "Condensation/DataTree/DataTree.pm"
	$o->{unsaved}->startSaving;
	my $revision = CDS->now;
	my $newPart = undef;

#line 106 "Condensation/DataTree/DataTree.pm"
	#-- saving ++ $o->{changes}->{count}
	if ($o->{changes}->{count}) {
		# Take the changes
		$newPart = $o->{changes};
		$o->{changes} = CDS::DataTree::Part->new;

#line 112 "Condensation/DataTree/DataTree.pm"
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

#line 125 "Condensation/DataTree/DataTree.pm"
			last if ! $addedPart;
		}

#line 128 "Condensation/DataTree/DataTree.pm"
		# Include the selected items
		for my $item (values %{$o->{itemsBySelector}}) {
			next if ! $item->{part}->{selected};
			$item->setPart($newPart);
			$item->createSaveRecord;
		}

#line 135 "Condensation/DataTree/DataTree.pm"
		my $record = CDS::Record->new;
		$record->add('created')->addInteger($revision);
		$record->add('client')->add(CDS->version);
		$record->addRecord($o->rootItem->createSaveRecord);

#line 140 "Condensation/DataTree/DataTree.pm"
		# Detach the save records
		for my $item (values %{$o->{itemsBySelector}}) {
			$item->detachSaveRecord;
		}

#line 145 "Condensation/DataTree/DataTree.pm"
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

#line 156 "Condensation/DataTree/DataTree.pm"
	# Remove obsolete parts
	my $obsoleteParts = [];
	for my $part (values %{$o->{parts}}) {
		next if ! $part->{isMerged};
		next if $part->{count};
		push @$obsoleteParts, $part;
		delete $o->{parts}->{$part->{hashAndKey}->hash->bytes};
	}

#line 165 "Condensation/DataTree/DataTree.pm"
	# Commit
	#-- saving done ++ $revision ++ $newPart ++ $obsoleteParts
	return $o->savingDone($revision, $newPart, $obsoleteParts);
}

package CDS::DataTree::Item;

sub new {
	my $class = shift;
	my $selector = shift; die 'wrong type '.ref($selector).' for $selector' if defined $selector && ref $selector ne 'CDS::Selector';

#line 2 "Condensation/DataTree/DataTree/Item.pm"
	my $parentSelector = $selector->parent;
	my $parent = $parentSelector ? $selector->dataTree->getOrCreate($parentSelector) : undef;

#line 5 "Condensation/DataTree/DataTree/Item.pm"
	my $o = bless {
		dataTree => $selector->dataTree,
		selector => $selector,
		parent => $parent,
		children => [],
		part => undef,
		revision => 0,
		record => CDS::Record->new
		};

#line 15 "Condensation/DataTree/DataTree/Item.pm"
	push @{$parent->{children}}, $o if $parent;
	return $o;
}

sub pruneTree {
	my $o = shift;

#line 20 "Condensation/DataTree/DataTree/Item.pm"
	# Try to remove children
	for my $child (@{$o->{children}}) { $child->pruneTree; }

#line 23 "Condensation/DataTree/DataTree/Item.pm"
	# Don't remove the root item
	return if ! $o->{parent};

#line 26 "Condensation/DataTree/DataTree/Item.pm"
	# Don't remove if the item has children, or a value
	return if scalar @{$o->{children}};
	return if $o->{revision} > 0;

#line 30 "Condensation/DataTree/DataTree/Item.pm"
	# Remove this from the tree
	$o->{parent}->{children} = [grep { $_ != $o } @{$o->{parent}->{children}}];

#line 33 "Condensation/DataTree/DataTree/Item.pm"
	# Remove this from the datatree hash
	delete $o->{dataTree}->{itemsBySelector}->{$o->{selector}->{id}};
}

#line 37 "Condensation/DataTree/DataTree/Item.pm"
# Low-level part change.
sub setPart {
	my $o = shift;
	my $part = shift;

#line 39 "Condensation/DataTree/DataTree/Item.pm"
	$o->{part}->{count} -= 1 if $o->{part};
	$o->{part} = $part;
	$o->{part}->{count} += 1 if $o->{part};
}

#line 44 "Condensation/DataTree/DataTree/Item.pm"
# Merge a value

sub mergeValue {
	my $o = shift;
	my $part = shift;
	my $revision = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 47 "Condensation/DataTree/DataTree/Item.pm"
	return if $revision <= 0;
	return if $revision < $o->{revision};
	return if $revision == $o->{revision} && $part->{size} < $o->{part}->{size};
	$o->setPart($part);
	$o->{revision} = $revision;
	$o->{record} = $record;
	$o->{dataTree}->dataChanged;
	return 1;
}

sub forget {
	my $o = shift;

#line 58 "Condensation/DataTree/DataTree/Item.pm"
	return if $o->{revision} <= 0;
	$o->{revision} = 0;
	$o->{record} = CDS::Record->new;
	$o->setPart;
}

#line 64 "Condensation/DataTree/DataTree/Item.pm"
# Saving

sub createSaveRecord {
	my $o = shift;

#line 67 "Condensation/DataTree/DataTree/Item.pm"
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

#line 79 "Condensation/DataTree/DataTree/Item.pm"
	return if ! $o->{saveRecord};
	delete $o->{saveRecord};
	$o->{parent}->detachSaveRecord if $o->{parent};
}

package CDS::DataTree::Part;

sub new {
	my $class = shift;

#line 2 "Condensation/DataTree/DataTree/Part.pm"
	return bless {
		isMerged => 0,
		hashAndKey => undef,
		size => 0,
		count => 0,
		selected => 0,
		};
}

#line 11 "Condensation/DataTree/DataTree/Part.pm"
# In this implementation, we only keep track of the number of values of the list, but
# not of the corresponding items. This saves memory (~100 MiB for 1M items), but takes
# more time (0.5 s for 1M items) when saving. Since command line programs usually write
# the data tree only once, this is acceptable. Reading the tree anyway takes about 10
# times more time.

package CDS::DetachedDataTree;

use parent -norequire, 'CDS::DataTree';

sub new {
	my $class = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 4 "Condensation/DataTree/DetachedDataTree.pm"
	return $class->SUPER::new($keyPair, CDS::InMemoryStore->create);
}

sub savingDone {
	my $o = shift;
	my $revision = shift;
	my $newPart = shift;
	my $obsoleteParts = shift;

#line 8 "Condensation/DataTree/DetachedDataTree.pm"
	# We don't do anything
	$o->{unsaved}->savingDone;
}

package CDS::DiscoverActorGroup;

sub discover {
	my $class = shift;
	my $builder = shift; die 'wrong type '.ref($builder).' for $builder' if defined $builder && ref $builder ne 'CDS::ActorGroupBuilder';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $delegate = shift;

#line 6 "Condensation/Actors/DiscoverActorGroup.pm"
	my $o = bless {
		knownPublicKeys => $builder->knownPublicKeys,	# A hashref of known public keys (e.g. from the existing actor group)
		keyPair => $keyPair,
		delegate => $delegate,							# The delegate
		nodesByUrl => {},								# Nodes on which this actor group is active, by URL
		coverage => {},									# Hashes that belong to this actor group
		};

#line 14 "Condensation/Actors/DiscoverActorGroup.pm"
	# Add all active members
	for my $member ($builder->members) {
		next if $member->status ne 'active';
		my $node = $o->node($member->hash, $member->storeUrl);
		if ($node->{revision} < $member->revision) {
			$node->{revision} = $member->revision;
			$node->{status} = 'active';
		}

#line 23 "Condensation/Actors/DiscoverActorGroup.pm"
		$o->{coverage}->{$member->hash->bytes} = 1;
	}

#line 26 "Condensation/Actors/DiscoverActorGroup.pm"
	# Determine the revision at start
	my $revisionAtStart = 0;
	for my $node (values %{$o->{nodesByUrl}}) {
		$revisionAtStart = $node->{revision} if $revisionAtStart < $node->{revision};
	}

#line 32 "Condensation/Actors/DiscoverActorGroup.pm"
	# Reload the cards of all known accounts
	for my $node (values %{$o->{nodesByUrl}}) {
		$node->discover;
	}

#line 37 "Condensation/Actors/DiscoverActorGroup.pm"
	# From here, try extending to other accounts
	while ($o->extend) {}

#line 40 "Condensation/Actors/DiscoverActorGroup.pm"
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

#line 53 "Condensation/Actors/DiscoverActorGroup.pm"
	# Get the newest list of entrusted actors
	my $parser = CDS::ActorGroupBuilder->new;
	for my $card (@cards) {
		$parser->parseEntrustedActors($card->card->child('entrusted actors'), 0);
	}

#line 59 "Condensation/Actors/DiscoverActorGroup.pm"
	# Get the entrusted actors
	my $entrustedActors = [];
	for my $actor ($parser->entrustedActors) {
		my $store = $o->{delegate}->onDiscoverActorGroupVerifyStore($actor->storeUrl);
		next if ! $store;

#line 65 "Condensation/Actors/DiscoverActorGroup.pm"
		my $knownPublicKey = $o->{knownPublicKeys}->{$actor->hash->bytes};
		if ($knownPublicKey) {
			push @$entrustedActors, CDS::ActorGroup::EntrustedActor->new(CDS::ActorOnStore->new($knownPublicKey, $store), $actor->storeUrl);
			next;
		}

#line 71 "Condensation/Actors/DiscoverActorGroup.pm"
		my ($publicKey, $invalidReason, $storeError) = $keyPair->getPublicKey($actor->hash, $store);

#line 73 "Condensation/Actors/DiscoverActorGroup.pm"
		if (defined $invalidReason) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidPublicKey($actor->hash, $store, $invalidReason);
			next;
		}

#line 78 "Condensation/Actors/DiscoverActorGroup.pm"
		if (defined $storeError) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupStoreError($store, $storeError);
			next;
		}

#line 83 "Condensation/Actors/DiscoverActorGroup.pm"
		push @$entrustedActors, CDS::ActorGroup::EntrustedActor->new(CDS::ActorOnStore->new($publicKey, $store), $actor->storeUrl);
	}

#line 86 "Condensation/Actors/DiscoverActorGroup.pm"
	my $members = [sort { $b->{revision} <=> $a->{revision} || $b->{status} cmp $a->{status} } @members];
	return CDS::ActorGroup->new($members, $parser->entrustedActorsRevision, $entrustedActors), [@cards], [grep { $_->{attachedToUs} } values %{$o->{nodesByUrl}}];
}

sub node {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';
	my $storeUrl = shift;
		# private
#line 91 "Condensation/Actors/DiscoverActorGroup.pm"
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

#line 100 "Condensation/Actors/DiscoverActorGroup.pm"
	# Start with the newest node
	my $mainNode;
	my $mainRevision = -1;
	for my $node (values %{$o->{nodesByUrl}}) {
		next if ! $node->{attachedToUs};
		next if $node->{revision} <= $mainRevision;
		$mainNode = $node;
		$mainRevision = $node->{revision};
	}

#line 110 "Condensation/Actors/DiscoverActorGroup.pm"
	return 0 if ! $mainNode;

#line 112 "Condensation/Actors/DiscoverActorGroup.pm"
	# Reset the reachable flag
	for my $node (values %{$o->{nodesByUrl}}) {
		$node->{reachable} = 0;
	}
	$mainNode->{reachable} = 1;

#line 118 "Condensation/Actors/DiscoverActorGroup.pm"
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

#line 134 "Condensation/Actors/DiscoverActorGroup.pm"
	# Discover these accounts
	my $hasChanges = 0;
	for my $node (sort { $b->{revision} <=> $a->{revision} } @toDiscover) {
		$node->discover;
		next if ! $node->{attachedToUs};
		$hasChanges = 1;
	}

#line 142 "Condensation/Actors/DiscoverActorGroup.pm"
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

#line 2 "Condensation/Actors/DiscoverActorGroup/Card.pm"
	return bless {
		storeUrl => $storeUrl,
		actorOnStore => $actorOnStore,
		envelopeHash => $envelopeHash,
		envelope => $envelope,
		cardHash => $cardHash,
		card => $card,
		};
}

#line 12 "Condensation/Actors/DiscoverActorGroup/Card.pm"
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

#line 2 "Condensation/Actors/DiscoverActorGroup/Link.pm"
	bless {
		node => $node,
		revision => $revision,
		status => $status,
		};
}

#line 9 "Condensation/Actors/DiscoverActorGroup/Link.pm"
sub node { shift->{node} }
sub revision { shift->{revision} }
sub status { shift->{status} }

package CDS::DiscoverActorGroup::Node;

sub new {
	my $class = shift;
	my $discoverer = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';
	my $storeUrl = shift;

#line 2 "Condensation/Actors/DiscoverActorGroup/Node.pm"
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

#line 22 "Condensation/Actors/DiscoverActorGroup/Node.pm"
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

#line 30 "Condensation/Actors/DiscoverActorGroup/Node.pm"
	#-- discover ++ $o->{actorHash}->hex
	$o->readCards;
	$o->attach;
}

sub readCards {
	my $o = shift;

#line 36 "Condensation/Actors/DiscoverActorGroup/Node.pm"
	return if $o->{cardsRead};
	$o->{cardsRead} = 1;
	#-- read cards of ++ $o->{actorHash}->hex

#line 40 "Condensation/Actors/DiscoverActorGroup/Node.pm"
	# Get the store
	my $store = $o->{discoverer}->{delegate}->onDiscoverActorGroupVerifyStore($o->{storeUrl}, $o->{actorHash}) // return;

#line 43 "Condensation/Actors/DiscoverActorGroup/Node.pm"
	# Get the public key if necessary
	if (! $o->{actorOnStore}) {
		my $publicKey = $o->{discoverer}->{knownPublicKeys}->{$o->{actorHash}->bytes};
		if (! $publicKey) {
			my ($downloadedPublicKey, $invalidReason, $storeError) = $o->{discoverer}->{keyPair}->getPublicKey($o->{actorHash}, $store);
			return $o->{discoverer}->{delegate}->onDiscoverActorGroupStoreError($store, $storeError) if defined $storeError;
			return $o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidPublicKey($o->{actorHash}, $store, $invalidReason) if defined $invalidReason;
			$publicKey = $downloadedPublicKey;
		}

#line 53 "Condensation/Actors/DiscoverActorGroup/Node.pm"
		$o->{actorOnStore} = CDS::ActorOnStore->new($publicKey, $store);
	}

#line 56 "Condensation/Actors/DiscoverActorGroup/Node.pm"
	# List the public box
	my ($hashes, $storeError) = $store->list($o->{actorHash}, 'public', 0, $o->{discoverer}->{keyPair});
	return $o->{discoverer}->{delegate}->onDiscoverActorGroupStoreError($store, $storeError) if defined $storeError;

#line 60 "Condensation/Actors/DiscoverActorGroup/Node.pm"
	for my $envelopeHash (@$hashes) {
		# Open the envelope
		my ($object, $storeError) = $store->get($envelopeHash, $o->{discoverer}->{keyPair});
		return $o->{discoverer}->{delegate}->onDiscoverActorGroupStoreError($store, $storeError) if defined $storeError;
		if (! $object) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidCard($o->{actorOnStore}, $envelopeHash, 'Envelope object not found.');
			next;
		}

#line 69 "Condensation/Actors/DiscoverActorGroup/Node.pm"
		my $envelope = CDS::Record->fromObject($object);
		if (! $envelope) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidCard($o->{actorOnStore}, $envelopeHash, 'Envelope is not a record.');
			next;
		}

#line 75 "Condensation/Actors/DiscoverActorGroup/Node.pm"
		my $cardHash = $envelope->child('content')->hashValue;
		if (! $cardHash) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidCard($o->{actorOnStore}, $envelopeHash, 'Missing content hash.');
			next;
		}

#line 81 "Condensation/Actors/DiscoverActorGroup/Node.pm"
		if (! CDS->verifyEnvelopeSignature($envelope, $o->{actorOnStore}->publicKey, $cardHash)) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidCard($o->{actorOnStore}, $envelopeHash, 'Invalid signature.');
			next;
		}

#line 86 "Condensation/Actors/DiscoverActorGroup/Node.pm"
		# Read the card
		my ($cardObject, $storeError1) = $store->get($cardHash, $o->{discoverer}->{keyPair});
		return $o->{discoverer}->{delegate}->onDiscoverActorGroupStoreError($store, $storeError) if defined $storeError1;
		if (! $cardObject) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidCard($o->{actorOnStore}, $envelopeHash, 'Card object not found.');
			next;
		}

#line 94 "Condensation/Actors/DiscoverActorGroup/Node.pm"
		my $card = CDS::Record->fromObject($cardObject);
		if (! $card) {
			$o->{discoverer}->{delegate}->onDiscoverActorGroupInvalidCard($o->{actorOnStore}, $envelopeHash, 'Card is not a record.');
			next;
		}

#line 100 "Condensation/Actors/DiscoverActorGroup/Node.pm"
		# Add the card to the list of cards
		push @{$o->{cards}}, CDS::DiscoverActorGroup::Card->new($o->{storeUrl}, $o->{actorOnStore}, $envelopeHash, $envelope, $cardHash, $card);

#line 103 "Condensation/Actors/DiscoverActorGroup/Node.pm"
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

#line 115 "Condensation/Actors/DiscoverActorGroup/Node.pm"
	return if $o->{attachedToUs};
	return if ! $o->hasLinkToUs;

#line 118 "Condensation/Actors/DiscoverActorGroup/Node.pm"
	# Attach this node
	$o->{attachedToUs} = 1;

#line 121 "Condensation/Actors/DiscoverActorGroup/Node.pm"
	# Merge all links
	for my $link (@{$o->{links}}) {
		$link->{node}->merge($link->{revision}, $link->{status});
	}

#line 126 "Condensation/Actors/DiscoverActorGroup/Node.pm"
	# Add the hash to the coverage
	$o->{discoverer}->{coverage}->{$o->{actorHash}->bytes} = 1;
}

sub merge {
	my $o = shift;
	my $revision = shift;
	my $status = shift;

#line 131 "Condensation/Actors/DiscoverActorGroup/Node.pm"
	return if $o->{revision} >= $revision;
	$o->{revision} = $revision;
	$o->{status} = $status;
}

sub hasLinkToUs {
	my $o = shift;

#line 137 "Condensation/Actors/DiscoverActorGroup/Node.pm"
	return 1 if $o->{discoverer}->covers($o->{actorHash});
	for my $link (@{$o->{links}}) {
		return 1 if $o->{discoverer}->covers($link->{node}->{actorHash});
	}
	return;
}

package CDS::ErrorHandlingStore;

use parent -norequire, 'CDS::Store';

sub new {
	my $class = shift;
	my $store = shift;
	my $url = shift;
	my $errorHandler = shift;

#line 4 "Condensation/Stores/ErrorHandlingStore.pm"
	return bless {
		store => $store,
		url => $url,
		errorHandler => $errorHandler,
		}
}

#line 11 "Condensation/Stores/ErrorHandlingStore.pm"
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

#line 18 "Condensation/Stores/ErrorHandlingStore.pm"
	return undef, 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'GET');

#line 20 "Condensation/Stores/ErrorHandlingStore.pm"
	my ($object, $error) = $o->{store}->get($hash, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'GET', $error);
		return undef, $error;
	}

#line 26 "Condensation/Stores/ErrorHandlingStore.pm"
	$o->{errorHandler}->onStoreSuccess($o, 'GET');
	return $object, $error;
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 31 "Condensation/Stores/ErrorHandlingStore.pm"
	return undef, 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'BOOK');

#line 33 "Condensation/Stores/ErrorHandlingStore.pm"
	my ($booked, $error) = $o->{store}->book($hash, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'BOOK', $error);
		return undef, $error;
	}

#line 39 "Condensation/Stores/ErrorHandlingStore.pm"
	$o->{errorHandler}->onStoreSuccess($o, 'BOOK');
	return $booked;
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 44 "Condensation/Stores/ErrorHandlingStore.pm"
	return 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'PUT');

#line 46 "Condensation/Stores/ErrorHandlingStore.pm"
	my $error = $o->{store}->put($hash, $object, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'PUT', $error);
		return $error;
	}

#line 52 "Condensation/Stores/ErrorHandlingStore.pm"
	$o->{errorHandler}->onStoreSuccess($o, 'PUT');
	return;
}

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 57 "Condensation/Stores/ErrorHandlingStore.pm"
	return undef, 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'LIST');

#line 59 "Condensation/Stores/ErrorHandlingStore.pm"
	my ($hashes, $error) = $o->{store}->list($accountHash, $boxLabel, $timeout, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'LIST', $error);
		return undef, $error;
	}

#line 65 "Condensation/Stores/ErrorHandlingStore.pm"
	$o->{errorHandler}->onStoreSuccess($o, 'LIST');
	return $hashes;
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 70 "Condensation/Stores/ErrorHandlingStore.pm"
	return 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'ADD');

#line 72 "Condensation/Stores/ErrorHandlingStore.pm"
	my $error = $o->{store}->add($accountHash, $boxLabel, $hash, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'ADD', $error);
		return $error;
	}

#line 78 "Condensation/Stores/ErrorHandlingStore.pm"
	$o->{errorHandler}->onStoreSuccess($o, 'ADD');
	return;
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 83 "Condensation/Stores/ErrorHandlingStore.pm"
	return 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'REMOVE');

#line 85 "Condensation/Stores/ErrorHandlingStore.pm"
	my $error = $o->{store}->remove($accountHash, $boxLabel, $hash, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'REMOVE', $error);
		return $error;
	}

#line 91 "Condensation/Stores/ErrorHandlingStore.pm"
	$o->{errorHandler}->onStoreSuccess($o, 'REMOVE');
	return;
}

sub modify {
	my $o = shift;
	my $modifications = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 96 "Condensation/Stores/ErrorHandlingStore.pm"
	return 'Store disabled.' if $o->{errorHandler}->hasStoreError($o, 'MODIFY');

#line 98 "Condensation/Stores/ErrorHandlingStore.pm"
	my $error = $o->{store}->modify($modifications, $keyPair);
	if (defined $error) {
		$o->{errorHandler}->onStoreError($o, 'MODIFY', $error);
		return $error;
	}

#line 104 "Condensation/Stores/ErrorHandlingStore.pm"
	$o->{errorHandler}->onStoreSuccess($o, 'MODIFY');
	return;
}

# A Condensation store on a local folder.
package CDS::FolderStore;

use parent -norequire, 'CDS::Store';

sub forUrl {
	my $class = shift;
	my $url = shift;

#line 8 "Condensation/Stores/FolderStore.pm"
	return if substr($url, 0, 8) ne 'file:///';
	return $class->new(substr($url, 7));
}

sub new {
	my $class = shift;
	my $folder = shift;

#line 13 "Condensation/Stores/FolderStore.pm"
	return bless {
		folder => $folder,
		permissions => CDS::FolderStore::PosixPermissions->forFolder($folder.'/accounts'),
		};
}

sub id {
	my $o = shift;
	 'file://'.$o->{folder} }
#line 20 "Condensation/Stores/FolderStore.pm"
sub folder { shift->{folder} }

#line 22 "Condensation/Stores/FolderStore.pm"
sub permissions { shift->{permissions} }
sub setPermissions {
	my $o = shift;
	my $permissions = shift;
	 $o->{permissions} = $permissions; }

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 26 "Condensation/Stores/FolderStore.pm"
	my $hashHex = $hash->hex;
	my $file = $o->{folder}.'/objects/'.substr($hashHex, 0, 2).'/'.substr($hashHex, 2);
	return CDS::Object->fromBytes(CDS->readBytesFromFile($file));
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 32 "Condensation/Stores/FolderStore.pm"
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

#line 41 "Condensation/Stores/FolderStore.pm"
	# Book the object if it exists
	my $hashHex = $hash->hex;
	my $folder = $o->{folder}.'/objects/'.substr($hashHex, 0, 2);
	my $file = $folder.'/'.substr($hashHex, 2);
	return if -e $file && utime(undef, undef, $file);

#line 47 "Condensation/Stores/FolderStore.pm"
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

#line 56 "Condensation/Stores/FolderStore.pm"
	return undef, 'Invalid box label.' if ! CDS->isValidBoxLabel($boxLabel);

#line 58 "Condensation/Stores/FolderStore.pm"
	# Prepare
	my $boxFolder = $o->{folder}.'/accounts/'.$accountHash->hex.'/'.$boxLabel;

#line 61 "Condensation/Stores/FolderStore.pm"
	# List
	return $o->listFolder($boxFolder) if ! $timeout;

#line 64 "Condensation/Stores/FolderStore.pm"
	# Watch
	my $hashes;
	my $watcher = CDS::FolderStore::Watcher->new($boxFolder);
	my $watchUntil = CDS->now + $timeout;
	while (1) {
		# List
		$hashes = $o->listFolder($boxFolder);
		last if scalar @$hashes;

#line 73 "Condensation/Stores/FolderStore.pm"
		# Wait
		$watcher->wait($watchUntil - CDS->now, $watchUntil) // last;
	}

#line 77 "Condensation/Stores/FolderStore.pm"
	$watcher->done;
	return $hashes;
}

sub listFolder {
	my $o = shift;
	my $boxFolder = shift;
		# private
#line 82 "Condensation/Stores/FolderStore.pm"
	my $hashes = [];
	for my $file (CDS->listFolder($boxFolder)) {
		push @$hashes, CDS::Hash->fromHex($file) // next;
	}

#line 87 "Condensation/Stores/FolderStore.pm"
	return $hashes;
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 91 "Condensation/Stores/FolderStore.pm"
	my $permissions = $o->{permissions};

#line 93 "Condensation/Stores/FolderStore.pm"
	next if ! CDS->isValidBoxLabel($boxLabel);
	my $accountFolder = $o->{folder}.'/accounts/'.$accountHash->hex;
	$permissions->mkdir($accountFolder, $permissions->accountFolderMode);
	my $boxFolder = $accountFolder.'/'.$boxLabel;
	$permissions->mkdir($boxFolder, $permissions->boxFolderMode($boxLabel));
	my $boxFileMode = $permissions->boxFileMode($boxLabel);

#line 100 "Condensation/Stores/FolderStore.pm"
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

#line 106 "Condensation/Stores/FolderStore.pm"
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

#line 115 "Condensation/Stores/FolderStore.pm"
	return $modifications->executeIndividually($o, $keyPair);
}

#line 118 "Condensation/Stores/FolderStore.pm"
# Store administration functions

sub exists {
	my $o = shift;

#line 121 "Condensation/Stores/FolderStore.pm"
	return -d $o->{folder}.'/accounts' && -d $o->{folder}.'/objects';
}

#line 124 "Condensation/Stores/FolderStore.pm"
# Creates the store if it does not exist. The store folder itself must exist.
sub createIfNecessary {
	my $o = shift;

#line 126 "Condensation/Stores/FolderStore.pm"
	my $accountsFolder = $o->{folder}.'/accounts';
	my $objectsFolder = $o->{folder}.'/objects';
	$o->{permissions}->mkdir($accountsFolder, $o->{permissions}->baseFolderMode);
	$o->{permissions}->mkdir($objectsFolder, $o->{permissions}->baseFolderMode);
	return -d $accountsFolder && -d $objectsFolder;
}

#line 133 "Condensation/Stores/FolderStore.pm"
# Lists accounts. This is a non-standard extension.
sub accounts {
	my $o = shift;

#line 135 "Condensation/Stores/FolderStore.pm"
	return	grep { defined $_ }
			map { CDS::Hash->fromHex($_) }
			CDS->listFolder($o->{folder}.'/accounts');
}

#line 140 "Condensation/Stores/FolderStore.pm"
# Adds an account. This is a non-standard extension.
sub addAccount {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';

#line 142 "Condensation/Stores/FolderStore.pm"
	my $accountFolder = $o->{folder}.'/accounts/'.$accountHash->hex;
	$o->{permissions}->mkdir($accountFolder, $o->{permissions}->accountFolderMode);
	return -d $accountFolder;
}

#line 147 "Condensation/Stores/FolderStore.pm"
# Removes an account. This is a non-standard extension.
sub removeAccount {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';

#line 149 "Condensation/Stores/FolderStore.pm"
	my $accountFolder = $o->{folder}.'/accounts/'.$accountHash->hex;
	my $trashFolder = $o->{folder}.'/accounts/.deleted-'.CDS->randomHex(16);
	rename $accountFolder, $trashFolder;
	system('rm', '-rf', $trashFolder);
	return ! -d $accountFolder;
}

#line 156 "Condensation/Stores/FolderStore.pm"
# Checks (and optionally fixes) the POSIX permissions of all files and folders. This is a non-standard extension.
sub checkPermissions {
	my $o = shift;
	my $logger = shift;

#line 158 "Condensation/Stores/FolderStore.pm"
	my $permissions = $o->{permissions};

#line 160 "Condensation/Stores/FolderStore.pm"
	# Check the accounts folder
	my $accountsFolder = $o->{folder}.'/accounts';
	$permissions->checkPermissions($accountsFolder, $permissions->baseFolderMode, $logger) || return;

#line 164 "Condensation/Stores/FolderStore.pm"
	# Check the account folders
	for my $account (sort { $a cmp $b } CDS->listFolder($accountsFolder)) {
		next if $account !~ /^[0-9a-f]{64}$/;
		my $accountFolder = $accountsFolder.'/'.$account;
		$permissions->checkPermissions($accountFolder, $permissions->accountFolderMode, $logger) || return;

#line 170 "Condensation/Stores/FolderStore.pm"
		# Check the box folders
		for my $boxLabel (sort { $a cmp $b } CDS->listFolder($accountFolder)) {
			next if $boxLabel =~ /^\./;
			my $boxFolder = $accountFolder.'/'.$boxLabel;
			$permissions->checkPermissions($boxFolder, $permissions->boxFolderMode($boxLabel), $logger) || return;

#line 176 "Condensation/Stores/FolderStore.pm"
			# Check each file
			my $filePermissions = $permissions->boxFileMode($boxLabel);
			for my $file (sort { $a cmp $b } CDS->listFolder($boxFolder)) {
				next if $file !~ /^[0-9a-f]{64}/;
				$permissions->checkPermissions($boxFolder.'/'.$file, $filePermissions, $logger) || return;
			}
		}
	}

#line 185 "Condensation/Stores/FolderStore.pm"
	# Check the objects folder
	my $objectsFolder = $o->{folder}.'/objects';
	my $fileMode = $permissions->objectFileMode;
	my $folderMode = $permissions->objectFolderMode;
	$permissions->checkPermissions($objectsFolder, $folderMode, $logger) || return;

#line 191 "Condensation/Stores/FolderStore.pm"
	# Check the 256 sub folders
	for my $sub (sort { $a cmp $b } CDS->listFolder($objectsFolder)) {
		next if $sub !~ /^[0-9a-f][0-9a-f]$/;
		my $subFolder = $objectsFolder.'/'.$sub;
		$permissions->checkPermissions($subFolder, $folderMode, $logger) || return;

#line 197 "Condensation/Stores/FolderStore.pm"
		for my $file (sort { $a cmp $b } CDS->listFolder($subFolder)) {
			next if $file !~ /^[0-9a-f]{62}/;
			$permissions->checkPermissions($subFolder.'/'.$file, $fileMode, $logger) || return;
		}
	}

#line 203 "Condensation/Stores/FolderStore.pm"
	return 1;
}

# Handles POSIX permissions (user, group, and mode).
package CDS::FolderStore::PosixPermissions;

#line 6 "Condensation/Stores/FolderStore/PosixPermissions.pm"
# Returns the permissions set corresponding to the mode, uid, and gid of the base folder.
# If the permissions are ambiguous, the more restrictive set is chosen.
sub forFolder {
	my $class = shift;
	my $folder = shift;

#line 9 "Condensation/Stores/FolderStore/PosixPermissions.pm"
	my @s = stat $folder;
	my $mode = $s[2] // 0;

#line 12 "Condensation/Stores/FolderStore/PosixPermissions.pm"
	return
		($mode & 077) == 077 ? CDS::FolderStore::PosixPermissions::World->new :
		($mode & 070) == 070 ? CDS::FolderStore::PosixPermissions::Group->new($s[5]) :
			CDS::FolderStore::PosixPermissions::User->new($s[4]);
}

#line 18 "Condensation/Stores/FolderStore/PosixPermissions.pm"
sub uid { shift->{uid} }
sub gid { shift->{gid} }

sub user {
	my $o = shift;

#line 22 "Condensation/Stores/FolderStore/PosixPermissions.pm"
	my $uid = $o->{uid} // return;
	return getpwuid($uid) // $uid;
}

sub group {
	my $o = shift;

#line 27 "Condensation/Stores/FolderStore/PosixPermissions.pm"
	my $gid = $o->{gid} // return;
	return getgrgid($gid) // $gid;
}

sub writeTemporaryFile {
	my $o = shift;
	my $folder = shift;
	my $mode = shift;

#line 32 "Condensation/Stores/FolderStore/PosixPermissions.pm"
	# Write the file
	my $temporaryFile = $folder.'/.'.CDS->randomHex(16);
	open(my $fh, '>:bytes', $temporaryFile) || return;
	print $fh @_;
	close $fh;

#line 38 "Condensation/Stores/FolderStore/PosixPermissions.pm"
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

#line 47 "Condensation/Stores/FolderStore/PosixPermissions.pm"
	return if -d $folder;

#line 49 "Condensation/Stores/FolderStore/PosixPermissions.pm"
	# Create the folder (note: mode is altered by umask)
	my $success = mkdir $folder, $mode;

#line 52 "Condensation/Stores/FolderStore/PosixPermissions.pm"
	# Set the permissions
	chmod $mode, $folder;
	my $uid = $o->uid;
	my $gid = $o->gid;
	chown $uid // -1, $gid // -1, $folder if defined $uid && $uid != $< || defined $gid && $gid != $(;
	return $success;
}

#line 60 "Condensation/Stores/FolderStore/PosixPermissions.pm"
# Check the permissions of a file or folder, and fix them if desired.
# A logger object is called for the different cases (access error, correct permissions, wrong permissions, error fixing permissions).
sub checkPermissions {
	my $o = shift;
	my $item = shift;
	my $expectedMode = shift;
	my $logger = shift;

#line 63 "Condensation/Stores/FolderStore/PosixPermissions.pm"
	my $expectedUid = $o->uid;
	my $expectedGid = $o->gid;

#line 66 "Condensation/Stores/FolderStore/PosixPermissions.pm"
	# Stat the item
	my @s = stat $item;
	return $logger->accessError($item) if ! scalar @s;
	my $mode = $s[2] & 07777;
	my $uid = $s[4];
	my $gid = $s[5];

#line 73 "Condensation/Stores/FolderStore/PosixPermissions.pm"
	# Check
	my $wrongUid = defined $expectedUid && $uid != $expectedUid;
	my $wrongGid = defined $expectedGid && $gid != $expectedGid;
	my $wrongMode = $mode != $expectedMode;
	if ($wrongUid || $wrongGid || $wrongMode) {
		# Something is wrong
		$logger->wrong($item, $uid, $gid, $mode, $expectedUid, $expectedGid, $expectedMode) || return 1;

#line 81 "Condensation/Stores/FolderStore/PosixPermissions.pm"
		# Fix uid and gid
		if ($wrongUid || $wrongGid) {
			my $count = chown $expectedUid // -1, $expectedGid // -1, $item;
			return $logger->setError($item) if $count < 1;
		}

#line 87 "Condensation/Stores/FolderStore/PosixPermissions.pm"
		# Fix mode
		if ($wrongMode) {
			my $count = chmod $expectedMode, $item;
			return $logger->setError($item) if $count < 1;
		}
	} else {
		# Everything is OK
		$logger->correct($item, $mode, $uid, $gid);
	}

#line 97 "Condensation/Stores/FolderStore/PosixPermissions.pm"
	return 1;
}

# The store belongs to a group. Every user belonging to the group is treated equivalent, and users are supposed to trust each other to some extent.
# The resulting store will have files belonging to multiple users, but the same group.
package CDS::FolderStore::PosixPermissions::Group;

use parent -norequire, 'CDS::FolderStore::PosixPermissions';

sub new {
	my $class = shift;
	my $gid = shift;

#line 6 "Condensation/Stores/FolderStore/PosixPermissions/Group.pm"
	return bless {gid => $gid // $(};
}

sub target {
	my $o = shift;
	 'members of the group '.$o->group }
#line 10 "Condensation/Stores/FolderStore/PosixPermissions/Group.pm"
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

#line 5 "Condensation/Stores/FolderStore/PosixPermissions/User.pm"
	return bless {uid => $uid // $<};
}

sub target {
	my $o = shift;
	 'user '.$o->user }
#line 9 "Condensation/Stores/FolderStore/PosixPermissions/User.pm"
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

#line 6 "Condensation/Stores/FolderStore/PosixPermissions/World.pm"
	return bless {};
}

#line 9 "Condensation/Stores/FolderStore/PosixPermissions/World.pm"
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

#line 35 "Condensation/Stores/FolderStore/Watcher.pm"
	return bless {folder => $folder};
}

sub wait {
	my $o = shift;
	my $remaining = shift;
	my $until = shift;

#line 39 "Condensation/Stores/FolderStore/Watcher.pm"
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

#line 2 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	my $o = bless {
		actor => $actor,
		label => 'shared group data',
		dataHandlers => {},
		messageChannel => CDS::MessageChannel->new($actor, 'group data', CDS->MONTH),
		revision => 0,
		version => '',
		}, $class;

#line 11 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	$actor->storagePrivateRoot->addDataHandler($o->{label}, $o);
	return $o;
}

#line 15 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
### Group data handlers

sub addDataHandler {
	my $o = shift;
	my $label = shift;
	my $dataHandler = shift;

#line 18 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	$o->{dataHandlers}->{$label} = $dataHandler;
}

sub removeDataHandler {
	my $o = shift;
	my $label = shift;
	my $dataHandler = shift;

#line 22 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	my $registered = $o->{dataHandlers}->{$label};
	return if $registered != $dataHandler;
	delete $o->{dataHandlers}->{$label};
}

#line 27 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
### MergeableData interface

sub addDataTo {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 30 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	return if ! $o->{revision};
	$record->addInteger($o->{revision})->add($o->{version});
}

sub mergeData {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 35 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	for my $child ($record->children) {
		my $revision = $child->asInteger;
		next if $revision <= $o->{revision};

#line 39 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
		$o->{revision} = $revision;
		$o->{version} = $child->bytesValue;
	}
}

sub mergeExternalData {
	my $o = shift;
	my $store = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';

#line 45 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	$o->mergeData($record);
	return if ! $source;
	$source->keep;
	$o->{actor}->storagePrivateRoot->unsaved->state->addMergedSource($source);
}

#line 51 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
### Sending messages

sub createMessage {
	my $o = shift;

#line 54 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
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

#line 64 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	# Get the group data members
	my $members = $o->{actor}->getGroupDataMembers // return;
	return 1 if ! scalar @$members;

#line 68 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	# Create the group data message, and check if it changed
	my $message = $o->createMessage;
	my $versionHash = $message->toObject->calculateHash;
	return if $versionHash->bytes eq $o->{version};

#line 73 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	$o->{revision} = CDS->now;
	$o->{version} = $versionHash->bytes;
	$o->{actor}->storagePrivateRoot->dataChanged;

#line 77 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	# Procure the sent list
	$o->{actor}->procureSentList // return;

#line 80 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	# Get the entrusted keys
	my $entrustedKeys = $o->{actor}->getEntrustedKeys // return;

#line 83 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	# Transfer the data
	$o->{messageChannel}->addTransfer([$message->dependentHashes], $o->{actor}->storagePrivateRoot->unsaved, 'group data message');

#line 86 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
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

#line 102 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
### Receiving messages

sub processGroupDataMessage {
	my $o = shift;
	my $message = shift;
	my $section = shift;

#line 105 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	if (! $o->{actor}->isGroupMember($message->sender->publicKey->hash)) {
		# TODO:
		# If the sender is not a known group member, we should run actor group discovery on the sender. He may be part of us, but we don't know that yet.
		# At the very least, we should keep this message, and reconsider it if the actor group changes within the next few minutes (e.g. through another message).
		return;
	}

#line 112 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	for my $child ($section->children) {
		my $dataHandler = $o->{dataHandlers}->{$child->bytes} // next;
		$dataHandler->mergeExternalData($message->sender->store, $child, $message->source);
	}

#line 117 "Condensation/ActorWithDataTree/GroupDataSharer.pm"
	return 1;
}

package CDS::HTTPServer;

use parent -norequire, 'HTTP::Server::Simple';

sub new {
	my $class = shift;

#line 14 "Condensation/HTTPServer/HTTPServer.pm"
	my $o = $class->SUPER::new(@_);
	$o->{logger} = CDS::HTTPServer::Logger->new(*STDERR);
	$o->{handlers} = [];
	return $o;
}

sub addHandler {
	my $o = shift;
	my $handler = shift;

#line 21 "Condensation/HTTPServer/HTTPServer.pm"
	push @{$o->{handlers}}, $handler;
}

sub setLogger {
	my $o = shift;
	my $logger = shift;

#line 25 "Condensation/HTTPServer/HTTPServer.pm"
	$o->{logger} = $logger;
}

#line 28 "Condensation/HTTPServer/HTTPServer.pm"
sub logger { shift->{logger} }

sub setCorsAllowEverybody {
	my $o = shift;
	my $value = shift;

#line 31 "Condensation/HTTPServer/HTTPServer.pm"
	$o->{corsAllowEverybody} = $value;
}

#line 34 "Condensation/HTTPServer/HTTPServer.pm"
sub corsAllowEverybody { shift->{corsAllowEverybody} }

#line 36 "Condensation/HTTPServer/HTTPServer.pm"
# *** HTTP::Server::Simple interface

sub print_banner {
	my $o = shift;

#line 39 "Condensation/HTTPServer/HTTPServer.pm"
	$o->{logger}->onServerStarts($o->port);
}

sub setup {
	my $o = shift;

#line 43 "Condensation/HTTPServer/HTTPServer.pm"
	$o->{request} = CDS::HTTPServer::Request->new($o, @_);
}

sub headers {
	my $o = shift;
	my $headers = shift;

#line 47 "Condensation/HTTPServer/HTTPServer.pm"
	$o->{request}->setHeaders($headers);
}

sub handler {
	my $o = shift;

#line 51 "Condensation/HTTPServer/HTTPServer.pm"
	# Start writing the log line
	$o->{logger}->onRequestStarts($o->{request});

#line 54 "Condensation/HTTPServer/HTTPServer.pm"
	# Process the request
	my $responseCode = $o->process;
	$o->{logger}->onRequestDone($o->{request}, $responseCode);

#line 58 "Condensation/HTTPServer/HTTPServer.pm"
	# Wrap up
	$o->{request}->dropData;
	$o->{request} = undef;
	return;
}

sub process {
	my $o = shift;

#line 65 "Condensation/HTTPServer/HTTPServer.pm"
	# Run the handler
	for my $handler (@{$o->{handlers}}) {
		my $responseCode = $handler->process($o->{request}) || next;
		return $responseCode;
	}

#line 71 "Condensation/HTTPServer/HTTPServer.pm"
	# Default handler
	return $o->{request}->reply404;
}

sub bad_request {
	my $o = shift;

#line 76 "Condensation/HTTPServer/HTTPServer.pm"
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

#line 2 "Condensation/HTTPServer/HTTPServer/IdentificationHandler.pm"
	return bless {root => $root};
}

sub process {
	my $o = shift;
	my $request = shift;

#line 6 "Condensation/HTTPServer/HTTPServer/IdentificationHandler.pm"
	my $path = $request->pathAbove($o->{root}) // return;
	return if $path ne '/';

#line 9 "Condensation/HTTPServer/HTTPServer/IdentificationHandler.pm"
	# Options
	return $request->replyOptions('HEAD', 'GET') if $request->method eq 'OPTIONS';

#line 12 "Condensation/HTTPServer/HTTPServer/IdentificationHandler.pm"
	# Get
	return $request->reply200HTML('<!DOCTYPE html><html><head><title>Condensation HTTP Store</title></head><body>This is a <a href="https://condensation.io/specifications/store/http/">Condensation HTTP Store</a> server.</body></html>') if $request->method eq 'HEAD' || $request->method eq 'GET';

#line 15 "Condensation/HTTPServer/HTTPServer/IdentificationHandler.pm"
	return $request->reply405;
}

package CDS::HTTPServer::Logger;

sub new {
	my $class = shift;
	my $fileHandle = shift;

#line 2 "Condensation/HTTPServer/HTTPServer/Logger.pm"
	return bless {
		fileHandle => $fileHandle,
		lineStarted => 0,
		};
}

sub onServerStarts {
	my $o = shift;
	my $port = shift;

#line 9 "Condensation/HTTPServer/HTTPServer/Logger.pm"
	my $fh = $o->{fileHandle};
	my @t = localtime(time);
	printf $fh '%04d-%02d-%02d %02d:%02d:%02d ', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0];
	print $fh 'Server ready at http://localhost:', $port, "\n";
}

sub onRequestStarts {
	my $o = shift;
	my $request = shift;

#line 16 "Condensation/HTTPServer/HTTPServer/Logger.pm"
	my $fh = $o->{fileHandle};
	my @t = localtime(time);
	printf $fh '%04d-%02d-%02d %02d:%02d:%02d ', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0];
	print $fh $request->peerAddress, ' ', $request->method, ' ', $request->path;
	$o->{lineStarted} = 1;
}

sub onRequestError {
	my $o = shift;
	my $request = shift;

#line 24 "Condensation/HTTPServer/HTTPServer/Logger.pm"
	my $fh = $o->{fileHandle};
	print $fh "\n" if $o->{lineStarted};
	print $fh '  ', @_, "\n";
	$o->{lineStarted} = 0;
}

sub onRequestDone {
	my $o = shift;
	my $request = shift;
	my $responseCode = shift;

#line 31 "Condensation/HTTPServer/HTTPServer/Logger.pm"
	my $fh = $o->{fileHandle};
	print $fh '  ===> ' if ! $o->{lineStarted};
	print $fh ' ', $responseCode, "\n";
	$o->{lineStarted} = 0;
}

package CDS::HTTPServer::MessageGatewayHandler;

sub new {
	my $class = shift;
	my $url = shift;
	my $identity = shift;
	my $recipient = shift;

#line 2 "Condensation/HTTPServer/HTTPServer/MessageGatewayHandler.pm"
	return bless {url => $url, identity => $identity, recipient => $recipient};
}

sub process {
	my $o = shift;
	my $request = shift;

#line 6 "Condensation/HTTPServer/HTTPServer/MessageGatewayHandler.pm"
	$request->path =~ /^\/data$/ || return;
	my $store = $request->server->store;

#line 9 "Condensation/HTTPServer/HTTPServer/MessageGatewayHandler.pm"
	# Options
	return $request->replyOptions('HEAD', 'GET', 'PUT', 'POST', 'DELETE') if $request->method eq 'OPTIONS';

#line 12 "Condensation/HTTPServer/HTTPServer/MessageGatewayHandler.pm"
	# Prepare a message
	my $record = CDS::Record->new;
	$record->add('time')->addInteger(CDS->now);
	$record->add('ip')->add($request->peerAddress);
	$record->add('method')->add($request->method);
	$record->add('path')->add($request->path);
	$record->add('query string')->add($request->queryString);

#line 20 "Condensation/HTTPServer/HTTPServer/MessageGatewayHandler.pm"
	my $headersRecord = $record->add('headers');
	my $headers = $request->headers;
	for my $key (keys %$headers) {
		$headersRecord->add($key)->add($headers->{$key});
	}

#line 26 "Condensation/HTTPServer/HTTPServer/MessageGatewayHandler.pm"
	$record->add('data')->add($request->readData) if $request->remainingData;

#line 28 "Condensation/HTTPServer/HTTPServer/MessageGatewayHandler.pm"
	# Post it
	my $success = $o->{identity}->sendMessageRecord($record, undef, [$o->{recipient}]);
	return $success ? $request->reply200 : $request->reply500('Unable to send the message.');
}

package CDS::HTTPServer::Request;

sub new {
	my $class = shift;
	my $server = shift;

#line 2 "Condensation/HTTPServer/HTTPServer/Request.pm"
	my %parameters = @_;
	return bless {
		server => $server,
		method => $parameters{method},
		path => $parameters{path},
		protocol => $parameters{protocol},
		queryString => $parameters{query_string},
		localName => $parameters{localname},
		localPort => $parameters{localport},
		peerName => $parameters{peername},
		peerAddress => $parameters{peeraddr},
		peerPort => $parameters{peerport},
		headers => {},
		remainingData => 0,
		};
}

#line 19 "Condensation/HTTPServer/HTTPServer/Request.pm"
sub server { shift->{server} }
sub method { shift->{method} }
sub path { shift->{path} }
sub queryString { shift->{queryString} }
sub peerAddress { shift->{peerAddress} }
sub peerPort { shift->{peerPort} }
sub headers { shift->{headers} }
sub remainingData { shift->{remainingData} }

#line 28 "Condensation/HTTPServer/HTTPServer/Request.pm"
# *** Request configuration

sub setHeaders {
	my $o = shift;
	my $newHeaders = shift;

#line 31 "Condensation/HTTPServer/HTTPServer/Request.pm"
	# Set the headers
	while (scalar @$newHeaders) {
		my $key = shift @$newHeaders;
		my $value = shift @$newHeaders;
		$o->{headers}->{lc($key)} = $value;
	}

#line 38 "Condensation/HTTPServer/HTTPServer/Request.pm"
	# Keep track of the data sent along with the request
	$o->{remainingData} = $o->{headers}->{'content-length'} // 0;
}

sub pathAbove {
	my $o = shift;
	my $root = shift;

#line 43 "Condensation/HTTPServer/HTTPServer/Request.pm"
	$root .= '/' if $root !~ /\/$/;
	return if substr($o->{path}, 0, length $root) ne $root;
	return substr($o->{path}, length($root) - 1);
}

#line 48 "Condensation/HTTPServer/HTTPServer/Request.pm"
# *** Request data

#line 50 "Condensation/HTTPServer/HTTPServer/Request.pm"
# Reads the request data
sub readData {
	my $o = shift;

#line 52 "Condensation/HTTPServer/HTTPServer/Request.pm"
	my @buffers;
	while ($o->{remainingData} > 0) {
		my $read = sysread(STDIN, my $buffer, $o->{remainingData}) || return;
		$o->{remainingData} -= $read;
		push @buffers, $buffer;
	}

#line 59 "Condensation/HTTPServer/HTTPServer/Request.pm"
	return join('', @buffers);
}

#line 62 "Condensation/HTTPServer/HTTPServer/Request.pm"
# Read the request data and writes it directly to a file handle
sub copyDataAndCalculateHash {
	my $o = shift;
	my $fh = shift;

#line 64 "Condensation/HTTPServer/HTTPServer/Request.pm"
	my $sha = Digest::SHA->new(256);
	while ($o->{remainingData} > 0) {
		my $read = sysread(STDIN, my $buffer, $o->{remainingData}) || return;
		$o->{remainingData} -= $read;
		$sha->add($buffer);
		print $fh $buffer;
	}

#line 72 "Condensation/HTTPServer/HTTPServer/Request.pm"
	return $sha->digest;
}

#line 75 "Condensation/HTTPServer/HTTPServer/Request.pm"
# Reads and drops the request data
sub dropData {
	my $o = shift;

#line 77 "Condensation/HTTPServer/HTTPServer/Request.pm"
	while ($o->{remainingData} > 0) {
		$o->{remainingData} -= read(STDIN, my $buffer, $o->{remainingData}) || return;
	}
}

#line 82 "Condensation/HTTPServer/HTTPServer/Request.pm"
# *** Query string

sub parseQueryString {
	my $o = shift;

#line 85 "Condensation/HTTPServer/HTTPServer/Request.pm"
	return {} if ! defined $o->{queryString};

#line 87 "Condensation/HTTPServer/HTTPServer/Request.pm"
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

#line 98 "Condensation/HTTPServer/HTTPServer/Request.pm"
	return $values;
}

sub uri_decode {
	my $encoded = shift;

#line 102 "Condensation/HTTPServer/HTTPServer/Request.pm"
	$encoded =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
	return $encoded;
}

#line 106 "Condensation/HTTPServer/HTTPServer/Request.pm"
# *** Condensation signature

sub checkSignature {
	my $o = shift;
	my $store = shift;
	my $contentBytesToSign = shift;

#line 109 "Condensation/HTTPServer/HTTPServer/Request.pm"
	# Check the date
	my $dateString = $o->{headers}->{'condensation-date'} // $o->{headers}->{'date'} // return;
	my $date = HTTP::Date::str2time($dateString) // return;
	my $now = time;
	return if $date < $now - 120 || $date > $now + 60;

#line 115 "Condensation/HTTPServer/HTTPServer/Request.pm"
	# Get and check the actor
	my $actorHash = CDS::Hash->fromHex($o->{headers}->{'condensation-actor'}) // return;
	my ($publicKeyObject, $error) = $store->get($actorHash);
	return if defined $error;
	return if ! $publicKeyObject->calculateHash->equals($actorHash);
	my $publicKey = CDS::PublicKey->fromObject($publicKeyObject) // return;

#line 122 "Condensation/HTTPServer/HTTPServer/Request.pm"
	# Text to sign
	my $bytesToSign = $dateString."\0".uc($o->{method})."\0".$o->{headers}->{'host'}.$o->{path};
	$bytesToSign .= "\0".$contentBytesToSign if defined $contentBytesToSign;
	my $hashToSign = CDS::Hash->calculateFor($bytesToSign);

#line 127 "Condensation/HTTPServer/HTTPServer/Request.pm"
	# Check the signature
	my $signatureString = $o->{headers}->{'condensation-signature'} // return;
	$signatureString =~ /^\s*([0-9a-z]{512,512})\s*$/ // return;
	my $signature = pack('H*', $1);
	return if ! $publicKey->verifyHash($hashToSign, $signature);

#line 133 "Condensation/HTTPServer/HTTPServer/Request.pm"
	# Return the verified actor hash
	return $actorHash;
}

#line 137 "Condensation/HTTPServer/HTTPServer/Request.pm"
# *** Reply functions

sub reply200 {
	my $o = shift;
	my $content = shift // '';

#line 140 "Condensation/HTTPServer/HTTPServer/Request.pm"
	return length $content ? $o->reply(200, 'OK', &textContentType, $content) : $o->reply(204, 'No Content', {});
}

sub reply200Bytes {
	my $o = shift;
	my $content = shift // '';

#line 144 "Condensation/HTTPServer/HTTPServer/Request.pm"
	return length $content ? $o->reply(200, 'OK', {'Content-Type' => 'application/octet-stream'}, $content) : $o->reply(204, 'No Content', {});
}

sub reply200HTML {
	my $o = shift;
	my $content = shift // '';

#line 148 "Condensation/HTTPServer/HTTPServer/Request.pm"
	return length $content ? $o->reply(200, 'OK', {'Content-Type' => 'text/html; charset=utf-8'}, $content) : $o->reply(204, 'No Content', {});
}

sub replyOptions {
	my $o = shift;

#line 152 "Condensation/HTTPServer/HTTPServer/Request.pm"
	my $headers = {};
	$headers->{'Allow'} = join(', ', @_, 'OPTIONS');
	$headers->{'Access-Control-Allow-Methods'} = join(', ', @_, 'OPTIONS') if $o->{server}->corsAllowEverybody && $o->{headers}->{'origin'};
	return $o->reply(200, 'OK', $headers);
}

sub replyFatalError {
	my $o = shift;

#line 159 "Condensation/HTTPServer/HTTPServer/Request.pm"
	$o->{server}->{logger}->onRequestError($o, @_);
	return $o->reply500;
}

sub reply303 {
	my $o = shift;
	my $location = shift;
	 $o->reply(303, 'See Other', {'Location' => $location}) }
#line 164 "Condensation/HTTPServer/HTTPServer/Request.pm"
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

#line 172 "Condensation/HTTPServer/HTTPServer/Request.pm"
	# Content-related headers
	$headers->{'Content-Length'} = length($content);

#line 175 "Condensation/HTTPServer/HTTPServer/Request.pm"
	# Origin
	if ($o->{server}->corsAllowEverybody && (my $origin = $o->{headers}->{'origin'})) {
		$headers->{'Access-Control-Allow-Origin'} = $origin;
		$headers->{'Access-Control-Allow-Headers'} = 'Content-Type';
		$headers->{'Access-Control-Max-Age'} = '86400';
	}

#line 182 "Condensation/HTTPServer/HTTPServer/Request.pm"
	# Write the reply
	print 'HTTP/1.1 ', $responseCode, ' ', $responseLabel, "\r\n";
	for my $key (keys %$headers) {
		print $key, ': ', $headers->{$key}, "\r\n";
	}
	print "\r\n";
	print $content if $o->{method} ne 'HEAD';

#line 190 "Condensation/HTTPServer/HTTPServer/Request.pm"
	# Return the response code
	return $responseCode;
}

#line 194 "Condensation/HTTPServer/HTTPServer/Request.pm"
sub textContentType { {'Content-Type' => 'text/plain; charset=utf-8'} }

package CDS::HTTPServer::StaticContentHandler;

sub new {
	my $class = shift;
	my $path = shift;
	my $content = shift;
	my $contentType = shift;

#line 2 "Condensation/HTTPServer/HTTPServer/StaticContentHandler.pm"
	return bless {
		path => $path,
		content => $content,
		contentType => $contentType,
		};
}

sub process {
	my $o = shift;
	my $request = shift;

#line 10 "Condensation/HTTPServer/HTTPServer/StaticContentHandler.pm"
	return if $request->path ne $o->{path};

#line 12 "Condensation/HTTPServer/HTTPServer/StaticContentHandler.pm"
	# Options
	return $request->replyOptions('HEAD', 'GET') if $request->method eq 'OPTIONS';

#line 15 "Condensation/HTTPServer/HTTPServer/StaticContentHandler.pm"
	# GET
	return $request->reply(200, 'OK', {'Content-Type' => $o->{contentType}}, $o->{content}) if $request->method eq 'GET';

#line 18 "Condensation/HTTPServer/HTTPServer/StaticContentHandler.pm"
	# Everything else
	return $request->reply405;
}

package CDS::HTTPServer::StaticFilesHandler;

sub new {
	my $class = shift;
	my $root = shift;
	my $folder = shift;
	my $defaultFile = shift // '';

#line 2 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
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

#line 25 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
sub folder { shift->{folder} }
sub defaultFile { shift->{defaultFile} }
sub mimeTypesByExtension { shift->{mimeTypesByExtension} }

sub setContentType {
	my $o = shift;
	my $extension = shift;
	my $contentType = shift;

#line 30 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
	$o->{mimeTypesByExtension}->{$extension} = $contentType;
}

sub process {
	my $o = shift;
	my $request = shift;

#line 34 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
	# Options
	return $request->replyOptions('HEAD', 'GET') if $request->method eq 'OPTIONS';

#line 37 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
	# Get
	return $o->get($request) if $request->method eq 'GET' || $request->method eq 'HEAD';

#line 40 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
	# Anything else
	return $request->reply405;
}

sub get {
	my $o = shift;
	my $request = shift;

#line 45 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
	my $path = $request->pathAbove($o->{root}) // return;
	return $o->deliverFileForPath($request, $path);
}

sub deliverFileForPath {
	my $o = shift;
	my $request = shift;
	my $path = shift;

#line 50 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
	# Hidden files (starting with a dot), as well as "." and ".." never exist
	for my $segment (split /\/+/, $path) {
		return $request->reply404 if $segment =~ /^\./;
	}

#line 55 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
	# If a folder is requested, we serve the default file
	my $file = $o->{folder}.$path;
	if (-d $file) {
		return $request->reply404 if ! length $o->{defaultFile};
		return $request->reply303($request->path.'/') if $file !~ /\/$/;
		$file .= $o->{defaultFile};
	}

#line 63 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
	return $o->deliverFile($request, $file);
}

sub deliverFile {
	my $o = shift;
	my $request = shift;
	my $file = shift;
	my $contentType = shift // $o->guessContentType($file);

#line 67 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
	my $bytes = $o->readFile($file) // return $request->reply404;
	return $request->reply(200, 'OK', {'Content-Type' => $contentType}, $bytes);
}

#line 71 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
# Guesses the content type from the extension
sub guessContentType {
	my $o = shift;
	my $file = shift;

#line 73 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
	my $extension = $file =~ /\.([A-Za-z0-9]*)$/ ? lc($1) : '';
	return $o->{mimeTypesByExtension}->{$extension} // 'application/octet-stream';
}

#line 77 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
# Reads a file
sub readFile {
	my $o = shift;
	my $file = shift;

#line 79 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
	open(my $fh, '<:bytes', $file) || return;
	if (! -f $fh) {
		close $fh;
		return;
	}

#line 85 "Condensation/HTTPServer/HTTPServer/StaticFilesHandler.pm"
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

#line 2 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
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

#line 13 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	my $path = $request->pathAbove($o->{root}) // return;

#line 15 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Objects request
	if ($request->path =~ /^\/objects\/([0-9a-f]{64})$/) {
		my $hash = CDS::Hash->fromHex($1);
		return $o->objects($request, $hash);
	}

#line 21 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Box request
	if ($request->path =~ /^\/accounts\/([0-9a-f]{64})\/(messages|private|public)$/) {
		my $accountHash = CDS::Hash->fromHex($1);
		my $boxLabel = $2;
		return $o->box($request, $accountHash, $boxLabel);
	}

#line 28 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Box entry request
	if ($request->path =~ /^\/accounts\/([0-9a-f]{64})\/(messages|private|public)\/([0-9a-f]{64})$/) {
		my $accountHash = CDS::Hash->fromHex($1);
		my $boxLabel = $2;
		my $hash = CDS::Hash->fromHex($3);
		return $o->boxEntry($request, $accountHash, $boxLabel, $hash);
	}

#line 36 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Account request
	if ($request->path =~ /^\/accounts\/([0-9a-f]{64})$/) {
		return $request->replyOptions if $request->method eq 'OPTIONS';
		return $request->reply405;
	}

#line 42 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Accounts request
	if ($request->path =~ /^\/accounts$/) {
		return $o->accounts($request);
	}

#line 47 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Other requests on /objects or /accounts
	if ($request->path =~ /^\/(accounts|objects)(\/|$)/) {
		return $request->reply404;
	}

#line 52 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Nothing for us
	return;
}

sub objects {
	my $o = shift;
	my $request = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 57 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Options
	if ($request->method eq 'OPTIONS') {
		return $request->replyOptions('HEAD', 'GET', 'PUT', 'POST');
	}

#line 62 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Retrieve object
	if ($request->method eq 'HEAD' || $request->method eq 'GET') {
		my ($object, $error) = $o->{store}->get($hash);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply404 if ! $object;
		# We don't check the SHA256 sum here - this should be done by the client
		return $request->reply200Bytes($object->bytes);
	}

#line 71 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Put object
	if ($request->method eq 'PUT') {
		my $bytes = $request->readData // return $request->reply400('No data received.');
		my $object = CDS::Object->fromBytes($bytes) // return $request->reply400('Not a Condensation object.');
		return $request->reply400('SHA256 sum does not match hash.') if $o->{checkPutHash} && ! $object->calculateHash->equals($hash);

#line 77 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
		if ($o->{checkSignatures}) {
			my $checkSignatureStore = CDS::CheckSignatureStore->new($o->{store});
			$checkSignatureStore->put($hash, $object);
			return $request->reply403 if ! $request->checkSignature($checkSignatureStore);
		}

#line 83 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
		my $error = $o->{store}->put($hash, $object);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200;
	}

#line 88 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Book object
	if ($request->method eq 'POST') {
		return $request->reply403 if $o->{checkSignatures} && ! $request->checkSignature($o->{store});
		return $request->reply400('You cannot send data when booking an object.') if $request->remainingData;
		my ($booked, $error) = $o->{store}->book($hash);
		return $request->replyFatalError($error) if defined $error;
		return $booked ? $request->reply200 : $request->reply404;
	}

#line 97 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	return $request->reply405;
}

sub box {
	my $o = shift;
	my $request = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;

#line 101 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Options
	if ($request->method eq 'OPTIONS') {
		return $request->replyOptions('HEAD', 'GET', 'PUT', 'POST');
	}

#line 106 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# List box
	if ($request->method eq 'HEAD' || $request->method eq 'GET') {
		my $watch = $request->headers->{'condensation-watch'} // '';
		my $timeout = $watch =~ /^(\d+)\s*ms$/ ? $1 + 0 : 0;
		$timeout = $o->{maximumWatchTimeout} if $timeout > $o->{maximumWatchTimeout};
		my ($hashes, $error) = $o->{store}->list($accountHash, $boxLabel, $timeout);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200Bytes(join('', map { $_->bytes } @$hashes));
	}

#line 116 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	return $request->reply405;
}

sub boxEntry {
	my $o = shift;
	my $request = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 120 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Options
	if ($request->method eq 'OPTIONS') {
		return $request->replyOptions('HEAD', 'PUT', 'DELETE');
	}

#line 125 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Add
	if ($request->method eq 'PUT') {
		if ($o->{checkSignatures}) {
			my $actorHash = $request->checkSignature($o->{store});
			return $request->reply403 if ! $actorHash;
			return $request->reply403 if ! $o->verifyAddition($actorHash, $accountHash, $boxLabel, $hash);
		}

#line 133 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
		my $error = $o->{store}->add($accountHash, $boxLabel, $hash);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200;
	}

#line 138 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Remove
	if ($request->method eq 'DELETE') {
		if ($o->{checkSignatures}) {
			my $actorHash = $request->checkSignature($o->{store});
			return $request->reply403 if ! $actorHash;
			return $request->reply403 if ! $o->verifyRemoval($actorHash, $accountHash, $boxLabel, $hash);
		}

#line 146 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
		my ($booked, $error) = $o->{store}->remove($accountHash, $boxLabel, $hash);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200;
	}

#line 151 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	return $request->reply405;
}

sub accounts {
	my $o = shift;
	my $request = shift;

#line 155 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Options
	if ($request->method eq 'OPTIONS') {
		return $request->replyOptions('POST');
	}

#line 160 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Modify boxes
	if ($request->method eq 'POST') {
		my $bytes = $request->readData // return $request->reply400('No data received.');
		my $modifications = CDS::StoreModifications->fromBytes($bytes);
		return $request->reply400('Invalid modifications.') if ! $modifications;

#line 166 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
		if ($o->{checkSignatures}) {
			my $actorHash = $request->checkSignature(CDS::CheckSignatureStore->new($o->{store}, $modifications->objects), $bytes);
			return $request->reply403 if ! $actorHash;
			return $request->reply403 if ! $o->verifyModifications($actorHash, $modifications);
		}

#line 172 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
		my $error = $o->{store}->modify($modifications);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200;
	}

#line 177 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	return $request->reply405;
}

sub verifyModifications {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';
	my $modifications = shift;

#line 181 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	for my $operation (@{$modifications->additions}) {
		return if ! $o->verifyAddition($actorHash, $operation->{accountHash}, $operation->{boxLabel}, $operation->{hash});
	}

#line 185 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	for my $operation (@{$modifications->removals}) {
		return if ! $o->verifyRemoval($actorHash, $operation->{accountHash}, $operation->{boxLabel}, $operation->{hash});
	}

#line 189 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	return 1;
}

sub verifyAddition {
	my $o = shift;
	my $actorHash = shift; die 'wrong type '.ref($actorHash).' for $actorHash' if defined $actorHash && ref $actorHash ne 'CDS::Hash';
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 193 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
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

#line 199 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	return 1 if $accountHash->equals($actorHash);

#line 201 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Get the envelope
	my ($bytes, $error) = $o->{store}->get($hash);
	return if defined $error;
	return 1 if ! defined $bytes;
	my $record = CDS::Record->fromObject(CDS::Object->fromBytes($bytes)) // return;

#line 207 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	# Allow anyone listed under "updated by"
	my $actorHashBytes24 = substr($actorHash->bytes, 0, 24);
	for my $child ($record->child('updated by')->children) {
		my $hashBytes24 = $child->bytes;
		next if length $hashBytes24 != 24;
		return 1 if $hashBytes24 eq $actorHashBytes24;
	}

#line 215 "Condensation/HTTPServer/HTTPServer/StoreHandler.pm"
	return;
}

# A Condensation store accessed through HTTP or HTTPS.
package CDS::HTTPStore;

use parent -norequire, 'CDS::Store';

sub forUrl {
	my $class = shift;
	my $url = shift;

#line 10 "Condensation/Stores/HTTPStore.pm"
	$url =~ /^(http|https):\/\// || return;
	return $class->new($url);
}

sub new {
	my $class = shift;
	my $url = shift;

#line 15 "Condensation/Stores/HTTPStore.pm"
	return bless {url => $url};
}

sub id {
	my $o = shift;
	 $o->{url} }

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 21 "Condensation/Stores/HTTPStore.pm"
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

#line 28 "Condensation/Stores/HTTPStore.pm"
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

#line 36 "Condensation/Stores/HTTPStore.pm"
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

#line 43 "Condensation/Stores/HTTPStore.pm"
	my $boxUrl = $o->{url}.'/accounts/'.$accountHash->hex.'/'.$boxLabel;
	my $headers = HTTP::Headers->new;
	$headers->header('Condensation-Watch' => $timeout.' ms') if $timeout > 0;
	my $response = $o->request('GET', $boxUrl, $headers);
	return undef, 'list ==> HTTP '.$response->status_line if ! $response->is_success;
	my $bytes = $response->decoded_content(charset => 'none');

#line 50 "Condensation/Stores/HTTPStore.pm"
	if (length($bytes) % 32 != 0) {
		print STDERR 'old procotol', "\n";
		my $hashes = [];
		for my $line (split /\n/, $bytes) {
			push @$hashes, CDS::Hash->fromHex($line) // next;
		}
		return $hashes;
	}

#line 59 "Condensation/Stores/HTTPStore.pm"
	my $countHashes = int(length($bytes) / 32);
	return [map { CDS::Hash->fromBytes(substr($bytes, $_ * 32, 32)) } 0 .. $countHashes - 1];
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 64 "Condensation/Stores/HTTPStore.pm"
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

#line 71 "Condensation/Stores/HTTPStore.pm"
	my $headers = HTTP::Headers->new;
	my $response = $o->request('DELETE', $o->{url}.'/accounts/'.$accountHash->hex.'/'.$boxLabel.'/'.$hash->hex, $headers, $keyPair);
	return if $response->is_success;
	return 'remove ==> HTTP '.$response->status_line;
}

sub modify {
	my $o = shift;
	my $modifications = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 78 "Condensation/Stores/HTTPStore.pm"
	my $bytes = $modifications->toRecord->toObject->bytes;
	my $headers = HTTP::Headers->new;
	$headers->header('Content-Type' => 'application/condensation-modifications');
	my $response = $o->request('POST', $o->{url}.'/accounts', $headers, $keyPair, $bytes, 1);
	return if $response->is_success;
	return 'modify ==> HTTP '.$response->status_line;
}

#line 86 "Condensation/Stores/HTTPStore.pm"
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
#line 88 "Condensation/Stores/HTTPStore.pm"
	$headers->date(time);
	$headers->header('User-Agent' => CDS->version);

#line 91 "Condensation/Stores/HTTPStore.pm"
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

#line 103 "Condensation/Stores/HTTPStore.pm"
	return LWP::UserAgent->new->request(HTTP::Request->new($method, $url, $headers, $data));
}

# Models a hash, and offers binary and hexadecimal representation.
package CDS::Hash;

sub fromBytes {
	my $class = shift;
	my $hashBytes = shift // return;

#line 5 "Condensation/Serialization/Hash.pm"
	return if length $hashBytes != 32;
	return bless \$hashBytes;
}

sub fromHex {
	my $class = shift;
	my $hashHex = shift // return;

#line 10 "Condensation/Serialization/Hash.pm"
	$hashHex =~ /^\s*([a-fA-F0-9]{64,64})\s*$/ || return;
	my $hashBytes = pack('H*', $hashHex);
	return bless \$hashBytes;
}

sub calculateFor {
	my $class = shift;
	my $bytes = shift;

#line 16 "Condensation/Serialization/Hash.pm"
	# The Perl built-in SHA256 implementation is a tad faster than our SHA256 implementation.
	#return $class->fromBytes(CDS::C::sha256($bytes));
	return $class->fromBytes(Digest::SHA::sha256($bytes));
}

sub hex {
	my $o = shift;

#line 22 "Condensation/Serialization/Hash.pm"
	return unpack('H*', $$o);
}

sub shortHex {
	my $o = shift;

#line 26 "Condensation/Serialization/Hash.pm"
	return unpack('H*', substr($$o, 0, 8)) . '…';
}

sub bytes {
	my $o = shift;
	 $$o }

sub equals {
	my $this = shift;
	my $that = shift;

#line 32 "Condensation/Serialization/Hash.pm"
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

#line 4 "Condensation/Serialization/HashAndKey.pm"
	return bless {
		hash => $hash,
		key => $key,
		};
}

#line 10 "Condensation/Serialization/HashAndKey.pm"
sub hash { shift->{hash} }
sub key { shift->{key} }

package CDS::ISODate;

#line 3 "Condensation/ISODate.pm"
# Parses a date accepting various ISO variants, and calculates the timestamp using Time::Local
sub parse {
	my $class = shift;
	my $dateString = shift // return;

#line 5 "Condensation/ISODate.pm"
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

#line 22 "Condensation/ISODate.pm"
# Returns a properly formatted string with a precision of 1 day (i.e., the "date" only)
sub dayString {
	my $class = shift;
	my $time = shift // 1000 * time;

#line 24 "Condensation/ISODate.pm"
	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3]);
}

#line 28 "Condensation/ISODate.pm"
# Returns a properly formatted string with a precision of 1 second (i.e., "time of day" and "date") using UTC
sub secondString {
	my $class = shift;
	my $time = shift // 1000 * time;

#line 30 "Condensation/ISODate.pm"
	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

#line 34 "Condensation/ISODate.pm"
# Returns a properly formatted string with a precision of 1 second (i.e., "time of day" and "date") using UTC
sub millisecondString {
	my $class = shift;
	my $time = shift // 1000 * time;

#line 36 "Condensation/ISODate.pm"
	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02dT%02d:%02d:%02d.%03dZ', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0], int($time) % 1000);
}

#line 40 "Condensation/ISODate.pm"
# Returns a properly formatted string with a precision of 1 second (i.e., "time of day" and "date") using local time
sub localSecondString {
	my $class = shift;
	my $time = shift // 1000 * time;

#line 42 "Condensation/ISODate.pm"
	my @t = localtime($time / 1000);
	return sprintf('%04d-%02d-%02dT%02d:%02d:%02d', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

package CDS::InMemoryStore;

sub create {
	my $class = shift;

#line 2 "Condensation/Stores/InMemoryStore.pm"
	return CDS::InMemoryStore->new('inMemoryStore:'.unpack('H*', CDS->randomBytes(16)));
}

sub new {
	my $o = shift;
	my $id = shift;

#line 6 "Condensation/Stores/InMemoryStore.pm"
	return bless {
		id => $id,
		objects => {},
		accounts => {},
		};
}

#line 13 "Condensation/Stores/InMemoryStore.pm"
sub id { shift->{id} }

sub accountForWriting {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 16 "Condensation/Stores/InMemoryStore.pm"
	my $account = $o->{accounts}->{$hash->bytes};
	return $account if $account;
	return $o->{accounts}->{$hash->bytes} = {messages => {}, private => {}, public => {}};
}

#line 21 "Condensation/Stores/InMemoryStore.pm"
# *** Store interface

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 24 "Condensation/Stores/InMemoryStore.pm"
	my $entry = $o->{objects}->{$hash->bytes} // return;
	return $entry->{object};
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 29 "Condensation/Stores/InMemoryStore.pm"
	my $entry = $o->{objects}->{$hash->bytes} // return;
	$entry->{booked} = CDS->now;
	return 1;
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 35 "Condensation/Stores/InMemoryStore.pm"
	$o->{objects}->{$hash->bytes} = {object => $object, booked => CDS->now};
	return;
}

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 40 "Condensation/Stores/InMemoryStore.pm"
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

#line 46 "Condensation/Stores/InMemoryStore.pm"
	my $box = $o->accountForWriting($accountHash)->{$boxLabel} // return;
	$box->{$hash->bytes} = $hash;
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 51 "Condensation/Stores/InMemoryStore.pm"
	my $box = $o->accountForWriting($accountHash)->{$boxLabel} // return;
	delete $box->{$hash->bytes};
}

sub modify {
	my $o = shift;
	my $modifications = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 56 "Condensation/Stores/InMemoryStore.pm"
	return $modifications->executeIndividually($o, $keyPair);
}

#line 59 "Condensation/Stores/InMemoryStore.pm"
# Garbage collection

sub collectGarbage {
	my $o = shift;
	my $graceTime = shift;

#line 62 "Condensation/Stores/InMemoryStore.pm"
	# Mark all objects as not used
	for my $entry (values @{$o->{objects}}) {
		$entry->{inUse} = 0;
	}

#line 67 "Condensation/Stores/InMemoryStore.pm"
	# Mark all objects newer than the grace time
	for my $entry (values @{$o->{objects}}) {
		$o->markEntry($entry) if $entry->{booked} > $graceTime;
	}

#line 72 "Condensation/Stores/InMemoryStore.pm"
	# Mark all objects referenced from a box
	for my $account (values @{$o->{accounts}}) {
		for my $hash (values @{$account->{messages}}) { $o->markHash($hash); }
		for my $hash (values @{$account->{private}}) { $o->markHash($hash); }
		for my $hash (values @{$account->{public}}) { $o->markHash($hash); }
	}

#line 79 "Condensation/Stores/InMemoryStore.pm"
	# Remove empty accounts
	while (my ($key, $account) = each %{$o->{accounts}}) {
		next if scalar @{$account->{messages}};
		next if scalar @{$account->{private}};
		next if scalar @{$account->{public}};
		delete $o->{accounts}->{$key};
	}

#line 87 "Condensation/Stores/InMemoryStore.pm"
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
#line 95 "Condensation/Stores/InMemoryStore.pm"
	my $child = $o->{objects}->{$hash->bytes} // return;
	$o->mark($child);
}

sub markEntry {
	my $o = shift;
	my $entry = shift;
			# private
#line 100 "Condensation/Stores/InMemoryStore.pm"
	return if $entry->{inUse};
	$entry->{inUse} = 1;

#line 103 "Condensation/Stores/InMemoryStore.pm"
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

#line 4 "Condensation/Stores/Transfer.pm"
	for my $hash (@$hashes) {
		my ($missing, $store, $storeError) = $o->recursiveTransfer($hash, $sourceStore, $destinationStore, {});
		return $missing if $missing;
		return undef, $store, $storeError if defined $storeError;
	}

#line 10 "Condensation/Stores/Transfer.pm"
	return;
}

sub recursiveTransfer {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $sourceStore = shift;
	my $destinationStore = shift;
	my $done = shift;
		# private
#line 14 "Condensation/Stores/Transfer.pm"
	return if $done->{$hash->bytes};
	$done->{$hash->bytes} = 1;

#line 17 "Condensation/Stores/Transfer.pm"
	# Book
	my ($booked, $bookError) = $destinationStore->book($hash, $o);
	return undef, $destinationStore, $bookError if defined $bookError;
	return if $booked;

#line 22 "Condensation/Stores/Transfer.pm"
	# Get
	my ($object, $getError) = $sourceStore->get($hash, $o);
	return undef, $sourceStore, $getError if defined $getError;
	return CDS::MissingObject->new($hash, $sourceStore) if ! defined $object;

#line 27 "Condensation/Stores/Transfer.pm"
	# Process children
	for my $child ($object->hashes) {
		my ($missing, $store, $error) = $o->recursiveTransfer($child, $sourceStore, $destinationStore, $done);
		return undef, $store, $error if defined $error;
		if (defined $missing) {
			push @{$missing->{path}}, $child;
			return $missing;
		}
	}

#line 37 "Condensation/Stores/Transfer.pm"
	# Put
	my $putError = $destinationStore->put($hash, $object, $o);
	return undef, $destinationStore, $putError if defined $putError;
	return;
}

sub createPublicEnvelope {
	my $o = shift;
	my $contentHash = shift; die 'wrong type '.ref($contentHash).' for $contentHash' if defined $contentHash && ref $contentHash ne 'CDS::Hash';

#line 4 "Condensation/Actors/CreateEnvelope.pm"
	my $envelope = CDS::Record->new;
	$envelope->add('content')->addHash($contentHash);
	$envelope->add('signature')->add($o->signHash($contentHash));
	return $envelope;
}

sub createPrivateEnvelope {
	my $o = shift;
	my $contentHashAndKey = shift;
	my $recipientPublicKeys = shift;

#line 11 "Condensation/Actors/CreateEnvelope.pm"
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

#line 19 "Condensation/Actors/CreateEnvelope.pm"
	my $contentRecord = CDS::Record->new;
	$contentRecord->add('store')->addText($storeUrl);
	$contentRecord->add('sender')->addHash($o->publicKey->hash);
	$contentRecord->addRecord($messageRecord->children);
	my $contentObject = $contentRecord->toObject;
	my $contentKey = CDS->randomKey;
	my $encryptedContent = CDS::C::aesCrypt($contentObject->bytes, $contentKey, CDS->zeroCTR);
	#my $hashToSign = $contentObject->calculateHash;	# prior to 2020-05-05
	my $hashToSign = CDS::Hash->calculateFor($encryptedContent);

#line 29 "Condensation/Actors/CreateEnvelope.pm"
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
#line 39 "Condensation/Actors/CreateEnvelope.pm"
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

#line 2 "Condensation/Actors/KeyPair.pm"
	# Generate a new private key
	my $rsaPrivateKey = CDS::C::privateKeyGenerate();

#line 5 "Condensation/Actors/KeyPair.pm"
	# Serialize the public key
	my $rsaPublicKey = CDS::C::publicKeyFromPrivateKey($rsaPrivateKey);
	my $record = CDS::Record->new;
	$record->add('e')->add(CDS::C::publicKeyE($rsaPublicKey));
	$record->add('n')->add(CDS::C::publicKeyN($rsaPublicKey));
	my $publicKey = CDS::PublicKey->fromObject($record->toObject);

#line 12 "Condensation/Actors/KeyPair.pm"
	# Return a new CDS::KeyPair instance
	return CDS::KeyPair->new($publicKey, $rsaPrivateKey);
}

sub fromFile {
	my $class = shift;
	my $file = shift;

#line 17 "Condensation/Actors/KeyPair.pm"
	my $bytes = CDS->readBytesFromFile($file) // return;
	my $record = CDS::Record->fromObject(CDS::Object->fromBytes($bytes));
	return $class->fromRecord($record);
}

sub fromHex {
	my $class = shift;
	my $hex = shift;

#line 23 "Condensation/Actors/KeyPair.pm"
	return $class->fromRecord(CDS::Record->fromObject(CDS::Object->fromBytes(pack 'H*', $hex)));
}

sub fromRecord {
	my $class = shift;
	my $record = shift // return; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 27 "Condensation/Actors/KeyPair.pm"
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

#line 36 "Condensation/Actors/KeyPair.pm"
	return bless {
		publicKey => $publicKey,			# The public key
		rsaPrivateKey => $rsaPrivateKey,	# The private key
		};
}

#line 42 "Condensation/Actors/KeyPair.pm"
sub publicKey { shift->{publicKey} }
sub rsaPrivateKey { shift->{rsaPrivateKey} }

#line 45 "Condensation/Actors/KeyPair.pm"
### Serialization ###

sub toRecord {
	my $o = shift;

#line 48 "Condensation/Actors/KeyPair.pm"
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

#line 58 "Condensation/Actors/KeyPair.pm"
	my $object = $o->toRecord->toObject;
	return unpack('H*', $object->header).unpack('H*', $object->data);
}

sub writeToFile {
	my $o = shift;
	my $file = shift;

#line 63 "Condensation/Actors/KeyPair.pm"
	my $object = $o->toRecord->toObject;
	return CDS->writeBytesToFile($file, $object->bytes);
}

#line 67 "Condensation/Actors/KeyPair.pm"
### Private key interface ###

sub decrypt {
	my $o = shift;
	my $bytes = shift;
		# decrypt(bytes) -> bytes
#line 70 "Condensation/Actors/KeyPair.pm"
	return CDS::C::privateKeyDecrypt($o->{rsaPrivateKey}, $bytes);
}

sub sign {
	my $o = shift;
	my $digest = shift;
		# sign(bytes) -> bytes
#line 74 "Condensation/Actors/KeyPair.pm"
	return CDS::C::privateKeySign($o->{rsaPrivateKey}, $digest);
}

sub signHash {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
		# signHash(hash) -> bytes
#line 78 "Condensation/Actors/KeyPair.pm"
	return CDS::C::privateKeySign($o->{rsaPrivateKey}, $hash->bytes);
}

#line 81 "Condensation/Actors/KeyPair.pm"
### Retrieval ###

#line 83 "Condensation/Actors/KeyPair.pm"
# Retrieves an object from one of the stores, and decrypts it.
sub getAndDecrypt {
	my $o = shift;
	my $hashAndKey = shift; die 'wrong type '.ref($hashAndKey).' for $hashAndKey' if defined $hashAndKey && ref $hashAndKey ne 'CDS::HashAndKey';
	my $store = shift;

#line 85 "Condensation/Actors/KeyPair.pm"
	my ($object, $error) = $store->get($hashAndKey->hash, $o);
	return undef, undef, $error if defined $error;
	return undef, 'Not found.', undef if ! $object;
	return $object->crypt($hashAndKey->key);
}

#line 91 "Condensation/Actors/KeyPair.pm"
# Retrieves an object from one of the stores, and parses it as record.
sub getRecord {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $store = shift;

#line 93 "Condensation/Actors/KeyPair.pm"
	my ($object, $error) = $store->get($hash, $o);
	return undef, undef, undef, $error if defined $error;
	return undef, undef, 'Not found.', undef if ! $object;
	my $record = CDS::Record->fromObject($object) // return undef, undef, 'Not a record.', undef;
	return $record, $object;
}

#line 100 "Condensation/Actors/KeyPair.pm"
# Retrieves an object from one of the stores, decrypts it, and parses it as record.
sub getAndDecryptRecord {
	my $o = shift;
	my $hashAndKey = shift; die 'wrong type '.ref($hashAndKey).' for $hashAndKey' if defined $hashAndKey && ref $hashAndKey ne 'CDS::HashAndKey';
	my $store = shift;

#line 102 "Condensation/Actors/KeyPair.pm"
	my ($object, $error) = $store->get($hashAndKey->hash, $o);
	return undef, undef, undef, $error if defined $error;
	return undef, undef, 'Not found.', undef if ! $object;
	my $decrypted = $object->crypt($hashAndKey->key);
	my $record = CDS::Record->fromObject($decrypted) // return undef, undef, 'Not a record.', undef;
	return $record, $object;
}

#line 110 "Condensation/Actors/KeyPair.pm"
# Retrieves an public key object from one of the stores, and parses its public key.
sub getPublicKey {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $store = shift;

#line 112 "Condensation/Actors/KeyPair.pm"
	my ($object, $error) = $store->get($hash, $o);
	return undef, undef, $error if defined $error;
	return undef, 'Not found.', undef if ! $object;
	return CDS::PublicKey->fromObject($object) // return undef, 'Not a public key.', undef;
}

#line 118 "Condensation/Actors/KeyPair.pm"
### Equality ###

sub equals {
	my $this = shift;
	my $that = shift;

#line 121 "Condensation/Actors/KeyPair.pm"
	return 1 if ! defined $this && ! defined $that;
	return if ! defined $this || ! defined $that;
	return $this->publicKey->hash->equals($that->publicKey->hash);
}

#line 17 "Condensation/Actors/OpenEnvelope.pm"
### Open envelopes ###

sub decryptKeyOnEnvelope {
	my $o = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';

#line 20 "Condensation/Actors/OpenEnvelope.pm"
	# Read the AES key
	my $hashBytes24 = substr($o->{publicKey}->hash->bytes, 0, 24);
	my $encryptedAesKey = $envelope->child('encrypted for')->child($hashBytes24)->bytesValue;
	$encryptedAesKey = $envelope->child('encrypted for')->child($o->{publicKey}->hash->bytes)->bytesValue if ! length $encryptedAesKey; # todo: remove this
	return if ! length $encryptedAesKey;

#line 26 "Condensation/Actors/OpenEnvelope.pm"
	# Decrypt the AES key
	my $aesKeyBytes = $o->decrypt($encryptedAesKey);
	return if ! $aesKeyBytes || length $aesKeyBytes != 32;

#line 30 "Condensation/Actors/OpenEnvelope.pm"
	return $aesKeyBytes;
}

# The result of parsing a KEYPAIR token (see Token.pm).
package CDS::KeyPairToken;

sub new {
	my $class = shift;
	my $file = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 4 "Condensation/CLI/KeyPairToken.pm"
	return bless {
		file => $file,
		keyPair => $keyPair,
		};
}

#line 10 "Condensation/CLI/KeyPairToken.pm"
sub file { shift->{file} }
sub keyPair { shift->{keyPair} }

package CDS::LoadActorGroup;

sub load {
	my $class = shift;
	my $builder = shift; die 'wrong type '.ref($builder).' for $builder' if defined $builder && ref $builder ne 'CDS::ActorGroupBuilder';
	my $store = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $delegate = shift;

#line 2 "Condensation/Actors/LoadActorGroup.pm"
	my $o = bless {
		store => $store,
		keyPair => $keyPair,
		knownPublicKeys => $builder->knownPublicKeys,
		};

#line 8 "Condensation/Actors/LoadActorGroup.pm"
	my $members = [];
	for my $member ($builder->members) {
		my $isActive = $member->status eq 'active';
		my $isIdle = $member->status eq 'idle';
		next if ! $isActive && ! $isIdle;

#line 14 "Condensation/Actors/LoadActorGroup.pm"
		my ($publicKey, $storeError) = $o->getPublicKey($member->hash);
		return undef, $storeError if defined $storeError;
		next if ! $publicKey;

#line 18 "Condensation/Actors/LoadActorGroup.pm"
		my $accountStore = $delegate->onLoadActorGroupVerifyStore($member->storeUrl) // next;
		my $actorOnStore = CDS::ActorOnStore->new($publicKey, $accountStore);
		push @$members, CDS::ActorGroup::Member->new($actorOnStore, $member->storeUrl, $member->revision, $isActive);
	}

#line 23 "Condensation/Actors/LoadActorGroup.pm"
	my $entrustedActors = [];
	for my $actor ($builder->entrustedActors) {
		my ($publicKey, $storeError) = $o->getPublicKey($actor->hash);
		return undef, $storeError if defined $storeError;
		next if ! $publicKey;

#line 29 "Condensation/Actors/LoadActorGroup.pm"
		my $accountStore = $delegate->onLoadActorGroupVerifyStore($actor->storeUrl) // next;
		my $actorOnStore = CDS::ActorOnStore->new($publicKey, $accountStore);
		push @$entrustedActors, CDS::ActorGroup::EntrustedActor->new($actorOnStore, $actor->storeUrl);
	}

#line 34 "Condensation/Actors/LoadActorGroup.pm"
	return CDS::ActorGroup->new($members, $builder->entrustedActorsRevision, $entrustedActors);
}

sub getPublicKey {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 38 "Condensation/Actors/LoadActorGroup.pm"
	my $knownPublicKey = $o->{knownPublicKeys}->{$hash->bytes};
	return $knownPublicKey if $knownPublicKey;

#line 41 "Condensation/Actors/LoadActorGroup.pm"
	my ($publicKey, $invalidReason, $storeError) = $o->{keyPair}->getPublicKey($hash, $o->{store});
	return undef, $storeError if defined $storeError;
	return if defined $invalidReason;

#line 45 "Condensation/Actors/LoadActorGroup.pm"
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

#line 5 "Condensation/Stores/LogStore.pm"
	return bless {
		id => "Log Store\n".$store->id,
		store => $store,
		fileHandle => $fileHandle,
		prefix => '',
		};
}

#line 13 "Condensation/Stores/LogStore.pm"
sub id { shift->{id} }
sub store { shift->{store} }
sub fileHandle { shift->{fileHandle} }
sub prefix { shift->{prefix} }

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 19 "Condensation/Stores/LogStore.pm"
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

#line 27 "Condensation/Stores/LogStore.pm"
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

#line 35 "Condensation/Stores/LogStore.pm"
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

#line 43 "Condensation/Stores/LogStore.pm"
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

#line 51 "Condensation/Stores/LogStore.pm"
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

#line 59 "Condensation/Stores/LogStore.pm"
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

#line 67 "Condensation/Stores/LogStore.pm"
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

#line 75 "Condensation/Stores/LogStore.pm"
	my $fh = $o->{fileHandle} // return;
	print $fh $o->{prefix}, &left(8, $cmd), &left(40, $input), ' => ', &left(40, $output), &formatDuration($elapsed), ' us', "\n";
}

sub left {
	my $width = shift;
	my $text = shift;
		# private
#line 80 "Condensation/Stores/LogStore.pm"
	return $text . (' ' x ($width - length $text)) if length $text < $width;
	return $text;
}

sub formatByteLength {
	my $byteLength = shift;
		# private
#line 85 "Condensation/Stores/LogStore.pm"
	my $s = ''.$byteLength;
	$s = ' ' x (9 - length $s) . $s if length $s < 9;
	my $len = length $s;
	return substr($s, 0, $len - 6).' '.substr($s, $len - 6, 3).' '.substr($s, $len - 3, 3);
}

sub formatDuration {
	my $elapsed = shift;
		# private
#line 92 "Condensation/Stores/LogStore.pm"
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

#line 5 "Condensation/Actors/MessageBoxReader.pm"
	return bless {
		pool => $pool,
		actorOnStore => $actorOnStore,
		streamCache => CDS::StreamCache->new($pool, $actorOnStore, $streamTimeout // CDS->MINUTE),
		entries => {},
		};
}

#line 13 "Condensation/Actors/MessageBoxReader.pm"
sub pool { shift->{pool} }
sub actorOnStore { shift->{actorOnStore} }

sub read {
	my $o = shift;
	my $timeout = shift // 0;

#line 17 "Condensation/Actors/MessageBoxReader.pm"
	my $store = $o->{actorOnStore}->store;
	my ($hashes, $listError) = $store->list($o->{actorOnStore}->publicKey->hash, 'messages', $timeout, $o->{pool}->{keyPair});
	return if defined $listError;

#line 21 "Condensation/Actors/MessageBoxReader.pm"
	for my $hash (@$hashes) {
		my $entry = $o->{entries}->{$hash->bytes};
		$o->{entries}->{$hash->bytes} = $entry = CDS::MessageBoxReader::Entry->new($hash) if ! $entry;
		next if $entry->{processed};

#line 26 "Condensation/Actors/MessageBoxReader.pm"
		# Check the sender store, if necessary
		if ($entry->{waitingForStore}) {
			my ($dummy, $checkError) = $entry->{waitingForStore}->get(CDS->emptyBytesHash, $o->{pool}->{keyPair});
			next if defined $checkError;
		}

#line 32 "Condensation/Actors/MessageBoxReader.pm"
		# Get the envelope
		my ($object, $getError) = $o->{actorOnStore}->store->get($entry->{hash}, $o->{pool}->{keyPair});
		return if defined $getError;

#line 36 "Condensation/Actors/MessageBoxReader.pm"
		# Mark the entry as processed
		$entry->{processed} = 1;

#line 39 "Condensation/Actors/MessageBoxReader.pm"
		if (! defined $object) {
			$o->invalid($entry, 'Envelope object not found.');
			next;
		}

#line 44 "Condensation/Actors/MessageBoxReader.pm"
		# Parse the record
		my $envelope = CDS::Record->fromObject($object);
		if (! $envelope) {
			$o->invalid($entry, 'Envelope is not a record.');
			next;
		}

#line 51 "Condensation/Actors/MessageBoxReader.pm"
		my $message =
			$envelope->contains('head') && $envelope->contains('mac') ?
				$o->readStreamMessage($entry, $envelope) :
				$o->readNormalMessage($entry, $envelope);
		next if ! $message;

#line 57 "Condensation/Actors/MessageBoxReader.pm"
		$o->{pool}->{delegate}->onMessageBoxEntry($message);
	}

#line 60 "Condensation/Actors/MessageBoxReader.pm"
	$o->{streamCache}->removeObsolete;
	return 1;
}

sub readNormalMessage {
	my $o = shift;
	my $entry = shift;
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
		# private
#line 65 "Condensation/Actors/MessageBoxReader.pm"
	# Read the embedded content object
	my $encryptedBytes = $envelope->child('content')->bytesValue;
	return $o->invalid($entry, 'Missing content object.') if ! length $encryptedBytes;

#line 69 "Condensation/Actors/MessageBoxReader.pm"
	# Decrypt the key
	my $aesKey = $o->{pool}->{keyPair}->decryptKeyOnEnvelope($envelope);
	return $o->invalid($entry, 'Not encrypted for us.') if ! $aesKey;

#line 73 "Condensation/Actors/MessageBoxReader.pm"
	# Decrypt the content
	my $contentObject = CDS::Object->fromBytes(CDS::C::aesCrypt($encryptedBytes, $aesKey, CDS->zeroCTR));
	return $o->invalid($entry, 'Invalid content object.') if ! $contentObject;

#line 77 "Condensation/Actors/MessageBoxReader.pm"
	my $content = CDS::Record->fromObject($contentObject);
	return $o->invalid($entry, 'Content object is not a record.') if ! $content;

#line 80 "Condensation/Actors/MessageBoxReader.pm"
	# Verify the sender hash
	my $senderHash = $content->child('sender')->hashValue;
	return $o->invalid($entry, 'Missing sender hash.') if ! $senderHash;

#line 84 "Condensation/Actors/MessageBoxReader.pm"
	# Verify the sender store
	my $storeRecord = $content->child('store');
	return $o->invalid($entry, 'Missing sender store.') if ! scalar $storeRecord->children;

#line 88 "Condensation/Actors/MessageBoxReader.pm"
	my $senderStoreUrl = $storeRecord->textValue;
	my $senderStore = $o->{pool}->{delegate}->onMessageBoxVerifyStore($senderStoreUrl, $entry->{hash}, $envelope, $senderHash);
	return $o->invalid($entry, 'Invalid sender store.') if ! $senderStore;

#line 92 "Condensation/Actors/MessageBoxReader.pm"
	# Retrieve the sender's public key
	my ($senderPublicKey, $invalidReason, $publicKeyStoreError) = $o->getPublicKey($senderHash, $senderStore);
	return if defined $publicKeyStoreError;
	return $o->invalid($entry, 'Failed to retrieve the sender\'s public key: '.$invalidReason) if defined $invalidReason;

#line 97 "Condensation/Actors/MessageBoxReader.pm"
	# Verify the signature
	my $signedHash = CDS::Hash->calculateFor($encryptedBytes);
	if (! CDS->verifyEnvelopeSignature($envelope, $senderPublicKey, $signedHash)) {
		# For backwards compatibility with versions before 2020-05-05
		return $o->invalid($entry, 'Invalid signature.') if ! CDS->verifyEnvelopeSignature($envelope, $senderPublicKey, $contentObject->calculateHash);
	}

#line 104 "Condensation/Actors/MessageBoxReader.pm"
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
#line 111 "Condensation/Actors/MessageBoxReader.pm"
	# Get the head
	my $head = $envelope->child('head')->hashValue;
	return $o->invalid($entry, 'Invalid head message hash.') if ! $head;

#line 115 "Condensation/Actors/MessageBoxReader.pm"
	# Get the head envelope
	my $streamHead = $o->{streamCache}->readStreamHead($head);
	return if ! $streamHead;
	return $o->invalid($entry, 'Invalid stream head: '.$streamHead->error) if $streamHead->error;

#line 120 "Condensation/Actors/MessageBoxReader.pm"
	# Read the embedded content object
	my $encryptedBytes = $envelope->child('content')->bytesValue;
	return $o->invalid($entry, 'Missing content object.') if ! length $encryptedBytes;

#line 124 "Condensation/Actors/MessageBoxReader.pm"
	# Get the CTR
	my $ctr = $envelope->child('ctr')->bytesValue;
	return $o->invalid($entry, 'Invalid CTR.') if length $ctr != 16;

#line 128 "Condensation/Actors/MessageBoxReader.pm"
	# Get the MAC
	my $mac = $envelope->child('mac')->bytesValue;
	return $o->invalid($entry, 'Invalid MAC.') if ! $mac;

#line 132 "Condensation/Actors/MessageBoxReader.pm"
	# Verify the MAC
	my $signedHash = CDS::Hash->calculateFor($encryptedBytes);
	my $expectedMac = CDS::C::aesCrypt($signedHash->bytes, $streamHead->aesKey, $ctr);
	return $o->invalid($entry, 'Invalid MAC.') if $mac ne $expectedMac;

#line 137 "Condensation/Actors/MessageBoxReader.pm"
	# Decrypt the content
	my $contentObject = CDS::Object->fromBytes(CDS::C::aesCrypt($encryptedBytes, $streamHead->aesKey, CDS::C::counterPlusInt($ctr, 2)));
	return $o->invalid($entry, 'Invalid content object.') if ! $contentObject;

#line 141 "Condensation/Actors/MessageBoxReader.pm"
	my $content = CDS::Record->fromObject($contentObject);
	return $o->invalid($entry, 'Content object is not a record.') if ! $content;

#line 144 "Condensation/Actors/MessageBoxReader.pm"
	# The envelope is valid
	my $source = CDS::Source->new($o->{pool}->{keyPair}, $o->{actorOnStore}, 'messages', $entry->{hash});
	return CDS::ReceivedMessage->new($o, $entry, $source, $envelope, $streamHead->senderStoreUrl, $streamHead->sender, $content, $streamHead);
}

sub invalid {
	my $o = shift;
	my $entry = shift;
	my $reason = shift;
		# private
#line 150 "Condensation/Actors/MessageBoxReader.pm"
	my $source = CDS::Source->new($o->{pool}->{keyPair}, $o->{actorOnStore}, 'messages', $entry->{hash});
	$o->{pool}->{delegate}->onMessageBoxInvalidEntry($source, $reason);
}

sub getPublicKey {
	my $o = shift;
	my $senderHash = shift; die 'wrong type '.ref($senderHash).' for $senderHash' if defined $senderHash && ref $senderHash ne 'CDS::Hash';
	my $senderStore = shift;
	my $senderStoreUrl = shift;
		# private
#line 155 "Condensation/Actors/MessageBoxReader.pm"
	# Use the account key if sender and recipient are the same
	return $o->{actorOnStore}->publicKey if $senderHash->equals($o->{actorOnStore}->publicKey->hash);

#line 158 "Condensation/Actors/MessageBoxReader.pm"
	# Reuse a cached public key
	my $cachedPublicKey = $o->{pool}->{publicKeyCache}->get($senderHash);
	return $cachedPublicKey if $cachedPublicKey;

#line 162 "Condensation/Actors/MessageBoxReader.pm"
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

#line 2 "Condensation/Actors/MessageBoxReader/Entry.pm"
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

#line 2 "Condensation/Actors/MessageBoxReaderPool.pm"
	return bless {
		keyPair => $keyPair,
		publicKeyCache => $publicKeyCache,
		delegate => $delegate,
		};
}

#line 9 "Condensation/Actors/MessageBoxReaderPool.pm"
sub keyPair { shift->{keyPair} }
sub publicKeyCache { shift->{publicKeyCache} }

#line 12 "Condensation/Actors/MessageBoxReaderPool.pm"
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

#line 4 "Condensation/ActorWithDataTree/MessageChannel.pm"
	my $o = bless {
		actor => $actor,
		label => $label,
		validity => $validity,
		};

#line 10 "Condensation/ActorWithDataTree/MessageChannel.pm"
	$o->{unsaved} = CDS::Unsaved->new($actor->sentList->unsaved);
	$o->{transfers} = [];
	$o->{recipients} = [];
	$o->{entrustedKeys} = [];
	$o->{obsoleteHashes} = {};
	$o->{currentSubmissionId} = 0;
	return $o;
}

#line 19 "Condensation/ActorWithDataTree/MessageChannel.pm"
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

#line 28 "Condensation/ActorWithDataTree/MessageChannel.pm"
	$o->{unsaved}->state->addObject($hash, $object);
}

sub addTransfer {
	my $o = shift;
	my $hashes = shift;
	my $sourceStore = shift;
	my $context = shift;

#line 32 "Condensation/ActorWithDataTree/MessageChannel.pm"
	return if ! scalar @$hashes;
	push @{$o->{transfers}}, {hashes => $hashes, sourceStore => $sourceStore, context => $context};
}

sub setRecipientActorGroup {
	my $o = shift;
	my $actorGroup = shift; die 'wrong type '.ref($actorGroup).' for $actorGroup' if defined $actorGroup && ref $actorGroup ne 'CDS::ActorGroup';

#line 37 "Condensation/ActorWithDataTree/MessageChannel.pm"
	$o->{recipients} = [map { $_->actorOnStore } $actorGroup->members];
	$o->{entrustedKeys} = [map { $_->actorOnStore->publicKey } $actorGroup->entrustedActors];
}

sub setRecipients {
	my $o = shift;
	my $recipients = shift;
	my $entrustedKeys = shift;

#line 42 "Condensation/ActorWithDataTree/MessageChannel.pm"
	$o->{recipients} = $recipients;
	$o->{entrustedKeys} = $entrustedKeys;
}

sub submit {
	my $o = shift;
	my $message = shift;
	my $done = shift;

#line 47 "Condensation/ActorWithDataTree/MessageChannel.pm"
	# Check if the sent list has been loaded
	return if ! $o->{actor}->sentListReady;

#line 50 "Condensation/ActorWithDataTree/MessageChannel.pm"
	# Transfer
	my $transfers = $o->{transfers};
	$o->{transfers} = [];
	for my $transfer (@$transfers) {
		my ($missingObject, $store, $error) = $o->{actor}->keyPair->transfer($transfer->{hashes}, $transfer->{sourceStore}, $o->{actor}->messagingPrivateRoot->unsaved);
		return if defined $error;

#line 57 "Condensation/ActorWithDataTree/MessageChannel.pm"
		if ($missingObject) {
			$missingObject->{context} = $transfer->{context};
			return undef, $missingObject;
		}
	}

#line 63 "Condensation/ActorWithDataTree/MessageChannel.pm"
	# Send the message
	return CDS::MessageChannel::Submission->new($o, $message, $done);
}

sub clear {
	my $o = shift;

#line 68 "Condensation/ActorWithDataTree/MessageChannel.pm"
	$o->item->clear(CDS->now + $o->{validity});
}

package CDS::MessageChannel::Submission;

sub new {
	my $class = shift;
	my $channel = shift;
	my $message = shift;
	my $done = shift;

#line 2 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
	$channel->{currentSubmissionId} += 1;

#line 4 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
	my $o = bless {
		channel => $channel,
		message => $message,
		done => $done,
		submissionId => $channel->{currentSubmissionId},
		recipients => [$channel->recipients],
		entrustedKeys => [$channel->entrustedKeys],
		expires => CDS->now + $channel->validity,
		};

#line 14 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
	# Add the current envelope hash to the obsolete hashes
	my $item = $channel->item;
	$channel->{obsoleteHashes}->{$item->envelopeHash->bytes} = $item->envelopeHash if $item->envelopeHash;
	$o->{obsoleteHashesSnapshot} = [values %{$channel->{obsoleteHashes}}];

#line 19 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
	# Create an envelope
	my $publicKeys = [];
	push @$publicKeys, $channel->{actor}->keyPair->publicKey;
	push @$publicKeys, map { $_->publicKey } @{$o->{recipients}};
	push @$publicKeys, @{$o->{entrustedKeys}};
	$o->{envelopeObject} = $channel->{actor}->keyPair->createMessageEnvelope($channel->{actor}->messagingStoreUrl, $message, $publicKeys, $o->{expires})->toObject;
	$o->{envelopeHash} = $o->{envelopeObject}->calculateHash;

#line 27 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
	# Set the new item and wait until it gets saved
	$channel->{unsaved}->startSaving;
	$channel->{unsaved}->savingState->addDataSavedHandler($o);
	$channel->{actor}->sentList->unsaved->state->merge($channel->{unsaved}->savingState);
	$item->set($o->{expires}, $o->{envelopeHash}, $message);
	$channel->{unsaved}->savingDone;

#line 34 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
	return $o;
}

#line 37 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
sub channel { shift->{channel} }
sub message { shift->{message} }
sub recipients {
	my $o = shift;
	 @{$o->{recipients}} }
sub entrustedKeys {
	my $o = shift;
	 @{$o->{entrustedKeys}} }
#line 41 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
sub expires { shift->{expires} }
sub envelopeObject { shift->{envelopeObject} }
sub envelopeHash { shift->{envelopeHash} }

sub onDataSaved {
	my $o = shift;

#line 46 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
	# If we are not the head any more, give up
	return $o->{done}->onMessageChannelSubmissionCancelled if $o->{submissionId} != $o->{channel}->{currentSubmissionId};
	$o->{channel}->{obsoleteHashes}->{$o->{envelopeHash}->bytes} = $o->{envelopeHash};

#line 50 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
	# Process all recipients
	my $succeeded = 0;
	my $failed = 0;
	for my $recipient (@{$o->{recipients}}) {
		my $modifications = CDS::StoreModifications->new;

#line 56 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
		# Prepare the list of removals
		my $removals = [];
		for my $hash (@{$o->{obsoleteHashesSnapshot}}) {
			$modifications->remove($recipient->publicKey->hash, 'messages', $hash);
		}

#line 62 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
		# Add the message entry
		$modifications->add($recipient->publicKey->hash, 'messages', $o->{envelopeHash}, $o->{envelopeObject});
		my $error = $recipient->store->modify($modifications, $o->{channel}->{actor}->keyPair);

#line 66 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
		if (defined $error) {
			$failed += 1;
			$o->{done}->onMessageChannelSubmissionRecipientFailed($recipient, $error);
		} else {
			$succeeded += 1;
			$o->{done}->onMessageChannelSubmissionRecipientDone($recipient);
		}
	}

#line 75 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
	if ($failed == 0 || scalar keys %{$o->{obsoleteHashes}} > 64) {
		for my $hash (@{$o->{obsoleteHashesSnapshot}}) {
			delete $o->{channel}->{obsoleteHashes}->{$hash->bytes};
		}
	}

#line 81 "Condensation/ActorWithDataTree/MessageChannel/Submission.pm"
	$o->{done}->onMessageChannelSubmissionDone($succeeded, $failed);
}

package CDS::MissingObject;

sub new {
	my $class = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $store = shift;

#line 2 "Condensation/Stores/MissingObject.pm"
	return bless {hash => $hash, store => $store, path => [], context => undef};
}

#line 5 "Condensation/Stores/MissingObject.pm"
sub hash { shift->{hash} }
sub store { shift->{store} }
sub path {
	my $o = shift;
	 @{$o->{path}} }
#line 8 "Condensation/Stores/MissingObject.pm"
sub context { shift->{context} }

package CDS::NewAnnounce;

sub new {
	my $class = shift;
	my $messagingStore = shift;

#line 2 "Condensation/Messaging/NewAnnounce.pm"
	my $o = bless {
		messagingStore => $messagingStore,
		unsaved => CDS::Unsaved->new($messagingStore->store),
		transfers => [],
		card => CDS::Record->new,
		};

#line 9 "Condensation/Messaging/NewAnnounce.pm"
	my $publicKey = $messagingStore->actor->keyPair->publicKey;
	$o->{card}->add('public key')->addHash($publicKey->hash);
	$o->addObject($publicKey->hash, $publicKey->object);
	return $o;
}

#line 15 "Condensation/Messaging/NewAnnounce.pm"
sub messagingStore { shift->{messagingStore} }
sub card { shift->{card} }

sub addObject {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

#line 19 "Condensation/Messaging/NewAnnounce.pm"
	$o->{unsaved}->state->addObject($hash, $object);
}

sub addTransfer {
	my $o = shift;
	my $hashes = shift;
	my $sourceStore = shift;
	my $context = shift;

#line 23 "Condensation/Messaging/NewAnnounce.pm"
	return if ! scalar @$hashes;
	push @{$o->{transfers}}, {hashes => $hashes, sourceStore => $sourceStore, context => $context};
}

sub addActorGroup {
	my $o = shift;
	my $actorGroupBuilder = shift;

#line 28 "Condensation/Messaging/NewAnnounce.pm"
	$actorGroupBuilder->addToRecord($o->{card}, 0);
}

sub submit {
	my $o = shift;

#line 32 "Condensation/Messaging/NewAnnounce.pm"
	my $keyPair = $o->{messagingStore}->actor->keyPair;

#line 34 "Condensation/Messaging/NewAnnounce.pm"
	# Create the public card
	my $cardObject = $o->{card}->toObject;
	my $cardHash = $cardObject->calculateHash;
	$o->addObject($cardHash, $cardObject);

#line 39 "Condensation/Messaging/NewAnnounce.pm"
	# Prepare the public envelope
	my $me = $keyPair->publicKey->hash;
	my $envelopeObject = $keyPair->createPublicEnvelope($cardHash)->toObject;
	my $envelopeHash = $envelopeObject->calculateHash;
	$o->addTransfer([$cardHash], $o->{unsaved}, 'Announcing');

#line 45 "Condensation/Messaging/NewAnnounce.pm"
	# Transfer all trees
	for my $transfer (@{$o->{transfers}}) {
		my ($missingObject, $store, $error) = $keyPair->transfer($transfer->{hashes}, $transfer->{sourceStore}, $o->{messagingStore}->store);
		return if defined $error;

#line 50 "Condensation/Messaging/NewAnnounce.pm"
		if ($missingObject) {
			$missingObject->{context} = $transfer->{context};
			return undef, $missingObject;
		}
	}

#line 56 "Condensation/Messaging/NewAnnounce.pm"
	# Prepare a modification
	my $modifications = CDS::StoreModifications->new;
	$modifications->add($me, 'public', $envelopeHash, $envelopeObject);

#line 60 "Condensation/Messaging/NewAnnounce.pm"
	# List the current cards to remove them
	# Ignore errors, in the worst case, we are going to have multiple entries in the public box
	my ($hashes, $error) = $o->{messagingStore}->store->list($me, 'public', 0, $keyPair);
	if ($hashes) {
		for my $hash (@$hashes) {
			$modifications->remove($me, 'public', $hash);
		}
	}

#line 69 "Condensation/Messaging/NewAnnounce.pm"
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

#line 2 "Condensation/Messaging/NewMessagingStore.pm"
	return bless {
		actor => $actor,
		store => $store,
		};
}

#line 8 "Condensation/Messaging/NewMessagingStore.pm"
sub actor { shift->{actor} }
sub store { shift->{store} }

# A Condensation object.
# A valid object starts with a 4-byte length (big-endian), followed by 32 * length bytes of hashes, followed by 0 or more bytes of data.
package CDS::Object;

#line 4 "Condensation/Serialization/Object.pm"
sub emptyHeader { "\0\0\0\0" }

sub create {
	my $class = shift;
	my $header = shift;
	my $data = shift;

#line 7 "Condensation/Serialization/Object.pm"
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

#line 19 "Condensation/Serialization/Object.pm"
	return if length $bytes < 4;

#line 21 "Condensation/Serialization/Object.pm"
	my $hashesCount = unpack 'L>', substr($bytes, 0, 4);
	my $dataStart = $hashesCount * 32 + 4;
	return if $dataStart > length $bytes;

#line 25 "Condensation/Serialization/Object.pm"
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

#line 34 "Condensation/Serialization/Object.pm"
	return $class->fromBytes(CDS->readBytesFromFile($file));
}

#line 37 "Condensation/Serialization/Object.pm"
sub bytes { shift->{bytes} }
sub header { shift->{header} }
sub data { shift->{data} }
sub hashesCount { shift->{hashesCount} }
sub byteLength {
	my $o = shift;
	 length($o->{header}) + length($o->{data}) }

sub calculateHash {
	my $o = shift;

#line 44 "Condensation/Serialization/Object.pm"
	return CDS::Hash->calculateFor($o->{bytes});
}

sub hashes {
	my $o = shift;

#line 48 "Condensation/Serialization/Object.pm"
	return map { CDS::Hash->fromBytes(substr($o->{header}, $_ * 32 + 4, 32)) } 0 .. $o->{hashesCount} - 1;
}

sub hashAtIndex {
	my $o = shift;
	my $index = shift // return;

#line 52 "Condensation/Serialization/Object.pm"
	return if $index < 0 || $index >= $o->{hashesCount};
	return CDS::Hash->fromBytes(substr($o->{header}, $index * 32 + 4, 32));
}

sub crypt {
	my $o = shift;
	my $key = shift;

#line 57 "Condensation/Serialization/Object.pm"
	return CDS::Object->create($o->{header}, CDS::C::aesCrypt($o->{data}, $key, CDS->zeroCTR));
}

sub writeToFile {
	my $o = shift;
	my $file = shift;

#line 61 "Condensation/Serialization/Object.pm"
	return CDS->writeBytesToFile($file, $o->{bytes});
}

# A store using a cache store to deliver frequently accessed objects faster, and a backend store.
package CDS::ObjectCache;

use parent -norequire, 'CDS::Store';

sub new {
	my $class = shift;
	my $backend = shift;
	my $cache = shift;

#line 5 "Condensation/Stores/ObjectCache.pm"
	return bless {
		id => "Object Cache\n".$backend->id."\n".$cache->id,
		backend => $backend,
		cache => $cache,
		};
}

#line 12 "Condensation/Stores/ObjectCache.pm"
sub id { shift->{id} }
sub backend { shift->{backend} }
sub cache { shift->{cache} }

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 17 "Condensation/Stores/ObjectCache.pm"
	my $objectFromCache = $o->{cache}->get($hash);
	return $objectFromCache if $objectFromCache;

#line 20 "Condensation/Stores/ObjectCache.pm"
	my ($object, $error) = $o->{backend}->get($hash, $keyPair);
	return undef, $error if ! defined $object;
	$o->{cache}->put($hash, $object, undef);
	return $object;
}

sub put {
	my $o = shift;

#line 27 "Condensation/Stores/ObjectCache.pm"
	# The important thing is that the backend succeeds. The cache is a nice-to-have.
	$o->{cache}->put(@_);
	return $o->{backend}->put(@_);
}

sub book {
	my $o = shift;

#line 33 "Condensation/Stores/ObjectCache.pm"
	# The important thing is that the backend succeeds. The cache is a nice-to-have.
	$o->{cache}->book(@_);
	return $o->{backend}->book(@_);
}

sub list {
	my $o = shift;

#line 39 "Condensation/Stores/ObjectCache.pm"
	# Just pass this through to the backend.
	return $o->{backend}->list(@_);
}

sub add {
	my $o = shift;

#line 44 "Condensation/Stores/ObjectCache.pm"
	# Just pass this through to the backend.
	return $o->{backend}->add(@_);
}

sub remove {
	my $o = shift;

#line 49 "Condensation/Stores/ObjectCache.pm"
	# Just pass this through to the backend.
	return $o->{backend}->remove(@_);
}

sub modify {
	my $o = shift;

#line 54 "Condensation/Stores/ObjectCache.pm"
	# Just pass this through to the backend.
	return $o->{backend}->modify(@_);
}

# The result of parsing an OBJECTFILE token (see Token.pm).
package CDS::ObjectFileToken;

sub new {
	my $class = shift;
	my $file = shift;
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

#line 4 "Condensation/CLI/ObjectFileToken.pm"
	return bless {
		file => $file,
		object => $object,
		};
}

#line 10 "Condensation/CLI/ObjectFileToken.pm"
sub file { shift->{file} }
sub object { shift->{object} }

# The result of parsing an OBJECT token.
package CDS::ObjectToken;

sub new {
	my $class = shift;
	my $cliStore = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 4 "Condensation/CLI/ObjectToken.pm"
	return bless {
		cliStore => $cliStore,
		hash => $hash,
		};
}

#line 10 "Condensation/CLI/ObjectToken.pm"
sub cliStore { shift->{cliStore} }
sub hash { shift->{hash} }
sub url {
	my $o = shift;
	 $o->{cliStore}->url.'/objects/'.$o->{hash}->hex }

package CDS::Parser;

sub new {
	my $class = shift;
	my $actor = shift;
	my $command = shift;

#line 8 "Condensation/CLI/Parser.pm"
	my $start = CDS::Parser::Node->new(0);
	return bless {
		actor => $actor,
		ui => $actor->ui,
		start => $start,
		states => [CDS::Parser::State->new($start)],
		command => $command,
		};
}

#line 18 "Condensation/CLI/Parser.pm"
sub actor { shift->{actor} }
sub start { shift->{start} }

sub execute {
	my $o = shift;

#line 22 "Condensation/CLI/Parser.pm"
	my $processed = [$o->{command}];
	for my $arg (@_) {
		return $o->howToContinue($processed) if $arg eq '?';
		return $o->explain if $arg eq '??';
		my $token = CDS::Parser::Token->new($o->{actor}, $arg);
		$o->advance($token);
		return $o->invalid($processed, $token) if ! scalar @{$o->{states}};
		push @$processed, $arg;
	}

#line 32 "Condensation/CLI/Parser.pm"
	my @results = grep { $_->runHandler } @{$o->{states}};
	return $o->howToContinue($processed) if ! scalar @results;

#line 35 "Condensation/CLI/Parser.pm"
	my $maxWeight = 0;
	for my $result (@results) {
		$maxWeight = $result->cumulativeWeight if $maxWeight < $result->cumulativeWeight;
	}

#line 40 "Condensation/CLI/Parser.pm"
	@results = grep { $_->cumulativeWeight == $maxWeight } @results;
	return $o->ambiguous if scalar @results > 1;

#line 43 "Condensation/CLI/Parser.pm"
	my $result = shift @results;
	my $handler = $result->runHandler;
	my $instance = &{$handler->{constructor}}(undef, $o->{actor});
	&{$handler->{function}}($instance, $result);
}

sub advance {
	my $o = shift;
	my $token = shift;

#line 50 "Condensation/CLI/Parser.pm"
	$o->{previousStates} = $o->{states};
	$o->{states} = [];
	for my $state (@{$o->{previousStates}}) {
		push @{$o->{states}}, $state->advance($token);
	}
}

sub showCompletions {
	my $o = shift;
	my $cmd = shift;

#line 58 "Condensation/CLI/Parser.pm"
	# Parse the command line
	my $state = '';
	my $arg = '';
	my @args;
	for my $c (split //, $cmd) {
		if ($state eq '') {
			if ($c eq ' ') {
				push @args, $arg if length $arg;
				$arg = '';
			} elsif ($c eq '\'') {
				push @args, $arg if length $arg;
				$arg = '';
				$state = '\'';
			} elsif ($c eq '"') {
				push @args, $arg if length $arg;
				$arg = '';
				$state = '"';
			} elsif ($c eq '\\') {
				$state = '\\';
			} else {
				$arg .= $c;
			}
		} elsif ($state eq '\\') {
			$arg .= $c;
			$state = '';
		} elsif ($state eq '\'') {
			if ($c eq '\'') {
				push @args, $arg if length $arg;
				$arg = '';
				$state = '';
			} else {
				$arg .= $c;
			}
		} elsif ($state eq '"') {
			if ($c eq '"') {
				push @args, $arg if length $arg;
				$arg = '';
				$state = '';
			} elsif ($c eq '\\') {
				$state = '"\\';
			} else {
				$arg .= $c;
			}
		} elsif ($state eq '\\"') {
			$arg .= $c;
			$state = '"';
		}
	}

#line 107 "Condensation/CLI/Parser.pm"
	# Use the last token to complete
	my $lastToken = CDS::Parser::Token->new($o->{actor}, $arg);

#line 110 "Condensation/CLI/Parser.pm"
	# Look for possible states
	shift @args;
	for my $arg (@args) {
		return if $arg eq '?';
		$o->advance(CDS::Parser::Token->new($o->{actor}, $arg));
	}

#line 117 "Condensation/CLI/Parser.pm"
	# Complete the last token
	my %possibilities;
	for my $state (@{$o->{states}}) {
		for my $possibility ($state->complete($lastToken)) {
			$possibilities{$possibility} = 1;
		}
	}

#line 125 "Condensation/CLI/Parser.pm"
	# Print all possibilities
	for my $possibility (keys %possibilities) {
		print $possibility, "\n";
	}
}

sub ambiguous {
	my $o = shift;

#line 132 "Condensation/CLI/Parser.pm"
	$o->{ui}->space;
	$o->{ui}->pRed('Your query is ambiguous. This is an error in the command grammar.');
	$o->explain;
}

sub explain {
	my $o = shift;

#line 138 "Condensation/CLI/Parser.pm"
	for my $interpretation (sort { $b->cumulativeWeight <=> $a->cumulativeWeight || $b->isExecutable <=> $a->isExecutable } @{$o->{states}}) {
		$o->{ui}->space;
		$o->{ui}->title('Interpretation with weight ', $interpretation->cumulativeWeight, $interpretation->isExecutable ? $o->{ui}->green(' (executable)') : $o->{ui}->orange(' (incomplete)'));
		$o->showTuples($interpretation->path);
	}

#line 144 "Condensation/CLI/Parser.pm"
	$o->{ui}->space;
}

sub showTuples {
	my $o = shift;

#line 148 "Condensation/CLI/Parser.pm"
	for my $state (@_) {
		my $label = $state->label;
		my $value = $state->value;

#line 152 "Condensation/CLI/Parser.pm"
		my $valueRef = ref $value;
		my $valueText =
			$valueRef eq '' ? $value // '' :
			$valueRef eq 'CDS::Hash' ? $value->hex :
			$valueRef eq 'CDS::ErrorHandlingStore' ? $value->url :
			$valueRef eq 'CDS::AccountToken' ? $value->actorHash->hex . ' on ' . $value->cliStore->url :
				$valueRef;
		$o->{ui}->line($o->{ui}->left(12, $label), $state->collectHandler ? $valueText : $o->{ui}->gray($valueText));
	}
}

sub cmd {
	my $o = shift;
	my $processed = shift;

#line 164 "Condensation/CLI/Parser.pm"
	my $cmd = join(' ', map { $_ =~ s/(\\|'|")/\\$1/g ; $_ } @$processed);
	$cmd = '…'.substr($cmd, length($cmd) - 20, 20) if length $cmd > 30;
	return $cmd;
}

sub howToContinue {
	my $o = shift;
	my $processed = shift;

#line 170 "Condensation/CLI/Parser.pm"
	my $cmd = $o->cmd($processed);
	#$o->displayWarnings($o->{states});
	$o->{ui}->space;
	for my $possibility (CDS::Parser::Continuations->collect($o->{states})) {
		$o->{ui}->line($o->{ui}->gray($cmd), $possibility);
	}
	$o->{ui}->space;
}

sub invalid {
	my $o = shift;
	my $processed = shift;
	my $invalid = shift;

#line 180 "Condensation/CLI/Parser.pm"
	my $cmd = $o->cmd($processed);
	$o->displayWarnings($o->{previousStates});
	$o->{ui}->space;

#line 184 "Condensation/CLI/Parser.pm"
	$o->{ui}->line($o->{ui}->gray($cmd), ' ', $o->{ui}->red($invalid->{text}));
	if (scalar @{$invalid->{warnings}}) {
		for my $warning (@{$invalid->{warnings}}) {
			$o->{ui}->warning($warning);
		}
	}

#line 191 "Condensation/CLI/Parser.pm"
	$o->{ui}->space;
	$o->{ui}->title('Possible continuations');
	for my $possibility (CDS::Parser::Continuations->collect($o->{previousStates})) {
		$o->{ui}->line($o->{ui}->gray($cmd), $possibility);
	}
	$o->{ui}->space;
}

sub displayWarnings {
	my $o = shift;
	my $states = shift;

#line 200 "Condensation/CLI/Parser.pm"
	for my $state (@$states) {
		my $current = $state;
		while ($current) {
			for my $warning (@{$current->{warnings}}) {
				$o->{ui}->warning($warning);
			}
			$current = $current->{previous};
		}
	}
}

# An arrow points from one node to another. The arrow is taken in State::advance if the next argument matches to the label.
package CDS::Parser::Arrow;

sub new {
	my $class = shift;
	my $node = shift;
	my $official = shift;
	my $weight = shift;
	my $label = shift;
	my $handler = shift;

#line 4 "Condensation/CLI/Parser/Arrow.pm"
	return bless {
		node => $node,				# target node
		official => $official,		# whether to show this arrow with '?'
		weight => $weight,			# weight
		label => $label,			# label
		handler => $handler,		# handler to invoke if we take this arrow
		};
}

package CDS::Parser::Continuations;

sub collect {
	my $class = shift;
	my $states = shift;

#line 2 "Condensation/CLI/Parser/Continuations.pm"
	my $o = bless {possibilities => {}};

#line 4 "Condensation/CLI/Parser/Continuations.pm"
	my $visitedNodes = {};
	for my $state (@$states) {
		$o->visit($visitedNodes, $state->node, '');
	}

#line 9 "Condensation/CLI/Parser/Continuations.pm"
	for my $possibility (keys %{$o->{possibilities}}) {
		delete $o->{possibilities}->{$possibility} if exists $o->{possibilities}->{$possibility.' …'};
	}

#line 13 "Condensation/CLI/Parser/Continuations.pm"
	return sort keys %{$o->{possibilities}};
}

sub visit {
	my $o = shift;
	my $visitedNodes = shift;
	my $node = shift;
	my $text = shift;

#line 17 "Condensation/CLI/Parser/Continuations.pm"
	$visitedNodes->{$node} = 1;

#line 19 "Condensation/CLI/Parser/Continuations.pm"
	my $arrows = [];
	$node->collectArrows($arrows);

#line 22 "Condensation/CLI/Parser/Continuations.pm"
	for my $arrow (@$arrows) {
		next if ! $arrow->{official};

#line 25 "Condensation/CLI/Parser/Continuations.pm"
		my $text = $text.' '.$arrow->{label};
		$o->{possibilities}->{$text} = 1 if $arrow->{node}->hasHandler;
		if ($arrow->{node}->endProposals || exists $visitedNodes->{$arrow->{node}}) {
			$o->{possibilities}->{$text . ($o->canContinue($arrow->{node}) ? ' …' : '')} = 1;
			next;
		}

#line 32 "Condensation/CLI/Parser/Continuations.pm"
		$o->visit($visitedNodes, $arrow->{node}, $text);
	}

#line 35 "Condensation/CLI/Parser/Continuations.pm"
	delete $visitedNodes->{$node};
}

sub canContinue {
	my $o = shift;
	my $node = shift;

#line 39 "Condensation/CLI/Parser/Continuations.pm"
	my $arrows = [];
	$node->collectArrows($arrows);

#line 42 "Condensation/CLI/Parser/Continuations.pm"
	for my $arrow (@$arrows) {
		next if ! $arrow->{official};
		return 1;
	}

#line 47 "Condensation/CLI/Parser/Continuations.pm"
	return;
}

# Nodes and arrows define the graph on which the parse state can move.
package CDS::Parser::Node;

sub new {
	my $class = shift;
	my $endProposals = shift;
	my $handler = shift;

#line 4 "Condensation/CLI/Parser/Node.pm"
	return bless {
		arrows => [],					# outgoing arrows
		defaults => [],					# default nodes, at which the current state could be as well
		endProposals => $endProposals,	# if set, the proposal search algorithm stops at this node
		handler => $handler,			# handler to be executed if parsing ends here
		};
}

#line 12 "Condensation/CLI/Parser/Node.pm"
sub endProposals { shift->{endProposals} }

#line 14 "Condensation/CLI/Parser/Node.pm"
# Adds an arrow.
sub addArrow {
	my $o = shift;
	my $to = shift;
	my $official = shift;
	my $weight = shift;
	my $label = shift;
	my $handler = shift;

#line 16 "Condensation/CLI/Parser/Node.pm"
	push @{$o->{arrows}}, CDS::Parser::Arrow->new($to, $official, $weight, $label, $handler);
}

#line 19 "Condensation/CLI/Parser/Node.pm"
# Adds a default node.
sub addDefault {
	my $o = shift;
	my $node = shift;

#line 21 "Condensation/CLI/Parser/Node.pm"
	push @{$o->{defaults}}, $node;
}

sub collectArrows {
	my $o = shift;
	my $arrows = shift;

#line 25 "Condensation/CLI/Parser/Node.pm"
	push @$arrows, @{$o->{arrows}};
	for my $default (@{$o->{defaults}}) { $default->collectArrows($arrows); }
}

sub hasHandler {
	my $o = shift;

#line 30 "Condensation/CLI/Parser/Node.pm"
	return 1 if $o->{handler};
	for my $default (@{$o->{defaults}}) { return 1 if $default->hasHandler; }
	return;
}

sub getHandler {
	my $o = shift;

#line 36 "Condensation/CLI/Parser/Node.pm"
	return $o->{handler} if $o->{handler};
	for my $default (@{$o->{defaults}}) {
		my $handler = $default->getHandler // next;
		return $handler;
	}
	return;
}

# A parser state denotes a possible current state (after having parsed a certain number of arguments).
# A parser keeps track of multiple states. When advancing, a state may disappear (if no possibility exists), or fan out (if multiple possibilities exist).
# A state is immutable.
package CDS::Parser::State;

sub new {
	my $class = shift;
	my $node = shift;
	my $previous = shift;
	my $arrow = shift;
	my $value = shift;
	my $warnings = shift;

#line 6 "Condensation/CLI/Parser/State.pm"
	return bless {
		node => $node,			# current node
		previous => $previous,	# previous state
		arrow => $arrow,		# the arrow we took to get here
		value => $value,		# the value we collected with the last arrow
		warnings => $warnings,	# the warnings we collected with the last arrow
		cumulativeWeight => ($previous ? $previous->cumulativeWeight : 0) + ($arrow ? $arrow->{weight} : 0),	# the weight we collected until here
		};
}

#line 16 "Condensation/CLI/Parser/State.pm"
sub node { shift->{node} }
sub runHandler {
	my $o = shift;
	 $o->{node}->getHandler }
sub isExecutable {
	my $o = shift;
	 $o->{node}->getHandler ? 1 : 0 }
sub collectHandler {
	my $o = shift;
	 $o->{arrow} ? $o->{arrow}->{handler} : undef }
sub label {
	my $o = shift;
	 $o->{arrow} ? $o->{arrow}->{label} : 'cds' }
#line 21 "Condensation/CLI/Parser/State.pm"
sub value { shift->{value} }
sub arrow { shift->{arrow} }
sub cumulativeWeight { shift->{cumulativeWeight} }

sub advance {
	my $o = shift;
	my $token = shift;

#line 26 "Condensation/CLI/Parser/State.pm"
	my $arrows = [];
	$o->{node}->collectArrows($arrows);

#line 29 "Condensation/CLI/Parser/State.pm"
	# Let the token know what possibilities we have
	for my $arrow (@$arrows) {
		$token->prepare($arrow->{label});
	}

#line 34 "Condensation/CLI/Parser/State.pm"
	# Ask the token to interpret the text
	my @states;
	for my $arrow (@$arrows) {
		my $value = $token->as($arrow->{label}) // next;
		push @states, CDS::Parser::State->new($arrow->{node}, $o, $arrow, $value, $token->{warnings});
	}

#line 41 "Condensation/CLI/Parser/State.pm"
	return @states;
}

sub complete {
	my $o = shift;
	my $token = shift;

#line 45 "Condensation/CLI/Parser/State.pm"
	my $arrows = [];
	$o->{node}->collectArrows($arrows);

#line 48 "Condensation/CLI/Parser/State.pm"
	# Let the token know what possibilities we have
	for my $arrow (@$arrows) {
		next if ! $arrow->{official};
		$token->prepare($arrow->{label});
	}

#line 54 "Condensation/CLI/Parser/State.pm"
	# Ask the token to interpret the text
	for my $arrow (@$arrows) {
		next if ! $arrow->{official};
		$token->complete($arrow->{label});
	}

#line 60 "Condensation/CLI/Parser/State.pm"
	return @{$token->{possibilities}};
}

sub arrows {
	my $o = shift;

#line 64 "Condensation/CLI/Parser/State.pm"
	my $arrows = [];
	$o->{node}->collectArrows($arrows);
	return @$arrows;
}

sub path {
	my $o = shift;

#line 70 "Condensation/CLI/Parser/State.pm"
	my @path;
	my $state = $o;
	while ($state) {
		unshift @path, $state;
		$state = $state->{previous};
	}
	return @path;
}

sub collect {
	my $o = shift;
	my $data = shift;

#line 80 "Condensation/CLI/Parser/State.pm"
	for my $state ($o->path) {
		my $collectHandler = $state->collectHandler // next;
		&$collectHandler($data, $state->label, $state->value);
	}
}

package CDS::Parser::Token;

sub new {
	my $class = shift;
	my $actor = shift;
	my $text = shift;

#line 5 "Condensation/CLI/Parser/Token.pm"
	return bless {
		actor => $actor,
		text => $text,
		keywords => {},
		cache => {},
		warnings => [],
		possibilities => [],
		};
}

sub prepare {
	my $o = shift;
	my $expect = shift;

#line 16 "Condensation/CLI/Parser/Token.pm"
	$o->{keywords}->{$expect} = 1 if $expect =~ /^[a-z0-9]*$/;
}

sub as {
	my $o = shift;
	my $expect = shift;
	 exists $o->{cache}->{$expect} ? $o->{cache}->{$expect} : $o->{cache}->{$expect} = $o->produce($expect) }

sub produce {
	my $o = shift;
	my $expect = shift;

#line 22 "Condensation/CLI/Parser/Token.pm"
	return $o->account if $expect eq 'ACCOUNT';
	return $o->hash if $expect eq 'ACTOR';
	return $o->actorGroup if $expect eq 'ACTORGROUP';
	return $o->aesKey if $expect eq 'AESKEY';
	return $o->box if $expect eq 'BOX';
	return $o->boxLabel if $expect eq 'BOXLABEL';
	return $o->file if $expect eq 'FILE';
	return $o->filename if $expect eq 'FILENAME';
	return $o->folder if $expect eq 'FOLDER';
	return $o->foldername if $expect eq 'FOLDERNAME';
	return $o->group if $expect eq 'GROUP';
	return $o->hash if $expect eq 'HASH';
	return $o->keyPair if $expect eq 'KEYPAIR';
	return $o->label if $expect eq 'LABEL';
	return $o->object if $expect eq 'OBJECT';
	return $o->objectFile if $expect eq 'OBJECTFILE';
	return $o->port if $expect eq 'PORT';
	return $o->store if $expect eq 'STORE';
	return $o->text if $expect eq 'TEXT';
	return $o->user if $expect eq 'USER';
	return $o->{text} eq $expect ? '' : undef;
}

sub complete {
	my $o = shift;
	my $expect = shift;

#line 46 "Condensation/CLI/Parser/Token.pm"
	return $o->completeAccount if $expect eq 'ACCOUNT';
	return $o->completeHash if $expect eq 'ACTOR';
	return $o->completeActorGroup if $expect eq 'ACTORGROUP';
	return if $expect eq 'AESKEY';
	return $o->completeBox if $expect eq 'BOX';
	return $o->completeBoxLabel if $expect eq 'BOXLABEL';
	return $o->completeFile if $expect eq 'FILE';
	return $o->completeFile if $expect eq 'FILENAME';
	return $o->completeFolder if $expect eq 'FOLDER';
	return $o->completeFolder if $expect eq 'FOLDERNAME';
	return $o->completeGroup if $expect eq 'GROUP';
	return $o->completeHash if $expect eq 'HASH';
	return $o->completeKeyPair if $expect eq 'KEYPAIR';
	return $o->completeLabel if $expect eq 'LABEL';
	return $o->completeObject if $expect eq 'OBJECT';
	return $o->completeObjectFile if $expect eq 'OBJECTFILE';
	return $o->completeStoreUrl if $expect eq 'STORE';
	return $o->completeUser if $expect eq 'USER';
	return if $expect eq 'TEXT';
	$o->addPossibility($expect);
}

sub addPossibility {
	my $o = shift;
	my $possibility = shift;

#line 69 "Condensation/CLI/Parser/Token.pm"
	push @{$o->{possibilities}}, $possibility.' ' if substr($possibility, 0, length $o->{text}) eq $o->{text};
}

sub addPartialPossibility {
	my $o = shift;
	my $possibility = shift;

#line 73 "Condensation/CLI/Parser/Token.pm"
	push @{$o->{possibilities}}, $possibility if substr($possibility, 0, length $o->{text}) eq $o->{text};
}

sub isKeyword {
	my $o = shift;
	 exists $o->{keywords}->{$o->{text}} }

sub account {
	my $o = shift;

#line 79 "Condensation/CLI/Parser/Token.pm"
	# From a remembered account
	my $record = $o->{actor}->remembered($o->{text});
	my $storeUrl = $record->child('store')->textValue;
	my $actorHash = CDS::Hash->fromBytes($record->child('actor')->bytesValue);
	if ($actorHash && length $storeUrl) {
		my $store = $o->{actor}->storeForUrl($storeUrl) // return $o->warning('Invalid store URL "', $storeUrl, '" in remembered account.');
		my $accountToken = CDS::AccountToken->new($store, $actorHash);
		return $o->warning('"', $o->{text}, '" is interpreted as a keyword. If you mean the account, write "', $accountToken->url, '".') if $o->isKeyword;
		return $accountToken;
	}

#line 90 "Condensation/CLI/Parser/Token.pm"
	# From a URL
	if ($o->{text} =~ /^\s*(.*?)\/accounts\/([0-9a-fA-F]{64,64})\/*\s*$/) {
		my $storeUrl = $1;
		my $actorHash = CDS::Hash->fromHex($2);
		$storeUrl = 'file://'.Cwd::abs_path($storeUrl) if $storeUrl !~ /^[a-zA-Z0-9_\+-]*:/ && -d $storeUrl;
		my $cliStore = $o->{actor}->storeForUrl($storeUrl) // return $o->warning('Invalid store URL "', $storeUrl, '".');
		return CDS::AccountToken->new($cliStore, $actorHash);
	}

#line 99 "Condensation/CLI/Parser/Token.pm"
	return;
}

sub completeAccount {
	my $o = shift;

#line 103 "Condensation/CLI/Parser/Token.pm"
	$o->completeUrl;

#line 105 "Condensation/CLI/Parser/Token.pm"
	my $records = $o->{actor}->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		my $storeUrl = $record->child('store')->textValue;
		next if ! length $storeUrl;
		my $actorHash = CDS::Hash->fromBytes($record->child('actor')->bytesValue) // next;

#line 112 "Condensation/CLI/Parser/Token.pm"
		$o->addPossibility($label);
		$o->addPossibility($storeUrl.'/accounts/'.$actorHash->hex);
	}

#line 116 "Condensation/CLI/Parser/Token.pm"
	return;
}

sub aesKey {
	my $o = shift;

#line 120 "Condensation/CLI/Parser/Token.pm"
	$o->{text} =~ /^[0-9A-Fa-f]{64}$/ || return;
	return pack('H*', $o->{text});
}

sub box {
	my $o = shift;

#line 125 "Condensation/CLI/Parser/Token.pm"
	# From a URL
	if ($o->{text} =~ /^\s*(.*?)\/accounts\/([0-9a-fA-F]{64,64})\/(messages|private|public)\/*\s*$/) {
		my $storeUrl = $1;
		my $boxLabel = $3;
		my $actorHash = CDS::Hash->fromHex($2);
		$storeUrl = 'file://'.Cwd::abs_path($storeUrl) if $storeUrl !~ /^[a-zA-Z0-9_\+-]*:/ && -d $storeUrl;
		my $cliStore = $o->{actor}->storeForUrl($storeUrl) // return $o->warning('Invalid store URL "', $storeUrl, '".');
		my $accountToken = CDS::AccountToken->new($cliStore, $actorHash);
		return CDS::BoxToken->new($accountToken, $boxLabel);
	}

#line 136 "Condensation/CLI/Parser/Token.pm"
	return;
}

sub completeBox {
	my $o = shift;

#line 140 "Condensation/CLI/Parser/Token.pm"
	$o->completeUrl;
	return;
}

sub boxLabel {
	my $o = shift;

#line 145 "Condensation/CLI/Parser/Token.pm"
	return $o->{text} if $o->{text} eq 'messages';
	return $o->{text} if $o->{text} eq 'private';
	return $o->{text} if $o->{text} eq 'public';
	return;
}

sub completeBoxLabel {
	my $o = shift;

#line 152 "Condensation/CLI/Parser/Token.pm"
	$o->addPossibility('messages');
	$o->addPossibility('private');
	$o->addPossibility('public');
}

sub file {
	my $o = shift;

#line 158 "Condensation/CLI/Parser/Token.pm"
	my $file = Cwd::abs_path($o->{text}) // return;
	return if ! -f $file;
	return $o->warning('"', $o->{text}, '" is interpreted as keyword. If you mean the file, write "./', $o->{text}, '".') if $o->isKeyword;
	return $file;
}

sub completeFile {
	my $o = shift;

#line 165 "Condensation/CLI/Parser/Token.pm"
	my $folder = './';
	my $startFilename = $o->{text};
	$startFilename = $ENV{HOME}.'/'.$1 if $startFilename =~ /^~\/(.*)$/;
	if ($startFilename eq '~') {
		$folder = $ENV{HOME}.'/';
		$startFilename = '';
	} elsif ($startFilename =~ /^(.*\/)([^\/]*)$/) {
		$folder = $1;
		$startFilename = $2;
	}

#line 176 "Condensation/CLI/Parser/Token.pm"
	for my $filename (CDS->listFolder($folder)) {
		next if $filename eq '.';
		next if $filename eq '..';
		next if substr($filename, 0, length $startFilename) ne $startFilename;
		my $file = $folder.$filename;
		$file .= '/' if -d $file;
		$file .= ' ' if -f $file;
		push @{$o->{possibilities}}, $file;
	}
}

sub filename {
	my $o = shift;

#line 188 "Condensation/CLI/Parser/Token.pm"
	return $o->warning('"', $o->{text}, '" is interpreted as keyword. If you mean the file, write "./', $o->{text}, '".') if $o->isKeyword;
	return Cwd::abs_path($o->{text});
}

sub folder {
	my $o = shift;

#line 193 "Condensation/CLI/Parser/Token.pm"
	my $folder = Cwd::abs_path($o->{text}) // return;
	return if ! -d $folder;
	return $o->warning('"', $o->{text}, '" is interpreted as keyword. If you mean the folder, write "./', $o->{text}, '".') if $o->isKeyword;
	return $folder;
}

sub completeFolder {
	my $o = shift;

#line 200 "Condensation/CLI/Parser/Token.pm"
	my $folder = './';
	my $startFilename = $o->{text};
	if ($o->{text} =~ /^(.*\/)([^\/]*)$/) {
		$folder = $1;
		$startFilename = $2;
	}

#line 207 "Condensation/CLI/Parser/Token.pm"
	for my $filename (CDS->listFolder($folder)) {
		next if $filename eq '.';
		next if $filename eq '..';
		next if substr($filename, 0, length $startFilename) ne $startFilename;
		my $file = $folder.$filename;
		next if ! -d $file;
		push @{$o->{possibilities}}, $file.'/';
	}
}

sub foldername {
	my $o = shift;

#line 218 "Condensation/CLI/Parser/Token.pm"
	return $o->warning('"', $o->{text}, '" is interpreted as keyword. If you mean the folder, write "./', $o->{text}, '".') if $o->isKeyword;
	return Cwd::abs_path($o->{text});
}

sub group {
	my $o = shift;

#line 223 "Condensation/CLI/Parser/Token.pm"
	return int($1) if $o->{text} =~ /^\s*(\d{1,5})\s*$/;
	return getgrnam($o->{text});
}

sub completeGroup {
	my $o = shift;

#line 228 "Condensation/CLI/Parser/Token.pm"
	while (my $name = getgrent) {
		$o->addPossibility($name);
	}
}

sub hash {
	my $o = shift;

#line 234 "Condensation/CLI/Parser/Token.pm"
	my $hash = CDS::Hash->fromHex($o->{text});
	return $hash if $hash;

#line 237 "Condensation/CLI/Parser/Token.pm"
	# Check if it's a remembered actor hash
	my $record = $o->{actor}->remembered($o->{text});
	my $actorHash = CDS::Hash->fromBytes($record->child('actor')->bytesValue) // return;
	return $o->warning('"', $o->{text}, '" is interpreted as keyword. If you mean the actor, write "', $actorHash->hex, '".') if $o->isKeyword;
	return $actorHash;
}

sub completeHash {
	my $o = shift;

#line 245 "Condensation/CLI/Parser/Token.pm"
	my $records = $o->{actor}->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		my $hash = CDS::Hash->fromBytes($record->child('actor')->bytesValue) // next;
		$o->addPossibility($label);
		$o->addPossibility($hash->hex);
	}

#line 253 "Condensation/CLI/Parser/Token.pm"
	for my $child ($o->{actor}->actorGroupSelector->children) {
		my $hash = $child->record->child('hash')->hashValue // next;
		$o->addPossibility($hash->hex);
	}
}

sub keyPair {
	my $o = shift;

#line 260 "Condensation/CLI/Parser/Token.pm"
	# Remembered key pair
	my $record = $o->{actor}->remembered($o->{text});
	my $file = $record->child('key pair')->textValue;

#line 264 "Condensation/CLI/Parser/Token.pm"
	# Key pair from file
	if (! length $file) {
		$file = Cwd::abs_path($o->{text}) // return;
		return $o->warning('"', $o->{text}, '" is interpreted as keyword. If you mean the file, write "./', $o->{text}, '".') if $o->isKeyword && -f $file;
	}

#line 270 "Condensation/CLI/Parser/Token.pm"
	# Load the key pair
	return if ! -f $file;
	my $bytes = CDS->readBytesFromFile($file) // return $o->warning('The key pair file "', $file, '" could not be read.');
	my $keyPair = CDS::KeyPair->fromRecord(CDS::Record->fromObject(CDS::Object->fromBytes($bytes))) // return $o->warning('The file "', $file, '" does not contain a key pair.');
	return CDS::KeyPairToken->new($file, $keyPair);
}

sub completeKeyPair {
	my $o = shift;

#line 278 "Condensation/CLI/Parser/Token.pm"
	$o->completeFile;

#line 280 "Condensation/CLI/Parser/Token.pm"
	my $records = $o->{actor}->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if ! length $record->child('key pair')->textValue;
		$o->addPossibility($label);
	}
}

sub label {
	my $o = shift;

#line 289 "Condensation/CLI/Parser/Token.pm"
	my $records = $o->{actor}->remembered($o->{text});
	return $o->{text} if $records->children;
	return;
}

sub completeLabel {
	my $o = shift;

#line 295 "Condensation/CLI/Parser/Token.pm"
	my $records = $o->{actor}->rememberedRecords;
	for my $label (keys %$records) {
		next if substr($label, 0, length $o->{text}) ne $o->{text};
		$o->addPossibility($label);
	}
}

sub object {
	my $o = shift;

#line 303 "Condensation/CLI/Parser/Token.pm"
	# Folder stores use the first two hex digits as folder
	my $url = $o->{text} =~ /^\s*(.*?\/objects\/)([0-9a-fA-F]{2,2})\/([0-9a-fA-F]{62,62})\/*\s*$/ ? $1.$2.$3 : $o->{text};

#line 306 "Condensation/CLI/Parser/Token.pm"
	# From a URL
	if ($url =~ /^\s*(.*?)\/objects\/([0-9a-fA-F]{64,64})\/*\s*$/) {
		my $storeUrl = $1;
		my $hash = CDS::Hash->fromHex($2);
		$storeUrl = 'file://'.Cwd::abs_path($storeUrl) if $storeUrl !~ /^[a-zA-Z0-9_\+-]*:/ && -d $storeUrl;
		my $cliStore = $o->{actor}->storeForUrl($storeUrl) // return $o->warning('Invalid store URL "', $storeUrl, '".');
		return CDS::ObjectToken->new($cliStore, $hash);
	}

#line 315 "Condensation/CLI/Parser/Token.pm"
	return;
}

sub completeObject {
	my $o = shift;

#line 319 "Condensation/CLI/Parser/Token.pm"
	$o->completeUrl;
	return;
}

sub objectFile {
	my $o = shift;

#line 324 "Condensation/CLI/Parser/Token.pm"
	# Key pair from file
	my $file = Cwd::abs_path($o->{text}) // return;
	return $o->warning('"', $o->{text}, '" is interpreted as keyword. If you mean the file, write "./', $o->{text}, '".') if $o->isKeyword && -f $file;

#line 328 "Condensation/CLI/Parser/Token.pm"
	# Load the object
	return if ! -f $file;
	my $bytes = CDS->readBytesFromFile($file) // return $o->warning('The object file "', $file, '" could not be read.');
	my $object = CDS::Object->fromBytes($bytes) // return $o->warning('The file "', $file, '" does not contain a Condensation object.');
	return CDS::ObjectFileToken->new($file, $object);
}

sub completeObjectFile {
	my $o = shift;

#line 336 "Condensation/CLI/Parser/Token.pm"
	$o->completeFile;
	return;
}

sub actorGroup {
	my $o = shift;

#line 341 "Condensation/CLI/Parser/Token.pm"
	# We only accept named actor groups. Accepting a single account as actor group is ambiguous whenever ACCOUNT and ACTORGROUP are accepted. For commands that are requiring an ACTORGROUP, they can also accept an ACCOUNT and then convert it.

#line 343 "Condensation/CLI/Parser/Token.pm"
	# Check if it's an actor group label
	my $record = $o->{actor}->remembered($o->{text})->child('actor group');
	return if ! scalar $record->children;
	return $o->warning('"', $o->{text}, '" is interpreted as keyword. To refer to the actor group, rename it.') if $o->isKeyword;

#line 348 "Condensation/CLI/Parser/Token.pm"
	my $builder = CDS::ActorGroupBuilder->new;
	$builder->addKnownPublicKey($o->{actor}->keyPair->publicKey);
	$builder->parse($record, 1);
	my ($actorGroup, $storeError) = $builder->load($o->{actor}->groupDataTree->unsaved, $o->{actor}->keyPair, $o);
	return $o->{actor}->storeError($o->{actor}->storageStore, $storeError) if defined $storeError;
	return CDS::ActorGroupToken->new($o->{text}, $actorGroup);
}

sub onLoadActorGroupVerifyStore {
	my $o = shift;
	my $storeUrl = shift;
	 $o->{actor}->storeForUrl($storeUrl); }

sub completeActorGroup {
	my $o = shift;

#line 359 "Condensation/CLI/Parser/Token.pm"
	my $records = $o->{actor}->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if ! scalar $record->child('actor group')->children;
		$o->addPossibility($label);
	}
	return;
}

sub port {
	my $o = shift;

#line 369 "Condensation/CLI/Parser/Token.pm"
	my $port = int($o->{text});
	return if $port <= 0 || $port > 65536;
	return $port;
}

sub rememberedStoreUrl {
	my $o = shift;

#line 375 "Condensation/CLI/Parser/Token.pm"
	my $record = $o->{actor}->remembered($o->{text});
	my $storeUrl = $record->child('store')->textValue;
	return if ! length $storeUrl;

#line 379 "Condensation/CLI/Parser/Token.pm"
	return $o->warning('"', $o->{text}, '" is interpreted as keyword. If you mean the store, write "', $storeUrl, '".') if $o->isKeyword;
	return $storeUrl;
}

sub directStoreUrl {
	my $o = shift;

#line 384 "Condensation/CLI/Parser/Token.pm"
	return $o->warning('"', $o->{text}, '" is interpreted as keyword. If you mean the folder store, write "./', $o->{text}, '".') if $o->isKeyword;
	return if $o->{text} =~ /[0-9a-f]{32}/;

#line 387 "Condensation/CLI/Parser/Token.pm"
	return $o->{text} if $o->{text} =~ /^[a-zA-Z0-9_\+-]*:/;
	return 'file://'.Cwd::abs_path($o->{text}) if -d $o->{text} && -d $o->{text}.'/accounts' && -d $o->{text}.'/objects';
	return;
}

sub store {
	my $o = shift;

#line 393 "Condensation/CLI/Parser/Token.pm"
	my $url = $o->rememberedStoreUrl // $o->directStoreUrl // return;
	return $o->{actor}->storeForUrl($url) // return $o->warning('"', $o->{text}, '" looks like a store, but no implementation is available to handle this protocol.');
}

sub completeFolderStoreUrl {
	my $o = shift;

#line 398 "Condensation/CLI/Parser/Token.pm"
	my $folder = './';
	my $startFilename = $o->{text};
	if ($o->{text} =~ /^(.*\/)([^\/]*)$/) {
		$folder = $1;
		$startFilename = $2;
	}

#line 405 "Condensation/CLI/Parser/Token.pm"
	for my $filename (CDS->listFolder($folder)) {
		next if $filename eq '.';
		next if $filename eq '..';
		next if substr($filename, 0, length $startFilename) ne $startFilename;
		my $file = $folder.$filename;
		next if ! -d $file;
		push @{$o->{possibilities}}, $file . (-d $file.'/accounts' && -d $file.'/objects' ? ' ' : '/');
	}
}

sub completeStoreUrl {
	my $o = shift;

#line 416 "Condensation/CLI/Parser/Token.pm"
	$o->completeFolderStoreUrl;
	$o->completeUrl;

#line 419 "Condensation/CLI/Parser/Token.pm"
	my $records = $o->{actor}->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if length $record->child('actor')->bytesValue;
		my $storeUrl = $record->child('store')->textValue;
		next if ! length $storeUrl;
		$o->addPossibility($label);
		$o->addPossibility($storeUrl);
	}
}

sub completeUrl {
	my $o = shift;

#line 431 "Condensation/CLI/Parser/Token.pm"
	$o->addPartialPossibility('http://');
	$o->addPartialPossibility('https://');
	$o->addPartialPossibility('ftp://');
	$o->addPartialPossibility('sftp://');
	$o->addPartialPossibility('file://');
}

sub text {
	my $o = shift;

#line 439 "Condensation/CLI/Parser/Token.pm"
	return $o->{text};
}

sub user {
	my $o = shift;

#line 443 "Condensation/CLI/Parser/Token.pm"
	return int($1) if $o->{text} =~ /^\s*(\d{1,5})\s*$/;
	return getpwnam($o->{text});
}

sub completeUser {
	my $o = shift;

#line 448 "Condensation/CLI/Parser/Token.pm"
	while (my $name = getpwent) {
		$o->addPossibility($name);
	}
}

sub warning {
	my $o = shift;

#line 454 "Condensation/CLI/Parser/Token.pm"
	push @{$o->{warnings}}, join('', @_);
	return;
}

# Reads the private box of an actor.
package CDS::PrivateBoxReader;

sub new {
	my $class = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $store = shift;
	my $delegate = shift;

#line 4 "Condensation/Actors/PrivateBoxReader.pm"
	return bless {
		keyPair => $keyPair,
		actorOnStore => CDS::ActorOnStore->new($keyPair->publicKey, $store),
		delegate => $delegate,
		entries => {},
		};
}

#line 12 "Condensation/Actors/PrivateBoxReader.pm"
sub keyPair { shift->{keyPair} }
sub actorOnStore { shift->{actorOnStore} }
sub delegate { shift->{delegate} }

sub read {
	my $o = shift;

#line 17 "Condensation/Actors/PrivateBoxReader.pm"
	my $store = $o->{actorOnStore}->store;
	my ($hashes, $listError) = $store->list($o->{actorOnStore}->publicKey->hash, 'private', 0, $o->{keyPair});
	return if defined $listError;

#line 21 "Condensation/Actors/PrivateBoxReader.pm"
	# Keep track of the processed entries
	my $newEntries = {};
	for my $hash (@$hashes) {
		$newEntries->{$hash->bytes} = $o->{entries}->{$hash->bytes} // {hash => $hash, processed => 0};
	}
	$o->{entries} = $newEntries;

#line 28 "Condensation/Actors/PrivateBoxReader.pm"
	# Process new entries
	for my $entry (values %$newEntries) {
		next if $entry->{processed};

#line 32 "Condensation/Actors/PrivateBoxReader.pm"
		# Get the envelope
		my ($object, $getError) = $store->get($entry->{hash}, $o->{keyPair});
		return if defined $getError;

#line 36 "Condensation/Actors/PrivateBoxReader.pm"
		if (! defined $object) {
			$o->invalid($entry, 'Envelope object not found.');
			next;
		}

#line 41 "Condensation/Actors/PrivateBoxReader.pm"
		# Parse the record
		my $envelope = CDS::Record->fromObject($object);
		if (! $envelope) {
			$o->invalid($entry, 'Envelope is not a record.');
			next;
		}

#line 48 "Condensation/Actors/PrivateBoxReader.pm"
		# Read the content hash
		my $contentHash = $envelope->child('content')->hashValue;
		if (! $contentHash) {
			$o->invalid($entry, 'Missing content hash.');
			next;
		}

#line 55 "Condensation/Actors/PrivateBoxReader.pm"
		# Verify the signature
		if (! CDS->verifyEnvelopeSignature($envelope, $o->{keyPair}->publicKey, $contentHash)) {
			$o->invalid($entry, 'Invalid signature.');
			next;
		}

#line 61 "Condensation/Actors/PrivateBoxReader.pm"
		# Decrypt the key
		my $aesKey = $o->{keyPair}->decryptKeyOnEnvelope($envelope);
		if (! $aesKey) {
			$o->invalid($entry, 'Not encrypted for us.');
			next;
		}

#line 68 "Condensation/Actors/PrivateBoxReader.pm"
		# Retrieve the content
		my $contentHashAndKey = CDS::HashAndKey->new($contentHash, $aesKey);
		my ($contentRecord, $contentObject, $contentInvalidReason, $contentStoreError) = $o->{keyPair}->getAndDecryptRecord($contentHashAndKey, $store);
		return if defined $contentStoreError;

#line 73 "Condensation/Actors/PrivateBoxReader.pm"
		if (defined $contentInvalidReason) {
			$o->invalid($entry, $contentInvalidReason);
			next;
		}

#line 78 "Condensation/Actors/PrivateBoxReader.pm"
		$entry->{processed} = 1;
		my $source = CDS::Source->new($o->{keyPair}, $o->{actorOnStore}, 'private', $entry->{hash});
		$o->{delegate}->onPrivateBoxEntry($source, $envelope, $contentHashAndKey, $contentRecord);
	}

#line 83 "Condensation/Actors/PrivateBoxReader.pm"
	return 1;
}

sub invalid {
	my $o = shift;
	my $entry = shift;
	my $reason = shift;

#line 87 "Condensation/Actors/PrivateBoxReader.pm"
	$entry->{processed} = 1;
	my $source = CDS::Source->new($o->{actorOnStore}, 'private', $entry->{hash});
	$o->{delegate}->onPrivateBoxInvalidEntry($source, $reason);
}

#line 92 "Condensation/Actors/PrivateBoxReader.pm"
# Delegate
# onPrivateBoxEntry($source, $envelope, $contentHashAndKey, $contentRecord)
# onPrivateBoxInvalidEntry($source, $reason)

package CDS::PrivateRoot;

sub new {
	my $class = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';
	my $store = shift;
	my $delegate = shift;

#line 2 "Condensation/Actors/PrivateRoot.pm"
	my $o = bless {
		unsaved => CDS::Unsaved->new($store),
		delegate => $delegate,
		dataHandlers => {},
		hasChanges => 0,
		procured => 0,
		mergedEntries => [],
		};

#line 11 "Condensation/Actors/PrivateRoot.pm"
	$o->{privateBoxReader} = CDS::PrivateBoxReader->new($keyPair, $store, $o);
	return $o;
}

#line 15 "Condensation/Actors/PrivateRoot.pm"
sub delegate { shift->{delegate} }
sub privateBoxReader { shift->{privateBoxReader} }
sub unsaved { shift->{unsaved} }
sub hasChanges { shift->{hasChanges} }
sub procured { shift->{procured} }

sub addDataHandler {
	my $o = shift;
	my $label = shift;
	my $dataHandler = shift;

#line 22 "Condensation/Actors/PrivateRoot.pm"
	$o->{dataHandlers}->{$label} = $dataHandler;
}

sub removeDataHandler {
	my $o = shift;
	my $label = shift;
	my $dataHandler = shift;

#line 26 "Condensation/Actors/PrivateRoot.pm"
	my $registered = $o->{dataHandlers}->{$label};
	return if $registered != $dataHandler;
	delete $o->{dataHandlers}->{$label};
}

#line 31 "Condensation/Actors/PrivateRoot.pm"
# *** Procurement

sub procure {
	my $o = shift;
	my $interval = shift;

#line 34 "Condensation/Actors/PrivateRoot.pm"
	my $now = CDS->now;
	return $o->{procured} if $o->{procured} + $interval > $now;
	$o->{privateBoxReader}->read // return;
	$o->{procured} = $now;
	return $now;
}

#line 41 "Condensation/Actors/PrivateRoot.pm"
# *** Merging

sub onPrivateBoxEntry {
	my $o = shift;
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';
	my $envelope = shift; die 'wrong type '.ref($envelope).' for $envelope' if defined $envelope && ref $envelope ne 'CDS::Record';
	my $contentHashAndKey = shift;
	my $content = shift;

#line 44 "Condensation/Actors/PrivateRoot.pm"
	for my $section ($content->children) {
		my $dataHandler = $o->{dataHandlers}->{$section->bytes} // next;
		$dataHandler->mergeData($section);
	}

#line 49 "Condensation/Actors/PrivateRoot.pm"
	push @{$o->{mergedEntries}}, $source->hash;
}

sub onPrivateBoxInvalidEntry {
	my $o = shift;
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';
	my $reason = shift;

#line 53 "Condensation/Actors/PrivateRoot.pm"
	$o->{delegate}->onPrivateRootReadingInvalidEntry($source, $reason);
	$source->discard;
}

#line 57 "Condensation/Actors/PrivateRoot.pm"
# *** Saving

sub dataChanged {
	my $o = shift;

#line 60 "Condensation/Actors/PrivateRoot.pm"
	$o->{hasChanges} = 1;
}

sub save {
	my $o = shift;
	my $entrustedKeys = shift;

#line 64 "Condensation/Actors/PrivateRoot.pm"
	$o->{unsaved}->startSaving;
	return $o->savingSucceeded if ! $o->{hasChanges};
	$o->{hasChanges} = 0;

#line 68 "Condensation/Actors/PrivateRoot.pm"
	# Create the record
	my $record = CDS::Record->new;
	$record->add('created')->addInteger(CDS->now);
	$record->add('client')->add(CDS->version);
	for my $label (keys %{$o->{dataHandlers}}) {
		my $dataHandler = $o->{dataHandlers}->{$label};
		$dataHandler->addDataTo($record->add($label));
	}

#line 77 "Condensation/Actors/PrivateRoot.pm"
	# Submit the object
	my $key = CDS->randomKey;
	my $object = $record->toObject->crypt($key);
	my $hash = $object->calculateHash;
	$o->{unsaved}->savingState->addObject($hash, $object);
	my $hashAndKey = CDS::HashAndKey->new($hash, $key);

#line 84 "Condensation/Actors/PrivateRoot.pm"
	# Create the envelope
	my $keyPair = $o->{privateBoxReader}->keyPair;
	my $publicKeys = [$keyPair->publicKey, @$entrustedKeys];
	my $envelopeObject = $keyPair->createPrivateEnvelope($hashAndKey, $publicKeys)->toObject;
	my $envelopeHash = $envelopeObject->calculateHash;
	$o->{unsaved}->savingState->addObject($envelopeHash, $envelopeObject);

#line 91 "Condensation/Actors/PrivateRoot.pm"
	# Transfer
	my ($missing, $store, $storeError) = $keyPair->transfer([$hash], $o->{unsaved}, $o->{privateBoxReader}->actorOnStore->store);
	return $o->savingFailed($missing) if defined $missing || defined $storeError;

#line 95 "Condensation/Actors/PrivateRoot.pm"
	# Modify the private box
	my $modifications = CDS::StoreModifications->new;
	$modifications->add($keyPair->publicKey->hash, 'private', $envelopeHash, $envelopeObject);
	for my $hash (@{$o->{mergedEntries}}) {
		$modifications->remove($keyPair->publicKey->hash, 'private', $hash);
	}

#line 102 "Condensation/Actors/PrivateRoot.pm"
	my $modifyError = $o->{privateBoxReader}->actorOnStore->store->modify($modifications, $keyPair);
	return $o->savingFailed if defined $modifyError;

#line 105 "Condensation/Actors/PrivateRoot.pm"
	# Set the new merged hashes
	$o->{mergedEntries} = [$envelopeHash];
	return $o->savingSucceeded;
}

sub savingSucceeded {
	my $o = shift;

#line 111 "Condensation/Actors/PrivateRoot.pm"
	# Discard all merged sources
	for my $source ($o->{unsaved}->savingState->mergedSources) {
		$source->discard;
	}

#line 116 "Condensation/Actors/PrivateRoot.pm"
	# Call all data saved handlers
	for my $handler ($o->{unsaved}->savingState->dataSavedHandlers) {
		$handler->onDataSaved;
	}

#line 121 "Condensation/Actors/PrivateRoot.pm"
	$o->{unsaved}->savingDone;
	return 1;
}

sub savingFailed {
	my $o = shift;
	my $missing = shift;
		# private
#line 126 "Condensation/Actors/PrivateRoot.pm"
	$o->{unsaved}->savingFailed;
	$o->{hasChanges} = 1;
	return undef, $missing;
}

# A public key of somebody.
package CDS::PublicKey;

sub fromObject {
	my $class = shift;
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

#line 4 "Condensation/Actors/PublicKey.pm"
	my $record = CDS::Record->fromObject($object) // return;
	my $rsaPublicKey = CDS::C::publicKeyNew($record->child('e')->bytesValue, $record->child('n')->bytesValue) // return;
	return bless {
		hash => $object->calculateHash,
		rsaPublicKey => $rsaPublicKey,
		object => $object,
		lastAccess => 0,	# used by PublicKeyCache
		};
}

#line 14 "Condensation/Actors/PublicKey.pm"
sub object { shift->{object} }
sub bytes {
	my $o = shift;
	 $o->{object}->bytes }

#line 17 "Condensation/Actors/PublicKey.pm"
### Public key interface ###

#line 19 "Condensation/Actors/PublicKey.pm"
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

#line 2 "Condensation/Actors/PublicKeyCache.pm"
	return bless {
		cache => {},
		maxSize => $maxSize,
		};
}

sub add {
	my $o = shift;
	my $publicKey = shift; die 'wrong type '.ref($publicKey).' for $publicKey' if defined $publicKey && ref $publicKey ne 'CDS::PublicKey';

#line 9 "Condensation/Actors/PublicKeyCache.pm"
	$o->{cache}->{$publicKey->hash->bytes} = {publicKey => $publicKey, lastAccess => CDS->now};
	$o->deleteOldest;
	return;
}

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 15 "Condensation/Actors/PublicKeyCache.pm"
	my $entry = $o->{cache}->{$hash->bytes} // return;
	$entry->{lastAccess} = CDS->now;
	return $entry->{publicKey};
}

sub deleteOldest {
	my $o = shift;
		# private
#line 21 "Condensation/Actors/PublicKeyCache.pm"
	return if scalar values %{$o->{cache}} < $o->{maxSize};

#line 23 "Condensation/Actors/PublicKeyCache.pm"
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

#line 2 "Condensation/Stores/PutTree.pm"
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

#line 11 "Condensation/Stores/PutTree.pm"
	return if $o->{done}->{$hash->bytes};

#line 13 "Condensation/Stores/PutTree.pm"
	# Get the item
	my $hashAndObject = $o->{commitPool}->object($hash) // return;

#line 16 "Condensation/Stores/PutTree.pm"
	# Upload all children
	for my $hash ($hashAndObject->object->hashes) {
		my $error = $o->put($hash);
		return $error if defined $error;
	}

#line 22 "Condensation/Stores/PutTree.pm"
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

#line 2 "Condensation/Actors/ReceivedMessage.pm"
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

#line 15 "Condensation/Actors/ReceivedMessage.pm"
sub source { shift->{source} }
sub envelope { shift->{envelope} }
sub senderStoreUrl { shift->{senderStoreUrl} }
sub sender { shift->{sender} }
sub content { shift->{content} }

sub waitForSenderStore {
	my $o = shift;

#line 22 "Condensation/Actors/ReceivedMessage.pm"
	$o->{entry}->{waitingForStore} = $o->sender->store;
}

sub skip {
	my $o = shift;

#line 26 "Condensation/Actors/ReceivedMessage.pm"
	$o->{entry}->{processed} = 0;
}

# A record is a tree, whereby each nodes holds a byte sequence and an optional hash.
# Child nodes are ordered, although the order does not always matter.
package CDS::Record;

sub fromObject {
	my $class = shift;
	my $object = shift // return; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

#line 6 "Condensation/Serialization/Record.pm"
	my $root = CDS::Record->new;
	$root->addFromObject($object) // return;
	return $root;
}

sub new {
	my $class = shift;
	my $bytes = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 12 "Condensation/Serialization/Record.pm"
	bless {
		bytes => $bytes // '',
		hash => $hash,
		children => [],
		};
}

#line 19 "Condensation/Serialization/Record.pm"
# *** Adding

#line 21 "Condensation/Serialization/Record.pm"
# Adds a record
sub add {
	my $o = shift;
	my $bytes = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 23 "Condensation/Serialization/Record.pm"
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

#line 37 "Condensation/Serialization/Record.pm"
	return 1 if ! length $object->data;
	return CDS::RecordReader->new($object)->readChildren($o);
}

#line 41 "Condensation/Serialization/Record.pm"
# *** Set value

sub set {
	my $o = shift;
	my $bytes = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 44 "Condensation/Serialization/Record.pm"
	$o->{bytes} = $bytes;
	$o->{hash} = $hash;
	return;
}

#line 49 "Condensation/Serialization/Record.pm"
# *** Querying

#line 51 "Condensation/Serialization/Record.pm"
# Returns true if the record contains a child with the indicated bytes.
sub contains {
	my $o = shift;
	my $bytes = shift;

#line 53 "Condensation/Serialization/Record.pm"
	for my $child (@{$o->{children}}) {
		return 1 if $child->{bytes} eq $bytes;
	}
	return;
}

#line 59 "Condensation/Serialization/Record.pm"
# Returns the child record for the given bytes. If no record with these bytes exists, a record with these bytes is returned (but not added).
sub child {
	my $o = shift;
	my $bytes = shift;

#line 61 "Condensation/Serialization/Record.pm"
	for my $child (@{$o->{children}}) {
		return $child if $child->{bytes} eq $bytes;
	}
	return $o->new($bytes);
}

#line 67 "Condensation/Serialization/Record.pm"
# Returns the first child, or an empty record.
sub firstChild {
	my $o = shift;
	 $o->{children}->[0] // $o->new }

#line 70 "Condensation/Serialization/Record.pm"
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

#line 76 "Condensation/Serialization/Record.pm"
# *** Get value

#line 78 "Condensation/Serialization/Record.pm"
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

#line 88 "Condensation/Serialization/Record.pm"
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

#line 101 "Condensation/Serialization/Record.pm"
# *** Dependent hashes

sub dependentHashes {
	my $o = shift;

#line 104 "Condensation/Serialization/Record.pm"
	my $hashes = {};
	$o->traverseHashes($hashes);
	return values %$hashes;
}

sub traverseHashes {
	my $o = shift;
	my $hashes = shift;
		# private
#line 110 "Condensation/Serialization/Record.pm"
	$hashes->{$o->{hash}->bytes} = $o->{hash} if $o->{hash};
	for my $child (@{$o->{children}}) {
		$child->traverseHashes($hashes);
	}
}

#line 116 "Condensation/Serialization/Record.pm"
# *** Size

sub countEntries {
	my $o = shift;

#line 119 "Condensation/Serialization/Record.pm"
	my $count = 1;
	for my $child (@{$o->{children}}) { $count += $child->countEntries; }
	return $count;
}

sub calculateSize {
	my $o = shift;

#line 125 "Condensation/Serialization/Record.pm"
	return 4 + $o->calculateSizeContribution;
}

sub calculateSizeContribution {
	my $o = shift;
		# private
#line 129 "Condensation/Serialization/Record.pm"
	my $byteLength = length $o->{bytes};
	my $size = $byteLength < 30 ? 1 : $byteLength < 286 ? 2 : 9;
	$size += $byteLength;
	$size += 32 + 4 if $o->{hash};
	for my $child (@{$o->{children}}) {
		$size += $child->calculateSizeContribution;
	}
	return $size;
}

#line 139 "Condensation/Serialization/Record.pm"
# *** Serialization

#line 141 "Condensation/Serialization/Record.pm"
# Serializes this record into a Condensation object.
sub toObject {
	my $o = shift;

#line 143 "Condensation/Serialization/Record.pm"
	my $writer = CDS::RecordWriter->new;
	$writer->writeChildren($o);
	return CDS::Object->create($writer->header, $writer->data);
}

package CDS::RecordReader;

sub new {
	my $class = shift;
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

#line 2 "Condensation/Serialization/RecordReader.pm"
	return bless {
		object => $object,
		data => $object->data,
		pos => 0,
		hasError => 0
		};
}

#line 10 "Condensation/Serialization/RecordReader.pm"
sub hasError { shift->{hasError} }

sub readChildren {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 13 "Condensation/Serialization/RecordReader.pm"
	while (1) {
		# Flags
		my $flags = $o->readUnsigned8 // return;

#line 17 "Condensation/Serialization/RecordReader.pm"
		# Data
		my $length = $flags & 0x1f;
		my $byteLength = $length == 30 ? 30 + ($o->readUnsigned8 // return) : $length == 31 ? ($o->readUnsigned64 // return) : $length;
		my $bytes = $o->readBytes($byteLength);
		my $hash = $flags & 0x20 ? $o->{object}->hashAtIndex($o->readUnsigned32 // return) : undef;
		return if $o->{hasError};

#line 24 "Condensation/Serialization/RecordReader.pm"
		# Children
		my $child = $record->add($bytes, $hash);
		return if $flags & 0x40 && ! $o->readChildren($child);
		return 1 if ! ($flags & 0x80);
	}
}

sub use {
	my $o = shift;
	my $length = shift;

#line 32 "Condensation/Serialization/RecordReader.pm"
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

#line 2 "Condensation/Serialization/RecordWriter.pm"
	return bless {
		hashesCount => 0,
		hashes => '',
		data => ''
		};
}

sub header {
	my $o = shift;
	 pack('L>', $o->{hashesCount}).$o->{hashes} }
#line 10 "Condensation/Serialization/RecordWriter.pm"
sub data { shift->{data} }

sub writeChildren {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 13 "Condensation/Serialization/RecordWriter.pm"
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

#line 21 "Condensation/Serialization/RecordWriter.pm"
	# Flags
	my $byteLength = length $record->{bytes};
	my $flags = $byteLength < 30 ? $byteLength : $byteLength < 286 ? 30 : 31;
	$flags |= 0x20 if defined $record->{hash};
	my $countChildren = scalar @{$record->{children}};
	$flags |= 0x40 if $countChildren;
	$flags |= 0x80 if $hasMoreSiblings;
	$o->writeUnsigned8($flags);

#line 30 "Condensation/Serialization/RecordWriter.pm"
	# Data
	$o->writeUnsigned8($byteLength - 30) if ($flags & 0x1f) == 30;
	$o->writeUnsigned64($byteLength) if ($flags & 0x1f) == 31;
	$o->writeBytes($record->{bytes});
	$o->writeUnsigned32($o->addHash($record->{hash})) if $flags & 0x20;

#line 36 "Condensation/Serialization/RecordWriter.pm"
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

#line 45 "Condensation/Serialization/RecordWriter.pm"
	warn $bytes.' is a utf8 string, not a byte string.' if utf8::is_utf8($bytes);
	$o->{data} .= $bytes;
}

sub addHash {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 50 "Condensation/Serialization/RecordWriter.pm"
	my $index = $o->{hashesCount};
	$o->{hashes} .= $hash->bytes;
	$o->{hashesCount} += 1;
	return $index;
}

package CDS::RootDataTree;

use parent -norequire, 'CDS::DataTree';

sub new {
	my $class = shift;
	my $privateRoot = shift;
	my $label = shift;

#line 4 "Condensation/DataTree/RootDataTree.pm"
	my $o = $class->SUPER::new($privateRoot->privateBoxReader->keyPair, $privateRoot->unsaved);
	$o->{privateRoot} = $privateRoot;
	$o->{label} = $label;
	$privateRoot->addDataHandler($label, $o);

#line 9 "Condensation/DataTree/RootDataTree.pm"
	# State
	$o->{dataSharingMessage} = undef;
	return $o;
}

#line 14 "Condensation/DataTree/RootDataTree.pm"
sub privateRoot { shift->{privateRoot} }
sub label { shift->{label} }

sub savingDone {
	my $o = shift;
	my $revision = shift;
	my $newPart = shift;
	my $obsoleteParts = shift;

#line 18 "Condensation/DataTree/RootDataTree.pm"
	$o->{privateRoot}->unsaved->state->merge($o->{unsaved}->savingState);
	$o->{unsaved}->savingDone;
	$o->{privateRoot}->dataChanged if $newPart || scalar @$obsoleteParts;
}

sub addDataTo {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 24 "Condensation/DataTree/RootDataTree.pm"
	for my $part (sort { $a->{hashAndKey}->hash->bytes cmp $b->{hashAndKey}->hash->bytes } values %{$o->{parts}}) {
		$record->addHashAndKey($part->{hashAndKey});
	}
}
sub mergeData {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 29 "Condensation/DataTree/RootDataTree.pm"
	my @hashesAndKeys;
	for my $child ($record->children) {
		push @hashesAndKeys, $child->asHashAndKey // next;
	}

#line 34 "Condensation/DataTree/RootDataTree.pm"
	$o->merge(@hashesAndKeys);
}

sub mergeExternalData {
	my $o = shift;
	my $store = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';

#line 38 "Condensation/DataTree/RootDataTree.pm"
	my @hashes;
	my @hashesAndKeys;
	for my $child ($record->children) {
		my $hashAndKey = $child->asHashAndKey // next;
		next if $o->{parts}->{$hashAndKey->hash->bytes};
		push @hashes, $hashAndKey->hash;
		push @hashesAndKeys, $hashAndKey;
	}

#line 47 "Condensation/DataTree/RootDataTree.pm"
	my ($missing, $transferStore, $storeError) = $o->{keyPair}->transfer([@hashes], $store, $o->{privateRoot}->unsaved);
	return if defined $storeError;
	return if $missing;

#line 51 "Condensation/DataTree/RootDataTree.pm"
	if ($source) {
		$source->keep;
		$o->{privateRoot}->unsaved->state->addMergedSource($source);
	}

#line 56 "Condensation/DataTree/RootDataTree.pm"
	$o->merge(@hashesAndKeys);
	return 1;
}

package CDS::Selector;

sub root {
	my $class = shift;
	my $dataTree = shift;

#line 4 "Condensation/DataTree/Selector.pm"
	return bless {dataTree => $dataTree, id => 'ROOT', label => ''};
}

#line 7 "Condensation/DataTree/Selector.pm"
sub dataTree { shift->{dataTree} }
sub parent { shift->{parent} }
sub label { shift->{label} }

sub child {
	my $o = shift;
	my $label = shift;

#line 12 "Condensation/DataTree/Selector.pm"
	return bless {
		dataTree => $o->{dataTree},
		id => $o->{id}.'/'.unpack('H*', $label),
		parent => $o,
		label => $label,
		};
}

sub childWithText {
	my $o = shift;
	my $label = shift;

#line 21 "Condensation/DataTree/Selector.pm"
	return $o->child(Encode::encode_utf8($label // ''));
}

sub children {
	my $o = shift;

#line 25 "Condensation/DataTree/Selector.pm"
	my $item = $o->{dataTree}->get($o) // return;
	return map { $_->{selector} } @{$item->{children}};
}

#line 29 "Condensation/DataTree/Selector.pm"
# Value

sub revision {
	my $o = shift;

#line 32 "Condensation/DataTree/Selector.pm"
	my $item = $o->{dataTree}->get($o) // return 0;
	return $item->{revision};
}

sub isSet {
	my $o = shift;

#line 37 "Condensation/DataTree/Selector.pm"
	my $item = $o->{dataTree}->get($o) // return;
	return scalar $item->{record}->children > 0;
}

sub record {
	my $o = shift;

#line 42 "Condensation/DataTree/Selector.pm"
	my $item = $o->{dataTree}->get($o) // return CDS::Record->new;
	return $item->{record};
}

sub set {
	my $o = shift;
	my $record = shift // return; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 47 "Condensation/DataTree/Selector.pm"
	my $now = CDS->now;
	my $item = $o->{dataTree}->getOrCreate($o);
	$item->mergeValue($o->{dataTree}->{changes}, $item->{revision} >= $now ? $item->{revision} + 1 : $now, $record);
}

sub merge {
	my $o = shift;
	my $revision = shift;
	my $record = shift // return; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 53 "Condensation/DataTree/Selector.pm"
	my $item = $o->{dataTree}->getOrCreate($o);
	return $item->mergeValue($o->{dataTree}->{changes}, $revision, $record);
}

sub clear {
	my $o = shift;
	 $o->set(CDS::Record->new) }

sub clearInThePast {
	my $o = shift;

#line 60 "Condensation/DataTree/Selector.pm"
	$o->merge($o->revision + 1, CDS::Record->new) if $o->isSet;
}

sub forget {
	my $o = shift;

#line 64 "Condensation/DataTree/Selector.pm"
	my $item = $o->{dataTree}->get($o) // return;
	$item->forget;
}

sub forgetBranch {
	my $o = shift;

#line 69 "Condensation/DataTree/Selector.pm"
	for my $child ($o->children) { $child->forgetBranch; }
	$o->forget;
}

#line 73 "Condensation/DataTree/Selector.pm"
# Convenience methods (simple interface)

sub firstValue {
	my $o = shift;

#line 76 "Condensation/DataTree/Selector.pm"
	my $item = $o->{dataTree}->get($o) // return CDS::Record->new;
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

#line 88 "Condensation/DataTree/Selector.pm"
# Sets a new value unless the node has that value already.
sub setBytes {
	my $o = shift;
	my $bytes = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 90 "Condensation/DataTree/Selector.pm"
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

#line 102 "Condensation/DataTree/Selector.pm"
# Adding objects and merged sources

sub addObject {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

#line 105 "Condensation/DataTree/Selector.pm"
	$o->{dataTree}->{unsaved}->state->addObject($hash, $object);
}

sub addMergedSource {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 109 "Condensation/DataTree/Selector.pm"
	$o->{dataTree}->{unsaved}->state->addMergedSource($hash);
}

package CDS::SentItem;

use parent -norequire, 'CDS::UnionList::Item';

sub new {
	my $class = shift;
	my $unionList = shift;
	my $id = shift;

#line 4 "Condensation/ActorWithDataTree/SentItem.pm"
	my $o = $class->SUPER::new($unionList, $id);
	$o->{validUntil} = 0;
	$o->{message} = CDS::Record->new;
	return $o;
}

#line 10 "Condensation/ActorWithDataTree/SentItem.pm"
sub validUntil { shift->{validUntil} }
sub envelopeHash {
	my $o = shift;
	 CDS::Hash->fromBytes($o->{message}->bytes) }
sub envelopeHashBytes {
	my $o = shift;
	 $o->{message}->bytes }
#line 13 "Condensation/ActorWithDataTree/SentItem.pm"
sub message { shift->{message} }

sub addToRecord {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 16 "Condensation/ActorWithDataTree/SentItem.pm"
	$record->add($o->{id})->addInteger($o->{validUntil})->addRecord($o->{message});
}

sub set {
	my $o = shift;
	my $validUntil = shift;
	my $envelopeHash = shift; die 'wrong type '.ref($envelopeHash).' for $envelopeHash' if defined $envelopeHash && ref $envelopeHash ne 'CDS::Hash';
	my $messageRecord = shift; die 'wrong type '.ref($messageRecord).' for $messageRecord' if defined $messageRecord && ref $messageRecord ne 'CDS::Record';

#line 20 "Condensation/ActorWithDataTree/SentItem.pm"
	my $message = CDS::Record->new($envelopeHash->bytes);
	$message->addRecord($messageRecord->children);
	$o->merge($o->{unionList}->{changes}, CDS->max($validUntil, $o->{validUntil} + 1), $message);
}

sub clear {
	my $o = shift;
	my $validUntil = shift;

#line 26 "Condensation/ActorWithDataTree/SentItem.pm"
	$o->merge($o->{unionList}->{changes}, CDS->max($validUntil, $o->{validUntil} + 1), CDS::Record->new);
}

sub merge {
	my $o = shift;
	my $part = shift;
	my $validUntil = shift;
	my $message = shift;

#line 30 "Condensation/ActorWithDataTree/SentItem.pm"
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

#line 4 "Condensation/ActorWithDataTree/SentList.pm"
	return $class->SUPER::new($privateRoot, 'sent list');
}

sub createItem {
	my $o = shift;
	my $id = shift;

#line 8 "Condensation/ActorWithDataTree/SentList.pm"
	return CDS::SentItem->new($o, $id);
}

sub mergeRecord {
	my $o = shift;
	my $part = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 12 "Condensation/ActorWithDataTree/SentList.pm"
	my $item = $o->getOrCreate($record->bytes);
	for my $child ($record->children) {
		my $validUntil = $child->asInteger;
		my $message = $child->firstChild;
		$item->merge($part, $validUntil, $message);
	}
}

sub forgetObsoleteItems {
	my $o = shift;

#line 21 "Condensation/ActorWithDataTree/SentList.pm"
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

#line 2 "Condensation/Actors/Source.pm"
	return bless {
		keyPair => $keyPair,
		actorOnStore => $actorOnStore,
		boxLabel => $boxLabel,
		hash => $hash,
		referenceCount => 1,
		};
}

#line 11 "Condensation/Actors/Source.pm"
sub keyPair { shift->{keyPair} }
sub actorOnStore { shift->{actorOnStore} }
sub boxLabel { shift->{boxLabel} }
sub hash { shift->{hash} }
sub referenceCount { shift->{referenceCount} }

sub keep {
	my $o = shift;

#line 18 "Condensation/Actors/Source.pm"
	if ($o->{referenceCount} < 1) {
		warn 'The source '.$o->{actorOnStore}->publicKey->hash->hex.'/'.$o->{boxLabel}.'/'.$o->{hash}->hex.' has already been discarded, and cannot be kept any more.';
		return;
	}

#line 23 "Condensation/Actors/Source.pm"
	$o->{referenceCount} += 1;
}

sub discard {
	my $o = shift;

#line 27 "Condensation/Actors/Source.pm"
	if ($o->{referenceCount} < 1) {
		warn 'The source '.$o->{actorOnStore}->publicKey->hash->hex.'/'.$o->{boxLabel}.'/'.$o->{hash}->hex.' has already been discarded, and cannot be discarded again.';
		return;
	}

#line 32 "Condensation/Actors/Source.pm"
	$o->{referenceCount} -= 1;
	return if $o->{referenceCount} > 0;

#line 35 "Condensation/Actors/Source.pm"
	$o->{actorOnStore}->store->remove($o->{actorOnStore}->publicKey->hash, $o->{boxLabel}, $o->{hash}, $o->{keyPair});
}

# A store mapping objects and accounts to a group of stores.
package CDS::SplitStore;

use parent -norequire, 'CDS::Store';

sub new {
	my $class = shift;
	my $key = shift;

#line 5 "Condensation/Stores/SplitStore.pm"
	return bless {
		id => 'Split Store\n'.unpack('H*', CDS::C::aesCrypt(CDS->zeroCTR, $key, CDS->zeroCTR)),
		key => $key,
		accountStores => [],
		objectStores => [],
		};
}

#line 13 "Condensation/Stores/SplitStore.pm"
sub id { shift->{id} }

#line 15 "Condensation/Stores/SplitStore.pm"
### Store configuration

sub assignAccounts {
	my $o = shift;
	my $fromIndex = shift;
	my $toIndex = shift;
	my $store = shift;

#line 18 "Condensation/Stores/SplitStore.pm"
	for my $i ($fromIndex .. $toIndex) {
		$o->{accountStores}->[$i] = $store;
	}
}

sub assignObjects {
	my $o = shift;
	my $fromIndex = shift;
	my $toIndex = shift;
	my $store = shift;

#line 24 "Condensation/Stores/SplitStore.pm"
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

#line 32 "Condensation/Stores/SplitStore.pm"
### Hash encryption

#line 34 "Condensation/Stores/SplitStore.pm"
our $zeroCounter = "\0" x 16;

sub storeIndex {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 37 "Condensation/Stores/SplitStore.pm"
	# To avoid attacks on a single store, the hash is encrypted with a key known to the operator only
	my $encryptedBytes = CDS::C::aesCrypt(substr($hash->bytes, 0, 16), $o->{key}, $zeroCounter);

#line 40 "Condensation/Stores/SplitStore.pm"
	# Use the first byte as store index
	return ord(substr($encryptedBytes, 0, 1));
}

#line 44 "Condensation/Stores/SplitStore.pm"
### Store interface

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 47 "Condensation/Stores/SplitStore.pm"
	my $store = $o->objectStore($o->storeIndex($hash)) // return undef, 'No store assigned.';
	return $store->get($hash, $keyPair);
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 52 "Condensation/Stores/SplitStore.pm"
	my $store = $o->objectStore($o->storeIndex($hash)) // return undef, 'No store assigned.';
	return $store->put($hash, $object, $keyPair);
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 57 "Condensation/Stores/SplitStore.pm"
	my $store = $o->objectStore($o->storeIndex($hash)) // return undef, 'No store assigned.';
	return $store->book($hash, $keyPair);
}

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 62 "Condensation/Stores/SplitStore.pm"
	my $store = $o->accountStore($o->storeIndex($accountHash)) // return undef, 'No store assigned.';
	return $store->list($accountHash, $boxLabel, $timeout, $keyPair);
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 67 "Condensation/Stores/SplitStore.pm"
	my $store = $o->accountStore($o->storeIndex($accountHash)) // return 'No store assigned.';
	return $store->add($accountHash, $boxLabel, $hash, $keyPair);
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 72 "Condensation/Stores/SplitStore.pm"
	my $store = $o->accountStore($o->storeIndex($accountHash)) // return 'No store assigned.';
	return $store->remove($accountHash, $boxLabel, $hash, $keyPair);
}

sub modify {
	my $o = shift;
	my $modifications = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 77 "Condensation/Stores/SplitStore.pm"
	# Put objects
	my %objectsByStoreId;
	for my $entry (values %{$modifications->objects}) {
		my $store = $o->objectStore($o->storeIndex($entry->{hash}));
		my $target = $objectsByStoreId{$store->id};
		$objectsByStoreId{$store->id} = $target = {store => $store, modifications => CDS::StoreModifications->new};
		$target->modifications->put($entry->{hash}, $entry->{object});
	}

#line 86 "Condensation/Stores/SplitStore.pm"
	for my $item (values %objectsByStoreId) {
		my $error = $item->{store}->modify($item->{modifications}, $keyPair);
		return $error if $error;
	}

#line 91 "Condensation/Stores/SplitStore.pm"
	# Add box entries
	my %additionsByStoreId;
	for my $operation (@{$modifications->additions}) {
		my $store = $o->accountStore($o->storeIndex($operation->{accountHash}));
		my $target = $additionsByStoreId{$store->id};
		$additionsByStoreId{$store->id} = $target = {store => $store, modifications => CDS::StoreModifications->new};
		$target->modifications->add($operation->{accountHash}, $operation->{boxLabel}, $operation->{hash});
	}

#line 100 "Condensation/Stores/SplitStore.pm"
	for my $item (values %additionsByStoreId) {
		my $error = $item->{store}->modify($item->{modifications}, $keyPair);
		return $error if $error;
	}

#line 105 "Condensation/Stores/SplitStore.pm"
	# Remove box entries (but ignore errors)
	my %removalsByStoreId;
	for my $operation (@$modifications->removals) {
		my $store = $o->accountStore($o->storeIndex($operation->{accountHash}));
		my $target = $removalsByStoreId{$store->id};
		$removalsByStoreId{$store->id} = $target = {store => $store, modifications => CDS::StoreModifications->new};
		$target->modifications->add($operation->{accountHash}, $operation->{boxLabel}, $operation->{hash});
	}

#line 114 "Condensation/Stores/SplitStore.pm"
	for my $item (values %removalsByStoreId) {
		$item->{store}->modify($item->{modifications}, $keyPair);
	}

#line 118 "Condensation/Stores/SplitStore.pm"
	return;
}

# General
# sub id($o)				# () => String
package CDS::Store;

#line 4 "Condensation/Stores/Store.pm"
# Object store functions
# sub get($o, $hash, $keyPair)				# Hash, KeyPair? => Object?, String?
# sub put($o, $hash, $object, $keyPair)		# Hash, Object, KeyPair? => String?
# sub book($o, $hash, $keyPair)				# Hash, KeyPair? => 1?, String?

#line 9 "Condensation/Stores/Store.pm"
# Account store functions
# sub list($o, $accountHash, $boxLabel, $timeout, $keyPair)		# Hash, String, Duration, KeyPair? => @$Hash, String?
# sub add($o, $accountHash, $boxLabel, $hash, $keyPair)			# Hash, String, Hash, KeyPair? => String?
# sub remove($o, $accountHash, $boxLabel, $hash, $keyPair)		# Hash, String, Hash, KeyPair? => String?
# sub modify($o, $storeModifications, $keyPair)					# StoreModifications, KeyPair? => String?

package CDS::StoreModifications;

sub new {
	my $class = shift;

#line 2 "Condensation/Stores/StoreModifications.pm"
	return bless {
		objects => {},
		additions => [],
		removals => [],
		};
}

#line 9 "Condensation/Stores/StoreModifications.pm"
sub objects { shift->{objects} }
sub additions { shift->{additions} }
sub removals { shift->{removals} }

sub isEmpty {
	my $o = shift;

#line 14 "Condensation/Stores/StoreModifications.pm"
	return if scalar keys %{$o->{objects}};
	return if scalar @{$o->{additions}};
	return if scalar @{$o->{removals}};
	return 1;
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

#line 21 "Condensation/Stores/StoreModifications.pm"
	$o->{objects}->{$hash->bytes} = {hash => $hash, object => $object};
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';

#line 25 "Condensation/Stores/StoreModifications.pm"
	$o->put($hash, $object) if $object;
	push @{$o->{additions}}, {accountHash => $accountHash, boxLabel => $boxLabel, hash => $hash};
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';

#line 30 "Condensation/Stores/StoreModifications.pm"
	push @{$o->{removals}}, {accountHash => $accountHash, boxLabel => $boxLabel, hash => $hash};
}

sub executeIndividually {
	my $o = shift;
	my $store = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 34 "Condensation/Stores/StoreModifications.pm"
	# Process objects
	for my $entry (values %{$o->{objects}}) {
		my $error = $store->put($entry->{hash}, $entry->{object}, $keyPair);
		return $error if $error;
	}

#line 40 "Condensation/Stores/StoreModifications.pm"
	# Process additions
	for my $entry (@{$o->{additions}}) {
		my $error = $store->add($entry->{accountHash}, $entry->{boxLabel}, $entry->{hash}, $keyPair);
		return $error if $error;
	}

#line 46 "Condensation/Stores/StoreModifications.pm"
	# Process removals (and ignore errors)
	for my $entry (@{$o->{removals}}) {
		$store->remove($entry->{accountHash}, $entry->{boxLabel}, $entry->{hash}, $keyPair);
	}

#line 51 "Condensation/Stores/StoreModifications.pm"
	return;
}

#line 54 "Condensation/Stores/StoreModifications.pm"
# Returns a text representation of box additions and removals.
sub toRecord {
	my $o = shift;

#line 56 "Condensation/Stores/StoreModifications.pm"
	my $record = CDS::Record->new;

#line 58 "Condensation/Stores/StoreModifications.pm"
	# Objects
	my $objectsRecord = $record->add('puts');
	for my $entry (values %{$o->{objects}}) {
		$objectsRecord->add($entry->{hash}->bytes)->add($entry->{object}->bytes);
	}

#line 64 "Condensation/Stores/StoreModifications.pm"
	# Box additions and removals
	&addEntriesToRecord($o->{additions}, $record->add('add'));
	&addEntriesToRecord($o->{removals}, $record->add('remove'));

#line 68 "Condensation/Stores/StoreModifications.pm"
	return $record;
}

sub addEntriesToRecord {
	my $unsortedEntries = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
		# private
#line 72 "Condensation/Stores/StoreModifications.pm"
	my @additions = sort { ($a->{accountHash}->bytes cmp $b->{accountHash}->bytes) || ($a->{boxLabel} cmp $b->{boxLabel}) } @$unsortedEntries;
	my $entry = shift @additions;
	while (defined $entry) {
		my $accountHash = $entry->{accountHash};
		my $accountRecord = $record->add($accountHash->bytes);

#line 78 "Condensation/Stores/StoreModifications.pm"
		while (defined $entry && $entry->{accountHash}->bytes eq $accountHash->bytes) {
			my $boxLabel = $entry->{boxLabel};
			my $boxRecord = $accountRecord->add($boxLabel);

#line 82 "Condensation/Stores/StoreModifications.pm"
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

#line 91 "Condensation/Stores/StoreModifications.pm"
	my $object = CDS::Object->fromBytes($bytes) // return;
	my $record = CDS::Record->fromObject($object) // return;
	return $class->fromRecord($record);
}

sub fromRecord {
	my $class = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 97 "Condensation/Stores/StoreModifications.pm"
	my $modifications = $class->new;

#line 99 "Condensation/Stores/StoreModifications.pm"
	# Read objects (and "envelopes" entries used before 2022-01)
	for my $objectRecord ($record->child('put')->children, $record->child('envelopes')->children) {
		my $hash = CDS::Hash->fromBytes($objectRecord->bytes) // return;
		my $object = CDS::Object->fromBytes($objectRecord->firstChild->bytes) // return;
		#return if $o->{checkEnvelopeHash} && ! $object->calculateHash->equals($hash);
		$modifications->put($hash, $object);
	}

#line 107 "Condensation/Stores/StoreModifications.pm"
	# Read additions and removals
	readEntriesFromRecord($modifications->{addition}, $record->child('add')) // return;
	readEntriesFromRecord($modifications->{removal}, $record->child('remove')) // return;

#line 111 "Condensation/Stores/StoreModifications.pm"
	return $modifications;
}

sub readEntriesFromRecord {
	my $entries = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
		# private
#line 115 "Condensation/Stores/StoreModifications.pm"
	for my $accountHashRecord ($record->children) {
		my $accountHash = CDS::Hash->fromBytes($accountHashRecord->bytes) // return;
		for my $boxLabelRecord ($accountHashRecord->children) {
			my $boxLabel = $boxLabelRecord->bytes;
			return if ! CDS->isValidBoxLabel($boxLabel);

#line 121 "Condensation/Stores/StoreModifications.pm"
			for my $hashRecord ($boxLabelRecord->children) {
				my $hash = CDS::Hash->fromBytes($hashRecord->bytes) // return;
				push @$entries, {accountHash => $accountHash, boxLabel => $boxLabel, hash => $hash};
			}
		}
	}

#line 128 "Condensation/Stores/StoreModifications.pm"
	return 1;
}

package CDS::StreamCache;

sub new {
	my $class = shift;
	my $pool = shift;
	my $actorOnStore = shift; die 'wrong type '.ref($actorOnStore).' for $actorOnStore' if defined $actorOnStore && ref $actorOnStore ne 'CDS::ActorOnStore';
	my $timeout = shift;

#line 2 "Condensation/Actors/StreamCache.pm"
	return bless {
		pool => $pool,
		actorOnStore => $actorOnStore,
		timeout => $timeout,
		cache => {},
		};
}

#line 10 "Condensation/Actors/StreamCache.pm"
sub messageBoxReader { shift->{messageBoxReader} }

sub removeObsolete {
	my $o = shift;

#line 13 "Condensation/Actors/StreamCache.pm"
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

#line 22 "Condensation/Actors/StreamCache.pm"
	my $streamHead = $o->{knownStreamHeads}->{$head->hex};
	if ($streamHead) {
		$streamHead->stillInUse;
		return $streamHead;
	}

#line 28 "Condensation/Actors/StreamCache.pm"
	# Retrieve the head envelope
	my ($object, $getError) = $o->{actorOnStore}->store->get($head, $o->{pool}->{keyPair});
	return if defined $getError;

#line 32 "Condensation/Actors/StreamCache.pm"
	# Parse the head envelope
	my $envelope = CDS::Record->fromObject($object);
	return $o->invalid($head, 'Not a record.') if ! $envelope;

#line 36 "Condensation/Actors/StreamCache.pm"
	# Read the embedded content object
	my $encryptedBytes = $envelope->child('content')->bytesValue;
	return $o->invalid($head, 'Missing content object.') if ! length $encryptedBytes;

#line 40 "Condensation/Actors/StreamCache.pm"
	# Decrypt the key
	my $aesKey = $o->{pool}->{keyPair}->decryptKeyOnEnvelope($envelope);
	return $o->invalid($head, 'Not encrypted for us.') if ! $aesKey;

#line 44 "Condensation/Actors/StreamCache.pm"
	# Decrypt the content
	my $contentObject = CDS::Object->fromBytes(CDS::C::aesCrypt($encryptedBytes, $aesKey, CDS->zeroCTR));
	return $o->invalid($head, 'Invalid content object.') if ! $contentObject;

#line 48 "Condensation/Actors/StreamCache.pm"
	my $content = CDS::Record->fromObject($contentObject);
	return $o->invalid($head, 'Content object is not a record.') if ! $content;

#line 51 "Condensation/Actors/StreamCache.pm"
	# Verify the sender hash
	my $senderHash = $content->child('sender')->hashValue;
	return $o->invalid($head, 'Missing sender hash.') if ! $senderHash;

#line 55 "Condensation/Actors/StreamCache.pm"
	# Verify the sender store
	my $storeRecord = $content->child('store');
	return $o->invalid($head, 'Missing sender store.') if ! scalar $storeRecord->children;

#line 59 "Condensation/Actors/StreamCache.pm"
	my $senderStoreUrl = $storeRecord->textValue;
	my $senderStore = $o->{pool}->{delegate}->onMessageBoxVerifyStore($senderStoreUrl, $head, $envelope, $senderHash);
	return $o->invalid($head, 'Invalid sender store.') if ! $senderStore;

#line 63 "Condensation/Actors/StreamCache.pm"
	# Retrieve the sender's public key
	my ($senderPublicKey, $invalidReason, $publicKeyStoreError) = $o->getPublicKey($senderHash, $senderStore);
	return if defined $publicKeyStoreError;
	return $o->invalid($head, 'Failed to retrieve the sender\'s public key: '.$invalidReason) if defined $invalidReason;

#line 68 "Condensation/Actors/StreamCache.pm"
	# Verify the signature
	my $signedHash = CDS::Hash->calculateFor($encryptedBytes);
	return $o->invalid($head, 'Invalid signature.') if ! CDS->verifyEnvelopeSignature($envelope, $senderPublicKey, $signedHash);

#line 72 "Condensation/Actors/StreamCache.pm"
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
#line 80 "Condensation/Actors/StreamCache.pm"
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

#line 2 "Condensation/Actors/StreamHead.pm"
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

#line 13 "Condensation/Actors/StreamHead.pm"
sub hash { shift->{hash} }
sub envelope { shift->{envelope} }
sub senderStoreUrl { shift->{senderStoreUrl} }
sub sender { shift->{sender} }
sub content { shift->{content} }
sub error { shift->{error} }
sub isValid {
	my $o = shift;
	 ! defined $o->{error} }
#line 20 "Condensation/Actors/StreamHead.pm"
sub lastUsed { shift->{lastUsed} }

sub stillInUse {
	my $o = shift;

#line 23 "Condensation/Actors/StreamHead.pm"
	$o->{lastUsed} = CDS->now;
}

package CDS::SubDataTree;

use parent -norequire, 'CDS::DataTree';

sub new {
	my $class = shift;
	my $parentSelector = shift; die 'wrong type '.ref($parentSelector).' for $parentSelector' if defined $parentSelector && ref $parentSelector ne 'CDS::Selector';

#line 4 "Condensation/DataTree/SubDataTree.pm"
	my $o = $class->SUPER::new($parentSelector->dataTree->keyPair, $parentSelector->dataTree->unsaved);
	$o->{parentSelector} = $parentSelector;
	return $o;
}

#line 9 "Condensation/DataTree/SubDataTree.pm"
sub parentSelector { shift->{parentSelector} }

sub partSelector {
	my $o = shift;
	my $hashAndKey = shift; die 'wrong type '.ref($hashAndKey).' for $hashAndKey' if defined $hashAndKey && ref $hashAndKey ne 'CDS::HashAndKey';

#line 12 "Condensation/DataTree/SubDataTree.pm"
	$o->{parentSelector}->child(substr($hashAndKey->hash->bytes, 0, 16));
}

sub read {
	my $o = shift;

#line 16 "Condensation/DataTree/SubDataTree.pm"
	$o->merge(map { $_->hashAndKeyValue } $o->{parentSelector}->children);
	return $o->SUPER::read;
}

sub savingDone {
	my $o = shift;
	my $revision = shift;
	my $newPart = shift;
	my $obsoleteParts = shift;

#line 21 "Condensation/DataTree/SubDataTree.pm"
	$o->{parentSelector}->dataTree->unsaved->state->merge($o->{unsaved}->savingState);

#line 23 "Condensation/DataTree/SubDataTree.pm"
	# Remove obsolete parts
	for my $part (@$obsoleteParts) {
		$o->partSelector($part->{hashAndKey})->merge($revision, CDS::Record->new);
	}

#line 28 "Condensation/DataTree/SubDataTree.pm"
	# Add the new part
	if ($newPart) {
		my $record = CDS::Record->new;
		$record->addHashAndKey($newPart->{hashAndKey});
		$o->partSelector($newPart->{hashAndKey})->merge($revision, $record);
	}

#line 35 "Condensation/DataTree/SubDataTree.pm"
	$o->{unsaved}->savingDone;
}

# Useful functions to display textual information on the terminal
package CDS::UI;

sub new {
	my $class = shift;
	my $fileHandle = shift // *STDOUT;
	my $pure = shift;

#line 8 "Condensation/CLI/UI.pm"
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

#line 21 "Condensation/CLI/UI.pm"
sub fileHandle { shift->{fileHandle} }

#line 23 "Condensation/CLI/UI.pm"
### Indent

sub pushIndent {
	my $o = shift;

#line 26 "Condensation/CLI/UI.pm"
	$o->{indentCount} += 1;
	$o->{indent} = '  ' x $o->{indentCount};
	return;
}

sub popIndent {
	my $o = shift;

#line 32 "Condensation/CLI/UI.pm"
	$o->{indentCount} -= 1;
	$o->{indent} = '  ' x $o->{indentCount};
	return;
}

sub valueIndent {
	my $o = shift;
	my $width = shift;

#line 38 "Condensation/CLI/UI.pm"
	$o->{valueIndent} = $width;
}

#line 41 "Condensation/CLI/UI.pm"
### Low-level (non-semantic) output

sub print {
	my $o = shift;

#line 44 "Condensation/CLI/UI.pm"
	my $fh = $o->{fileHandle} // return;
	print $fh @_;
}

sub raw {
	my $o = shift;

#line 49 "Condensation/CLI/UI.pm"
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

#line 59 "Condensation/CLI/UI.pm"
	$o->removeProgress;
	return if $o->{hasSpace};
	$o->{hasSpace} = 1;
	$o->print("\n");
	return;
}

#line 66 "Condensation/CLI/UI.pm"
# A line of text (without word-wrap).
sub line {
	my $o = shift;

#line 68 "Condensation/CLI/UI.pm"
	$o->removeProgress;
	my $span = CDS::UI::Span->new(@_);
	$o->print($o->{indent});
	$span->printTo($o);
	$o->print(chr(0x1b), '[0m', "\n");
	$o->{hasSpace} = 0;
	return;
}

#line 77 "Condensation/CLI/UI.pm"
# A line of word-wrapped text.
sub p {
	my $o = shift;

#line 79 "Condensation/CLI/UI.pm"
	$o->removeProgress;
	my $span = CDS::UI::Span->new(@_);
	$span->wordWrap({lineLength => 0, maxLength => 100 - length $o->{indent}, indent => $o->{indent}});
	$o->print($o->{indent});
	$span->printTo($o);
	$o->print(chr(0x1b), '[0m', "\n");
	$o->{hasSpace} = 0;
	return;
}

#line 89 "Condensation/CLI/UI.pm"
# Line showing the progress.
sub progress {
	my $o = shift;

#line 91 "Condensation/CLI/UI.pm"
	return if $o->{pure};
	$| = 1;
	$o->{hasProgress} = 1;
	my $text = '  '.join('', @_);
	$text = substr($text, 0, 79).'…' if length $text > 80;
	$text .= ' ' x (80 - length $text) if length $text < 80;
	$o->print($text, "\r");
}

#line 100 "Condensation/CLI/UI.pm"
# Progress line removal.
sub removeProgress {
	my $o = shift;

#line 102 "Condensation/CLI/UI.pm"
	return if $o->{pure};
	return if ! $o->{hasProgress};
	$o->print(' ' x 80, "\r");
	$o->{hasProgress} = 0;
	$| = 0;
}

#line 109 "Condensation/CLI/UI.pm"
### Low-level (non-semantic) formatting

sub span {
	my $o = shift;
	 CDS::UI::Span->new(@_) }

sub bold {
	my $o = shift;

#line 114 "Condensation/CLI/UI.pm"
	my $span = CDS::UI::Span->new(@_);
	$span->{bold} = 1;
	return $span;
}

sub underlined {
	my $o = shift;

#line 120 "Condensation/CLI/UI.pm"
	my $span = CDS::UI::Span->new(@_);
	$span->{underlined} = 1;
	return $span;
}

sub foreground {
	my $o = shift;
	my $foreground = shift;

#line 126 "Condensation/CLI/UI.pm"
	my $span = CDS::UI::Span->new(@_);
	$span->{foreground} = $foreground;
	return $span;
}

sub background {
	my $o = shift;
	my $background = shift;

#line 132 "Condensation/CLI/UI.pm"
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

#line 146 "Condensation/CLI/UI.pm"
	my $span = CDS::UI::Span->new(@_);
	$span->{bold} = 1;
	$span->{foreground} = 240;
	return $span;
}

#line 152 "Condensation/CLI/UI.pm"
### Semantic output

sub title {
	my $o = shift;
	 $o->line($o->bold(@_)) }

sub left {
	my $o = shift;
	my $width = shift;
	my $text = shift;

#line 157 "Condensation/CLI/UI.pm"
	return substr($text, 0, $width - 1).'…' if length $text > $width;
	return $text . ' ' x ($width - length $text);
}

sub right {
	my $o = shift;
	my $width = shift;
	my $text = shift;

#line 162 "Condensation/CLI/UI.pm"
	return substr($text, 0, $width - 1).'…' if length $text > $width;
	return ' ' x ($width - length $text) . $text;
}

sub keyValue {
	my $o = shift;
	my $key = shift;
	my $firstLine = shift;

#line 167 "Condensation/CLI/UI.pm"
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

#line 181 "Condensation/CLI/UI.pm"
	$o->p($o->green(@_));
	return;
}

sub pOrange {
	my $o = shift;

#line 186 "Condensation/CLI/UI.pm"
	$o->p($o->orange(@_));
	return;
}

sub pRed {
	my $o = shift;

#line 191 "Condensation/CLI/UI.pm"
	$o->p($o->red(@_));
	return;
}

#line 195 "Condensation/CLI/UI.pm"
### Warnings and errors

#line 197 "Condensation/CLI/UI.pm"
sub hasWarning { shift->{hasWarning} }
sub hasError { shift->{hasError} }

sub warning {
	my $o = shift;

#line 201 "Condensation/CLI/UI.pm"
	$o->{hasWarning} = 1;
	$o->p($o->orange(@_));
	return;
}

sub error {
	my $o = shift;

#line 207 "Condensation/CLI/UI.pm"
	$o->{hasError} = 1;
	my $span = CDS::UI::Span->new(@_);
	$span->{background} = 196;
	$span->{foreground} = 15;
	$span->{bold} = 1;
	$o->line($span);
	return;
}

#line 216 "Condensation/CLI/UI.pm"
### Semantic formatting

sub a {
	my $o = shift;
	 $o->underlined(@_) }

#line 220 "Condensation/CLI/UI.pm"
### Human readable formats

sub niceBytes {
	my $o = shift;
	my $bytes = shift;
	my $maxLength = shift;

#line 223 "Condensation/CLI/UI.pm"
	my $length = length $bytes;
	my $text = defined $maxLength && $length > $maxLength ? substr($bytes, 0, $maxLength - 1).'…' : $bytes;
	$text =~ s/[\x00-\x1f\x7f-\xff]/./g;
	return $text;
}

sub niceFileSize {
	my $o = shift;
	my $fileSize = shift;

#line 230 "Condensation/CLI/UI.pm"
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

#line 240 "Condensation/CLI/UI.pm"
	my @t = localtime($time / 1000);
	return sprintf('%04d-%02d-%02d %02d:%02d:%02d', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

sub niceDateTime {
	my $o = shift;
	my $time = shift // time() * 1000;

#line 245 "Condensation/CLI/UI.pm"
	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02d %02d:%02d:%02d UTC', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

sub niceDate {
	my $o = shift;
	my $time = shift // time() * 1000;

#line 250 "Condensation/CLI/UI.pm"
	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3]);
}

sub niceTime {
	my $o = shift;
	my $time = shift // time() * 1000;

#line 255 "Condensation/CLI/UI.pm"
	my @t = gmtime($time / 1000);
	return sprintf('%02d:%02d:%02d UTC', $t[2], $t[1], $t[0]);
}

#line 259 "Condensation/CLI/UI.pm"
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

#line 264 "Condensation/CLI/UI.pm"
	for my $child ($record->children) {
		CDS::UI::Record->display($o, $child, $storeUrl);
	}
}

sub selector {
	my $o = shift;
	my $selector = shift; die 'wrong type '.ref($selector).' for $selector' if defined $selector && ref $selector ne 'CDS::Selector';
	my $rootLabel = shift;

#line 270 "Condensation/CLI/UI.pm"
	my $item = $selector->dataTree->get($selector);
	my $revision = $item->{revision} ? $o->green('  ', $o->niceDateTime($item->{revision})) : '';

#line 273 "Condensation/CLI/UI.pm"
	if ($selector->{id} eq 'ROOT') {
		$o->line($o->bold($rootLabel // 'Data tree'), $revision);
		$o->recordChildren($selector->record);
		$o->selectorChildren($selector);
	} else {
		my $label = $selector->label;
		my $labelText = length $label > 64 ? substr($label, 0, 64).'…' : $label;
		$labelText =~ s/[\x00-\x1f\x7f-\xff]/·/g;
		$o->line($o->blue($labelText), $revision);

#line 283 "Condensation/CLI/UI.pm"
		$o->pushIndent;
		$o->recordChildren($selector->record);
		$o->selectorChildren($selector);
		$o->popIndent;
	}
}

sub selectorChildren {
	my $o = shift;
	my $selector = shift; die 'wrong type '.ref($selector).' for $selector' if defined $selector && ref $selector ne 'CDS::Selector';

#line 291 "Condensation/CLI/UI.pm"
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

#line 2 "Condensation/CLI/UI/HexDump.pm"
	return bless {ui => $ui, bytes => $bytes, styleChanges => [], };
}

#line 5 "Condensation/CLI/UI/HexDump.pm"
sub reset { chr(0x1b).'[0m' }
sub foreground {
	my $o = shift;
	my $color = shift;
	 chr(0x1b).'[0;38;5;'.$color.'m' }

sub changeStyle {
	my $o = shift;

#line 9 "Condensation/CLI/UI/HexDump.pm"
	push @{$o->{styleChanges}}, @_;
}

sub styleHashList {
	my $o = shift;
	my $offset = shift;

#line 13 "Condensation/CLI/UI/HexDump.pm"
	my $hashesCount = unpack('L>', substr($o->{bytes}, $offset, 4));
	my $dataStart = $offset + 4 + $hashesCount  * 32;
	return $offset if $dataStart > length $o->{bytes};

#line 17 "Condensation/CLI/UI/HexDump.pm"
	# Styles
	my $darkGreen = $o->foreground(28);
	my $green0 = $o->foreground(40);
	my $green1 = $o->foreground(34);

#line 22 "Condensation/CLI/UI/HexDump.pm"
	# Color the hash count
	my $pos = $offset;
	$o->changeStyle({at => $pos, style => $darkGreen, breakBefore => 1});
	$pos += 4;

#line 27 "Condensation/CLI/UI/HexDump.pm"
	# Color the hashes
	my $alternate = 0;
	while ($hashesCount) {
		$o->changeStyle({at => $pos, style => $alternate ? $green1 : $green0, breakBefore => 1});
		$pos += 32;
		$alternate = 1 - $alternate;
		$hashesCount -= 1;
	}

#line 36 "Condensation/CLI/UI/HexDump.pm"
	return $dataStart;
}

sub styleRecord {
	my $o = shift;
	my $offset = shift;

#line 40 "Condensation/CLI/UI/HexDump.pm"
	# Styles
	my $blue = $o->foreground(33);
	my $black = $o->reset;
	my $violet = $o->foreground(93);
	my @styleChanges;

#line 46 "Condensation/CLI/UI/HexDump.pm"
	# Prepare
	my $pos = $offset;
	my $hasError = 0;
	my $level = 0;

#line 51 "Condensation/CLI/UI/HexDump.pm"
	my $use = sub { my $length = shift;
		my $start = $pos;
		$pos += $length;
		return substr($o->{bytes}, $start, $length) if $pos <= length $o->{bytes};
		$hasError = 1;
		return;
	};

#line 59 "Condensation/CLI/UI/HexDump.pm"
	my $readUnsigned8 = sub { unpack('C', &$use(1) // return) };
	my $readUnsigned32 = sub { unpack('L>', &$use(4) // return) };
	my $readUnsigned64 = sub { unpack('Q>', &$use(8) // return) };

#line 63 "Condensation/CLI/UI/HexDump.pm"
	# Parse all record nodes
	while ($level >= 0) {
		# Flags
		push @styleChanges, {at => $pos, style => $blue, breakBefore => 1};
		my $flags = &$readUnsigned8 // last;

#line 69 "Condensation/CLI/UI/HexDump.pm"
		# Data
		my $length = $flags & 0x1f;
		my $byteLength = $length == 30 ? 30 + (&$readUnsigned8 // last) : $length == 31 ? (&$readUnsigned64 // last) : $length;

#line 73 "Condensation/CLI/UI/HexDump.pm"
		if ($byteLength) {
			push @styleChanges, {at => $pos, style => $black};
			&$use($byteLength) // last;
		}

#line 78 "Condensation/CLI/UI/HexDump.pm"
		if ($flags & 0x20) {
			push @styleChanges, {at => $pos, style => $violet};
			&$readUnsigned32 // last;
		}

#line 83 "Condensation/CLI/UI/HexDump.pm"
		# Children
		$level += 1 if $flags & 0x40;
		$level -= 1 if ! ($flags & 0x80);
	}

#line 88 "Condensation/CLI/UI/HexDump.pm"
	# Don't apply any styles if there are errors
	$hasError = 1 if $pos != length $o->{bytes};
	return $offset if $hasError;

#line 92 "Condensation/CLI/UI/HexDump.pm"
	$o->changeStyle(@styleChanges);
	return $pos;
}

sub display {
	my $o = shift;

#line 97 "Condensation/CLI/UI/HexDump.pm"
	$o->{ui}->valueIndent(8);

#line 99 "Condensation/CLI/UI/HexDump.pm"
	my $resetStyle = chr(0x1b).'[0m';
	my $length = length($o->{bytes});
	my $lineStart = 0;
	my $currentStyle = '';

#line 104 "Condensation/CLI/UI/HexDump.pm"
	my @styleChanges = sort { $a->{at} <=> $b->{at} } @{$o->{styleChanges}};
	push @styleChanges, {at => $length};
	my $nextChange = shift(@styleChanges);

#line 108 "Condensation/CLI/UI/HexDump.pm"
	$o->{ui}->line($o->{ui}->gray('····   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f  0123456789abcdef'));
	while ($lineStart < $length) {
		my $hexLine = $currentStyle;
		my $textLine = $currentStyle;

#line 113 "Condensation/CLI/UI/HexDump.pm"
		my $k = 0;
		while ($k < 16) {
			my $index = $lineStart + $k;
			last if $index >= $length;

#line 118 "Condensation/CLI/UI/HexDump.pm"
			my $break = 0;
			while ($index >= $nextChange->{at}) {
				$currentStyle = $nextChange->{style};
				$break = $nextChange->{breakBefore} && $k > 0;
				$hexLine .= $currentStyle;
				$textLine .= $currentStyle;
				$nextChange = shift @styleChanges;
				last if $break;
			}

#line 128 "Condensation/CLI/UI/HexDump.pm"
			last if $break;

#line 130 "Condensation/CLI/UI/HexDump.pm"
			my $byte = substr($o->{bytes}, $lineStart + $k, 1);
			$hexLine .= ' '.unpack('H*', $byte);

#line 133 "Condensation/CLI/UI/HexDump.pm"
			my $code = ord($byte);
			$textLine .= $code >= 32 && $code <= 126 ? $byte : '·';

#line 136 "Condensation/CLI/UI/HexDump.pm"
			$k += 1;
		}

#line 139 "Condensation/CLI/UI/HexDump.pm"
		$hexLine .= '   ' x (16 - $k);
		$textLine .= ' ' x (16 - $k);
		$o->{ui}->line($o->{ui}->gray(unpack('H4', pack('S>', $lineStart))), ' ', $hexLine, $resetStyle, '  ', $textLine, $resetStyle);

#line 143 "Condensation/CLI/UI/HexDump.pm"
		$lineStart += $k;
	}
}

package CDS::UI::ProgressStore;

use parent -norequire, 'CDS::Store';

sub new {
	my $class = shift;
	my $store = shift;
	my $url = shift;
	my $ui = shift;

#line 4 "Condensation/CLI/UI/ProgressStore.pm"
	return bless {
		store => $store,
		url => $url,
		ui => $ui,
		}
}

#line 11 "Condensation/CLI/UI/ProgressStore.pm"
sub store { shift->{store} }
sub url { shift->{url} }
sub ui { shift->{ui} }

sub id {
	my $o = shift;
	 'Progress'."\n  ".$o->{store}->id }

#line 17 "Condensation/CLI/UI/ProgressStore.pm"
### Object store functions

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 20 "Condensation/CLI/UI/ProgressStore.pm"
	$o->{ui}->progress('GET ', $hash->shortHex, ' on ', $o->{url});
	return $o->{store}->get($hash, $keyPair);
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 25 "Condensation/CLI/UI/ProgressStore.pm"
	$o->{ui}->progress('BOOK ', $hash->shortHex, ' on ', $o->{url});
	return $o->{store}->book($hash, $keyPair);
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 30 "Condensation/CLI/UI/ProgressStore.pm"
	$o->{ui}->progress('PUT ', $hash->shortHex, ' (', $o->{ui}->niceFileSize($object->byteLength), ') on ', $o->{url});
	return $o->{store}->put($hash, $object, $keyPair);
}

#line 34 "Condensation/CLI/UI/ProgressStore.pm"
### Account store functions

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 37 "Condensation/CLI/UI/ProgressStore.pm"
	$o->{ui}->progress($timeout == 0 ? 'LIST ' : 'WATCH ', $boxLabel, ' of ', $accountHash->shortHex, ' on ', $o->{url});
	return $o->{store}->list($accountHash, $boxLabel, $timeout, $keyPair);
}

sub add {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 42 "Condensation/CLI/UI/ProgressStore.pm"
	$o->{ui}->progress('ADD ', $accountHash->shortHex, ' ', $boxLabel, ' ', $hash->shortHex, ' on ', $o->{url});
	return $o->{store}->add($accountHash, $boxLabel, $hash, $keyPair);
}

sub remove {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 47 "Condensation/CLI/UI/ProgressStore.pm"
	$o->{ui}->progress('REMOVE ', $accountHash->shortHex, ' ', $boxLabel, ' ', $hash->shortHex, ' on ', $o->{url});
	return $o->{store}->remove($accountHash, $boxLabel, $hash, $keyPair);
}

sub modify {
	my $o = shift;
	my $modifications = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 52 "Condensation/CLI/UI/ProgressStore.pm"
	$o->{ui}->progress('MODIFY +', scalar @{$modifications->additions}, ' -', scalar @{$modifications->removals}, ' on ', $o->{url});
	return $o->{store}->modify($modifications, $keyPair);
}

# Displays a record, and tries to guess the byte interpretation
package CDS::UI::Record;

sub display {
	my $class = shift;
	my $ui = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $storeUrl = shift;

#line 4 "Condensation/CLI/UI/Record.pm"
	my $o = bless {
		ui => $ui,
		onStore => defined $storeUrl ? $ui->gray(' on ', $storeUrl) : '',
		};

#line 9 "Condensation/CLI/UI/Record.pm"
	$o->record($record, '');
}

sub record {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $context = shift;

#line 13 "Condensation/CLI/UI/Record.pm"
	my $bytes = $record->bytes;
	my $hash = $record->hash;
	my @children = $record->children;

#line 17 "Condensation/CLI/UI/Record.pm"
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

#line 36 "Condensation/CLI/UI/Record.pm"
	push @value, ' ', $o->{ui}->blue($hash->hex), $o->{onStore} if $hash && ($bytes && length $bytes != 32);
	$o->{ui}->line(@value);

#line 39 "Condensation/CLI/UI/Record.pm"
	# Children
	$o->{ui}->pushIndent;
	for my $child (@children) { $o->record($child, $bytes); }
	$o->{ui}->popIndent;
}

sub hexValue {
	my $o = shift;
	my $bytes = shift;

#line 46 "Condensation/CLI/UI/Record.pm"
	my $length = length $bytes;
	return '#'.unpack('H*', substr($bytes, 0, $length)) if $length <= 64;
	return '#'.unpack('H*', substr($bytes, 0, 64)), '…', $o->{ui}->gray(' (', $length, ' bytes)');
}

sub guessValue {
	my $o = shift;
	my $bytes = shift;

#line 52 "Condensation/CLI/UI/Record.pm"
	my $length = length $bytes;
	my $text = $length > 64 ? substr($bytes, 0, 64).'…' : $bytes;
	$text =~ s/[\x00-\x1f\x7f-\xff]/·/g;
	my @value = ($text);

#line 57 "Condensation/CLI/UI/Record.pm"
	if ($length <= 8) {
		my $integer = CDS->integerFromBytes($bytes);
		push @value, $o->{ui}->gray(' = ', $integer, $o->looksLikeTimestamp($integer) ? ' = '.$o->{ui}->niceDateTime($integer).' = '.$o->{ui}->niceDateTimeLocal($integer) : '');
	}

#line 62 "Condensation/CLI/UI/Record.pm"
	push @value, $o->{ui}->gray(' = ', CDS::Hash->fromBytes($bytes)->hex) if $length == 32;
	push @value, $o->{ui}->gray(' (', length $bytes, ' bytes)') if length $bytes > 64;
	return @value;
}

sub dateValue {
	my $o = shift;
	my $bytes = shift;

#line 68 "Condensation/CLI/UI/Record.pm"
	my $integer = CDS->integerFromBytes($bytes);
	return $integer if ! $o->looksLikeTimestamp($integer);
	return $o->{ui}->niceDateTime($integer), '  ', $o->{ui}->gray($o->{ui}->niceDateTimeLocal($integer));
}

sub revisionValue {
	my $o = shift;
	my $bytes = shift;

#line 74 "Condensation/CLI/UI/Record.pm"
	my $integer = CDS->integerFromBytes($bytes);
	return $integer if ! $o->looksLikeTimestamp($integer);
	return $o->{ui}->niceDateTime($integer);
}

sub looksLikeTimestamp {
	my $o = shift;
	my $integer = shift;

#line 80 "Condensation/CLI/UI/Record.pm"
	return $integer > 100000000000 && $integer < 10000000000000;
}

package CDS::UI::Span;

sub new {
	my $class = shift;

#line 2 "Condensation/CLI/UI/Span.pm"
	return bless {
		text => [@_],
		};
}

sub printTo {
	my $o = shift;
	my $ui = shift;
	my $parent = shift;

#line 8 "Condensation/CLI/UI/Span.pm"
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

#line 20 "Condensation/CLI/UI/Span.pm"
	my $style = chr(0x1b).'[0';
	$style .= ';1' if $o->{appliedBold};
	$style .= ';4' if $o->{appliedUnderlined};
	$style .= ';38;5;'.$o->{appliedForeground} if defined $o->{appliedForeground};
	$style .= ';48;5;'.$o->{appliedBackground} if defined $o->{appliedBackground};
	$style .= 'm';

#line 27 "Condensation/CLI/UI/Span.pm"
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

#line 42 "Condensation/CLI/UI/Span.pm"
		if ($needStyle) {
			$ui->print($style);
			$needStyle = 0;
		}

#line 47 "Condensation/CLI/UI/Span.pm"
		$ui->print($child);
	}
}

sub wordWrap {
	my $o = shift;
	my $state = shift;

#line 52 "Condensation/CLI/UI/Span.pm"
	my $index = -1;
	for my $child (@{$o->{text}}) {
		$index += 1;

#line 56 "Condensation/CLI/UI/Span.pm"
		next if ! defined $child;

#line 58 "Condensation/CLI/UI/Span.pm"
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

#line 70 "Condensation/CLI/UI/Span.pm"
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

#line 5 "Condensation/UnionList/UnionList.pm"
	my $o = bless {
		privateRoot => $privateRoot,
		label => $label,
		unsaved => CDS::Unsaved->new($privateRoot->unsaved),
		items => {},
		parts => {},
		hasPartsToMerge => 0,
		}, $class;

#line 14 "Condensation/UnionList/UnionList.pm"
	$o->{unused} = CDS::UnionList::Part->new;
	$o->{changes} = CDS::UnionList::Part->new;
	$privateRoot->addDataHandler($label, $o);
	return $o;
}

#line 20 "Condensation/UnionList/UnionList.pm"
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

#line 28 "Condensation/UnionList/UnionList.pm"
	my $item = $o->{items}->{$id};
	return $item if $item;
	my $newItem = $o->createItem($id);
	$o->{items}->{$id} = $newItem;
	return $newItem;
}

#line 35 "Condensation/UnionList/UnionList.pm"
# abstract sub createItem($o, $id)
# abstract sub forgetObsoleteItems($o)

sub forget {
	my $o = shift;
	my $id = shift;

#line 39 "Condensation/UnionList/UnionList.pm"
	my $item = $o->{items}->{$id} // return;
	$item->{part}->{count} -= 1;
	delete $o->{items}->{$id};
}

sub forgetItem {
	my $o = shift;
	my $item = shift;

#line 45 "Condensation/UnionList/UnionList.pm"
	$item->{part}->{count} -= 1;
	delete $o->{items}->{$item->id};
}

#line 49 "Condensation/UnionList/UnionList.pm"
# *** MergeableData interface

sub addDataTo {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 52 "Condensation/UnionList/UnionList.pm"
	for my $part (sort { $a->{hashAndKey}->hash->bytes cmp $b->{hashAndKey}->hash->bytes } values %{$o->{parts}}) {
		$record->addHashAndKey($part->{hashAndKey});
	}
}

sub mergeData {
	my $o = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';

#line 58 "Condensation/UnionList/UnionList.pm"
	my @hashesAndKeys;
	for my $child ($record->children) {
		push @hashesAndKeys, $child->asHashAndKey // next;
	}

#line 63 "Condensation/UnionList/UnionList.pm"
	$o->merge(@hashesAndKeys);
}

sub mergeExternalData {
	my $o = shift;
	my $store = shift;
	my $record = shift; die 'wrong type '.ref($record).' for $record' if defined $record && ref $record ne 'CDS::Record';
	my $source = shift; die 'wrong type '.ref($source).' for $source' if defined $source && ref $source ne 'CDS::Source';

#line 67 "Condensation/UnionList/UnionList.pm"
	my @hashes;
	my @hashesAndKeys;
	for my $child ($record->children) {
		my $hashAndKey = $child->asHashAndKey // next;
		next if $o->{parts}->{$hashAndKey->hash->bytes};
		push @hashes, $hashAndKey->hash;
		push @hashesAndKeys, $hashAndKey;
	}

#line 76 "Condensation/UnionList/UnionList.pm"
	my $keyPair = $o->{privateRoot}->privateBoxReader->keyPair;
	my ($missing, $transferStore, $storeError) = $keyPair->transfer([@hashes], $store, $o->{privateRoot}->unsaved);
	return if defined $storeError;
	return if $missing;

#line 81 "Condensation/UnionList/UnionList.pm"
	if ($source) {
		$source->keep;
		$o->{privateRoot}->unsaved->state->addMergedSource($source);
	}

#line 86 "Condensation/UnionList/UnionList.pm"
	$o->merge(@hashesAndKeys);
	return 1;
}

sub merge {
	my $o = shift;

#line 91 "Condensation/UnionList/UnionList.pm"
	for my $hashAndKey (@_) {
		next if ! $hashAndKey;
		next if $o->{parts}->{$hashAndKey->hash->bytes};
		my $part = CDS::UnionList::Part->new;
		$part->{hashAndKey} = $hashAndKey;
		$o->{parts}->{$hashAndKey->hash->bytes} = $part;
		$o->{hasPartsToMerge} = 1;
	}
}

#line 101 "Condensation/UnionList/UnionList.pm"
# *** Reading

sub read {
	my $o = shift;

#line 104 "Condensation/UnionList/UnionList.pm"
	return 1 if ! $o->{hasPartsToMerge};

#line 106 "Condensation/UnionList/UnionList.pm"
	# Load the parts
	for my $part (values %{$o->{parts}}) {
		next if $part->{isMerged};
		next if $part->{loadedRecord};

#line 111 "Condensation/UnionList/UnionList.pm"
		my ($record, $object, $invalidReason, $storeError) = $o->{privateRoot}->privateBoxReader->keyPair->getAndDecryptRecord($part->{hashAndKey}, $o->{privateRoot}->unsaved);
		return if defined $storeError;

#line 114 "Condensation/UnionList/UnionList.pm"
		delete $o->{parts}->{$part->{hashAndKey}->hash->bytes} if defined $invalidReason;
		$part->{loadedRecord} = $record;
	}

#line 118 "Condensation/UnionList/UnionList.pm"
	# Merge the loaded parts
	for my $part (values %{$o->{parts}}) {
		next if $part->{isMerged};
		next if ! $part->{loadedRecord};

#line 123 "Condensation/UnionList/UnionList.pm"
		# Merge
		for my $child ($part->{loadedRecord}->children) {
			$o->mergeRecord($part, $child);
		}

#line 128 "Condensation/UnionList/UnionList.pm"
		delete $part->{loadedRecord};
		$part->{isMerged} = 1;
	}

#line 132 "Condensation/UnionList/UnionList.pm"
	$o->{hasPartsToMerge} = 0;
	return 1;
}

#line 136 "Condensation/UnionList/UnionList.pm"
# abstract sub mergeRecord($o, $part, $record)

#line 138 "Condensation/UnionList/UnionList.pm"
# *** Saving

sub hasChanges {
	my $o = shift;
	 $o->{changes}->{count} > 0 }

sub save {
	my $o = shift;

#line 143 "Condensation/UnionList/UnionList.pm"
	$o->forgetObsoleteItems;
	$o->{unsaved}->startSaving;

#line 146 "Condensation/UnionList/UnionList.pm"
	if ($o->{changes}->{count}) {
		# Take the changes
		my $newPart = $o->{changes};
		$o->{changes} = CDS::UnionList::Part->new;

#line 151 "Condensation/UnionList/UnionList.pm"
		# Add all changes
		my $record = CDS::Record->new;
		for my $item (values %{$o->{items}}) {
			next if $item->{part} != $newPart;
			$item->addToRecord($record);
		}

#line 158 "Condensation/UnionList/UnionList.pm"
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

#line 169 "Condensation/UnionList/UnionList.pm"
			last if ! $addedPart;
		}

#line 172 "Condensation/UnionList/UnionList.pm"
		# Include the selected items
		for my $item (values %{$o->{items}}) {
			next if ! $item->{part}->{selected};
			$item->setPart($newPart);
			$item->addToRecord($record);
		}

#line 179 "Condensation/UnionList/UnionList.pm"
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

#line 190 "Condensation/UnionList/UnionList.pm"
	# Remove obsolete parts
	for my $part (values %{$o->{parts}}) {
		next if ! $part->{isMerged};
		next if $part->{count};
		delete $o->{parts}->{$part->{hashAndKey}->hash->bytes};
		$o->{privateRoot}->dataChanged;
	}

#line 198 "Condensation/UnionList/UnionList.pm"
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

#line 2 "Condensation/UnionList/UnionList/Item.pm"
	$unionList->{unused}->{count} += 1;
	return bless {
		unionList => $unionList,
		id => $id,
		part => $unionList->{unused},
		}, $class;
}

#line 10 "Condensation/UnionList/UnionList/Item.pm"
sub unionList { shift->{unionList} }
sub id { shift->{id} }

sub setPart {
	my $o = shift;
	my $part = shift;

#line 14 "Condensation/UnionList/UnionList/Item.pm"
	$o->{part}->{count} -= 1;
	$o->{part} = $part;
	$o->{part}->{count} += 1;
}

#line 19 "Condensation/UnionList/UnionList/Item.pm"
# abstract sub addToRecord($o, $record)

package CDS::UnionList::Part;

sub new {
	my $class = shift;

#line 2 "Condensation/UnionList/UnionList/Part.pm"
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

#line 5 "Condensation/Actors/Unsaved.pm"
	return bless {
		state => CDS::Unsaved::State->new,
		savingState => undef,
		store => $store,
		};
}

#line 12 "Condensation/Actors/Unsaved.pm"
sub state { shift->{state} }
sub savingState { shift->{savingState} }

#line 15 "Condensation/Actors/Unsaved.pm"
# *** Saving, state propagation

sub isSaving {
	my $o = shift;
	 defined $o->{savingState} }

sub startSaving {
	my $o = shift;

#line 20 "Condensation/Actors/Unsaved.pm"
	die 'Start saving, but already saving' if $o->{savingState};
	$o->{savingState} = $o->{state};
	$o->{state} = CDS::Unsaved::State->new;
}

sub savingDone {
	my $o = shift;

#line 26 "Condensation/Actors/Unsaved.pm"
	die 'Not in saving state' if ! $o->{savingState};
	$o->{savingState} = undef;
}

sub savingFailed {
	my $o = shift;

#line 31 "Condensation/Actors/Unsaved.pm"
	die 'Not in saving state' if ! $o->{savingState};
	$o->{state}->merge($o->{savingState});
	$o->{savingState} = undef;
}

#line 36 "Condensation/Actors/Unsaved.pm"
# *** Store interface

sub id {
	my $o = shift;
	 'Unsaved'."\n".unpack('H*', CDS->randomBytes(16))."\n".$o->{store}->id }

sub get {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 41 "Condensation/Actors/Unsaved.pm"
	my $stateObject = $o->{state}->{objects}->{$hash->bytes};
	return $stateObject->{object} if $stateObject;

#line 44 "Condensation/Actors/Unsaved.pm"
	if ($o->{savingState}) {
		my $savingStateObject = $o->{savingState}->{objects}->{$hash->bytes};
		return $savingStateObject->{object} if $savingStateObject;
	}

#line 49 "Condensation/Actors/Unsaved.pm"
	return $o->{store}->get($hash, $keyPair);
}

sub book {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 53 "Condensation/Actors/Unsaved.pm"
	return $o->{store}->book($hash, $keyPair);
}

sub put {
	my $o = shift;
	my $hash = shift; die 'wrong type '.ref($hash).' for $hash' if defined $hash && ref $hash ne 'CDS::Hash';
	my $object = shift; die 'wrong type '.ref($object).' for $object' if defined $object && ref $object ne 'CDS::Object';
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 57 "Condensation/Actors/Unsaved.pm"
	return $o->{store}->put($hash, $object, $keyPair);
}

sub list {
	my $o = shift;
	my $accountHash = shift; die 'wrong type '.ref($accountHash).' for $accountHash' if defined $accountHash && ref $accountHash ne 'CDS::Hash';
	my $boxLabel = shift;
	my $timeout = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 61 "Condensation/Actors/Unsaved.pm"
	return $o->{store}->list($accountHash, $boxLabel, $timeout, $keyPair);
}

sub modify {
	my $o = shift;
	my $additions = shift;
	my $removals = shift;
	my $keyPair = shift; die 'wrong type '.ref($keyPair).' for $keyPair' if defined $keyPair && ref $keyPair ne 'CDS::KeyPair';

#line 65 "Condensation/Actors/Unsaved.pm"
	return $o->{store}->modify($additions, $removals, $keyPair);
}

package CDS::Unsaved::State;

sub new {
	my $class = shift;

#line 2 "Condensation/Actors/Unsaved/State.pm"
	return bless {
		objects => {},
		mergedSources => [],
		dataSavedHandlers => [],
		};
}

#line 9 "Condensation/Actors/Unsaved/State.pm"
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

#line 14 "Condensation/Actors/Unsaved/State.pm"
	$o->{objects}->{$hash->bytes} = {hash => $hash, object => $object};
}

sub addMergedSource {
	my $o = shift;

#line 18 "Condensation/Actors/Unsaved/State.pm"
	push @{$o->{mergedSources}}, @_;
}

sub addDataSavedHandler {
	my $o = shift;

#line 22 "Condensation/Actors/Unsaved/State.pm"
	push @{$o->{dataSavedHandlers}}, @_;
}

sub merge {
	my $o = shift;
	my $state = shift;

#line 26 "Condensation/Actors/Unsaved/State.pm"
	for my $key (keys %{$state->{objects}}) {
		$o->{objects}->{$key} = $state->{objects}->{$key};
	}

#line 30 "Condensation/Actors/Unsaved/State.pm"
	push @{$o->{mergedSources}}, @{$state->{mergedSources}};
	push @{$o->{dataSavedHandlers}}, @{$state->{dataSavedHandlers}};
}

package UNKNOWN;

package CDS::C;
use Config;
use Inline (C => 'DATA', CCFLAGS => $Config{ccflags}.' -DNDEBUG -std=gnu99', OPTIMIZE => '-O3', LIBS => '-lrt');
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
