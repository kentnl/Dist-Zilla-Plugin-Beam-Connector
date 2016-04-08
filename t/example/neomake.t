
use strict;
use warnings;

use Test::More;
use Path::Tiny qw( cwd path );
use constant _eg => cwd()->child('examples/neo-makemaker')->stringify;
use lib _eg;

# ABSTRACT: Test neomake example works

use Test::DZil qw( Builder );
my $tzil = Builder->from_config( { dist_root => _eg } );
$tzil->chrome->logger->set_debug(1);
$tzil->build;

pass("Built ok");

done_testing;

