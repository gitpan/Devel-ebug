package Devel::ebug::Backend::Plugin::Eval;
use strict;
use warnings;
  

sub register_commands {
  return ( eval => { sub => \&DB::eval, record => 0 } )
}

package DB;

# there appears to be something semi-magical about the DB 
# namespace that makes this eval only work when it's in it
sub eval {
  my($req, $context) = @_;
  my $eval = $req->{eval};
  local $SIG{__WARN__} = sub {};

  my $v = eval "package $context->{package}; $eval";
  if ($@) {
    return { eval => $@ };
  } else {
    return { eval => $v };
  }
}

1;
