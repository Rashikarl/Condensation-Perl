# Handles posix permissions.
# INCLUDE PosixPermissions/Group.pm
# INCLUDE PosixPermissions/User.pm
# INCLUDE PosixPermissions/World.pm

# Returns the permissions set corresponding to the mode, uid, and gid of the base folder.
sub forStat($class, $stat) {
	my $mode = $stat:mode;
	return
		! defined $stat || ! defined $mode ? CDS::SFTPStore::PosixPermissions::World->new :
		($mode & 077) == 077 ? CDS::SFTPStore::PosixPermissions::World->new :
		($mode & 070) == 070 ? CDS::SFTPStore::PosixPermissions::Group->new($stat:gid) :
			CDS::SFTPStore::PosixPermissions::User->new($stat:uid);
}

sub uid;
sub gid;
