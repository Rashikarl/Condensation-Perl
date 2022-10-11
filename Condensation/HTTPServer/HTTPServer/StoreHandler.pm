sub new($class, $root, $store, $checkPutHash, $checkSignatures // 1) {
	return bless {
		root => $root,
		store => $store,
		checkPutHash => $checkPutHash,
		checkEnvelopeHash => $checkPutHash,
		checkSignatures => $checkSignatures,
		maximumWatchTimeout => 0,
		};
}

sub process($o, $request) {
	my $path = $request->pathAbove($o:root) // return;

	# Objects request
	if ($request->path =~ /^\/objects\/([0-9a-f]{64})$/) {
		my $hash = CDS::Hash->fromHex($1);
		return $o->objects($request, $hash);
	}

	# Box request
	if ($request->path =~ /^\/accounts\/([0-9a-f]{64})\/(messages|private|public)$/) {
		my $accountHash = CDS::Hash->fromHex($1);
		my $boxLabel = $2;
		return $o->box($request, $accountHash, $boxLabel);
	}

	# Box entry request
	if ($request->path =~ /^\/accounts\/([0-9a-f]{64})\/(messages|private|public)\/([0-9a-f]{64})$/) {
		my $accountHash = CDS::Hash->fromHex($1);
		my $boxLabel = $2;
		my $hash = CDS::Hash->fromHex($3);
		return $o->boxEntry($request, $accountHash, $boxLabel, $hash);
	}

	# Account request
	if ($request->path =~ /^\/accounts\/([0-9a-f]{64})$/) {
		return $request->replyOptions if $request->method eq 'OPTIONS';
		return $request->reply405;
	}

	# Accounts request
	if ($request->path =~ /^\/accounts$/) {
		return $o->accounts($request);
	}

	# Other requests on /objects or /accounts
	if ($request->path =~ /^\/(accounts|objects)(\/|$)/) {
		return $request->reply404;
	}

	# Nothing for us
	return;
}

sub objects($o, $request, $hash) {
	# Options
	if ($request->method eq 'OPTIONS') {
		return $request->replyOptions('HEAD', 'GET', 'PUT', 'POST');
	}

	# Retrieve object
	if ($request->method eq 'HEAD' || $request->method eq 'GET') {
		my ($object, $error) = $o:store->get($hash);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply404 if ! $object;
		# We don't check the SHA256 sum here - this should be done by the client
		return $request->reply200Bytes($object->bytes);
	}

	# Put object
	if ($request->method eq 'PUT') {
		my $bytes = $request->readData // return $request->reply400('No data received.');
		my $object = CDS::Object->fromBytes($bytes) // return $request->reply400('Not a Condensation object.');
		return $request->reply400('SHA256 sum does not match hash.') if $o:checkPutHash && ! $object->calculateHash->equals($hash);

		if ($o:checkSignatures) {
			my $checkSignatureStore = CDS::CheckSignatureStore->new($o:store);
			$checkSignatureStore->put($hash, $object);
			return $request->reply403 if ! $request->checkSignature($checkSignatureStore);
		}

		my $error = $o:store->put($hash, $object);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200;
	}

	# Book object
	if ($request->method eq 'POST') {
		return $request->reply403 if $o:checkSignatures && ! $request->checkSignature($o:store);
		return $request->reply400('You cannot send data when booking an object.') if $request->remainingData;
		my ($booked, $error) = $o:store->book($hash);
		return $request->replyFatalError($error) if defined $error;
		return $booked ? $request->reply200 : $request->reply404;
	}

	return $request->reply405;
}

sub box($o, $request, $accountHash, $boxLabel) {
	# Options
	if ($request->method eq 'OPTIONS') {
		return $request->replyOptions('HEAD', 'GET', 'PUT', 'POST');
	}

	# List box
	if ($request->method eq 'HEAD' || $request->method eq 'GET') {
		if ($o:checkSignatures) {
			my $actorHash = $request->checkSignature($o:store);
			return $request->reply403 if ! $o->verifyList($actorHash, $accountHash, $boxLabel);
		}

		my $watch = $request->headers->{'condensation-watch'} // '';
		my $timeout = $watch =~ /^(\d+)\s*ms$/ ? $1 + 0 : 0;
		$timeout = $o:maximumWatchTimeout if $timeout > $o:maximumWatchTimeout;
		my ($hashes, $error) = $o:store->list($accountHash, $boxLabel, $timeout);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200Bytes(join('', map { $_->bytes } @$hashes));
	}

	return $request->reply405;
}

sub boxEntry($o, $request, $accountHash, $boxLabel, $hash) {
	# Options
	if ($request->method eq 'OPTIONS') {
		return $request->replyOptions('HEAD', 'PUT', 'DELETE');
	}

	# Add
	if ($request->method eq 'PUT') {
		if ($o:checkSignatures) {
			my $actorHash = $request->checkSignature($o:store);
			return $request->reply403 if ! $o->verifyAddition($actorHash, $accountHash, $boxLabel, $hash);
		}

		my $error = $o:store->add($accountHash, $boxLabel, $hash);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200;
	}

	# Remove
	if ($request->method eq 'DELETE') {
		if ($o:checkSignatures) {
			my $actorHash = $request->checkSignature($o:store);
			return $request->reply403 if ! $o->verifyRemoval($actorHash, $accountHash, $boxLabel, $hash);
		}

		my ($booked, $error) = $o:store->remove($accountHash, $boxLabel, $hash);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200;
	}

	return $request->reply405;
}

sub accounts($o, $request) {
	# Options
	if ($request->method eq 'OPTIONS') {
		return $request->replyOptions('POST');
	}

	# Modify boxes
	if ($request->method eq 'POST') {
		my $bytes = $request->readData // return $request->reply400('No data received.');
		my $modifications = CDS::StoreModifications->fromBytes($bytes);
		return $request->reply400('Invalid modifications.') if ! $modifications;

		if ($o:checkSignatures) {
			my $actorHash = $request->checkSignature(CDS::CheckSignatureStore->new($o:store, $modifications->objects), $bytes);
			return $request->reply403 if ! $o->verifyModifications($actorHash, $modifications);
		}

		my $error = $o:store->modify($modifications);
		return $request->replyFatalError($error) if defined $error;
		return $request->reply200;
	}

	return $request->reply405;
}

sub verifyList($o, $actorHash, $accountHash, $boxLabel) {
	return 1 if $boxLabel eq 'public';
	return if ! $actorHash;
	return 1 if $accountHash->equals($actorHash);
	return;
}

sub verifyModifications($o, $actorHash, $modifications) {
	for my $operation (@{$modifications->additions}) {
		return if ! $o->verifyAddition($actorHash, $operation:accountHash, $operation:boxLabel, $operation:hash);
	}

	for my $operation (@{$modifications->removals}) {
		return if ! $o->verifyRemoval($actorHash, $operation:accountHash, $operation:boxLabel, $operation:hash);
	}

	return 1;
}

sub verifyAddition($o, $actorHash, $accountHash, $boxLabel, $hash) {
	return 1 if $boxLabel eq 'messages';
	return if ! $actorHash;
	return 1 if $accountHash->equals($actorHash);
	return;
}

sub verifyRemoval($o, $actorHash, $accountHash, $boxLabel, $hash) {
	return if ! $actorHash;
	return 1 if $accountHash->equals($actorHash);

	# Get the envelope
	my ($bytes, $error) = $o:store->get($hash);
	return if defined $error;
	return 1 if ! defined $bytes;
	my $record = CDS::Record->fromObject(CDS::Object->fromBytes($bytes)) // return;

	# Allow anyone listed under "updated by"
	my $actorHashBytes24 = substr($actorHash->bytes, 0, 24);
	for my $child ($record->child('updated by')->children) {
		my $hashBytes24 = $child->bytes;
		next if length $hashBytes24 != 24;
		return 1 if $hashBytes24 eq $actorHashBytes24;
	}

	return;
}
