sub load($class, $builder, $store, $keyPair, $delegate) {
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

sub getPublicKey($o, $hash) {
	my $knownPublicKey = $o:knownPublicKeys->{$hash->bytes};
	return $knownPublicKey if $knownPublicKey;

	my ($publicKey, $invalidReason, $storeError) = $o:keyPair->getPublicKey($hash, $o:store);
	return undef, $storeError if defined $storeError;
	return if defined $invalidReason;

	$o:knownPublicKeys->{$hash->bytes} = $publicKey;
	return $publicKey;
};
