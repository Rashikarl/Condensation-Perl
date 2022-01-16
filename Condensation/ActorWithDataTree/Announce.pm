# EXTEND CDS::ActorWithDataTree

### Announcing ###

sub announceOnAllStores($o) {
	$o->announce($o:storageStore);
	$o->announce($o:messagingStore) if $o:messagingStore->id ne $o:storageStore->id;
}

sub announce($o, $store) {
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
	$card->add('public key')->addHash($o:keyPair->publicKey->hash);

	# Add the public data
	for my $child ($o->publicDataSelector->children) {
		my $childRecord = $child->record;
		$card->addRecord($childRecord->children);
	}

	# Create an unsaved state
	my $unsaved = CDS::Unsaved->new($o->publicDataSelector->dataTree->unsaved);

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
		$missingObject:context = 'announce on '.$store->id;
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
