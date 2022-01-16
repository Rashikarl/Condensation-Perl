sub new($class) {
	return bless {
		isMerged => 0,
		hashAndKey => undef,
		size => 0,
		count => 0,
		selected => 0,
		};
}
