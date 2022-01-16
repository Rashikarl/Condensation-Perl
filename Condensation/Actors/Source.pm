sub new($class, $keyPair, $actorOnStore, $boxLabel, $hash) {
	return bless {
		keyPair => $keyPair,
		actorOnStore => $actorOnStore,
		boxLabel => $boxLabel,
		hash => $hash,
		referenceCount => 1,
		};
}

sub keyPair;
sub actorOnStore;
sub boxLabel;
sub hash;
sub referenceCount;

sub keep($o) {
	if ($o:referenceCount < 1) {
		warn 'The source '.$o:actorOnStore->publicKey->hash->hex.'/'.$o:boxLabel.'/'.$o:hash->hex.' has already been discarded, and cannot be kept any more.';
		return;
	}

	$o:referenceCount += 1;
}

sub discard($o) {
	if ($o:referenceCount < 1) {
		warn 'The source '.$o:actorOnStore->publicKey->hash->hex.'/'.$o:boxLabel.'/'.$o:hash->hex.' has already been discarded, and cannot be discarded again.';
		return;
	}

	$o:referenceCount -= 1;
	return if $o:referenceCount > 0;

	$o:actorOnStore->store->remove($o:actorOnStore->publicKey->hash, $o:boxLabel, $o:hash, $o:keyPair);
}
