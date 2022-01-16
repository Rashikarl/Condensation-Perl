use parent 'CDS::SFTPStore::PosixPermissions';

sub new($class, $gid) {
	return bless {gid => $gid};
}

sub target($o) { 'members of the group '.$o:gid }
sub baseFolderMode { 0771 }
sub objectFolderMode { 0771 }
sub objectFileMode { 0664 }
sub accountFolderMode { 0771 }
sub boxFolderMode($o, $boxLabel) { $boxLabel eq 'public' ? 0775 : 0770 }
sub boxFileMode($o, $boxLabel) { $boxLabel eq 'public' ? 0664 : 0660 }
