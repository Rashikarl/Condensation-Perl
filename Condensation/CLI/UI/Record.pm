# Displays a record, and tries to guess the byte interpretation

sub display($class, $ui, $record, $storeUrl) {
	my $o = bless {
		ui => $ui,
		onStore => defined $storeUrl ? $ui->gray(' on ', $storeUrl) : '',
		};

	$o->record($record, '');
}

sub record($o, $record, $context) {
	my $bytes = $record->bytes;
	my $hash = $record->hash;
	my @children = $record->children;

	# Try to interpret the key / value pair with a set of heuristic rules
	my @value =
		! length $bytes && $hash ? ($o:ui->gold('cds show record '), $hash->hex, $o:onStore) :
		! length $bytes ? $o:ui->gray('empty') :
		length $bytes == 32 && $hash ? ($o:ui->gold('cds show record '), $hash->hex, $o:onStore, $o:ui->gold(' decrypted with ', unpack('H*', $bytes))) :
		$context eq 'e' ? $o->hexValue($bytes) :
		$context eq 'n' ? $o->hexValue($bytes) :
		$context eq 'p' ? $o->hexValue($bytes) :
		$context eq 'q' ? $o->hexValue($bytes) :
		$context eq 'encrypted for' ? $o->hexValue($bytes) :
		$context eq 'updated by' ? $o->hexValue($bytes) :
		$context =~ /(^| )id( |$)/ ? $o->hexValue($bytes) :
		$context =~ /(^| )key( |$)/ ? $o->hexValue($bytes) :
		$context =~ /(^| )signature( |$)/ ? $o->hexValue($bytes) :
		$context =~ /(^| )revision( |$)/ ? $o->revisionValue($bytes) :
		$context =~ /(^| )date( |$)/ ? $o->dateValue($bytes) :
		$context =~ /(^| )expires( |$)/ ? $o->dateValue($bytes) :
			$o->guessValue($bytes);

	push @value, ' ', $o:ui->blue($hash->hex), $o:onStore if $hash && ($bytes && length $bytes != 32);
	$o:ui->line(@value);

	# Children
	$o:ui->pushIndent;
	for my $child (@children) { $o->record($child, $bytes); }
	$o:ui->popIndent;
}

sub hexValue($o, $bytes) {
	my $length = length $bytes;
	return '#'.unpack('H*', substr($bytes, 0, $length)) if $length <= 64;
	return '#'.unpack('H*', substr($bytes, 0, 64)), '…', $o:ui->gray(' (', $length, ' bytes)');
}

sub guessValue($o, $bytes) {
	my $length = length $bytes;
	my $text = $length > 64 ? substr($bytes, 0, 64).'…' : $bytes;
	$text =~ s/[\x00-\x1f\x7f-\xff]/·/g;
	my @value = ($text);

	if ($length <= 8) {
		my $integer = CDS->integerFromBytes($bytes);
		push @value, $o:ui->gray(' = ', $integer, $o->looksLikeTimestamp($integer) ? ' = '.$o:ui->niceDateTime($integer).' = '.$o:ui->niceDateTimeLocal($integer) : '');
	}

	push @value, $o:ui->gray(' = ', CDS::Hash->fromBytes($bytes)->hex) if $length == 32;
	push @value, $o:ui->gray(' (', length $bytes, ' bytes)') if length $bytes > 64;
	return @value;
}

sub dateValue($o, $bytes) {
	my $integer = CDS->integerFromBytes($bytes);
	return $integer if ! $o->looksLikeTimestamp($integer);
	return $o:ui->niceDateTime($integer), '  ', $o:ui->gray($o:ui->niceDateTimeLocal($integer));
}

sub revisionValue($o, $bytes) {
	my $integer = CDS->integerFromBytes($bytes);
	return $integer if ! $o->looksLikeTimestamp($integer);
	return $o:ui->niceDateTime($integer);
}

sub looksLikeTimestamp($o, $integer) {
	return $integer > 100000000000 && $integer < 10000000000000;
}
