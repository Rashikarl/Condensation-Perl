# The result of parsing a BOX token (see Token.pm).

sub new($class, $accountToken, $boxLabel) {
	return bless {
		accountToken => $accountToken,
		boxLabel => $boxLabel
		};
}

sub accountToken;
sub boxLabel;
sub url($o) { $o:accountToken->url.'/'.$o:boxLabel }
