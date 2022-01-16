# EXTEND CDS::KeyPair

sub transfer($o, $hashes, $sourceStore, $destinationStore) {
	for my $hash (@$hashes) {
		my ($missing, $store, $storeError) = $o->recursiveTransfer($hash, $sourceStore, $destinationStore, {});
		return $missing if $missing;
		return undef, $store, $storeError if defined $storeError;
	}

	return;
}

sub recursiveTransfer($o, $hash, $sourceStore, $destinationStore, $done) {	# private
	return if $done->{$hash->bytes};
	$done->{$hash->bytes} = 1;

	# Book
	my ($booked, $bookError) = $destinationStore->book($hash, $o);
	return undef, $destinationStore, $bookError if defined $bookError;
	return if $booked;

	# Get
	my ($object, $getError) = $sourceStore->get($hash, $o);
	return undef, $sourceStore, $getError if defined $getError;
	return CDS::MissingObject->new($hash, $sourceStore) if ! defined $object;

	# Process children
	for my $child ($object->hashes) {
		my ($missing, $store, $error) = $o->recursiveTransfer($child, $sourceStore, $destinationStore, $done);
		return undef, $store, $error if defined $error;
		if (defined $missing) {
			push @$missing:path, $child;
			return $missing;
		}
	}

	# Put
	my $putError = $destinationStore->put($hash, $object, $o);
	return undef, $destinationStore, $putError if defined $putError;
	return;
}
