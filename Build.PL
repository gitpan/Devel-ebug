use Module::Build;
use strict;

my $build = Module::Build->new(
  create_makefile_pl => 'traditional',
  license            => 'perl',
  module_name        => 'Devel::ebug',
  requires           => {
    'Class::Accessor::Chained::Fast'   => '0',
    'IO::Socket::INET'   => '0',
    'PadWalker'          => '0',
    'Proc::Background'   => '0',
    'Storable'           => '0',
    'String::Koremutake' => '0',
    'Test::Differences'  => '0',
    'Test::Expect'       => '0',
    'Test::More'         => '0',
  },
  script_files       => 'ebug',
);
$build->create_build_script;
