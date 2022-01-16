use parent 'CDS::Store';

sub new($class, $store, $url, $errorHandler) {
	return bless {
		store => $store,
		url => $url,
		errorHandler => $errorHandler,
		}
}

sub store;
sub url;
sub errorHandler;

sub id($o) { 'Error handling'."\n  ".$o:store->id }

sub get($o, $hash, $keyPair) {
	return undef, 'Store disabled.' if $o:errorHandler->hasStoreError($o, 'GET');

	my ($object, $error) = $o:store->get($hash, $keyPair);
	if (defined $error) {
		$o:errorHandler->onStoreError($o, 'GET', $error);
		return undef, $error;
	}

	$o:errorHandler->onStoreSuccess($o, 'GET');
	return $object, $error;
}

sub book($o, $hash, $keyPair) {
	return undef, 'Store disabled.' if $o:errorHandler->hasStoreError($o, 'BOOK');

	my ($booked, $error) = $o:store->book($hash, $keyPair);
	if (defined $error) {
		$o:errorHandler->onStoreError($o, 'BOOK', $error);
		return undef, $error;
	}

	$o:errorHandler->onStoreSuccess($o, 'BOOK');
	return $booked;
}

sub put($o, $hash, $object, $keyPair) {
	return 'Store disabled.' if $o:errorHandler->hasStoreError($o, 'PUT');

	my $error = $o:store->put($hash, $object, $keyPair);
	if (defined $error) {
		$o:errorHandler->onStoreError($o, 'PUT', $error);
		return $error;
	}

	$o:errorHandler->onStoreSuccess($o, 'PUT');
	return;
}

sub list($o, $accountHash, $boxLabel, $timeout, $keyPair) {
	return undef, 'Store disabled.' if $o:errorHandler->hasStoreError($o, 'LIST');

	my ($hashes, $error) = $o:store->list($accountHash, $boxLabel, $timeout, $keyPair);
	if (defined $error) {
		$o:errorHandler->onStoreError($o, 'LIST', $error);
		return undef, $error;
	}

	$o:errorHandler->onStoreSuccess($o, 'LIST');
	return $hashes;
}

sub add($o, $accountHash, $boxLabel, $hash, $keyPair) {
	return 'Store disabled.' if $o:errorHandler->hasStoreError($o, 'ADD');

	my $error = $o:store->add($accountHash, $boxLabel, $hash, $keyPair);
	if (defined $error) {
		$o:errorHandler->onStoreError($o, 'ADD', $error);
		return $error;
	}

	$o:errorHandler->onStoreSuccess($o, 'ADD');
	return;
}

sub remove($o, $accountHash, $boxLabel, $hash, $keyPair) {
	return 'Store disabled.' if $o:errorHandler->hasStoreError($o, 'REMOVE');

	my $error = $o:store->remove($accountHash, $boxLabel, $hash, $keyPair);
	if (defined $error) {
		$o:errorHandler->onStoreError($o, 'REMOVE', $error);
		return $error;
	}

	$o:errorHandler->onStoreSuccess($o, 'REMOVE');
	return;
}

sub modify($o, $modifications, $keyPair) {
	return 'Store disabled.' if $o:errorHandler->hasStoreError($o, 'MODIFY');

	my $error = $o:store->modify($modifications, $keyPair);
	if (defined $error) {
		$o:errorHandler->onStoreError($o, 'MODIFY', $error);
		return $error;
	}

	$o:errorHandler->onStoreSuccess($o, 'MODIFY');
	return;
}
