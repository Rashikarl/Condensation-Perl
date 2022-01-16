sub new($class, $keyPair, $publicKeyCache, $delegate) {
	return bless {
		keyPair => $keyPair,
		publicKeyCache => $publicKeyCache,
		delegate => $delegate,
		};
}

sub keyPair;
sub publicKeyCache;

# Delegate
# onMessageBoxVerifyStore($senderStoreUrl, $hash, $envelope, $senderHash)
# onMessageBoxEntry($receivedMessage)
# onMessageBoxStream($receivedMessage)
# onMessageBoxInvalidEntry($source, $reason)
