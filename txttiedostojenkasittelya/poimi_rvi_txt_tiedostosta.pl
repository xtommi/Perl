use Cwd;
use strict;

my $input_file = shift;
my $search_word = shift;
my $output = "my_output.txt";

unless ( $input_file and $search_word)
	{
	print "perl poimi_rivi_txt_tiedostosta.pl <INPU_FILE_NAME> <SEARCH_WORD>";	
	exit 1;
	}

if (-e "my_output.txt"){
	system("del my_output.txt");
}

open (FILE, "$input_file") or die "$input_file: $!";
while(<FILE>)
{
	chomp;
	next if ($_ =~ /^$/);
			
	#$object_name = $_;
	#$task_id = $_;
	
	if ($_ =~ /($search_word)/i) 
	{
		print "rivi: $_\n";
		open (OUTPUT, ">>$output");
		print OUTPUT "$_\n";
		close(OUTPUT);
	}
}
close(FILE);	

