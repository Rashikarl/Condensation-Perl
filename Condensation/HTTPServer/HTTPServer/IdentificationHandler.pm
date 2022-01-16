sub new($class, $root) {
	return bless {root => $root};
}

sub process($o, $request) {
	my $path = $request->pathAbove($o:root) // return;
	return if $path ne '/';

	# Options
	return $request->replyOptions('HEAD', 'GET') if $request->method eq 'OPTIONS';

	# Get
	return $request->reply200HTML('<!DOCTYPE html><html><head><meta charset="utf-8"><title>Condensation HTTP Store</title></head><body>This is a <a href="https://condensation.io/specifications/store/http/">Condensation HTTP Store</a> server.</body></html>') if $request->method eq 'HEAD' || $request->method eq 'GET';

	return $request->reply405;
}
