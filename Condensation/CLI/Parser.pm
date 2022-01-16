# INCLUDE Parser/Arrow.pm
# INCLUDE Parser/Continuations.pm
# INCLUDE Parser/Node.pm
# INCLUDE Parser/State.pm
# INCLUDE Parser/Token.pm

sub new($class, $actor, $command) {
	my $start = CDS::Parser::Node->new(0);
	return bless {
		actor => $actor,
		ui => $actor->ui,
		start => $start,
		states => [CDS::Parser::State->new($start)],
		command => $command,
		};
}

sub actor;
sub start;

sub execute($o; @args) {
	my $processed = [$o:command];
	for my $arg (@_) {
		return $o->howToContinue($processed) if $arg eq '?';
		return $o->explain if $arg eq '??';
		my $token = CDS::Parser::Token->new($o:actor, $arg);
		$o->advance($token);
		return $o->invalid($processed, $token) if ! scalar @$o:states;
		push @$processed, $arg;
	}

	my @results = grep { $_->runHandler } @$o:states;
	return $o->howToContinue($processed) if ! scalar @results;

	my $maxWeight = 0;
	for my $result (@results) {
		$maxWeight = $result->cumulativeWeight if $maxWeight < $result->cumulativeWeight;
	}

	@results = grep { $_->cumulativeWeight == $maxWeight } @results;
	return $o->ambiguous if scalar @results > 1;

	my $result = shift @results;
	my $handler = $result->runHandler;
	my $instance = &{$handler:constructor}(undef, $o:actor);
	&{$handler:function}($instance, $result);
}

sub advance($o, $token) {
	$o:previousStates = $o:states;
	$o:states = [];
	for my $state (@$o:previousStates) {
		push @$o:states, $state->advance($token);
	}
}

sub showCompletions($o, $cmd) {
	# Parse the command line
	my $state = '';
	my $arg = '';
	my @args;
	for my $c (split //, $cmd) {
		if ($state eq '') {
			if ($c eq ' ') {
				push @args, $arg if length $arg;
				$arg = '';
			} elsif ($c eq '\'') {
				push @args, $arg if length $arg;
				$arg = '';
				$state = '\'';
			} elsif ($c eq '"') {
				push @args, $arg if length $arg;
				$arg = '';
				$state = '"';
			} elsif ($c eq '\\') {
				$state = '\\';
			} else {
				$arg .= $c;
			}
		} elsif ($state eq '\\') {
			$arg .= $c;
			$state = '';
		} elsif ($state eq '\'') {
			if ($c eq '\'') {
				push @args, $arg if length $arg;
				$arg = '';
				$state = '';
			} else {
				$arg .= $c;
			}
		} elsif ($state eq '"') {
			if ($c eq '"') {
				push @args, $arg if length $arg;
				$arg = '';
				$state = '';
			} elsif ($c eq '\\') {
				$state = '"\\';
			} else {
				$arg .= $c;
			}
		} elsif ($state eq '\\"') {
			$arg .= $c;
			$state = '"';
		}
	}

	# Use the last token to complete
	my $lastToken = CDS::Parser::Token->new($o:actor, $arg);

	# Look for possible states
	shift @args;
	for my $arg (@args) {
		return if $arg eq '?';
		$o->advance(CDS::Parser::Token->new($o:actor, $arg));
	}

	# Complete the last token
	my %possibilities;
	for my $state (@$o:states) {
		for my $possibility ($state->complete($lastToken)) {
			$possibilities{$possibility} = 1;
		}
	}

	# Print all possibilities
	for my $possibility (keys %possibilities) {
		print $possibility, "\n";
	}
}

sub ambiguous($o) {
	$o:ui->space;
	$o:ui->pRed('Your query is ambiguous. This is an error in the command grammar.');
	$o->explain;
}

sub explain($o) {
	for my $interpretation (sort { $b->cumulativeWeight <=> $a->cumulativeWeight || $b->isExecutable <=> $a->isExecutable } @$o:states) {
		$o:ui->space;
		$o:ui->title('Interpretation with weight ', $interpretation->cumulativeWeight, $interpretation->isExecutable ? $o:ui->green(' (executable)') : $o:ui->orange(' (incomplete)'));
		$o->showTuples($interpretation->path);
	}

	$o:ui->space;
}

sub showTuples($o; @states) {
	for my $state (@_) {
		my $label = $state->label;
		my $value = $state->value;

		my $valueRef = ref $value;
		my $valueText =
			$valueRef eq '' ? $value // '' :
			$valueRef eq 'CDS::Hash' ? $value->hex :
			$valueRef eq 'CDS::ErrorHandlingStore' ? $value->url :
			$valueRef eq 'CDS::AccountToken' ? $value->actorHash->hex . ' on ' . $value->cliStore->url :
				$valueRef;
		$o:ui->line($o:ui->left(12, $label), $state->collectHandler ? $valueText : $o:ui->gray($valueText));
	}
}

sub cmd($o, $processed) {
	my $cmd = join(' ', map { $_ =~ s/(\\|'|")/\\$1/g ; $_ } @$processed);
	$cmd = '…'.substr($cmd, length($cmd) - 20, 20) if length $cmd > 30;
	return $cmd;
}

sub howToContinue($o, $processed) {
	my $cmd = $o->cmd($processed);
	#$o->displayWarnings($o:states);
	$o:ui->space;
	for my $possibility (CDS::Parser::Continuations->collect($o:states)) {
		$o:ui->line($o:ui->gray($cmd), $possibility);
	}
	$o:ui->space;
}

sub invalid($o, $processed, $invalid) {
	my $cmd = $o->cmd($processed);
	$o->displayWarnings($o:previousStates);
	$o:ui->space;

	$o:ui->line($o:ui->gray($cmd), ' ', $o:ui->red($invalid:text));
	if (scalar @$invalid:warnings) {
		for my $warning (@$invalid:warnings) {
			$o:ui->warning($warning);
		}
	}

	$o:ui->space;
	$o:ui->title('Possible continuations');
	for my $possibility (CDS::Parser::Continuations->collect($o:previousStates)) {
		$o:ui->line($o:ui->gray($cmd), $possibility);
	}
	$o:ui->space;
}

sub displayWarnings($o, $states) {
	for my $state (@$states) {
		my $current = $state;
		while ($current) {
			for my $warning (@$current:warnings) {
				$o:ui->warning($warning);
			}
			$current = $current:previous;
		}
	}
}
