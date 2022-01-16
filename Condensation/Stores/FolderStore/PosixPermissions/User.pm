# The store belongs to a single user. Other users shall only be able to read objects and the public box, and post to the message box.
use parent 'CDS::FolderStore::PosixPermissions';

sub new($class, $uid) {
	return bless {uid => $uid // $<};
}

sub target($o) { 'user '.$o->user }
sub baseFolderMode { 0711 }
sub objectFolderMode { 0711 }
sub objectFileMode { 0644 }
sub accountFolderMode { 0711 }
sub boxFolderMode($o, $boxLabel) { $boxLabel eq 'public' ? 0755 : 0700 }
sub boxFileMode($o, $boxLabel) { $boxLabel eq 'public' ? 0644 : 0600 }
