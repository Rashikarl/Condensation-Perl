# EXTEND CDS
# Utility functions for random sequences

srand(time);
our @hexDigits = ('0'..'9', 'a'..'f');

sub randomHex($class, $length) {
	return substr(unpack('H*', CDS::C::randomBytes(int(($length + 1) / 2))), 0, $length);
}

sub randomBytes($class, $length) {
	return CDS::C::randomBytes($length);
}

sub randomKey($class) {
	return CDS::C::randomBytes(32);
}
