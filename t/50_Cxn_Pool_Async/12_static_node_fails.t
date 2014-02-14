use Test::More;
use Test::Exception;
use Elasticsearch::Async;
use lib 't/lib';
use MockAsyncCxn qw(mock_static_client);

## One node fails with a Cxn error, then rejoins

my $t = mock_static_client(
    { nodes => [ 'one', 'two' ] },

    { node => 1, ping => 1 },
    { node => 1, code => 200, content => 1 },
    { node => 2, ping => 1 },
    { node => 2, code => 200, content => 1 },
    { node => 1, code => 509, error => 'Cxn' },
    { node => 2, ping => 1 },
    { node => 2, code => 200, content => 1 },
    { node => 2, code => 200, content => 1 },

    # force ping on missing node
    { node => 1, ping => 1 },
    { node => 1, code => 200, content => 1 },
    { node => 2, code => 200, content => 1 },
    { node => 1, code => 200, content => 1 },
);

ok $t->perform_sync_request
    && $t->perform_sync_request
    && $t->perform_sync_request
    && $t->perform_sync_request,
    'One node throws Cxn';

# force ping on missing node
$t->cxn_pool->cxns->[0]->next_ping(-1);

ok $t->perform_sync_request && $t->perform_sync_request && $t->perform_sync_request,
    'Failed node recovers';

done_testing;

