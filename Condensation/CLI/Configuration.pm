our $xdgConfigurationFolder = ($ENV{XDG_CONFIG_HOME} || $ENV{HOME}.'/.config').'/condensation';
our $xdgDataFolder = ($ENV{XDG_DATA_HOME} || $ENV{HOME}.'/.local/share').'/condensation';

sub getOrCreateDefault($class, $ui) {
	my $configuration = $class->new($ui, $xdgConfigurationFolder, $xdgDataFolder);
	$configuration->createIfNecessary();
	return $configuration;
}

sub new($class, $ui, $folder, $defaultStoreFolder) {
	return bless {ui => $ui, folder => $folder, defaultStoreFolder => $defaultStoreFolder};
}

sub ui;
sub folder;

sub createIfNecessary($o) {
	my $keyPairFile = $o:folder.'/key-pair';
	return 1 if -f $keyPairFile;

	$o:ui->progress('Creating configuration folders …');
	$o->createFolder($o:folder) // return $o:ui->error('Failed to create the folder "', $o:folder, '".');
	$o->createFolder($o:defaultStoreFolder) // return $o:ui->error('Failed to create the folder "', $o:defaultStoreFolder, '".');
	CDS::FolderStore->new($o:defaultStoreFolder)->createIfNecessary;

	$o:ui->progress('Generating key pair …');
	my $keyPair = CDS::KeyPair->generate;
	$keyPair->writeToFile($keyPairFile) // return $o:ui->error('Failed to write the configuration file "', $keyPairFile, '". Make sure that this location is writable.');
	$o:ui->removeProgress;
	return 1;
}

sub createFolder($o, $folder) {
	for my $path (CDS->intermediateFolders($folder)) {
		mkdir $path;
	}

	return -d $folder;
}

sub file($o, $filename) {
	return $o:folder.'/'.$filename;
}

sub messagingStoreUrl($o) {
	return $o->readFirstLine('messaging-store') // 'file://'.$o:defaultStoreFolder;
}

sub storageStoreUrl($o) {
	return $o->readFirstLine('store') // 'file://'.$o:defaultStoreFolder;
}

sub setMessagingStoreUrl($o, $storeUrl) {
	CDS->writeTextToFile($o->file('messaging-store'), $storeUrl);
}

sub setStorageStoreUrl($o, $storeUrl) {
	CDS->writeTextToFile($o->file('store'), $storeUrl);
}

sub keyPair($o) {
	return CDS::KeyPair->fromFile($o->file('key-pair'));
}

sub setKeyPair($o, $keyPair) {
	$keyPair->writeToFile($o->file('key-pair'));
}

sub readFirstLine($o, $file) {
	my $content = CDS->readTextFromFile($o->file($file)) // return;
	$content = $1 if $content =~ /^(.*)\n/;
	$content = $1 if $content =~ /^\s*(.*?)\s*$/;
	return $content;
}
