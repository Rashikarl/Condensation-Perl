# EXTEND CDS

# Checks if a box label is valid.
sub isValidBoxLabel($class, $label) { $label eq 'messages' || $label eq 'private' || $label eq 'public' }

# Groups box additions or removals by account hash and box label.
sub groupedBoxOperations($class, $operations) {
	my %byAccountHash;
	for my $operation (@$operations) {
		my $accountHashBytes = $operation:accountHash->bytes;
		$byAccountHash{$accountHashBytes} = {accountHash => $operation:accountHash, byBoxLabel => {}} if ! exists $byAccountHash{$accountHashBytes};
		my $byBoxLabel = $byAccountHash{$accountHashBytes}->{byBoxLabel};
		my $boxLabel = $operation:boxLabel;
		$byBoxLabel->{$boxLabel} = [] if ! exists $byBoxLabel->{$boxLabel};
		push @{$byBoxLabel->{$boxLabel}}, $operation;
	}

	return values %byAccountHash;
}
