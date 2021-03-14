#!/usr/bin/perl -w

=for header

Gene annotation program written by Thomas Parish z5207264 for BINF2010

    Program is used in the following way ./geneanot <filename> <other options>
    Other options include:
        -e  changes the e-value cutoff of the request, default is 1
        -f  force the program to use the file even if it is not in the format <filename>.fasta. Be careful when using.
        -o  changes the output file, doing so will mean that the output file is kept after the end of this program.
        -a  prints the alignment of the orfs against the original sequence
        -r  changes the number of results the program produces, default is 3
        -p  changes the percentage match of the request, default is 0.4

Structure of program:
    - Reads command line arguments
    - Runs getorf on specified file
    - Opens file and reads all information into a series of hashes
    - Sort the hashes based off length 
    - Pull out the top 3
    - Construct json request
    - Use RSCB PDB Search API and return the best hit if there is one.
    - Prints graphical representation of orfs if required


As additional features i added the ability to graphically show the orfs found by the rest of the program in relation to 
the overall sequence. It can be used with the -a option when running the command. Also i added the ability to change a
number of variables throughout the program, these are listed above.

=cut

use JSON; # for constructing the api request
use LWP::Simple;  # for interacting with the api

sub setup_json {
    my ($sequence, $e_value, $percentage) = @_;

    # setting up json 
    # need to multiply variables by 1 to be sure perl is treating them as numbers as not strings. If you dont, then they are put into the request as "1" rather than 1
    my %parameters = ("evalue_cutoff" => $e_value * 1, "identity_cutoff" => $percentage * 1, "target" => "pdb_protein_sequence", "value" => $sequence);
    my $parameters_string = encode_json \%parameters;

    my %query = ("type" => "terminal", "service" => "sequence", "parameters" => $parameters_string);
    my $query_string = encode_json \%query;

    my %pager = ("start" => 0, "rows" => 1);
    my $pager_string = encode_json \%pager;

    my %request_options = ("scoring_strategy" => "sequence", "pager" => $pager_string);
    my $request_options_string = encode_json \%request_options;

    my %request = ("query" => $query_string, "request_options" => $request_options_string, "return_type" => "polymer_entity");
    my $request_string = encode_json \%request;

    # getting rid of '\' which encode_json adds when going multiple layers deep
    $request_string =~ s/(\\)*\"\{/\{/g;
    $request_string =~ s/\}\\\"/\}/g;
    $request_string =~ s/\\//g;
    $request_string =~ s/\}\"/}/g;
    $request_string =~ s/\"\{/\{/g;

    # creating url
    my $url = "https://search.rcsb.org/rcsbsearch/v1/query?json=$request_string";
    return $url;
}

sub search_pdb {
    my ($sequence, $desired_e_value, $percentage) = @_;

    #json request
    #my $request = '{"query":{"type":"terminal","service":"sequence",' .
    #            '"parameters":{"evalue_cutoff":1000,"identity_cutoff":0,' .
    #            '"target":"pdb_protein_sequence","value":"'.
    #            $sequence .
    #            '"}},"request_options":{"scoring_strategy":"sequence",' .
    #            '"pager":{"start":0,"rows": 1}},"return_type": "polymer_entity"}';
    
    #build request
    my $url = setup_json($sequence, $desired_e_value, $percentage);

    my $web_page = get($url) or return;  
    # if it fails, return no values. The program inteprets that as a failure and 
    # will place '-' in the fields for PDB_ID and E-value

    # print ("Request returned: \n\n $web_page");
    
    my @info = split('\n', $web_page);
    foreach $line (@info) {
        
        # since the match percentage is after the identifier, we can just delete the varaible, meaning it returns nothing
        # if the match is below 40%
        if ($line =~ / "sequence_identity" : (\d\.\d*),/) {
            # print "MATCH IS $1\n";
            if ($1 < $percentage) {
                undef $PDB_ID;
            }
            
        }
        if ($line =~ /"identifier" : "(.*)"/) {
            
            $PDB_ID = $1;

        }
        # pull e-value out
        if ($line =~ /"evalue" : (.*),/) {
            $E_value = $1;

        }
        
    }
    return ($PDB_ID, $E_value);
}


# variables to handle arugments and to save arguments in
$outfile = "temp.orf";
$outfile_option = 0;
$force = 0;

$e_value_option = 0;
$desired_evalue = 1;

$percentage_match_option = 0;
$desired_percentage = 0.4;

$results_option = 0;
$desired_results = 3;

$alignment_option = 0;

# ARGUMENT HANDLING
foreach $ARGV (@ARGV) {

    if ($ARGV =~ /(.*)\.fasta/) {
        $file = $ARGV;
    } elsif (-e $ARGV) {
        if ($force == 1) {
            $file = $ARGV;
            $force = 0;
        } else {
            print "\nPlease provide a file that is in the format <filename>.fasta. If you want to override this please type -force before the filename\n\n " and exit;
        }
    }

    if ($e_value_option == 1) {
        
        if ($ARGV =~ /\d*(.\d*)+/) {
            $desired_evalue = $ARGV;
        } else {
            print "usage: ./geneanot <filename> -e <desired e_value>\n";
        }
        $e_value_option = 0;
        next;
    }

    if ($results_option == 1) {
        if ($ARGV =~ /^\d*$/) {
            $desired_results = $ARGV;
        } else {
            print "usage: ./geneanot <filename> -r <desired number of results>\n";
        }
        $results_option = 0;
        next;
    }

    if ($outfile_option == 1) {
        if ($ARGV =~ /^\w*.orf/) {
            $outfile = $ARGV;
        } else {
            print "Please provide a file that is in the format <filename>.fasta. If you want to override this please type -force before the filename\n";
        }
        $outfile_option = 2;
        next;
    }

    if ($percentage_match_option == 1) {
        if ($ARGV =~ /^(0\.\d*)$|^1$/) {
            $desired_percentage = $ARGV;
        } elsif ($ARGV =~ /^(\d*)/) {
            print "Percentage must be between 0 and 1, using default of 0.4\n";
        } else {
            print "usage: ./geneanot <filename> -p <desired percentage match>\n";
        }
        $percentage_match_option = 0;
        next;
    }

    if ($ARGV =~ /^-/) {
        if ($ARGV =~ /^-e/) {
            $e_value_option = 1;
            next;
        } elsif ($ARGV =~ /^-p/) {
            $percentage_match_option = 1;
            next;
        } elsif ($ARGV =~ /^-r/) {
            $results_option = 1;
            next;
        } elsif ($ARGV =~ /^-o/) {
            $outfile_option = 1;
            next;
        } elsif ($ARGV =~ /^-a/) {
            $alignment_option = 1;
            next;
        } elsif ($ARGV =~ /^-help/){
            print "\nProgram is used in the following way ./geneanot <filename> <other options>\n\n" .
                "Other options include:\n" .
                "     -e  changes the e-value cutoff of the request, default is 1\n" .
                "     -f  force the program to use the file even if it is not in the format <filename>.fasta. Be careful when using.\n" .
                "     -o  changes the output file, doing so will mean that the output file is kept after the end of this program.\n" .
                "     -r  changes the number of results the program produces, default is 3\n" .
                "     -a  rints the alignment of the orfs against the original sequence\n" .
                "     -p  changes the percentage match of the request, default is 0.4\n\n";
            exit;
        } elsif ($ARGV =~ /^-f/) {
            $force = 1;
        } else {
            print "Invalid option selected, please pick from the list of options. Type ./geneanot.pl -help for more information\n";
        }
    }
        
}

#running external program
system("getorf -sequence $file -outseq $outfile -minsize 150 2> /dev/null");

#open the temporary file storing the orfs
open my $tempfile, '<', $outfile or die "Cannot open $outfile: $!";

# don't love this, might try and make it 2d rather than multiple 1d
my %sequences;
my %length;
my %start;
my %end;
my %direction;

# cycle through each line of the file
while ($line = <$tempfile>) {
    chomp $line;

    # if a header file, pull out the important info
    if ($line =~ /^>/){

        #pull out the sequence name to use as and id
        $line =~ s/^>(.*) \[/\[/;
        $identifier = $1;

        #pull out the first and last base number
        $line =~ s/^\[(\d*) - (\d*)\]//;
        
        $first = $1;
        $last = $2;
        
        # if below the cut off, dont save (shouldn't happen, requires a problem with getorf)
        if(abs($first - $last) < 150) {
            next;
        }

        # calculating lengths, need to handle both forward and reverse cases
        if ($first >= $last) {
            $length{$identifier} = $first - $last + 1;
            $direction{$identifier} = "REVERSE";
        } else {
            $length{$identifier} = $last -  $first + 1;
            $direction{$identifier} = "FORWARD";
        }

        # save to hashes
        $start{$identifier} = $first;
        $end{$identifier} = $last;
    
    } else {
        #appending the sequence to the hash
        chomp $line;
        $sequences{$identifier} .= $line;
    }
}

# if there was no lines starting with '>', then the file is not in fasta format
if (!%length) {
    print "No Orfs were found in the given file\n" and exit;
}

# saving the top n longest results
$counter = 0;

foreach my $identifier (sort { $length{$b} <=> $length{$a} } keys %length) {
    
    
    if ($counter >= $desired_results){
        last;
    }
    $top{$identifier} = $start{$identifier};
    $counter++;

}

# printing data as csv
print "Start,End,Strand,PDB_ID,E-value\n";
foreach my $identifier (sort { $top{$a} <=> $top{$b} } keys %top) {
    ($id, $e_val) = search_pdb($sequences{$identifier}, $desired_evalue, $desired_percentage);
    $name{$identifier} = $id;
    if ($id and $e_val) {
        # if we get results from rcsb.org
        printf "%d,%d,%s,%s,%s\n" ,$start{$identifier}, $end{$identifier}, $direction{$identifier}, $id, $e_val;
    } elsif ($e_val) {
        
        # if we get results from rcsb.org
        printf "%d,%d,%s,-,%s\n" ,$start{$identifier}, $end{$identifier}, $direction{$identifier}, $e_val;
    } elsif ($id) {
        
        # if we get results from rcsb.org
        printf "%d,%d,%s,%s,-\n" ,$start{$identifier}, $end{$identifier}, $direction{$identifier}, $id;
    } else {
        # if we dont get results
        printf "%d,%d,%s,-,-\n" ,$start{$identifier}, $end{$identifier}, $direction{$identifier};
    }
    
}

if ($alignment_option == 1) {
    print "\n";
    open my $tempfile, '<', $file or die "Cannot open $outfile: $!";
    $start_position = 0;
    $end_position = 0;
    $total_chars = 0;
    while ($line = <$tempfile>) {
        chomp $line;
        if ($line =~ /^>/) {
            next;
        }

        my $counter = 0;
        @characters = split('', $line);
        foreach (@characters) {

            $end_position++;
            $total_chars++;
        }
        printf "%8s %s %s\n", $start_position, $line, $end_position;
        foreach my $identifier (sort { $top{$a} <=> $top{$b} } keys %top) {
            if ($counter >= 3) {
                last;
            }
            if (!$name{$identifier}){
                next;
            }

            if ($name{$identifier}) {
                printf "%8s ", $name{$identifier};
            }
            for (my $i = 0; $i < $end_position - $start_position; $i++) {
                if ($direction{$identifier} eq "FORWARD") {
                    if ($end{$identifier} < $start_position + $i + 1) {
                        print " ";
                    } elsif ($start{$identifier} < $start_position + $i + 1){
                        print "*";
                    } else {
                        print " ";
                    }
                }
            }
            for (my $i = 0; $i < $end_position - $start_position; $i++) {
                if ($direction{$identifier} eq "REVERSE") {
                    if ($start{$identifier} < $start_position + $i + 1) {
                        print " ";
                    } elsif ($end{$identifier} < $start_position + $i + 1){
                        print "*";
                    } else {
                        print " ";
                    }
                }
            }
            print "\n";
            
            $counter++;
        }
        $start_position = $end_position;
        print "\n";
    }

}

# delete the temporary file
if ($outfile_option != 2) {
    unlink($outfile);
}
