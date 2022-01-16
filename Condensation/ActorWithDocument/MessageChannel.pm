# INCLUDE MessageChannel/Submission.pm

sub new($class, $actor, $label, $validity) {
	my $o = bless {
		actor => $actor,
		label => $label,
		validity => $validity,
		};

	$o:unsaved = CDS::Unsaved->new($actor->sentList->unsaved);
	$o:transfers = [];
	$o:recipients = [];
	$o:entrustedKeys = [];
	$o:obsoleteHashes = {};
	$o:currentSubmissionId = 0;
	return $o;
}

sub actor;
sub label;
sub validity;
sub unsaved;
sub item($o) { $o:actor->sentList->getOrCreate($o:label) }
sub recipients($o) { @$o:recipients }
sub entrustedKeys($o) { @$o:entrustedKeys }

sub addObject($o, $hash, $object) {
	$o:unsaved->state->addObject($hash, $object);
}

sub addTransfer($o, $hashes, $sourceStore, $context) {
	return if ! scalar @$hashes;
	push @$o:transfers, {hashes => $hashes, sourceStore => $sourceStore, context => $context};
}

sub setRecipientActorGroup($o, $actorGroup) {
	$o:recipients = [map { $_->actorOnStore } $actorGroup->members];
	$o:entrustedKeys = [map { $_->actorOnStore->publicKey } $actorGroup->entrustedActors];
}

sub setRecipients($o, $recipients, $entrustedKeys) {
	$o:recipients = $recipients;
	$o:entrustedKeys = $entrustedKeys;
}

sub submit($o, $message, $done) {
	# Check if the sent list has been loaded
	return if ! $o:actor->sentListReady;

	# Transfer
	my $transfers = $o:transfers;
	$o:transfers = [];
	for my $transfer (@$transfers) {
		my ($missingObject, $store, $error) = $o:actor->keyPair->transfer($transfer:hashes, $transfer:sourceStore, $o:actor->messagingPrivateRoot->unsaved);
		return if defined $error;

		if ($missingObject) {
			$missingObject:context = $transfer:context;
			return undef, $missingObject;
		}
	}

	# Send the message
	return CDS::MessageChannel::Submission->new($o, $message, $done);
}

sub clear($o) {
	$o->item->clear(CDS->now + $o:validity);
}
