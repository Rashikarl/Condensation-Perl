use parent 'CDS::Document';

sub new($class, $parentSelector) {
	my $o = $class->SUPER::new($parentSelector->document->keyPair, $parentSelector->document->unsaved);
	$o:parentSelector = $parentSelector;
	return $o;
}

sub parentSelector;

sub partSelector($o, $hashAndKey) {
	$o:parentSelector->child(substr($hashAndKey->hash->bytes, 0, 16));
}

sub read($o) {
	$o->merge(map { $_->hashAndKeyValue } $o:parentSelector->children);
	return $o->SUPER::read;
}

sub savingDone($o, $revision, $newPart, $obsoleteParts) {
	$o:parentSelector->document->unsaved->state->merge($o:unsaved->savingState);

	# Remove obsolete parts
	for my $part (@$obsoleteParts) {
		$o->partSelector($part:hashAndKey)->merge($revision, CDS::Record->new);
	}

	# Add the new part
	if ($newPart) {
		my $record = CDS::Record->new;
		$record->addHashAndKey($newPart:hashAndKey);
		$o->partSelector($newPart:hashAndKey)->merge($revision, $record);
	}

	$o:unsaved->savingDone;
}
