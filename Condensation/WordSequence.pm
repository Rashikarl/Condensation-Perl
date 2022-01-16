# Converts a binary sequence to a list of words, or back

# Word list and corresponding dictionary
our @wordList = qw(outside special two open airplane love lake death talk eye air lemon light today blood fly salad small learn top yes key blue man center winter garden leg friend autumn wheel word son chicken year run injured difficult say simply source empty short bicycle thin education woman bell head name weak yellow poison ruler distribute white sugar stone zero heavy uncle tomorrow aunt salt no boy separate date shelf fight summit cousin earth mouse letter cold wood knowledge day happy laugh orange fresh seven long tongue table past mix sun line question many old grandmother door elephant sleep taxi shoes hair burn wind four slow arm three strong finger above summer tooth foot spring valley chair fast wash banana aluminum expert easy inside feather clock leaf knife freezing rice cloud jump sign road star piano mountain test tiny speak before water square here lion right remember trousers hammer hot decrease sick round gold desert nose fork thunderstorm house tiger bridge painting fingernail train ball scissors glass pain prison far throw hope play king drink future near young now pencil bed green red silence wife one yesterday drawing horse fish warm night big meeting apple increase potato mouth map river left black see grandfather watch between boat allowed eat thick closed pen husband daughter birth sand nine egg rainfall smile half tired listen cat dog bus after ten field forbidden iron girl island tree baby flower six ocean knee bird eight below bottom loud answer wall full swim moon silver five circle bear staircase soft book quick);
our %wordDictionary;
for my $i (0 .. 255) { $wordDictionary{$wordList[$i]} = $i; }

sub fromBytes($class, $sequence) {
	my @words;
	for my $i (0 .. length($sequence) - 1) {
		my $charCode = unpack('c', substr($sequence, $i, 1));
		push @words, $wordList[$charCode];
	}
	return @words;
}

sub toBytes($class; @words) {
	my $sequence = '';
	for my $word (@_) {
		next if ! exists $wordDictionary{$word};
		$sequence .= pack('c', $wordDictionary{$word});
	}
	return $sequence;
}
