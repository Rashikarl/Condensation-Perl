sub new($class, $node, $revision, $status) {
	bless {
		node => $node,
		revision => $revision,
		status => $status,
		};
}

sub node;
sub revision;
sub status;
