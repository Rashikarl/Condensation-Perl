# The result of parsing an OBJECTFILE token (see Token.pm).

sub new($class, $file, $object) {
	return bless {
		file => $file,
		object => $object,
		};
}

sub file;
sub object;
