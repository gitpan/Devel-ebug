use Module::Build;
use strict;

my $requires = {
  'Devel::StackTrace'    => '0',
  'Class::Accessor::Chained::Fast' => '0',
  'IO::Socket::INET'     => '0',
  'HTTP::Server::Simple::CGI' => '0',
  'List::Util'           => '0',
  'PadWalker'            => '0',
  'PPI'                  => '0',
  'PPI::HTML'            => '0',
  'PPI::Lexer'           => '0',
  'Proc::Background'     => '0',
  'Scalar::Util'         => '0',
  'Storable'             => '0',
  'String::Koremutake'   => '0',
  'Template'             => '0',
  'Test::Differences'    => '0',
  'Test::More'           => '0',
  'YAML'                 => '0',
};


# Test::Expect doesn't run under Windows atm
if ($^O =~ /mswin32/i) {
  $requires->{'Test::Expect'} = '0';
}

my $build = Module::Build->new(
  create_makefile_pl => 'small',
  license            => 'perl',
  module_name        => 'Devel::ebug',
  requires           => $requires,
  script_files       => ['ebug', 'ebug_http'],
);
$build->create_build_script;
