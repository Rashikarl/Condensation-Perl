sub create($class) {
	return CDS::InMemoryStore->new('inMemoryStore:'.unpack('H*', CDS->randomBytes(16)));
}

sub new($o, $id) {
	return bless {
		id => $id,
		objects => {},
		accounts => {},
		};
}

sub id;

sub accountForWriting($o, $hash) {
	my $account = $o:accounts->{$hash->bytes};
	return $account if $account;
	return $o:accounts->{$hash->bytes} = {messages => {}, private => {}, public => {}};
}

# *** Store interface

sub get($o, $hash, $keyPair) {
	my $entry = $o:objects->{$hash->bytes} // return;
	return $entry:object;
}

sub book($o, $hash, $keyPair) {
	my $entry = $o:objects->{$hash->bytes} // return;
	$entry:booked = CDS->now;
	return 1;
}

sub put($o, $hash, $object, $keyPair) {
	$o:objects->{$hash->bytes} = {object => $object, booked => CDS->now};
	return;
}

sub list($o, $accountHash, $boxLabel, $timeout, $keyPair) {
	my $account = $o:accounts->{$accountHash->bytes} // return [];
	my $box = $account->{$boxLabel} // return undef, 'Invalid box label.';
	return values %$box;
}

sub add($o, $accountHash, $boxLabel, $hash, $keyPair) {
	my $box = $o->accountForWriting($accountHash)->{$boxLabel} // return;
	$box->{$hash->bytes} = $hash;
}

sub remove($o, $accountHash, $boxLabel, $hash, $keyPair) {
	my $box = $o->accountForWriting($accountHash)->{$boxLabel} // return;
	delete $box->{$hash->bytes};
}

sub modify($o, $modifications, $keyPair) {
	return $modifications->executeIndividually($o, $keyPair);
}

# Garbage collection

sub collectGarbage($o, $graceTime) {
	# Mark all objects as not used
	for my $entry (values @$o:objects) {
		$entry:inUse = 0;
	}

	# Mark all objects newer than the grace time
	for my $entry (values @$o:objects) {
		$o->markEntry($entry) if $entry:booked > $graceTime;
	}

	# Mark all objects referenced from a box
	for my $account (values @$o:accounts) {
		for my $hash (values @$account:messages) { $o->markHash($hash); }
		for my $hash (values @$account:private) { $o->markHash($hash); }
		for my $hash (values @$account:public) { $o->markHash($hash); }
	}

	# Remove empty accounts
	while (my ($key, $account) = each %$o:accounts) {
		next if scalar @$account:messages;
		next if scalar @$account:private;
		next if scalar @$account:public;
		delete $o:accounts->{$key};
	}

	# Remove obsolete objects
	while (my ($key, $entry) = each %$o:objects) {
		next if $entry:inUse;
		delete $o:objects->{$key};
	}
}

sub markHash($o, $hash) {		# private
	my $child = $o:objects->{$hash->bytes} // return;
	$o->mark($child);
}

sub markEntry($o, $entry) {		# private
	return if $entry:inUse;
	$entry:inUse = 1;

	# Mark all children
	for my $hash ($entry:object->hashes) {
		$o->markHash($hash);
	}
}
