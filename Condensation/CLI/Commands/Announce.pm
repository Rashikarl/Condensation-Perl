# BEGIN AUTOGENERATED

sub register($class, $cds, $help) {
	my $node000 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node001 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&announceMe});
	my $node002 = CDS::Parser::Node->new(1);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(0);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(1);
	my $node014 = CDS::Parser::Node->new(0);
	my $node015 = CDS::Parser::Node->new(0);
	my $node016 = CDS::Parser::Node->new(0);
	my $node017 = CDS::Parser::Node->new(0, {constructor => \&new, function => \&announceKeyPair});
	$cds->addArrow($node001, 1, 0, 'announce');
	$cds->addArrow($node002, 1, 0, 'announce');
	$help->addArrow($node000, 1, 0, 'announce');
	$node002->addArrow($node003, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node003->addArrow($node004, 1, 0, 'on');
	$node004->addArrow($node005, 1, 0, 'STORE', \&collectStore);
	$node005->addArrow($node006, 1, 0, 'without');
	$node005->addArrow($node007, 1, 0, 'with');
	$node005->addDefault($node017);
	$node006->addArrow($node006, 1, 0, 'ACTOR', \&collectActor);
	$node006->addArrow($node017, 1, 0, 'ACTOR', \&collectActor);
	$node007->addArrow($node008, 1, 0, 'active', \&collectActive);
	$node007->addArrow($node008, 1, 0, 'entrusted', \&collectEntrusted);
	$node007->addArrow($node008, 1, 0, 'idle', \&collectIdle);
	$node007->addArrow($node008, 1, 0, 'revoked', \&collectRevoked);
	$node008->addDefault($node009);
	$node008->addDefault($node010);
	$node009->addArrow($node009, 1, 0, 'ACCOUNT', \&collectAccount);
	$node009->addArrow($node013, 1, 1, 'ACCOUNT', \&collectAccount);
	$node010->addArrow($node010, 1, 0, 'ACTOR', \&collectActor1);
	$node010->addArrow($node011, 1, 0, 'ACTOR', \&collectActor1);
	$node011->addArrow($node012, 1, 0, 'on');
	$node012->addArrow($node013, 1, 0, 'STORE', \&collectStore1);
	$node013->addArrow($node014, 1, 0, 'but');
	$node013->addArrow($node016, 1, 0, 'and');
	$node013->addDefault($node017);
	$node014->addArrow($node015, 1, 0, 'without');
	$node015->addArrow($node015, 1, 0, 'ACTOR', \&collectActor);
	$node015->addArrow($node017, 1, 0, 'ACTOR', \&collectActor);
	$node016->addDefault($node007);
}

sub collectAccount($o, $label, $value) {
	push @$o:with, {status => $o:status, accountToken => $value};
}

sub collectActive($o, $label, $value) {
	$o:status = 'active';
}

sub collectActor($o, $label, $value) {
	$o:without->{$value->bytes} = $value;
}

sub collectActor1($o, $label, $value) {
	push @$o:actorHashes, $value;
}

sub collectEntrusted($o, $label, $value) {
	$o:status = 'entrusted';
}

sub collectIdle($o, $label, $value) {
	$o:status = 'idle';
}

sub collectKeypair($o, $label, $value) {
	$o:keyPairToken = $value;
}

sub collectRevoked($o, $label, $value) {
	$o:status = 'revoked';
}

sub collectStore($o, $label, $value) {
	$o:store = $value;
}

sub collectStore1($o, $label, $value) {
	for my $actorHash (@$o:actorHashes) {
	my $accountToken = CDS::AccountToken->new($value, $actorHash);
	push @$o:with, {status => $o:status, accountToken => $accountToken};
	}

	$o:actorHashes = [];
}

sub new($class, $actor) { bless {actor => $actor, ui => $actor->ui} }

# END AUTOGENERATED

# HTML FOLDER NAME announce
# HTML TITLE Announce
sub help($o, $cmd) {
	my $ui = $o:ui;
	$ui->space;
	$ui->command('cds announce');
	$ui->p('Announces yourself on your accounts.');
	$ui->space;
	$ui->command('cds announce KEYPAIR on STORE');
	$ui->command('… with (active|idle|revoked|entrusted) ACCOUNT*');
	$ui->command('… with (active|idle|revoked|entrusted) ACTOR* on STORE');
	$ui->command('… without ACTOR*');
	$ui->command('… with … and … and … but without …');
	$ui->p('Updates the public card of the indicated key pair on the indicated store. The indicated accounts are added or removed from the actor group on the card.');
	$ui->p('If no card exists, a minimalistic card is created.');
	$ui->p('Use this with care, as the generated card may not be compliant with the card produced by the actor.');
	$ui->space;
}

sub announceMe($o, $cmd) {
	$o->announceOnStore($o:actor->storageStore);
	$o->announceOnStore($o:actor->messagingStore) if $o:actor->messagingStore->id ne $o:actor->storageStore->id;
	$o:ui->space;
}

sub announceOnStore($o, $store) {
	$o:ui->space;
	$o:ui->title($store->url);
	my ($envelopeHash, $cardHash, $invalidReason, $storeError) = $o:actor->announce($store);
	return if defined $storeError;
	return $o:ui->pRed($invalidReason) if defined $invalidReason;
	$o:ui->pGreen('Announced');
}

sub announceKeyPair($o, $cmd) {
	$o:actors = [];
	$o:with = [];
	$o:without = {};
	$o:now = CDS->now;
	$cmd->collect($o);

	# List
	$o:keyPair = $o:keyPairToken->keyPair;
	my ($hashes, $listError) = $o:store->list($o:keyPair->publicKey->hash, 'public', 0, $o:keyPair);
	return if defined $listError;

	# Check if there are more than one cards
	if (scalar @$hashes > 1) {
		$o:ui->space;
		$o:ui->p('This account contains more than one public card:');
		$o:ui->pushIndent;
		for my $hash (@$hashes) {
			$o:ui->line($o:ui->gold('cds show card ', $hash->hex, ' on ', $o:storeUrl));
		}
		$o:ui->popIndent;
		$o:ui->p('Remove all but the most recent card. Cards can be removed as follows:');
		my $keyPairReference = $o:actor->blueKeyPairReference($o:keyPairToken);
		$o:ui->line($o:ui->gold('cds remove ', 'HASH', ' on ', $o:storeUrl, ' using ', $keyPairReference));
		$o:ui->space;
		return;
	}

	# Read the card
	my $cardRecord = scalar @$hashes ? $o->readCard($hashes->[0]) : CDS::Record->new;
	return if ! $cardRecord;

	# Parse
	my $builder = CDS::ActorGroupBuilder->new;
	$builder->parse($cardRecord, 0);

	# Apply the changes
	for my $change (@$o:with) {
		if ($change:status eq 'entrusted') {
			$builder->addEntrustedActor($change:accountToken->cliStore->url, $change:accountToken->actorHash);
			$builder:entrustedActorsRevision = $o:now;
		} else {
			$builder->addMember($change:accountToken->cliStore->url, $change:accountToken->actorHash, $o:now, $change:status);
		}
	}

	for my $hash (values %$o:without) {
		$builder->removeEntrustedActor($hash)
	}

	for my $member ($builder->members) {
		next if ! $o:without->{$member->hash->bytes};
		$builder->removeMember($member->storeUrl, $member->hash);
	}

	# Write the new card
	my $newCard = $builder->toRecord(0);
	$newCard->add('public key')->addHash($o:keyPair->publicKey->hash);

	for my $child ($cardRecord->children) {
		if ($child->bytes eq 'actor group') {
		} elsif ($child->bytes eq 'entrusted actors') {
		} elsif ($child->bytes eq 'public key') {
		} else {
			$newCard->addRecord($child);
		}
	}

	$o->announce($newCard, $hashes);
}

sub readCard($o, $envelopeHash) {
	# Open the envelope
	my ($object, $storeError) = $o:store->get($envelopeHash, $o:keyPair);
	return if defined $storeError;
	return $o:ui->error('Envelope object ', $envelopeHash->hex, ' not found.') if ! $object;

	my $envelope = CDS::Record->fromObject($object) // return $o:ui->error($envelopeHash->hex, ' is not a record.');
	my $cardHash = $envelope->child('content')->hashValue // return $o:ui->error($envelopeHash->hex, ' is not a valid envelope, because it has no content hash.');
	return $o:ui->error($envelopeHash->hex, ' has an invalid signature.') if ! CDS->verifyEnvelopeSignature($envelope, $o:keyPair->publicKey, $cardHash);

	# Read the card
	my ($cardObject, $storeError1) = $o:store->get($cardHash, $o:keyPair);
	return if defined $storeError1;
	return $o:ui->error('Card object ', $cardHash->hex, ' not found.') if ! $cardObject;

	return CDS::Record->fromObject($cardObject) // return $o:ui->error($cardHash->hex, ' is not a record.');
}

sub applyChanges($o, $actorGroup, $status, $accounts) {
	for my $account (@$accounts) {
		$actorGroup->{$account->url} = {storeUrl => $account->cliStore->url, actorHash => $account->actorHash, revision => $o:now, status => $status};
	}
}

sub announce($o, $card, $sourceHashes) {
	my $inMemoryStore = CDS::InMemoryStore->create;

	# Serialize the card
	my $cardObject = $card->toObject;
	my $cardHash = $cardObject->calculateHash;
	$inMemoryStore->put($cardHash, $cardObject);
	$inMemoryStore->put($o:keyPair->publicKey->hash, $o:keyPair->publicKey->object);

	# Prepare the public envelope
	my $envelopeObject = $o:keyPair->createPublicEnvelope($cardHash)->toObject;
	my $envelopeHash = $envelopeObject->calculateHash;
	$inMemoryStore->put($envelopeHash, $envelopeObject);

	# Transfer
	my ($missingHash, $failedStore, $storeError) = $o:keyPair->transfer([$envelopeHash], $inMemoryStore, $o:store);
	return if $storeError;
	return $o:ui->pRed('Object ', $missingHash, ' is missing.') if $missingHash;

	# Modify
	my $modifications = CDS::StoreModifications->new;
	$modifications->add($o:keyPair->publicKey->hash, 'public', $envelopeHash);
	for my $hash (@$sourceHashes) {
		$modifications->remove($o:keyPair->publicKey->hash, 'public', $hash);
	}

	my $modifyError = $o:store->modify($modifications, $o:keyPair);
	return if $modifyError;

	$o:ui->pGreen('Announced on ', $o:store->url, '.');
}
