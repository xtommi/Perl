###############################################################################################
#created by: Tommi Paananen, 03.05.2013
#
#script: Create_binary_list.pl
#
#purpose: 
#					this script will list all binary files found from Lumia environment spkg files 
#					and write them to binary_component_list excel file.
#
#usage: 
#					perl create_binary_list.pl <folder_name>

#for example spkg files from ffu/ folder:  
#					perl create_binary_list.pl ffu
###############################################################################################
	
use Cwd;				#Cwd - get pathname of current working directory module.
use Env; 				#
use strict;
use warnings;
use File::Find;
use XML::Simple;
use Data::Dumper;
use Spreadsheet::WriteExcel; 
my $curr_dir = getcwd();
my %spkgfilename = ();
my $fileName;
my $xml2spkg;
my $muunimi;
my $data;
my $packetcounter;
my $search;
my $targetdir;
my @found =();
my $look_dir = shift;
if (!$look_dir) { 
	print "\n\nUSAGE:\n";
	print "perl create_binary_list.pl ffu     -> finds all spkg files from ffu + subfolder\n\n";
	exit;
	}
my $packetpath = $look_dir;  	#paketin lopullinen polkutieto
$packetpath =~ s/\\/\//g; 		#muutta takakenot etukenoiksi
system("del spkginside.txt");		#deletoi spkginside
system("del spkgfile.txt");
if (-e "$curr_dir\\manxml"){
	rmdir "$curr_dir\\manxml";
}
system ("del binary_component_list");

my $workbook = Spreadsheet::WriteExcel->new('binary_component_list.xls');   # Create a new Excel workbook
my $worksheet = $workbook->add_worksheet();																	# Add a worksheet
my %hfont =	(																																#  Add and define a format                                          
									font	=>	'Arial',
									size	=>	10,
									color	=>	'blue',
									bold	=>	1,
									align	=> 'center',
									underline	=>	1,
								);
my %tfont	=	(
									font 	=>	'Arial',
									size	=>	10,
									color	=>	'black',
									align	=>	'center',
								);
						
my $format1 = $workbook->add_format(%hfont); # Add a format for headers
my $format2 = $workbook->add_format(%tfont); # Add a format for text
#$format->set_bold();                                                
#$format->set_color('red');                                          
#$format->set_align('center');
#$format->set_underline();

# Increase the column width for clarity
$worksheet->set_column(0,3,30);
$worksheet->set_column(4,11,20);
$worksheet->freeze_panes(1,0);	# Freeze the first row of worksheet
#$worksheet->set_column(undef,7, 25);
#$worksheet->set_column(8,11,15);
#$worksheet->set_column(undef,7, 25);
#$worksheet->set_column(8,10, 10);

my $col = my $row = 0;
#$worksheet->write($row,$col, 'Binary Name',$format1);
$worksheet->write('A1', 'Binary Name in device',$format1);
$worksheet->write('B1', 'Binary path in device',$format1);
$worksheet->write('C1', 'Binaryname in spkg',$format1);
$worksheet->write('D1',	'SPKG packet name', $format1);	
$worksheet->write('E1', 'Component Version',$format1);
$worksheet->write('F1', 'Owner',$format1);
$worksheet->write('G1', 'Component',$format1);
$worksheet->write('H1', 'Sub Component',$format1);
$worksheet->write('I1', 'Description',$format1);
$worksheet->write('J1', 'Owner ID',$format1);
$worksheet->write('K1', 'Release Type',$format1);
$worksheet->write('L1', 'Owner Type',$format1);
$worksheet->write('M1', 'Build Type',$format1);

my %staulukko = (
									binpaate 			=> 	0,
									binpolku 			=>	1,
									origbin				=>	2,
									spkgpacket 		=> 	3,
									versionid			=>	4,
									owner 				=>	5,
									component			=>	6,
									subcomponent	=>	7,
									description		=>	8,
									ownerid				=>	9,
									releasetype		=>	10,
									ownertype			=>	11,
									buildtype			=>	12,
									);
									
#----------------Tee listaus polkulistaus paketeista-------------------------#

find(\&process, $packetpath);	#k‰ynnist‰‰ file::find-function ja hypp‰‰ process subiin

foreach my $spkg (@found){  
	
	if ($spkg =~ /.spkg$/) {														#jos filenimi p‰‰ttyy .spkg p‰‰tteeseen, niin tehd‰‰n t‰m‰
		$packetcounter++;
		my @xmlPolku = split(/\//,$spkg);									#pilkotaan spkg-tiedoston polku taulukkoon
		my $spkgtiedosto = pop (@xmlPolku); 							#palauttaa tauluko viimeisen arvon ja poistaa sen.
		my @tiedostonimi = split(/\./,$spkgtiedosto);
		my $paate = pop (@tiedostonimi);									#poistetaa taulukon viimeinen arvo, t‰ss‰ tapauksessa spkg-p‰‰te
		my $spkgpacketname = join (".", @tiedostonimi); 						#yhdistet‰‰n taulukon alkiot yhteen, ja v‰liin tulee piste
		$spkgfilename{$spkgpacketname} = $packetcounter;	#lis‰t‰‰n hashiin paketin nimi ja countterinarvo
		open(OUT, ">>$curr_dir\\spkgfile.txt");						#kaikki spkg tiedosto t‰h‰n tiedostoon
		print OUT "$spkg\n";
		close(OUT);
		#my @args1 = ("7z", "l", "$spkg");
#----------------Pura/listaa paketti 7Zipill‰-------------------------#
		my $spkginside = `7z l $spkg`;										#backstick, want to capture the output of the command.
		open (OUT2,">>$curr_dir\\spkginside.txt") or die "Failed: $!\n";
		print OUT2 "$spkginside\n";
		close(OUT2);
		
#----------------Pura spkg tiedostosta ainoastaan man.dsm.xml tiedosto--------------#
	#Extracts files from an archive to the current directory or to the output directory. 
	#The output directory can be specified by -o (Set Output Directory) switch.
	my @args = ("7z", "e", "$spkg", "-o$curr_dir\\manxml", "man.dsm.xml", "-y");
	system(@args);
	
#----------------Etsi binaari file paketista ja versiotieto-------------------------#
	my $xmlfile= "$curr_dir\\manxml\\man.dsm.xml";		# tiedoston nimi
	open(INFO, $xmlfile);		# avaa tiedostokahvan
	my @lines = <INFO>;		# lukee tiedoston taulukkoon
	close(INFO);			# sulkee tiedostokahvan
	#print @lines;			# tulostaa taulukon
	rename ("$curr_dir\\manxml\\man.dsm.xml", "$curr_dir\\manxml\\$spkgpacketname$spkgfilename{$spkgpacketname}.xml") || die "Error in renaming $!";			
	my %binsisalto = ();			#m‰‰ritel‰‰n binsalto silpputaulukko binaarifileille
	my %origsisalto = ();
	my %vakiosisalto = ();		#m‰‰ritell‰‰n vakiosisalto silpputaulukko vakionimille
	my @taulu;								#taulukko binaarinimille
	my $bincounter = 0;				#laskuri, kuinka monta binaari filea on yhdessa paketissa
	my $origcounter = 0;
	my $rowcounter = 0; 			
	
		
		foreach my $rivit (@lines){		#k‰yd‰‰n l‰pi xmltiedosto rivikerrallaan
			
			if ($rivit =~ m/(<Owner>)(.*)(<\/Owner>)/){				
				$vakiosisalto{"owner"} = $2; 	
			}
			if ($rivit =~ m/(<Component>)(.*)(<\/Component>)/){
				$vakiosisalto{"component"} = $2;
			}
			if ($rivit =~ m/(<SubComponent>)(.*)(<\/SubComponent>)/){
				$vakiosisalto{"subcomponent"} = $2;                          	
			}
			#<Version Major="3036" Minor="0" QFE="3033" Build="81" />
			if ($rivit =~ /(.*)(\")(\d+)(\")(.*)(\")(\d+)(\")(.*)(\")(\d+)(\")(.*)(\")(\d+)(\")(.*)/){
				my $compversion = "$3.$7.$11.$15";
				$vakiosisalto{"versionid"} = $compversion;
			}
			if ($rivit =~ m/(<ReleaseType>)(.*)(<\/ReleaseType>)/){
				$vakiosisalto{"releasetype"} = $2;
			}
			if ($rivit =~ m/(<OwnerType>)(.*)(<\/OwnerType>)/){
				$vakiosisalto{"ownertype"} = $2;
			}
			if ($rivit =~ m/(<BuildType>)(.*)(<\/BuildType>)/){
				$vakiosisalto{"buildtype"} = $2;
				}
			if ($rivit =~ m/(<BuildString>)(.*)(<\/BuildString>)/){
					if ($2 =~ m/(.*)(description=)(.*)(owner\.id=)(\d+)(.*)/){
						$vakiosisalto{"description"} = $3;
						$vakiosisalto{"ownerid"} = $5;
					}	
				}
			if ($rivit =~ m/(<DevicePath>)(.*)(<\/DevicePath>)/){			
				my @bintaulu = split (/\\/,$2);		#splitataan devicepath takakenoista ja osat bintauluun
				my $binpaate = pop (@bintaulu);		#otetaan bintaulusta viimeisin osa pois, eli binaaritiedosto t‰ss‰ tapauksessa
				my $binpolku = join ("\\", @bintaulu);	#liitetaan loput bintaulunosat yhteen takakenarilla
				if ($binpaate =~ m/\.dll$/ or $binpaate =~ /\.sys$/ or $binpaate =~ /\.bin$/ or $binpaate =~ /\.exe$/) {	#tarkistetaan lˆytyykˆ binaarifile‰
					$bincounter++;
					print "\n\nbinpaate: $binpaate\n";
					print "binpolku: $binpolku\n";
					$binsisalto{"binaryname.$bincounter"} = $binpaate;
					$binsisalto{"binarypath.$bincounter"} =	$binpolku;
				}
			}
			if ($rivit =~ m/(<CabPath>)(.*)(<\/CabPath>)/){		#<CabPath>7_facp.acp</CabPath>
				my $foo = $2;
				if ($foo =~ m/\.dll$/ or $foo =~ /\.sys$/ or $foo =~ /\.bin$/ or $foo =~ /\.exe$/) {
					$origcounter++;			
					$origsisalto{"origname.$origcounter"} = $foo;
				}
			}               	
		}
		
		while ($bincounter > 0){
			my $binary	= $binsisalto{"binaryname.$bincounter"};
			my $binarypath	= $binsisalto{"binarypath.$bincounter"};
			my $origbinary	= $origsisalto{"origname.$origcounter"};
			$row++;
			$worksheet->write($row,$staulukko{binpaate}, "$binary", $format2);
			$worksheet->write($row,$staulukko{binpolku}, "$binarypath", $format2);
			$worksheet->write($row,$staulukko{origbin}, "$origbinary", $format2);
			$worksheet->write($row,$staulukko{spkgpacket}, "$spkgpacketname", $format2);
		
			foreach my $avain (keys %vakiosisalto) { 
				foreach my $sarake (keys %staulukko){
					if ($avain eq $sarake){
						#print "$avain : $vakiosisalto{$avain}\n";
						#print "$sarake : $staulukko{$sarake}\n";
						$worksheet->write($row,$staulukko{$sarake}, "$vakiosisalto{$avain}", $format2);
					}
				}
			}
			$bincounter--;
			$origcounter--;
		}	
	}	
}                        
exit;

sub process {
	push(@found, $File::Find::name)
}

