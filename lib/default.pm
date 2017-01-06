package default;
use Dancer2 ':syntax';
use Template;
use DBI;
use DBD::mysql;
use MIME::Base64;
use JSON;
use JSON::Parse 'parse_json';

set template => 'template_toolkit';
set layout => undef;
set views => File::Spec->rel2abs('./views');

sub get_connection{
  my $service_name=uc $ENV{'DATABASE_SERVICE_NAME'};
  my $db_host=$ENV{"${service_name}_SERVICE_HOST"};
  my $db_port=$ENV{"${service_name}_SERVICE_PORT"};
  my $dbh=DBI->connect("DBI:mysql:database=$ENV{'MYSQL_DATABASE'};host=$db_host;port=$db_port",$ENV{'MYSQL_USER'},$ENV{'MYSQL_PASSWORD'}) or return 0;
  return $dbh;
}

sub init_db{

  my $dbh = $_[0];
  eval{ $dbh->do("DROP TABLE view_counter") };

  $dbh->do("CREATE TABLE view_counter (count INTEGER)");
  $dbh->do("INSERT INTO view_counter (count) VALUES (0)");
};

get '/' => sub {

    my $hasDB=1;
    my $dbh = get_connection() or $hasDB=0;
    my @data;
    $data[0]="No DB connection available";
    if ($hasDB==1) {
 		$dbh->prepare("SELECT * FROM view_counter")->execute() or init_db($dbh);

        my $sth = $dbh->prepare("UPDATE view_counter SET count = count + 1");
        $sth->execute();

        $sth = $dbh->prepare("SELECT * FROM view_counter");
        $sth->execute();
        @data = $sth->fetchrow_array();
        $sth->finish();
    }
    template default => {hasDB => $hasDB, data => $data[0]};
};

get '/health' => sub {
  my $dbh  = get_connection();
  my $ping = $dbh->ping();

  if ($ping and $ping == 0) {
    # This is the 'true but zero' case, meaning that ping() is not implemented for this DB type.
    # See: http://search.cpan.org/~timb/DBI-1.636/DBI.pm#ping
    return "WARNING: Database health uncertain; this database type does not support ping checks.";
  }
  elsif (not $ping) {
    status 'error';
    return "ERROR: Database did not respond to ping.";
  }
  return "SUCCESS: Database connection appears healthy.";
};


sub local_decode_jwt
{
	( my $jwt64 ) = @_;

	my @temp = split  /\./, $jwt64;

	my $jwt = decode_base64( $temp[1] );
	
	return parse_json($jwt);
}

get '/echo' => sub {
	my ($entry_id) = splat;
	my $httprequest = request;
	
	my $routeparm            = $httprequest->route_parameters;
	my $queryparm            = $httprequest->query_parameters;
	my $bodyparm             = $httprequest->body_parameters;

	my $request_method       = $httprequest->method;
	my $client_address       = $httprequest->address;
	my $client_base          = $httprequest->base->as_string;
	my $client_dispatch_path = $httprequest->dispatch_path;
	my $remote_address       = $httprequest->remote_address;

	my $httprequest_headers = $httprequest->headers;

    my %resulthash = ();
    my $result = \%resulthash; 

	$result->{method}               = defined $request_method       ? $request_method       : "";          
	$result->{client_address}       = defined $client_address       ? $client_address       : "";
	$result->{client_base}          = defined $client_base          ? $client_base          : "";
	$result->{client_dispatch_path} = defined $client_dispatch_path ? $client_dispatch_path : "";
	$result->{remote_address}       = defined $remote_address       ? $remote_address       : "";

	map { $result->{routeparams}->{$_} = $routeparm->{$_};           } keys %$routeparm;

	map { $result->{queryparams}->{$_} = $queryparm->{$_};           } keys %$queryparm;

	map { $result->{bodyparams}->{$_}  = $bodyparm->{$_};            } keys %$bodyparm;

	map { $result->{headers}->{$_}     = $httprequest_headers->{$_}; } keys %$httprequest_headers;

	if ( defined $entry_id )
	{
		$result->{route} = [];
		push @{ $result->{route} }, @$entry_id;
	}

	if ( exists $httprequest_headers->{'glue-id'} )
	{
		my $jwt = local_decode_jwt( $httprequest_headers->{'glue-id'} );
		$result->{JWT} = $jwt;
	}

    if ( exists $httprequest_headers->{'accept'} 
       && $httprequest_headers->{'accept'} =~ /application\/json/ )
    {
        set content_type => 'application/json';
        content_type 'json';
        set serializer => 'JSON'; 
    }
    else
    {
        set content_type => 'text/plain';
        my $json = JSON->new->allow_nonref;
        $result = $json->pretty->encode( \%resulthash );
    }

	return $result;
};

true;
