sub new($class, $selector) {
	my $parentSelector = $selector->parent;
	my $parent = $parentSelector ? $selector->dataTree->getOrCreate($parentSelector) : undef;

	my $o = bless {
		dataTree => $selector->dataTree,
		selector => $selector,
		parent => $parent,
		children => [],
		part => undef,
		revision => 0,
		record => CDS::Record->new
		};

	push @$parent:children, $o if $parent;
	return $o;
}

sub pruneTree($o) {
	# Try to remove children
	for my $child (@$o:children) { $child->pruneTree; }

	# Don't remove the root item
	return if ! $o:parent;

	# Don't remove if the item has children, or a value
	return if scalar @$o:children;
	return if $o:revision > 0;

	# Remove this from the tree
	$o:parent:children = [grep { $_ != $o } @$o:parent:children];

	# Remove this from the datatree hash
	delete $o:dataTree:itemsBySelector->{$o:selector:id};
}

# Low-level part change.
sub setPart($o, $part) {
	$o:part:count -= 1 if $o:part;
	$o:part = $part;
	$o:part:count += 1 if $o:part;
}

# Merge a value

sub mergeValue($o, $part, $revision, $record) {
	return if $revision <= 0;
	return if $revision < $o:revision;
	return if $revision == $o:revision && $part:size < $o:part:size;
	$o->setPart($part);
	$o:revision = $revision;
	$o:record = $record;
	$o:dataTree->dataChanged;
	return 1;
}

sub forget($o) {
	return if $o:revision <= 0;
	$o:revision = 0;
	$o:record = CDS::Record->new;
	$o->setPart;
}

# Saving

sub createSaveRecord($o) {
	return $o:saveRecord if $o:saveRecord;
	$o:saveRecord = $o:parent ? $o:parent->createSaveRecord->add($o:selector:label) : CDS::Record->new('root');
	if ($o:part:selected) {
		CDS->log('Item saving zero revision of ', $o:selector->label) if $o:revision <= 0;
		$o:saveRecord->addInteger($o:revision)->addRecord($o:record->children);
	} else {
		$o:saveRecord->add('');
	}
	return $o:saveRecord;
}

sub detachSaveRecord($o) {
	return if ! $o:saveRecord;
	delete $o:saveRecord;
	$o:parent->detachSaveRecord if $o:parent;
}
