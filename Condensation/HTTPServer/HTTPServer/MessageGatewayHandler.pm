sub new($class, $root, $actor, $store, $recipientHash) {
	return bless {root => $root, actor => $actor, store => $store, recipientHash => $recipientHash};
}

sub process($o, $request) {
	my $path = $request->pathAbove($o:root) // return;
	return if $path ne '/';

	# Options
	return $request->replyOptions('HEAD', 'GET', 'PUT', 'POST', 'DELETE') if $request->method eq 'OPTIONS';

	# Prepare a message
	my $message = CDS::Record->new;
	$message->add('time')->addInteger(CDS->now);
	$message->add('ip')->add($request->peerAddress);
	$message->add('method')->add($request->method);
	$message->add('path')->add($request->path);
	$message->add('query string')->add($request->queryString);

	my $headersRecord = $message->add('headers');
	my $headers = $request->headers;
	for my $key (keys %$headers) {
		$headersRecord->add($key)->add($headers->{$key});
	}

	# Prepare a channel
	my $channel = CDS::MessageChannel->new($o:actor, CDS->randomBytes(8), CDS->WEEK);
	$o:messageChannel->setRecipients([$o:recipientHash], []);

	# Add the data
	if ($request->remainingData > 1024) {
		# Store the data as a separate object
		my $object = CDS::Object->create(CDS::Object->emptyHeader, $request->readData);
		my $key = CDS->randomKey;
		my $encryptedObject = $object->crypt($key);
		my $hash = $encryptedObject->calculateHash;
		$message->add('data')->addHash($hash);
		$channel->addObject($hash, $encryptedObject);
	} elsif ($request->remainingData) {
		$message->add('data')->add($request->readData)
	}

	# Submit
	my ($submission, $missingObject) = $channel->submit($message, $o);
	$o:actor->sendMessages;

	return $submission ? $request->reply200 : $request->reply500('Unable to send the message.');
}

sub onMessageChannelSubmissionCancelled($o) { }

sub onMessageChannelSubmissionRecipientDone($o, $recipientActorOnStore) { }

sub onMessageChannelSubmissionRecipientFailed($o, $recipientActorOnStore) { }

sub onMessageChannelSubmissionDone($o, $succeeded, $failed) { }

