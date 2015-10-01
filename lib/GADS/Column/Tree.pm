=pod
GADS - Globally Accessible Data Store
Copyright (C) 2014 Ctrl O Ltd

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
=cut

package GADS::Column::Tree;

use Log::Report;
use String::CamelCase qw(camelize);
use Tree::DAG_Node;
use GADS::Util qw(:all);

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'GADS::Column';

sub DESTROY
{   my $self = shift;
    $self->_root->delete_tree if $self->_has_tree;
}

has end_node_only => (
    is     => 'rw',
    isa    => Bool,
    coerce => sub { $_[0] ? 1 : 0 },
);

# The root node, which all other nodes are referenced from.
# Gets value from _tree once it's built
has _root => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $_[0]->_tree->{root} },
);

# A hash of all the tree nodes. Also gets value from
# _tree once it's built. Contains only DAG_Node nodes
has _nodes => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $_[0]->_tree->{nodes} },
);

# A hash of all the enumvals. Also gets value from
# _tree once it's built. Contains the enumvals with
# their actual values in, but no tree relationship info
has _enumvals => (
    is      => 'lazy',
    isa     => ArrayRef,
    clearer => 1,
);

sub _build__enumvals
{   my $self = shift;
    my $enumrs = $self->schema->resultset('Enumval')->search({
        layout_id => $self->id,
        deleted   => 0,
    },{
        order_by => 'me.value',
    });
    $enumrs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    my @enumvals = $enumrs->all;
    \@enumvals;
}

has _enumvals_index => (
    is      => 'rwp',
    isa     => HashRef,
    lazy    => 1,
    builder => 1,
    clearer => 1,
);

sub _build__enumvals_index
{   my $self = shift;
    my %enumvals = map {$_->{id} => $_} @{$self->_enumvals};
    \%enumvals;
}

# The whole tree, constructed here so that it only
# needs to be done once
has _tree => (
    is        => 'rw',
    lazy      => 1,
    builder   => 1,
    predicate => 1,
);

# The original values hash
has original => (
    is => 'rw',
);

after build_values => sub {
    my ($self, $original) = @_;
    trace "Entering after build_values";
    $self->table('Enum');
    $self->original($original);
    $self->end_node_only($original->{end_node_only});
    trace "Exiting after build_values";
};

after 'write' => sub {
    my $self = shift;
    trace "Entering write";
    my $newitem = { end_node_only => $self->end_node_only };
    $self->schema->resultset('Layout')->find($self->id)->update($newitem);
};

before 'delete' => sub {
    my $self = shift;
    trace "Entering delete";
    $self->schema->resultset('Enum')->search({ layout_id => $self->id })->delete;
    $self->_clear_enumvals;
    $self->_clear_enumvals_index;
    $self->_delete_unused_nodes(purge => 1);
};

# Get a single node value
sub node
{   my ($self, $id) = @_;

    trace "Entering node";

    $id or return;
    {
        node  => $self->_nodes->{$id},
        value => $self->_enumvals_index->{$id}->{value},
    }
}

sub _build__tree
{   my $self = shift;

    trace "Entering _build_tree";

    my $enumvals;
    my $tree; my @order;
    my @enumvals = @{$self->_enumvals};
    foreach my $enumval (@enumvals)
    {
        my $parent = $enumval->{parent}; # && $enum->parent->id;
        my $node = Tree::DAG_Node->new();
        $node->name($enumval->{id});
        $tree->{$enumval->{id}} = {
            node   => $node,
            parent => $parent,
        };
        # Keep order in a list
        push @order, $enumval->{id};
        # Store the entire value for retrieval later
        $enumvals->{$enumval->{id}} = $enumval;
    }

    my $root = Tree::DAG_Node->new();
    $root->name("Root");

    foreach my $n (@order)
    {
        my $node = $tree->{$n};
        if (my $parent = $node->{parent})
        {
            $tree->{$parent}->{node}->add_daughter($node->{node});
        }
        else {
            $root->add_daughter($node->{node});
        }
    }

    {
        nodes    => $tree,
        root     => $root,
        enumvals => $enumvals,
    }
}

sub json
{   my ($self, $selected) = @_;

    trace "Entering json";

    my $stash = {
        tree => {
            text => "root"
        },
    };
    my $root = $self->_root;
    return [] unless $root->depth_under; # No nodes
    $root->walk_down
    ({
        callback => sub
        {
                my($node, $options) = @_;
                my $depth = $options->{_depth};
                if ($depth == 0)
                {
                    # Starting out at root
                    $options->{stash}->{last_node}->{$depth} = $stash->{tree};
                }
                elsif (!$self->_enumvals_index->{$node->name}->{deleted}) # Ignore deleted nodes
                {
                    my $parent = $options->{stash}->{last_node}->{$depth-1};
                    my $text = $self->_enumvals_index->{$node->name}->{value};
                    $parent->{children} = [] unless $parent->{children};
                    my $leaf = {
                        text => $text,
                        id   => $node->name,
                    };
                    $leaf->{state} = {selected => \1} if $selected && $node->name == $selected;
                    push @{$parent->{children}}, $leaf;
                    $options->{stash}->{last_node}->{$depth} = $parent->{children}->[-1];
                }
                return 1; # Keep walking.
        },
        _depth => 0,
        stash  => $stash,
    });
    $stash->{tree}->{children};
}

sub _delete_unused_nodes
{   my ($self, %options) = @_;

    trace "Entering _delete_unused_nodes";

    # Get all ones currently in database. This will be different to
    # the ones currently in _enumvals_index
    my $node_rs = $self->schema->resultset('Enumval')->search({
        layout_id => $self->id,
    });
    $node_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    my @all_nodes = $node_rs->all;

    my @top = grep { !$_->{parent} } @all_nodes;

    sub _flat
    {
        my ($self, $start, $flat, $level, @all_nodes) = @_;
        push @$flat, {
            id      => $start->{id},
            level   => $level,
            deleted => $start->{deleted},
            parent  => $start->{parent},
        };
        # See if it has any children
        my @children = grep { $_->{parent} && $_->{parent} == $start->{id} } @all_nodes;
        foreach my $child (@children)
        {
            _flat($self, $child, $flat, $level + 1, @all_nodes);
        }
    };

    # Now collect all the nodes in a flat structure. We can only delete
    # from the children up, otherwise there are relationship constraints.
    # We actually only delete nodes that aren't referenced anywhere, in
    # order to keep data integrity for old records
    my @flat;
    foreach (@top)
    {
        _flat $self, $_, \@flat, 0, @all_nodes;
    }
    @flat = sort { $b->{level} <=> $a->{level} } @flat;

    # Do the actual deletion if they don't exist
    foreach my $node (@flat)
    {
        next if !$options{purge} && $node->{deleted}; # Already deleted
        if ($self->_enumvals_index->{$node->{id}})
        {
            # Node in use somewhere
            if ($node->{parent} && !$self->_enumvals_index->{$node->{parent}})
            {
                # Current node still exists, but its parent doesn't
                # Move current node to the top by undefing the parent
                $self->schema->resultset('Enumval')->find($node->{id})->update({
                    parent => undef
                });
            }
        }
        else
        {
            my $count = $self->schema->resultset('Enum')->search({
                layout_id => $self->id,
                value     => $node->{id}
            })->count; # In use somewhere
            my $haschild = grep {$_->{parent} && $node->{id} == $_->{parent}} @flat; # Has (deleted) children
            if (!$options{purge} && ($count || $haschild))
            {
                $self->schema->resultset('Enumval')->find($node->{id})->update({
                    deleted => 1
                });
            }
            else {
                $self->schema->resultset('Enumval')->find($node->{id})->delete;
                # Remove from flattened list
                @flat = grep {$_->{id} != $node->{id}} @flat;
            }
        }
    }

    trace "Exiting _delete_unused_nodes";
}

sub random
{   my $self = shift;
    my %hash = %{$self->_enumvals_index};
    my $value;
    while (!$value)
    {
        my $node = $hash{(keys %hash)[rand keys %hash]};
        $value = $node->{value} unless $node->{deleted};
    }
    $value;
}

sub update
{   my ($self, $tree) = @_;

    trace "Entering update";

    # Create a new hash ref with our new tree structure in. We'll copy
    # the new nodes into it as we go, and then compare it to the old
    # one after to know which ones to delete from the database
    my $new_tree = {};

    # Do any updates
    foreach my $t (@$tree)
    {
        $self->_update($t, $new_tree);
    }

    $self->_set__enumvals_index($new_tree);
    $self->_clear_enumvals; # Array shouldn't be used now, but clear in case
    $self->_delete_unused_nodes;

    trace "Exiting update";
}

sub _update
{   my ($self, $t, $new_tree) = @_;

    trace "Entering _update";

    my $parent = $t->{parent} || '#';
    $parent = undef if $parent eq '#'; # Hash is top of tree (no parent)

    my $dbt;
    if ($t->{id} =~ /^[0-9]+$/)
    {
        # existing entry
        $dbt = $self->_enumvals_index->{$t->{id}};
    }
    if ($dbt)
    {
        if ($dbt->{value} ne $t->{text})
        {
            $self->schema->resultset('Enumval')->find($t->{id})->update({
                parent => $parent,
                value  => $t->{text},
            });
        }
        $new_tree->{$dbt->{id}} = $dbt;
    }
    else {
        # new entry
        $dbt = {
            layout_id => $self->id,
            parent    => $parent,
            value     => $t->{text},
        };
        my $id = $self->schema->resultset('Enumval')->create($dbt)->id;
        $dbt->{id} = $id;
        # Add to existing cache.
        $new_tree->{$id} = $dbt;
    }

    foreach my $child (@{$t->{children}})
    {
        $child->{parent} = $dbt->{id};
        $self->_update($child, $new_tree);
    }
};

1;

