sub new($class, $actorOnStore, $storeUrl, $revision, $isActive) {
	return bless {
		actorOnStore => $actorOnStore,
		storeUrl => $storeUrl,
		revision => $revision,
		isActive => $isActive,
		};
}

sub actorOnStore;
sub storeUrl;
sub revision;
sub isActive;
