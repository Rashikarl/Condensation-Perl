sub new($class, $keyPair, $storageStore, $messagingStore, $messagingStoreUrl, $publicKeyCache) {
	my $o = bless {
		keyPair => $keyPair,
		storageStore => $storageStore,
		messagingStore => $messagingStore,
		messagingStoreUrl => $messagingStoreUrl,
		groupDataHandlers => [],
		}, $class;

	# Private data on the storage store
	$o:storagePrivateRoot = CDS::PrivateRoot->new($keyPair, $storageStore, $o);
	$o:groupDocument = CDS::RootDocument->new($o:storagePrivateRoot, 'group data');
	$o:localDocument = CDS::RootDocument->new($o:storagePrivateRoot, 'local data');

	# Private data on the messaging store
	$o:messagingPrivateRoot = $storageStore->id eq $messagingStore->id ? $o:storagePrivateRoot : CDS::PrivateRoot->new($keyPair, $messagingStore, $o);
	$o:sentList = CDS::SentList->new($o:messagingPrivateRoot);
	$o:sentListReady = 0;

	# Group data sharing
	$o:groupDataSharer = CDS::GroupDataSharer->new($o);
	$o:groupDataSharer->addDataHandler($o:groupDocument->label, $o:groupDocument);

	# Selectors
	$o:groupRoot = $o:groupDocument->root;
	$o:localRoot = $o:localDocument->root;
	$o:publicDataSelector = $o:groupRoot->child('public data');
	$o:actorGroupSelector = $o:groupRoot->child('actor group');
	$o:actorSelector = $o:actorGroupSelector->child(substr($keyPair->publicKey->hash->bytes, 0, 16));
	$o:entrustedActorsSelector = $o:groupRoot->child('entrusted actors');

	# Message reader
	my $pool = CDS::MessageBoxReaderPool->new($keyPair, $publicKeyCache, $o);
	$o:messageBoxReader = CDS::MessageBoxReader->new($pool, CDS::ActorOnStore->new($keyPair->publicKey, $messagingStore), CDS->HOUR);

	# Active actor group members and entrusted keys
	$o:cachedGroupDataMembers = {};
	$o:cachedEntrustedKeys = {};
	return $o;
}

sub keyPair;
sub storageStore;
sub messagingStore;
sub messagingStoreUrl;

sub storagePrivateRoot;
sub groupDocument;
sub localDocument;

sub messagingPrivateRoot;
sub sentList;
sub sentListReady;

sub groupDataSharer;

sub groupRoot;
sub localRoot;
sub publicDataSelector;
sub actorGroupSelector;
sub actorSelector;
sub entrustedActorsSelector;

### Our own actor ###

sub isMe($o, $actorHash) {
	return $o:keyPair->publicKey->hash->equals($actorHash);
}

sub setName($o, $name) {
	$o:actorSelector->child('name')->set($name);
}

sub getName($o) {
	return $o:actorSelector->child('name')->textValue;
}

sub updateMyRegistration($o) {
	$o:actorSelector->addObject($o:keyPair->publicKey->hash, $o:keyPair->publicKey->object);
	my $record = CDS::Record->new;
	$record->add('hash')->addHash($o:keyPair->publicKey->hash);
	$record->add('store')->addText($o:messagingStoreUrl);
	$o:actorSelector->set($record);
}

sub setMyActiveFlag($o, $flag) {
	$o:actorSelector->child('active')->setBoolean($flag);
}

sub setMyGroupDataFlag($o, $flag) {
	$o:actorSelector->child('group data')->setBoolean($flag);
}

### Actor group

sub isGroupMember($o, $actorHash) {
	return 1 if $actorHash->equals($o:keyPair->publicKey->hash);
	my $memberSelector = $o->findMember($actorHash) // return;
	return ! $memberSelector->child('revoked')->isSet;
}

sub findMember($o, $memberHash) {
	for my $child ($o:actorGroupSelector->children) {
		my $record = $child->record;
		my $hash = $record->child('hash')->hashValue // next;
		next if ! $hash->equals($memberHash);
		return $child;
	}

	return;
}

sub forgetOldIdleActors($o, $limit) {
	for my $child ($o:actorGroupSelector->children) {
		next if $child->child('active')->booleanValue;
		next if $child->child('group data')->booleanValue;
		next if $child->revision > $limit;
		$child->forgetBranch;
	}
}

### Group data members

sub getGroupDataMembers($o) {
	# Update the cached list
	for my $child ($o:actorGroupSelector->children) {
		my $record = $child->record;
		my $hash = $record->child('hash')->hashValue;
		$hash = undef if $hash->equals($o:keyPair->publicKey->hash);
		$hash = undef if $child->child('revoked')->isSet;
		$hash = undef if ! $child->child('group data')->isSet;

		# Remove
		if (! $hash) {
			delete $o:cachedGroupDataMembers->{$child->label};
			next;
		}

		# Keep
		my $member = $o:cachedGroupDataMembers->{$child->label};
		my $storeUrl = $record->child('store')->textValue;
		next if $member && $member->storeUrl eq $storeUrl && $member->actorOnStore->publicKey->hash->equals($hash);

		# Verify the store
		my $store = $o->onVerifyMemberStore($storeUrl, $child);
		if (! $store) {
			delete $o:cachedGroupDataMembers->{$child->label};
			next;
		}

		# Reuse the public key and add
		if ($member && $member->actorOnStore->publicKey->hash->equals($hash)) {
			my $actorOnStore = CDS::ActorOnStore->new($member->actorOnStore->publicKey, $store);
			$o:cachedEntrustedKeys->{$child->label} = {storeUrl => $storeUrl, actorOnStore => $actorOnStore};
		}

		# Get the public key and add
		my ($publicKey, $invalidReason, $storeError) = $o:keyPair->getPublicKey($hash, $o:groupDocument->unsaved);
		return if defined $storeError;
		if (defined $invalidReason) {
			delete $o:cachedGroupDataMembers->{$child->label};
			next;
		}

		my $actorOnStore = CDS::ActorOnStore->new($publicKey, $store);
		$o:cachedGroupDataMembers->{$child->label} = {storeUrl => $storeUrl, actorOnStore => $actorOnStore};
	}

	# Return the current list
	return [map { $_:actorOnStore } values %$o:cachedGroupDataMembers];
}

### Entrusted actors

sub entrust($o, $storeUrl, $publicKey) {
	# TODO: this is not compatible with the Java implementation (which uses a record with "hash" and "store")
	my $selector = $o:entrustedActorsSelector;
	my $builder = CDS::ActorGroupBuilder->new;
	$builder->parseEntrustedActorList($selector->record, 1);
	$builder->removeEntrustedActor($publicKey->hash);
	$builder->addEntrustedActor($storeUrl, $publicKey->hash);
	$selector->addObject($publicKey->hash, $publicKey->object);
	$selector->set($builder->entrustedActorListToRecord(1));
	$o:cachedEntrustedKeys->{$publicKey->hash->bytes} = $publicKey;
}

sub doNotEntrust($o, $hash) {
	my $selector = $o:entrustedActorsSelector;
	my $builder = CDS::ActorGroupBuilder->new;
	$builder->parseEntrustedActorList($selector->record, 1);
	$builder->removeEntrustedActor($hash);
	$selector->set($builder->entrustedActorListToRecord(1));
	delete $o:cachedEntrustedKeys->{$hash->bytes};
}

sub getEntrustedKeys($o) {
	my $entrustedKeys = [];
	for my $storeRecord ($o:entrustedActorsSelector->record->children) {
		for my $child ($storeRecord->children) {
			my $hash = $child->hash // next;
			push @$entrustedKeys, $o->getEntrustedKey($hash) // next;
		}
	}

	# We could remove unused keys from $o:cachedEntrustedKeys here, but since this is
	# such a rare event, and doesn't consume a lot of memory, this would be overkill.

	return $entrustedKeys;
}

sub getEntrustedKey($o, $hash) {
	my $entrustedKey = $o:cachedEntrustedKeys->{$hash->bytes};
	return $entrustedKey if $entrustedKey;

	my ($publicKey, $invalidReason, $storeError) = $o:keyPair->getPublicKey($hash, $o:groupDocument->unsaved);
	return if defined $storeError;
	return if defined $invalidReason;
	$o:cachedEntrustedKeys->{$hash->bytes} = $publicKey;
	return $publicKey;
}

### Private data

sub procurePrivateData($o, $interval // CDS->DAY) {
	$o:storagePrivateRoot->procure($interval) // return;
	$o:groupDocument->read // return;
	$o:localDocument->read // return;
	return 1;
}

sub savePrivateDataAndShareGroupData($o) {
	$o:localDocument->save;
	$o:groupDocument->save;
	$o->groupDataSharer->share;
	my $entrustedKeys = $o->getEntrustedKeys // return;
	my ($ok, $missingHash) = $o:storagePrivateRoot->save($entrustedKeys);
	return 1 if $ok;
	$o->onMissingObject($missingHash) if $missingHash;
	return;
}

# abstract sub onVerifyMemberStore($storeUrl, $selector)
# abstract sub onPrivateRootReadingInvalidEntry($o, $source, $reason)
# abstract sub onMissingObject($missingHash)

### Sending messages

sub procureSentList($o, $interval // CDS->DAY) {
	$o:messagingPrivateRoot->procure($interval) // return;
	$o:sentList->read // return;
	$o:sentListReady = 1;
	return 1;
}

sub openMessageChannel($o, $label, $validity) {
	return CDS::MessageChannel->new($o, $label, $validity);
}

sub sendMessages($o) {
	return 1 if ! $o:sentList->hasChanges;
	$o:sentList->save;
	my $entrustedKeys = $o->getEntrustedKeys // return;
	my ($ok, $missingHash) = $o:messagingPrivateRoot->save($entrustedKeys);
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
