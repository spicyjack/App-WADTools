#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( q(App::WADTools) );
}

diag( qq(Testing App::WADTools $App::WADTools::VERSION, )
    . qq(Perl $], $^X) );
