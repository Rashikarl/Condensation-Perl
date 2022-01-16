# A public key and a store.

sub new($class, $publicKey, $store) {
	return bless {
		publicKey => $publicKey,
		store => $store
		};
}

sub publicKey;
sub store;

sub equals($this, $that) {
	return 1 if ! defined $this && ! defined $that;
	return if ! defined $this || ! defined $that;
	return $this:store->id eq $that:store->id && $this:publicKey:hash->equals($that:publicKey:hash);
}
