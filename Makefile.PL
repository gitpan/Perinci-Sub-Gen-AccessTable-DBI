
use strict;
use warnings;

use 5.010001;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Generate function (and its Rinci metadata) to access DBI table data",
  "AUTHOR" => "Steven Haryanto <stevenharyanto\@gmail.com>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Perinci-Sub-Gen-AccessTable-DBI",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Perinci::Sub::Gen::AccessTable::DBI",
  "PREREQ_PM" => {
    "DBI" => 0,
    "Data::Clone" => 0,
    "Data::Sah" => 0,
    "Locale::TextDomain::UTF8" => 0,
    "Log::Any" => 0,
    "Perinci::Sub::Gen::AccessTable" => "0.18",
    "Rinci" => "v1.1.13"
  },
  "TEST_REQUIRES" => {
    "DBD::SQLite" => 0,
    "File::Spec" => 0,
    "IO::Handle" => 0,
    "IPC::Open3" => 0,
    "Test::More" => "0.96"
  },
  "VERSION" => "0.09",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "DBD::SQLite" => 0,
  "DBI" => 0,
  "Data::Clone" => 0,
  "Data::Sah" => 0,
  "File::Spec" => 0,
  "IO::Handle" => 0,
  "IPC::Open3" => 0,
  "Locale::TextDomain::UTF8" => 0,
  "Log::Any" => 0,
  "Perinci::Sub::Gen::AccessTable" => "0.18",
  "Rinci" => "v1.1.13",
  "Test::More" => "0.96"
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



