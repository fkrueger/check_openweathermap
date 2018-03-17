#!/usr/bin/perl -w

# nagios plugin using openweathermap's JSON api
#
# (c) 2013-2017 by Frederic Krueger / fkrueger-dev-checkopenweathermap@holics.at
#
# Licensed under the Apache License, Version 2.0
# There is no warranty of any kind, explicit or implied, for anything this software does or does not do.
#
# Updates for this piece of software could be available under the following URL:
#   GIT:   https://github.com/fkrueger-2/check_openweathermap
#   Home:  http://dev.techno.holics.at/check_openweathermap/
#


## uses
use Data::Dumper;             # for debugging
use JSON qw( decode_json );
use LWP::UserAgent;

use lib "/usr/lib/nagios/plugins";
use lib "/usr/lib64/nagios/plugins";
use lib "/srv/nagios/libexec";
use utils qw (%ERRORS);


## globals
my $dflt_where = "London,uk";    # default

# sorry OWM, the api.openweathermap.org/data/2.5/ API did not return any data for most station_ids;
# also, the data structure on non-api openweathermap.org is much easier to implement (and has less infos) ;-)

my $locurl = "http://api.openweathermap.org/data/2.5/find?q=<LOCATION>&units=metric&mode=json";
my $idurl = "http://api.openweathermap.org/data/2.1/weather/station/<ID>?type=json";
my $apikeypart = "&APPID=<APIKEY>";

my ($PROG_NAME, $PROG_VERSION) = ("check_openweathermap", "0.0.4");

our $DEBUG = 0;			# set to 1 for debug output

my %opttranslation = (
  'loc' => {      # probably can be used as a general API 2.5 translation table
    '_BASE_' => "{'list'}[0]",
    'clouds' => 'clouds-all',
    'country' => 'sys-country',
    'humidity' => 'main-humidity',
    'humidity-current' => 'main-humidity',
    'id' => 'id',
    'latitude' => 'coord-lat',
    'longitude' => 'coord-lon',
    'name' => 'name',
    'pressure' => 'main-pressure',
    'pressure-current' => 'main-pressure',
    'temp' => 'main-temp',
    'temp-current' => 'main-temp',
    'temp-minimum' => 'main-temp_min',
    'temp-maximum' => 'main-temp_max',
    'unixdate' => 'dt',
    'weather' => 'weather-0-main',
    'weather-main' => 'weather-0-main',
    'weather-description' => 'weather-0-description',
    'weather-icon' => 'weather-0-icon',
    'weather-id' => 'weather-0-id',
    'wind' => 'wind-speed',
    'wind-current' => 'wind-speed',
    'wind-deg' => 'wind-deg',
    'wind-gust' => 'wind-gust',
    'wind-speed' => 'wind-speed',
  },
  'id' => {               # probably can be used as a general API 2.1 translation table
    '_BASE_' => '',
    'clouds' => 'clouds-all',
    'date' => 'date',
    'dewpoint' => 'calc-dewpoint',
    'dt' => 'dt',
    'humidex' => 'calc-humidex',
    'humidity' => 'main-humidity',
    'humidity-current' => 'main-humidity',
    'id' => 'id',
    'latitude' => 'coord-lat',
    'longitude' => 'coord-lon',
    'name' => 'name',
    'pressure' => 'main-pressure',
    'pressure-current' => 'main-pressure',
    'temp' => 'main-temp',
    'temp-current' => 'main-temp',
    'unixdate' => 'dt',
    'weather' => 'weather-0-name',
    'wind' => 'wind-speed',
    'wind-current' => 'wind-speed',
    'wind-deg' => 'wind-deg',
    'wind-gust' => 'wind-gust',
    'wind-speed' => 'wind-speed',
  }
);

## subs
sub usage
{
  my $msg = shift;
  print "\n";
  print "usage: $0 <locationstring> <wantedinfo> [api-key]\n";
  print "\n";
  print "    locationstring is usually 'townname,countrytld' (ie. Wuerzburg,de or London,uk),\n";
  print "    but can be id=<owm-id> as well.\n";
  print "\n";
  print "    wantedinfo is either 'all' or one of the following:\n";
  print "      sys-country,sys-sunrise,sys-sunset (in epoch time)\n";
  print "      weather-main (ie. 'Clouds'), weather-description (ie. 'Broken clouds'), clouds-all (ie. '68' percent)\n";
  print "      main-temp,main-humidity,main-pressure,main-temp_min,main-temp_max,wind-speed,wind-gust,wind-deg (just the stated)\n";
  print "      name (name of location), coord-lat (latitude of location), coord-lon (longitude of location), id (id of weatherstation)\n";
  print "\n";
  print "    perfdata is being created with all available data, all the time.\n";
  print "\n";
  print "\n";
  print "    if you are getting an error, you probably need a (supposedly free) API key.\n";
  print "    see here for more info: http://openweathermap.org/faq#error401\n\n";

  ## calling example
#  print "Example with nearly all parameters available (as of 2013-07-28) being used:\n";
#  print "nagios\@comp:/srv/nagios/libexec/contrib# ./check_openweathermap.pl Wuerzburg,de sys-sunrise,sys-sunset,main-pressure,main-temp,main-humidity,wind-gust,wind-speed,wind-deg,weather-main,coord-lat,coord-lon,clouds-all,id,name
#OK - sys-sunrise=1374983154, sys-sunset=1375038455, main-pressure=1012, main-temp=298.69, main-humidity=38, wind-gust=2.06, wind-speed=1.03, wind-deg=0, weather-main=Clouds, coord-lat=49.787781, coord-lon=9.93611, clouds-all=68, id=2805615, name=Wuerzburg | sys-sunrise=1374983154;;;; sys-sunset=1375038455;;;; main-pressure=1012;;;; main-temp=298.69;;;; main-humidity=38;;;; wind-gust=2.06;;;; wind-speed=1.03;;;; wind-deg=0;;;; coord-lat=49.787781;;;; coord-lon=9.93611;;;; clouds-all=68;;;; id=2805615;;;
#nagios\@comp:/srv/nagios/libexec/contrib
#";
#  print "\n\n";
  ## nagios setup info
  print "## NAGIOS COMMANDS SETUP\n";
  print 'define command{
  command_name  check_openweathermap
  command_line  $USER1$/contrib/check_openweathermap.pl $ARG1$ $ARG2$ $ARG3$ $ARG4$ $ARG5$ $ARG6$ $ARG7$
}

';
  print "## NAGIOS SERVICE SETUP\n";
  print "define service{
  name                     owm-service
  use                      local-service
  normal_check_interval    10
  retry_check_interval     5
  register  0
}
            
define service{
  use                    owm-service         ; or owm-service-pnp, if you have pnp4nagios integrated and use that templatename
  host_name              yourhost
  service_description    Weather myplace
  check_command          check_openweathermap!London,uk!name,temp-current,humidity-current,wind-current,clouds,pressure-current
}


For the pnp4nagios related files (check_command entry as well as the graph-template), check the archive you got this script in.

";

  ## licensing info
  print "$PROG_NAME v$PROG_VERSION is licensed under the Apache License, Version 2.0 .\n";
  print "There is no warranty of any kind, explicit or implied, for anything this software does or does not do.\n";
  print "\n";
  print "(c) 2013-2017 by Frederic Krueger / igetspam\@bigfoot.com\n";
  print "\n";

  if ((defined($msg)) and ($msg ne ""))
  {
    print "\nERROR: $msg\n\n";
  }

  exit($ERRORS{"UNKNOWN"});
} # end sub usage


sub dbgprint
{
  if ($DEBUG > 0)
  {
    print "@_";
  }
}


sub nagexit
{
  my ($nagstate, $msg, $perfdata, $debugout) = @_;
  $perfdata = ""  if (!defined($perfdata));
  $nagstate = "UNKNOWN" if ((!defined($nagstate)) or (!defined($ERRORS{uc($nagstate)})));
  $nagstate = uc($nagstate);
  $msg = $nagstate  if (!defined($msg));
  $debugout = ""  if (!defined($debugout));

  print "$msg" .($perfdata ne "" ? " | $perfdata" : "") ."\n";
  if ($debugout ne "") { print "$debugout\n"; }                 # add debug out, only used with errors

  exit ($ERRORS{$nagstate});
} # end sub nagexit



## args
if ((!defined($ARGV[0])) or (!defined($ARGV[1])))
{
  usage();
} # end if not enough arguments gotten

my $location   = $ARGV[0];
my $wantedinfo = $ARGV[1];
my $apikey     = "";
if (defined($ARGV[2])) { $apikey = $ARGV[2]; }
if ($apikey ne "")
{
  $apikey =~ s/[^a-fA-F0-9]//g;
  $apikeypart =~ s/<APIKEY>/$apikey/isg;
}

my $owmid = -1;
if ($location =~ /^id=(\d+)$/i)
{
  $owmid = $1;
}

my $opttype = "";
my $usedurl = "";
if ((defined($owmid)) and ($owmid >= 0))
{
  $opttype = "id";
  $usedurl = $idurl;
  $usedurl =~ s/<ID>/$owmid/isg;
} # end if use location as owmid
else
{
  $opttype = "loc";
  $usedurl = $locurl;
  $usedurl =~ s/<LOCATION>/$location/isg;
} # end if use location as city,country

if ((defined($apikey)) and ($apikey ne "")) { $usedurl .= $apikeypart; }


my $wiref;		# we declare it here for the debug lateron

# now the actual request:
if ($DEBUG <= 0)
{
  my $ua = LWP::UserAgent->new;
  $ua->env_proxy;

  my $response = $ua->get("$usedurl");

  if ($response->is_success)
  {
    $weatherinfo_json = $response->decoded_content;  # or whatever
  }
  elsif ($response->code != 200)
  {
    usage ("Problem getting weatherinfo for argument '$location':

    Used URL: $usedurl
    HTTP RC: " .$response->code. "
    HTTP status: " .$response->status_line. "
    Other content:
". $response->decoded_content. "
    " .("-"x105). "

Maybe you need to provide an API key (see here for more info: http://openweathermap.org/faq#error401 ).
Hopefully at some point we will get an API key for general plugin use. Until then, create an account at owm.org as you see fit.");
  }

  # now JSON-parse the data gotten (hopefully)
  eval { $wiref = decode_json($weatherinfo_json); };

}
else
{
  dbgprint (">>> Using debug data instead of actual request data...\n");
  $wiref = {
          'list' => [
                      {
                        'wind' => {
                                    'speed' => '4.1',
                                    'deg' => 50
                                  },
                        'clouds' => {
                                      'all' => 90
                                    },
                        'coord' => {
                                     'lon' => '182.551',
                                     'lat' => '189.773'
                                   },
                        'sys' => {
                                   'country' => 'ME'
                                 },
                        'dt' => 1486664400,
                        'id' => 2810716,
                        'name' => 'The Shire',
                        'snow' => undef,
                        'rain' => undef,
                        'weather' => [
                                       {
                                         'id' => 804,
                                         'main' => 'Clouds',
                                         'icon' => '04n',
                                         'description' => 'overcast clouds'
                                       }
                                     ],
                        'main' => {
                                    'temp_min' => -2,
                                    'temp' => '11.69',
                                    'humidity' => 74,
                                    'pressure' => 1022,
                                    'temp_max' => 20
                                  }
                      }
                    ],
          'count' => 1,
          'message' => 'accurate',
          'cod' => '200'
        };
}


# now check if the parsing worked.
if ( ($@) or ((!defined($wiref)) or (ref($wiref) ne "HASH")) )
{
  nagexit ("UNKNOWN", "UNKNOWN - Problem parsing returned JSON for location '$location'", "", "$@");
}


my $datastr = "";
my $perfdatastr = "";

if (($wantedinfo ne "") and (defined($opttranslation{$opttype})))
{
  if (($wantedinfo ne "all") and ($wantedinfo ne "*"))
  {
    my @wantedinfos = split /,/, $wantedinfo;
    my $val = ""; my $key = ""; my $hashpoint = ""; my $perfdataname = "";
    my $hpbase = $opttranslation{$opttype}{'_BASE_'};
    # XXX inp1key 'wind-speed' per user request
    foreach $inp1key (@wantedinfos)
    {
      dbgprint ("- inp1key '$inp1key'\n");
      $perfdataname = $inp1key;
      $hashpoint = $hpbase;  $val = "";
      if (defined($opttranslation{$opttype}{$inp1key}))
      {
        $inp1key = $opttranslation{$opttype}{$inp1key};
      }
  
      my @keywordinfos = split /-/, $inp1key;
      # XXX inp2key 'wind' and 'speed'
      foreach my $inp2key (@keywordinfos)
      {
        dbgprint ("-- inp2key '$inp2key'\n");
        if ($inp2key =~ /^\d+$/)
        {
          $inp2key = "[$inp2key]";    # get numbered list element
        }
        else
        {
          $inp2key = "{'$inp2key'}";
        }
  
        $hashpoint = "${hashpoint}$inp2key";
      } # end foreach keyword info part
      # XXX hashpoint '{'list'}[0]{'wind'}{'speed'}
      dbgprint ("--- hashpoint '$hashpoint'\n");

      eval "\$val = \${\$wiref}$hashpoint;";
      # XXX the following is used in a verbatim copy within the "all" part
      if ((defined($val)) and ($val ne ""))
      {
        # if is a temperature, subtract zero degree kelvin (-273.15)
        if (($opttype eq "id") and ($hashpoint =~ /'temp/)) { $val -= 273; }
        dbgprint ("=== hashpoint-val '$val'\n");
        $datastr .= "$perfdataname=$val, ";
        if ($val =~ /^[0-9\.\-]+$/) { $perfdatastr .= "$perfdataname=$val;;;; "; }   # add perfdata only if numeric data gotten
      }
    } # end foreach key to translate
  }

  else		# if keyword == all / '*'

  {
    foreach my $inp1key (sort keys %{${$wiref}{'list'}[0]})
    {
      dbgprint ("- inp1key '$inp1key'\n");
      my $infohashbase = ($inp1key eq "weather") ? ${$wiref}{'list'}[0]{$inp1key}[0] : ${$wiref}{'list'}[0]{$inp1key};
      foreach my $inp2key (sort keys %{$infohashbase})
      {
        dbgprint ("-- inp2key '$inp2key'\n");
        dbgprint ("=== hashpoint-val '" . ${$infohashbase}{$inp2key}. "'\n");
	# XXX the following is to make sure the snippet from above can be used exactly the same here.
	$hashpoint = "'$inp1key";
	$val = %{$infohashbase}{$inp2key};
        $perfdataname = "$inp1key-$inp2key";
	# XXX the following is a verbatim copy of the above part. i'm too lazy for now, until someone wants nicer parsing ;-)
        if ((defined($val)) and ($val ne ""))
        {
          # if is a temperature, subtract zero degree kelvin (-273.15)
          if (($opttype eq "id") and ($hashpoint =~ /'temp/)) { $val -= 273; }
          dbgprint ("=== hashpoint-val '$val'\n");
          $datastr .= "$perfdataname=$val, ";
          if ($val =~ /^[0-9\.\-]+$/) { $perfdatastr .= "$perfdataname=$val;;;; "; }   # add perfdata only if numeric data gotten
        }
      }
    }
  } # end if keyword == all / *

  if (length($datastr) > 0) { $datastr = substr($datastr, 0, length($datastr)-2); }
  if (length($perfdatastr) > 0) { $perfdatastr = substr($perfdatastr, 0, length($perfdatastr)-2); }
}

if ((length($datastr) > 0) and (length($perfdatastr) > 0))
{
  nagexit ("OK", "OK - $datastr", $perfdatastr, "");
}


# default exitcode:
my $wiref_ds = Dumper($wiref);
nagexit ("UNKNOWN", "UNKNOWN - Unknown error occured for location '$location' (url: $usedurl)", "", "Returned datastructure is:\n$wiref_ds");


