sub new($class) {
	return bless {
		objects => {},
		additions => [],
		removals => [],
		};
}

sub objects;
sub additions;
sub removals;

sub isEmpty($o) {
	return if scalar keys %$o:objects;
	return if scalar @$o:additions;
	return if scalar @$o:removals;
	return 1;
}

sub put($o, $hash, $object) {
	$o:objects->{$hash->bytes} = {hash => $hash, object => $object};
}

sub add($o, $accountHash, $boxLabel, $hash, $object) {
	$o->put($hash, $object) if $object;
	push @$o:additions, {accountHash => $accountHash, boxLabel => $boxLabel, hash => $hash};
}

sub remove($o, $accountHash, $boxLabel, $hash) {
	push @$o:removals, {accountHash => $accountHash, boxLabel => $boxLabel, hash => $hash};
}

sub executeIndividually($o, $store, $keyPair) {
	# Process objects
	for my $entry (values %$o:objects) {
		my $error = $store->put($entry:hash, $entry:object, $keyPair);
		return $error if $error;
	}

	# Process additions
	for my $entry (@$o:additions) {
		my $error = $store->add($entry:accountHash, $entry:boxLabel, $entry:hash, $keyPair);
		return $error if $error;
	}

	# Process removals (and ignore errors)
	for my $entry (@$o:removals) {
		$store->remove($entry:accountHash, $entry:boxLabel, $entry:hash, $keyPair);
	}

	return;
}

# Returns a text representation of box additions and removals.
sub toRecord($o) {
	my $record = CDS::Record->new;

	# Objects
	my $objectsRecord = $record->add('put');
	for my $entry (values %$o:objects) {
		$objectsRecord->add($entry:hash->bytes)->add($entry:object->bytes);
	}

	# Box additions and removals
	&addEntriesToRecord($o:additions, $record->add('add'));
	&addEntriesToRecord($o:removals, $record->add('remove'));

	return $record;
}

sub addEntriesToRecord($unsortedEntries, $record) {	# private
	my @additions = sort { ($a:accountHash->bytes cmp $b:accountHash->bytes) || ($a:boxLabel cmp $b:boxLabel) } @$unsortedEntries;
	my $entry = shift @additions;
	while (defined $entry) {
		my $accountHash = $entry:accountHash;
		my $accountRecord = $record->add($accountHash->bytes);

		while (defined $entry && $entry:accountHash->bytes eq $accountHash->bytes) {
			my $boxLabel = $entry:boxLabel;
			my $boxRecord = $accountRecord->add($boxLabel);

			while (defined $entry && $entry:boxLabel eq $boxLabel) {
				$boxRecord->add($entry:hash->bytes);
				$entry = shift @additions;
			}
		}
	}
}

sub fromBytes($class, $bytes) {
	my $object = CDS::Object->fromBytes($bytes) // return;
	my $record = CDS::Record->fromObject($object) // return;
	return $class->fromRecord($record);
}

sub fromRecord($class, $record) {
	my $modifications = $class->new;

	# Read objects (and "envelopes" entries used before 2022-01)
	for my $objectRecord ($record->child('put')->children, $record->child('envelopes')->children) {
		my $hash = CDS::Hash->fromBytes($objectRecord->bytes) // return;
		my $object = CDS::Object->fromBytes($objectRecord->firstChild->bytes) // return;
		#return if $o:checkEnvelopeHash && ! $object->calculateHash->equals($hash);
		$modifications->put($hash, $object);
	}

	# Read additions and removals
	&readEntriesFromRecord($modifications:additions, $record->child('add')) // return;
	&readEntriesFromRecord($modifications:removals, $record->child('remove')) // return;

	return $modifications;
}

sub readEntriesFromRecord($entries, $record) {	# private
	for my $accountHashRecord ($record->children) {
		my $accountHash = CDS::Hash->fromBytes($accountHashRecord->bytes) // return;
		for my $boxLabelRecord ($accountHashRecord->children) {
			my $boxLabel = $boxLabelRecord->bytes;
			return if ! CDS->isValidBoxLabel($boxLabel);

			for my $hashRecord ($boxLabelRecord->children) {
				my $hash = CDS::Hash->fromBytes($hashRecord->bytes) // return;
				push @$entries, {accountHash => $accountHash, boxLabel => $boxLabel, hash => $hash};
			}
		}
	}

	return 1;
}
