# BEGIN AUTOGENERATED

sub register($class, $cds, $help) {
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node008 = CDS::Parser::Node->new(1);
	my $node009 = CDS::Parser::Node->new(0);
	my $node010 = CDS::Parser::Node->new(0);
	my $node011 = CDS::Parser::Node->new(0);
	my $node012 = CDS::Parser::Node->new(0);
	my $node013 = CDS::Parser::Node->new(0);
	my $node014 = CDS::Parser::Node->new(0);
	my $node015 = CDS::Parser::Node->new(0);
	my $node016 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&modify});
	$cds->addDefault($node000);
	$help->addArrow($node007, 1, 0, 'add');
	$help->addArrow($node007, 1, 0, 'purge');
	$help->addArrow($node007, 1, 0, 'remove');
	$node000->addArrow($node001, 1, 0, 'add');
	$node000->addArrow($node002, 1, 0, 'remove');
	$node000->addArrow($node003, 1, 0, 'add');
	$node000->addArrow($node008, 1, 0, 'purge', \&collectPurge);
	$node001->addArrow($node001, 1, 0, 'HASH', \&collectHash);
	$node001->addArrow($node004, 1, 0, 'HASH', \&collectHash);
	$node002->addArrow($node002, 1, 0, 'HASH', \&collectHash1);
	$node002->addArrow($node005, 1, 0, 'HASH', \&collectHash1);
	$node003->addArrow($node003, 1, 0, 'FILE', \&collectFile);
	$node003->addArrow($node006, 1, 0, 'FILE', \&collectFile);
	$node004->addArrow($node008, 1, 0, 'to');
	$node005->addArrow($node008, 1, 0, 'from');
	$node006->addArrow($node008, 1, 0, 'to');
	$node008->addArrow($node000, 1, 0, 'and');
	$node008->addArrow($node009, 1, 0, 'message');
	$node008->addArrow($node010, 1, 0, 'private');
	$node008->addArrow($node011, 1, 0, 'public');
	$node008->addArrow($node012, 0, 0, 'messages', \&collectMessages);
	$node008->addArrow($node012, 0, 0, 'private', \&collectPrivate);
	$node008->addArrow($node012, 0, 0, 'public', \&collectPublic);
	$node008->addArrow($node016, 1, 0, 'BOX', \&collectBox);
	$node009->addArrow($node012, 1, 0, 'box', \&collectMessages);
	$node010->addArrow($node012, 1, 0, 'box', \&collectPrivate);
	$node011->addArrow($node012, 1, 0, 'box', \&collectPublic);
	$node012->addArrow($node013, 1, 0, 'of');
	$node013->addArrow($node014, 1, 0, 'ACTOR', \&collectActor);
	$node013->addArrow($node014, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node013->addArrow($node016, 1, 1, 'ACCOUNT', \&collectAccount);
	$node014->addArrow($node015, 1, 0, 'on');
	$node014->addDefault($node016);
	$node015->addArrow($node016, 1, 0, 'STORE', \&collectStore);
}

sub collectAccount($o, $label, $value) {
	$o:boxToken = CDS::BoxToken->new($value, $o:boxLabel);
	delete $o:boxLabel;
}

sub collectActor($o, $label, $value) {
	$o:actorHash = $value;
}

sub collectBox($o, $label, $value) {
	$o:boxToken = $value;
}

sub collectFile($o, $label, $value) {
	push @$o:fileAdditions, $value;
}

sub collectHash($o, $label, $value) {
	push @$o:additions, $value;
}

sub collectHash1($o, $label, $value) {
	push @$o:removals, $value;
}

sub collectKeypair($o, $label, $value) {
	$o:actorHash = $value->publicKey->hash;
	$o:keyPairToken = $value;
}

sub collectMessages($o, $label, $value) {
	$o:boxLabel = 'messages';
}

sub collectPrivate($o, $label, $value) {
	$o:boxLabel = 'private';
}

sub collectPublic($o, $label, $value) {
	$o:boxLabel = 'public';
}

sub collectPurge($o, $label, $value) {
	$o:purge = 1;
}

sub collectStore($o, $label, $value) {
	$o:boxToken = CDS::BoxToken->new(CDS::AccountToken->new($value, $o:actorHash), $o:boxLabel);
	delete $o:boxLabel;
	delete $o:actorHash;
}

sub new($class, $actor) { bless {actor => $actor, ui => $actor->ui} }

# END AUTOGENERATED

# HTML FOLDER NAME store-modify
# HTML TITLE Modify
sub help($o, $cmd) {
	my $ui = $o:ui;
	$ui->space;
	$ui->command('cds add HASH* to BOX');
	$ui->p('Adds HASH to BOX.');
	$ui->space;
	$ui->command('cds add FILE* to BOX');
	$ui->p('Adds the envelope FILE to BOX.');
	$ui->space;
	$ui->command('cds remove HASH* from BOX');
	$ui->p('Removes HASH from BOX.');
	$ui->p('Note that the store may just mark the hash for removal, and defer its actual removal, or even cancel it. Such removals will still be reported as success.');
	$ui->space;
	$ui->command('cds purge BOX');
	$ui->p('Empties BOX, i.e., removes all its hashes.');
	$ui->space;
	$ui->command('… BOXLABEL of ACCOUNT');
	$ui->p('Modifies a box of an actor group, or account.');
	$ui->space;
	$ui->command('… BOXLABEL of KEYPAIR on STORE');
	$ui->command('… BOXLABEL of ACTOR on STORE');
	$ui->p('Modifies a box of a key pair or an actor on a specific store.');
	$ui->space;
}

sub modify($o, $cmd) {
	$o:additions = [];
	$o:removals = [];
	$cmd->collect($o);

	# Add a box using the selected store
	if ($o:actorHash && $o:boxLabel) {
		$o:boxToken = CDS::BoxToken->new(CDS::AccountToken->new($o:actor->preferredStore, $o:actorHash), $o:boxLabel);
		delete $o:actorHash;
		delete $o:boxLabel;
	}

	my $store = $o:boxToken->accountToken->cliStore;

	# Prepare additions
	my $modifications = CDS::StoreModifications->new;
	for my $hash (@$o:additions) {
		$modifications->add($o:boxToken->accountToken->actorHash, $o:boxToken->boxLabel, $hash);
	}

	for my $file (@$o:fileAdditions) {
		my $bytes = CDS->readBytesFromFile($file) // return $o:ui->error('Unable to read "', $file, '".');
		my $object = CDS::Object->fromBytes($bytes) // return $o:ui->error('"', $file, '" is not a Condensation object.');
		my $hash = $object->calculateHash;
		$o:ui->warning('"', $file, '" is not a valid envelope. The server may reject it.') if ! $o:actor->isEnvelope($object);
		$modifications->add($o:boxToken->accountToken->actorHash, $o:boxToken->boxLabel, $hash, $object);
	}

	# Prepare removals
	my $boxRemovals = [];
	for my $hash (@$o:removals) {
		$modifications->remove($o:boxToken->accountToken->actorHash, $o:boxToken->boxLabel, $hash);
	}

	# If purging is requested, list the box
	if ($o:purge) {
		my ($hashes, $error) = $store->list($o:boxToken->accountToken->actorHash, $o:boxToken->boxLabel, 0);
		return if defined $error;
		$o:ui->warning('The box is empty.') if ! scalar @$hashes;

		for my $hash (@$hashes) {
			$modifications->remove($o:boxToken->accountToken->actorHash, $o:boxToken->boxLabel, $hash);
		}
	}

	# Cancel if there is nothing to do
	return if $modifications->isEmpty;

	# Modify the box
	my $keyPairToken = $o:keyPairToken // $o:actor->preferredKeyPairToken;
	my $error = $store->modify($modifications, $keyPairToken->keyPair);
	$o:ui->pGreen('Box modified.') if ! defined $error;

	# Print undo information
	if ($o:purge && scalar @$boxRemovals) {
		$o:ui->space;
		$o:ui->line($o:ui->gray('To undo purging, type:'));
		$o:ui->line($o:ui->gray('  cds add ', join(" \\\n         ", map { $_:hash->hex } @$boxRemovals), " \\\n         to ", $o:actor->boxReference($o:boxToken)));
		$o:ui->space;
	}
}
