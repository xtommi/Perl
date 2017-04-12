# Created by Tommi Paananen 16.08.2006

use Cwd;
use strict;
use Getopt::Long;

my $input_file = "";
my $search_word = "";
my $look_same_word = "";
my $output = "my_output.txt";

&GetOptions ('input_file|i=s' => \$input_file, 'search_word|s=s' => \$search_word, 'look_same_word|l=s' => \$look_same_word) || die "Wrong syntax !! \n";

unless($input_file){ 
	print "\n\n";
	print "perl poimi_rivi_txt_tiedostosta.pl -i <INPU_FILE_NAME>\n";
	print "\t\t or \n";	
	print "perl poimi_rivi_txt_tiedostosta.pl -i <INPU_FILE_NAME> -s <SEARCH_WORD>\n";
	print "\t\t or \n";	
	print "perl poimi_rivi_txt_tiedostosta.pl -i <INPU_FILE_NAME> -l <SAME>\n";	
	print "\n\n";
	exit 1;
}
if (-e "my_output.txt"){
	system("del my_output.txt");
}

if ($search_word)
{
	serch_word();
}elsif ($look_same_word eq "same"){
	look_same_word();
}else {exit;}


sub serch_word ()
{
	open (FILE, "$input_file") or die "$input_file: $!";
	while(<FILE>)
	{
		chomp;
		next if ($_ =~ /^$/);
		if ($_ =~ /($search_word)/i) {
			print "rivi: $_\n";
			open (OUTPUT, ">>$output");
			print OUTPUT "$_\n";
			close(OUTPUT);
		}else {next};
	}
	close(FILE);	 
}

sub look_same_word ()
{
		my @t1 = "";
		my @t2 = "";
		my $t1 = "";
		my $t2 = "";
		my $t3 = "";
				
		open (IN, "$input_file") or die "cannot open $input_file: $!";
		while (<IN>)
		{
			next if ($_ =~ /^$/);
			$t1 = $_;
			$t1 =~ /(.*)(-)(.*)/;
			$t1 = "$1";
			#print "t1: $t1\n";
			
			if ($t1 eq $t3)
			{
				#print "t1: $_";
				#print "t2: $t2\n";
				open (OUT,">>$output") or die "cannot open $output$!";
				print OUT $_;
				print OUT $t2;
				print OUT "\n";
			}
			$t2 = $_;
			$t3 = $t1;
		}
		close(IN);
		close(OUT);
	}