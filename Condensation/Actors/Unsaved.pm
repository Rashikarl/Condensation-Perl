# INCLUDE Unsaved/State.pm
use parent 'CDS::Store';

sub new($class, $store) {
	return bless {
		state => CDS::Unsaved::State->new,
		savingState => undef,
		store => $store,
		};
}

sub state;
sub savingState;

# *** Saving, state propagation

sub isSaving($o) { defined $o:savingState }

sub startSaving($o) {
	die 'Start saving, but already saving' if $o:savingState;
	$o:savingState = $o:state;
	$o:state = CDS::Unsaved::State->new;
}

sub savingDone($o) {
	die 'Not in saving state' if ! $o:savingState;
	$o:savingState = undef;
}

sub savingFailed($o) {
	die 'Not in saving state' if ! $o:savingState;
	$o:state->merge($o:savingState);
	$o:savingState = undef;
}

# *** Store interface

sub id($o) { 'Unsaved'."\n".unpack('H*', CDS->randomBytes(16))."\n".$o:store->id }

sub get($o, $hash, $keyPair) {
	my $stateObject = $o:state:objects->{$hash->bytes};
	return $stateObject:object if $stateObject;

	if ($o:savingState) {
		my $savingStateObject = $o:savingState:objects->{$hash->bytes};
		return $savingStateObject:object if $savingStateObject;
	}

	return $o:store->get($hash, $keyPair);
}

sub book($o, $hash, $keyPair) {
	return $o:store->book($hash, $keyPair);
}

sub put($o, $hash, $object, $keyPair) {
	return $o:store->put($hash, $object, $keyPair);
}

sub list($o, $accountHash, $boxLabel, $timeout, $keyPair) {
	return $o:store->list($accountHash, $boxLabel, $timeout, $keyPair);
}

sub modify($o, $additions, $removals, $keyPair) {
	return $o:store->modify($additions, $removals, $keyPair);
}
