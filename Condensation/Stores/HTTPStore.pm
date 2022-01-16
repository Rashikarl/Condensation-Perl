# A Condensation store accessed through HTTP or HTTPS.
use Digest::SHA;
use Encode;
use HTTP::Headers;
use HTTP::Request;
use LWP::UserAgent;
use parent 'CDS::Store';

sub forUrl($class, $url) {
	$url =~ /^(http|https):\/\// || return;
	return $class->new($url);
}

sub new($class, $url) {
	return bless {url => $url};
}

sub id($o) { $o:url }

sub get($o, $hash, $keyPair) {
	my $response = $o->request('GET', $o:url.'/objects/'.$hash->hex, HTTP::Headers->new);
	return if $response->code == 404;
	return undef, 'get ==> HTTP '.$response->status_line if ! $response->is_success;
	return CDS::Object->fromBytes($response->decoded_content(charset => 'none'));
}

sub put($o, $hash, $object, $keyPair) {
	my $headers = HTTP::Headers->new;
	$headers->header('Content-Type' => 'application/condensation-object');
	my $response = $o->request('PUT', $o:url.'/objects/'.$hash->hex, $headers, $keyPair, $object->bytes);
	return if $response->is_success;
	return 'put ==> HTTP '.$response->status_line;
}

sub book($o, $hash, $keyPair) {
	my $response = $o->request('POST', $o:url.'/objects/'.$hash->hex, HTTP::Headers->new, $keyPair);
	return if $response->code == 404;
	return 1 if $response->is_success;
	return undef, 'book ==> HTTP '.$response->status_line;
}

sub list($o, $accountHash, $boxLabel, $timeout, $keyPair) {
	my $boxUrl = $o:url.'/accounts/'.$accountHash->hex.'/'.$boxLabel;
	my $headers = HTTP::Headers->new;
	$headers->header('Condensation-Watch' => $timeout.' ms') if $timeout > 0;
	my $response = $o->request('GET', $boxUrl, $headers);
	return undef, 'list ==> HTTP '.$response->status_line if ! $response->is_success;
	my $bytes = $response->decoded_content(charset => 'none');

	if (length($bytes) % 32 != 0) {
		print STDERR 'old procotol', "\n";
		my $hashes = [];
		for my $line (split /\n/, $bytes) {
			push @$hashes, CDS::Hash->fromHex($line) // next;
		}
		return $hashes;
	}

	my $countHashes = int(length($bytes) / 32);
	return [map { CDS::Hash->fromBytes(substr($bytes, $_ * 32, 32)) } 0 .. $countHashes - 1];
}

sub add($o, $accountHash, $boxLabel, $hash, $keyPair) {
	my $headers = HTTP::Headers->new;
	my $response = $o->request('PUT', $o:url.'/accounts/'.$accountHash->hex.'/'.$boxLabel.'/'.$hash->hex, $headers, $keyPair);
	return if $response->is_success;
	return 'add ==> HTTP '.$response->status_line;
}

sub remove($o, $accountHash, $boxLabel, $hash, $keyPair) {
	my $headers = HTTP::Headers->new;
	my $response = $o->request('DELETE', $o:url.'/accounts/'.$accountHash->hex.'/'.$boxLabel.'/'.$hash->hex, $headers, $keyPair);
	return if $response->is_success;
	return 'remove ==> HTTP '.$response->status_line;
}

sub modify($o, $modifications, $keyPair) {
	my $bytes = $modifications->toRecord->toObject->bytes;
	my $headers = HTTP::Headers->new;
	$headers->header('Content-Type' => 'application/condensation-modifications');
	my $response = $o->request('POST', $o:url.'/accounts', $headers, $keyPair, $bytes, 1);
	return if $response->is_success;
	return 'modify ==> HTTP '.$response->status_line;
}

# Executes a HTTP request.
sub request($class, $method, $url, $headers, $keyPair, $data, $signData) {	# private
	$headers->date(time);
	$headers->header('User-Agent' => CDS->version);

	if ($keyPair) {
		my $hostAndPath = $url =~ /^https?:\/\/(.*)$/ ? $1 : $url;
		my $date = CDS::ISODate->millisecondString;
		my $bytesToSign = $date."\0".uc($method)."\0".$hostAndPath;
		$bytesToSign .= "\0".$data if $signData;
		my $hashBytesToSign = Digest::SHA::sha256($bytesToSign);
		my $signature = $keyPair->sign($hashBytesToSign);
		$headers->header('Condensation-Date' => $date);
		$headers->header('Condensation-Actor' => $keyPair->publicKey->hash->hex);
		$headers->header('Condensation-Signature' => unpack('H*', $signature));
	}

	return LWP::UserAgent->new->request(HTTP::Request->new($method, $url, $headers, $data));
}
