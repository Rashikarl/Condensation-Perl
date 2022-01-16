use parent 'CDS::SFTPStore::PosixPermissions';

sub new($class) {
	return bless {};
}

sub target { 'everybody' }
sub baseFolderMode { 0777 }
sub objectFolderMode { 0777 }
sub objectFileMode { 0666 }
sub accountFolderMode { 0777 }
sub boxFolderMode { 0777 }
sub boxFileMode { 0666 }
