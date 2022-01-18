sub new($class, $ui) {
	return bless {ui => $ui, failedStores => {}};
}

sub ui;

sub rawStoreForUrl($o, $url) {
	return if ! $url;
	return
		CDS::FolderStore->forUrl($url) //
		CDS::HTTPStore->forUrl($url) //
		undef;
}

sub storeForUrl($o, $url) {
	my $store = $o->rawStoreForUrl($url);
	my $progressStore = CDS::UI::ProgressStore->new($store, $url, $o:ui);
	my $cachedStore = defined $o:cacheStore ? CDS::ObjectCache->new($progressStore, $o:cacheStore) : $progressStore;
	return CDS::ErrorHandlingStore->new($cachedStore, $url, $o);
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

sub setCacheStoreUrl($o, $storeUrl) {
	return if ($storeUrl // '') eq ($o:cacheStoreUrl // '');
	$o:cacheStoreUrl = $storeUrl;
	$o:cacheStore = $o->rawStoreForUrl($storeUrl);
}
