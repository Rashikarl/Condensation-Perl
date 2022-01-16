sub new($class, $channel, $message, $done) {
	$channel:currentSubmissionId += 1;

	my $o = bless {
		channel => $channel,
		message => $message,
		done => $done,
		submissionId => $channel:currentSubmissionId,
		recipients => [$channel->recipients],
		entrustedKeys => [$channel->entrustedKeys],
		expires => CDS->now + $channel->validity,
		};

	# Add the current envelope hash to the obsolete hashes
	my $item = $channel->item;
	$channel:obsoleteHashes->{$item->envelopeHash->bytes} = $item->envelopeHash if $item->envelopeHash;
	$o:obsoleteHashesSnapshot = [values %$channel:obsoleteHashes];

	# Create an envelope
	my $publicKeys = [];
	push @$publicKeys, $channel:actor->keyPair->publicKey;
	push @$publicKeys, map { $_->publicKey } @$o:recipients;
	push @$publicKeys, @$o:entrustedKeys;
	$o:envelopeObject = $channel:actor->keyPair->createMessageEnvelope($channel:actor->messagingStoreUrl, $message, $publicKeys, $o:expires)->toObject;
	$o:envelopeHash = $o:envelopeObject->calculateHash;

	# Set the new item and wait until it gets saved
	$channel:unsaved->startSaving;
	$channel:unsaved->savingState->addDataSavedHandler($o);
	$channel:actor->sentList->unsaved->state->merge($channel:unsaved->savingState);
	$item->set($o:expires, $o:envelopeHash, $message);
	$channel:unsaved->savingDone;

	return $o;
}

sub channel;
sub message;
sub recipients($o) { @$o:recipients }
sub entrustedKeys($o) { @$o:entrustedKeys }
sub expires;
sub envelopeObject;
sub envelopeHash;

sub onDataSaved($o) {
	# If we are not the head any more, give up
	return $o:done->onMessageChannelSubmissionCancelled if $o:submissionId != $o:channel:currentSubmissionId;
	$o:channel:obsoleteHashes->{$o:envelopeHash->bytes} = $o:envelopeHash;

	# Process all recipients
	my $succeeded = 0;
	my $failed = 0;
	for my $recipient (@$o:recipients) {
		my $modifications = CDS::StoreModifications->new;

		# Prepare the list of removals
		my $removals = [];
		for my $hash (@$o:obsoleteHashesSnapshot) {
			$modifications->remove($recipient->publicKey->hash, 'messages', $hash);
		}

		# Add the message entry
		$modifications->add($recipient->publicKey->hash, 'messages', $o:envelopeHash, $o:envelopeObject);
		my $error = $recipient->store->modify($modifications, $o:channel:actor->keyPair);

		if (defined $error) {
			$failed += 1;
			$o:done->onMessageChannelSubmissionRecipientFailed($recipient, $error);
		} else {
			$succeeded += 1;
			$o:done->onMessageChannelSubmissionRecipientDone($recipient);
		}
	}

	if ($failed == 0 || scalar keys %$o:obsoleteHashes > 64) {
		for my $hash (@$o:obsoleteHashesSnapshot) {
			delete $o:channel:obsoleteHashes->{$hash->bytes};
		}
	}

	$o:done->onMessageChannelSubmissionDone($succeeded, $failed);
}

