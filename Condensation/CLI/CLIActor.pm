use parent 'CDS::ActorWithDataTree';

sub openOrCreateDefault($class, $ui) {
	$class->open(CDS::Configuration->getOrCreateDefault($ui));
}

sub open($class, $configuration) {
	# Read the store configuration
	my $ui = $configuration->ui;
	my $storeManager = CDS::CLIStoreManager->new($ui);

	my $storageStoreUrl = $configuration->storageStoreUrl;
	my $storageStore = $storeManager->uncachedStoreForUrl($storageStoreUrl) // return $ui->error('Your storage store "', $storageStoreUrl, '" cannot be accessed. You can set this store in "', $configuration->file('store'), '".');

	my $messagingStoreUrl = $configuration->messagingStoreUrl;
	my $messagingStore = $storeManager->uncachedStoreForUrl($messagingStoreUrl) // return $ui->error('Your messaging store "', $messagingStoreUrl, '" cannot be accessed. You can set this store in "', $configuration->file('messaging-store'), '".');

	# Read the key pair
	my $keyPair = $configuration->keyPair // return $ui->error('Your key pair (', $configuration->file('key-pair'), ') is missing.');

	# Create the actor
	my $publicKeyCache = CDS::PublicKeyCache->new(128);
	my $o = $class->SUPER::new($keyPair, $storageStore, $messagingStore, $messagingStoreUrl, $publicKeyCache);
	$o:ui = $ui;
	$o:storeManager = $storeManager;
	$o:configuration = $configuration;
	$o:sessionRoot = $o->localRoot->child('sessions')->child(''.getppid);
	$o:keyPairToken = CDS::KeyPairToken->new($configuration->file('key-pair'), $keyPair);

	# Message handlers
	$o:messageHandlers = {};
	$o->setMessageHandler('sender', \&onIgnoreMessage);
	$o->setMessageHandler('store', \&onIgnoreMessage);
	$o->setMessageHandler('group data', \&onGroupDataMessage);

	# Read the private data
	if (! $o->procurePrivateData) {
		$o:ui->space;
		$ui->pRed('Failed to read the local private data.');
		$o:ui->space;
		return;
	}

	return $o;
}

sub ui;
sub storeManager;
sub configuration;
sub sessionRoot;
sub keyPairToken;

### Saving

sub saveOrShowError($o) {
	$o->forgetOldSessions;
	my ($ok, $missingHash) = $o->savePrivateDataAndShareGroupData;
	return if ! $ok;
	return $o->onMissingObject($missingHash) if $missingHash;
	$o->sendMessages;
	return 1;
}

sub onMissingObject($o, $missingObject) {
	$o:ui->space;
	$o:ui->pRed('The object ', $missingObject->hash->hex, ' was missing while saving data.');
	$o:ui->space;
	$o:ui->p('This is a fatal error with two possible sources:');
	$o:ui->p('- A store may have lost objects, e.g. due to an error with the underlying storage, misconfiguration, or too aggressive garbage collection.');
	$o:ui->p('- The application is linking objects without properly storing them. This is an error in the application, that must be fixed by a developer.');
	$o:ui->space;
}

sub onGroupDataSharingStoreError($o, $recipientActorOnStore, $storeError) {
	$o:ui->space;
	$o:ui->pRed('Unable to share the group data with ', $recipientActorOnStore->publicKey->hash->hex, '.');
	$o:ui->space;
}

### Reading

sub onPrivateRootReadingInvalidEntry($o, $source, $reason) {
	$o:ui->space;
	$o:ui->pRed('The envelope ', $source->hash->shortHex, ' points to invalid private data (', $reason, ').');
	$o:ui->p('This could be due to a storage system failure, a malicious attempt to delete or modify your data, or simply an application error. To investigate what is going on, the following commands may be helpful:');
	$o:ui->line('  cds open envelope ', $source->hash->hex, ' from ', $source->actorOnStore->publicKey->hash->hex, ' on ', $source->actorOnStore->store->url);
	$o:ui->line('  cds show record ', $source->hash->hex, ' on ', $source->actorOnStore->store->url);
	$o:ui->line('  cds list private box of ', $source->actorOnStore->publicKey->hash->hex, ' on ', $source->actorOnStore->store->url);
	$o:ui->p('To remove the invalid entry, type:');
	$o:ui->line('  cds remove ', $source->hash->hex, ' from private box of ', $source->actorOnStore->publicKey->hash->hex, ' on ', $source->actorOnStore->store->url);
	$o:ui->space;
}

sub onVerifyMemberStore($o, $storeUrl, $actorSelector) { $o->storeForUrl($storeUrl) }

### Announcing

sub registerIfNecessary($o) {
	my $now = CDS->now;
	return if $o:actorSelector->revision > $now - CDS->DAY;
	$o->updateMyRegistration;
	$o->setMyActiveFlag(1);
	$o->setMyGroupDataFlag(1);
}

sub announceIfNecessary($o) {
	my $state = join('', map { CDS->bytesFromUnsigned($_->revision) } sort { $a->label cmp $b->label } $o:actorGroupSelector->children);
	$o->announceOnStoreIfNecessary($o:storageStore, $state);
	$o->announceOnStoreIfNecessary($o:messagingStore, $state) if $o:messagingStore->id ne $o:storageStore->id;
}

sub announceOnStoreIfNecessary($o, $store, $state) {
	my $stateSelector = $o:localRoot->child('announced')->childWithText($store->id);
	return if $stateSelector->bytesValue eq $state;
	my ($envelopeHash, $cardHash) = $o->announce($store);
	return $o:ui->pRed('Updating the card on ', $store->url, ' failed.') if ! $envelopeHash;
	$stateSelector->setBytes($state);
	$o:ui->pGreen('The card on ', $store->url, ' has been updated.');
	return 1;
}

### Store resolving

sub storeForUrl($o, $url) {
	my $store = &main::uncachedStoreForUrl($url) // return;
	my $progressShowingStore = CDS::UI::ProgressStore->new($store, $url, $o:ui);
	my $cacheStore = $o->cacheStore;
	my $cachedStore = defined $cacheStore ? CDS::ObjectCache->new($progressShowingStore, $cacheStore) : $progressShowingStore;
	return CDS::ErrorHandlingStore->new($cachedStore, $url, $o:storeManager);
}

sub cacheStore($o) {
	my $selector = $o:sessionRoot->child('use cache');
	return if ! $selector->isSet;
	my $storeUrl = $selector->textValue;
	return $o:cacheStore if defined $o:cacheStoreUrl && $storeUrl eq $o:cacheStoreUrl;

	$o:cacheStoreUrl = $storeUrl;
	$o:cacheStore = &main::uncachedStoreForUrl($storeUrl);
	return $o:cacheStore;
}

### Processing messages

sub setMessageHandler($o, $type, $handler) {
	$o:messageHandlers->{$type} = $handler;
}

sub readMessages($o) {
	$o:ui->title('Messages');
	$o:countMessages = 0;
	$o:messageBoxReader->read;
	$o:ui->line($o:ui->gray('none')) if ! $o:countMessages;
}

sub onMessageBoxVerifyStore($o, $senderStoreUrl, $hash, $envelope, $senderHash) {
	return $o->storeForUrl($senderStoreUrl);
}

sub onMessageBoxEntry($o, $message) {
	$o:countMessages += 1;

	for my $section ($message->content->children) {
		my $type = $section->bytes;
		my $handler = $o:messageHandlers->{$type} // \&onUnknownMessage;
		&$handler($o, $message, $section);
	}

#	1. message processed
#		-> source can be deleted immediately (e.g. invalid)
#			source.discard()
#		-> source has been merged, and will be deleted when changes have been saved
#			dataTree.addMergedSource(source)
#	2. wait for sender store
#		-> set entry.waitForStore = senderStore
#	3. skip
#		-> set entry.processed = false

	my $source = $message->source;
	$message->source->discard;
}

sub onGroupDataMessage($o, $message, $section) {
	my $ok = $o:groupDataSharer->processGroupDataMessage($message, $section);
	$o:groupDataTree->read;
	return $o:ui->line('Group data from ', $message->sender->publicKey->hash->hex) if $ok;
	$o:ui->line($o:ui->red('Group data from foreign actor ', $message->sender->publicKey->hash->hex, ' (ignored)'));
}

sub onIgnoreMessage($o, $message, $section) { }

sub onUnknownMessage($o, $message, $section) {
	$o:ui->line($o:ui->orange('Unknown message of type "', $section->asText, '" from ', $message->sender->publicKey->hash->hex));
}

sub onMessageBoxInvalidEntry($o, $source, $reason) {
	$o:ui->warning('Discarding invalid message ', $source->hash->hex, ' (', $reason, ').');
	$source->discard;
}

### Remembered values

sub labelSelector($o, $label) {
	my $bytes = Encode::encode_utf8($label);
	return $o->groupRoot->child('labels')->child($bytes);
}

sub remembered($o, $label) {
	return $o->labelSelector($label)->record;
}

sub remember($o, $label, $record) {
	$o->labelSelector($label)->set($record);
}

sub rememberedRecords($o) {
	my $records = {};
	for my $child ($o:groupRoot->child('labels')->children) {
		next if ! $child->isSet;
		my $label = Encode::decode_utf8($child->label);
		$records->{$label} = $child->record;
	}

	return $records;
}

sub storeLabel($o, $storeUrl) {
	my $records = $o->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if length $record->child('actor')->bytesValue;
		next if $storeUrl ne $record->child('store')->textValue;
		return $label;
	}

	return;
}

sub actorLabel($o, $actorHash) {
	my $records = $o->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if $actorHash->bytes ne $record->child('actor')->bytesValue;
		return $label;
	}

	return;
}

sub actorLabelByHashStartBytes($o, $actorHashStartBytes) {
	my $length = length $actorHashStartBytes;
	my $records = $o->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if $actorHashStartBytes ne substr($record->child('actor')->bytesValue, 0, $length);
		return $label;
	}

	return;
}

sub accountLabel($o, $storeUrl, $actorHash) {
	my $storeLabel;
	my $actorLabel;

	my $records = $o->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		my $actorBytes = $record->child('actor')->bytesValue;

		my $correctActor = $actorHash->bytes eq $actorBytes;
		$actorLabel = $label if $correctActor;

		if ($storeUrl eq $record->child('store')->textValue) {
			return $label if $correctActor;
			$storeLabel = $label if ! length $actorBytes;
		}
	}

	return (undef, $storeLabel, $actorLabel);
}

sub keyPairLabel($o, $file) {
	my $records = $o->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if $file ne $record->child('key pair')->textValue;
		return $label;
	}

	return;
}

### References that can be used in commands

sub actorReference($o, $actorHash) {
	return $o->actorLabel($actorHash) // $actorHash->hex;
}

sub storeReference($o, $store) { $o->storeUrlReference($store->url); }

sub storeUrlReference($o, $storeUrl) {
	return $o->storeLabel($storeUrl) // $storeUrl;
}

sub accountReference($o, $accountToken) {
	my ($accountLabel, $storeLabel, $actorLabel) = $o->accountLabel($accountToken:cliStore->url, $accountToken:actorHash);
	return $accountLabel if defined $accountLabel;
	return defined $actorLabel ? $actorLabel : $accountToken:actorHash->hex, ' on ', defined $storeLabel ? $storeLabel : $accountToken:cliStore->url;
}

sub boxReference($o, $boxToken) {
	return $o->boxName($boxToken:boxLabel), ' of ', $o->accountReference($boxToken:accountToken);
}

sub keyPairReference($o, $keyPairToken) {
	return $o->keyPairLabel($keyPairToken->file) // $keyPairToken->file;
}

sub blueActorReference($o, $actorHash) {
	my $label = $o->actorLabel($actorHash);
	return defined $label ? $o:ui->blue($label) : $actorHash->hex;
}

sub blueStoreReference($o, $store) { $o->blueStoreUrlReference($store->url); }

sub blueStoreUrlReference($o, $storeUrl) {
	my $label = $o->storeLabel($storeUrl);
	return defined $label ? $o:ui->blue($label) : $storeUrl;
}

sub blueAccountReference($o, $accountToken) {
	my ($accountLabel, $storeLabel, $actorLabel) = $o->accountLabel($accountToken:cliStore->url, $accountToken:actorHash);
	return $o:ui->blue($accountLabel) if defined $accountLabel;
	return defined $actorLabel ? $o:ui->blue($actorLabel) : $accountToken:actorHash->hex, ' on ', defined $storeLabel ? $o:ui->blue($storeLabel) : $accountToken:cliStore->url;
}

sub blueBoxReference($o, $boxToken) {
	return $o->boxName($boxToken:boxLabel), ' of ', $o->blueAccountReference($boxToken:accountToken);
}

sub blueKeyPairReference($o, $keyPairToken) {
	my $label = $o->keyPairLabel($keyPairToken->file);
	return defined $label ? $o:ui->blue($label) : $keyPairToken->file;
}

sub boxName($o, $boxLabel) {
	return 'private box' if $boxLabel eq 'private';
	return 'public box' if $boxLabel eq 'public';
	return 'message box' if $boxLabel eq 'messages';
	return $boxLabel;
}

### Session

sub forgetOldSessions($o) {
	for my $child ($o:sessionRoot->parent->children) {
		my $pid = $child->label;
		next if -e '/proc/'.$pid;
		$child->forgetBranch;
	}
}

sub selectedKeyPairToken($o) {
	my $file = $o:sessionRoot->child('selected key pair')->textValue;
	return if ! length $file;
	my $keyPair = CDS::KeyPair->fromFile($file) // return;
	return CDS::KeyPairToken->new($file, $keyPair);
}

sub selectedStoreUrl($o) {
	my $storeUrl = $o:sessionRoot->child('selected store')->textValue;
	return if ! length $storeUrl;
	return $storeUrl;
}

sub selectedStore($o) {
	my $storeUrl = $o->selectedStoreUrl // return;
	return $o->storeForUrl($storeUrl);
}

sub selectedActorHash($o) {
	return CDS::Hash->fromBytes($o:sessionRoot->child('selected actor')->bytesValue);
}

sub preferredKeyPairToken($o) { $o->selectedKeyPairToken // $o->keyPairToken }
sub preferredStore($o) { $o->selectedStore // $o->storageStore }
sub preferredStores($o) { $o->selectedStore // ($o->storageStore, $o->messagingStore) }
sub preferredActorHash($o) { $o->selectedActorHash // $o->keyPair->publicKey->hash }

### Common functions

sub uiGetObject($o, $hash, $store, $keyPairToken) {
	my ($object, $storeError) = $store->get($hash, $keyPairToken->keyPair);
	return if defined $storeError;
	return $o:ui->error('The object ', $hash->hex, ' does not exist on "', $store->url, '".') if ! $object;
	return $object;
}

sub uiGetRecord($o, $hash, $store, $keyPairToken) {
	my $object = $o->uiGetObject($hash, $store, $keyPairToken) // return;
	return CDS::Record->fromObject($object) // return $o:ui->error('The object ', $hash->hex, ' is not a record.');
}

sub uiGetPublicKey($o, $hash, $store, $keyPairToken) {
	my $object = $o->uiGetObject($hash, $store, $keyPairToken) // return;
	return CDS::PublicKey->fromObject($object) // return $o:ui->error('The object ', $hash->hex, ' is not a public key.');
}

sub isEnvelope($o, $object) {
	my $record = CDS::Record->fromObject($object) // return;
	return if ! $record->contains('signed');
	my $signatureRecord = $record->child('signature')->firstChild;
	return if ! $signatureRecord->hash;
	return if ! length $signatureRecord->bytes;
	return 1;
}
