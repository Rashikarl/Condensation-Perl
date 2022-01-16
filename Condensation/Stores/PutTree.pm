sub new($o, $store, $keyPair, $commitPool) {
	return bless {
		store => $store,
		commitPool => $commitPool,
		keyPair => $keyPair,
		done => {},
		};
}

sub put($o, $hash // return) {
	return if $o:done->{$hash->bytes};

	# Get the item
	my $hashAndObject = $o:commitPool->object($hash) // return;

	# Upload all children
	for my $hash ($hashAndObject->object->hashes) {
		my $error = $o->put($hash);
		return $error if defined $error;
	}

	# Upload this object
	my $error = $o:store->put($hashAndObject->hash, $hashAndObject->object, $o:keyPair);
	return $error if defined $error;
	$o:done->{$hash->bytes} = 1;
	return;
}
