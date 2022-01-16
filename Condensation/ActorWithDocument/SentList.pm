use parent 'CDS::UnionList';

sub new($class, $privateRoot) {
	return $class->SUPER::new($privateRoot, 'sent list');
}

sub createItem($o, $id) {
	return CDS::SentItem->new($o, $id);
}

sub mergeRecord($o, $part, $record) {
	my $item = $o->getOrCreate($record->bytes);
	for my $child ($record->children) {
		my $validUntil = $child->asInteger;
		my $message = $child->firstChild;
		$item->merge($part, $validUntil, $message);
	}
}

sub forgetObsoleteItems($o) {
	my $now = CDS->now;
	my $toDelete = [];
	for my $item (values %$o:items) {
		next if $item:validUntil >= $now;
		$o->forgetItem($item);
	}
}
