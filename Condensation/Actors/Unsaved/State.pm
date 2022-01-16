sub new($class) {
	return bless {
		objects => {},
		mergedSources => [],
		dataSavedHandlers => [],
		};
}

sub objects;
sub mergedSources($o) { @$o:mergedSources }
sub dataSavedHandlers($o) { @$o:dataSavedHandlers }

sub addObject($o, $hash, $object) {
	$o:objects->{$hash->bytes} = {hash => $hash, object => $object};
}

sub addMergedSource($o; @sources) {
	push @$o:mergedSources, @_;
}

sub addDataSavedHandler($o; @handlers) {
	push @$o:dataSavedHandlers, @_;
}

sub merge($o, $state) {
	for my $key (keys %$state:objects) {
		$o:objects->{$key} = $state:objects->{$key};
	}

	push @$o:mergedSources, @$state:mergedSources;
	push @$o:dataSavedHandlers, @$state:dataSavedHandlers;
}
