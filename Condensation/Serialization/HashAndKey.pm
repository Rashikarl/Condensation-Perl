# A hash with an AES key.

sub new($class, $hash // return, $key // return) {
	return bless {
		hash => $hash,
		key => $key,
		};
}

sub hash;
sub key;
