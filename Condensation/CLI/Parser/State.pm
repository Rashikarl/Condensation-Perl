# A parser state denotes a possible current state (after having parsed a certain number of arguments).
# A parser keeps track of multiple states. When advancing, a state may disappear (if no possibility exists), or fan out (if multiple possibilities exist).
# A state is immutable.

sub new($class, $node, $previous, $arrow, $value, $warnings) {
	return bless {
		node => $node,			# current node
		previous => $previous,	# previous state
		arrow => $arrow,		# the arrow we took to get here
		value => $value,		# the value we collected with the last arrow
		warnings => $warnings,	# the warnings we collected with the last arrow
		cumulativeWeight => ($previous ? $previous->cumulativeWeight : 0) + ($arrow ? $arrow:weight : 0),	# the weight we collected until here
		};
}

sub node;
sub runHandler($o) { $o:node->getHandler }
sub isExecutable($o) { $o:node->getHandler ? 1 : 0 }
sub collectHandler($o) { $o:arrow ? $o:arrow:handler : undef }
sub label($o) { $o:arrow ? $o:arrow:label : 'cds' }
sub value;
sub arrow;
sub cumulativeWeight;

sub advance($o, $token) {
	my $arrows = [];
	$o:node->collectArrows($arrows);

	# Let the token know what possibilities we have
	for my $arrow (@$arrows) {
		$token->prepare($arrow:label);
	}

	# Ask the token to interpret the text
	my @states;
	for my $arrow (@$arrows) {
		my $value = $token->as($arrow:label) // next;
		push @states, CDS::Parser::State->new($arrow:node, $o, $arrow, $value, $token:warnings);
	}

	return @states;
}

sub complete($o, $token) {
	my $arrows = [];
	$o:node->collectArrows($arrows);

	# Let the token know what possibilities we have
	for my $arrow (@$arrows) {
		next if ! $arrow:official;
		$token->prepare($arrow:label);
	}

	# Ask the token to interpret the text
	for my $arrow (@$arrows) {
		next if ! $arrow:official;
		$token->complete($arrow:label);
	}

	return @$token:possibilities;
}

sub arrows($o) {
	my $arrows = [];
	$o:node->collectArrows($arrows);
	return @$arrows;
}

sub path($o) {
	my @path;
	my $state = $o;
	while ($state) {
		unshift @path, $state;
		$state = $state:previous;
	}
	return @path;
}

sub collect($o, $data) {
	for my $state ($o->path) {
		my $collectHandler = $state->collectHandler // next;
		&$collectHandler($data, $state->label, $state->value);
	}
}
