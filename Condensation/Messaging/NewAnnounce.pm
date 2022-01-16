sub new($class, $messagingStore) {
	my $o = bless {
		messagingStore => $messagingStore,
		unsaved => CDS::Unsaved->new($messagingStore->store),
		transfers => [],
		card => CDS::Record->new,
		};

	my $publicKey = $messagingStore->actor->keyPair->publicKey;
	$o:card->add('public key')->addHash($publicKey->hash);
	$o->addObject($publicKey->hash, $publicKey->object);
	return $o;
}

sub messagingStore;
sub card;

sub addObject($o, $hash, $object) {
	$o:unsaved->state->addObject($hash, $object);
}

sub addTransfer($o, $hashes, $sourceStore, $context) {
	return if ! scalar @$hashes;
	push @$o:transfers, {hashes => $hashes, sourceStore => $sourceStore, context => $context};
}

sub addActorGroup($o, $actorGroupBuilder) {
	$actorGroupBuilder->addToRecord($o:card, 0);
}

sub submit($o) {
	my $keyPair = $o:messagingStore->actor->keyPair;

	# Create the public card
	my $cardObject = $o:card->toObject;
	my $cardHash = $cardObject->calculateHash;
	$o->addObject($cardHash, $cardObject);

	# Prepare the public envelope
	my $me = $keyPair->publicKey->hash;
	my $envelopeObject = $keyPair->createPublicEnvelope($cardHash)->toObject;
	my $envelopeHash = $envelopeObject->calculateHash;
	$o->addTransfer([$cardHash], $o:unsaved, 'Announcing');

	# Transfer all trees
	for my $transfer (@$o:transfers) {
		my ($missingObject, $store, $error) = $keyPair->transfer($transfer:hashes, $transfer:sourceStore, $o:messagingStore->store);
		return if defined $error;

		if ($missingObject) {
			$missingObject:context = $transfer:context;
			return undef, $missingObject;
		}
	}

	# Prepare a modification
	my $modifications = CDS::StoreModifications->new;
	$modifications->add($me, 'public', $envelopeHash, $envelopeObject);

	# List the current cards to remove them
	# Ignore errors, in the worst case, we are going to have multiple entries in the public box
	my ($hashes, $error) = $o:messagingStore->store->list($me, 'public', 0, $keyPair);
	if ($hashes) {
		for my $hash (@$hashes) {
			$modifications->remove($me, 'public', $hash);
		}
	}

	# Modify the public box
	my $modifyError = $o:messagingStore->store->modify($modifications, $keyPair);
	return if defined $modifyError;
	return $envelopeHash, $cardHash;
}
