# INCLUDE ActorGroup/Member.pm
# INCLUDE ActorGroup/EntrustedActor.pm

# Members must be sorted in descending revision order, such that the member with the most recent revision is first. Members must not include any revoked actors.
sub new($class, $members, $entrustedActorsRevision, $entrustedActors) {
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

sub members($o) { @$o:members }
sub entrustedActorsRevision;
sub entrustedActors($o) { @$o:entrustedActors }

# Checks whether the actor group contains at least one active member.
sub isActive($o) {
	for my $member (@$o:members) {
		return 1 if $member->isActive;
	}
	return;
}

# Returns the most recent active member, the most recent idle member, or undef if the group is empty.
sub leader($o) {
	for my $member (@$o:members) {
		return $member if $member->isActive;
	}
	return $o:members->[0];
}

# Returns true if the account belongs to this actor group.
# Note that multiple (different) actor groups may claim that the account belongs to them. In practice, an account usually belongs to one actor group.
sub contains($o, $actorHash) {
	return exists $o:containsCache->{$actorHash->bytes};
}

# Returns true if the account is entrusted by this actor group.
sub entrusts($o, $actorHash) {
	for my $actor (@$o:entrustedActors) {
		return 1 if $actorHash->equals($actor->publicKey->hash);
	}
	return;
}

# Returns all public keys.
sub publicKeys($o) {
	my @publicKeys;
	for my $member (@$o:members) {
		push @publicKeys, $member->actorOnStore->publicKey;
	}
	for my $actor (@$o:entrustedActors) {
		push @publicKeys, $actor->actorOnStore->publicKey;
	}
	return @publicKeys;
}

# Returns an ActorGroupBuilder with all members and entrusted keys of this ActorGroup.
sub toBuilder($o) {
	my $builder = CDS::ActorGroupBuilder->new;
	$builder->mergeEntrustedActors($o:entrustedActorsRevision);
	for my $member (@$o:members) {
		my $publicKey = $member->actorOnStore->publicKey;
		$builder->addKnownPublicKey($publicKey);
		$builder->addMember($publicKey->hash, $member->storeUrl, $member->revision, $member->isActive ? 'active' : 'idle');
	}
	for my $actor (@$o:entrustedActors) {
		my $publicKey = $actor->actorOnStore->publicKey;
		$builder->addKnownPublicKey($publicKey);
		$builder->addEntrustedActor($publicKey->hash, $actor->storeUrl);
	}
	return $builder;
}
