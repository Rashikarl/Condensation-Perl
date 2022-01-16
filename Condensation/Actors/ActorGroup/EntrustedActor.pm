sub new($class, $actorOnStore, $storeUrl) {
	return bless {
		actorOnStore => $actorOnStore,
		storeUrl => $storeUrl,
		};
}

sub actorOnStore;
sub storeUrl;
