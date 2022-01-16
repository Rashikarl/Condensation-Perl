use Time::Local;

# Parses a date accepting various ISO variants, and calculates the timestamp using Time::Local
sub parse($class, $dateString // return) {
	if ($dateString =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/) {
		return (timegm(0, 0, 0, $3, $2 - 1, $1 - 1900) + 86400 - 30) * 1000;
	} elsif ($dateString =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(T|\s+)(\d\d):(\d\d):(\d\d|\d\d\.\d*)$/) {
		return (timelocal(0, $6, $5, $3, $2 - 1, $1 - 1900) + $7) * 1000;
	} elsif ($dateString =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(T|\s+)(\d\d):(\d\d):(\d\d|\d\d\.\d*)Z$/) {
		return (timegm(0, $6, $5, $3, $2 - 1, $1 - 1900) + $7) * 1000;
	} elsif ($dateString =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(T|\s+)(\d\d):(\d\d):(\d\d|\d\d\.\d*)+(\d\d):(\d\d)$/) {
		return (timegm(0, $6, $5, $3, $2 - 1, $1 - 1900) + $7 - $8 * 3600 - $9 * 60) * 1000;
	} elsif ($dateString =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(T|\s+)(\d\d):(\d\d):(\d\d|\d\d\.\d*)-(\d\d):(\d\d)$/) {
		return (timegm(0, $6, $5, $3, $2 - 1, $1 - 1900) + $7 + $8 * 3600 + $9 * 60) * 1000;
	} elsif ($dateString =~ /^\s*(\d+)\s*$/) {
		return $1;
	} else {
		return;
	}
}

# Returns a properly formatted string with a precision of 1 day (i.e., the "date" only)
sub dayString($class, $time // 1000 * time) {
	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3]);
}

# Returns a properly formatted string with a precision of 1 second (i.e., "time of day" and "date") using UTC
sub secondString($class, $time // 1000 * time) {
	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

# Returns a properly formatted string with a precision of 1 second (i.e., "time of day" and "date") using UTC
sub millisecondString($class, $time // 1000 * time) {
	my @t = gmtime($time / 1000);
	return sprintf('%04d-%02d-%02dT%02d:%02d:%02d.%03dZ', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0], int($time) % 1000);
}

# Returns a properly formatted string with a precision of 1 second (i.e., "time of day" and "date") using local time
sub localSecondString($class, $time // 1000 * time) {
	my @t = localtime($time / 1000);
	return sprintf('%04d-%02d-%02dT%02d:%02d:%02d', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}
