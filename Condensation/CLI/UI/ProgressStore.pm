use parent 'CDS::Store';

sub new($class, $store, $url, $ui) {
	return bless {
		store => $store,
		url => $url,
		ui => $ui,
		}
}

sub store;
sub url;
sub ui;

sub id($o) { 'Progress'."\n  ".$o:store->id }

### Object store functions

sub get($o, $hash, $keyPair) {
	$o:ui->progress('GET ', $hash->shortHex, ' on ', $o:url);
	return $o:store->get($hash, $keyPair);
}

sub book($o, $hash, $keyPair) {
	$o:ui->progress('BOOK ', $hash->shortHex, ' on ', $o:url);
	return $o:store->book($hash, $keyPair);
}

sub put($o, $hash, $object, $keyPair) {
	$o:ui->progress('PUT ', $hash->shortHex, ' (', $o:ui->niceFileSize($object->byteLength), ') on ', $o:url);
	return $o:store->put($hash, $object, $keyPair);
}

### Account store functions

sub list($o, $accountHash, $boxLabel, $timeout, $keyPair) {
	$o:ui->progress($timeout == 0 ? 'LIST ' : 'WATCH ', $boxLabel, ' of ', $accountHash->shortHex, ' on ', $o:url);
	return $o:store->list($accountHash, $boxLabel, $timeout, $keyPair);
}

sub add($o, $accountHash, $boxLabel, $hash, $keyPair) {
	$o:ui->progress('ADD ', $accountHash->shortHex, ' ', $boxLabel, ' ', $hash->shortHex, ' on ', $o:url);
	return $o:store->add($accountHash, $boxLabel, $hash, $keyPair);
}

sub remove($o, $accountHash, $boxLabel, $hash, $keyPair) {
	$o:ui->progress('REMOVE ', $accountHash->shortHex, ' ', $boxLabel, ' ', $hash->shortHex, ' on ', $o:url);
	return $o:store->remove($accountHash, $boxLabel, $hash, $keyPair);
}

sub modify($o, $modifications, $keyPair) {
	$o:ui->progress('MODIFY +', scalar @{$modifications->additions}, ' -', scalar @{$modifications->removals}, ' on ', $o:url);
	return $o:store->modify($modifications, $keyPair);
}
