sub new($class, $pool, $actorOnStore, $timeout) {
	return bless {
		pool => $pool,
		actorOnStore => $actorOnStore,
		timeout => $timeout,
		cache => {},
		};
}

sub messageBoxReader;

sub removeObsolete($o) {
	my $limit = CDS->now - $o:timeout;
	for my $key (%$o:knownStreamHeads) {
		my $streamHead = $o:knownStreamHeads->{$key} // next;
		next if $streamHead->lastUsed < $limit;
		delete $o:knownStreamHeads->{$key};
	}
}

sub readStreamHead($o, $head) {
	my $streamHead = $o:knownStreamHeads->{$head->hex};
	if ($streamHead) {
		$streamHead->stillInUse;
		return $streamHead;
	}

	# Retrieve the head envelope
	my ($object, $getError) = $o:actorOnStore->store->get($head, $o:pool:keyPair);
	return if defined $getError;

	# Parse the head envelope
	my $envelope = CDS::Record->fromObject($object);
	return $o->invalid($head, 'Not a record.') if ! $envelope;

	# Read the embedded content object
	my $encryptedBytes = $envelope->child('content')->bytesValue;
	return $o->invalid($head, 'Missing content object.') if ! length $encryptedBytes;

	# Decrypt the key
	my $aesKey = $o:pool:keyPair->decryptKeyOnEnvelope($envelope);
	return $o->invalid($head, 'Not encrypted for us.') if ! $aesKey;

	# Decrypt the content
	my $contentObject = CDS::Object->fromBytes(CDS::C::aesCrypt($encryptedBytes, $aesKey, CDS->zeroCTR));
	return $o->invalid($head, 'Invalid content object.') if ! $contentObject;

	my $content = CDS::Record->fromObject($contentObject);
	return $o->invalid($head, 'Content object is not a record.') if ! $content;

	# Verify the sender hash
	my $senderHash = $content->child('sender')->hashValue;
	return $o->invalid($head, 'Missing sender hash.') if ! $senderHash;

	# Verify the sender store
	my $storeRecord = $content->child('store');
	return $o->invalid($head, 'Missing sender store.') if ! scalar $storeRecord->children;

	my $senderStoreUrl = $storeRecord->textValue;
	my $senderStore = $o:pool:delegate->onMessageBoxVerifyStore($senderStoreUrl, $head, $envelope, $senderHash);
	return $o->invalid($head, 'Invalid sender store.') if ! $senderStore;

	# Retrieve the sender's public key
	my ($senderPublicKey, $invalidReason, $publicKeyStoreError) = $o->getPublicKey($senderHash, $senderStore);
	return if defined $publicKeyStoreError;
	return $o->invalid($head, 'Failed to retrieve the sender\'s public key: '.$invalidReason) if defined $invalidReason;

	# Verify the signature
	my $signedHash = CDS::Hash->calculateFor($encryptedBytes);
	return $o->invalid($head, 'Invalid signature.') if ! CDS->verifyEnvelopeSignature($envelope, $senderPublicKey, $signedHash);

	# The envelope is valid
	my $sender = CDS::ActorOnStore->new($senderPublicKey, $senderStore);
	my $newStreamHead = CDS::StreamHead->new($head, $envelope, $senderStoreUrl, $sender, $aesKey, $content);
	$o:knownStreamHeads->{$head->hex} = $newStreamHead;
	return $newStreamHead;
}

sub invalid($o, $head, $reason) {	# private
	my $newStreamHead = CDS::StreamHead->new($head, undef, undef, undef, undef, undef, $reason);
	$o:knownStreamHeads->{$head->hex} = $newStreamHead;
	return $newStreamHead;
}
