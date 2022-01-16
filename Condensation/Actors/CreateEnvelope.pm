# EXTEND CDS::KeyPair

sub createPublicEnvelope($o, $contentHash) {
	my $envelope = CDS::Record->new;
	$envelope->add('content')->addHash($contentHash);
	$envelope->add('signature')->add($o->signHash($contentHash));
	return $envelope;
}

sub createPrivateEnvelope($o, $contentHashAndKey, $recipientPublicKeys) {
	my $envelope = CDS::Record->new;
	$envelope->add('content')->addHash($contentHashAndKey->hash);
	$o->addRecipientsToEnvelope($envelope, $contentHashAndKey->key, $recipientPublicKeys);
	$envelope->add('signature')->add($o->signHash($contentHashAndKey->hash));
	return $envelope;
}

sub createMessageEnvelope($o, $storeUrl, $messageRecord, $recipientPublicKeys, $expires) {
	my $contentRecord = CDS::Record->new;
	$contentRecord->add('store')->addText($storeUrl);
	$contentRecord->add('sender')->addHash($o->publicKey->hash);
	$contentRecord->addRecord($messageRecord->children);
	my $contentObject = $contentRecord->toObject;
	my $contentKey = CDS->randomKey;
	my $encryptedContent = CDS::C::aesCrypt($contentObject->bytes, $contentKey, CDS->zeroCTR);
	#my $hashToSign = $contentObject->calculateHash;	# prior to 2020-05-05
	my $hashToSign = CDS::Hash->calculateFor($encryptedContent);

	my $envelope = CDS::Record->new;
	$envelope->add('content')->add($encryptedContent);
	$o->addRecipientsToEnvelope($envelope, $contentKey, $recipientPublicKeys);
	$envelope->add('updated by')->add(substr($o->publicKey->hash->bytes, 0, 24));
	$envelope->add('expires')->addInteger($expires) if defined $expires;
	$envelope->add('signature')->add($o->signHash($hashToSign));
	return $envelope;
}

sub addRecipientsToEnvelope($o, $envelope, $key, $recipientPublicKeys) {	# private
	my $encryptedKeyRecord = $envelope->add('encrypted for');
	my $myHashBytes24 = substr($o:publicKey->hash->bytes, 0, 24);
	$encryptedKeyRecord->add($myHashBytes24)->add($o:publicKey->encrypt($key));
	for my $publicKey (@$recipientPublicKeys) {
		next if $publicKey->hash->equals($o:publicKey->hash);
		my $hashBytes24 = substr($publicKey->hash->bytes, 0, 24);
		$encryptedKeyRecord->add($hashBytes24)->add($publicKey->encrypt($key));
	}
}
