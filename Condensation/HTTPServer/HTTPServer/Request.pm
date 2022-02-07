sub new($class, $parameters) {
	return bless $parameters;
}

sub logger;
sub method;
sub path;
sub queryString;
sub peerAddress;
sub peerPort;
sub headers;
sub remainingData;
sub corsAllowEverybody;

# *** Path

sub pathAbove($o, $root) {
	$root .= '/' if $root !~ /\/$/;
	return if substr($o:path, 0, length $root) ne $root;
	return substr($o:path, length($root) - 1);
}

# *** Request data

sub setRemainingData($o, $remainingData) {
	$o:remainingData = $remainingData;
}

# Reads the request data
sub readData($o) {
	my @buffers;
	while ($o:remainingData > 0) {
		my $read = sysread(STDIN, my $buffer, $o:remainingData) || return;
		$o:remainingData -= $read;
		push @buffers, $buffer;
	}

	return join('', @buffers);
}

# Read the request data and writes it directly to a file handle
sub copyDataAndCalculateHash($o, $fh) {
	my $sha = Digest::SHA->new(256);
	while ($o:remainingData > 0) {
		my $read = sysread(STDIN, my $buffer, $o:remainingData) || return;
		$o:remainingData -= $read;
		$sha->add($buffer);
		print $fh $buffer;
	}

	return $sha->digest;
}

# Reads and drops the request data
sub dropData($o) {
	while ($o:remainingData > 0) {
		$o:remainingData -= read(STDIN, my $buffer, $o:remainingData) || return;
	}
}

# *** Headers

sub setHeader($o, $key, $value) {
	$o:headers->{lc($key)} = $value;
}

sub header($o, $key) {
	return $o:headers->{lc($key)};
}

# *** Query string

sub parseQueryString($o) {
	return {} if ! defined $o:queryString;

	my $values = {};
	for my $pair (split /&/, $o:queryString) {
		if ($pair =~ /^(.*?)=(.*)$/) {
			my $key = $1;
			my $value = $2;
			$values->{&uri_decode($key)} = &uri_decode($value);
		} else {
			$values->{&uri_decode($pair)} = 1;
		}
	}

	return $values;
}

sub uri_decode($encoded) {
	$encoded =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
	return $encoded;
}

# *** Condensation signature

sub checkSignature($o, $store, $contentBytesToSign) {
	# Check the date
	my $dateString = $o:headers->{'condensation-date'} // $o:headers->{'date'} // return;
	my $date = HTTP::Date::str2time($dateString) // return;
	my $now = time;
	return if $date < $now - 120 || $date > $now + 60;

	# Get and check the actor
	my $actorHash = CDS::Hash->fromHex($o:headers->{'condensation-actor'}) // return;
	my ($publicKeyObject, $error) = $store->get($actorHash);
	return if ! $publicKeyObject;
	return if ! $publicKeyObject->calculateHash->equals($actorHash);
	my $publicKey = CDS::PublicKey->fromObject($publicKeyObject) // return;

	# Text to sign
	my $bytesToSign = $dateString."\0".uc($o:method)."\0".$o:headers->{'host'}.$o:path;
	$bytesToSign .= "\0".$contentBytesToSign if defined $contentBytesToSign;
	my $hashToSign = CDS::Hash->calculateFor($bytesToSign);

	# Check the signature
	my $signatureString = $o:headers->{'condensation-signature'} // return;
	$signatureString =~ /^\s*([0-9a-z]{512,512})\s*$/ // return;
	my $signature = pack('H*', $1);
	return if ! $publicKey->verifyHash($hashToSign, $signature);

	# Return the verified actor hash
	return $actorHash;
}

# *** Reply functions

sub reply200($o, $content // '') {
	return length $content ? $o->reply(200, 'OK', &textContentType, $content) : $o->reply(204, 'No Content', {});
}

sub reply200Bytes($o, $content // '') {
	return length $content ? $o->reply(200, 'OK', {'Content-Type' => 'application/octet-stream'}, $content) : $o->reply(204, 'No Content', {});
}

sub reply200HTML($o, $content // '') {
	return length $content ? $o->reply(200, 'OK', {'Content-Type' => 'text/html; charset=utf-8'}, $content) : $o->reply(204, 'No Content', {});
}

sub replyOptions($o; @methods) {
	my $headers = {};
	$headers->{'Allow'} = join(', ', @_, 'OPTIONS');
	$headers->{'Access-Control-Allow-Methods'} = join(', ', @_, 'OPTIONS') if $o->corsAllowEverybody && $o:headers->{'origin'};
	return $o->reply(200, 'OK', $headers);
}

sub replyFatalError($o; @error) {
	$o:logger->onRequestError($o, @_);
	return $o->reply500;
}

sub reply303($o, $location) { $o->reply(303, 'See Other', {'Location' => $location}) }
sub reply400 { shift->reply(400, 'Bad Request', &textContentType, @_) }
sub reply403 { shift->reply(403, 'Forbidden', &textContentType, @_) }
sub reply404 { shift->reply(404, 'Not Found', &textContentType, @_) }
sub reply405 { shift->reply(405, 'Method Not Allowed', &textContentType, @_) }
sub reply500 { shift->reply(500, 'Internal Server Error', &textContentType, @_) }
sub reply503 { shift->reply(503, 'Service Not Available', &textContentType, @_) }

sub reply($o, $responseCode, $responseLabel, $headers // {}, $content // '') {
	# Content-related headers
	$headers->{'Content-Length'} = length($content);

	# Origin
	if ($o->corsAllowEverybody && (my $origin = $o:headers->{'origin'})) {
		$headers->{'Access-Control-Allow-Origin'} = $origin;
		$headers->{'Access-Control-Allow-Headers'} = 'Content-Type';
		$headers->{'Access-Control-Max-Age'} = '86400';
	}

	# Write the reply
	print 'HTTP/1.1 ', $responseCode, ' ', $responseLabel, "\r\n";
	for my $key (keys %$headers) {
		print $key, ': ', $headers->{$key}, "\r\n";
	}
	print "\r\n";
	print $content if $o:method ne 'HEAD';

	# Return the response code
	return $responseCode;
}

sub textContentType { {'Content-Type' => 'text/plain; charset=utf-8'} }
