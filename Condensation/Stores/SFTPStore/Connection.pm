# Class managing SFTP connections
use Fcntl;
use Net::SSH2;

our %connections;

sub forEndpoint($class, $host) {
	# Extract the port
	my $port = 22;
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
	return $CDS::SFTPStore::Connection::connections{$cacheName} if exists $CDS::SFTPStore::Connection::connections{$cacheName};

	# Create a new connection
	my $ssh = &sshConnection($host, $port, $username, $password) // return;
	my $hostKey = $ssh->can('hostkey_hash') ? $ssh->hostkey_hash('MD5') : $ssh->hostkey('MD5');
	return $CDS::SFTPStore::Connection::connections{$cacheName} = bless {
		ssh => $ssh,
		sftp => $ssh->sftp,
		hostKey => $hostKey,
		}, 'CDS::SFTPStore::Connection';
}

sub sshConnection($host, $port, $username, $password) {	# private
	# Open an SSH connection
	my $ssh = Net::SSH2->new;
	$ssh->connect($host, $port) || return &reportError('Unable to connect to ', $host, ':', $port, '.');

	# Try authenticating using the provided password
	if (defined $password) {
		return $ssh if $ssh->auth_password($username, $password);
		&reportError('Password authentication for user "', $username, '" failed.');
	}

	# Try authenticating using the RSA key, if one exists
	if (-f $ENV{HOME}.'/.ssh/id_rsa.pub' && -f $ENV{HOME}.'/.ssh/id_rsa') {
		return $ssh if $ssh->auth_publickey($username, $ENV{HOME}.'/.ssh/id_rsa.pub', $ENV{HOME}.'/.ssh/id_rsa');
		&reportError('Authentication for user "', $username, '" using "'.$ENV{HOME}.'/.ssh/id_rsa.pub" failed.');
	}

	# Try authenticating using the DSA key, if one exists
	if (-f $ENV{HOME}.'/.ssh/id_dsa.pub' && -f $ENV{HOME}.'/.ssh/id_dsa') {
		return $ssh if $ssh->auth_publickey($username, $ENV{HOME}.'/.ssh/id_dsa.pub', $ENV{HOME}.'/.ssh/id_dsa');
		&reportError('Authentication for user "', $username, '" using "'.$ENV{HOME}.'/.ssh/id_dsa.pub" failed.');
	}

	return &reportError('Unable to authenticate.');
}

sub reportError(; @text) {	# private
	print STDERR 'CDS::SFTPStore::Connection', ': ', @_, "\n";
	return;
}

sub exists($o, $file) {
	my %stat = $o:sftp->stat($file, 0);
	return defined $stat{mode};
}

sub stat($o, $file) {
	return {$o:sftp->stat($file, 0)};
}

sub touch($o, $file) {
	my $now = time;
	return $o:sftp->setstat($file, 'atime', $now, 'mtime', $now);
}

sub files($o, $folder) {
	my @files;
	my $dh = $o:sftp->opendir($folder) || return;
	while (my $file = $dh->read) { push @files, $file; }
	return @files;
}

sub readFileBytes($o, $file) {
    my $fh = $o:sftp->open($file) || return;
	binmode $fh, ':raw';

	my @bytes;
	while (1) {
		$fh->read(my $block, 256 * 256) || last;
		push @bytes, $block;
	}

	close $fh;
	return join '', @bytes;
}

sub writeTemporaryFile($o, $folder, $uid, $gid, $mode, $bytes // '') {
	# Write the file
	my $temporaryFile = $folder.'/.'.CDS->randomHex(16);
	my $fh = $o:sftp->open($temporaryFile, Fcntl::O_WRONLY | Fcntl::O_CREAT, $mode) || return;
	my $written = 0;
	while ($written < length $bytes) {
		# Note that SFTP has problems when writing too much data. The limit appears to be at about 30k.
		my $length = $fh->write(substr($bytes, $written, 16384));
		if (! $length) { close $fh; return; }
		$written += $length;
	}
	close $fh;

	# Set the uid and gid if necessary
	my @args;
	push @args, 'uid', $uid if defined $uid;
	push @args, 'gid', $gid if defined $gid;
	$o:sftp->setstat($temporaryFile, @args) if scalar @args;

	return $temporaryFile;
}


sub mkdir($o, $folder, $uid, $gid, $mode) {
	return if $o->exists($folder);

	# Create directory with the correct mode
	my $success = $o:sftp->mkdir($folder, $mode);

	# Set the uid and gid if necessary
	my @args;
	push @args, 'uid', $uid if defined $uid;
	push @args, 'gid', $gid if defined $gid;
	$o:sftp->setstat($folder, @args) if scalar @args;

	return $success;
}

sub mkdirRecursive($o, $folder, $mode) {
	map { $o:sftp->mkdir($_, $mode) } CDS->intermediateFolders($folder) if ! $o:sftp->stat($folder);
}

sub rename($o, $from, $to) {
	return $o:sftp->rename($from, $to);
}

sub unlink($o, $file) {
	return $o:sftp->unlink($file);
}
