use Test::More;
use Test::Exception;
use Elasticsearch;
use lib 't/lib';
use Elasticsearch::MockCxn;


## One node fails with a Timeout error and causes good node to timeout

my $t = mock_client(
    { nodes => [ 'one', 'two' ] },

    { node => 1, ping => 1 },
    { node => 1, code => 200, content => 1 },
    { node => 2, ping => 1 },
    { node => 2, code => 200, content => 1 },
    { node => 1, code => 500, error => 'Timeout' },
    { node => 2, ping => 1 },
    { node => 2, code => 500, error => 'Timeout' },
    { node => 1, ping => 0 },
    { node => 2, ping => 1 },
    { node => 2, code => 200, content => 1 },

);

ok $t->perform_request
    && $t->perform_request
    && !eval { $t->perform_request }
    && $@ =~ /Timeout/
    && !eval { $t->perform_request }
    && $@ =~ /Timeout/
    && $t->perform_request,
    'One node throws Timeout, causing Timeout on other node';


done_testing;

#===================================
sub mock_client {
#===================================
    my $params = shift;
    return Elasticsearch->new(
        cxn            => '+Elasticsearch::MockCxn',
        mock_responses => \@_,
        %$params,
    )->transport;
}
