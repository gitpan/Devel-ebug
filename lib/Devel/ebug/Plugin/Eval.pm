package Devel::ebug::Plugin::Eval;
use base qw(Exporter);
our @EXPORT = qw(eval);

# eval
sub eval {
  my($self, $eval) = @_;
  my $response = $self->talk({
    command => "eval",
    eval    => $eval,
  });
  return $response->{eval};
}

1;
