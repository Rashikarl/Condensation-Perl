# Nodes and arrows define the graph on which the parse state can move.

sub new($class, $endProposals, $handler) {
	return bless {
		arrows => [],					# outgoing arrows
		defaults => [],					# default nodes, at which the current state could be as well
		endProposals => $endProposals,	# if set, the proposal search algorithm stops at this node
		handler => $handler,			# handler to be executed if parsing ends here
		};
}

sub endProposals;

# Adds an arrow.
sub addArrow($o, $to, $official, $weight, $label, $handler) {
	push @$o:arrows, CDS::Parser::Arrow->new($to, $official, $weight, $label, $handler);
}

# Adds a default node.
sub addDefault($o, $node) {
	push @$o:defaults, $node;
}

sub collectArrows($o, $arrows) {
	push @$arrows, @$o:arrows;
	for my $default (@$o:defaults) { $default->collectArrows($arrows); }
}

sub hasHandler($o) {
	return 1 if $o:handler;
	for my $default (@$o:defaults) { return 1 if $default->hasHandler; }
	return;
}

sub getHandler($o) {
	return $o:handler if $o:handler;
	for my $default (@$o:defaults) {
		my $handler = $default->getHandler // next;
		return $handler;
	}
	return;
}
