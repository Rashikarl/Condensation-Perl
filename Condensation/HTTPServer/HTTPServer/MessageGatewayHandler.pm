sub new($class, $url, $identity, $recipient) {
	return bless {url => $url, identity => $identity, recipient => $recipient};
}

sub process($o, $request) {
	$request->path =~ /^\/data$/ || return;
	my $store = $request->server->store;

	# Options
	return $request->replyOptions('HEAD', 'GET', 'PUT', 'POST', 'DELETE') if $request->method eq 'OPTIONS';

	# Prepare a message
	my $record = CDS::Record->new;
	$record->add('time')->addInteger(CDS->now);
	$record->add('ip')->add($request->peerAddress);
	$record->add('method')->add($request->method);
	$record->add('path')->add($request->path);
	$record->add('query string')->add($request->queryString);

	my $headersRecord = $record->add('headers');
	my $headers = $request->headers;
	for my $key (keys %$headers) {
		$headersRecord->add($key)->add($headers->{$key});
	}

	$record->add('data')->add($request->readData) if $request->remainingData;

	# Post it
	my $success = $o:identity->sendMessageRecord($record, undef, [$o:recipient]);
	return $success ? $request->reply200 : $request->reply500('Unable to send the message.');
}
