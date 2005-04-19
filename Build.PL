use strict;
use lib 'lib';
use Devel::ebug::Build;

my $requires = {
  'Carp'                 => '0',
  'Catalyst'             => '5.02',
  'Catalyst::Plugin::Static' => '0.07',
  'Catalyst::View::TT'    => '0.11',
  'Class::Accessor::Chained::Fast' => '0',
  'Devel::StackTrace'    => '0',
  'IO::Socket::INET'     => '0',
  'File::Find'           => '0',
  'HTTP::Server::Simple::CGI' => '0',
  'HTML::Prototype'      => '0',
  'List::Util'           => '0',
  'Module::Pluggable'    => '0',
  'PadWalker'            => '0',
  'Path::Class'          => '0',
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
  'Test::WWW::Mechanize::Catalyst' => '0.31',
  'YAML'                 => '0.39',
};


# Test::Expect doesn't run under Windows atm
if ($^O !~ /mswin32/i) {
  $requires->{'Test::Expect'} = '0';
}

my $build = Devel::ebug::Build->new(
  create_makefile_pl => 'small',
  license            => 'perl',
  module_name        => 'Devel::ebug',
  requires           => $requires,
  script_files       => ['ebug', 'ebug_http'],
);
$build->{config}->{__extras_from} = [ 'root' ];
$build->create_build_script;
