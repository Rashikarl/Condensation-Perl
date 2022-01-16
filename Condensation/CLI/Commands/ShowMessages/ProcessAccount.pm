sub new($class, $cmd, $accountToken) {
	my $o = bless {
		cmd => $cmd,
		accountToken => $accountToken,
		countValid => 0,
		countInvalid => 0,
		};

	$cmd:ui->space;
	$cmd:ui->title('Messages of ', $cmd:actor->blueAccountReference($accountToken));

	# Get the public key
	my $publicKey = $o->getPublicKey // return;

	# Read all messages
	my $publicKeyCache = CDS::PublicKeyCache->new(128);
	my $pool = CDS::MessageBoxReaderPool->new($cmd:keyPairToken->keyPair, $publicKeyCache, $o);
	my $reader = CDS::MessageBoxReader->new($pool, CDS::ActorOnStore->new($publicKey, $accountToken->cliStore));
	$reader->read;

	$cmd:ui->line($cmd:ui->gray('No messages.')) if $o:countValid + $o:countInvalid == 0;
}

sub getPublicKey($o) {
	# Use the keypair's public key if possible
	return $o:cmd:keyPairToken->keyPair->publicKey if $o:accountToken->actorHash->equals($o:cmd:keyPairToken->keyPair->publicKey->hash);

	# Retrieve the public key
	return $o:cmd:actor->uiGetPublicKey($o:accountToken->actorHash, $o:accountToken->cliStore, $o:cmd:keyPairToken);
}

sub onMessageBoxVerifyStore($o, $senderStoreUrl, $hash, $envelope, $senderHash) {
	return $o:cmd:actor->storeForUrl($senderStoreUrl);
}

sub onMessageBoxEntry($o, $message) {
	$o:countValid += 1;
	$o:cmd:countValid += 1;

	my $ui = $o:cmd:ui;
	my $sender = CDS::AccountToken->new($message->sender->store, $message->sender->publicKey->hash);

	$ui->space;
	$ui->title($message->source->hash->hex);
	$ui->line('from ', $o:cmd:actor->blueAccountReference($sender));
	$ui->line('for ', $o:cmd:actor->blueAccountReference($o:accountToken));
	$ui->space;
	$ui->recordChildren($message->content);
}

sub onMessageBoxInvalidEntry($o, $source, $reason) {
	$o:countInvalid += 1;
	$o:cmd:countInvalid += 1;

	my $ui = $o:cmd:ui;
	my $hashHex = $source->hash->hex;
	my $storeReference = $o:cmd:actor->storeReference($o:accountToken->cliStore);

	$ui->space;
	$ui->title($hashHex);
	$ui->pOrange($reason);
	$ui->space;
	$ui->p('You may use the following commands to check out the envelope:');
	$ui->line($ui->gold('  cds open envelope ', $hashHex, ' on ', $storeReference));
	$ui->line($ui->gold('  cds show record ', $hashHex, ' on ', $storeReference));
	$ui->line($ui->gold('  cds show hashes and data of ', $hashHex, ' on ', $storeReference));
}
