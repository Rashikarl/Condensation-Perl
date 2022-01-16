sub new($class, $root, $folder, $defaultFile // '') {
	return bless {
		root => $root,
		folder => $folder,
		defaultFile => $defaultFile,
		mimeTypesByExtension => {
			'css' => 'text/css',
			'gif' => 'image/gif',
			'html' => 'text/html',
			'jpg' => 'image/jpeg',
			'jpeg' => 'image/jpeg',
			'js' => 'application/javascript',
			'mp4' => 'video/mp4',
			'ogg' => 'video/ogg',
			'pdf' => 'application/pdf',
			'png' => 'image/png',
			'svg' => 'image/svg+xml',
			'txt' => 'text/plain',
			'webm' => 'video/webm',
			'zip' => 'application/zip',
			},
		};
}

sub folder;
sub defaultFile;
sub mimeTypesByExtension;

sub setContentType($o, $extension, $contentType) {
	$o:mimeTypesByExtension->{$extension} = $contentType;
}

sub process($o, $request) {
	# Options
	return $request->replyOptions('HEAD', 'GET') if $request->method eq 'OPTIONS';

	# Get
	return $o->get($request) if $request->method eq 'GET' || $request->method eq 'HEAD';

	# Anything else
	return $request->reply405;
}

sub get($o, $request) {
	my $path = $request->pathAbove($o:root) // return;
	return $o->deliverFileForPath($request, $path);
}

sub deliverFileForPath($o, $request, $path) {
	# Hidden files (starting with a dot), as well as "." and ".." never exist
	for my $segment (split /\/+/, $path) {
		return $request->reply404 if $segment =~ /^\./;
	}

	# If a folder is requested, we serve the default file
	my $file = $o:folder.$path;
	if (-d $file) {
		return $request->reply404 if ! length $o:defaultFile;
		return $request->reply303($request->path.'/') if $file !~ /\/$/;
		$file .= $o:defaultFile;
	}

	return $o->deliverFile($request, $file);
}

sub deliverFile($o, $request, $file, $contentType // $o->guessContentType($file)) {
	my $bytes = $o->readFile($file) // return $request->reply404;
	return $request->reply(200, 'OK', {'Content-Type' => $contentType}, $bytes);
}

# Guesses the content type from the extension
sub guessContentType($o, $file) {
	my $extension = $file =~ /\.([A-Za-z0-9]*)$/ ? lc($1) : '';
	return $o:mimeTypesByExtension->{$extension} // 'application/octet-stream';
}

# Reads a file
sub readFile($o, $file) {
	open(my $fh, '<:bytes', $file) || return;
	if (! -f $fh) {
		close $fh;
		return;
	}

	local $/ = undef;
	my $bytes = <$fh>;
	close $fh;
	return $bytes;
}
