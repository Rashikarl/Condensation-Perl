# A public key of somebody.

sub fromObject($class, $object) {
	my $record = CDS::Record->fromObject($object) // return;
	my $rsaPublicKey = CDS::C::publicKeyNew($record->child('e')->bytesValue, $record->child('n')->bytesValue) // return;
	return bless {
		hash => $object->calculateHash,
		rsaPublicKey => $rsaPublicKey,
		object => $object,
		lastAccess => 0,	# used by PublicKeyCache
		};
}

sub object;
sub bytes($o) { $o:object->bytes }

### Public key interface ###

sub hash;
sub encrypt($o, $bytes) { CDS::C::publicKeyEncrypt($o:rsaPublicKey, $bytes) }
sub verifyHash($o, $hash, $signature) { CDS::C::publicKeyVerify($o:rsaPublicKey, $hash->bytes, $signature) }
