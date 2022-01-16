sub new($class, $ui) {
	return bless {
		ui => $ui,
		countReported => 0,
		deletedEnvelopesText => 'envelopes have expired',
		keptEnvelopesText => 'envelopes are in use',
		deletedObjectsText => 'objects can be deleted',
		keptObjectsText => 'objects are in use',
		};
}

sub initialize($o, $folderStore) {
	$o:file = $folderStore->folder.'/.garbage';
	open($o:fh, '>', $o:file) || return $o:ui->error('Failed to open ', $o:file, ' for writing.');
	return 1;
}

sub startDeletion($o) {
	$o:ui->title('Deleting obsolete objects');
}

sub deleteEnvelope($o, $file) { $o->deleteObject($file) }

sub deleteObject($o, $file) {
	my $fh = $o:fh;
	print $fh 'rm ', $file, "\n";
	$o:countReported += 1;
	print $fh 'echo ', $o:countReported, ' files deleted', "\n" if $o:countReported % 100 == 0;
	return 1;
}

sub wrapUp($o) {
	close $o:fh;
	if ($o:countReported == 0) {
		unlink $o:file;
	} else {
		$o:ui->space;
		$o:ui->p('The report was written to ', $o:file, '.');
		$o:ui->space;
	}
}
