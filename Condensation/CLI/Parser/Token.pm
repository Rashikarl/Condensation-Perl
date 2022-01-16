use Cwd;
use Encode;

sub new($class, $actor, $text) {
	return bless {
		actor => $actor,
		text => $text,
		keywords => {},
		cache => {},
		warnings => [],
		possibilities => [],
		};
}

sub prepare($o, $expect) {
	$o:keywords->{$expect} = 1 if $expect =~ /^[a-z0-9]*$/;
}

sub as($o, $expect) { exists $o:cache->{$expect} ? $o:cache->{$expect} : $o:cache->{$expect} = $o->produce($expect) }

sub produce($o, $expect) {
	return $o->account if $expect eq 'ACCOUNT';
	return $o->hash if $expect eq 'ACTOR';
	return $o->actorGroup if $expect eq 'ACTORGROUP';
	return $o->aesKey if $expect eq 'AESKEY';
	return $o->box if $expect eq 'BOX';
	return $o->boxLabel if $expect eq 'BOXLABEL';
	return $o->file if $expect eq 'FILE';
	return $o->filename if $expect eq 'FILENAME';
	return $o->folder if $expect eq 'FOLDER';
	return $o->foldername if $expect eq 'FOLDERNAME';
	return $o->group if $expect eq 'GROUP';
	return $o->hash if $expect eq 'HASH';
	return $o->keyPair if $expect eq 'KEYPAIR';
	return $o->label if $expect eq 'LABEL';
	return $o->object if $expect eq 'OBJECT';
	return $o->objectFile if $expect eq 'OBJECTFILE';
	return $o->port if $expect eq 'PORT';
	return $o->store if $expect eq 'STORE';
	return $o->text if $expect eq 'TEXT';
	return $o->user if $expect eq 'USER';
	return $o:text eq $expect ? '' : undef;
}

sub complete($o, $expect) {
	return $o->completeAccount if $expect eq 'ACCOUNT';
	return $o->completeHash if $expect eq 'ACTOR';
	return $o->completeActorGroup if $expect eq 'ACTORGROUP';
	return if $expect eq 'AESKEY';
	return $o->completeBox if $expect eq 'BOX';
	return $o->completeBoxLabel if $expect eq 'BOXLABEL';
	return $o->completeFile if $expect eq 'FILE';
	return $o->completeFile if $expect eq 'FILENAME';
	return $o->completeFolder if $expect eq 'FOLDER';
	return $o->completeFolder if $expect eq 'FOLDERNAME';
	return $o->completeGroup if $expect eq 'GROUP';
	return $o->completeHash if $expect eq 'HASH';
	return $o->completeKeyPair if $expect eq 'KEYPAIR';
	return $o->completeLabel if $expect eq 'LABEL';
	return $o->completeObject if $expect eq 'OBJECT';
	return $o->completeObjectFile if $expect eq 'OBJECTFILE';
	return $o->completeStoreUrl if $expect eq 'STORE';
	return $o->completeUser if $expect eq 'USER';
	return if $expect eq 'TEXT';
	$o->addPossibility($expect);
}

sub addPossibility($o, $possibility) {
	push @$o:possibilities, $possibility.' ' if substr($possibility, 0, length $o:text) eq $o:text;
}

sub addPartialPossibility($o, $possibility) {
	push @$o:possibilities, $possibility if substr($possibility, 0, length $o:text) eq $o:text;
}

sub isKeyword($o) { exists $o:keywords->{$o:text} }

sub account($o) {
	# From a remembered account
	my $record = $o:actor->remembered($o:text);
	my $storeUrl = $record->child('store')->textValue;
	my $actorHash = CDS::Hash->fromBytes($record->child('actor')->bytesValue);
	if ($actorHash && length $storeUrl) {
		my $store = $o:actor->storeForUrl($storeUrl) // return $o->warning('Invalid store URL "', $storeUrl, '" in remembered account.');
		my $accountToken = CDS::AccountToken->new($store, $actorHash);
		return $o->warning('"', $o:text, '" is interpreted as a keyword. If you mean the account, write "', $accountToken->url, '".') if $o->isKeyword;
		return $accountToken;
	}

	# From a URL
	if ($o:text =~ /^\s*(.*?)\/accounts\/([0-9a-fA-F]{64,64})\/*\s*$/) {
		my $storeUrl = $1;
		my $actorHash = CDS::Hash->fromHex($2);
		$storeUrl = 'file://'.Cwd::abs_path($storeUrl) if $storeUrl !~ /^[a-zA-Z0-9_\+-]*:/ && -d $storeUrl;
		my $cliStore = $o:actor->storeForUrl($storeUrl) // return $o->warning('Invalid store URL "', $storeUrl, '".');
		return CDS::AccountToken->new($cliStore, $actorHash);
	}

	return;
}

sub completeAccount($o) {
	$o->completeUrl;

	my $records = $o:actor->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		my $storeUrl = $record->child('store')->textValue;
		next if ! length $storeUrl;
		my $actorHash = CDS::Hash->fromBytes($record->child('actor')->bytesValue) // next;

		$o->addPossibility($label);
		$o->addPossibility($storeUrl.'/accounts/'.$actorHash->hex);
	}

	return;
}

sub aesKey($o) {
	$o:text =~ /^[0-9A-Fa-f]{64}$/ || return;
	return pack('H*', $o:text);
}

sub box($o) {
	# From a URL
	if ($o:text =~ /^\s*(.*?)\/accounts\/([0-9a-fA-F]{64,64})\/(messages|private|public)\/*\s*$/) {
		my $storeUrl = $1;
		my $boxLabel = $3;
		my $actorHash = CDS::Hash->fromHex($2);
		$storeUrl = 'file://'.Cwd::abs_path($storeUrl) if $storeUrl !~ /^[a-zA-Z0-9_\+-]*:/ && -d $storeUrl;
		my $cliStore = $o:actor->storeForUrl($storeUrl) // return $o->warning('Invalid store URL "', $storeUrl, '".');
		my $accountToken = CDS::AccountToken->new($cliStore, $actorHash);
		return CDS::BoxToken->new($accountToken, $boxLabel);
	}

	return;
}

sub completeBox($o) {
	$o->completeUrl;
	return;
}

sub boxLabel($o) {
	return $o:text if $o:text eq 'messages';
	return $o:text if $o:text eq 'private';
	return $o:text if $o:text eq 'public';
	return;
}

sub completeBoxLabel($o) {
	$o->addPossibility('messages');
	$o->addPossibility('private');
	$o->addPossibility('public');
}

sub file($o) {
	my $file = Cwd::abs_path($o:text) // return;
	return if ! -f $file;
	return $o->warning('"', $o:text, '" is interpreted as keyword. If you mean the file, write "./', $o:text, '".') if $o->isKeyword;
	return $file;
}

sub completeFile($o) {
	my $folder = './';
	my $startFilename = $o:text;
	$startFilename = $ENV{HOME}.'/'.$1 if $startFilename =~ /^~\/(.*)$/;
	if ($startFilename eq '~') {
		$folder = $ENV{HOME}.'/';
		$startFilename = '';
	} elsif ($startFilename =~ /^(.*\/)([^\/]*)$/) {
		$folder = $1;
		$startFilename = $2;
	}

	for my $filename (CDS->listFolder($folder)) {
		next if $filename eq '.';
		next if $filename eq '..';
		next if substr($filename, 0, length $startFilename) ne $startFilename;
		my $file = $folder.$filename;
		$file .= '/' if -d $file;
		$file .= ' ' if -f $file;
		push @$o:possibilities, $file;
	}
}

sub filename($o) {
	return $o->warning('"', $o:text, '" is interpreted as keyword. If you mean the file, write "./', $o:text, '".') if $o->isKeyword;
	return Cwd::abs_path($o:text);
}

sub folder($o) {
	my $folder = Cwd::abs_path($o:text) // return;
	return if ! -d $folder;
	return $o->warning('"', $o:text, '" is interpreted as keyword. If you mean the folder, write "./', $o:text, '".') if $o->isKeyword;
	return $folder;
}

sub completeFolder($o) {
	my $folder = './';
	my $startFilename = $o:text;
	if ($o:text =~ /^(.*\/)([^\/]*)$/) {
		$folder = $1;
		$startFilename = $2;
	}

	for my $filename (CDS->listFolder($folder)) {
		next if $filename eq '.';
		next if $filename eq '..';
		next if substr($filename, 0, length $startFilename) ne $startFilename;
		my $file = $folder.$filename;
		next if ! -d $file;
		push @$o:possibilities, $file.'/';
	}
}

sub foldername($o) {
	return $o->warning('"', $o:text, '" is interpreted as keyword. If you mean the folder, write "./', $o:text, '".') if $o->isKeyword;
	return Cwd::abs_path($o:text);
}

sub group($o) {
	return int($1) if $o:text =~ /^\s*(\d{1,5})\s*$/;
	return getgrnam($o:text);
}

sub completeGroup($o) {
	while (my $name = getgrent) {
		$o->addPossibility($name);
	}
}

sub hash($o) {
	my $hash = CDS::Hash->fromHex($o:text);
	return $hash if $hash;

	# Check if it's a remembered actor hash
	my $record = $o:actor->remembered($o:text);
	my $actorHash = CDS::Hash->fromBytes($record->child('actor')->bytesValue) // return;
	return $o->warning('"', $o:text, '" is interpreted as keyword. If you mean the actor, write "', $actorHash->hex, '".') if $o->isKeyword;
	return $actorHash;
}

sub completeHash($o) {
	my $records = $o:actor->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		my $hash = CDS::Hash->fromBytes($record->child('actor')->bytesValue) // next;
		$o->addPossibility($label);
		$o->addPossibility($hash->hex);
	}

	for my $child ($o:actor->actorGroupSelector->children) {
		my $hash = $child->record->child('hash')->hashValue // next;
		$o->addPossibility($hash->hex);
	}
}

sub keyPair($o) {
	# Remembered key pair
	my $record = $o:actor->remembered($o:text);
	my $file = $record->child('key pair')->textValue;

	# Key pair from file
	if (! length $file) {
		$file = Cwd::abs_path($o:text) // return;
		return $o->warning('"', $o:text, '" is interpreted as keyword. If you mean the file, write "./', $o:text, '".') if $o->isKeyword && -f $file;
	}

	# Load the key pair
	return if ! -f $file;
	my $bytes = CDS->readBytesFromFile($file) // return $o->warning('The key pair file "', $file, '" could not be read.');
	my $keyPair = CDS::KeyPair->fromRecord(CDS::Record->fromObject(CDS::Object->fromBytes($bytes))) // return $o->warning('The file "', $file, '" does not contain a key pair.');
	return CDS::KeyPairToken->new($file, $keyPair);
}

sub completeKeyPair($o) {
	$o->completeFile;

	my $records = $o:actor->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if ! length $record->child('key pair')->textValue;
		$o->addPossibility($label);
	}
}

sub label($o) {
	my $records = $o:actor->remembered($o:text);
	return $o:text if $records->children;
	return;
}

sub completeLabel($o) {
	my $records = $o:actor->rememberedRecords;
	for my $label (keys %$records) {
		next if substr($label, 0, length $o:text) ne $o:text;
		$o->addPossibility($label);
	}
}

sub object($o) {
	# Folder stores use the first two hex digits as folder
	my $url = $o:text =~ /^\s*(.*?\/objects\/)([0-9a-fA-F]{2,2})\/([0-9a-fA-F]{62,62})\/*\s*$/ ? $1.$2.$3 : $o:text;

	# From a URL
	if ($url =~ /^\s*(.*?)\/objects\/([0-9a-fA-F]{64,64})\/*\s*$/) {
		my $storeUrl = $1;
		my $hash = CDS::Hash->fromHex($2);
		$storeUrl = 'file://'.Cwd::abs_path($storeUrl) if $storeUrl !~ /^[a-zA-Z0-9_\+-]*:/ && -d $storeUrl;
		my $cliStore = $o:actor->storeForUrl($storeUrl) // return $o->warning('Invalid store URL "', $storeUrl, '".');
		return CDS::ObjectToken->new($cliStore, $hash);
	}

	return;
}

sub completeObject($o) {
	$o->completeUrl;
	return;
}

sub objectFile($o) {
	# Key pair from file
	my $file = Cwd::abs_path($o:text) // return;
	return $o->warning('"', $o:text, '" is interpreted as keyword. If you mean the file, write "./', $o:text, '".') if $o->isKeyword && -f $file;

	# Load the object
	return if ! -f $file;
	my $bytes = CDS->readBytesFromFile($file) // return $o->warning('The object file "', $file, '" could not be read.');
	my $object = CDS::Object->fromBytes($bytes) // return $o->warning('The file "', $file, '" does not contain a Condensation object.');
	return CDS::ObjectFileToken->new($file, $object);
}

sub completeObjectFile($o) {
	$o->completeFile;
	return;
}

sub actorGroup($o) {
	# We only accept named actor groups. Accepting a single account as actor group is ambiguous whenever ACCOUNT and ACTORGROUP are accepted. For commands that are requiring an ACTORGROUP, they can also accept an ACCOUNT and then convert it.

	# Check if it's an actor group label
	my $record = $o:actor->remembered($o:text)->child('actor group');
	return if ! scalar $record->children;
	return $o->warning('"', $o:text, '" is interpreted as keyword. To refer to the actor group, rename it.') if $o->isKeyword;

	my $builder = CDS::ActorGroupBuilder->new;
	$builder->addKnownPublicKey($o:actor->keyPair->publicKey);
	$builder->parse($record, 1);
	my ($actorGroup, $storeError) = $builder->load($o:actor->groupDataTree->unsaved, $o:actor->keyPair, $o);
	return $o:actor->storeError($o:actor->storageStore, $storeError) if defined $storeError;
	return CDS::ActorGroupToken->new($o:text, $actorGroup);
}

sub onLoadActorGroupVerifyStore($o, $storeUrl) { $o:actor->storeForUrl($storeUrl); }

sub completeActorGroup($o) {
	my $records = $o:actor->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if ! scalar $record->child('actor group')->children;
		$o->addPossibility($label);
	}
	return;
}

sub port($o) {
	my $port = int($o:text);
	return if $port <= 0 || $port > 65536;
	return $port;
}

sub rememberedStoreUrl($o) {
	my $record = $o:actor->remembered($o:text);
	my $storeUrl = $record->child('store')->textValue;
	return if ! length $storeUrl;

	return $o->warning('"', $o:text, '" is interpreted as keyword. If you mean the store, write "', $storeUrl, '".') if $o->isKeyword;
	return $storeUrl;
}

sub directStoreUrl($o) {
	return $o->warning('"', $o:text, '" is interpreted as keyword. If you mean the folder store, write "./', $o:text, '".') if $o->isKeyword;
	return if $o:text =~ /[0-9a-f]{32}/;

	return $o:text if $o:text =~ /^[a-zA-Z0-9_\+-]*:/;
	return 'file://'.Cwd::abs_path($o:text) if -d $o:text && -d $o:text.'/accounts' && -d $o:text.'/objects';
	return;
}

sub store($o) {
	my $url = $o->rememberedStoreUrl // $o->directStoreUrl // return;
	return $o:actor->storeForUrl($url) // return $o->warning('"', $o:text, '" looks like a store, but no implementation is available to handle this protocol.');
}

sub completeFolderStoreUrl($o) {
	my $folder = './';
	my $startFilename = $o:text;
	if ($o:text =~ /^(.*\/)([^\/]*)$/) {
		$folder = $1;
		$startFilename = $2;
	}

	for my $filename (CDS->listFolder($folder)) {
		next if $filename eq '.';
		next if $filename eq '..';
		next if substr($filename, 0, length $startFilename) ne $startFilename;
		my $file = $folder.$filename;
		next if ! -d $file;
		push @$o:possibilities, $file . (-d $file.'/accounts' && -d $file.'/objects' ? ' ' : '/');
	}
}

sub completeStoreUrl($o) {
	$o->completeFolderStoreUrl;
	$o->completeUrl;

	my $records = $o:actor->rememberedRecords;
	for my $label (keys %$records) {
		my $record = $records->{$label};
		next if length $record->child('actor')->bytesValue;
		my $storeUrl = $record->child('store')->textValue;
		next if ! length $storeUrl;
		$o->addPossibility($label);
		$o->addPossibility($storeUrl);
	}
}

sub completeUrl($o) {
	$o->addPartialPossibility('http://');
	$o->addPartialPossibility('https://');
	$o->addPartialPossibility('ftp://');
	$o->addPartialPossibility('sftp://');
	$o->addPartialPossibility('file://');
}

sub text($o) {
	return $o:text;
}

sub user($o) {
	return int($1) if $o:text =~ /^\s*(\d{1,5})\s*$/;
	return getpwnam($o:text);
}

sub completeUser($o) {
	while (my $name = getpwent) {
		$o->addPossibility($name);
	}
}

sub warning($o; @text) {
	push @$o:warnings, join('', @_);
	return;
}
