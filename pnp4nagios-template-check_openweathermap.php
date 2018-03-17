<?php
/*
  (c) 2013,2017 by Frederic Krueger / fkrueger-dev-checkopenweathermap@holics.at
 
  Licensed under the Apache License, Version 2.0
  There is no warranty of any kind, explicit or implied, for anything this software does or does not do.

  Updates for this piece of software could be available under the following URL:
    GIT:   https://github.com/fkrueger-2/check_openweathermap
    Home:  http://dev.techno.holics.at/check_openweathermap/
   
  Requires: pnp4nagios

*/

# Template to combine all selected data sets (of varying usefulness) provided by the plugin into one single graph

$opt[1] = " --title \"check_openweathermap graph for " . $this->MACRO['DISP_HOSTNAME'] . ' / ' . $this->MACRO['DISP_SERVICEDESC'] . "\" ";
$def[1] = "";

foreach ($this->DS as $key => $val)
{
	$def[1] .= rrd::def     ("var$key", $val['RRDFILE'], $val['DS'], "AVERAGE");
	$def[1] .= rrd::line2   ("var$key", rrd::color($key, 80) , rrd::cut($val['NAME'],16) );
	$def[1] .= rrd::gprint  ("var$key", array("LAST","AVERAGE"), "%9.4lf %S".$val['UNIT']);
}
$def[1] .= rrd::comment("\\r");
$def[1] .= rrd::comment("check_openweathermap graph template\\r");
$def[1] .= rrd::comment("Command " . $val['TEMPLATE'] . "\\r");

?>
