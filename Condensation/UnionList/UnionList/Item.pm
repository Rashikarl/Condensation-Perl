sub new($class, $unionList, $id) {
	$unionList:unused:count += 1;
	return bless {
		unionList => $unionList,
		id => $id,
		part => $unionList:unused,
		}, $class;
}

sub unionList;
sub id;

sub setPart($o, $part) {
	$o:part:count -= 1;
	$o:part = $part;
	$o:part:count += 1;
}

# abstract sub addToRecord($o, $record)
