sub new($o, $store, $objects) {
	return bless {
		store => $store,
		id => "Check signature store\n".$store->id,
		objects => $objects // {},
		};
}

sub id;

sub get($o, $hash, $keyPair) {
	my $entry = $o:objects->{$hash->bytes} // return $o:store->get($hash);
	return $entry:object;
}

sub book($o, $hash, $keyPair) {
	return exists $o:objects->{$hash->bytes};
}

sub put($o, $hash, $object, $keyPair) {
	$o:objects->{$hash->bytes} = {hash => $hash, object => $object};
	return;
}

sub list($o, $accountHash, $boxLabel, $timeout, $keyPair) {
	return 'This store only handles objects.';
}

sub add($o, $accountHash, $boxLabel, $hash, $keyPair) {
	return 'This store only handles objects.';
}

sub remove($o, $accountHash, $boxLabel, $hash, $keyPair) {
	return 'This store only handles objects.';
}

sub modify($o, $modifications, $keyPair) {
	return $modifications->executeIndividually($o, $keyPair);
}


