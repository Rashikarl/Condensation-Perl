# The result of parsing an ACCOUNT token (see Token.pm).

sub new($class, $cliStore, $actorHash) {
	return bless {
		cliStore => $cliStore,
		actorHash => $actorHash,
		};
}

sub cliStore;
sub actorHash;
sub url($o) { $o:cliStore->url.'/accounts/'.$o:actorHash->hex }
