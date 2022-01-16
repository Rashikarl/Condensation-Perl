use strict;
use warnings;

package SourceFilter;
use Filter::Util::Call;

sub import {
	my $type = shift;
	filter_add(bless []);
}

sub filter {
	my $o = shift;
	my $status = filter_read || return 0;
	$_ = &filterLine($_, 1);
	return $status;
}

sub filterLine {
	my $line = shift;
	my $singleLine = shift;
	$line =~ s/^sub ([a-zA-Z0-9_]+)\s*;$/'sub '.$1.' { shift->{'.$1.'} }'/eg;
	$line =~ s/^sub ([a-zA-Z0-9_]+)\((.*?)\)\s*\{/'sub '.$1.&parseArgs($2, $singleLine)/eg;
	$line =~ s/([^a-z0-9\$_])sub\s*\((.*?)\)\s*\{/$1.'sub'.&parseArgs($2, 1)/eg;
	$line =~ s/(\@|\%|)\$([a-zA-Z0-9_]+:[a-zA-Z0-9_:]+)/&parseMembers($1, $2)/eg;
	$line =~ s/^\s*(--|\+\+)\s*(.*?)\s*$/&parseDebug($1, $2)/eg;
	return $line;
}

sub parseArgs {
	my $args = shift;
	my $singleLine = shift;
	my $nlTab = $singleLine ? ' ' : "\n\t";
	$args = $1 if $args =~ /^(.*?);/;
	my @args = split(/,/, $args);
	my @lines = map { &parseArg($_) } @args;
	return ' {'.$nlTab.join($nlTab, @lines).$nlTab;
}

sub parseArg {
	my $arg = shift;
	$arg = $1 if $arg =~ /^\s*(.*?)\s*$/;
	return 'my '.$1.' = shift'.$2.';'.&typeCheck($1) if $arg =~ /^(\$[a-zA-Z0-9_]+)(.*?)$/;
	return 'my '.$arg.' = shift;'.&typeCheck($arg);
}

sub typeCheck {
	# Enable this line for the clean version
	#return '';

	# Enable these lines to add dynamic type checks for certain parameters
	my $name = shift;
	my $class = &classForName($name) // return '';
	return ' die \'wrong type \'.ref('.$name.').\' for '.$name.'\' if defined '.$name.' && ref '.$name.' ne \''.$class.'\';';
}

sub classForName {
	my $name = shift;
	return if $name =~ /^\$check/;
	return 'CDS::Hash' if $name eq '$hash';
	return 'CDS::Hash' if $name =~ /^\$.*Hash$/;
	return 'CDS::ActorOnStore' if $name eq '$actorOnStore';
	return 'CDS::ActorOnStore' if $name =~ /^\$.*ActorOnStore$/;
	return 'CDS::Record' if $name eq '$record';
	return 'CDS::Record' if $name eq '$envelope';
	return 'CDS::Record' if $name =~ /^\$.*Record$/;
	return 'CDS::Object' if $name eq '$object';
	return 'CDS::Object' if $name =~ /^\$.*Object$/;
	return 'CDS::ActorGroup' if $name eq '$actorGroup';
	return 'CDS::ActorGroupBuilder' if $name eq '$builder';
	return 'CDS::KeyPair' if $name eq '$keyPair';
	return 'CDS::PublicKey' if $name eq '$publicKey';
	return 'CDS::Source' if $name eq '$source';
	return 'CDS::HashAndKey' if $name eq '$hashAndKey';
	return 'CDS::Selector' if $name eq '$selector';
	return 'CDS::Selector' if $name =~ /^\$.*Selector$/;
	return;
}

sub parseMembers {
	my $prefix = shift;
	my $expression = shift;
	return $prefix.'$'.$expression if $expression =~ /::/;
	my @parts = split(/:/, $expression);
	my $first = shift @parts;
	my $value = '$'.$first.join('', map { '->{'.$_.'}' } @parts);
	return '@{'.$value.'}' if $prefix eq '@';
	return '%{'.$value.'}' if $prefix eq '%';
	return $value;
}

sub parseDebug {
	my $type = shift;
	my $text = shift;
	my @args;
	while ($text =~ /^(.*?)\s*(--|\+\+)\s*(.*)$/) {
		my $arg = $1;
		my $nextType = $2;
		$text = $3;
		push @args, $type eq '--' ? '\''.$arg.'\'' : $arg;
		$type = $nextType;
	}
	push @args, $type eq '--' ? '\''.$text.'\'' : $text if length $text;
	push @args, '\'--- \'.__FILE__.\':\'.__LINE__';
	return 'print STDERR '.join(', \' \', ', @args).', "\n";'."\n";
}

1;
