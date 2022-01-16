# Models a hash, and offers binary and hexadecimal representation.
use Digest::SHA;

sub fromBytes($class, $hashBytes // return) {
	return if length $hashBytes != 32;
	return bless \$hashBytes;
}

sub fromHex($class, $hashHex // return) {
	$hashHex =~ /^\s*([a-fA-F0-9]{64,64})\s*$/ || return;
	my $hashBytes = pack('H*', $hashHex);
	return bless \$hashBytes;
}

sub calculateFor($class, $bytes) {
	# The Perl built-in SHA256 implementation is a tad faster than our SHA256 implementation.
	#return $class->fromBytes(CDS::C::sha256($bytes));
	return $class->fromBytes(Digest::SHA::sha256($bytes));
}

sub hex($o) {
	return unpack('H*', $$o);
}

sub shortHex($o) {
	return unpack('H*', substr($$o, 0, 8)) . '…';
}

sub bytes($o) { $$o }

sub equals($this, $that) {
	return 1 if ! defined $this && ! defined $that;
	return if ! defined $this || ! defined $that;
	return $$this eq $$that;
}

sub cmp($this, $that) { $$this cmp $$that }
