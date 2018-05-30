=pod
GADS - Globally Accessible Data Store
Copyright (C) 2018 Ctrl O Ltd

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

package GADS::Timeline;

use DateTime;
use HTML::Entities qw/encode_entities/;
use GADS::Graph::Data;
use Log::Report 'linkspace';
use Moo;
use MooX::Types::MooseLike::Base qw(:all);
use MooX::Types::MooseLike::DateTime qw/DateAndTime/;

has type => (
    is       => 'ro',
    required => 1,
);

has _date_colors => (
    is      => 'ro',
    default => sub { +{} },
);

has _available_colors => (
    is      => 'ro',
    default => sub {
        [qw/event-important event-success event-warning event-info event-inverse event-special/];
    },
);

has label_col_id => (
    is => 'ro',
);

has group_col_id => (
    is => 'ro',
);

has color_col_id => (
    is => 'ro',
);

has groups => (
    is => 'ro',
    default => sub { +{} },
);

has _group_count => (
    is      => 'rw',
    isa     => Int,
    default => 0,
);

has retrieved_from => (
    is      => 'rwp',
    isa     => Maybe[DateAndTime],
);

has retrieved_to => (
    is      => 'rwp',
    isa     => Maybe[DateAndTime],
);

has records => (
    is => 'ro',
);

sub clear
{   my $self = shift;
    $self->records->clear;
    $self->clear_items;
}

has _all_items_index => (
    is      => 'ro',
    default => sub { +{} },
);

has items => (
    is      => 'lazy',
    clearer => 1,
);

sub _build_items
{   my $self = shift;

    # Need a Graph::Data instance to get relevant colors
    my $graph = GADS::Graph::Data->new(
        schema  => $self->records->schema,
        records => undef,
    );

    # Add on any extra required columns for labelling etc
    my @extra;
    push @extra, $self->label_col_id if $self->label_col_id;
    push @extra, $self->group_col_id if $self->group_col_id;
    push @extra, $self->color_col_id if $self->color_col_id;
    $self->records->columns_extra([@extra]);

    # All the data values
    my @items;
    my $multiple_dates;
    my $records  = $self->records;
    my $find_min = $self->records->from && !$self->records->to ? $self->records->from->clone->truncate(to => 'day') : undef;
    my $find_max = !$self->records->from && $self->records->to ? $self->records->to->clone->truncate(to => 'day')->add(days => 1) : undef;
    my $count;
    while (my $record  = $records->single)
    {
        my @group_to_add = $self->group_col_id
            ? @{$record->fields->{$self->group_col_id}->text_all}
            : (undef);

        my $count;
        my ($min_of_this, $max_of_this);
        foreach my $group_to_add (@group_to_add)
        {
            my @dates; my @titles;
            my $had_date_col; # Used to detect multiple date columns in this view
            my @columns = @{$records->columns_retrieved_no};
            my %curcommon_values;
            foreach my $column (@columns)
            {
                if ($column->is_curcommon)
                {
                    push @columns, @{$column->curval_fields};
                    foreach my $row (values %{$record->fields->{$column->id}->field_values})
                    {
                        foreach my $cur_col_id (keys %$row)
                        {
                            $curcommon_values{$cur_col_id} ||= [];
                            push @{$curcommon_values{$cur_col_id}}, $row->{$cur_col_id};
                        }
                    }
                    next;
                }

                # Get item value
                my @d = $curcommon_values{$column->id}
                    ? @{$curcommon_values{$column->id}}
                    : ($record->fields->{$column->id});

                foreach my $d (@d)
                {
                    $d or next;

                    # Only show unique items of children, otherwise will be a lot of
                    # repeated entries
                    next if $record->parent_id && !$d->child_unique;

                    if ($column->return_type eq "daterange" || $column->return_type eq "date")
                    {
                        $multiple_dates = 1 if $had_date_col;
                        $had_date_col = 1;
                        next unless $column->user_can('read');

                        # Create colour if need be
                        $self->_date_colors->{$column->id} = shift @{$self->_available_colors} unless $self->_date_colors->{$column->id};

                        # Set colour
                        my $color = $self->_date_colors->{$column->id};

                        # Push value onto stack
                        if ($column->type eq "daterange")
                        {
                            foreach my $range (@{$d->values})
                            {
                                # It's possible that values from other columns not within
                                # the required range will have been retrieved. Don't bother
                                # adding them
                                if (
                                    (!$records->to || $range->start <= $records->to)
                                    && (!$records->from || $range->end >= $records->from)
                                ) {
                                    push @dates, {
                                        from       => $range->start,
                                        to         => $range->end,
                                        color      => $color,
                                        column     => $column->id,
                                        count      => ++$count,
                                        daterange  => 1,
                                        current_id => $d->record->current_id,
                                    };
                                    if ($find_min)
                                    {
                                        $self->_set_retrieved_from($range->start->clone)
                                            if (!$find_min || $range->start > $find_min)
                                                && (!defined $self->retrieved_from || $range->start < $self->retrieved_from);
                                        $self->_set_retrieved_from($range->end->clone)
                                            if (!$find_min || $range->end > $find_min)
                                                && (!defined $self->retrieved_from || $range->end < $self->retrieved_from);
                                        $min_of_this = $range->start->clone
                                            if (!$find_min || $range->start > $find_min)
                                                && (!defined $min_of_this || $range->start < $min_of_this);
                                        $min_of_this = $range->end->clone
                                            if (!$find_min || $range->end > $find_min)
                                                && (!defined $min_of_this || $range->end < $min_of_this);
                                    }
                                    if ($find_max)
                                    {
                                        $self->_set_retrieved_to($range->end->clone)
                                            if (!$find_max || $range->end < $find_max)
                                                && (!defined $self->retrieved_to || $range->end > $self->retrieved_to);
                                        $self->_set_retrieved_to($range->start->clone)
                                            if (!$find_max || $range->start < $find_max)
                                                && (!defined $self->retrieved_to || $range->start > $self->retrieved_to);
                                        $max_of_this = $range->end->clone
                                            if (!$find_max || $range->end < $find_max)
                                                && (!defined $max_of_this || $range->end > $max_of_this);
                                        $max_of_this = $range->start->clone
                                            if (!$find_max || $range->start < $find_max)
                                                && (!defined $max_of_this || $range->start > $max_of_this);
                                    }
                                }
                            }
                        }
                        else {
                            $d->value or next;
                            if (
                                (!$records->from || $d->value >= $records->from)
                                && (!$records->to || $d->value <= $records->to)
                            ) {
                                push @dates, {
                                    from       => $d->value,
                                    to         => $d->value,
                                    color      => $color,
                                    column     => $column->id,
                                    count      => 1,
                                    current_id => $d->record->current_id,
                                };
                                if ($find_min)
                                {
                                    $self->_set_retrieved_from($d->value->clone)
                                        if !defined $self->retrieved_from || $d->value < $self->retrieved_from;
                                    $min_of_this = $d->value->clone
                                        if (!$find_min || $d->value > $find_min)
                                            && (!defined $min_of_this || $d->value < $min_of_this);
                                }
                                if ($find_max)
                                {
                                    $self->_set_retrieved_to($d->value->clone)
                                        if !defined $self->retrieved_to || $d->value > $self->retrieved_to;
                                    $max_of_this = $d->value->clone
                                        if (!$find_max || $d->value < $find_max)
                                            && (!defined $max_of_this || $d->value > $max_of_this);
                                }
                            }
                        }
                    }
                    else {
                        next if $column->type eq "rag";
                        # Check if the user has selected only one label
                        next if $self->label_col_id && $self->label_col_id != $column->id;
                        # Don't add grouping text to title
                        next if $self->group_col_id && $self->group_col_id == $column->id;
                        # Not a date value, push onto title
                        # Don't want full HTML, which includes hyperlinks etc
                        push @titles, $d->as_string if $d->as_string;
                    }
                }
            }
            if (my $label = $self->label_col_id)
            {
                @titles = ($record->fields->{$label}->as_string)
                    # Value for this record may not exist or be blank
                    if $record->fields->{$label} && $record->fields->{$label}->as_string;
            }
            my $item_color; my $color_key = '';
            if (my $color = $self->color_col_id)
            {
                if ($record->fields->{$color})
                {
                    $color_key = $record->fields->{$color}->as_string;
                    $item_color = $graph->get_color($color_key);
                }
            }
            my $item_group;
            if ($group_to_add)
            {
                unless ($item_group = $self->groups->{$group_to_add})
                {
                    $item_group = $self->_group_count($self->_group_count + 1);
                    $self->groups->{$group_to_add} = $item_group;
                }
            }

            # Create title label
            my $title = join ' - ', @titles;
            my $title_abr = length $title > 50 ? substr($title, 0, 45).'...' : $title;

            foreach my $d (@dates)
            {
                next unless $d->{from} && $d->{to};
                my @add;
                push @add, $records->layout->column($d->{column})->name if $multiple_dates;
                push @add, $color_key if $self->color_col_id;
                my $add = join ', ', @add;
                my $title_i = $add ? "$title ($add)" : $title;
                my $title_i_abr = $add ? "$title_abr ($add)" : $title_abr;
                my $cid = $d->{current_id} || $record->current_id;
                if ($self->type eq 'calendar')
                {
                    my $item = {
                        "url"   => "/record/" . $cid,
                        "class" => $d->{color},
                        "title" => $title_i_abr,
                        "id"    => $record->current_id,
                        "start" => $d->{from}->epoch*1000,
                        "end"   => $d->{to}->epoch*1000,
                    };
                    push @items, $item;
                }
                else {
                    my $uid  = "$cid+$d->{column}+$d->{count}";
                    next if $self->_all_items_index->{$uid};
                    $title_i = encode_entities $title_i;
                    $title_i_abr = encode_entities $title_i_abr;
                    # If this is an item for a single day, then abbreviate the title,
                    # otherwise it can appear as a very long item on the timeline.
                    # If it's multiple day, the timeline plugin will automatically shorten it.
                    my $t = $d->{from}->epoch == $d->{to}->epoch ? $title_i_abr : $title_i;
                    my $item = {
                        "content"  => qq(<a title="$title_i" href="/record/$cid" style="color:inherit;">$t</a>),
                        "id"       => $uid,
                        current_id => $cid,
                        "start"    => $d->{from}->epoch * 1000,
                        "group"    => $item_group,
                        column     => $d->{column},
                        title      => $title_i,
                        dt         => $d->{from},
                    };
                    $item->{style} = qq(background-color: $item_color)
                        if $item_color;
                    # Add one day, otherwise ends at 00:00:00, looking like day is not included
                    $item->{end}    = $d->{to}->clone->add( days => 1 )->epoch * 1000 if $d->{daterange};
                    $item->{single} = $d->{from}->epoch * 1000 if !$d->{daterange};
                    $self->_all_items_index->{$item->{id}} = 1;
                    push @items, $item;
                }
            }
        }
        $self->_set_retrieved_to($min_of_this)
            if $find_min && (!$self->retrieved_to || $min_of_this > $self->retrieved_to);
        $self->_set_retrieved_from($max_of_this)
            if $find_max && (!$self->retrieved_from || $max_of_this < $self->retrieved_from);
    }

    \@items;
}

1;

