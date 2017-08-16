use Test::More; # tests => 1;
use strict;
use warnings;

use Log::Report;

use t::lib::DataSheet;

# Tests to check that fields that depend on another field for their display are
# blanked if they should not have been shown

my $sheet   = t::lib::DataSheet->new;
my $schema  = $sheet->schema;
my $layout  = $sheet->layout;
my $columns = $sheet->columns;
$sheet->create_records;

my $string1  = $columns->{string1};
my $integer1 = $columns->{integer1};
$integer1->display_field($string1->id);
$integer1->display_regex('foobar');
$integer1->write;
$layout->clear;

my $record = GADS::Record->new(
    user   => undef,
    layout => $layout,
    schema => $schema,
);

$record->find_current_id(1);

# Initial checks
{
    is($record->fields->{$string1->id}->as_string, 'Foo', 'Initial string value is correct');
    is($record->fields->{$integer1->id}->as_string, '50', 'Initial integer value is correct');
}

# Test write of value that should be shown
{
    $record->fields->{$string1->id}->set_value('foobar');
    $record->fields->{$integer1->id}->set_value('150');
    $record->write(no_alerts => 1);

    $record->clear;
    $record->find_current_id(1);

    is($record->fields->{$string1->id}->as_string, 'foobar', 'Updated string value is correct');
    is($record->fields->{$integer1->id}->as_string, '150', 'Updated integer value is correct');
}

# Test write of value that shouldn't be shown (string)
{
    $record->fields->{$string1->id}->set_value('foo');
    $record->fields->{$integer1->id}->set_value('200');
    $record->write(no_alerts => 1);

    $record->clear;
    $record->find_current_id(1);

    is($record->fields->{$string1->id}->as_string, 'foo', 'Updated string value is correct');
    is($record->fields->{$integer1->id}->as_string, '', 'Updated integer value is correct');
}

# Test value that depends on tree. Full levels of tree values can be tested
# using the nodes separated by hashes
{
    # Set up columns
    my $tree1 = $columns->{tree1};
    $integer1->display_field($tree1->id);
    $integer1->display_regex('(.*#)?tree3');
    $integer1->write;
    $layout->clear;

    # Set value of tree that should blank int
    $record->fields->{$tree1->id}->set_value(4); # value: tree1
    $record->fields->{$integer1->id}->set_value('250');
    $record->write(no_alerts => 1);

    $record->clear;
    $record->find_current_id(1);

    is($record->fields->{$tree1->id}->as_string, 'tree1', 'Initial tree value is correct');
    is($record->fields->{$integer1->id}->as_string, '', 'Updated integer value is correct');

    # Set matching value of tree - int should be written
    $record->fields->{$tree1->id}->set_value(6);
    $record->fields->{$integer1->id}->set_value('350');
    $record->write(no_alerts => 1);

    $record->clear;
    $record->find_current_id(1);

    is($record->fields->{$tree1->id}->as_string, 'tree3', 'Updated tree value is correct');
    is($record->fields->{$integer1->id}->as_string, '350', 'Updated integer value is correct');

    # Now test 2 tree levels
    $integer1->display_regex('tree2#tree3');
    $integer1->write;
    $layout->clear;
    # Set matching value of tree - int should be written
    $record->fields->{$tree1->id}->set_value(6);
    $record->fields->{$integer1->id}->set_value('400');
    $record->write(no_alerts => 1);

    $record->clear;
    $record->find_current_id(1);

    is($record->fields->{$tree1->id}->as_string, 'tree3', 'Tree value is correct');
    is($record->fields->{$integer1->id}->as_string, '400', 'Updated integer value with full tree path is correct');
}

done_testing();