use 5.006;  # our
use strict;
use warnings;

package Dist::Zilla::Plugin::Beam::Connector;

our $VERSION = '0.001000';

# ABSTRACT: Connect events to listeners in Dist::Zilla plugins.

# AUTHORITY

use Moose;


__PACKAGE__->meta->make_immutable;
no Moose;

1;

=head1 SYNOPSIS

  [Some::PluginA / PluginA]
  [Some::PluginB / PluginB]

  [Beam::Connector]
  ; PluginA emitting event 'foo' passes the event to PluginB
  on   = plugin:PluginA#foo    =>   plugin:PluginB#handle_foo
  on   = plugin:PluginA#bar    =>   plugin:PluginB#handle_bar

=head1 DESCRIPTION

This module aims to allow L<< C<Dist::Zilla>|Dist::Zilla >> to use plugins
using L<< C<Beam::Event>|Beam::Event >> and L<< C<Beam::Emitter>|Beam::Emitter >>,
and perhaps reduce the need for massive amounts of composition and role application
proliferating C<CPAN>.

This is in lieu of a decent dependency injection system, and is presently relying
on C<Dist::Zilla> to load and construct the plugins itself, and then you just connect
the plugins together informally, without necessitating each plugin be specifically
tailored to the recipient.

Hopefully, this may also give scope for non-C<dzil> plugins being loadable into memory
some day, and allowing message passing of events to those plugins. ( Hence, the C<plugin:> prefix )

A Real World Example of what a future could look like?

  [GatherDir]

  [Test::Compile]

  [Beam::Connector]
  on = plugin:GatherDir#collect => plugin:Test::Compile#generate_test


C<GatherDir> in this example would build a mutable tree of files,
attach them to an event C<::GatherDir::Tree>, and pass that event to C<Test::Compile#generate_test>,
which would then add ( or remove, or mutate ) any files in that tree.

Tree state mutation then happens in order of prescription, in the order given
by the various C<on> declarations.

Thus, a single plugin can be in 2 places in the same logical stage.

  [Beam::Connector]
  on = plugin:GatherDir#collect => plugin:Test::Compile#generate_test
  ; lots more collectors here
  on = plugin:GatherDir#collect => plugin:Test::Compile#finalize_test

Whereas presently, order of affect is either governed by:

=over 4

=item * phase - where you can add but not remove or mutate, mutate but not add or remove, remove, but not add or mutate

=item * plugin order - where a single plugin cant be both early in a single phase and late

=back

If that example is not convincing enough for you, consider all the different ways
there are presently for implementing C<[MakeMaker]>. If you're following the standard logic
its fine, but as soon as you set out of the box, you have a few things you're going to have to do instead:

=over 4

=item * Subclass C<MakeMaker> in some way

=item * Re-implement C<MakeMaker> in some way

=item * Fuss a lot with phase ordering and then inject code in the C<File> that C<MakeMaker> generates.

=back

These approaches all work, but they're an open door to everyone re-implementing the same thing
thousands of times over.

  [MakeMaker]

  [DynamicPrereqs]
  -phases = none

  [Beam::Connector]
  on = plugin:MakeMaker#collect_augments => plugin:DynamicPrereqs#inject_augments

C<MakeMaker> here can just create an C<event>, pass it to C<DynamicPrereqs>,
C<DynamicPrereqs> can inject its desired content into the C<event>,
and then C<MakeMaker> can integrate the injected events at "wherever" the right place for them is.

This is much superior to scraping the generated text file and injecting events
at a given place based on a C<RegEx> match.

=cut
