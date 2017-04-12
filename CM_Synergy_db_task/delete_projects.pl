# Created by Tommi Paananen 16.08.2006
#
# This script delete all prep or working state project which are stamped with spesific version id 
#
# Usage: perl delete_projects.pl <project_name> <owner> <version>
# Example: perl delete_projects.pl * topaanan *Aalto_1.25.028
#
# Note: project name can be, like *, or Aalto* or whatever...
# Note: use star mark * in the beginning of the version name, like *Aalto_1.25* 

use Cwd;
use strict;

my $search_word = shift;
my $owner = shift;
my $version = shift;
my $query_file = "query_results.txt";

unless ($search_word and $owner and $version)
	{
	print "\n\n";
	print "UASGE: \t perl deleting_projects.pl <project_name> <owner> <version>\n\n";
	print "For example: \t perl deleting_projects.pl maps* topaanan Aalto_1.25.028\n";
	print "\n\n";
	exit 1;
	}
system("ccm query /n $search_word /o $owner /v *$version > $query_file");
open (FILE, "$query_file") or die "$query_file dosen't exist: $!";
while(<FILE>)
{
	chomp;
	next if ($_ =~ /^$/);
	$_ =~ /([\d+) ]*)(\w+)([0-9Aa-zZ_\-.:#]*)/;  #etsii rivin alusta numeroa \d+, kaarisulkua ), välilyöntiä , sen jälkeen sanmerkkejä \w+ ja lopuksi erikoismerkkejä ja [Aa-zZ0-9]
	$_ = "$2$3";
	print "$_\n";
	system("ccm delete -p $_");
	print "\n";			
}
close(FILE);