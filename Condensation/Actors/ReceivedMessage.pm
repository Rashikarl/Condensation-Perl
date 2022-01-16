sub new($class, $messageBoxReader, $entry, $source, $envelope, $senderStoreUrl, $sender, $content, $streamHead) {
	return bless {
		messageBoxReader => $messageBoxReader,
		entry => $entry,
		source => $source,
		envelope => $envelope,
		senderStoreUrl => $senderStoreUrl,
		sender => $sender,
		content => $content,
		streamHead => $streamHead,
		isDone => 0,
		};
}

sub source;
sub envelope;
sub senderStoreUrl;
sub sender;
sub content;

sub waitForSenderStore($o) {
	$o:entry:waitingForStore = $o->sender->store;
}

sub skip($o) {
	$o:entry:processed = 0;
}
