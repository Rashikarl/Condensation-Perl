sub new($class, $parent, $baseFolder) {
	return bless {
		ui => $parent:ui,
		store => $parent:store,
		baseFolder => $baseFolder,
		correct => 0,
		wrong => 0,
		}, $class;
}

sub correct($o) {
	$o:correct += 1;
}

sub wrong($o, $item, $uid, $gid, $mode, $expectedUid, $expectedGid, $expectedMode) {
	my $len = length $o:baseFolder;
	$o:wrong += 1;
	$item = '…'.substr($item, $len) if length $item > $len && substr($item, 0, $len) eq $o:baseFolder;
	my @changes;
	push @changes, 'user '.&username($uid).' -> '.&username($expectedUid) if defined $expectedUid && $uid != $expectedUid;
	push @changes, 'group '.&groupname($gid).' -> '.&groupname($expectedGid) if defined $expectedGid && $gid != $expectedGid;
	push @changes, 'mode '.sprintf('%04o -> %04o', $mode, $expectedMode) if $mode != $expectedMode;
	return $o->finalizeWrong(join(', ', @changes), "\t", $item);
}

sub username($uid) {
	return getpwuid($uid) // $uid;
}

sub groupname($gid) {
	return getgrgid($gid) // $gid;
}

sub accessError($o, $item) {
	$o:ui->error('Error accessing ', $item, '.');
	return 0;
}

sub setError($o, $item) {
	$o:ui->error('Error setting permissions of ', $item, '.');
	return 0;
}
