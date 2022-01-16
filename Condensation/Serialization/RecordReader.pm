sub new($class, $object) {
	return bless {
		object => $object,
		data => $object->data,
		pos => 0,
		hasError => 0
		};
}

sub hasError;

sub readChildren($o, $record) {
	while (1) {
		# Flags
		my $flags = $o->readUnsigned8 // return;

		# Data
		my $length = $flags & 0x1f;
		my $byteLength = $length == 30 ? 30 + ($o->readUnsigned8 // return) : $length == 31 ? ($o->readUnsigned64 // return) : $length;
		my $bytes = $o->readBytes($byteLength);
		my $hash = $flags & 0x20 ? $o:object->hashAtIndex($o->readUnsigned32 // return) : undef;
		return if $o:hasError;

		# Children
		my $child = $record->add($bytes, $hash);
		return if $flags & 0x40 && ! $o->readChildren($child);
		return 1 if ! ($flags & 0x80);
	}
}

sub use($o, $length) {
	my $start = $o:pos;
	$o:pos += $length;
	return substr($o:data, $start, $length) if $o:pos <= length $o:data;
	$o:hasError = 1;
	return;
}

sub readUnsigned8($o) { unpack('C', $o->use(1) // return) }
sub readUnsigned32($o) { unpack('L>', $o->use(4) // return) }
sub readUnsigned64($o) { unpack('Q>', $o->use(8) // return) }
sub readBytes($o, $length) { $o->use($length) }
sub trailer($o) { substr($o:data, $o:pos) }
