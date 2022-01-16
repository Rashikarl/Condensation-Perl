# Reads the private box of an actor.

sub new($class, $keyPair, $store, $delegate) {
	return bless {
		keyPair => $keyPair,
		actorOnStore => CDS::ActorOnStore->new($keyPair->publicKey, $store),
		delegate => $delegate,
		entries => {},
		};
}

sub keyPair;
sub actorOnStore;
sub delegate;

sub read($o) {
	my $store = $o:actorOnStore->store;
	my ($hashes, $listError) = $store->list($o:actorOnStore->publicKey->hash, 'private', 0, $o:keyPair);
	return if defined $listError;

	# Keep track of the processed entries
	my $newEntries = {};
	for my $hash (@$hashes) {
		$newEntries->{$hash->bytes} = $o:entries->{$hash->bytes} // {hash => $hash, processed => 0};
	}
	$o:entries = $newEntries;

	# Process new entries
	for my $entry (values %$newEntries) {
		next if $entry:processed;

		# Get the envelope
		my ($object, $getError) = $store->get($entry:hash, $o:keyPair);
		return if defined $getError;

		if (! defined $object) {
			$o->invalid($entry, 'Envelope object not found.');
			next;
		}

		# Parse the record
		my $envelope = CDS::Record->fromObject($object);
		if (! $envelope) {
			$o->invalid($entry, 'Envelope is not a record.');
			next;
		}

		# Read the content hash
		my $contentHash = $envelope->child('content')->hashValue;
		if (! $contentHash) {
			$o->invalid($entry, 'Missing content hash.');
			next;
		}

		# Verify the signature
		if (! CDS->verifyEnvelopeSignature($envelope, $o:keyPair->publicKey, $contentHash)) {
			$o->invalid($entry, 'Invalid signature.');
			next;
		}

		# Decrypt the key
		my $aesKey = $o:keyPair->decryptKeyOnEnvelope($envelope);
		if (! $aesKey) {
			$o->invalid($entry, 'Not encrypted for us.');
			next;
		}

		# Retrieve the content
		my $contentHashAndKey = CDS::HashAndKey->new($contentHash, $aesKey);
		my ($contentRecord, $contentObject, $contentInvalidReason, $contentStoreError) = $o:keyPair->getAndDecryptRecord($contentHashAndKey, $store);
		return if defined $contentStoreError;

		if (defined $contentInvalidReason) {
			$o->invalid($entry, $contentInvalidReason);
			next;
		}

		$entry:processed = 1;
		my $source = CDS::Source->new($o:keyPair, $o:actorOnStore, 'private', $entry:hash);
		$o:delegate->onPrivateBoxEntry($source, $envelope, $contentHashAndKey, $contentRecord);
	}

	return 1;
}

sub invalid($o, $entry, $reason) {
	$entry:processed = 1;
	my $source = CDS::Source->new($o:actorOnStore, 'private', $entry:hash);
	$o:delegate->onPrivateBoxInvalidEntry($source, $reason);
}

# Delegate
# onPrivateBoxEntry($source, $envelope, $contentHashAndKey, $contentRecord)
# onPrivateBoxInvalidEntry($source, $reason)
