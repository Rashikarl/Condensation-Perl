# The store is open to everybody. This does not usually make sense, but is offered here for completeness.
# This is the simplest permission scheme.
use parent 'CDS::FolderStore::PosixPermissions';

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
