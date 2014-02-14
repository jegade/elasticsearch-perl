use Test::More;
use Test::Exception;
use Elasticsearch::Async;
use lib 't/lib';
use MockAsyncCxn qw(mock_static_client);

## One node fails with a Timeout error, then rejoins

my $t = mock_static_client(
    { nodes => [ 'one', 'two' ] },

    { node => 1, ping => 1 },
    { node => 1, code => 200, content => 1 },
    { node => 2, ping => 1 },
    { node => 2, code => 200, content => 1 },
    { node => 1, code => 509, error => 'Timeout' },
    { node => 2, ping => 1 },
    { node => 2, code => 200, content => 1 },
    { node => 1, ping => 1 },
    { node => 1, code => 200, content => 1 },

);

ok $t->perform_sync_request
    && $t->perform_sync_request
    && !eval { $t->perform_sync_request }
    && $@ =~ /Timeout/
    && $t->perform_sync_request,
    'One node throws Timeout then recovers';

done_testing;

