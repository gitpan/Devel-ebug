package Devel::ebug::Backend::Plugin::Basic;
use strict;
use warnings;

sub register_commands {
    return ( basic => { sub => \&basic } );
}

sub basic {
  my($req, $context) = @_;
  return {
    package  => $context->{package},
    filename => $context->{filename},
    line     => $context->{line},
    codeline => $context->{codeline},
  }
}

1;
