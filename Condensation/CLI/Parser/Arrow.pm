# An arrow points from one node to another. The arrow is taken in State::advance if the next argument matches to the label.

sub new($class, $node, $official, $weight, $label, $handler) {
	return bless {
		node => $node,				# target node
		official => $official,		# whether to show this arrow with '?'
		weight => $weight,			# weight
		label => $label,			# label
		handler => $handler,		# handler to invoke if we take this arrow
		};
}
