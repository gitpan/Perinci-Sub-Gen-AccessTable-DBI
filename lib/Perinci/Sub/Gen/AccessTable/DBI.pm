package Perinci::Sub::Gen::AccessTable::DBI;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';
use Moo; # we go OO just for the I18N, we don't store attributes, etc

use Data::Clone;
use Data::Sah;
use DBI;
use Perinci::Sub::Gen::AccessTable qw(gen_read_table_func);
#use Data::Sah;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(gen_read_dbi_table_func);

with 'SHARYANTO::Role::I18NMany';

our $VERSION = '0.04'; # VERSION

our %SPEC;
my $label = "(gen_read_dbi_table_func)";

sub __parse_schema {
    Data::Sah::normalize_schema($_[0]);
}

my $spec = clone $Perinci::Sub::Gen::AccessTable::SPEC{gen_read_table_func};
$spec->{summary} = 'Generate function (and its metadata) to read DBI table';
$spec->{description} = <<'_';

The generated function acts like a simple single table SQL SELECT query,
featuring filtering, ordering, and paging, but using arguments as the 'query
language'. The generated function is suitable for exposing a table data from an
API function. Please see Perinci::Sub::Gen::AccessTable's documentation for more
details on what arguments the generated function will accept.

_
delete $spec->{args}{table_data};
$spec->{args}{table_name} = {
    req => 1,
    schema => 'str*',
    summary => 'DBI table name',
};
$spec->{args}{table_spec}{description} = <<'_';

Just like Perinci::Sub::Gen::AccessTable's table_spec, except that each field
specification can have a key called `db_field` to specify the database field (if
different). Currently this is required. Future version will be able to generate
table_spec from table schema if table_spec is not specified.

_
$spec->{args}{dbh} = {
    schema => 'obj*',
    summary => 'DBI database handle',
};
$SPEC{gen_read_dbi_table_func} = $spec;
sub gen_read_dbi_table_func {
    my $self = __PACKAGE__->new;
    unshift @_, $self;
    goto &_gen_read_dbi_table_func;
}

sub _gen_read_dbi_table_func {
    my ($self, %args) = @_;

    # XXX schema
    my $table_name = $args{table_name}; delete $args{table_name};
    $table_name or return [400, "Please specify table_name"];
    my $dbh = $args{dbh}; delete $args{dbh};
    $dbh or return [400, "Please specify dbh"];

    # duplicate and make each field's schema normalized
    my $table_spec = clone($args{table_spec});
    for my $fspec (values %{$table_spec->{fields}}) {
        $fspec->{schema} //= 'any';
        $fspec->{schema} = __parse_schema($fspec->{schema});
    }

    my $table_data = sub {
        my $query = shift;

        my ($db) = $dbh->get_info(17);
        unless ($db =~ /\A(SQLite|mysql|Pg)\z/) {
            $log->warnf("$label Database is not supported: %s", $db);
        }

        # function to quote identifier, e.g. `col` or "col"
        my $qi = sub {
            if ($db =~ /SQLite|mysql/) { return "`$_[0]`" }
            return qq("$_[0]");
        };

        my $fspecs = $table_spec->{fields};
        my @fields = keys %$fspecs;
        my @searchable_fields = grep {
            !defined($fspecs->{$_}{searchable}) || $fspecs->{$_}{searchable}
        } @fields;

        my $filtered;
        my @wheres;
        # XXX case_insensitive_search & word_search not yet observed
        my $q = $query->{q};
        if (defined($q) && @searchable_fields) {
            push @wheres, "(".
                join(" OR ", map {$qi->($fspecs->{$_}{db_field}//$_)." LIKE ".
                                      $dbh->quote("%$q%")}
                         @searchable_fields).
                    ")";
        }
        if ($args{custom_search}) {
            $filtered = 0; # perigen-acctbl will be doing custom_search
        }
        if ($args{custom_filter}) {
            $filtered = 0; # perigen-acctbl will be doing custom_search
        }
        for my $filter (@{$query->{filters}}) {
            my ($f, $op, $opn) = @$filter;
            my $qdbf = $qi->($fspecs->{$f}{db_field} // $f);
            my $qopn = $dbh->quote($opn);
            if ($op eq 'truth')     { push @wheres, $qdbf
            } elsif ($op eq '~~')   { $filtered = 0 # not supported
            } elsif ($op eq '!~~')  { $filtered = 0 # not supported
            } elsif ($op eq 'eq')   { push @wheres, "$qdbf = $qopn"
            } elsif ($op eq '==')   { push @wheres, "$qdbf = $qopn"
            } elsif ($op eq 'ne')   { push @wheres, "$qdbf <> $qopn"
            } elsif ($op eq '!=')   { push @wheres, "$qdbf <> $qopn"
            } elsif ($op eq 'ge')   { push @wheres, "$qdbf >= $qopn"
            } elsif ($op eq '>=')   { push @wheres, "$qdbf >= $qopn"
            } elsif ($op eq 'gt')   { push @wheres, "$qdbf > $qopn"
            } elsif ($op eq '>' )   { push @wheres, "$qdbf > $qopn"
            } elsif ($op eq 'le')   { push @wheres, "$qdbf <= $qopn"
            } elsif ($op eq '<=')   { push @wheres, "$qdbf <= $qopn"
            } elsif ($op eq 'lt')   { push @wheres, "$qdbf < $qopn"
            } elsif ($op eq '<' )   { push @wheres, "$qdbf < $qopn"
            } elsif ($op eq '=~')   { $filtered = 0 # not supported
            } elsif ($op eq '!~')   { $filtered = 0 # not supported
            } elsif ($op eq 'pos')  { $filtered = 0 # different substr funcs
            } elsif ($op eq '!pos') { $filtered = 0 # different substr funcs
            } elsif ($op eq 'call') { $filtered = 0 # not supported
            } else {
                die "BUG: Unknown op $op";
            }
        }
        $filtered //= 1;

        my $sorted;
        my @orders;
        if ($query->{random}) {
            push @orders, "RANDOM()";
        } elsif (@{$query->{sorts}}) {
            for my $s (@{$query->{sorts}}) {
                my ($f, $op, $desc) = @$s;
                push @orders, $qi->($fspecs->{$f}{db_field} // $f).
                    ($desc == -1 ? " DESC" : "");
            }
        }
        $sorted //= 1;

        my $paged;
        my $limit = "";
        my ($ql, $qs) = ($query->{result_limit}, $query->{result_start}-1);
        if (defined($ql) || $qs > 0) {
            $limit = join(
                "",
                "LIMIT ".($ql // ($db eq 'Pg' ? "ALL":"999999999")),
                ($qs > 1 ? ($db eq 'mysql' ? ",$qs" : " OFFSET $qs") : "")
            );
        }
        $paged //= 1;

        my $sql = join(
            "",
            "SELECT ",
            join(",", map {$qi->($fspecs->{$_}{db_field}//$_)." AS ".$qi->($_)}
                     @{$query->{requested_fields}}).
                         " FROM ".$qi->($table_name),
            (@wheres ? " WHERE ".join(" AND ", @wheres) : ""),
            (@orders ? " ORDER BY ".join(",", @orders) : ""),
            $limit,
        );
        $log->tracef("$label SQL=%s", $sql);

        my $sth = $dbh->prepare($sql);
        $sth->execute or die "Can't query: ".$sth->errstr;
        my @r;
        while (my $row = $sth->fetchrow_hashref) { push @r, $row }

        {data=>\@r, paged=>$paged, filtered=>$filtered, sorted=>$sorted,
             fields_selected=>0, # XXX i'm lazy to handle detail=0
         };
    };

    @_ = (%args, table_data => $table_data);
    goto &gen_read_table_func;
}

1;
# ABSTRACT: Generate function (and its Rinci metadata) to access DBI table data


__END__
=pod

=head1 NAME

Perinci::Sub::Gen::AccessTable::DBI - Generate function (and its Rinci metadata) to access DBI table data

=head1 VERSION

version 0.04

=head1 SYNOPSIS

Your database table C<countries>:

 | id | eng_name                 | ind_name        |
 |----+--------------------------+-----------------|
 | cn | China                    | Cina            |
 | id | Indonesia                | Indonesia       |
 | sg | Singapore                | Singapura       |
 | us | United States of America | Amerika Serikat |

In list_countries.pl:

 #!perl
 use strict;
 use warnings;
 use Perinci::CmdLine;
 use Perinci::Sub::Gen::AccessTable::DBI qw(gen_read_dbi_table_func);

 our %SPEC;

 my $res = gen_read_dbi_table_func(
     name        => 'list_countries',
     summary     => 'func summary',     # opt
     description => 'func description', # opt
     dbh         => ...,
     table_name  => 'countries',
     table_spec  => {
         summary => 'List of countries',
         fields => {
             id => {
                 schema => 'str*',
                 summary => 'ISO 2-letter code for the country',
                 index => 0,
                 sortable => 1,
             },
             eng_name => {
                 schema => 'str*',
                 summary => 'English name',
                 index => 1,
                 sortable => 1,
             },
             ind_name => {
                 schema => 'str*',
                 summary => 'Indonesian name',
                 index => 2,
                 sortable => 1,
             },
         },
         pk => 'id',
     },
 );
 die "Can't generate function: $res->[0] - $res->[1]" unless $res->[0] == 200;

 Perinci::CmdLine->new(url=>'/main/list_countries')->run;

Now you can do:

 # list all countries, by default only PK field is shown
 $ list_countries.pl --format=text-simple
 cn
 id
 sg
 us

 # show as json, randomize order
 $ list_countries.pl --format=json --random
 ["id","us","sg","cn"]

 # only list countries which contain 'Sin', show all fields (--detail)
 $ list_countries.pl --q=Sin --detail
 .----------------------------.
 | eng_name  | id | ind_name  |
 +-----------+----+-----------+
 | Singapore | sg | Singapura |
 '-----------+----+-----------+

 # show only certain fields, limit number of records, return in YAML format
 $ list_countries.pl --fields '[id, eng_name]' --result-limit 2 --format=yaml
 - 200
 - OK
 -
   - id: cn
     eng_name: China
   - id: id
     eng_name: Indonesia

=head1 DESCRIPTION

This module is just like L<Perinci::Sub::Gen::AccessTable>, except that table
data source is from DBI. gen_read_dbi_table_func() accept mostly the same
arguments as gen_read_table_func(), except: 'table_name' instead of
'table_data', and 'dbh'.

Supported databases: SQLite, MySQL, PostgreSQL.

Early versions tested on: SQLite.

=head1 CAVEATS

It is often not a good idea to expose your database schema directly as API.

=head1 TODO

=over 4

=item * Generate table_spec from database schema, if unspecified

=back

=head1 FAQ

=head1 SEE ALSO

L<Perinci::Sub::Gen::AccessTable>

=head1 DESCRIPTION


This module has L<Rinci> metadata.

=head1 FUNCTIONS


None are exported by default, but they are exportable.

=head2 gen_read_dbi_table_func(%args) -> [status, msg, result, meta]

Generate function (and its metadata) to read DBI table.

The generated function acts like a simple single table SQL SELECT query,
featuring filtering, ordering, and paging, but using arguments as the 'query
language'. The generated function is suitable for exposing a table data from an
API function. Please see Perinci::Sub::Gen::AccessTable's documentation for more
details on what arguments the generated function will accept.

Arguments ('*' denotes required arguments):

=over 4

=item * B<case_insensitive_search> => I<bool> (default: 1)

Decide whether generated function will perform case-insensitive search.

=item * B<custom_filters> => I<hash>

Supply custom filters.

A hash of filter name and definitions. Filter name will be used as generated
function's argument and must not clash with other arguments. Filter definition
is a hash containing these keys: I<meta> (hash, argument metadata), I<code>,
I<fields> (array, list of table fields related to this field).

Code will be called for each record to be filtered and will be supplied ($r, $v,
$opts) where $v is the filter value (from the function argument) and $r the
hashref record value. $opts is currently empty. Code should return true if
record satisfies the filter.

=item * B<custom_search> => I<code>

Supply custom searching for generated function.

Code will be supplied ($r, $q, $opts) where $r is the record (hashref), $q is
the search term (from the function argument 'q'), and $opts is {ci=>0|1}. Code
should return true if record matches search term.

=item * B<dbh> => I<obj>

DBI database handle.

=item * B<default_arg_values> => I<hash>

Specify defaults for generated function's arguments.

Can be used to supply default filters, e.g.

    # limit years for credit card expiration date
    { "year.min" => $curyear, "year.max" => $curyear+10, }

=item * B<default_detail> => I<bool>

Supply default 'detail' value for function arg spec.

=item * B<default_fields> => I<str>

Supply default 'fields' value for function arg spec.

=item * B<default_random> => I<bool>

Supply default 'random' value in generated function's metadata.

=item * B<default_result_limit> => I<int>

Supply default 'result_limit' value in generated function's metadata.

=item * B<default_sort> => I<str>

Supply default 'sort' value in generated function's metadata.

=item * B<default_with_field_names> => I<bool>

Supply default 'with_field_names' value in generated function's metadata.

=item * B<description> => I<str>

Generated function's description.

=item * B<enable_search> => I<bool> (default: 1)

Decide whether generated function will support searching (argument q).

=item * B<install> => I<bool> (default: 1)

Whether to install generated function (and metadata).

By default, generated function will be installed to the specified (or caller's)
package, as well as its generated metadata into %SPEC. Set this argument to
false to skip installing.

=item * B<langs> => I<array> (default: ["en_US"])

Choose language for function metadata.

This function can generate metadata containing text from one or more languages.
For example if you set 'langs' to ['enI<US', 'id>ID'] then the generated function
metadata might look something like this:

    {
        v => 1.1,
        args => {
            random => {
                summary => 'Random order of results', # English
                "summary.alt.lang.id_ID" => "Acak urutan hasil", # Indonesian
                ...
            },
            ...
        },
        ...
    }

=item * B<name>* => I<str>

Generated function's name, e.g. `myfunc`.

=item * B<package> => I<str>

Generated function's package, e.g. `My::Package`.

This is needed mostly for installing the function. You usually don't need to
supply this if you set C<install> to false.

If not specified, caller's package will be used by default.

=item * B<summary> => I<str>

Generated function's summary.

=item * B<table_name>* => I<str>

DBI table name.

=item * B<table_spec>* => I<hash>

Table specification.

Just like Perinci::Sub::Gen::AccessTable's tableI<spec, except that each field
specification can have a key called C<db_field> to specify the database field (if
different). Currently this is required. Future version will be able to generate
table>spec from table schema if table_spec is not specified.

=item * B<word_search> => I<bool> (default: 0)

Decide whether generated function will perform word searching instead of string searching.

For example, if search term is 'pine' and field value is 'green pineapple',
search will match if wordI<search=false, but won't match under word>search.

This will not have effect under 'custom_search'.

=back

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

