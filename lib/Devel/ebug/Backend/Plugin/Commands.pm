package Devel::ebug::Backend::Plugin::Commands;

sub register_commands {
  return ( commands    => { sub => \&commands }, );
}

sub commands {
  my($req, $context) = @_;
  return { commands => $context->{history} };
}

1;
