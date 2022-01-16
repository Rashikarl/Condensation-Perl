# INCLUDE ActorGroupBuilder/Member.pm
# INCLUDE ActorGroupBuilder/EntrustedActor.pm

sub new($class) {
	return bless {
		knownPublicKeys => {},			# A hashref of known public keys (e.g. from the existing actor group)
		members => {},					# Members by URL
		entrustedActorsRevision => 0,	# Revision of the list of entrusted actors
		entrustedActors => {},			# Entrusted actors by hash
		};
}

sub members($o) { values %$o:members }
sub entrustedActorsRevision;
sub entrustedActors($o) { values %$o:entrustedActors }
sub knownPublicKeys;

sub addKnownPublicKey($o, $publicKey) {
	$o:publicKeys->{$publicKey->hash->bytes} = $publicKey;
}

sub addMember($o, $hash, $storeUrl, $revision // 0, $status // 'active') {
	my $url = $storeUrl.'/accounts/'.$hash->hex;
	my $member = $o:members->{$url};
	return if $member && $revision <= $member->revision;
	$o:members->{$url} = CDS::ActorGroupBuilder::Member->new($hash, $storeUrl, $revision, $status);
	return 1;
}

sub removeMember($o, $hash, $storeUrl) {
	my $url = $storeUrl.'/accounts/'.$hash->hex;
	delete $o:members->{$url};
}

sub parseMembers($o, $record, $linkedPublicKeys) {
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

sub mergeEntrustedActors($o, $revision) {
	return if $revision <= $o:entrustedActorsRevision;
	$o:entrustedActorsRevision = $revision;
	$o:entrustedActors = {};
	return 1;
}

sub addEntrustedActor($o, $hash, $storeUrl) {
	my $actor = CDS::ActorGroupBuilder::EntrustedActor->new($hash, $storeUrl);
	$o:entrustedActors->{$hash->bytes} = $actor;
}

sub removeEntrustedActor($o, $hash) {
	delete $o:entrustedActors->{$hash->bytes};
}

sub parseEntrustedActors($o, $record, $linkedPublicKeys) {
	for my $revisionRecord ($record->children) {
		next if ! $o->mergeEntrustedActors($revisionRecord->asInteger);
		$o->parseEntrustedActorList($revisionRecord, $linkedPublicKeys);
	}
}

sub parseEntrustedActorList($o, $record, $linkedPublicKeys) {
	die 'linked public keys?' if ! defined $linkedPublicKeys;
	for my $storeRecord ($record->children) {
		my $storeUrl = $storeRecord->asText;

		for my $child ($storeRecord->children) {
			my $hash = $linkedPublicKeys ? $child->hash : CDS::Hash->fromBytes($child->bytes);
			$o->addEntrustedActor($hash // next, $storeUrl);
		}
	}
}

sub parse($o, $record, $linkedPublicKeys) {
	$o->parseMembers($record->child('actor group'), $linkedPublicKeys);
	$o->parseEntrustedActors($record->child('entrusted actors'), $linkedPublicKeys);
}

sub load($o, $store, $keyPair, $delegate) {
	return CDS::LoadActorGroup->load($o, $store, $keyPair, $delegate);
}

sub discover($o, $keyPair, $delegate) {
	return CDS::DiscoverActorGroup->discover($o, $keyPair, $delegate);
}

# Serializes the actor group to a record that can be passed to parse.
sub addToRecord($o, $record, $linkedPublicKeys) {
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

	if ($o:entrustedActorsRevision) {
		my $listRecord = $o->entrustedActorListToRecord($linkedPublicKeys);
		$record->add('entrusted actors')->addInteger($o:entrustedActorsRevision)->addRecord($listRecord->children);
	}
}

sub toRecord($o, $linkedPublicKeys) {
	my $record = CDS::Record->new;
	$o->addToRecord($record, $linkedPublicKeys);
	return $record;
}

sub entrustedActorListToRecord($o, $linkedPublicKeys) {
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
