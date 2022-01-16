sub new($class, $ui) {
	return bless {ui => $ui, failedStores => {}};
}

sub ui;

sub uncachedStoreForUrl($o, $url) {
	my $store =
		CDS::FolderStore->forUrl($url) //
		CDS::HTTPStore->forUrl($url) //
		undef;
	my $progressStore = CDS::UI::ProgressStore->new($store, $url, $o:ui);
	return CDS::ErrorHandlingStore->new($progressStore, $url, $o);
}

sub onStoreSuccess($o, $store, $function) {
	delete $o:failedStores->{$store->store->id};
}

sub onStoreError($o, $store, $function, $error) {
	$o:failedStores->{$store->store->id} = 1;
	$o:ui->error('The store "', $store:url, '" reports: ', $error);
}

sub hasStoreError($o, $store, $function) {
	return if ! $o:failedStores->{$store->store->id};
	$o:ui->error('Ignoring store "', $store:url, '", because it previously reported errors.');
	return 1;
}
