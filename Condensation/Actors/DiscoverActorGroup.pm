# INCLUDE DiscoverActorGroup/Card.pm
# INCLUDE DiscoverActorGroup/Link.pm
# INCLUDE DiscoverActorGroup/Node.pm

sub discover($class, $builder, $keyPair, $delegate) {
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
		if ($node:revision < $member->revision) {
			$node:revision = $member->revision;
			$node:status = 'active';
		}

		$o:coverage->{$member->hash->bytes} = 1;
	}

	# Determine the revision at start
	my $revisionAtStart = 0;
	for my $node (values %$o:nodesByUrl) {
		$revisionAtStart = $node:revision if $revisionAtStart < $node:revision;
	}

	# Reload the cards of all known accounts
	for my $node (values %$o:nodesByUrl) {
		$node->discover;
	}

	# From here, try extending to other accounts
	while ($o->extend) {}

	# Compile the list of actors and cards
	my @members;
	my @cards;
	for my $node (values %$o:nodesByUrl) {
		next if ! $node:reachable;
		next if ! $node:attachedToUs;
		next if ! $node:actorOnStore;
		next if ! $node->isActiveOrIdle;
		#-- member ++ $node:actorHash->hex ++ $node:cardsRead ++ $node:cards // 'undef' ++ $node:actorOnStore // 'undef'
		push @members, CDS::ActorGroup::Member->new($node:actorOnStore, $node:storeUrl, $node:revision, $node->isActive);
		push @cards, @$node:cards;
	}

	# Get the newest list of entrusted actors
	my $parser = CDS::ActorGroupBuilder->new;
	for my $card (@cards) {
		$parser->parseEntrustedActors($card->card->child('entrusted actors'), 0);
	}

	# Get the entrusted actors
	my $entrustedActors = [];
	for my $actor ($parser->entrustedActors) {
		my $store = $o:delegate->onDiscoverActorGroupVerifyStore($actor->storeUrl);
		next if ! $store;

		my $knownPublicKey = $o:knownPublicKeys->{$actor->hash->bytes};
		if ($knownPublicKey) {
			push @$entrustedActors, CDS::ActorGroup::EntrustedActor->new(CDS::ActorOnStore->new($knownPublicKey, $store), $actor->storeUrl);
			next;
		}

		my ($publicKey, $invalidReason, $storeError) = $keyPair->getPublicKey($actor->hash, $store);

		if (defined $invalidReason) {
			$o:discoverer:delegate->onDiscoverActorGroupInvalidPublicKey($actor->hash, $store, $invalidReason);
			next;
		}

		if (defined $storeError) {
			$o:discoverer:delegate->onDiscoverActorGroupStoreError($store, $storeError);
			next;
		}

		push @$entrustedActors, CDS::ActorGroup::EntrustedActor->new(CDS::ActorOnStore->new($publicKey, $store), $actor->storeUrl);
	}

	my $members = [sort { $b:revision <=> $a:revision || $b:status cmp $a:status } @members];
	return CDS::ActorGroup->new($members, $parser->entrustedActorsRevision, $entrustedActors), [@cards], [grep { $_:attachedToUs } values %$o:nodesByUrl];
}

sub node($o, $actorHash, $storeUrl) {	# private
	my $url = $storeUrl.'/accounts/'.$actorHash->hex;
	my $node = $o:nodesByUrl->{$url};
	return $node if $node;
	return $o:nodesByUrl->{$url} = CDS::DiscoverActorGroup::Node->new($o, $actorHash, $storeUrl);
}

sub covers($o, $hash) { $o:coverage->{$hash->bytes} }

sub extend($o) {
	# Start with the newest node
	my $mainNode;
	my $mainRevision = -1;
	for my $node (values %$o:nodesByUrl) {
		next if ! $node:attachedToUs;
		next if $node:revision <= $mainRevision;
		$mainNode = $node;
		$mainRevision = $node:revision;
	}

	return 0 if ! $mainNode;

	# Reset the reachable flag
	for my $node (values %$o:nodesByUrl) {
		$node:reachable = 0;
	}
	$mainNode:reachable = 1;

	# Traverse the graph along active links to find accounts to discover.
	my @toDiscover;
	my @toCheck = ($mainNode);
	while (1) {
		my $currentNode = shift(@toCheck) // last;
		for my $link (@$currentNode:links) {
			my $node = $link:node;
			next if $node:reachable;
			my $prospectiveStatus = $link:revision > $node:revision ? $link:status : $node:status;
			next if $prospectiveStatus ne 'active';
			$node:reachable = 1;
			push @toCheck, $node if $node:attachedToUs;
			push @toDiscover, $node if ! $node:attachedToUs;
		}
	}

	# Discover these accounts
	my $hasChanges = 0;
	for my $node (sort { $b:revision <=> $a:revision } @toDiscover) {
		$node->discover;
		next if ! $node:attachedToUs;
		$hasChanges = 1;
	}

	return $hasChanges;
}
