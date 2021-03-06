use utf8;
package GADS::Schema::Result::Site;

use strict;
use warnings;

use base 'DBIx::Class::Core';

use JSON qw(decode_json encode_json);

__PACKAGE__->load_components("InflateColumn::DateTime");

__PACKAGE__->table("site");

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "host",
  { data_type => "varchar", is_nullable => 1, size => 128 },
  "name",
  { data_type => "text", is_nullable => 1 },
  "created",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "email_welcome_text",
  { data_type => "text", is_nullable => 1 },
  "email_welcome_subject",
  { data_type => "text", is_nullable => 1 },
  "email_delete_text",
  { data_type => "text", is_nullable => 1 },
  "email_delete_subject",
  { data_type => "text", is_nullable => 1 },
  "email_reject_text",
  { data_type => "text", is_nullable => 1 },
  "email_reject_subject",
  { data_type => "text", is_nullable => 1 },
  "register_text",
  { data_type => "text", is_nullable => 1 },
  "homepage_text",
  { data_type => "text", is_nullable => 1 },
  "homepage_text2",
  { data_type => "text", is_nullable => 1 },
  "register_title_help",
  { data_type => "text", is_nullable => 1 },
  "register_freetext1_help",
  { data_type => "text", is_nullable => 1 },
  "register_freetext2_help",
  { data_type => "text", is_nullable => 1 },
  "register_email_help",
  { data_type => "text", is_nullable => 1 },
  "register_organisation_help",
  { data_type => "text", is_nullable => 1 },
  "register_organisation_name",
  { data_type => "text", is_nullable => 1 },
  "register_organisation_mandatory",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "register_department_help",
  { data_type => "text", is_nullable => 1 },
  "register_department_name",
  { data_type => "text", is_nullable => 1 },
  "register_department_mandatory",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "register_team_help",
  { data_type => "text", is_nullable => 1 },
  "register_team_name",
  { data_type => "text", is_nullable => 1 },
  "register_team_mandatory",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "register_notes_help",
  { data_type => "text", is_nullable => 1 },
  "register_freetext1_name",
  { data_type => "text", is_nullable => 1 },
  "register_freetext2_name",
  { data_type => "text", is_nullable => 1 },
  "register_show_organisation",
  { data_type => "smallint", default_value => 1, is_nullable => 0 },
  "register_show_department",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "register_show_team",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "register_show_title",
  { data_type => "smallint", default_value => 1, is_nullable => 0 },
  "hide_account_request",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "remember_user_location",
  { data_type => "smallint", default_value => 1, is_nullable => 0 },
  "user_editable_fields",
  { data_type => "text", is_nullable => 1 },
);

__PACKAGE__->set_primary_key("id");

__PACKAGE__->has_many(
  "audits",
  "GADS::Schema::Result::Audit",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "groups",
  "GADS::Schema::Result::Group",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "imports",
  "GADS::Schema::Result::Import",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "instances",
  "GADS::Schema::Result::Instance",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "organisations",
  "GADS::Schema::Result::Organisation",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "departments",
  "GADS::Schema::Result::Department",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "teams",
  "GADS::Schema::Result::Team",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "titles",
  "GADS::Schema::Result::Title",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "users",
  "GADS::Schema::Result::User",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "dashboards",
  "GADS::Schema::Result::Dashboard",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

sub has_main_homepage
{   my $self = shift;
    return 1 if $self->homepage_text && $self->homepage_text !~ /^\s*$/;
    return 1 if $self->homepage_text2 && $self->homepage_text2 !~ /^\s*$/;
    return 0;
}

sub has_table_homepage
{   my $self = shift;
    foreach my $table ($self->instances)
    {
        return 1 if $table->homepage_text && $table->homepage_text !~ /^\s*$/;
        return 1 if $table->homepage_text2 && $table->homepage_text2 !~ /^\s*$/;
    }
    return 0;
}

sub organisation_name
{   my $self = shift;
    $self->register_organisation_name || 'Organisation';
}

sub department_name
{   my $self = shift;
    $self->register_department_name || 'Department';
}

sub team_name
{   my $self = shift;
    $self->register_team_name || 'Team';
}

sub update_user_editable_fields
{   my ($self, @fieldnames) = @_;

    my %editable = map { $_ => 1 } @fieldnames;

    my @fields = $self->user_fields;

    $_->{editable} = $editable{$_->{name}} || 0
        foreach @fields;

    my $json = encode_json +{
        map { $_->{name} => $_->{editable} } @fields
    };

    $self->update({
        user_editable_fields => $json,
    });
}

sub user_fields_as_string
{   my $self = shift;
    join ', ', map $_->{description}, $self->user_fields;
}

sub user_fields
{   my $self = shift;

    my @fields = (
        {
            name        => 'firstname',
            description => 'Forename',
            type        => 'freetext',
        },
        {
            name        => 'surname',
            description => 'Surname',
            type        => 'freetext',
        },
        {
            name        => 'email',
            description => 'Email',
            type        => 'freetext',
        },
    );
    push @fields, {
        name        => 'title',
        description => 'Title',
        type        => 'dropdown',
    } if $self->register_show_title;
    push @fields, {
        name        => 'organisation',
        description => $self->organisation_name,
        type        => 'dropdown',
    } if $self->register_show_organisation;
    push @fields, {
        name        => 'department_id',
        description => $self->department_name,
        type        => 'dropdown',
    } if $self->register_show_department;
    push @fields, {
        name        => 'team_id',
        description => $self->team_name,
        type        => 'dropdown',
    } if $self->register_show_team;
    push @fields, {
        name        => 'freetext1',
        description => $self->register_freetext1_name,
        type        => 'freetext',
    } if $self->register_freetext1_name;
    push @fields, {
        name        => 'freetext2',
        description => $self->register_freetext2_name,
        type        => 'freetext',
    } if $self->register_freetext2_name;

    my $user_editable = decode_json($self->user_editable_fields || '{}');

    $_->{editable} = $user_editable->{$_->{name}} // 1 # Default to editable
        foreach @fields;

    return @fields;
}

1;
