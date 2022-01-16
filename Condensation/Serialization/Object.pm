# A Condensation object.
# A valid object starts with a 4-byte length (big-endian), followed by 32 * length bytes of hashes, followed by 0 or more bytes of data.

sub emptyHeader { "\0\0\0\0" }

sub create($class, $header, $data) {
	return if length $header < 4;
	my $hashesCount = unpack('L>', substr($header, 0, 4));
	return if length $header != 4 + $hashesCount * 32;
	return bless {
		bytes => $header.$data,
		hashesCount => $hashesCount,
		header => $header,
		data => $data
		};
}

sub fromBytes($class, $bytes // return) {
	return if length $bytes < 4;

	my $hashesCount = unpack 'L>', substr($bytes, 0, 4);
	my $dataStart = $hashesCount * 32 + 4;
	return if $dataStart > length $bytes;

	return bless {
		bytes => $bytes,
		hashesCount => $hashesCount,
		header => substr($bytes, 0, $dataStart),
		data => substr($bytes, $dataStart)
		};
}

sub fromFile($class, $file) {
	return $class->fromBytes(CDS->readBytesFromFile($file));
}

sub bytes;
sub header;
sub data;
sub hashesCount;
sub byteLength($o) { length($o:header) + length($o:data) }

sub calculateHash($o) {
	return CDS::Hash->calculateFor($o:bytes);
}

sub hashes($o) {
	return map { CDS::Hash->fromBytes(substr($o:header, $_ * 32 + 4, 32)) } 0 .. $o:hashesCount - 1;
}

sub hashAtIndex($o, $index // return) {
	return if $index < 0 || $index >= $o:hashesCount;
	return CDS::Hash->fromBytes(substr($o:header, $index * 32 + 4, 32));
}

sub crypt($o, $key) {
	return CDS::Object->create($o:header, CDS::C::aesCrypt($o:data, $key, CDS->zeroCTR));
}

sub writeToFile($o, $file) {
	return CDS->writeBytesToFile($file, $o:bytes);
}
