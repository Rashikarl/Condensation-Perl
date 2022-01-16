# Reads the message box of an actor.
# INCLUDE MessageBoxReader/Entry.pm

sub new($class, $pool, $actorOnStore, $streamTimeout) {
	return bless {
		pool => $pool,
		actorOnStore => $actorOnStore,
		streamCache => CDS::StreamCache->new($pool, $actorOnStore, $streamTimeout // CDS->MINUTE),
		entries => {},
		};
}

sub pool;
sub actorOnStore;

sub read($o, $timeout // 0) {
	my $store = $o:actorOnStore->store;
	my ($hashes, $listError) = $store->list($o:actorOnStore->publicKey->hash, 'messages', $timeout, $o:pool:keyPair);
	return if defined $listError;

	for my $hash (@$hashes) {
		my $entry = $o:entries->{$hash->bytes};
		$o:entries->{$hash->bytes} = $entry = CDS::MessageBoxReader::Entry->new($hash) if ! $entry;
		next if $entry:processed;

		# Check the sender store, if necessary
		if ($entry:waitingForStore) {
			my ($dummy, $checkError) = $entry:waitingForStore->get(CDS->emptyBytesHash, $o:pool:keyPair);
			next if defined $checkError;
		}

		# Get the envelope
		my ($object, $getError) = $o:actorOnStore->store->get($entry:hash, $o:pool:keyPair);
		return if defined $getError;

		# Mark the entry as processed
		$entry:processed = 1;

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

		my $message =
			$envelope->contains('head') && $envelope->contains('mac') ?
				$o->readStreamMessage($entry, $envelope) :
				$o->readNormalMessage($entry, $envelope);
		next if ! $message;

		$o:pool:delegate->onMessageBoxEntry($message);
	}

	$o:streamCache->removeObsolete;
	return 1;
}

sub readNormalMessage($o, $entry, $envelope) {	# private
	# Read the embedded content object
	my $encryptedBytes = $envelope->child('content')->bytesValue;
	return $o->invalid($entry, 'Missing content object.') if ! length $encryptedBytes;

	# Decrypt the key
	my $aesKey = $o:pool:keyPair->decryptKeyOnEnvelope($envelope);
	return $o->invalid($entry, 'Not encrypted for us.') if ! $aesKey;

	# Decrypt the content
	my $contentObject = CDS::Object->fromBytes(CDS::C::aesCrypt($encryptedBytes, $aesKey, CDS->zeroCTR));
	return $o->invalid($entry, 'Invalid content object.') if ! $contentObject;

	my $content = CDS::Record->fromObject($contentObject);
	return $o->invalid($entry, 'Content object is not a record.') if ! $content;

	# Verify the sender hash
	my $senderHash = $content->child('sender')->hashValue;
	return $o->invalid($entry, 'Missing sender hash.') if ! $senderHash;

	# Verify the sender store
	my $storeRecord = $content->child('store');
	return $o->invalid($entry, 'Missing sender store.') if ! scalar $storeRecord->children;

	my $senderStoreUrl = $storeRecord->textValue;
	my $senderStore = $o:pool:delegate->onMessageBoxVerifyStore($senderStoreUrl, $entry:hash, $envelope, $senderHash);
	return $o->invalid($entry, 'Invalid sender store.') if ! $senderStore;

	# Retrieve the sender's public key
	my ($senderPublicKey, $invalidReason, $publicKeyStoreError) = $o->getPublicKey($senderHash, $senderStore);
	return if defined $publicKeyStoreError;
	return $o->invalid($entry, 'Failed to retrieve the sender\'s public key: '.$invalidReason) if defined $invalidReason;

	# Verify the signature
	my $signedHash = CDS::Hash->calculateFor($encryptedBytes);
	if (! CDS->verifyEnvelopeSignature($envelope, $senderPublicKey, $signedHash)) {
		# For backwards compatibility with versions before 2020-05-05
		return $o->invalid($entry, 'Invalid signature.') if ! CDS->verifyEnvelopeSignature($envelope, $senderPublicKey, $contentObject->calculateHash);
	}

	# The envelope is valid
	my $sender = CDS::ActorOnStore->new($senderPublicKey, $senderStore);
	my $source = CDS::Source->new($o:pool:keyPair, $o:actorOnStore, 'messages', $entry:hash);
	return CDS::ReceivedMessage->new($o, $entry, $source, $envelope, $senderStoreUrl, $sender, $content);
}

sub readStreamMessage($o, $entry, $envelope) {	# private
	# Get the head
	my $head = $envelope->child('head')->hashValue;
	return $o->invalid($entry, 'Invalid head message hash.') if ! $head;

	# Get the head envelope
	my $streamHead = $o:streamCache->readStreamHead($head);
	return if ! $streamHead;
	return $o->invalid($entry, 'Invalid stream head: '.$streamHead->error) if $streamHead->error;

	# Read the embedded content object
	my $encryptedBytes = $envelope->child('content')->bytesValue;
	return $o->invalid($entry, 'Missing content object.') if ! length $encryptedBytes;

	# Get the CTR
	my $ctr = $envelope->child('ctr')->bytesValue;
	return $o->invalid($entry, 'Invalid CTR.') if length $ctr != 16;

	# Get the MAC
	my $mac = $envelope->child('mac')->bytesValue;
	return $o->invalid($entry, 'Invalid MAC.') if ! $mac;

	# Verify the MAC
	my $signedHash = CDS::Hash->calculateFor($encryptedBytes);
	my $expectedMac = CDS::C::aesCrypt($signedHash->bytes, $streamHead->aesKey, $ctr);
	return $o->invalid($entry, 'Invalid MAC.') if $mac ne $expectedMac;

	# Decrypt the content
	my $contentObject = CDS::Object->fromBytes(CDS::C::aesCrypt($encryptedBytes, $streamHead->aesKey, CDS::C::counterPlusInt($ctr, 2)));
	return $o->invalid($entry, 'Invalid content object.') if ! $contentObject;

	my $content = CDS::Record->fromObject($contentObject);
	return $o->invalid($entry, 'Content object is not a record.') if ! $content;

	# The envelope is valid
	my $source = CDS::Source->new($o:pool:keyPair, $o:actorOnStore, 'messages', $entry:hash);
	return CDS::ReceivedMessage->new($o, $entry, $source, $envelope, $streamHead->senderStoreUrl, $streamHead->sender, $content, $streamHead);
}

sub invalid($o, $entry, $reason) {	# private
	my $source = CDS::Source->new($o:pool:keyPair, $o:actorOnStore, 'messages', $entry:hash);
	$o:pool:delegate->onMessageBoxInvalidEntry($source, $reason);
}

sub getPublicKey($o, $senderHash, $senderStore, $senderStoreUrl) {	# private
	# Use the account key if sender and recipient are the same
	return $o:actorOnStore->publicKey if $senderHash->equals($o:actorOnStore->publicKey->hash);

	# Reuse a cached public key
	my $cachedPublicKey = $o:pool:publicKeyCache->get($senderHash);
	return $cachedPublicKey if $cachedPublicKey;

	# Retrieve the sender's public key from the sender's store
	my ($publicKey, $invalidReason, $storeError) = $o:pool:keyPair->getPublicKey($senderHash, $senderStore);
	return undef, undef, $storeError if defined $storeError;
	return undef, $invalidReason if defined $invalidReason;
	$o:pool:publicKeyCache->add($publicKey);
	return $publicKey;
}
