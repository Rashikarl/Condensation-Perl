# Useful functions to display textual information on the terminal
# INCLUDE UI/HexDump.pm
# INCLUDE UI/Record.pm
# INCLUDE UI/Span.pm
use utf8;

sub new($class, $fileHandle // *STDOUT, $pure) {
	binmode $fileHandle, ":utf8";
	return bless {
		fileHandle => $fileHandle,
		pure => $pure,
		indentCount => 0,
		indent => '',
		valueIndent => 16,
		hasSpace => 0,
		hasError => 0,
		hasWarning => 0,
		};
}

sub fileHandle;

### Indent

sub pushIndent($o) {
	$o:indentCount += 1;
	$o:indent = '  ' x $o:indentCount;
	return;
}

sub popIndent($o) {
	$o:indentCount -= 1;
	$o:indent = '  ' x $o:indentCount;
	return;
}

sub valueIndent($o, $width) {
	$o:valueIndent = $width;
}

### Low-level (non-semantic) output

sub print($o; @text) {
	my $fh = $o:fileHandle // return;
	print $fh @_;
}

sub raw($o; @bytes) {
	$o->removeProgress;
	my $fh = $o:fileHandle // return;
	binmode $fh, ":bytes";
	print $fh @_;
	binmode $fh, ":utf8";
	$o:hasSpace = 0;
	return;
}

sub space($o) {
	$o->removeProgress;
	return if $o:hasSpace;
	$o:hasSpace = 1;
	$o->print("\n");
	return;
}

# A line of text (without word-wrap).
sub line($o; @text) {
	$o->removeProgress;
	my $span = CDS::UI::Span->new(@_);
	$o->print($o:indent);
	$span->printTo($o);
	$o->print(chr(0x1b), '[0m', "\n");
	$o:hasSpace = 0;
	return;
}

# A line of word-wrapped text.
sub p($o; @text) {
	$o->removeProgress;
	my $span = CDS::UI::Span->new(@_);
	$span->wordWrap({lineLength => 0, maxLength => 100 - length $o:indent, indent => $o:indent});
	$o->print($o:indent);
	$span->printTo($o);
	$o->print(chr(0x1b), '[0m', "\n");
	$o:hasSpace = 0;
	return;
}

# Line showing the progress.
sub progress($o; @text) {
	return if $o:pure;
	$| = 1;
	$o:hasProgress = 1;
	my $text = '  '.join('', @_);
	$text = substr($text, 0, 79).'…' if length $text > 80;
	$text .= ' ' x (80 - length $text) if length $text < 80;
	$o->print($text, "\r");
}

# Progress line removal.
sub removeProgress($o) {
	return if $o:pure;
	return if ! $o:hasProgress;
	$o->print(' ' x 80, "\r");
	$o:hasProgress = 0;
	$| = 0;
}

### Low-level (non-semantic) formatting

sub span($o; @text) { CDS::UI::Span->new(@_) }

sub bold($o; @text) {
	my $span = CDS::UI::Span->new(@_);
	$span:bold = 1;
	return $span;
}

sub underlined($o; @text) {
	my $span = CDS::UI::Span->new(@_);
	$span:underlined = 1;
	return $span;
}

sub foreground($o, $foreground; @text) {
	my $span = CDS::UI::Span->new(@_);
	$span:foreground = $foreground;
	return $span;
}

sub background($o, $background; @text) {
	my $span = CDS::UI::Span->new(@_);
	$span:background = $background;
	return $span;
}

sub red($o; @text) { $o->foreground(196, @_) }		# for failure
sub green($o; @text) { $o->foreground(40, @_) }		# for success
sub orange($o; @text) { $o->foreground(166, @_) }	# for warnings
sub blue($o; @text) { $o->foreground(33, @_) }		# to highlight something (selection)
sub violet($o; @text) { $o->foreground(93, @_) }	# to highlight something (selection)
sub gold($o; @text) { $o->foreground(238, @_) }		# for commands that can be executed
sub gray($o; @text) { $o->foreground(246, @_) }		# for additional (less important) information

sub darkBold($o; @text) {
	my $span = CDS::UI::Span->new(@_);
	$span:bold = 1;
	$span:foreground = 240;
	return $span;
}

### Semantic output

sub title($o; @text) { $o->line($o->bold(@_)) }

sub left($o, $width, $text) {
	return substr($text, 0, $width - 1).'…' if length $text > $width;
	return $text . ' ' x ($width - length $text);
}

sub right($o, $width, $text) {
	return substr($text, 0, $width - 1).'…' if length $text > $width;
	return ' ' x ($width - length $text) . $text;
}

sub keyValue($o, $key, $firstLine; @lines) {
	my $indent = $o:valueIndent - length $o:indent;
	$key = substr($key, 0, $indent - 2).'…' if defined $firstLine && length $key >= $indent;
	$key .= ' ' x ($indent - length $key);
	$o->line($o->gray($key), $firstLine);
	my $noKey = ' ' x $indent;
	for my $line (@_) { $o->line($noKey, $line); }
	return;
}

sub command($o; @text) { $o->line($o->bold(@_)) }

sub verbose($o; @text) { $o->line($o->foreground(45, @_)) if $o:verbose }

sub pGreen($o; @text) {
	$o->p($o->green(@_));
	return;
}

sub pOrange($o; @text) {
	$o->p($o->orange(@_));
	return;
}

sub pRed($o; @text) {
	$o->p($o->red(@_));
	return;
}

### Warnings and errors

sub hasWarning;
sub hasError;

sub warning($o; @text) {
	$o:hasWarning = 1;
	$o->p($o->orange(@_));
	return;
}

sub error($o; @text) {
	$o:hasError = 1;
	my $span = CDS::UI::Span->new(@_);
	$span:background = 196;
	$span:foreground = 15;
	$span:bold = 1;
	$o->line($span);
	return;
}

### Semantic formatting

sub a($o; @text) { $o->underlined(@_) }

### Human readable formats

sub niceBytes($o, $bytes, $maxLength) {
	my $length = length $bytes;
	my $text = defined $maxLength && $length > $maxLength ? substr($bytes, 0, $maxLength - 1).'…' : $bytes;
	$text =~ s/[\x00-\x1f\x7f-\xff]/./g;
	return $text;
}

sub niceFileSize($o, $fileSize) {
	return $fileSize.' bytes' if $fileSize < 1000;
	return sprintf('%0.1f', $fileSize / 1000).' KB' if $fileSize < 10000;
	return sprintf('%0.0f', $fileSize / 1000).' KB' if $fileSize < 1000000;
	return sprintf('%0.1f', $fileSize / 1000000).' MB' if $fileSize < 10000000;
	return sprintf('%0.0f', $fileSize / 1000000).' MB' if $fileSize < 1000000000;
	return sprintf('%0.1f', $fileSize / 1000000000).' GB' if $fileSize < 10000000000;
	return sprintf('%0.0f', $fileSize / 1000000000).' GB';
}

sub niceDateTimeLocal($o, $time // time() * 1000) {
	my @t = localtime($time / 1000);
	return sprintf('%04d-%02d-%02d %02d:%02d:%02d', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

sub niceDateTime($o, $time // time() * 1000) {
	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02d %02d:%02d:%02d UTC', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

sub niceDate($o, $time // time() * 1000) {
	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3]);
}

sub niceTime($o, $time // time() * 1000) {
	my @t = gmtime($time / 1000);
	return sprintf('%02d:%02d:%02d UTC', $t[2], $t[1], $t[0]);
}

### Special output

sub record($o, $record, $storeUrl) { CDS::UI::Record->display($o, $record, $storeUrl) }

sub recordChildren($o, $record, $storeUrl) {
	for my $child ($record->children) {
		CDS::UI::Record->display($o, $child, $storeUrl);
	}
}

sub selector($o, $selector, $rootLabel) {
	my $item = $selector->dataTree->get($selector);
	my $revision = $item:revision ? $o->green('  ', $o->niceDateTime($item:revision)) : '';

	if ($selector:id eq 'ROOT') {
		$o->line($o->bold($rootLabel // 'Data tree'), $revision);
		$o->recordChildren($selector->record);
		$o->selectorChildren($selector);
	} else {
		my $label = $selector->label;
		my $labelText = length $label > 64 ? substr($label, 0, 64).'…' : $label;
		$labelText =~ s/[\x00-\x1f\x7f-\xff]/·/g;
		$o->line($o->blue($labelText), $revision);

		$o->pushIndent;
		$o->recordChildren($selector->record);
		$o->selectorChildren($selector);
		$o->popIndent;
	}
}

sub selectorChildren($o, $selector) {
	for my $child (sort { $a:id cmp $b:id } $selector->children) {
		$o->selector($child);
	}
}

sub hexDump($o, $bytes) { CDS::UI::HexDump->new($o, $bytes) }
