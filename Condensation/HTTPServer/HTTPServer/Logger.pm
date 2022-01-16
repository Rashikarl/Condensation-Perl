sub new($class, $fileHandle) {
	return bless {
		fileHandle => $fileHandle,
		lineStarted => 0,
		};
}

sub onServerStarts($o, $port) {
	my $fh = $o:fileHandle;
	my @t = localtime(time);
	printf $fh '%04d-%02d-%02d %02d:%02d:%02d ', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0];
	print $fh 'Server ready at http://localhost:', $port, "\n";
}

sub onRequestStarts($o, $request) {
	my $fh = $o:fileHandle;
	my @t = localtime(time);
	printf $fh '%04d-%02d-%02d %02d:%02d:%02d ', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0];
	print $fh $request->peerAddress, ' ', $request->method, ' ', $request->path;
	$o:lineStarted = 1;
}

sub onRequestError($o, $request; @text) {
	my $fh = $o:fileHandle;
	print $fh "\n" if $o:lineStarted;
	print $fh '  ', @_, "\n";
	$o:lineStarted = 0;
}

sub onRequestDone($o, $request, $responseCode) {
	my $fh = $o:fileHandle;
	print $fh '  ===> ' if ! $o:lineStarted;
	print $fh ' ', $responseCode, "\n";
	$o:lineStarted = 0;
}
