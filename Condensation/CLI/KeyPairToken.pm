# The result of parsing a KEYPAIR token (see Token.pm).

sub new($class, $file, $keyPair) {
	return bless {
		file => $file,
		keyPair => $keyPair,
		};
}

sub file;
sub keyPair;
