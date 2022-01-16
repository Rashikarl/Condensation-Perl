sub new($class, $hash) {
	return bless {
		hash => $hash,
		processed => 0,
		};
}
