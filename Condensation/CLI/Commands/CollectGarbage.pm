# BEGIN AUTOGENERATED

sub register($class, $cds, $help) {
	my $node000 = CDS::Parser::Node->new(0);
	my $node001 = CDS::Parser::Node->new(0);
	my $node002 = CDS::Parser::Node->new(0);
	my $node003 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&help});
	my $node004 = CDS::Parser::Node->new(0, {constructor => \&new, function => \&collectGarbage});
	my $node005 = CDS::Parser::Node->new(0);
	my $node006 = CDS::Parser::Node->new(0, {constructor => \&new, function => \&reportGarbage});
	my $node007 = CDS::Parser::Node->new(0);
	my $node008 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&collectGarbage});
	my $node009 = CDS::Parser::Node->new(1, {constructor => \&new, function => \&reportGarbage});
	$cds->addArrow($node001, 1, 0, 'report');
	$cds->addArrow($node002, 1, 0, 'collect');
	$help->addArrow($node000, 1, 0, 'collect');
	$node000->addArrow($node003, 1, 0, 'garbage');
	$node001->addArrow($node006, 1, 0, 'garbage');
	$node002->addArrow($node004, 1, 0, 'garbage');
	$node004->addArrow($node005, 1, 0, 'of');
	$node004->addDefault($node008);
	$node005->addArrow($node008, 1, 0, 'STORE', \&collectStore);
	$node006->addArrow($node007, 1, 0, 'of');
	$node006->addDefault($node009);
	$node007->addArrow($node009, 1, 0, 'STORE', \&collectStore);
}

sub collectStore($o, $label, $value) {
	$o:store = $value;
}

sub new($class, $actor) { bless {actor => $actor, ui => $actor->ui} }

# END AUTOGENERATED

# INCLUDE CollectGarbage/Delete.pm
# INCLUDE CollectGarbage/Report.pm

# HTML FOLDER NAME collect-garbage
# HTML TITLE Garbage collection
sub help($o, $cmd) {
	my $ui = $o:ui;
	$ui->space;
	$ui->command('cds collect garbage [of STORE]');
	$ui->p('Runs garbage collection. STORE must be a folder store. Objects not in use, and older than 1 day are removed from the store.');
	$ui->p('If no store is provided, garbage collection is run on the selected store, or the actor\'s storage store.');
	$ui->space;
	$ui->p('The store must not be written to while garbage collection is running. Objects booked during garbage collection may get deleted, and leave the store in a corrupt state. Reading from the store is fine.');
	$ui->space;
	$ui->command('cds report garbage [of STORE]');
	$ui->p('As above, but reports obsolete objects rather than deleting them. A protocol (shell script) is written to ".garbage" in the store folder.');
	$ui->space;
}

sub collectGarbage($o, $cmd) {
	$cmd->collect($o);
	$o->run(CDS::Commands::CollectGarbage::Delete->new($o:ui));
}

sub wrapUpDeletion($o) { }

sub reportGarbage($o, $cmd) {
	$cmd->collect($o);
	$o->run(CDS::Commands::CollectGarbage::Report->new($o:ui));
	$o:ui->space;
}

# Creates a folder with the selected permissions.
sub run($o, $handler) {
	# Prepare
	my $store = $o:store // $o:actor->selectedStore // $o:actor->storageStore;
	my $folderStore = CDS::FolderStore->forUrl($store->url) // return $o:ui->error('"', $store->url, '" is not a folder store.');
	$handler->initialize($folderStore) // return;

	$o:storeFolder = $folderStore->folder;
	$o:accountsFolder = $folderStore->folder.'/accounts';
	$o:objectsFolder = $folderStore->folder.'/objects';
	my $dateLimit = time - 86400;
	my $envelopeExpirationLimit = time * 1000;

	# Read the tree index
	$o->readIndex;

	# Process all accounts
	$o:ui->space;
	$o:ui->title($o:ui->left(64, 'Accounts'), '   ', $o:ui->right(10, 'messages'), ' ', $o:ui->right(10, 'private'), ' ', $o:ui->right(10, 'public'), '   ', 'last modification');
	$o->startProgress('accounts');
	$o:usedHashes = {};
	$o:missingObjects = {};
	$o:brokenOrigins = {};
	my $countAccounts = 0;
	my $countKeptEnvelopes = 0;
	my $countDeletedEnvelopes = 0;
	for my $accountHash (sort { $$a cmp $$b } $folderStore->accounts) {
		# This would be the private key, but we don't use it right now
		$o:usedHashes->{$accountHash->hex} = 1;

		my $newestDate = 0;
		my %sizeByBox;
		my $accountFolder = $o:accountsFolder.'/'.$accountHash->hex;
		foreach my $boxLabel (CDS->listFolder($accountFolder)) {
			next if $boxLabel =~ /^\./;
			my $boxFolder = $accountFolder.'/'.$boxLabel;
			my $date = &lastModified($boxFolder);
			$newestDate = $date if $newestDate < $date;
			my $size = 0;
			foreach my $filename (CDS->listFolder($boxFolder)) {
				next if $filename =~ /^\./;
				my $hash = pack('H*', $filename);
				my $file = $boxFolder.'/'.$filename;

				my $timestamp = $o->envelopeExpiration($hash, $boxFolder);
				if ($timestamp > 0 && $timestamp < $envelopeExpirationLimit) {
					$countDeletedEnvelopes += 1;
					$handler->deleteEnvelope($file) // return;
					next;
				}

				$countKeptEnvelopes += 1;
				my $date = &lastModified($file);
				$newestDate = $date if $newestDate < $date;
				$size += $o->traverse($hash, $boxFolder);
			}
			$sizeByBox{$boxLabel} = $size;
		}

		$o:ui->line($accountHash->hex, '   ',
			$o:ui->right(10, $o:ui->niceFileSize($sizeByBox{'messages'} || 0)), ' ',
			$o:ui->right(10, $o:ui->niceFileSize($sizeByBox{'private'} || 0)), ' ',
			$o:ui->right(10, $o:ui->niceFileSize($sizeByBox{'public'} || 0)), '   ',
			$newestDate == 0 ? 'never' : $o:ui->niceDateTime($newestDate * 1000));

		$countAccounts += 1;
	}

	$o:ui->line($countAccounts, ' accounts traversed');
	$o:ui->space;

	# Mark all objects that are younger than 1 day (so that objects being uploaded right now but not linked yet remain)
	$o:ui->title('Objects');
	$o->startProgress('objects');

	my %objects;
	my @topFolders = sort grep {$_ !~ /^\./} CDS->listFolder($o:objectsFolder);
	foreach my $topFolder (@topFolders) {
		my @files = sort grep {$_ !~ /^\./} CDS->listFolder($o:objectsFolder.'/'.$topFolder);
		foreach my $filename (@files) {
			$o->incrementProgress;
			my $hash = pack 'H*', $topFolder.$filename;
			my @s = stat $o:objectsFolder.'/'.$topFolder.'/'.$filename;
			$objects{$hash} = $s[7];
			next if $s[9] < $dateLimit;
			$o->traverse($hash, 'recent object');
		}
	}

	$o:ui->line(scalar keys %objects, ' objects traversed');
	$o:ui->space;

	# Delete all unmarked objects, and add the marked objects to the new tree index
	my $index = CDS::Record->new;
	my $countKeptObjects = 0;
	my $sizeKeptObjects = 0;
	my $countDeletedObjects = 0;
	my $sizeDeletedObjects = 0;

	$handler->startDeletion;
	$o->startProgress('delete-objects');
	for my $hash (keys %objects) {
		my $size = $objects{$hash};
		if (exists $o:usedHashes->{$hash}) {
			$countKeptObjects += 1;
			$sizeKeptObjects += $size;
			my $entry = $o:index->{$hash};
			$index->addRecord($entry) if $entry;
		} else {
			$o->incrementProgress;
			$countDeletedObjects += 1;
			$sizeDeletedObjects += $size;
			my $hashHex = unpack 'H*', $hash;
			my $file = $o:objectsFolder.'/'.substr($hashHex, 0, 2).'/'.substr($hashHex, 2);
			$handler->deleteObject($file) // return;
		}
	}

	# Write the new tree index
	CDS->writeBytesToFile($o:storeFolder.'/.index-new', $index->toObject->bytes);
	rename $o:storeFolder.'/.index-new', $o:storeFolder.'/.index';

	# Show what has been done
	$o:ui->space;
	$o:ui->line($countDeletedEnvelopes, ' ', $handler:deletedEnvelopesText);
	$o:ui->line($countKeptEnvelopes, ' ', $handler:keptEnvelopesText);
	my $line1 = $countDeletedObjects.' '.$handler:deletedObjectsText;
	my $line2 = $countKeptObjects.' '.$handler:keptObjectsText;
	my $maxLength = CDS->max(length $line1, length $line2);
	$o:ui->line($o:ui->left($maxLength, $line1), '  ', $o:ui->gray($o:ui->niceFileSize($sizeDeletedObjects)));
	$o:ui->line($o:ui->left($maxLength, $line2), '  ', $o:ui->gray($o:ui->niceFileSize($sizeKeptObjects)));
	$o:ui->space;
	$handler->wrapUp;

	my $missing = scalar keys %$o:missingObjects;
	if ($missing) {
		$o:ui->warning($missing, ' objects are referenced from other objects, but missing:');

		my $count = 0;
		for my $hashBytes (sort keys %$o:missingObjects) {
			$o:ui->warning('  ', unpack('H*', $hashBytes));

			$count += 1;
			if ($missing > 10 && $count > 5) {
				$o:ui->warning('  …');
				last;
			}
		}

		$o:ui->space;
		$o:ui->warning('The missing objects are from the following origins:');
		for my $origin (sort keys %$o:brokenOrigins) {
			$o:ui->line('  ', $o:ui->orange($origin));
		}

		$o:ui->space;
	}
}

sub traverse($o, $hashBytes, $origin) {
	return $o:usedHashes->{$hashBytes} if exists $o:usedHashes->{$hashBytes};

	# Get index information about the object
	my $record = $o->index($hashBytes, $origin) // return 0;
	my $size = $record->nthChild(0)->asInteger;

	# Process children
	my $pos = 0;
	my $hashes = $record->nthChild(1)->bytes;
	while ($pos < length $hashes) {
		$size += $o->traverse(substr($hashes, $pos, 32), $origin);
		$pos += 32;
	}

	# Keep the size for future use
	$o:usedHashes->{$hashBytes} = $size;
	return $size;
}

sub readIndex($o) {
	$o:index = {};
	my $file = $o:storeFolder.'/.index';
	my $record = CDS::Record->fromObject(CDS::Object->fromBytes(CDS->readBytesFromFile($file))) // return;
	for my $child ($record->children) {
		$o:index->{$child->bytes} = $child;
	}
}

sub index($o, $hashBytes, $origin) {
	$o->incrementProgress;

	# Report a known result
	if ($o:missingObjects->{$hashBytes}) {
		$o:brokenOrigins->{$origin} = 1;
		return;
	}

	return $o:index->{$hashBytes} if exists $o:index->{$hashBytes};

	# Object file
	my $hashHex = unpack 'H*', $hashBytes;
	my $file = $o:objectsFolder.'/'.substr($hashHex, 0, 2).'/'.substr($hashHex, 2);

	# Size and existence
	my @s = stat $file;
	if (! scalar @s) {
		$o:missingObjects->{$hashBytes} = 1;
		$o:brokenOrigins->{$origin} = 1;
		return;
	}
	my $size = $s[7];
	return $o:ui->error('Unexpected: object ', $hashHex, ' has ', $size, ' bytes') if $size < 4;

	# Read header
	open O, '<', $file;
	read O, my $buffer, 4;
	my $links = unpack 'L>', $buffer;
	return $o:ui->error('Unexpected: object ', $hashHex, ' has ', $links, ' references') if $links > 160000;
	return $o:ui->error('Unexpected: object ', $hashHex, ' is too small for ', $links, ' references') if 4 + $links * 32 > $s[7];
	my $hashes = '';
	read O, $hashes, $links * 32 if $links > 0;
	close O;

	return $o:ui->error('Incomplete read: ', length $hashes, ' out of ', $links * 32, ' bytes received.') if length $hashes != $links * 32;

	my $record = CDS::Record->new($hashBytes);
	$record->addInteger($size);
	$record->add($hashes);
	return $o:index->{$hashBytes} = $record;
}

sub envelopeExpiration($o, $hashBytes, $origin) {
	my $entry = $o->index($hashBytes, $origin) // return 0;
	return $entry->nthChild(2)->asInteger if scalar $entry->children > 2;

	# Object file
	my $hashHex = unpack 'H*', $hashBytes;
	my $file = $o:objectsFolder.'/'.substr($hashHex, 0, 2).'/'.substr($hashHex, 2);
	my $record = CDS::Record->fromObject(CDS::Object->fromBytes(CDS->readBytesFromFile($file)));
	my $expires = $record->child('expires')->integerValue;
	$entry->addInteger($expires);
	return $expires;
}

sub startProgress($o, $title) {
	$o:progress = 0;
	$o:progressTitle = $title;
	$o:ui->progress($o:progress, ' ', $o:progressTitle);
}

sub incrementProgress($o) {
	$o:progress += 1;
	return if $o:progress % 100;
	$o:ui->progress($o:progress, ' ', $o:progressTitle);
}

sub lastModified($file) {
	my @s = stat $file;
	return scalar @s ? $s[9] : 0;
}
