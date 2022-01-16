use Encode;

sub root($class, $dataTree) {
	return bless {dataTree => $dataTree, id => 'ROOT', label => ''};
}

sub dataTree;
sub parent;
sub label;

sub child($o, $label) {
	return bless {
		dataTree => $o:dataTree,
		id => $o:id.'/'.unpack('H*', $label),
		parent => $o,
		label => $label,
		};
}

sub childWithText($o, $label) {
	return $o->child(Encode::encode_utf8($label // ''));
}

sub children($o) {
	my $item = $o:dataTree->get($o) // return;
	return map { $_:selector } @$item:children;
}

# Value

sub revision($o) {
	my $item = $o:dataTree->get($o) // return 0;
	return $item:revision;
}

sub isSet($o) {
	my $item = $o:dataTree->get($o) // return;
	return scalar $item:record->children > 0;
}

sub record($o) {
	my $item = $o:dataTree->get($o) // return CDS::Record->new;
	return $item:record;
}

sub set($o, $record // return) {
	my $now = CDS->now;
	my $item = $o:dataTree->getOrCreate($o);
	$item->mergeValue($o:dataTree:changes, $item:revision >= $now ? $item:revision + 1 : $now, $record);
}

sub merge($o, $revision, $record // return) {
	my $item = $o:dataTree->getOrCreate($o);
	return $item->mergeValue($o:dataTree:changes, $revision, $record);
}

sub clear($o) { $o->set(CDS::Record->new) }

sub clearInThePast($o) {
	$o->merge($o->revision + 1, CDS::Record->new) if $o->isSet;
}

sub forget($o) {
	my $item = $o:dataTree->get($o) // return;
	$item->forget;
}

sub forgetBranch($o) {
	for my $child ($o->children) { $child->forgetBranch; }
	$o->forget;
}

# Convenience methods (simple interface)

sub firstValue($o) {
	my $item = $o:dataTree->get($o) // return CDS::Record->new;
	return $item:record->firstChild;
}

sub bytesValue($o) { $o->firstValue->bytes }
sub hashValue($o) { $o->firstValue->hash }
sub textValue($o) { $o->firstValue->asText }
sub unsignedValue($o) { $o->firstValue->asUnsigned }
sub integerValue($o) { $o->firstValue->asInteger }
sub booleanValue($o) { $o->firstValue->asBoolean }
sub hashAndKeyValue($o) { $o->firstValue->asHashAndKey }

# Sets a new value unless the node has that value already.
sub setBytes($o, $bytes, $hash) {
	my $record = CDS::Record->new;
	$record->add($bytes, $hash);
	$o->set($record);
}

sub setHash($o, $hash) { $o->setBytes('', $hash); };
sub setText($o, $value, $hash) { $o->setBytes(Encode::encode_utf8($value), $hash); };
sub setBoolean($o, $value, $hash) { $o->setBytes(CDS->bytesFromBoolean($value), $hash); };
sub setInteger($o, $value, $hash) { $o->setBytes(CDS->bytesFromInteger($value), $hash); };
sub setUnsigned($o, $value, $hash) { $o->setBytes(CDS->bytesFromUnsigned($value), $hash); };
sub setHashAndKey($o, $hashAndKey) { $o->setBytes($hashAndKey->key, $hashAndKey->hash); };

# Adding objects and merged sources

sub addObject($o, $hash, $object) {
	$o:dataTree:unsaved->state->addObject($hash, $object);
}

sub addMergedSource($o, $hash) {
	$o:dataTree:unsaved->state->addMergedSource($hash);
}
