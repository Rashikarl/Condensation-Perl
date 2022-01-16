# The result of parsing an OBJECT token.

sub new($class, $cliStore, $hash) {
	return bless {
		cliStore => $cliStore,
		hash => $hash,
		};
}

sub cliStore;
sub hash;
sub url($o) { $o:cliStore->url.'/objects/'.$o:hash->hex }
