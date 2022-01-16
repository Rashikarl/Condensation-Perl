sub new($class, $storeUrl, $actorOnStore, $envelopeHash, $envelope, $cardHash, $card) {
	return bless {
		storeUrl => $storeUrl,
		actorOnStore => $actorOnStore,
		envelopeHash => $envelopeHash,
		envelope => $envelope,
		cardHash => $cardHash,
		card => $card,
		};
}

sub storeUrl;
sub actorOnStore;
sub envelopeHash;
sub envelope;
sub cardHash;
sub card;
