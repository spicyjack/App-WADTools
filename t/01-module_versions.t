#!perl

use Test::More tests => 3;
use Test::File;

diag( qq(Testing module versions for App::WADTools;\nPerl $], $^X) );

eval "use Test::ConsistentVersion";
plan skip_all => "Test::ConsistentVersion required "
    . "for checking module versions" if $@;

Test::ConsistentVersion::check_consistent_versions(
    # We don't use the version in the README
    no_readme => 1,
    # We don't maintain a ChangeLog file, we use NEWS instead
    no_changelog => 1,
    # Test::Pod::Content lookѕ for VERSION blocks in POD
    no_pod => 1,
);
