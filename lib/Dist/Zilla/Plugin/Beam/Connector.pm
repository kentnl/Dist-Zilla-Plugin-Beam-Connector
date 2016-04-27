use 5.006;    # our
use strict;
use warnings;

package Dist::Zilla::Plugin::Beam::Connector;

our $VERSION = '0.001000';

# ABSTRACT: Connect events to listeners in Dist::Zilla plugins.

# AUTHORITY

use Moose qw( has around with );
use MooseX::LazyRequire;
use Carp qw( croak );
use Path::Tiny qw( path );
with 'Dist::Zilla::Role::Plugin';

has 'on' => (
  isa     => 'ArrayRef[Str]',
  is      => 'ro',
  default => sub { [] },
);

has 'container' => (
  isa           => 'Str',
  is            => 'ro',
  lazy_required => 1,
);

has '_on_parsed' => (
  isa     => 'ArrayRef',
  is      => 'ro',
  lazy    => 1,
  builder => '_build_on_parsed',
);

has '_container' => (
  isa     => 'Ref',
  is      => 'ro',
  lazy    => 1,
  builder => '_build_container',
);

around mvp_multivalue_args => sub {
  my ( $orig, $self, @args ) = @_;
  return ( qw( on ), $self->$orig(@args) );
};

around plugin_from_config => sub {
  my ( $orig, $plugin_class, $name, $arg, $own_section ) = @_;
  my $instance = $plugin_class->$orig( $name, $arg, $own_section );
  for my $connection ( @{ $instance->_on_parsed } ) {
    $instance->_connect( $connection->{emitter}, $connection->{listener} );
  }
  return $instance;
};

__PACKAGE__->meta->make_immutable;
no Moose;

sub _parse_connector {
  my ($connector) = @_;
  if ( $connector =~ /\Aplugin:(.+?)[#]([^#]+)\z/sx ) {
    return { type => 'plugin', name => "$1", connection => "$2", };
  }
  if ( $connector =~ /\Acontainer:(.+?)[#]([^#]+)\z/sx ) {
    return { type => 'container', name => "$1", connection => "$2", };
  }
  croak "Invalid connector specification \"$connector\"\n"    #
    . q[Didn't match "(plugin|container):<id>#<event|listener>"];
}

sub _parse_on_directive {
  my ($connection_string) = @_;

  # Remove leading padding
  $connection_string =~ s/\A\s*//sx;
  $connection_string =~ s/\s*\z//sx;
  if ( $connection_string =~ /\A(.+?)\s*=>\s*(.+?)\z/sx ) {
    my ( $emitter, $listener ) = ( $1, $2 );
    return {
      emitter  => _parse_connector($emitter),
      listener => _parse_connector($listener),
    };
  }
  croak "Can't parse 'on' directive \"$connection_string\"\n"    #
    . q[Didn't match "emitter => listener"];
}

sub _find_connector {
  my ( $self, $spec ) = @_;
  if ( 'plugin' eq $spec->{type} ) {
    my $plugin = $self->zilla->plugin_named( $spec->{name} );
    return $plugin if defined $plugin;
    croak "Can't resolve plugin \"$spec->{name}\" to an instance.\n"    #
      . q[Did the plugin exist? Is the connection *after* it?];
  }
  if ( 'container' eq $spec->{type} ) {
    return $self->_container->get( $spec->{'name'} );
  }
  croak "Unknown connector type \"$spec->{type}\"";
}

# This is to avoid making the sub a closure that contains the emitter
sub _make_connector {
  my ( $recipient, $method_name ) = @_;

  # Maybe weak ref? IDK
  return sub {
    my ($event) = @_;
    $recipient->$method_name($event);
  };
}

sub _connect {
  my ( $self, $emitter, $listener ) = @_;
  my $emitter_object  = $self->_find_connector($emitter);
  my $listener_object = $self->_find_connector($listener);

  my $emit_name   = $emitter->{type} . $emitter->{name};
  my $listen_name = $listener->{type} . $listener->{name};

  my $emit_on   = $emitter->{connection};
  my $listen_on = $listener->{connection};

  if ( not $emitter_object->can('on') ) {
    croak qq[Emitter Target "$emit_name" has no "on" method to register listeners];
  }
  if ( not $listener_object->can($listen_on) ) {
    croak qq[Listener Target "$listen_name" has no "$listen_on" method to recive events];
  }

  $self->log_debug( [ 'Connecting %s#<%s> to %s#<%s>', $emit_name, $emit_on, $listen_name, $listen_on ] );
  $emitter_object->on( $emit_on, _make_connector( $listener_object, $listen_on ) );
  return;

}

sub _build_on_parsed {
  my ($self) = @_;
  return [ map { _parse_on_directive($_) } @{ $self->on } ];
}

sub _build_container {
  my ($self) = @_;
  my $file = $self->container;
  require Beam::Wire;
  $self->log_debug( [ 'Loading Beam::Wire container from %s', $file ] );
  my $wire = Beam::Wire->new( file => path( $self->zilla->root, $file ) );
  return $wire;
}

1;

=head1 SYNOPSIS

  [Some::PluginA / PluginA]
  [Some::PluginB / PluginB]

  [Beam::Connector]
  ; PluginA emitting event 'foo' passes the event to PluginB
  on   = plugin:PluginA#foo    =>   plugin:PluginB#handle_foo
  on   = plugin:PluginA#bar    =>   plugin:PluginB#handle_bar
  ; Load 'beam.yml' as a Beam::Wire container
  container = beam.yml
  ; Handle Dist::Zilla plugin events with arbitrary classes
  ; loaded by Beam::Wire
  on   = plugin:PluginA#foo    =>   container:servicename#handle_foo
  on   = plugin:PluginA#bar    =>   container:otherservicename#handle_bar

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

=head1 PARAMETERS

=head2 C<container>

Allows loading an arbitrary C<Beam::Wire> container L<< specification|Beam::Wire::Help::Config >>, initializing the
relevant objects lazily, and connecting them to relevant events emitted by C<dzil> plugins.

  [Beam::Connector]
  container = inc/dist_beam.yml

The value can be a path to any file name that C<< Beam::Wire->new( file => ... ) >> understands, (which itself
is any file name that C<< Config::Any->load_files >> understands).

Items in loaded container can then be referred to by their identifiers to the L<< C<on>|/on >> parameter in the form

  container:${name}#${method}

For example:

  [Beam::Connector]
  container = inc/dist_beam.yml
  on = plugin:GatherDir#gather_files => container:file_gatherer#on_gather_files

This would register the object called C<file_gatherer> inside the container to be a recipient of any events called
C<gather_files> emitted by the plugin I<named> C<GatherDir>

=head2 C<on>

Defines a connection between an event emitter and a listener.

The general syntax is:

  on = emitterspec => listenerspec

Where C<emitterspec> and C<listenerspec> are of the form

  objectnamespace:objectname#connector

=head3 C<objectnamespace>

There are presently two defined object name-spaces.

=over 4

=item * C<plugin>: Resolves C<objectname> to a C<Dist::Zilla> plugin by its C<name> identifier

=item * C<container>: Resolves C<objectname> to an explicitly named object inside an associated L<< C<container>|/container >>

=back

=head3 C<connector>

For an C<emitter>, the C<connector> property identifies the name of the event that is expected to be emitted by
that C<emitter>

For a C<listener>, the C<connector> property identifies the name of a C<method> that is expected to receive the event.

=cut
