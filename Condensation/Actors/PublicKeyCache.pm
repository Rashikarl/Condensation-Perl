sub new($class, $maxSize) {
	return bless {
		cache => {},
		maxSize => $maxSize,
		};
}

sub add($o, $publicKey) {
	$o:cache->{$publicKey->hash->bytes} = {publicKey => $publicKey, lastAccess => CDS->now};
	$o->deleteOldest;
	return;
}

sub get($o, $hash) {
	my $entry = $o:cache->{$hash->bytes} // return;
	$entry:lastAccess = CDS->now;
	return $entry:publicKey;
}

sub deleteOldest($o) {	# private
	return if scalar values %$o:cache < $o:maxSize;

	my @entries = sort { $a:lastAccess <=> $b:lastAccess } values %$o:cache;
	my $toRemove = int(scalar(@entries) - $o:maxSize / 2);
	for my $entry (@entries) {
		$toRemove -= 1;
		last if $toRemove <= 0;
		delete $o:cache->{$entry:publicKey->hash->bytes};
	}
}
