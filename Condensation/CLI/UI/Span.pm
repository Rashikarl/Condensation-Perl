sub new($class; @text) {
	return bless {
		text => [@_],
		};
}

sub printTo($o, $ui, $parent) {
	if ($parent) {
		$o:appliedForeground = $o:foreground // $parent:appliedForeground;
		$o:appliedBackground = $o:background // $parent:appliedBackground;
		$o:appliedBold = $o:bold // $parent:appliedBold // 0;
		$o:appliedUnderlined = $o:underlined // $parent:appliedUnderlined // 0;
	} else {
		$o:appliedForeground = $o:foreground;
		$o:appliedBackground = $o:background;
		$o:appliedBold = $o:bold // 0;
		$o:appliedUnderlined = $o:underlined // 0;
	}

	my $style = chr(0x1b).'[0';
	$style .= ';1' if $o:appliedBold;
	$style .= ';4' if $o:appliedUnderlined;
	$style .= ';38;5;'.$o:appliedForeground if defined $o:appliedForeground;
	$style .= ';48;5;'.$o:appliedBackground if defined $o:appliedBackground;
	$style .= 'm';

	my $needStyle = 1;
	for my $child (@$o:text) {
		my $ref = ref $child;
		if ($ref eq 'CDS::UI::Span') {
			$child->printTo($ui, $o);
			$needStyle = 1;
			next;
		} elsif (length $ref) {
			warn 'Printing REF';
			$child = $ref;
		} elsif (! defined $child) {
			warn 'Printing UNDEF';
			$child = 'UNDEF';
		}

		if ($needStyle) {
			$ui->print($style);
			$needStyle = 0;
		}

		$ui->print($child);
	}
}

sub wordWrap($o, $state) {
	my $index = -1;
	for my $child (@$o:text) {
		$index += 1;

		next if ! defined $child;

		my $ref = ref $child;
		if ($ref eq 'CDS::UI::Span') {
			$child->wordWrap($state);
			next;
		} elsif (length $ref) {
			warn 'Printing REF';
			$child = $ref;
		} elsif (! defined $child) {
			warn 'Printing UNDEF';
			$child = 'UNDEF';
		}

		my $position = -1;
		for my $char (split //, $child) {
			$position += 1;
			$state:lineLength += 1;
			if ($char eq ' ' || $char eq "\t") {
				$state:wrapSpan = $o;
				$state:wrapIndex = $index;
				$state:wrapPosition = $position;
				$state:wrapReturn = $state:lineLength;
			} elsif ($state:wrapSpan && $state:lineLength > $state:maxLength) {
				my $text = $state:wrapSpan:text->[$state:wrapIndex];
				$text = substr($text, 0, $state:wrapPosition)."\n".$state:indent.substr($text, $state:wrapPosition + 1);
				$state:wrapSpan:text->[$state:wrapIndex] = $text;
				$state:lineLength -= $state:wrapReturn;
				$position += length $state:indent if $state:wrapSpan == $o && $state:wrapIndex == $index;
				$state:wrapSpan = undef;
			}
		}
	}
}
