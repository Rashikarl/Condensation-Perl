# A store mapping objects and accounts to a group of stores.
use parent 'CDS::Store';

sub new($class, $key) {
	return bless {
		id => 'Split Store\n'.unpack('H*', CDS::C::aesCrypt(CDS->zeroCTR, $key, CDS->zeroCTR)),
		key => $key,
		accountStores => [],
		objectStores => [],
		};
}

sub id;

### Store configuration

sub assignAccounts($o, $fromIndex, $toIndex, $store) {
	for my $i ($fromIndex .. $toIndex) {
		$o:accountStores->[$i] = $store;
	}
}

sub assignObjects($o, $fromIndex, $toIndex, $store) {
	for my $i ($fromIndex .. $toIndex) {
		$o:objectStores->[$i] = $store;
	}
}

sub objectStore($o, $index) { $o:objectStores->[$index] }
sub accountStore($o, $index) { $o:accountStores->[$index] }

### Hash encryption

our $zeroCounter = "\0" x 16;

sub storeIndex($o, $hash) {
	# To avoid attacks on a single store, the hash is encrypted with a key known to the operator only
	my $encryptedBytes = CDS::C::aesCrypt(substr($hash->bytes, 0, 16), $o:key, $zeroCounter);

	# Use the first byte as store index
	return ord(substr($encryptedBytes, 0, 1));
}

### Store interface

sub get($o, $hash, $keyPair) {
	my $store = $o->objectStore($o->storeIndex($hash)) // return undef, 'No store assigned.';
	return $store->get($hash, $keyPair);
}

sub put($o, $hash, $object, $keyPair) {
	my $store = $o->objectStore($o->storeIndex($hash)) // return undef, 'No store assigned.';
	return $store->put($hash, $object, $keyPair);
}

sub book($o, $hash, $keyPair) {
	my $store = $o->objectStore($o->storeIndex($hash)) // return undef, 'No store assigned.';
	return $store->book($hash, $keyPair);
}

sub list($o, $accountHash, $boxLabel, $timeout, $keyPair) {
	my $store = $o->accountStore($o->storeIndex($accountHash)) // return undef, 'No store assigned.';
	return $store->list($accountHash, $boxLabel, $timeout, $keyPair);
}

sub add($o, $accountHash, $boxLabel, $hash, $keyPair) {
	my $store = $o->accountStore($o->storeIndex($accountHash)) // return 'No store assigned.';
	return $store->add($accountHash, $boxLabel, $hash, $keyPair);
}

sub remove($o, $accountHash, $boxLabel, $hash, $keyPair) {
	my $store = $o->accountStore($o->storeIndex($accountHash)) // return 'No store assigned.';
	return $store->remove($accountHash, $boxLabel, $hash, $keyPair);
}

sub modify($o, $modifications, $keyPair) {
	# Put objects
	my %objectsByStoreId;
	for my $entry (values %{$modifications->objects}) {
		my $store = $o->objectStore($o->storeIndex($entry:hash));
		my $target = $objectsByStoreId{$store->id};
		$objectsByStoreId{$store->id} = $target = {store => $store, modifications => CDS::StoreModifications->new};
		$target->modifications->put($entry:hash, $entry:object);
	}

	for my $item (values %objectsByStoreId) {
		my $error = $item:store->modify($item:modifications, $keyPair);
		return $error if $error;
	}

	# Add box entries
	my %additionsByStoreId;
	for my $operation (@{$modifications->additions}) {
		my $store = $o->accountStore($o->storeIndex($operation:accountHash));
		my $target = $additionsByStoreId{$store->id};
		$additionsByStoreId{$store->id} = $target = {store => $store, modifications => CDS::StoreModifications->new};
		$target->modifications->add($operation:accountHash, $operation:boxLabel, $operation:hash);
	}

	for my $item (values %additionsByStoreId) {
		my $error = $item:store->modify($item:modifications, $keyPair);
		return $error if $error;
	}

	# Remove box entries (but ignore errors)
	my %removalsByStoreId;
	for my $operation (@$modifications->removals) {
		my $store = $o->accountStore($o->storeIndex($operation:accountHash));
		my $target = $removalsByStoreId{$store->id};
		$removalsByStoreId{$store->id} = $target = {store => $store, modifications => CDS::StoreModifications->new};
		$target->modifications->add($operation:accountHash, $operation:boxLabel, $operation:hash);
	}

	for my $item (values %removalsByStoreId) {
		$item:store->modify($item:modifications, $keyPair);
	}

	return;
}
