#script will copy image&symbol&uda files from build server to user define folder.

use strict;
use Cwd;
use File::Copy;
use File::Find;

#get path from where to copy files to where
#define home directory
my $source_path = shift;
my $destination_path = shift;
my $home_dir = getcwd();

my @found;
my $imagefile;

unless ($source_path or $destination_path)
{
	usage();
}

#get release flash files folder structure
find(\&process,$source_path);

foreach $imagefile (@found)
{
	chomp;
	next if ($imagefile =~ /.*\/subcon\/.*/); #exclude subcon folder
	if ($imagefile =~ /.fpsx$/)
	{
		print "flashfile name: $imagefile\n";
	}
}



#finds the complete path name to the file and pushing it to @found table.
sub process 
{
	push(@found, $File::Find::name);
}


#Usage
sub usage
{
	print "Script will copy image, uda, symbol and etc files \nfrom build server to network disk folder keeping folder structure\n";
	print"\nUSAGE: perl server2disk.pl <source path> <destination path> \n";
}