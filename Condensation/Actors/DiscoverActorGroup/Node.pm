sub new($class, $discoverer, $actorHash, $storeUrl) {
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

sub cards($o) { @$o:cards }
sub isActive($o) { $o:status eq 'active' }
sub isActiveOrIdle($o) { $o:status eq 'active' || $o:status eq 'idle' }

sub actorHash;
sub storeUrl;
sub revision;
sub status;
sub attachedToUs;
sub links($o) { @$o:links }

sub discover($o) {
	#-- discover ++ $o:actorHash->hex
	$o->readCards;
	$o->attach;
}

sub readCards($o) {
	return if $o:cardsRead;
	$o:cardsRead = 1;
	#-- read cards of ++ $o:actorHash->hex

	# Get the store
	my $store = $o:discoverer:delegate->onDiscoverActorGroupVerifyStore($o:storeUrl, $o:actorHash) // return;

	# Get the public key if necessary
	if (! $o:actorOnStore) {
		my $publicKey = $o:discoverer:knownPublicKeys->{$o:actorHash->bytes};
		if (! $publicKey) {
			my ($downloadedPublicKey, $invalidReason, $storeError) = $o:discoverer:keyPair->getPublicKey($o:actorHash, $store);
			return $o:discoverer:delegate->onDiscoverActorGroupStoreError($store, $storeError) if defined $storeError;
			return $o:discoverer:delegate->onDiscoverActorGroupInvalidPublicKey($o:actorHash, $store, $invalidReason) if defined $invalidReason;
			$publicKey = $downloadedPublicKey;
		}

		$o:actorOnStore = CDS::ActorOnStore->new($publicKey, $store);
	}

	# List the public box
	my ($hashes, $storeError) = $store->list($o:actorHash, 'public', 0, $o:discoverer:keyPair);
	return $o:discoverer:delegate->onDiscoverActorGroupStoreError($store, $storeError) if defined $storeError;

	for my $envelopeHash (@$hashes) {
		# Open the envelope
		my ($object, $storeError) = $store->get($envelopeHash, $o:discoverer:keyPair);
		return $o:discoverer:delegate->onDiscoverActorGroupStoreError($store, $storeError) if defined $storeError;
		if (! $object) {
			$o:discoverer:delegate->onDiscoverActorGroupInvalidCard($o:actorOnStore, $envelopeHash, 'Envelope object not found.');
			next;
		}

		my $envelope = CDS::Record->fromObject($object);
		if (! $envelope) {
			$o:discoverer:delegate->onDiscoverActorGroupInvalidCard($o:actorOnStore, $envelopeHash, 'Envelope is not a record.');
			next;
		}

		my $cardHash = $envelope->child('content')->hashValue;
		if (! $cardHash) {
			$o:discoverer:delegate->onDiscoverActorGroupInvalidCard($o:actorOnStore, $envelopeHash, 'Missing content hash.');
			next;
		}

		if (! CDS->verifyEnvelopeSignature($envelope, $o:actorOnStore->publicKey, $cardHash)) {
			$o:discoverer:delegate->onDiscoverActorGroupInvalidCard($o:actorOnStore, $envelopeHash, 'Invalid signature.');
			next;
		}

		# Read the card
		my ($cardObject, $storeError1) = $store->get($cardHash, $o:discoverer:keyPair);
		return $o:discoverer:delegate->onDiscoverActorGroupStoreError($store, $storeError) if defined $storeError1;
		if (! $cardObject) {
			$o:discoverer:delegate->onDiscoverActorGroupInvalidCard($o:actorOnStore, $envelopeHash, 'Card object not found.');
			next;
		}

		my $card = CDS::Record->fromObject($cardObject);
		if (! $card) {
			$o:discoverer:delegate->onDiscoverActorGroupInvalidCard($o:actorOnStore, $envelopeHash, 'Card is not a record.');
			next;
		}

		# Add the card to the list of cards
		push @$o:cards, CDS::DiscoverActorGroup::Card->new($o:storeUrl, $o:actorOnStore, $envelopeHash, $envelope, $cardHash, $card);

		# Parse the account list
		my $builder = CDS::ActorGroupBuilder->new;
		$builder->parseMembers($card->child('actor group'), 0);
		for my $member ($builder->members) {
			my $node = $o:discoverer->node($member->hash, $member->storeUrl);
			#-- new link ++ $o:actorHash->hex ++ $status ++ $hash->hex
			push @$o:links, CDS::DiscoverActorGroup::Link->new($node, $member->revision, $member->status);
		}
	}
}

sub attach($o) {
	return if $o:attachedToUs;
	return if ! $o->hasLinkToUs;

	# Attach this node
	$o:attachedToUs = 1;

	# Merge all links
	for my $link (@$o:links) {
		$link:node->merge($link:revision, $link:status);
	}

	# Add the hash to the coverage
	$o:discoverer:coverage->{$o:actorHash->bytes} = 1;
}

sub merge($o, $revision, $status) {
	return if $o:revision >= $revision;
	$o:revision = $revision;
	$o:status = $status;
}

sub hasLinkToUs($o) {
	return 1 if $o:discoverer->covers($o:actorHash);
	for my $link (@$o:links) {
		return 1 if $o:discoverer->covers($link:node:actorHash);
	}
	return;
}
