#!/usr/bin/perl

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

use FindBin;
use lib "$FindBin::Bin/../lib";

use Dancer2 ':script';
use Dancer2::Plugin::DBIC qw(schema resultset rset);
use GADS::Schema;
use GADS::Record;
use GADS::DB;
use GADS::Alert;
use Ouch;
use Text::CSV;

GADS::DB->setup;

my $csv = Text::CSV->new({ binary => 1 }) # should set binary attribute?
    or die "Cannot use CSV: ".Text::CSV->error_diag ();

my $first = <STDIN>;
$csv->parse($first) or die "Failed to parse initial file line for headings";

my @f = $csv->fields;

# First check if fields exist
my @fields; my $selects;
my $dr;
foreach my $field (@f)
{
    my ($f) = rset('Layout')->search({ name => $field })->all;
    die "Field $field does not exist" unless $f;
    push @fields, {
        field => "field".$f->id,
        id    => $f->id,
        type  => $f->type,
        name  => $f->name,
    };

    die "Daterange $field needs 2 columns" if ($dr && $f->type ne "daterange");

    # Prefill select values
    if ($f->type eq "enum" || $f->type eq "tree")
    {
        my @vals = rset('Enumval')->search({ layout_id => $f->id, deleted => 0 })->all;
        foreach my $v (@vals)
        {
            # See if it already exists - possible multiple values
            if (exists $selects->{$f->id}->{$v->value})
            {
                my $existing = $selects->{$f->id}->{$v->value};
                my @existing = ref $existing eq "ARRAY" ? @$existing : ($existing);
                $selects->{$f->id}->{$v->value} = [@existing, $v->id];
            }
            else {
                $selects->{$f->id}->{$v->value} = $v->id;
            }
        }
    }
    elsif ($f->type eq "daterange")
    {
        # Expect a second daterange column immediately after
        $dr = $dr ? 0 : 1;
    }
}

my @all_bad;

while (<STDIN>)
{
    $csv->parse($_) or die "Failed to parse link $_";
    my @row = $csv->fields
        or next;
    next unless "@row"; # Skip blank lines

    my $count = 0;
    my $input; my @bad;
    my $previous_field;
    foreach my $col (@row)
    {
        my $f = $fields[$count];
        say STDERR "Going to process $col into field $f->{name}";
        if ($f->{type} eq "enum" || $f->{type} eq "tree")
        {
            # Get enum ID value
            if (!$col)
            {
                # Blank value. Insertion will handle non-optional fields
                $input->{$f->{field}} = $col;
            }
            else {
                if (ref $selects->{$f->{id}}->{$col} eq "ARRAY")
                {
                    push @bad, qq(Multiple instances of enum value "$col" for "$f->{name}");
                }
                elsif (exists $selects->{$f->{id}}->{$col})
                {
                    # okay
                    $input->{$f->{field}} = $selects->{$f->{id}}->{$col};
                }
                else {
                    push @bad, qq(Invalid enum value "$col" for "$f->{name}");
                }
            }
        }
        elsif ($f->{type} eq "daterange")
        {
            $col =~ s!/!-!g; # Change date delimiters from slash to hyphen
            if ($col =~ /([0-9]{1,2}).([0-9]{1,2}).([0-9]{4})/)
            {
                # Swap year and day if needed
                $col = "$3-$2-$1";
            }
            if (exists $input->{$f->{field}})
            {
                push $input->{$f->{field}}, $col;
            }
            else {
                $input->{$f->{field}} = [$col];
            }
        }
        else {
            $input->{$f->{field}} = $col;
        }

        my $previous_field = $f;
        $count++;
    }

    unless (@bad)
    {
        # Insert record into DB. May still be problems
        eval {GADS::Record->update($input)};
        if (hug)
        {
            push @bad, $@;
        }
    }

    if (@bad)
    {
        push @all_bad, {
            problems => \@bad,
            row      => $_,
        };
    }

}

