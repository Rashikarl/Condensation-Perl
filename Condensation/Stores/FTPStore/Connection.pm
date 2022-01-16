# Class managing FTP connections
use Net::FTP;

our %connections;

sub forEndpoint($class, $host) {
	# Extract the port
	my $port = 21;
	if ($host =~ /^(.*):(\d+)/) {
		$host = $1;
		$port = $2;
	}

	# Extract the username and password
	my $username = $ENV{USER};
	my $password;
	if ($host =~ /^(.*?):(.*?)@(.*)/) {
		$username = $1;
		$password = $2;
		$host = $3;
	} elsif ($host =~ /^(.*?)@(.*)/) {
		$username = $1;
		$host = $2;
	}

	return $class->new($host, $port, $username, $password);
}

sub new($class, $host, $port, $username, $password) {
	# Check if we have an active connection
	my $cacheName = $username.'@'.$host.':'.$port;
	return $CDS::FTPStore::Connection::connections{$cacheName} if exists $CDS::FTPStore::Connection::connections{$cacheName};

	# Create a new connection
	my $ftp = &ftpConnection($host, $port, $username, $password) // return;
	my $connection = bless { ftp => $ftp };
	$CDS::FTPStore::Connection::connections{$cacheName} = $connection;
	return $connection;
}

sub ftpConnection($host, $port, $username, $password) {
	# Open an FTP connection
	my $ftp = Net::FTP->new($host, Port => $port, Passive => 1) || return &reportError('Unable to connect to ', $host, ':', $port, ': '.$@);

	# Authenticate
	if (defined $password) {
		# Try using the provided password
		$ftp->login($username, $password) || return &reportError('Password authentication for user "', $username, '" failed: '.$@);
	} else {
		# Try using netrc information, or anonymously
		$ftp->login || return &reportError('Unable to log in: '.$@);
	}

	# Configure
	$ftp->binary || return &reportError('Unable to set binary transfer mode:'.$@);
	return $ftp;
}

sub reportError(; @text) {	# private
	print STDERR 'CDS::FTPStore::Connection', ': ', @_, "\n";
	return;
}

sub exists($o, $file) {
	return defined $o:ftp->size($file);
}

sub touch($o, $file) {
	my @t = gmtime;
	my $now = &fourDigits($t[0] + 1900).&twoDigits($t[4] + 1).&twoDigits($t[3]).&twoDigits($t[2]).&twoDigits($t[1]).&twoDigits($t[0]);

	return $o:ftp->quot('MFMT', $now, $file) if $o:ftp->supported('MFMT') == 2;
	return $o:ftp->site('UTIME', $now, $file) == 2;
}

sub twoDigits($number) {	# private
	my $a = int($number / 10);
	return ($a % 10).($number % 10);
}

sub fourDigits($number) {	# private
	my $a = int($number / 10);
	my $b = int($a / 10);
	my $c = int($b / 10);
	return ($c % 10).($b % 10).($a % 10).($number % 10);
}

sub files($o, $folder) {
	return map { $_ =~ /\/([^\/]*)$/ ? $1 : $_ } $o:ftp->ls($folder);
}

sub readFileBytes($o, $file) {
    my $dataconn = $o:ftp->retr($file) || return;
	binmode $dataconn, ':raw';

	my @bytes;
	while (1) {
		$dataconn->read(my $block, 256 * 256) || last;
		push @bytes, $block;
	}
	$dataconn->close;

	return join '', @bytes;
}

sub writeTemporaryFile($o, $folder, $bytes // '') {
	# Write the file
	my $temporaryFile = $folder.'/.'.CDS->randomHex(16);
	my $dataconn = $o:ftp->stor($temporaryFile) || return;
	my $written = 0;
	while ($written < length $bytes) {
		my $block = substr($bytes, $written, 16384);
		my $length = $dataconn->write($block, length $block);
		if (! $length) { $dataconn->close; return; }
		$written += $length;
	}
	$dataconn->close;

	return $temporaryFile;
}

sub mkdir($o, $folder) {
	return if $o:ftp->cwd($folder);
	return $o:ftp->mkdir($folder, 1);
}

sub rename($o, $from, $to) {
	return $o:ftp->rename($from, $to);
}

sub delete($o, $file) {
	return $o:ftp->delete($file);
}
