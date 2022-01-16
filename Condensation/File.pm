# EXTEND CDS
# File system utility functions.

sub readBytesFromFile($class, $filename) {
	open(my $fh, '<:bytes', $filename) || return;
	local $/;
	my $content = <$fh>;
	close $fh;
	return $content;
}

sub writeBytesToFile($class, $filename; @bytes) {
	open(my $fh, '>:bytes', $filename) || return;
	print $fh @_;
	close $fh;
	return 1;
}

sub readTextFromFile($class, $filename) {
	open(my $fh, '<:utf8', $filename) || return;
	local $/;
	my $content = <$fh>;
	close $fh;
	return $content;
}

sub writeTextToFile($class, $filename; @text) {
	open(my $fh, '>:utf8', $filename) || return;
	print $fh @_;
	close $fh;
	return 1;
}

sub listFolder($class, $folder) {
	opendir(my $dh, $folder) || return;
	my @files = readdir $dh;
	closedir $dh;
	return @files;
}

sub intermediateFolders($class, $path) {
	my @paths = ($path);
	while (1) {
		$path =~ /^(.+)\/(.*?)$/ || last;
		$path = $1;
		next if ! length $2;
		unshift @paths, $path;
	}
	return @paths;
}
