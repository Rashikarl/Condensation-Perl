# IF inotify

use Linux::Inotify2;

sub new($class, $folder) {
	my $inotify = Linux::Inotify2->new;
	my $watch = $inotify->watch($folder, Linux::Inotify2::IN_MOVED_TO | Linux::Inotify2::IN_CREATE | Linux::Inotify2::IN_ONESHOT);
	return bless {
		folder => $folder,
		inotify => $inotify,
		watch => $watch
		};
}

sub wait($o, $remaining, $until) {
	my $remainingSeconds = $remaining / 1000;
	return if $remainingSeconds < 1;
	eval {
		local $SIG{ALRM} = sub { die 'alarm' };
		alarm $remainingSeconds;
		$o:inotify->read;
		alarm 0;
	};

	return 1;
}

sub done($o) {
	$o:watch->cancel if $o:watch;
}

# IF !inotify

sub new($class, $folder) {
	return bless {folder => $folder};
}

sub wait($o, $remaining, $until) {
	return if $remaining <= 0;
	sleep 1;
	return 1;
}

sub done($o) { }
