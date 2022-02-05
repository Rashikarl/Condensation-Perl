# EXTEND CDS

# Conversion of numbers and booleans to and from bytes.
# To convert text, use Encode::encode_utf8($text) and Encode::decode_utf8($bytes).
# To convert hex sequences, use pack('H*', $hex) and unpack('H*', $bytes).

sub bytesFromBoolean($class, $value) { $value ? 'y' : '' }

sub bytesFromInteger($class, $value) {
	return '' if $value >= 0 && $value < 1;
	return pack 'c', $value if $value >= -0x80 && $value < 0x80;
	return pack 's>', $value if $value >= -0x8000 && $value < 0x8000;

	# This works up to 63 bits, plus 1 sign bit
	my $bytes = pack 'q>', $value;

	my $pos = 0;
	my $first = ord(substr($bytes, 0, 1));
	if ($value > 0) {
		# Perl internally uses an unsigned 64-bit integer if the value is positive
		return "\x7f\xff\xff\xff\xff\xff\xff\xff" if $first >= 128;
		while ($first == 0) {
			my $next = ord(substr($bytes, $pos + 1, 1));
			last if $next >= 128;
			$first = $next;
			$pos += 1;
		}
	} elsif ($first == 255) {
		while ($first == 255) {
			my $next = ord(substr($bytes, $pos + 1, 1));
			last if $next < 128;
			$first = $next;
			$pos += 1;
		}
	}

	return substr($bytes, $pos);
}

sub bytesFromUnsigned($class, $value) {
	return '' if $value < 1;
	return pack 'C', $value if $value < 0x100;
	return pack 'S>', $value if $value < 0x10000;

	# This works up to 64 bits
	my $bytes = pack 'Q>', $value;
	my $pos = 0;
	$pos += 1 while substr($bytes, $pos, 1) eq "\0";
	return substr($bytes, $pos);
}

sub bytesFromFloat32($class, $value) { pack('f', $value) }
sub bytesFromFloat64($class, $value) { pack('d', $value) }

sub booleanFromBytes($class, $bytes) {
	return length $bytes > 0;
}

sub integerFromBytes($class, $bytes) {
	return 0 if ! length $bytes;
	my $value = unpack('C', substr($bytes, 0, 1));
	$value -= 0x100 if $value & 0x80;
	for my $i (1 .. length($bytes) - 1) {
		$value *= 256;
		$value += unpack('C', substr($bytes, $i, 1));
	}
	return $value;
}

sub unsignedFromBytes($class, $bytes) {
	my $value = 0;
	for my $i (0 .. length($bytes) - 1) {
		$value *= 256;
		$value += unpack('C', substr($bytes, $i, 1));
	}
	return $value;
}

sub floatFromBytes($class, $bytes) {
	return unpack('f', $bytes) if length $bytes == 4;
	return unpack('d', $bytes) if length $bytes == 8;
	return undef;
}

# Initial counter value for AES in CTR mode
sub zeroCTR { "\0" x 16 }

my $emptyBytesHash = CDS::Hash->fromHex('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
sub emptyBytesHash { $emptyBytesHash }
