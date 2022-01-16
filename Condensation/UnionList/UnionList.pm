# INCLUDE UnionList/Item.pm
# INCLUDE UnionList/Part.pm

sub new($class, $privateRoot, $label) {
	my $o = bless {
		privateRoot => $privateRoot,
		label => $label,
		unsaved => CDS::Unsaved->new($privateRoot->unsaved),
		items => {},
		parts => {},
		hasPartsToMerge => 0,
		}, $class;

	$o:unused = CDS::UnionList::Part->new;
	$o:changes = CDS::UnionList::Part->new;
	$privateRoot->addDataHandler($label, $o);
	return $o;
}

sub privateRoot;
sub unsaved;
sub items($o) { values %$o:items }
sub parts($o) { values %$o:parts }

sub get($o, $id) { $o:items->{$id} }

sub getOrCreate($o, $id) {
	my $item = $o:items->{$id};
	return $item if $item;
	my $newItem = $o->createItem($id);
	$o:items->{$id} = $newItem;
	return $newItem;
}

# abstract sub createItem($o, $id)
# abstract sub forgetObsoleteItems($o)

sub forget($o, $id) {
	my $item = $o:items->{$id} // return;
	$item:part:count -= 1;
	delete $o:items->{$id};
}

sub forgetItem($o, $item) {
	$item:part:count -= 1;
	delete $o:items->{$item->id};
}

# *** MergeableData interface

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

	my $keyPair = $o:privateRoot->privateBoxReader->keyPair;
	my ($missing, $transferStore, $storeError) = $keyPair->transfer([@hashes], $store, $o:privateRoot->unsaved);
	return if defined $storeError;
	return if $missing;

	if ($source) {
		$source->keep;
		$o:privateRoot->unsaved->state->addMergedSource($source);
	}

	$o->merge(@hashesAndKeys);
	return 1;
}

sub merge($o; @hashesAndKeys) {
	for my $hashAndKey (@_) {
		next if ! $hashAndKey;
		next if $o:parts->{$hashAndKey->hash->bytes};
		my $part = CDS::UnionList::Part->new;
		$part:hashAndKey = $hashAndKey;
		$o:parts->{$hashAndKey->hash->bytes} = $part;
		$o:hasPartsToMerge = 1;
	}
}

# *** Reading

sub read($o) {
	return 1 if ! $o:hasPartsToMerge;

	# Load the parts
	for my $part (values %$o:parts) {
		next if $part:isMerged;
		next if $part:loadedRecord;

		my ($record, $object, $invalidReason, $storeError) = $o:privateRoot->privateBoxReader->keyPair->getAndDecryptRecord($part:hashAndKey, $o:privateRoot->unsaved);
		return if defined $storeError;

		delete $o:parts->{$part:hashAndKey->hash->bytes} if defined $invalidReason;
		$part:loadedRecord = $record;
	}

	# Merge the loaded parts
	for my $part (values %$o:parts) {
		next if $part:isMerged;
		next if ! $part:loadedRecord;

		# Merge
		for my $child ($part:loadedRecord->children) {
			$o->mergeRecord($part, $child);
		}

		delete $part:loadedRecord;
		$part:isMerged = 1;
	}

	$o:hasPartsToMerge = 0;
	return 1;
}

# abstract sub mergeRecord($o, $part, $record)

# *** Saving

sub hasChanges($o) { $o:changes:count > 0 }

sub save($o) {
	$o->forgetObsoleteItems;
	$o:unsaved->startSaving;

	if ($o:changes:count) {
		# Take the changes
		my $newPart = $o:changes;
		$o:changes = CDS::UnionList::Part->new;

		# Add all changes
		my $record = CDS::Record->new;
		for my $item (values %$o:items) {
			next if $item:part != $newPart;
			$item->addToRecord($record);
		}

		# Select all parts smaller than 2 * count elements
		my $count = $newPart:count;
		while (1) {
			my $addedPart = 0;
			for my $part (values %$o:parts) {
				next if ! $part:isMerged || $part:selected || $part:count >= $count * 2;
				$count += $part:count;
				$part:selected = 1;
				$addedPart = 1;
			}

			last if ! $addedPart;
		}

		# Include the selected items
		for my $item (values %$o:items) {
			next if ! $item:part:selected;
			$item->setPart($newPart);
			$item->addToRecord($record);
		}

		# Serialize the new part
		my $key = CDS->randomKey;
		my $newObject = $record->toObject->crypt($key);
		my $newHash = $newObject->calculateHash;
		$newPart:hashAndKey = CDS::HashAndKey->new($newHash, $key);
		$newPart:isMerged = 1;
		$o:parts->{$newHash->bytes} = $newPart;
		$o:privateRoot->unsaved->state->addObject($newHash, $newObject);
		$o:privateRoot->dataChanged;
	}

	# Remove obsolete parts
	for my $part (values %$o:parts) {
		next if ! $part:isMerged;
		next if $part:count;
		delete $o:parts->{$part:hashAndKey->hash->bytes};
		$o:privateRoot->dataChanged;
	}

	# Propagate the unsaved state
	$o:privateRoot->unsaved->state->merge($o:unsaved->savingState);
	$o:unsaved->savingDone;
	return 1;
}
