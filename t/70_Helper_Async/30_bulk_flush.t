use Test::More;
use Test::Deep;
use strict;
use warnings;
use lib 't/lib';
use AE;
use Promises qw(deferred);
use Elasticsearch::Async::Bulk;

my $es = do "es_async.pl";

wait_for($es->indices->delete( index => '_all' ));

test_flush(
    "max count",    #
    { max_count => 3 },    #
    1, 2, 0, 1, 2, 0, 1, 2, 0, 1
);

test_flush(
    "max size",            #
    { max_size => 95 },    #
    1, 2, 3, 0, 1, 2, 3, 0, 1, 2
);

test_flush(
    "max size > max_count",
    { max_size => 95, max_count => 3 },
    1, 2, 0, 1, 2, 0, 1, 2, 0, 1
);

test_flush(
    "max size < max_count",
    { max_size => 95, max_count => 5 },
    1, 2, 3, 0, 1, 2, 3, 0, 1, 2
);

test_flush(
    "max size = 0, max_count",
    { max_size => 0, max_count => 5 },
    1, 2, 3, 4, 0, 1, 2, 3, 4, 0
);

test_flush(
    "max count = 0, max_size",
    { max_size => 95, max_count => 0 },
    1, 2, 3, 0, 1, 2, 3, 0, 1, 2
);

test_flush(
    "max count = 0, max_size = 0",
    { max_size => 0, max_count => 0 },
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10
);

done_testing;

wait_for($es->indices->delete( index => 'test' ));

#===================================
sub test_flush {
#===================================
    my $title  = shift;
    my $params = shift;
    my $b      = Elasticsearch::Async::Bulk->new(
        %$params,
        index => 'test',
        type  => 'test',
        es    => $es
    );

    my @seq = @_;
    my $cv  = AE::cv;

    my $i = 10;
    my $loop;

    my $d = deferred;
    $loop = sub {
        if ( $i == 20 ) {
            return $b->flush->then( sub { $d->resolve } );
        }
        $b->index( { id => $i, source => {} } )->then(
            sub {
                is $b->_buffer_count, shift @seq, "$title - " . ( $i - 9 );
                $i++;
                $loop->();
            }
        );
    };

    $es->indices->delete( index => 'test', ignore => 404 )
        ->then( sub { $es->indices->create( index => 'test' ) } )
        ->then( sub { $es->cluster->health( wait_for_status => 'yellow' ) } )
        ->then($loop);

    $d->promise->then(
        sub {
            is $b->_buffer_count, 0, "$title - final flush";
            $es->indices->refresh;
        }
        )->then(
        sub {
            $es->count;
        }
        )->then(
        sub {
            is shift()->{count}, 10, "$title - all docs indexed";
        }
        )->then(
        sub {
            $cv->send;
        }
        )->catch( sub { $cv->croak(@_) } );
    $cv->recv;
}

#===================================
sub wait_for {
#===================================
    my $promise = shift;
    my $cv      = AE::cv;
    $promise->done( $cv, sub { $cv->croak } );
    $cv->recv;
}
