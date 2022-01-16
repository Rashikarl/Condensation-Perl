sub new($class, $keyPair, $store, $delegate) {
	my $o = bless {
		unsaved => CDS::Unsaved->new($store),
		delegate => $delegate,
		dataHandlers => {},
		hasChanges => 0,
		procured => 0,
		mergedEntries => [],
		};

	$o:privateBoxReader = CDS::PrivateBoxReader->new($keyPair, $store, $o);
	return $o;
}

sub delegate;
sub privateBoxReader;
sub unsaved;
sub hasChanges;
sub procured;

sub addDataHandler($o, $label, $dataHandler) {
	$o:dataHandlers->{$label} = $dataHandler;
}

sub removeDataHandler($o, $label, $dataHandler) {
	my $registered = $o:dataHandlers->{$label};
	return if $registered != $dataHandler;
	delete $o:dataHandlers->{$label};
}

# *** Procurement

sub procure($o, $interval) {
	my $now = CDS->now;
	return $o:procured if $o:procured + $interval > $now;
	$o:privateBoxReader->read // return;
	$o:procured = $now;
	return $now;
}

# *** Merging

sub onPrivateBoxEntry($o, $source, $envelope, $contentHashAndKey, $content) {
	for my $section ($content->children) {
		my $dataHandler = $o:dataHandlers->{$section->bytes} // next;
		$dataHandler->mergeData($section);
	}

	push @$o:mergedEntries, $source->hash;
}

sub onPrivateBoxInvalidEntry($o, $source, $reason) {
	$o:delegate->onPrivateRootReadingInvalidEntry($source, $reason);
	$source->discard;
}

# *** Saving

sub dataChanged($o) {
	$o:hasChanges = 1;
}

sub save($o, $entrustedKeys) {
	$o:unsaved->startSaving;
	return $o->savingSucceeded if ! $o:hasChanges;
	$o:hasChanges = 0;

	# Create the record
	my $record = CDS::Record->new;
	$record->add('created')->addInteger(CDS->now);
	$record->add('client')->add(CDS->version);
	for my $label (keys %$o:dataHandlers) {
		my $dataHandler = $o:dataHandlers->{$label};
		$dataHandler->addDataTo($record->add($label));
	}

	# Submit the object
	my $key = CDS->randomKey;
	my $object = $record->toObject->crypt($key);
	my $hash = $object->calculateHash;
	$o:unsaved->savingState->addObject($hash, $object);
	my $hashAndKey = CDS::HashAndKey->new($hash, $key);

	# Create the envelope
	my $keyPair = $o:privateBoxReader->keyPair;
	my $publicKeys = [$keyPair->publicKey, @$entrustedKeys];
	my $envelopeObject = $keyPair->createPrivateEnvelope($hashAndKey, $publicKeys)->toObject;
	my $envelopeHash = $envelopeObject->calculateHash;
	$o:unsaved->savingState->addObject($envelopeHash, $envelopeObject);

	# Transfer
	my ($missing, $store, $storeError) = $keyPair->transfer([$hash], $o:unsaved, $o:privateBoxReader->actorOnStore->store);
	return $o->savingFailed($missing) if defined $missing || defined $storeError;

	# Modify the private box
	my $modifications = CDS::StoreModifications->new;
	$modifications->add($keyPair->publicKey->hash, 'private', $envelopeHash, $envelopeObject);
	for my $hash (@$o:mergedEntries) {
		$modifications->remove($keyPair->publicKey->hash, 'private', $hash);
	}

	my $modifyError = $o:privateBoxReader->actorOnStore->store->modify($modifications, $keyPair);
	return $o->savingFailed if defined $modifyError;

	# Set the new merged hashes
	$o:mergedEntries = [$envelopeHash];
	return $o->savingSucceeded;
}

sub savingSucceeded($o) {
	# Discard all merged sources
	for my $source ($o:unsaved->savingState->mergedSources) {
		$source->discard;
	}

	# Call all data saved handlers
	for my $handler ($o:unsaved->savingState->dataSavedHandlers) {
		$handler->onDataSaved;
	}

	$o:unsaved->savingDone;
	return 1;
}

sub savingFailed($o, $missing) {	# private
	$o:unsaved->savingFailed;
	$o:hasChanges = 1;
	return undef, $missing;
}
