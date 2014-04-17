package Devel::ebug::Backend::Plugin::Commands;
$Devel::ebug::Backend::Plugin::Commands::VERSION = '0.56';
use strict;
use warnings;

sub register_commands {
  return ( commands    => { sub => \&commands }, );
}

sub commands {
  my($req, $context) = @_;
  return { commands => $context->{history} };
}

1;
