# The result of parsing an ACTORGROUP token (see Token.pm).

sub new($class, $label, $actorGroup) {
	return bless {
		label => $label,
		actorGroup => $actorGroup,
		};
}

sub label;
sub actorGroup;
