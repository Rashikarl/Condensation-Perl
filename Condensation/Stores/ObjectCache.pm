# A store using a cache store to deliver frequently accessed objects faster, and a backend store.
use parent 'CDS::Store';

sub new($class, $backend, $cache) {
	return bless {
		id => "Object Cache\n".$backend->id."\n".$cache->id,
		backend => $backend,
		cache => $cache,
		};
}

sub id;
sub backend;
sub cache;

sub get($o, $hash, $keyPair) {
	my $objectFromCache = $o:cache->get($hash);
	return $objectFromCache if $objectFromCache;

	my ($object, $error) = $o:backend->get($hash, $keyPair);
	return undef, $error if ! defined $object;
	$o:cache->put($hash, $object, undef);
	return $object;
}

sub put($o; $hash, $object, $keyPair) {
	# The important thing is that the backend succeeds. The cache is a nice-to-have.
	$o:cache->put(@_);
	return $o:backend->put(@_);
}

sub book($o; $hash, $keyPair) {
	# The important thing is that the backend succeeds. The cache is a nice-to-have.
	$o:cache->book(@_);
	return $o:backend->book(@_);
}

sub list($o; $accountHash, $boxLabel, $timeout, $keyPair) {
	# Just pass this through to the backend.
	return $o:backend->list(@_);
}

sub add($o; $accountHash, $boxLabel, $hash, $keyPair) {
	# Just pass this through to the backend.
	return $o:backend->add(@_);
}

sub remove($o; $accountHash, $boxLabel, $hash, $keyPair) {
	# Just pass this through to the backend.
	return $o:backend->remove(@_);
}

sub modify($o; @$additions, @$removals, $keyPair) {
	# Just pass this through to the backend.
	return $o:backend->modify(@_);
}
