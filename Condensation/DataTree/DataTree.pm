# INCLUDE DataTree/Item.pm
# INCLUDE DataTree/Part.pm

sub new($class, $keyPair, $store) {
	my $o = bless {
		keyPair => $keyPair,
		unsaved => CDS::Unsaved->new($store),
		itemsBySelector => {},
		parts => {},
		hasPartsToMerge => 0,
		}, $class;

	$o:root = CDS::Selector->root($o);
	$o:changes = CDS::DataTree::Part->new;
	return $o;
}

sub keyPair;
sub unsaved;
sub parts($o) { values %$o:parts }
sub hasPartsToMerge;

### Items

sub root;
sub rootItem($o) { $o->getOrCreate($o:root) }

sub get($o, $selector) { $o:itemsBySelector->{$selector:id} }

sub getOrCreate($o, $selector) {
	my $item = $o:itemsBySelector->{$selector:id};
	$o:itemsBySelector->{$selector:id} = $item = CDS::DataTree::Item->new($selector) if ! $item;
	return $item;
}

sub prune($o) { $o->rootItem->pruneTree; }

### Merging

sub merge($o; @hashesAndKeys) {
	for my $hashAndKey (@_) {
		next if ! $hashAndKey;
		next if $o:parts->{$hashAndKey->hash->bytes};
		my $part = CDS::DataTree::Part->new;
		$part:hashAndKey = $hashAndKey;
		$o:parts->{$hashAndKey->hash->bytes} = $part;
		$o:hasPartsToMerge = 1;
	}
}

sub read($o) {
	return 1 if ! $o:hasPartsToMerge;

	# Load the parts
	for my $part (values %$o:parts) {
		next if $part:isMerged;
		next if $part:loadedRecord;

		my ($record, $object, $invalidReason, $storeError) = $o:keyPair->getAndDecryptRecord($part:hashAndKey, $o:unsaved);
		return if defined $storeError;

		delete $o:parts->{$part:hashAndKey->hash->bytes} if defined $invalidReason;
		$part:loadedRecord = $record;
	}

	# Merge the loaded parts
	for my $part (values %$o:parts) {
		next if $part:isMerged;
		next if ! $part:loadedRecord;
		my $oldFormat = $part:loadedRecord->child('client')->textValue =~ /0.19/ ? 1 : 0;
		$o->mergeNode($part, $o:root, $part:loadedRecord->child('root'), $oldFormat);
		delete $part:loadedRecord;
		$part:isMerged = 1;
	}

	$o:hasPartsToMerge = 0;
	return 1;
}

sub mergeNode($o, $part, $selector, $record, $oldFormat) {
	# Prepare
	my @children = $record->children;
	return if ! scalar @children;
	my $item = $o->getOrCreate($selector);

	# Merge value
	my $valueRecord = shift @children;
	$valueRecord = $valueRecord->firstChild if $oldFormat;
	$item->mergeValue($part, $valueRecord->asInteger, $valueRecord);

	# Merge children
	for my $child (@children) { $o->mergeNode($part, $selector->child($child->bytes), $child, $oldFormat); }
}

# *** Saving
# Call $dataTree->save at any time to save the current state (if necessary).

# This is called by the items whenever some data changes.
sub dataChanged($o) { }

sub save($o) {
	$o:unsaved->startSaving;
	my $revision = CDS->now;
	my $newPart = undef;

	#-- saving ++ $o:changes:count
	if ($o:changes:count) {
		# Take the changes
		$newPart = $o:changes;
		$o:changes = CDS::DataTree::Part->new;

		# Select all parts smaller than 2 * changes
		$newPart:selected = 1;
		my $count = $newPart:count;
		while (1) {
			my $addedPart = 0;
			for my $part (values %$o:parts) {
				#-- candidate ++ $part:count ++ $count
				next if ! $part:isMerged || $part:selected || $part:count >= $count * 2;
				$count += $part:count;
				$part:selected = 1;
				$addedPart = 1;
			}

			last if ! $addedPart;
		}

		# Include the selected items
		for my $item (values %$o:itemsBySelector) {
			next if ! $item:part:selected;
			$item->setPart($newPart);
			$item->createSaveRecord;
		}

		my $record = CDS::Record->new;
		$record->add('created')->addInteger($revision);
		$record->add('client')->add(CDS->version);
		$record->addRecord($o->rootItem->createSaveRecord);

		# Detach the save records
		for my $item (values %$o:itemsBySelector) {
			$item->detachSaveRecord;
		}

		# Serialize and encrypt the record
		my $key = CDS->randomKey;
		my $newObject = $record->toObject->crypt($key);
		$newPart:hashAndKey = CDS::HashAndKey->new($newObject->calculateHash, $key);
		$newPart:isMerged = 1;
		$newPart:selected = 0;
		$o:parts->{$newPart:hashAndKey->hash->bytes} = $newPart;
		#-- added ++ $o:parts ++ scalar keys %$o:parts ++ $newPart:count
		$o:unsaved:savingState->addObject($newPart:hashAndKey->hash, $newObject);
	}

	# Remove obsolete parts
	my $obsoleteParts = [];
	for my $part (values %$o:parts) {
		next if ! $part:isMerged;
		next if $part:count;
		push @$obsoleteParts, $part;
		delete $o:parts->{$part:hashAndKey->hash->bytes};
	}

	# Commit
	#-- saving done ++ $revision ++ $newPart ++ $obsoleteParts
	return $o->savingDone($revision, $newPart, $obsoleteParts);
}
