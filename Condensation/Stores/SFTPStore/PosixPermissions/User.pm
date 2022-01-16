use parent 'CDS::SFTPStore::PosixPermissions';

sub new($class, $uid) {
	return bless {uid => $uid};
}

sub target($o) { 'user '.$o:uid }
sub baseFolderMode { 0711 }
sub objectFolderMode { 0711 }
sub objectFileMode { 0644 }
sub accountFolderMode { 0711 }
sub boxFolderMode($o, $boxLabel) { $boxLabel eq 'public' ? 0755 : 0700 }
sub boxFileMode($o, $boxLabel) { $boxLabel eq 'public' ? 0644 : 0600 }
