sub new($class, $actor, $store) {
	return bless {
		actor => $actor,
		store => $store,
		};
}

sub actor;
sub store;
