# A store that prints all accesses to a filehandle (STDERR by default).
use parent 'CDS::Store';

sub new($class, $store, $fileHandle // *STDERR, $prefix // '') {
	return bless {
		id => "Log Store\n".$store->id,
		store => $store,
		fileHandle => $fileHandle,
		prefix => '',
		};
}

sub id;
sub store;
sub fileHandle;
sub prefix;

sub get($o, $hash, $keyPair) {
	my $start = CDS::C::performanceStart();
	my ($object, $error) = $o:store->get($hash, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('get', $hash->shortHex, defined $object ? &formatByteLength($object->byteLength).' bytes' : defined $error ? 'failed: '.$error : 'not found', $elapsed);
	return $object, $error;
}

sub put($o, $hash, $object, $keyPair) {
	my $start = CDS::C::performanceStart();
	my $error = $o:store->put($hash, $object, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('put', $hash->shortHex . ' ' . &formatByteLength($object->byteLength) . ' bytes', defined $error ? 'failed: '.$error : 'OK', $elapsed);
	return $error;
}

sub book($o, $hash, $keyPair) {
	my $start = CDS::C::performanceStart();
	my ($booked, $error) = $o:store->book($hash, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('book', $hash->shortHex, defined $booked ? 'OK' : defined $error ? 'failed: '.$error : 'not found', $elapsed);
	return $booked, $error;
}

sub list($o, $accountHash, $boxLabel, $timeout, $keyPair) {
	my $start = CDS::C::performanceStart();
	my ($hashes, $error) = $o:store->list($accountHash, $boxLabel, $timeout, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('list', $accountHash->shortHex . ' ' . $boxLabel . ($timeout ? ' ' . $timeout . ' s' : ''), defined $hashes ? scalar(@$hashes).' entries' : 'failed: '.$error, $elapsed);
	return $hashes, $error;
}

sub add($o, $accountHash, $boxLabel, $hash, $keyPair) {
	my $start = CDS::C::performanceStart();
	my $error = $o:store->add($accountHash, $boxLabel, $hash, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('add', $accountHash->shortHex . ' ' . $boxLabel . ' ' . $hash->shortHex, defined $error ? 'failed: '.$error : 'OK', $elapsed);
	return $error;
}

sub remove($o, $accountHash, $boxLabel, $hash, $keyPair) {
	my $start = CDS::C::performanceStart();
	my $error = $o:store->remove($accountHash, $boxLabel, $hash, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('remove', $accountHash->shortHex . ' ' . $boxLabel . ' ' . $hash->shortHex, defined $error ? 'failed: '.$error : 'OK', $elapsed);
	return $error;
}

sub modify($o, $modifications, $keyPair) {
	my $start = CDS::C::performanceStart();
	my $error = $o:store->modify($modifications, $keyPair);
	my $elapsed = CDS::C::performanceElapsed($start);
	$o->log('modify', scalar(keys %{$modifications->objects}) . ' objects ' . scalar @{$modifications->additions} . ' additions ' . scalar @{$modifications->removals} . ' removals', defined $error ? 'failed: '.$error : 'OK', $elapsed);
	return $error;
}

sub log($o, $cmd, $input, $output, $elapsed) {
	my $fh = $o:fileHandle // return;
	print $fh $o:prefix, &left(8, $cmd), &left(40, $input), ' => ', &left(40, $output), &formatDuration($elapsed), ' us', "\n";
}

sub left($width, $text) {	# private
	return $text . (' ' x ($width - length $text)) if length $text < $width;
	return $text;
}

sub formatByteLength($byteLength) {	# private
	my $s = ''.$byteLength;
	$s = ' ' x (9 - length $s) . $s if length $s < 9;
	my $len = length $s;
	return substr($s, 0, $len - 6).' '.substr($s, $len - 6, 3).' '.substr($s, $len - 3, 3);
}

sub formatDuration($elapsed) {	# private
	my $s = ''.$elapsed;
	$s = ' ' x (9 - length $s) . $s if length $s < 9;
	my $len = length $s;
	return substr($s, 0, $len - 6).' '.substr($s, $len - 6, 3).' '.substr($s, $len - 3, 3);
}
