sub new($class, $ui, $bytes) {
	return bless {ui => $ui, bytes => $bytes, styleChanges => [], };
}

sub reset { chr(0x1b).'[0m' }
sub foreground($o, $color) { chr(0x1b).'[0;38;5;'.$color.'m' }

sub changeStyle($o; @changes) {
	push @$o:styleChanges, @_;
}

sub styleHashList($o, $offset) {
	my $hashesCount = unpack('L>', substr($o:bytes, $offset, 4));
	my $dataStart = $offset + 4 + $hashesCount  * 32;
	return $offset if $dataStart > length $o:bytes;

	# Styles
	my $darkGreen = $o->foreground(28);
	my $green0 = $o->foreground(40);
	my $green1 = $o->foreground(34);

	# Color the hash count
	my $pos = $offset;
	$o->changeStyle({at => $pos, style => $darkGreen, breakBefore => 1});
	$pos += 4;

	# Color the hashes
	my $alternate = 0;
	while ($hashesCount) {
		$o->changeStyle({at => $pos, style => $alternate ? $green1 : $green0, breakBefore => 1});
		$pos += 32;
		$alternate = 1 - $alternate;
		$hashesCount -= 1;
	}

	return $dataStart;
}

sub styleRecord($o, $offset) {
	# Styles
	my $blue = $o->foreground(33);
	my $black = $o->reset;
	my $violet = $o->foreground(93);
	my @styleChanges;

	# Prepare
	my $pos = $offset;
	my $hasError = 0;
	my $level = 0;

	my $use = sub($length) {
		my $start = $pos;
		$pos += $length;
		return substr($o:bytes, $start, $length) if $pos <= length $o:bytes;
		$hasError = 1;
		return;
	};

	my $readUnsigned8 = sub { unpack('C', &$use(1) // return) };
	my $readUnsigned32 = sub { unpack('L>', &$use(4) // return) };
	my $readUnsigned64 = sub { unpack('Q>', &$use(8) // return) };

	# Parse all record nodes
	while ($level >= 0) {
		# Flags
		push @styleChanges, {at => $pos, style => $blue, breakBefore => 1};
		my $flags = &$readUnsigned8 // last;

		# Data
		my $length = $flags & 0x1f;
		my $byteLength = $length == 30 ? 30 + (&$readUnsigned8 // last) : $length == 31 ? (&$readUnsigned64 // last) : $length;

		if ($byteLength) {
			push @styleChanges, {at => $pos, style => $black};
			&$use($byteLength) // last;
		}

		if ($flags & 0x20) {
			push @styleChanges, {at => $pos, style => $violet};
			&$readUnsigned32 // last;
		}

		# Children
		$level += 1 if $flags & 0x40;
		$level -= 1 if ! ($flags & 0x80);
	}

	# Don't apply any styles if there are errors
	$hasError = 1 if $pos != length $o:bytes;
	return $offset if $hasError;

	$o->changeStyle(@styleChanges);
	return $pos;
}

sub display($o) {
	$o:ui->valueIndent(8);

	my $resetStyle = chr(0x1b).'[0m';
	my $length = length($o:bytes);
	my $lineStart = 0;
	my $currentStyle = '';

	my @styleChanges = sort { $a:at <=> $b:at } @$o:styleChanges;
	push @styleChanges, {at => $length};
	my $nextChange = shift(@styleChanges);

	$o:ui->line($o:ui->gray('····   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f  0123456789abcdef'));
	while ($lineStart < $length) {
		my $hexLine = $currentStyle;
		my $textLine = $currentStyle;

		my $k = 0;
		while ($k < 16) {
			my $index = $lineStart + $k;
			last if $index >= $length;

			my $break = 0;
			while ($index >= $nextChange:at) {
				$currentStyle = $nextChange:style;
				$break = $nextChange:breakBefore && $k > 0;
				$hexLine .= $currentStyle;
				$textLine .= $currentStyle;
				$nextChange = shift @styleChanges;
				last if $break;
			}

			last if $break;

			my $byte = substr($o:bytes, $lineStart + $k, 1);
			$hexLine .= ' '.unpack('H*', $byte);

			my $code = ord($byte);
			$textLine .= $code >= 32 && $code <= 126 ? $byte : '·';

			$k += 1;
		}

		$hexLine .= '   ' x (16 - $k);
		$textLine .= ' ' x (16 - $k);
		$o:ui->line($o:ui->gray(unpack('H4', pack('S>', $lineStart))), ' ', $hexLine, $resetStyle, '  ', $textLine, $resetStyle);

		$lineStart += $k;
	}
}
