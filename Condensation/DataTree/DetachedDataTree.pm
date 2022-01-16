use parent 'CDS::DataTree';

sub new($class, $keyPair) {
	return $class->SUPER::new($keyPair, CDS::InMemoryStore->create);
}

sub savingDone($o, $revision, $newPart, $obsoleteParts) {
	# We don't do anything
	$o:unsaved->savingDone;
}
