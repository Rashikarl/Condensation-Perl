# INCLUDE HTTPServer/Logger.pm
# INCLUDE HTTPServer/Request.pm

use Encode;
use HTTP::Date;
use HTTP::Server::Simple;
use parent 'HTTP::Server::Simple';

sub new($class) {
	my $o = $class->SUPER::new(@_);
	$o:logger = CDS::HTTPServer::Logger->new(*STDERR);
	$o:handlers = [];
	return $o;
}

sub addHandler($o, $handler) {
	push @$o:handlers, $handler;
}

sub setLogger($o, $logger) {
	$o:logger = $logger;
}

sub logger;

sub setCorsAllowEverybody($o, $value) {
	$o:corsAllowEverybody = $value;
}

sub corsAllowEverybody;

# *** HTTP::Server::Simple interface

sub print_banner($o) {
	$o:logger->onServerStarts($o->port);
}

sub setup($o; %parameters) {
	my %parameters = @_;
	$o:request = CDS::HTTPServer::Request->new({
		logger => $o->logger,
		method => $parameters{method},
		path => $parameters{path},
		protocol => $parameters{protocol},
		queryString => $parameters{query_string},
		peerAddress => $parameters{peeraddr},
		peerPort => $parameters{peerport},
		headers => {},
		corsAllowEverybody => $o->corsAllowEverybody,
		});
}

sub headers($o, $headers) {
	while (scalar @$headers) {
		my $key = shift @$headers;
		my $value = shift @$headers;
		$o:request->setHeader($key, $value);
	}

	# Read the content length
	$o:request->setRemainingData($o:request->header('content-length') // 0);
}

sub handler($o) {
	# Start writing the log line
	$o:logger->onRequestStarts($o:request);

	# Process the request
	my $responseCode = $o->process;
	$o:logger->onRequestDone($o:request, $responseCode);

	# Wrap up
	$o:request->dropData;
	$o:request = undef;
	return;
}

sub process($o) {
	# Run the handler
	for my $handler (@$o:handlers) {
		my $responseCode = $handler->process($o:request) || next;
		return $responseCode;
	}

	# Default handler
	return $o:request->reply404;
}

sub bad_request($o) {
	my $content = 'Bad Request';
	print 'HTTP/1.1 400 Bad Request', "\r\n";
	print 'Content-Length: ', length $content, "\r\n";
	print 'Content-Type: text/plain; charset=utf-8', "\r\n";
	print "\r\n";
	print $content;
	$o:request = undef;
}
