use strict;
use SourceFilter;
use File::Basename;

package Build;

sub read($class, $version, @flags) {
	my $o = bless {
		edition => [@flags],
		flags => {},
		sections => {},
		use => {},
		includedFiles => {},
		cdsUse => {},
		geanyTags => {},
		cCode => [],
		};

	for my $flag (@flags) {
		$o:flags->{$flag} = 1;
	}

	my @releaseDate = gmtime(time);
	$o:releaseDate = sprintf('%04d-%02d-%02d', $releaseDate[5] + 1900, $releaseDate[4] + 1, $releaseDate[3]);
	$o:version = $version;

	my $staticCode = $o->section('CDS');
	push @$staticCode, 'our $VERSION = \''.$o:version.'\';';
	push @$staticCode, 'our $edition = \''.join(' ', @$o:edition).'\';';
	push @$staticCode, 'our $releaseDate = \''.$o:releaseDate.'\';';

	# Prepare the perl code
	$o->includePerl('Condensation.pm');
	$o->addPackageNamesToGeanyTags;
	$o->reportMissingPackages;

	# Prepare the C code
	$o->includeC('Condensation/C.inc.c');

	return $o;
}

sub releaseDate;
sub version;
sub cCode;

sub editionString($o, $separator // ' ') {
	return join($separator, @$o:edition);
}

sub sections($o) {
	return keys %$o:sections;
}

sub countSections($o) {
	return scalar keys %$o:sections;
}

sub section($o, $name) {
	$o:sections->{$name} = [] if ! $o:sections->{$name};
	return $o:sections->{$name};
}

sub includePerl($o, $file) {
	$file = $1.$2 while $file =~ /^(.*)\.\/(.*)$/;
	$file = $1.$2 while $file =~ /^(.*)[^\/]+\/\.\.\/(.*)$/;
	return if $o:includedFiles{$file};
	$o:includedFiles{$file} = 1;

	# Read
	my @lines = $o->readLines($file);
	die 'File "'.$file.'" not found.' if ! scalar @lines;

	# Determine where to add the code by default
	my $packageName = $o->derivePackageName($file);
	my $section = $o->section($packageName);
	my $folder = File::Basename::dirname($file);

	# Perl code
	my $selected = 1;
	my $lineNumber = 0;
	my $emptyLineBefore = 1;
	for my $line (@lines) {
		$lineNumber += 1;

		if ($line =~ /^#\s*IF\s+(.*?)\s*$/) {
			$selected = $o->orFlags($1);
			next;
		}

		next if ! $selected;

		if ($line =~ /^#\s*INCLUDE\s+(.*?)\s*$/) {
			$o->includePerl($folder.'/'.$1);
			next;
		} elsif ($line =~ /^#\s*EXTEND\s+(.*?)\s*$/) {
			$packageName = $1;
			$section = $o->section($packageName);
			next;
		} elsif ($line =~ /^use parent (.*);$/) {
			$line = 'use parent -norequire, '.$1.';';
		} elsif ($line =~ /^use .*;$/) {
			$o:use->{$line} = 1;
			next;
		} elsif ($line =~ /^sub\s+([A-Za-z0-9_]+)\s*\((.*?)\)/) {
			my $name = $1;
			my $args = $2;
			if ($args =~ /^\s*\$(class|o)([^a-zA-Z0-9_]|$)/) {
				my $firstArg = $1;
				my $allButFirstArg = $args =~ /^.*?,\s*(.*)$/ ? $1 : '';
				$o->addGeanyTag($name, '', '('.$allButFirstArg.') in '.$packageName.($firstArg eq 'class' ? ' STATIC' : ''));
			} else {
				$o->addGeanyTag($name, '', '('.$args.') in '.$packageName);
			}
		} elsif ($line =~ /^sub\s+([A-Za-z0-9_]+)\s*;/) {
			$o->addGeanyTag($1, '', 'in '.$packageName);
		} elsif ($line =~ /^sub\s+([A-Za-z0-9_]+)/) {
			$o->addGeanyTag($1, '', 'in '.$packageName);
		}

		for my $access ($line =~ /(CDS(?:::[A-Z][a-zA-Z0-9]*)+)/g) {
			$o:cdsUse->{$access} = 1;
		}

		my $filteredLine = SourceFilter::filterLine($line, 0);
		my @lines = $filteredLine eq '' ? '' : split(/\n/, $filteredLine);
		for my $line (@lines) {
			if ($line =~ /^\s*$/) {
				$emptyLineBefore = 1
			} elsif ($emptyLineBefore) {
				$emptyLineBefore = 0;
				push @$section, '#line '.$lineNumber.' "'.$file.'"' if $o:flags->{debug};
			}

			push @$section, $line;
		}
	}

	push @$section, '';
}

sub derivePackageName($o, $file) {
	if ($file =~ /^Condensation\/([^\/]*)\/(.*).pm$/) {
		my $name = $2;
		$name =~ s/\//::/g;
		return 'CDS::'.$name;
	}

	if ($file =~ /^Condensation\/([^\/]*).pm$/) {
		return 'CDS::'.$1;
	}

	if ($file eq 'Condensation.pm') {
		return 'CDS';
	}

	die 'Cannot derive package name for "', $file, '".', "\n";
	return 'UNKNOWN';
}

sub reportMissingPackages($o) {
	for my $packageName (sort keys %$o:sections) {
		delete $o:cdsUse->{$packageName};
	}

	delete $o:cdsUse->{'CDS::C'};
	delete $o:cdsUse->{'CDS::VERSION'};
	for my $packageName (sort keys %$o:cdsUse) {
		print 'Missing package: ', $packageName, "\n";
	}
}

# Geany tags

sub addGeanyTag($o, $symbolName, $returnType, $argumentList) {
	my $line = $symbolName.'|'.$returnType.'|'.$argumentList.'|';
	$o:geanyTags->{$line} = 1;
}

sub addPackageNamesToGeanyTags($o) {
	for my $packageName (sort keys %$o:sections) {
		for my $element (split /::/, $packageName) {
			$o->addGeanyTag($element, 'package', '');
		}
	}
}

sub writeGeanyTags($o, $filename) {
	# Write the geany tags
	my @tags;
	push @tags, '# format=pipe';
	push @tags, sort keys %$o:geanyTags;
	$o->writeLines($filename, @tags);
}

# Flag selection

sub orFlags($o, $text) {
	for my $part (split(/\|/, $text)) {
		return 1 if $o->andFlags($part);
	}

	return;
}

sub andFlags($o, $text) {
	for my $part (split(/&/, $text)) {
		return if ! $o->notFlags($part);
	}

	return 1;
}

sub notFlags($o, $text) {
	return $text =~ /^\s*!(.*)$/ ? ! $o->notFlags($1) : $o->flags($text);
}

sub flags($o, $text) {
	return $o->orFlags($1) if $text =~ /^\s*\((.*)\)\s*$/;
	$text = $1 if $text =~ /^\s*(.*?)\s*$/;
	die 'Missing flag expression' if ! length $text;
	return 1 if $text eq 'all';
	return $o:flags->{$text} if $text =~ /^[a-zA-Z0-9_-]*$/;
	die 'Invalid flag "'.$text.'"';
}

# Produce the Perl code

sub allPackages($o) {
	my $output = [];
	push @$output, sort keys %$o:use;

	for my $packageName (sort keys %$o:sections) {
		$o->addPackage($output, $packageName) || next;
		push @$output, '';
	}

	return $o->compressEmptyLines($output);
}

sub addPackage($o, $output, $packageName) {
	my $code = $o:sections->{$packageName};
	return if ! scalar @$code;

	my $packageAdded = 0;
	for my $line (@$code) {
		if (! $packageAdded && $line !~ /^#/) {
			push @$output, 'package '.$packageName.';';
			push @$output, '';
			$packageAdded = 1;
		}
		push @$output, $line;
	}

	return 1;
}

sub onePackage($o, $packageName) {
	my $code = $o:sections->{$packageName};
	return if ! scalar @$code;

	my $output = [];
	my $packageAdded = 0;
	for my $line (@$code) {
		if (! $packageAdded && $line !~ /^#/) {
			push @$output, 'package '.$packageName.';';
			#push @$output, sort keys %$section:use;
			push @$output, '';
			$packageAdded = 1;
		}
		push @$output, $line;
	}

	return $o->compressEmptyLines($output);
}

# C code

sub includeC($o, $file) {
	my $folder = File::Basename::dirname($file);
	my @includeLines = $o->readLines($file);
	die 'Include file "'.$file.'" not found.' if ! scalar @includeLines;

	my $lineNumber = 0;
	for my $line (@includeLines) {
		$lineNumber += 1;
		if ($line =~ /^\s*#insert\s+"(.*?)"/) {
			my $includeFile = $folder.'/'.$1;
			push @$o:cCode, '';
			push @$o:cCode, '#line 1 "'.$includeFile.'"';
			$o->includeC($includeFile);
			push @$o:cCode, '';
			push @$o:cCode, '#line '.$lineNumber.' "'.$file.'"';
		} elsif ($line =~ /^\s*\/\//) {
			# Ignore
		} else {
			push @$o:cCode, $line;
		}
	}
}

# Reading and writing

sub compressEmptyLines($class, $lines) {
	my $newLines = [];
	my $isEmpty = 1;
	for my $line (@$lines) {
		$line = $1 if $line =~ /^(.*?)\s*$/;
		if ($line eq '') {
			$isEmpty = 1;
		} else {
			push @$newLines, '' if $isEmpty;
			push @$newLines, $line;
			$isEmpty = 0;
		}
	}

	return $newLines;
}

sub readLines($class, $filename) {
	open(my $fh, '<:utf8', $filename) || return;
	my @lines = map { while (chomp $_) {} $_ } <$fh>;
	close $fh;
	return @lines;
}

sub writeLines($class, $filename) {
	open(my $fh, '>:utf8', $filename) || die 'Unable to write "'.$filename.'".';
	for my $line (@_) {
		print $fh $line, "\n";
	}
	close $fh;
}

1;
