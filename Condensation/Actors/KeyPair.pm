sub generate($class) {
	# Generate a new private key
	my $rsaPrivateKey = CDS::C::privateKeyGenerate();

	# Serialize the public key
	my $rsaPublicKey = CDS::C::publicKeyFromPrivateKey($rsaPrivateKey);
	my $record = CDS::Record->new;
	$record->add('e')->add(CDS::C::publicKeyE($rsaPublicKey));
	$record->add('n')->add(CDS::C::publicKeyN($rsaPublicKey));
	my $publicKey = CDS::PublicKey->fromObject($record->toObject);

	# Return a new CDS::KeyPair instance
	return CDS::KeyPair->new($publicKey, $rsaPrivateKey);
}

sub fromFile($class, $file) {
	my $bytes = CDS->readBytesFromFile($file) // return;
	my $record = CDS::Record->fromObject(CDS::Object->fromBytes($bytes));
	return $class->fromRecord($record);
}

sub fromHex($class, $hex) {
	return $class->fromRecord(CDS::Record->fromObject(CDS::Object->fromBytes(pack 'H*', $hex)));
}

sub fromRecord($class, $record // return) {
	my $publicKey = CDS::PublicKey->fromObject(CDS::Object->fromBytes($record->child('public key object')->bytesValue)) // return;
	my $rsaKey = $record->child('rsa key');
	my $e = $rsaKey->child('e')->bytesValue;
	my $p = $rsaKey->child('p')->bytesValue;
	my $q = $rsaKey->child('q')->bytesValue;
	return $class->new($publicKey, CDS::C::privateKeyNew($e, $p, $q) // return);
}

sub new($class, $publicKey, $rsaPrivateKey) {
	return bless {
		publicKey => $publicKey,			# The public key
		rsaPrivateKey => $rsaPrivateKey,	# The private key
		};
}

sub publicKey;
sub rsaPrivateKey;

### Serialization ###

sub toRecord($o) {
	my $record = CDS::Record->new;
	$record->add('public key object')->add($o:publicKey->object->bytes);
	my $rsaKeyRecord = $record->add('rsa key');
	$rsaKeyRecord->add('e')->add(CDS::C::privateKeyE($o:rsaPrivateKey));
	$rsaKeyRecord->add('p')->add(CDS::C::privateKeyP($o:rsaPrivateKey));
	$rsaKeyRecord->add('q')->add(CDS::C::privateKeyQ($o:rsaPrivateKey));
	return $record;
}

sub toHex($o) {
	my $object = $o->toRecord->toObject;
	return unpack('H*', $object->header).unpack('H*', $object->data);
}

sub writeToFile($o, $file) {
	my $object = $o->toRecord->toObject;
	return CDS->writeBytesToFile($file, $object->bytes);
}

### Private key interface ###

sub decrypt($o, $bytes) {	# decrypt(bytes) -> bytes
	return CDS::C::privateKeyDecrypt($o:rsaPrivateKey, $bytes);
}

sub sign($o, $digest) {	# sign(bytes) -> bytes
	return CDS::C::privateKeySign($o:rsaPrivateKey, $digest);
}

sub signHash($o, $hash) {	# signHash(hash) -> bytes
	return CDS::C::privateKeySign($o:rsaPrivateKey, $hash->bytes);
}

### Retrieval ###

# Retrieves an object from one of the stores, and decrypts it.
sub getAndDecrypt($o, $hashAndKey, $store) {
	my ($object, $error) = $store->get($hashAndKey->hash, $o);
	return undef, undef, $error if defined $error;
	return undef, 'Not found.', undef if ! $object;
	return $object->crypt($hashAndKey->key);
}

# Retrieves an object from one of the stores, and parses it as record.
sub getRecord($o, $hash, $store) {
	my ($object, $error) = $store->get($hash, $o);
	return undef, undef, undef, $error if defined $error;
	return undef, undef, 'Not found.', undef if ! $object;
	my $record = CDS::Record->fromObject($object) // return undef, undef, 'Not a record.', undef;
	return $record, $object;
}

# Retrieves an object from one of the stores, decrypts it, and parses it as record.
sub getAndDecryptRecord($o, $hashAndKey, $store) {
	my ($object, $error) = $store->get($hashAndKey->hash, $o);
	return undef, undef, undef, $error if defined $error;
	return undef, undef, 'Not found.', undef if ! $object;
	my $decrypted = $object->crypt($hashAndKey->key);
	my $record = CDS::Record->fromObject($decrypted) // return undef, undef, 'Not a record.', undef;
	return $record, $object;
}

# Retrieves an public key object from one of the stores, and parses its public key.
sub getPublicKey($o, $hash, $store) {
	my ($object, $error) = $store->get($hash, $o);
	return undef, undef, $error if defined $error;
	return undef, 'Not found.', undef if ! $object;
	return CDS::PublicKey->fromObject($object) // return undef, 'Not a public key.', undef;
}

### Equality ###

sub equals($this, $that) {
	return 1 if ! defined $this && ! defined $that;
	return if ! defined $this || ! defined $that;
	return $this->publicKey->hash->equals($that->publicKey->hash);
}
