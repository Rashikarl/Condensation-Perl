# The store belongs to a group. Every user belonging to the group is treated equivalent, and users are supposed to trust each other to some extent.
# The resulting store will have files belonging to multiple users, but the same group.
use parent 'CDS::FolderStore::PosixPermissions';

sub new($class, $gid) {
	return bless {gid => $gid // $(};
}

sub target($o) { 'members of the group '.$o->group }
sub baseFolderMode { 0771 }
sub objectFolderMode { 0771 }
sub objectFileMode { 0664 }
sub accountFolderMode { 0771 }
sub boxFolderMode($o, $boxLabel) { $boxLabel eq 'public' ? 0775 : 0770 }
sub boxFileMode($o, $boxLabel) { $boxLabel eq 'public' ? 0664 : 0660 }
