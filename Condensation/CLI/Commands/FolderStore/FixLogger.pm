use parent 'CDS::Commands::FolderStore::Logger';

sub finalizeWrong($o) {
	$o:ui->line(@_);
	return 1;
}

sub summary($o) {
	$o:ui->p(($o:correct + $o:wrong).' files and folders traversed.');
	$o:ui->p('The permissions of ', $o:wrong, ' files and folders have been fixed.') if $o:wrong > 0;
	$o:ui->pGreen('All permissions are OK.');
}

