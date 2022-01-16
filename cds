#! /usr/bin/perl
use strict;
use warnings;
use Carp::Always;
use File::Basename;
use lib dirname (__FILE__);
#use lib 'editions/cli-sftp-inotify';
use CDS;

my $isTTY = -t STDOUT;
my $isCompletion = exists $ENV{COMP_LINE};
my $ui = CDS::UI->new(*STDOUT, $isCompletion || ! $isTTY);

my $actor = CDS::CLIActor->openOrCreateDefault($ui) // exit(1);
my $parser = CDS::Parser->new($actor, 'cds');
my $cds = CDS::Parser::Node->new(0, {constructor => \&DefaultHandler::new, function => \&DefaultHandler::default});
my $help = CDS::Parser::Node->new(1, {constructor => \&CDS::Commands::Help::new, function => \&CDS::Commands::Help::help});
$cds->addArrow($help, 1, 0, 'help');
$parser->start->addDefault($cds);

CDS::Commands::ActorGroup->register($cds, $help);
CDS::Commands::Announce->register($cds, $help);
CDS::Commands::Book->register($cds, $help);
CDS::Commands::CheckKeyPair->register($cds, $help);
CDS::Commands::CollectGarbage->register($cds, $help);
CDS::Commands::CreateKeyPair->register($cds, $help);
CDS::Commands::Curl->register($cds, $help);
CDS::Commands::DiscoverActorGroup->register($cds, $help);
CDS::Commands::EntrustedActors->register($cds, $help);
CDS::Commands::FolderStore->register($cds, $help);
CDS::Commands::Get->register($cds, $help);
CDS::Commands::Help->register($cds, $help);
CDS::Commands::List->register($cds, $help);
CDS::Commands::Modify->register($cds, $help);
CDS::Commands::OpenEnvelope->register($cds, $help);
CDS::Commands::Put->register($cds, $help);
CDS::Commands::Remember->register($cds, $help);
CDS::Commands::Select->register($cds, $help);
CDS::Commands::ShowCard->register($cds, $help);
CDS::Commands::ShowKeyPair->register($cds, $help);
CDS::Commands::ShowMessages->register($cds, $help);
CDS::Commands::ShowObject->register($cds, $help);
CDS::Commands::ShowPrivateData->register($cds, $help);
CDS::Commands::ShowTree->register($cds, $help);
CDS::Commands::StartHTTPServer->register($cds, $help);
CDS::Commands::Transfer->register($cds, $help);
CDS::Commands::UseCache->register($cds, $help);
CDS::Commands::UseStore->register($cds, $help);
CDS::Commands::Welcome->register($cds, $help);
CDS::Commands::WhatIs->register($cds, $help);

if ($isCompletion) {
	my $line = $ENV{COMP_LINE};
	$line = substr($line, 0, $ENV{COMP_POINT}) if exists $ENV{COMP_POINT};
	$parser->showCompletions($line);
} else {
	$actor->ui->pushIndent;
	$parser->execute(@ARGV);
	$actor->ui->popIndent;
	$actor->ui->removeProgress;
	exit(1) if $actor->ui->hasError;
}

package DefaultHandler;

sub new {
	my ($class, $actor) = @_;
	return bless {actor => $actor, ui => $actor->ui};
}

sub default {
	my $o = shift;
	my $cmd = shift;

	my $ui = $o->{ui};
	my $actor = $o->{actor};

	# Version
	$ui->space;
	$ui->title('Condensation CLI');
	$ui->line('Version ', $CDS::VERSION, ', ', $CDS::releaseDate, '.');

	# Welcome message
	my $welcome = CDS::Commands::Welcome->new($actor);
	if ($welcome->isEnabled) {
		$welcome->show;
	} else {
		$ui->line('Type "cds help" to get help.');
	}

	# Actor info
	$ui->space;
	$ui->title('Your key pair');
	CDS::Commands::ShowKeyPair->new($actor)->show($actor->keyPairToken);

	$ui->space;
	$ui->title('Your stores');
	$ui->line($ui->darkBold('Storage store    '), $actor->storageStore->url);
	$ui->line($ui->darkBold('Messaging store  '), $actor->messagingStoreUrl);

	# Read messages to merge any data before displaying the rest
	$ui->space;
	$actor->readMessages;

	$ui->space;
	$ui->title('Your actor group');
	$actor->registerIfNecessary;
	CDS::Commands::ActorGroup->new($actor)->show;

	$ui->space;
	$ui->title('Your entrusted actors');
	CDS::Commands::EntrustedActors->new($actor)->show;

	$ui->space;
	$ui->title('Selection (in this terminal)');
	CDS::Commands::Select->new($actor)->showSelection;

	$ui->space;
	$ui->title('Remembered values');
	CDS::Commands::Remember->new($actor)->showRememberedValues;

	# Announce if necessary
	$ui->space;
	$actor->announceIfNecessary;

	# Save any changes
	$actor->saveOrShowError;
	$ui->space;
	return;
}
