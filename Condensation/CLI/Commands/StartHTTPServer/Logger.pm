sub new($class, $ui) {
	return bless {ui => $ui};
}

sub onServerStarts($o, $port) {
	my $ui = $o:ui;
	$ui->space;
	$ui->line($o:ui->gray($ui->niceDateTimeLocal), '  ', $ui->green('Server ready at http://localhost:', $port));
}

sub onRequestStarts($o, $request) { }

sub onRequestError($o, $request; @text) {
	my $ui = $o:ui;
	$ui->line($o:ui->gray($ui->niceDateTimeLocal), '  ', $ui->blue($ui->left(15, $request->peerAddress)), '  ', $request->method, ' ', $request->path, '  ', $ui->red(@_));
}

sub onRequestDone($o, $request, $responseCode) {
	my $ui = $o:ui;
	$ui->line($o:ui->gray($ui->niceDateTimeLocal), '  ', $ui->blue($ui->left(15, $request->peerAddress)), '  ', $request->method, ' ', $request->path, '  ', $ui->bold($responseCode));
}
