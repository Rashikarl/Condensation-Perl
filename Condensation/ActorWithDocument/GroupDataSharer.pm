sub new($class, $actor) {
	my $o = bless {
		actor => $actor,
		label => 'shared group data',
		dataHandlers => {},
		messageChannel => CDS::MessageChannel->new($actor, 'group data', CDS->MONTH),
		revision => 0,
		version => '',
		}, $class;

	$actor->storagePrivateRoot->addDataHandler($o:label, $o);
	return $o;
}

### Group data handlers

sub addDataHandler($o, $label, $dataHandler) {
	$o:dataHandlers->{$label} = $dataHandler;
}

sub removeDataHandler($o, $label, $dataHandler) {
	my $registered = $o:dataHandlers->{$label};
	return if $registered != $dataHandler;
	delete $o:dataHandlers->{$label};
}

### MergeableData interface

sub addDataTo($o, $record) {
	return if ! $o:revision;
	$record->addInteger($o:revision)->add($o:version);
}

sub mergeData($o, $record) {
	for my $child ($record->children) {
		my $revision = $child->asInteger;
		next if $revision <= $o:revision;

		$o:revision = $revision;
		$o:version = $child->bytesValue;
	}
}

sub mergeExternalData($o, $store, $record, $source) {
	$o->mergeData($record);
	return if ! $source;
	$source->keep;
	$o:actor->storagePrivateRoot->unsaved->state->addMergedSource($source);
}

### Sending messages

sub createMessage($o) {
	my $message = CDS::Record->new;
	my $data = $message->add('group data');
	for my $label (keys %$o:dataHandlers) {
		my $dataHandler = $o:dataHandlers->{$label};
		$dataHandler->addDataTo($data->add($label));
	}
	return $message;
}

sub share($o) {
	# Get the group data members
	my $members = $o:actor->getGroupDataMembers // return;
	return 1 if ! scalar @$members;

	# Create the group data message, and check if it changed
	my $message = $o->createMessage;
	my $versionHash = $message->toObject->calculateHash;
	return if $versionHash->bytes eq $o:version;

	$o:revision = CDS->now;
	$o:version = $versionHash->bytes;
	$o:actor->storagePrivateRoot->dataChanged;

	# Procure the sent list
	$o:actor->procureSentList // return;

	# Get the entrusted keys
	my $entrustedKeys = $o:actor->getEntrustedKeys // return;

	# Transfer the data
	$o:messageChannel->addTransfer([$message->dependentHashes], $o:actor->storagePrivateRoot->unsaved, 'group data message');

	# Send the message
	$o:messageChannel->setRecipients($members, $entrustedKeys);
	my ($submission, $missingObject) = $o:messageChannel->submit($message, $o);
	$o:actor->onMissingObject($missingObject) if $missingObject;
	return if ! $submission;
	return 1;
}

sub onMessageChannelSubmissionCancelled($o) { }

sub onMessageChannelSubmissionRecipientDone($o, $recipientActorOnStore) { }

sub onMessageChannelSubmissionRecipientFailed($o, $recipientActorOnStore) { }

sub onMessageChannelSubmissionDone($o, $succeeded, $failed) { }

### Receiving messages

sub processGroupDataMessage($o, $message, $section) {
	if (! $o:actor->isGroupMember($message->sender->publicKey->hash)) {
		# TODO:
		# If the sender is not a known group member, we should run actor group discovery on the sender. He may be part of us, but we don't know that yet.
		# At the very least, we should keep this message, and reconsider it if the actor group changes within the next few minutes (e.g. through another message).
		return;
	}

	for my $child ($section->children) {
		my $dataHandler = $o:dataHandlers->{$child->bytes} // next;
		$dataHandler->mergeExternalData($message->sender->store, $child, $message->source);
	}

	return 1;
}
