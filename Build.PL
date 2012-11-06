
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "DBD::SQLite" => 0,
    "Module::Build" => "0.3601",
    "Test::More" => "0.96"
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Generate function (and its Rinci metadata) to access DBI table data",
  "dist_author" => [
    "Steven Haryanto <stevenharyanto\@gmail.com>"
  ],
  "dist_name" => "Perinci-Sub-Gen-AccessTable-DBI",
  "dist_version" => "0.06",
  "license" => "perl",
  "module_name" => "Perinci::Sub::Gen::AccessTable::DBI",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "DBI" => 0,
    "Data::Clone" => 0,
    "Data::Sah" => 0,
    "Locale::Maketext::Lexicon" => 0,
    "Locale::Maketext::Lexicon::Gettext" => 0,
    "Log::Any" => 0,
    "Moo" => 0,
    "Perinci::Sub::Gen::AccessTable" => "0.17",
    "Rinci" => "v1.1.13",
    "SHARYANTO::Role::I18NMany" => "0.17",
    "perl" => "5.010001"
  },
  "script_files" => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
