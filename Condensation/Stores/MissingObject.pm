sub new($class, $hash, $store) {
	return bless {hash => $hash, store => $store, path => [], context => undef};
}

sub hash;
sub store;
sub path($o) { @$o:path }
sub context;
