sub new($class) {
	return bless {
		hashesCount => 0,
		hashes => '',
		data => ''
		};
}

sub header($o) { pack('L>', $o:hashesCount).$o:hashes }
sub data;

sub writeChildren($o, $record) {
	my @children = @$record:children;
	return if ! scalar @children;
	my $lastChild = pop @children;
	for my $child (@children) { $o->writeNode($child, 1); }
	$o->writeNode($lastChild, 0);
}

sub writeNode($o, $record, $hasMoreSiblings) {
	# Flags
	my $byteLength = length $record:bytes;
	my $flags = $byteLength < 30 ? $byteLength : $byteLength < 286 ? 30 : 31;
	$flags |= 0x20 if defined $record:hash;
	my $countChildren = scalar @$record:children;
	$flags |= 0x40 if $countChildren;
	$flags |= 0x80 if $hasMoreSiblings;
	$o->writeUnsigned8($flags);

	# Data
	$o->writeUnsigned8($byteLength - 30) if ($flags & 0x1f) == 30;
	$o->writeUnsigned64($byteLength) if ($flags & 0x1f) == 31;
	$o->writeBytes($record:bytes);
	$o->writeUnsigned32($o->addHash($record:hash)) if $flags & 0x20;

	# Children
	$o->writeChildren($record);
}

sub writeUnsigned8($o, $value) { $o:data .= pack('C', $value) }
sub writeUnsigned32($o, $value) { $o:data .= pack('L>', $value) }
sub writeUnsigned64($o, $value) { $o:data .= pack('Q>', $value) }

sub writeBytes($o, $bytes) {
	warn $bytes.' is a utf8 string, not a byte string.' if utf8::is_utf8($bytes);
	$o:data .= $bytes;
}

sub addHash($o, $hash) {
	my $index = $o:hashesCount;
	$o:hashes .= $hash->bytes;
	$o:hashesCount += 1;
	return $index;
}
