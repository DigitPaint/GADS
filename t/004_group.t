use Test::More; # tests => 1;
use strict;
use warnings;

use GADS::Records;
use Log::Report;

use lib 't/lib';
use Test::GADS::DataSheet;

foreach my $multivalue (0..1)
{
    # It doesn't make a lot of sense to test a lot of these values, as the grouping
    # of text fields is not really possible (instead, the max value is used).
    # However, add them to the tests, to check that if a user does add them to a
    # grouping view that something unexpected doesn't happen
    my $data = [
        {
            string1    => 'foo1',
            integer1   => 25,
            date1      => '2011-10-10',
            daterange1 => ['2000-01-02', '2001-03-03'],
            enum1      => 8,
            tree1      => 12,
            curval1    => 1,
            person1    => 1,
        },
        {
            string1    => 'foo1',
            integer1   => 50,
            date1      => '2012-10-10',
            daterange1 => ['2004-01-02', '2005-03-03'],
            enum1      => $multivalue ? [7,9] : 7,
            tree1      => 12,
            curval1    => 1,
            person1    => 1,
        },
        {
            string1    => 'foo2',
            integer1   => 60,
            date1      => '2009-10-10',
            daterange1 => ['2007-01-02', '2007-03-03'],
            enum1      => 8,
            tree1      => 11,
            curval1    => 2,
            person1    => 1,
        },
        {
            string1    => 'foo2',
            integer1   => 70,
            date1      => '2008-10-10',
            daterange1 => ['2001-01-02', '2001-03-03'],
            enum1      => 8,
            tree1      => 11,
            curval1    => 2,
            person1    => 1,
        },
    ];

    my $expected = [
        {
            string1    => 'foo1',
            integer1   => 75,
            calc1      => 150,
            date1      => '2 unique',
            daterange1 => '2 unique',
            enum1      => $multivalue ? '3 unique' : '2 unique',
            tree1      => '1 unique',
            curval1    => '1 unique',
        },
        {
            string1    => 'foo2',
            integer1   => 130,
            calc1      => 260,
            date1      => '2 unique',
            daterange1 => '2 unique',
            enum1      => '1 unique',
            tree1      => '1 unique',
            curval1    => '1 unique',
        },
    ];

    my $curval_sheet = Test::GADS::DataSheet->new(instance_id => 2, user_permission_override => 0);
    $curval_sheet->create_records;
    my $schema = $curval_sheet->schema;

    my $sheet   = Test::GADS::DataSheet->new(
        data             => $data,
        calc_code        => "function evaluate (L1integer1) \n return L1integer1 * 2 \n end",
        schema           => $schema,
        curval           => 2,
        curval_field_ids => [$curval_sheet->columns->{string1}->id],
        multivalue       => $multivalue,
        user_permission_override => 0,
    );

    my $layout  = $sheet->layout;
    $sheet->create_records;
    my $columns = $sheet->columns;
    foreach my $col_id (keys %$columns)
    {
        my $c = $columns->{$col_id};
        $c->group_display('unique')
            if !$c->numeric;
        $c->write;
    }
    $layout->clear;

    my $autocur = $curval_sheet->add_autocur(
        refers_to_instance_id => 1,
        related_field_id      => $columns->{curval1}->id,
        curval_field_ids      => [$columns->{string1}->id],
    );

    my $string1    = $columns->{string1};
    my $integer1   = $columns->{integer1};
    my $calc1      = $columns->{calc1};
    my $date1      = $columns->{date1};
    my $daterange1 = $columns->{daterange1};
    my $enum1      = $columns->{enum1};
    my $tree1      = $columns->{tree1};
    my $curval1    = $columns->{curval1};

    my $view = GADS::View->new(
        name        => 'Group view',
        columns     => [$string1->id, $integer1->id, $calc1->id, $date1->id, $daterange1->id, $enum1->id, $tree1->id, $curval1->id],
        instance_id => $layout->instance_id,
        layout      => $layout,
        schema      => $schema,
        user        => $sheet->user,
    );
    $view->set_groups([$string1->id]);
    # Also add a sort, to check that doesn't result in unwanted multi-value
    # field joins
    $view->set_sorts({fields => [$enum1->id], types => ['asc']});
    $view->write;

    my $records = GADS::Records->new(
        view   => $view,
        layout => $layout,
        user   => $sheet->user,
        schema => $schema,
    );

    my @results = @{$records->results};
    is(@results, 2, "Correct number of rows for group by string");

    my @expected = (@$expected);
    foreach my $row (@results)
    {
        my $expected = shift @expected;
        is($row->fields->{$string1->id}, $expected->{string1}, "Group text correct");
        is($row->fields->{$integer1->id}, $expected->{integer1}, "Group integer correct");
        is($row->fields->{$calc1->id}, $expected->{calc1}, "Group calc correct");
        is($row->fields->{$date1->id}, $expected->{date1}, "Group date correct");
        is($row->fields->{$daterange1->id}, $expected->{daterange1}, "Group daterange correct");
        is($row->fields->{$enum1->id}, $expected->{enum1}, "Group enum correct");
        is($row->fields->{$tree1->id}, $expected->{tree1}, "Group tree correct");
        is($row->fields->{$curval1->id}, $expected->{curval1}, "Group curval correct");
        is($row->id_count, 2, "ID count correct");
    }

    # Remove grouped column from view and check still gets added as required
    $view->columns([$integer1->id]);
    $view->write;

    @expected = (@$expected);
    $records->clear;
    $records = GADS::Records->new(
        view   => $view,
        layout => $layout,
        user   => $sheet->user,
        schema => $schema,
    );
    @results = @{$records->results};
    is(@results, 2, "Correct number of rows for group by string");
    foreach my $row (@results)
    {
        my $expected = shift @expected;
        is($row->fields->{$string1->id}, $expected->{string1}, "Group text correct");
        is($row->fields->{$integer1->id}, $expected->{integer1}, "Group integer correct");
    }

    # Test grouping on all fields for completeness
    foreach my $type (keys %$columns)
    {
        next if $type eq 'file1';
        my $col = $columns->{$type};
        my $view = GADS::View->new(
            name        => 'Group view',
            columns     => [$col->id],
            instance_id => $layout->instance_id,
            layout      => $layout,
            schema      => $schema,
            user        => $sheet->user,
        );
        $view->set_groups([$col->id]);
        $view->write;

        $records = GADS::Records->new(
            view   => $view,
            layout => $layout,
            user   => $sheet->user,
            schema => $schema,
        );

        my $expected = {
            string1    => 'foo1',
            integer1   => 25,
            enum1      => 'foo1',
            tree1      => 'tree2',
            date1      => '2008-10-10',
            rag1       => 'b_red',
            calc1      => 50,
            curval1    => 'Foo',
            daterange1 => '2000-01-02 to 2001-03-03',
            person1    => 'User1, User1',
        };
        @results = @{$records->results};
        is($results[0]->fields->{$col->id}, $expected->{$type}, "Group by $type result correct");
    }

    # Remove permissions and check grouped column not in view
    $string1->set_permissions({$sheet->group->id => []});
    $string1->write;
    $layout->clear;
    $records = GADS::Records->new(
        view   => $view,
        layout => $layout,
        user   => $sheet->user,
        schema => $schema,
    );
    @results = @{$records->results};
    is(@results, 2, "Correct number of rows for group by string");
    is(@{$records->columns_render}, 1, "Only one column in view");

    # Test autocur
    $autocur = $curval_sheet->layout->column($autocur->id); # Reload to get new permissions
    $autocur->group_display('unique');
    $autocur->write;
    $view = GADS::View->new(
        name        => 'Group view autocur',
        columns     => [$autocur->id],
        instance_id => $curval_sheet->layout->instance_id,
        layout      => $curval_sheet->layout,
        schema      => $schema,
        user        => $sheet->user,
    );
    $view->set_groups([$curval_sheet->columns->{string1}->id]);
    $view->write;

    $records = GADS::Records->new(
        view   => $view,
        layout => $curval_sheet->layout,
        user   => $sheet->user,
        schema => $schema,
    );

    @results = @{$records->results};
    is(@results, 2, "Correct number of rows for group by string with autocur");
    foreach my $row (@results)
    {
        is($row->fields->{$autocur->id}, '2 unique', "Group text correct");
    }

    # Test curval (field itself)
    $view = GADS::View->new(
        name        => 'Group view curval',
        columns     => [$integer1->id],
        instance_id => $layout->instance_id,
        layout      => $layout,
        schema      => $schema,
        user        => $sheet->user,
    );
    $view->set_groups([$columns->{curval1}->id]);
    $view->write;

    $records = GADS::Records->new(
        view   => $view,
        layout => $layout,
        user   => $sheet->user,
        schema => $schema,
    );

    @results = @{$records->results};
    is(@results, 2, "Correct number of rows for group by curval");
    is($results[0]->fields->{$integer1->id}, '75', "Group by curval first result correct");
    is($results[1]->fields->{$integer1->id}, '130', "Group by curval second result correct");

    # Test curval (subfield)
    $view = GADS::View->new(
        name        => 'Group view curval subfield',
        columns     => [$integer1->id],
        instance_id => $layout->instance_id,
        layout      => $layout,
        schema      => $schema,
        user        => $sheet->user,
    );
    $view->set_groups([$columns->{curval1}->id."_".$curval_sheet->columns->{string1}->id]);
    $view->write;

    $records = GADS::Records->new(
        view   => $view,
        layout => $layout,
        user   => $sheet->user,
        schema => $schema,
    );

    @results = @{$records->results};
    is(@results, 2, "Correct number of rows for group by curval subfield");
    is($results[0]->fields->{$integer1->id}, '75', "Group by curval subfield first result correct");
    is($results[1]->fields->{$integer1->id}, '130', "Group by curval subfield second result correct");

}

# Make sure that correct columns are returned from view
{
    my $sheet   = Test::GADS::DataSheet->new;
    my $schema  = $sheet->schema;
    my $layout  = $sheet->layout;
    my $columns = $sheet->columns;
    $sheet->create_records;

    my $string1  = $columns->{string1};
    my $integer1 = $columns->{integer1};
    my $enum1    = $columns->{enum1};

    my $view = GADS::View->new(
        name        => 'Group view',
        columns     => [$string1->id, $integer1->id],
        instance_id => $layout->instance_id,
        layout      => $layout,
        schema      => $schema,
        user        => $sheet->user,
    );
    $view->set_groups([$enum1->id]);
    $view->write;

    foreach my $run (0..2)
    {
        my @additional = ({
            id    => $string1->id,
            value => 'Foo',
        });

        my $records = GADS::Records->new(
            view               => $view,
            layout             => $layout,
            user               => $sheet->user,
            schema             => $schema,
            additional_filters => $run == 1 ? \@additional : [],
        );

        my $vids = join ' ', map { $_->id } @{$records->columns_render};
        my $expected = $run == 0
            ? $enum1->id.' '.$integer1->id
            : $run == 1
            ? $string1->id.' '.$integer1->id.' '.$enum1->id
            : $enum1->id.' '.$string1->id.' '.$integer1->id;
        is($vids, $expected, "Correct columns in group view");

        if ($run == 1)
        {
            # Add string column as unique count
            $string1->group_display('unique');
            $string1->write;
            $layout->clear;
        }
    }
}

# Large number of records (greater than default number of rows in table). Check
# that paging does not affect results
{
    my @data;
    my %group_values;
    for my $count (1..300)
    {
        my $id = substr $count, -1;
        push @data, {
            string1  => "Foo$id",
            integer1 => $id * 10,
        };
    }

    my $sheet = Test::GADS::DataSheet->new(data => \@data);
    $sheet->create_records;
    my $schema   = $sheet->schema;
    my $layout   = $sheet->layout;
    my $columns  = $sheet->columns;
    my $string1  = $columns->{string1};
    my $integer1 = $columns->{integer1};

    my $view = GADS::View->new(
        name        => 'Group view large',
        columns     => [$string1->id, $integer1->id],
        instance_id => $layout->instance_id,
        layout      => $layout,
        schema      => $schema,
        user        => $sheet->user,
    );
    $view->set_groups([$string1->id]);
    $view->write;

    my $records = GADS::Records->new(
        # Specify rows parameter to simulate default used for table view. This
        # should be ignored
        rows   => 50,
        page   => 1,
        view   => $view,
        layout => $layout,
        user   => $sheet->user,
        schema => $schema,
    );

    my @results = @{$records->results};
    is(@results, 10, "Correct number of rows for group of large number of records");
    is($records->pages, 1, "Correct number of pages for large number of records");

    my @expected = (
        {
            string1  => 'Foo0',
            integer1 => 0,
        },
        {
            string1  => 'Foo1',
            integer1 => 300,
        },
        {
            string1  => 'Foo2',
            integer1 => 600,
        },
        {
            string1  => 'Foo3',
            integer1 => 900,
        },
        {
            string1  => 'Foo4',
            integer1 => 1200,
        },
        {
            string1  => 'Foo5',
            integer1 => 1500,
        },
        {
            string1  => 'Foo6',
            integer1 => 1800,
        },
        {
            string1  => 'Foo7',
            integer1 => 2100,
        },
        {
            string1  => 'Foo8',
            integer1 => 2400,
        },
        {
            string1  => 'Foo9',
            integer1 => 2700,
        },
    );
    foreach my $row (@results)
    {
        my $expected = shift @expected;
        is($row->fields->{$string1->id}, $expected->{string1}, "Group text correct");
        is($row->fields->{$integer1->id}, $expected->{integer1}, "Group integer correct");
        is($row->id_count, 30, "ID count correct for large records group");
    }

}

# Test of recalc aggregate type, whereby calc values are recalculated based on
# other aggregate fields. Do not include all required columns in the view -
# this should still work
{
    my $data = [
        {
            string1    => 'foo1',
            integer1   => 250,
            integer2   => 500,
        },
        {
            string1    => 'foo1',
            integer1   => 50,
            integer2   => 50,
        },
        {
            string1    => 'foo2',
            integer1   => 3,
            integer2   => 4,
        },
        {
            string1    => 'foo2',
            integer1   => 120,
            integer2   => 240,
        },
    ];

    my $sheet   = Test::GADS::DataSheet->new(
        data         => $data,
        multivalue   => 1,
        calc_code    => "function evaluate (L1integer1, L1integer2) \n return (L1integer1 / L1integer2) * 100 \n end",
        column_count => { integer => 2 },
    );
    my $schema  = $sheet->schema;
    my $layout  = $sheet->layout;
    my $columns = $sheet->columns;
    $sheet->create_records;

    my $string1 = $columns->{string1};
    my $integer1 = $columns->{integer1};
    $integer1->aggregate('sum');
    $integer1->write;
    my $integer2 = $columns->{integer2};
    $integer2->aggregate('sum');
    $integer2->write;
    my $calc1   = $columns->{calc1};
    $calc1->aggregate('recalc');
    $calc1->write;
    $layout->clear;

    my $view = GADS::View->new(
        name        => 'Group view',
        columns     => [$string1->id, $calc1->id],
        instance_id => $layout->instance_id,
        layout      => $layout,
        schema      => $schema,
        user        => $sheet->user,
    );
    $view->set_groups([$string1->id]);
    $view->write;

    my $records = GADS::Records->new(
        view   => $view,
        layout => $layout,
        user   => $sheet->user,
        schema => $schema,
    );

    my @expected = (
        {
            string1 => 'foo1',
            calc1   => 55,
        },
        {
            string1 => 'foo2',
            calc1   => 50,
        },
    );

    my @results = @{$records->results};
    is(@results, 2, "Correct number of rows for group by string");
    foreach my $row (@results)
    {
        my $expected = shift @expected;
        is($row->fields->{$string1->id}, $expected->{string1}, "Group text correct");
        is($row->fields->{$calc1->id}, $expected->{calc1}, "Group calc correct");
    }
}

done_testing();
