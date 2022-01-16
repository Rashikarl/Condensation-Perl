sub collect($class, $states) {
	my $o = bless {possibilities => {}};

	my $visitedNodes = {};
	for my $state (@$states) {
		$o->visit($visitedNodes, $state->node, '');
	}

	for my $possibility (keys %$o:possibilities) {
		delete $o:possibilities->{$possibility} if exists $o:possibilities->{$possibility.' …'};
	}

	return sort keys %$o:possibilities;
}

sub visit($o, $visitedNodes, $node, $text) {
	$visitedNodes->{$node} = 1;

	my $arrows = [];
	$node->collectArrows($arrows);

	for my $arrow (@$arrows) {
		next if ! $arrow:official;

		my $text = $text.' '.$arrow:label;
		$o:possibilities->{$text} = 1 if $arrow:node->hasHandler;
		if ($arrow:node->endProposals || exists $visitedNodes->{$arrow:node}) {
			$o:possibilities->{$text . ($o->canContinue($arrow:node) ? ' …' : '')} = 1;
			next;
		}

		$o->visit($visitedNodes, $arrow:node, $text);
	}

	delete $visitedNodes->{$node};
}

sub canContinue($o, $node) {
	my $arrows = [];
	$node->collectArrows($arrows);

	for my $arrow (@$arrows) {
		next if ! $arrow:official;
		return 1;
	}

	return;
}
