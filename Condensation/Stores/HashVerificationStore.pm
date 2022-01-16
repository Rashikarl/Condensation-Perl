# A store that verifies retrieved objects.
use parent 'CDS::Store';

sub new($class, $store) {
	return bless {
		id => "Hash Verification Store\n".$store->id,
		store => $store,
		};
}

sub id;
sub store;

sub get($o, $hash, $keyPair) {
	my ($object, $error) = $o:store->get($hash, $keyPair);
	return undef, $error if defined $error;
	return undef, undef if ! defined $object;
	return undef, 'Hash mismatch.' if ! CDS::Hash->equals($object->calculateHash, $hash);
	return $object, $error;
}

sub put($o; $hash, $object, $keyPair) { $o:store->put(@_); }
sub book($o; $hash, $keyPair) { $o:store->book(@_); }
sub list($o; $accountHash, $boxLabel, $timeout, $keyPair) { $o:store->list(@_); }
sub add($o; $accountHash, $boxLabel, $hash, $keyPair) { $o:store->add(@_); }
sub remove($o; $accountHash, $boxLabel, $hash, $keyPair) { $o:store->remove(@_); }
sub modify($o; $modifications, $keyPair) { $o:store->modify(@_); }
