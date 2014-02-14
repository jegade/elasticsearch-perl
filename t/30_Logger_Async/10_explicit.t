use Test::More;
use Elasticsearch::Async;
use File::Temp;
my $file = File::Temp->new;

# default

isa_ok my $l = Elasticsearch::Async->new->logger,
    'Elasticsearch::Logger::LogAny',
    'Default Logger';

is $l->log_as,           'elasticsearch.event',     'Log as';
is $l->trace_as,         'elasticsearch.trace',     'Trace as';
isa_ok $l->log_handle,   'Log::Any::Adapter::Null', 'Default - Log to NULL';
isa_ok $l->trace_handle, 'Log::Any::Adapter::Null', 'Default - Trace to NULL';

# stdout/stderr

isa_ok $l
    = Elasticsearch::Async->new( log_to => 'Stderr', trace_to => 'Stdout' )
    ->logger,
    'Elasticsearch::Logger::LogAny',
    'Std Logger';

isa_ok $l->log_handle,   'Log::Any::Adapter::Stderr', 'Std - Log to Stderr';
isa_ok $l->trace_handle, 'Log::Any::Adapter::Stdout', 'Std - Trace to Stdout';

# file

isa_ok $l = Elasticsearch::Async->new(
    log_to   => [ 'File', $file->filename ],
    trace_to => [ 'File', $file->filename ]
    )->logger, 'Elasticsearch::Logger::LogAny',
    'File Logger';

isa_ok $l->log_handle,   'Log::Any::Adapter::File', 'File - Log to file';
isa_ok $l->trace_handle, 'Log::Any::Adapter::File', 'File - Trace to file';

done_testing;
