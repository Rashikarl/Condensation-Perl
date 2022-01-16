# EXTEND CDS

### Open envelopes ###

sub verifyEnvelopeSignature($class, $envelope, $publicKey, $hash) {
	# Read the signature
	my $signature = $envelope->child('signature')->bytesValue;
	return if length $signature < 1;

	# Verify the signature
	return if ! $publicKey->verifyHash($hash, $signature);
	return 1;
}

# EXTEND CDS::KeyPair

### Open envelopes ###

sub decryptKeyOnEnvelope($o, $envelope) {
	# Read the AES key
	my $hashBytes24 = substr($o:publicKey->hash->bytes, 0, 24);
	my $encryptedAesKey = $envelope->child('encrypted for')->child($hashBytes24)->bytesValue;
	$encryptedAesKey = $envelope->child('encrypted for')->child($o:publicKey->hash->bytes)->bytesValue if ! length $encryptedAesKey; # todo: remove this
	return if ! length $encryptedAesKey;

	# Decrypt the AES key
	my $aesKeyBytes = $o->decrypt($encryptedAesKey);
	return if ! $aesKeyBytes || length $aesKeyBytes != 32;

	return $aesKeyBytes;
}
