use parent 'CDS::Document';

sub new($class, $privateRoot, $label) {
	my $o = $class->SUPER::new($privateRoot->privateBoxReader->keyPair, $privateRoot->unsaved);
	$o:privateRoot = $privateRoot;
	$o:label = $label;
	$privateRoot->addDataHandler($label, $o);

	# State
	$o:dataSharingMessage = undef;
	return $o;
}

sub privateRoot;
sub label;

sub savingDone($o, $revision, $newPart, $obsoleteParts) {
	$o:privateRoot->unsaved->state->merge($o:unsaved->savingState);
	$o:unsaved->savingDone;
	$o:privateRoot->dataChanged if $newPart || scalar @$obsoleteParts;
}

sub addDataTo($o, $record) {
	for my $part (sort { $a:hashAndKey->hash->bytes cmp $b:hashAndKey->hash->bytes } values %$o:parts) {
		$record->addHashAndKey($part:hashAndKey);
	}
}
sub mergeData($o, $record) {
	my @hashesAndKeys;
	for my $child ($record->children) {
		push @hashesAndKeys, $child->asHashAndKey // next;
	}

	$o->merge(@hashesAndKeys);
}

sub mergeExternalData($o, $store, $record, $source) {
	my @hashes;
	my @hashesAndKeys;
	for my $child ($record->children) {
		my $hashAndKey = $child->asHashAndKey // next;
		next if $o:parts->{$hashAndKey->hash->bytes};
		push @hashes, $hashAndKey->hash;
		push @hashesAndKeys, $hashAndKey;
	}

	my ($missing, $transferStore, $storeError) = $o:keyPair->transfer([@hashes], $store, $o:privateRoot->unsaved);
	return if defined $storeError;
	return if $missing;

	if ($source) {
		$source->keep;
		$o:privateRoot->unsaved->state->addMergedSource($source);
	}

	$o->merge(@hashesAndKeys);
	return 1;
}
