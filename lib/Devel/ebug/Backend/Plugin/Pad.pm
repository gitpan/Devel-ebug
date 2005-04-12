package Devel::ebug::Backend::Plugin::Pad;
use strict;
use warnings;
use PadWalker;

sub register_commands {
  return ( pad => { sub => \&DB::pad } )
}

package DB;

sub pad {
  my($req, $context) = @_;
  my $pad;
  my $h = eval { PadWalker::peek_my(2) };
  foreach my $k (sort keys %$h) {
    if ($k =~ /^@/) {
      my @v = eval "package $context->{package}; ($k)";
      $pad->{$k} = \@v;
    } else {
      my $v = eval "package $context->{package}; $k";
      $pad->{$k} = $v;
    }
  }
  return { pad => $pad };
}


1;
