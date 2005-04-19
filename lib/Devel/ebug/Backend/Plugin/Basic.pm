package Devel::ebug::Backend::Plugin::Basic;
use strict;
use warnings;

sub register_commands {
    return ( basic => { sub => \&basic } );
}

sub basic {
  my($req, $context) = @_;
  return {
    codeline => $context->{codeline},
    filename => $context->{filename},
    finished => $context->{finished},
    line     => $context->{line},
    package  => $context->{package},
  }
}

1;
