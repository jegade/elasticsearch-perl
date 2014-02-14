use Test::More;
use Test::Exception;
use Elasticsearch::Async;
use lib 't/lib';
use MockAsyncCxn qw(mock_sniff_client);

## Sniff when bad node timesout causing good node to timeout too

my $t = mock_sniff_client(
    { nodes => [ 'one', 'two' ] },

    { node => 1, sniff => [ 'one', 'two' ] },
    { node => 2, sniff => [ 'one', 'two' ] },
    { node => 3, code => 200, content => 1 },
    { node => 4, code => 509, error   => 'Timeout' },

    # throws Timeout

    { node => 3, sniff => ['one'] },
    { node => 4, sniff => ['one'] },
    { node => 5, code  => 509, error => 'Timeout' },

    # throws Timeout

    { node => 5, sniff => ['one'] },
    { node => 6, code  => 200, content => 1 },

    # force sniff
    { node => 6, sniff => [ 'one', 'two' ] },
    { node => 7, code => 200, content => 1 },
    { node => 8, code => 200, content => 1 },
);

ok $t->perform_sync_request()
    && !eval { $t->perform_sync_request }
    && $@ =~ /Timeout/
    && !eval { $t->perform_sync_request }
    && $@ =~ /Timeout/
    && $t->perform_sync_request
    && $t->cxn_pool->schedule_check
    && $t->perform_sync_request
    && $t->perform_sync_request,
    'Sniff after both nodes timeout';

done_testing;
