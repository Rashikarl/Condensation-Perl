# A record is a tree, whereby each nodes holds a byte sequence and an optional hash.
# Child nodes are ordered, although the order does not always matter.
use Encode;

sub fromObject($class, $object // return) {
	my $root = CDS::Record->new;
	$root->addFromObject($object) // return;
	return $root;
}

sub new($class, $bytes, $hash) {
	bless {
		bytes => $bytes // '',
		hash => $hash,
		children => [],
		};
}

# *** Adding

# Adds a record
sub add($o, $bytes, $hash) {
	my $record = CDS::Record->new($bytes, $hash);
	push @$o:children, $record;
	return $record;
}

sub addText($o, $value, $hash) { $o->add(Encode::encode_utf8($value // ''), $hash) }
sub addBoolean($o, $value, $hash) { $o->add(CDS->bytesFromBoolean($value), $hash) }
sub addInteger($o, $value, $hash) { $o->add(CDS->bytesFromInteger($value // 0), $hash) }
sub addUnsigned($o, $value, $hash) { $o->add(CDS->bytesFromUnsigned($value // 0), $hash) }
sub addHash($o, $hash) { $o->add('', $hash) }
sub addHashAndKey($o, $hashAndKey) { $hashAndKey ? $o->add($hashAndKey->key, $hashAndKey->hash) : $o->add('') }
sub addRecord($o; @records) { push @$o:children, @_; return; }

sub addFromObject($o, $object // return) {
	return 1 if ! length $object->data;
	return CDS::RecordReader->new($object)->readChildren($o);
}

# *** Set value

sub set($o, $bytes, $hash) {
	$o:bytes = $bytes;
	$o:hash = $hash;
	return;
}

# *** Querying

# Returns true if the record contains a child with the indicated bytes.
sub contains($o, $bytes) {
	for my $child (@$o:children) {
		return 1 if $child:bytes eq $bytes;
	}
	return;
}

# Returns the child record for the given bytes. If no record with these bytes exists, a record with these bytes is returned (but not added).
sub child($o, $bytes) {
	for my $child (@$o:children) {
		return $child if $child:bytes eq $bytes;
	}
	return $o->new($bytes);
}

# Returns the first child, or an empty record.
sub firstChild($o) { $o:children->[0] // $o->new }

# Returns the nth child, or an empty record.
sub nthChild($o, $i) { $o:children->[$i] // $o->new }

sub containsText($o, $text) { $o->contains(Encode::encode_utf8($text // '')) }
sub childWithText($o, $text) { $o->child(Encode::encode_utf8($text // '')) }

# *** Get value

sub bytes;
sub hash;
sub children($o) { @$o:children }

sub asText($o) { Encode::decode_utf8($o:bytes) // '' }
sub asBoolean($o) { CDS->booleanFromBytes($o:bytes) }
sub asInteger($o) { CDS->integerFromBytes($o:bytes) // 0 }
sub asUnsigned($o) { CDS->unsignedFromBytes($o:bytes) // 0 }

sub asHashAndKey($o) {
	return if ! $o:hash;
	return if length $o:bytes != 32;
	return CDS::HashAndKey->new($o:hash, $o:bytes);
}

sub bytesValue($o) { $o->firstChild->bytes }
sub hashValue($o) { $o->firstChild->hash }
sub textValue($o) { $o->firstChild->asText }
sub booleanValue($o) { $o->firstChild->asBoolean }
sub integerValue($o) { $o->firstChild->asInteger }
sub unsignedValue($o) { $o->firstChild->asUnsigned }
sub hashAndKeyValue($o) { $o->firstChild->asHashAndKey }

# *** Dependent hashes

sub dependentHashes($o) {
	my $hashes = {};
	$o->traverseHashes($hashes);
	return values %$hashes;
}

sub traverseHashes($o, $hashes) {	# private
	$hashes->{$o:hash->bytes} = $o:hash if $o:hash;
	for my $child (@$o:children) {
		$child->traverseHashes($hashes);
	}
}

# *** Size

sub countEntries($o) {
	my $count = 1;
	for my $child (@$o:children) { $count += $child->countEntries; }
	return $count;
}

sub calculateSize($o) {
	return 4 + $o->calculateSizeContribution;
}

sub calculateSizeContribution($o) {	# private
	my $byteLength = length $o:bytes;
	my $size = $byteLength < 30 ? 1 : $byteLength < 286 ? 2 : 9;
	$size += $byteLength;
	$size += 32 + 4 if $o:hash;
	for my $child (@$o:children) {
		$size += $child->calculateSizeContribution;
	}
	return $size;
}

# *** Serialization

# Serializes this record into a Condensation object.
sub toObject($o) {
	my $writer = CDS::RecordWriter->new;
	$writer->writeChildren($o);
	return CDS::Object->create($writer->header, $writer->data);
}
