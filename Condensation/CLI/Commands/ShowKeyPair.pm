# BEGIN AUTOGENERATED

sub register($class, $cds, $help) {
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(0);
	my $node004 = CDS::Parser::Node->new(0);
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0);
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node009 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showKeyPair});
	my $node010 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showMyKeyPair});
	my $node011 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&showSelectedKeyPair});
	$cds->addArrow($node002, 1, 0, 'show');
	$cds->addArrow($node003, 1, 0, 'show');
	$cds->addArrow($node004, 1, 0, 'show');
	$help->addArrow($node000, 1, 0, 'show');
	$node000->addArrow($node001, 1, 0, 'key');
	$node001->addArrow($node008, 1, 0, 'pair');
	$node002->addArrow($node009, 1, 0, 'KEYPAIR', \&collectKeypair);
	$node003->addArrow($node005, 1, 0, 'my');
	$node004->addArrow($node006, 1, 0, 'key');
	$node005->addArrow($node007, 1, 0, 'key');
	$node006->addArrow($node011, 1, 0, 'pair');
	$node007->addArrow($node010, 1, 0, 'pair');
}

sub collectKeypair($o, $label, $value) {
	$o:keyPairToken = $value;
}

sub new($class, $actor) { bless {actor => $actor, ui => $actor->ui} }

# END AUTOGENERATED

# HTML FOLDER NAME show-key-pair
# HTML TITLE Show key pair
sub help($o, $cmd) {
	my $ui = $o:ui;
	$ui->space;
	$ui->command('cds show KEYPAIR');
	$ui->command('cds show my key pair');
	$ui->command('cds show key pair');
	$ui->p('Shows information about KEYPAIR, your key pair, or the currently selected key pair (see "cds use …").');
	$ui->space;
}

sub showKeyPair($o, $cmd) {
	$cmd->collect($o);
	$o->showAll($o:keyPairToken);
}

sub showMyKeyPair($o, $cmd) {
	$cmd->collect($o);
	$o->showAll($o:actor->keyPairToken);
}

sub showSelectedKeyPair($o, $cmd) {
	$cmd->collect($o);
	$o->showAll($o:actor->preferredKeyPairToken);
}

sub show($o, $keyPairToken) {
	$o:ui->line($o:ui->darkBold('File  '), $keyPairToken->file) if defined $keyPairToken->file;
	$o:ui->line($o:ui->darkBold('Hash  '), $keyPairToken->keyPair->publicKey->hash->hex);
}

sub showAll($o, $keyPairToken) {
	$o:ui->space;
	$o:ui->title('Key pair');
	$o->show($keyPairToken);
	$o->showPublicKeyObject($keyPairToken);
	$o->showPublicKey($keyPairToken);
	$o->showPrivateKey($keyPairToken);
	$o:ui->space;
}

sub showPublicKeyObject($o, $keyPairToken) {
	my $object = $keyPairToken->keyPair->publicKey->object;
	$o:ui->space;
	$o:ui->title('Public key object');
	$o->byteData('      ', $object->bytes);
}

sub showPublicKey($o, $keyPairToken) {
	my $rsaPublicKey = $keyPairToken->keyPair->publicKey->{rsaPublicKey};
	$o:ui->space;
	$o:ui->title('Public key');
	$o->byteData('e     ', CDS::C::publicKeyE($rsaPublicKey));
	$o->byteData('n     ', CDS::C::publicKeyN($rsaPublicKey));
}

sub showPrivateKey($o, $keyPairToken) {
	my $rsaPrivateKey = $keyPairToken->keyPair->{rsaPrivateKey};
	$o:ui->space;
	$o:ui->title('Private key');
	$o->byteData('e     ', CDS::C::privateKeyE($rsaPrivateKey));
	$o->byteData('p     ', CDS::C::privateKeyP($rsaPrivateKey));
	$o->byteData('q     ', CDS::C::privateKeyQ($rsaPrivateKey));
}

sub byteData($o, $label, $bytes) {
	my $hex = unpack('H*', $bytes);
	$o:ui->line($o:ui->darkBold($label), substr($hex, 0, 64));

	my $start = 64;
	my $spaces = ' ' x length $label;
	while ($start < length $hex) {
		$o:ui->line($spaces, substr($hex, $start, 64));
		$start += 64;
	}
}
