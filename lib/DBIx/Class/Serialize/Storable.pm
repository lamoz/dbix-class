package DBIx::Class::Serialize::Storable;
use strict;
use warnings;
use Storable;

sub STORABLE_freeze {
    my ($self, $cloning) = @_;
    my $to_serialize = { %$self };

    delete $to_serialize->{result_source};
    delete $to_serialize->{related_resultsets};
    delete $to_serialize->{_inflated_column};

    return('', $to_serialize);
}

sub STORABLE_thaw {
    my ($self, $cloning, $junk, $obj) = @_;

    %$self = %{ $obj };
    $self->result_source($self->result_source_instance)
      if $self->can('result_source_instance');
}

1;

__END__

=head1 NAME

    DBIx::Class::Serialize::Storable - hooks for Storable freeze/thaw

=head1 SYNOPSIS

    # in a table class definition
    __PACKAGE__->load_components(qw/Serialize::Storable/);

    # meanwhile, in a nearby piece of code
    my $cd = $schema->resultset('CD')->find(12);
    # if the cache uses Storable, this will work automatically
    $cache->set($cd->ID, $cd);

=head1 DESCRIPTION

This component adds hooks for Storable so that row objects can be
serialized. It assumes that your row object class (C<result_class>) is
the same as your table class, which is the normal situation.

=head1 HOOKS

The following hooks are defined for L<Storable> - see the
documentation for L<Storable/Hooks> for detailed information on these
hooks.

=head2 STORABLE_freeze

The serializing hook, called on the object during serialization. It
can be inherited, or defined in the class itself, like any other
method.

=head2 STORABLE_thaw

The deserializing hook called on the object during deserialization.

=head1 AUTHORS

David Kamholz <dkamholz@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
