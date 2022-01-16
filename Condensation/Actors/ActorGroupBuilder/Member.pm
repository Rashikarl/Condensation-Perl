sub new($class, $hash, $storeUrl, $revision, $status) {
	return bless {
		hash => $hash,
		storeUrl => $storeUrl,
		revision => $revision,
		status => $status,
		};
}

sub hash;
sub storeUrl;
sub revision;
sub status;
