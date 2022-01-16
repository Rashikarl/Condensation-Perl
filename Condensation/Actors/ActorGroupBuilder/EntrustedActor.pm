sub new($class, $hash, $storeUrl) {
	return bless {
		hash => $hash,
		storeUrl => $storeUrl,
		};
}

sub hash;
sub storeUrl;
