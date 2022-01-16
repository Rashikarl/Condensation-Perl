sub new($class, $hash, $envelope, $senderStoreUrl, $sender, $content, $error) {
	return bless {
		hash => $hash,
		envelope => $envelope,
		senderStoreUrl => $senderStoreUrl,
		sender => $sender,
		content => $content,
		error => $error,
		lastUsed => CDS->now,
		};
}

sub hash;
sub envelope;
sub senderStoreUrl;
sub sender;
sub content;
sub error;
sub isValid($o) { ! defined $o:error }
sub lastUsed;

sub stillInUse($o) {
	$o:lastUsed = CDS->now;
}
