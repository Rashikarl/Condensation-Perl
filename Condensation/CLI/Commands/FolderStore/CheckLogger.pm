use parent 'CDS::Commands::FolderStore::Logger';

sub finalizeWrong($o) {
	$o:ui->pRed(@_);
	return 0;
}

sub summary($o) {
	$o:ui->p(($o:correct + $o:wrong).' files and folders traversed.');
	if ($o:wrong > 0) {
		$o:ui->p($o:wrong, ' files and folders have wrong permissions. To fix them, run');
		$o:ui->line($o:ui->gold('  cds fix permissions of ', $o:store->url));
	} else {
		$o:ui->pGreen('All permissions are OK.');
	}
}
