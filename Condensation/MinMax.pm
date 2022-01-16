# EXTEND CDS

sub min($class; @numbers) {
	my $min = shift;
	for my $number (@_) {
		$min = $min < $number ? $min : $number;
	}

	return $min;
}

sub max($class; @numbers) {
	my $max = shift;
	for my $number (@_) {
		$max = $max > $number ? $max : $number;
	}

	return $max;
}

sub booleanCompare($class, $a, $b) { $a && $b ? 0 : $a ? 1 : $b ? -1 : 0 }
