use parent 'CDS::UnionList::Item';

sub new($class, $unionList, $id) {
	my $o = $class->SUPER::new($unionList, $id);
	$o:validUntil = 0;
	$o:message = CDS::Record->new;
	return $o;
}

sub validUntil;
sub envelopeHash($o) { CDS::Hash->fromBytes($o:message->bytes) }
sub envelopeHashBytes($o) { $o:message->bytes }
sub message;

sub addToRecord($o, $record) {
	$record->add($o:id)->addInteger($o:validUntil)->addRecord($o:message);
}

sub set($o, $validUntil, $envelopeHash, $messageRecord) {
	my $message = CDS::Record->new($envelopeHash->bytes);
	$message->addRecord($messageRecord->children);
	$o->merge($o:unionList:changes, CDS->max($validUntil, $o:validUntil + 1), $message);
}

sub clear($o, $validUntil) {
	$o->merge($o:unionList:changes, CDS->max($validUntil, $o:validUntil + 1), CDS::Record->new);
}

sub merge($o, $part, $validUntil, $message) {
	return if $o:validUntil > $validUntil;
	return if $o:validUntil == $validUntil && $part:size < $o:part:size;
	$o:validUntil = $validUntil;
	$o:message = $message;
	$o->setPart($part);
}
