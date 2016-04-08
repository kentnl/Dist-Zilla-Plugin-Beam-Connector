use 5.006;
use strict;
use warnings;

package My::MakeMakerArgsEvent;

# ABSTRACT: An event for passing args for MakeMaker

# AUTHORITY

use Moo qw( extends has );

extends 'Beam::Event';

has 'args' => ( is => 'ro', required => 1 );

no Moo;

1;

