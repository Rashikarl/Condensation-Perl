sub new($class, $path, $content, $contentType) {
	return bless {
		path => $path,
		content => $content,
		contentType => $contentType,
		};
}

sub process($o, $request) {
	return if $request->path ne $o:path;

	# Options
	return $request->replyOptions('HEAD', 'GET') if $request->method eq 'OPTIONS';

	# GET
	return $request->reply(200, 'OK', {'Content-Type' => $o:contentType}, $o:content) if $request->method eq 'GET';

	# Everything else
	return $request->reply405;
}
