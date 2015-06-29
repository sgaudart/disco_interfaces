#!/usr/bin/perl
#======================================================================
# Auteur : sebastien.gaudart@orange.com
# Date   : 06/07/2014
# But    : ce script demande sur quels équipements il faut découvrir 
#          les interfaces UP. Il effectue la découverte et vous demande
#          quelles interfaces il faut créer dans Centreon (via CLAPI).
#
# INPUT : 
#			the name of the config file
# OUTPUT :
#			one CLAPI file (CLAPI.sh) => create the interfaces inside Centreon
#
#======================================================================
#   Date      Version     Numero      Auteur       Commentaires
# 07/07/14    15                      SGA          initial code
# 09/07/14    16                      SGA          use input file with hostname
# 10/07/14    17                      SGA          only scan operstatus=up interface
# 23/07/14    18                      SGA          add python program for the selection
# 24/07/14    19                      SGA          get the information about the group's host
# 25/07/14    20                      SGA          add the ifAlias information (interface)
# 01/08/14    21                      SGA          create CLAPI file
# 01/08/14    22                      SGA          add ifDescr interrogation
# 05/08/14    23                      SGA          update the python pgr
# 01/09/14    24                      SGA          use config file
# 13/10/14    25                      SGA          enhancement with %clapidata
#======================================================================

use strict;
use warnings;

my $ligne = 0;
my $ifOperStatus_oid = "1.3.6.1.2.1.2.2.1.8";
my $ifDescr_oid      = "1.3.6.1.2.1.2.2.1.2";
my $ifAlias_oid      = "1.3.6.1.2.1.31.1.1.1.18";
my $ifSpeed_oid	  	 = "1.3.6.1.2.1.2.2.1.5";
my $ifName_oid       = "1.3.6.1.2.1.31.1.1.1.1";
my $hostdir = "/usr/share/centreon/filesGeneration/nagiosCFG"; # repertoire de la conf nagios des differents pollers
my $hostfile; # fichier nagios hosts.cfg
my @liste;
my $file;
my $modifdate;

my $HOSTCSV = "HOSTS.txt"; # INPUT : hosts file
my $CSVFILE2 = "INTERFACES.txt"; # OUTPUT : interfaces file
my $CLAPIFILE = "CLAPI.sh";
my $CFGFILE = "disco_interfaces.cfg";

my $line;
my $hostname;
my $pollername;
my $address;
my $community;
my $snmpver;
my $groupname;
my %hostdata;
our %ifdata; # $ifdata{$hostname}{$index}{ifName|ifAlias|ifOperStatus}
our %ifIndex; # use to translate from the ifName to the ifIndex
my $command;
my %PollerName2PollerIp;
my %clapidata; # hash table for CLAPI utilization

###############################################
# INITIALISATION ET LECTURE FICHIERS DE CONFIG
###############################################

$clapidata{"user"}="centreonadmin"; # login for CLAPI
$clapidata{"password"}="my_password_here"; # password for CLAPI
$clapidata{"path"}="/usr/share/centreon/www/modules/centreon-clapi/core/centreon"; # path to the CLAPI bin file

open (CFGFILE, "$CFGFILE") or die "Can't open $CFGFILE\n" ; # reading
while (<CFGFILE>)
{
	$line=$_;
	chomp($line);
	
	if ($line =~ /^clapi_(.*)=(.*)$/)
	{
		$clapidata{$1}=$2;
		#print "DEBUG : clapidata{$1}=$clapidata{$1}\n";
	}
	
	if ($line =~ /^(.*)=([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})$/) # regex for ip address => poller management
	{
		$PollerName2PollerIp{$1}=$2;
		#print "DEBUG : PollerName2PollerIp{$1}=$PollerName2PollerIp{$1}\n";
	}
	
	
}
close CFGFILE;


###############################################
# ANALYSE DES FICHERS HOSTS => remplissage $hostdata{}{}
###############################################
opendir DIR, $hostdir or die "impossible d'ouvrir le repertoire $hostdir en argument";
@liste = readdir DIR;
closedir DIR;
foreach $file (@liste)
{	
	if ($file eq ".") { next; } # exception for the local directory
	if ($file eq "..") { next; } # exception for the directory ".."
	
	print "analyse du fichier $hostdir/$file/hosts.cfg";
	# recherche du poller
	open (NDOFILE, "$hostdir/$file/ndomod.cfg") or die "Can't open $hostdir/$file/hosts.cfg\n" ; # reading
	while (<NDOFILE>)
	{
		$line=$_;
		if ($line =~ /^instance_name=(.*)$/)
		{
			$pollername=$1;
		}
	}
	# detection du poller fini
	print " [$pollername]\n";
	
	if ($pollername eq "noc-sv-testpol21") { next; } # exception
	
	# PROCESS the file hosts.cfg
	open (HOSTFILE, "$hostdir/$file/hosts.cfg") or die "Can't open $hostdir/$file/hosts.cfg\n" ; # reading
	while (<HOSTFILE>)
	{
		$line=$_;
		$ligne++;
		
		if ($line =~ /^.*host_name(.*)$/)
		{
			$hostname = $1;
			$hostname =~ s/^\s+//; # space delete
		}
		
		if ($line =~ /^.*address(.*)$/)
		{
			$address = $1;
			$address =~ s/^\s+//; # space delete
		}
		
		if ($line =~ /^.*SNMPCOMMUNITY(.*)$/)
		{
			$community = $1;
			$community =~ s/^\s+//; # space delete
		}
		
		if ($line =~ /^.*SNMPVERSION(.*)$/)
		{
			#print "$line\n" if $debug;
			$snmpver = $1;
			$snmpver =~ s/^\s+//; # space delete
			#if ($snmpver eq "2c") { $snmpver = 2; }
		}
		
		if ($line =~ /^.*hostgroups(.*)$/)
		{
			$groupname = $1;
			$groupname =~ s/^\s+//; # space delete
		}
		
		if ($line  eq "}\n")
		{
			# fin d'un bloc : traitement des infos du host
			
			$hostdata{$hostname}{ip}=$address;
			$hostdata{$hostname}{community}=$community;
			$hostdata{$hostname}{snmpversion}=$snmpver;
			$hostdata{$hostname}{poller}=$pollername;
			$hostdata{$hostname}{group}=$groupname;
			
			#print "$hostname;$address;$community;$snmpver\n";
		}
	}

	close HOSTFILE;

}

system "rm HOSTS.txt HOSTS.txt.selection INTERFACES.txt INTERFACES.txt.selection CLAPI.sh 2>/dev/null"; # cleaning file

###############################################
# CREATION DU FICHIER INPUT (hostname)
###############################################

# creation input file + script de selection

open (HOSTFD, ">$HOSTCSV") or die "Can't open $HOSTCSV\n" ; # writing
foreach my $key (sort keys %hostdata)
{
	print HOSTFD "$key\n" ;	
}
close HOSTFD;

system "python pyselection.py $HOSTCSV"; # visualisation
system "reset"; # pour retrouver un term normal

###############################################
# LECTURE DU FICHIER INPUT (hostname) et DECOUVERTE
###############################################

open (INPUTHOST, "$HOSTCSV.selection") or die "Can't open $HOSTCSV.selection\n" ; # reading
while (<INPUTHOST>)
{
	$line=$_;
	chomp($line);
	&disco_interface_by_hostname("$line");
}
close INPUTHOST;

system "python pyselection.py $CSVFILE2"; # visualisation des interfaces
system "reset"; # pour retrouver un term normal
print "Please check and execute CLAPI.sh to create the selected interfaces\n";

###############################################
# CREATION DU FICHIER CLAPI (creation service)
###############################################

open (INPUTINTERFACES, "$CSVFILE2.selection") or die "Can't open $CSVFILE2.selection\n" ; # reading
open (CLAPI, ">$CLAPIFILE") or die "Can't open $CLAPIFILE\n" ; # writing
while (<INPUTINTERFACES>)
{
	$line=$_;
	chomp($line);
	
	# SWF-XXX-001-A07     Gi1/1 (SWI-AUB-001-A23)
	if ($line =~ /^(.*)\t(.*) \((.*)\)$/)
	{
		#/usr/share/centreon/www/modules/centreon-clapi/core/centreon -u USER -p PASSWORD -o SERVICE -a add -v "myhostname;Traffic Eth0 - WAN;check5_traffic"
		#/usr/share/centreon/www/modules/centreon-clapi/core/centreon -u USER -p PASSWORD -o SERVICE -a setmacro -v "myhostname;Traffic Eth0 - WAN;INTERFACE;-n -i ^eth0$"
		#if ($ifAlias =~ /$\"(.*)\"$/) { $ifAlias = $1; }
		if ($3 ne "") # we have ifAlias => we create : Traffic ifName - ifAlias
		{
			print CLAPI "$clapidata{path} -u $clapidata{user} -p $clapidata{password} -o SERVICE -a add -v \"$1;Traffic $2 - $3;check5_traffic\"\n";
			print CLAPI "$clapidata{path} -u $clapidata{user} -p $clapidata{password} -o SERVICE -a setmacro -v \"$1;Traffic $2 - $3;INTERFACE;-n -i $ifdata{$1}{$ifIndex{$1}{$2}}{ifDescr}\$\"\n\n";
		}
		else # no ifAlias => we create : Traffic ifName
		{
			print CLAPI "$clapidata{path} -u $clapidata{user} -p $clapidata{password} -o SERVICE -a add -v \"$1;Traffic $2;check5_traffic\"\n";
			print CLAPI "$clapidata{path} -u $clapidata{user} -p $clapidata{password} -o SERVICE -a setmacro -v \"$1;Traffic $2;INTERFACE;-n -i $ifdata{$1}{$ifIndex{$1}{$2}}{ifDescr}\$\"\n\n";
		}
	}
}
close INPUTINTERFACES;
close CLAPI;

# THIS IS THE END 

#########################################
# FONCTIONS
#########################################
sub disco_interface_by_hostname
{
	my(@args) = @_;
	my $hostname = $args[0];
	
	print "Discovering interfaces for $hostname";
	open (CSVOUT, ">>$CSVFILE2") or die "Can't open $CSVFILE2\n" ; # writting
	
	# ifName
	$command = "ssh $PollerName2PollerIp{$hostdata{$hostname}{poller}} \'snmpwalk -v 2c $hostdata{$hostname}{ip} -c $hostdata{$hostname}{community} ifName\' 2>/dev/null |";
	
	open (COMMAND, $command) or die "Could not use $command, $!";
	while (<COMMAND>)
	{
		$line=$_;
		#ifName.9 = STRING: Fa5
		if ($line =~ /^ifName\.(.*) = STRING: (.*)$/)
		{
			$ifdata{$hostname}{$1}{ifName}=$2;
			$ifIndex{$hostname}{$2}=$1; # ex : $ifIndex{MY_HOSTNAME}{eth0}=1
		}
	}
	close COMMAND;
	print ".";
	
	# ifDescr
	$command = "ssh $PollerName2PollerIp{$hostdata{$hostname}{poller}} \'snmpwalk -v 2c $hostdata{$hostname}{ip} -c $hostdata{$hostname}{community} ifDescr\' 2>/dev/null |";
	
	open (COMMAND, $command) or die "Could not use $command, $!";
	while (<COMMAND>)
	{
		$line=$_;
		#ifDescr.9 = STRING: FastEthernet5
		if ($line =~ /^ifDescr\.(.*) = STRING: (.*)$/)
		{
			$ifdata{$hostname}{$1}{ifDescr}=$2;
		}
	}
	close COMMAND;
	print ".";
	
	# ifAlias
	$command = "ssh $PollerName2PollerIp{$hostdata{$hostname}{poller}} \'snmpwalk -v 2c $hostdata{$hostname}{ip} -c $hostdata{$hostname}{community} ifAlias\' 2>/dev/null |";
	
	open (COMMAND, $command) or die "Could not use $command, $!";
	while (<COMMAND>)
	{
		$line=$_;
		if ($line =~ /^ifAlias\.(.*) = STRING: (.*)$/)
		{
			$ifdata{$hostname}{$1}{ifAlias}=$2;
			#print "DEBUG : ifdata{$hostname}{$1}{ifAlias}=$ifdata{$hostname}{$1}{ifAlias}\n";
		}
	}
	close COMMAND;
	print ".";
	
	# ifOperStatus
	$command = "ssh $PollerName2PollerIp{$hostdata{$hostname}{poller}} \'snmpwalk -v 2c $hostdata{$hostname}{ip} -c $hostdata{$hostname}{community} ifOperStatus\' 2>/dev/null |";
	
	open (COMMAND, $command) or die "Could not use $command, $!";
	while (<COMMAND>)
	{
		$line=$_;
		#ifOperStatus.4 = INTEGER: down(2)
		if ($line =~ /^ifOperStatus\.(.*) = INTEGER: .*\((.)\)$/)
		{
			$ifdata{$hostname}{$1}{ifOperStatus}=$2;
			if ($ifdata{$hostname}{$1}{ifOperStatus} eq 1)
			{
				print CSVOUT "$hostname\t$ifdata{$hostname}{$1}{ifName} ($ifdata{$hostname}{$1}{ifAlias})\n";
			}
			#print "DEBUG : ifdata{$hostname}{$1}{ifOperStatus}=$ifdata{$hostname}{$1}{ifOperStatus}\n";
		}
	}
	close COMMAND;
	close CSVOUT;
	print ".\n";
}
