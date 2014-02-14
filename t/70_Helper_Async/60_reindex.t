use Test::More;
use Test::Deep;
use Test::Exception;
use lib 't/lib';

use AE;
use strict;
use warnings;
use Elasticsearch::Async::Scroll;
use Elasticsearch::Async::Bulk;

our ( $es, $es_version );

BEGIN {
    $es = do "es_async.pl";
}

wait_for( $es->indices->delete( index => '_all', ignore => 404 )
        ->then( sub { $es->info } )
        ->then( sub { $es_version = shift()->{version}{number} } ) );

do "index_test_data.pl" or die $!;

my $b;

# Reindex to new index and new type
$b = Elasticsearch::Async::Bulk->new(
    es    => $es,
    index => 'test2',
    type  => 'test2'
);
wait_for( $b->reindex( source => { index => 'test' } )
        ->then( sub { $es->indices->refresh } ) );

is wait_for(
    $es->count(
        index => 'test2',
        type  => 'test2'
    )
    )->{count}, 100,
    'Reindexed to new index and type';

# Reindex to same index
$b = Elasticsearch::Async::Bulk->new( es => $es );
wait_for( $b->reindex( source => { index => 'test' } )
        ->then( sub { $es->indices->refresh } ) );

is wait_for(
    $es->count(
        index => 'test',
        type  => 'test'
    )
    )->{count}, 100,
    'Reindexed to same index';

is wait_for( $es->get( index => 'test', type => 'test', id => 1 ) )
    ->{_version}, 2,
    "Reindexed to same index - version updated";

# Reindex with transform
wait_for( $es->indices->delete( index => 'test2' ) );

$b = Elasticsearch::Async::Bulk->new( es => $es, index => 'test2' );
wait_for(
    $b->reindex(
        source    => { index => 'test' },
        transform => sub {
            my $doc = shift;
            return if $doc->{_source}{color} eq 'red';
            $doc->{_source}{transformed} = 1;
            return $doc;
        }
    )->then( sub { $es->indices->refresh } )
);

is wait_for(
    $es->count(
        index => 'test2',
        type  => 'test'
    )
    )->{count}, 50,
    'Transfrom - removed docs';

my $query = {
    bool => {
        must => [
            { term => { color       => 'green' } },
            { term => { transformed => 1 } }
        ]
    }
};
if ( $es_version !~ /^0.90/ ) {
    $query = { query => $query };
}

is wait_for(
    $es->count(
        index => 'test2',
        type  => 'test',
        body  => $query,
    )
    )->{count}, 50,
    'Transform - transformed docs';

# Reindex with sync Scroll
wait_for( $es->indices->delete( index => 'test2' ) );

$b = Elasticsearch::Async::Bulk->new( es => $es, index => 'test2' );
my $s;
{
    local $ENV{CXN};
    local $ENV{CXN_POOL};
    my $sync = do 'es_sync.pl';
    $s = $sync->scroll_helper( index => 'test' )
}

wait_for(
    $b->reindex(
        source    => $s,
        transform => sub {
            my $doc = shift;
            return if $doc->{_source}{color} eq 'red';
            $doc->{_source}{transformed} = 1;
            return $doc;
        }
    )->then( sub { $es->indices->refresh } )
);

is wait_for(
    $es->count(
        index => 'test2',
        type  => 'test'
    )
    )->{count}, 50,
    'Transform sync - removed docs';

is wait_for(
    $es->count(
        index => 'test2',
        type  => 'test',
        body  => $query,
    )
    )->{count}, 50,
    'Transfrom sync - transformed docs';

# Reindex with parent & routing
wait_for( $es->indices->delete( index => '_all', ignore => 404 ) );
for ( 'test', 'test2' ) {
    wait_for(
        $es->indices->create(
            index => $_,
            body =>
                { mappings => { test => { _parent => { type => 'foo' } } } }
        )
    );
}
wait_for( $es->cluster->health( wait_for_status => 'yellow' ) );

for ( 1 .. 5 ) {
    wait_for(
        $es->index(
            index        => 'test',
            type         => 'test',
            version_type => 'external',
            version      => $_,
            id           => $_,
            parent       => 1,
            routing      => 2,
            body         => { count => $_ },
        )
    );
}
wait_for( $es->indices->refresh );

$b = Elasticsearch::Async::Bulk->new( es => $es, index => 'test2' );
ok wait_for(
    $b->reindex(
        version_type => 'external',
        source       => {
            index   => 'test',
            version => 1,
            fields  => [ '_parent', '_routing', '_source' ]
        }
    )->then( sub { $es->indices->refresh } )
    ),
    "Advanced";

my $results = wait_for(
    $es->search(
        index   => 'test2',
        type    => 'test',
        sort    => 'count',
        fields  => [ '_parent', '_routing' ],
        version => 1,
    )
)->{hits}{hits};
is $results->[3]{fields}{_parent},  1, "Advanced - parent";
is $results->[3]{fields}{_routing}, 2, "Advanced - routing";
is $results->[3]{_version}, 4, "Advanced - version";

done_testing;

#===================================
sub wait_for {
#===================================
    my $promise = shift;
    my $cv      = AE::cv;
    $promise->done( $cv, sub { $cv->croak } );
    $cv->recv;
}
