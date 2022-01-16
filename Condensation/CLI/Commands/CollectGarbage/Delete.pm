sub new($class, $ui) {
	return bless {
		ui => $ui,
		deletedEnvelopesText => 'expired envelopes deleted',
		keptEnvelopesText => 'envelopes kept',
		deletedObjectsText => 'objects deleted',
		keptObjectsText => 'objects kept',
		};
}

sub initialize($o, $folder) { 1 }

sub startDeletion($o) {
	$o:ui->title('Deleting obsolete objects');
}

sub deleteEnvelope($o, $file) { $o->deleteObject($file) }

sub deleteObject($o, $file) {
	unlink $file // return $o:ui->error('Unable to delete "', $file, '". Giving up …');
	return 1;
}

sub wrapUp($o) { }
