#!/usr/bin/perl

use strict;
use Getopt::Long qw(GetOptions);
use FindBin qw($Bin); 

### INPUT: vcf file and list of normal/tumor sample pairing information
### OUTPUT: 2 maf files; 

### NOTE: CAN'T RUN ON NODE BECAUSE NO NETWORK ACCESS FOR ONCOTATOR
### NOTE2: DESIGNED TO WORK FOR ONCOTATOR ANNOTATED MAFS

my ($vcf, $pairing, $patient, $bam_dir, $species, $config, $caller, $normal_sample, $tumor_sample, $delete_temp);
GetOptions ('vcf=s' => \$vcf,
	    'species=s' => \$species,
	    'config=s' => \$config,
	    'caller=s' => \$caller,
            'align_dir=s' => \$bam_dir,
            'patient=s' => \$patient,
	    'normal_sample=s' => \$normal_sample,
	    'tumor_sample=s' => \$tumor_sample,
	    'delete_temp' => \$delete_temp,
	    'pairing=s' => \$pairing) or die;


my $somatic = 'UNPAIRED';
if(!$vcf){
    die "YOU MUST PROVIDE A VCF\n";
}

if(!-e $vcf){
    die "$vcf DOES NOT EXIST";
}

if($pairing){
    $somatic = 'PAIRED';
    if(!-e $pairing){
	die "$pairing DOES NOT EXIST";
    }
}

if($patient) {
    if(!-e $patient){
        die "$patient DOES NOT EXIST";
    }
    if(!$bam_dir){
        die "If patient file is given, you must supply alignment directory for fillout.";
    }
}

if($bam_dir){
    if(!-e $bam_dir){
        die "$bam_dir DOES NOT EXIST";
    }
}

if($species !~ /hg19/i){
    die "Only support for hg19";
}

if($caller !~ /unifiedgenotyper|ug|haplotypecaller|hc|mutect|varscan|somaticsniper/i){
    die "Only support for unifiedgenotyper(ug), haplotypecaller(hc), mutect, varscan, and somaticsniper";
}

my $HG19_FASTA = '';
my $ONCOTATOR = '';
my $PYTHON = '';
my $PERL = '';
open(CONFIG, "$config") or warn "CAN'T OPEN CONFIG FILE $config SO USING DEFAULT SETTINGS";
while(<CONFIG>){
    chomp;

    my @conf = split(/\s+/, $_);
    if($conf[0] =~ /oncotator/i){
	if(!-e "$conf[1]/oncotateMaf.sh"){
	    die "CAN'T FIND oncotateMaf.sh IN $conf[1] $!";
	}
	$ONCOTATOR = $conf[1];
    }
    elsif($conf[0] =~ /hg19_fasta/i){
        if(!-e "$conf[1]"){
          die "CAN'T FIND $conf[1] $!";
        }
        $HG19_FASTA = $conf[1];
    }
    elsif($conf[0] =~ /python/i){
	if(!-e "$conf[1]/python"){
	    die "CAN'T FIND python IN $conf[1] $!";
	}
	$PYTHON = $conf[1];
    }
    elsif($conf[0] =~ /perl/i){
	if(!-e "$conf[1]/perl"){
	    die "CAN'T FIND perl IN $conf[1] $!";
	}
	$PERL = $conf[1];
    }
}
close CONFIG;

print "converting to MAF and filtering snp calls for coverage/qual\n";
if($caller =~ /unifiedgenotyper|ug|haplotypecaller|hc/i){
    if($pairing){
	print "$PYTHON/python $Bin/maf/vcf2maf0.py -i $vcf -c $caller -o $vcf\_PAIRED.maf -p $pairing\n";
	print "cat $vcf\_PAIRED.maf | $PYTHON/python $Bin/maf/pA_qSomHC.py | /usr/bin/tee $vcf\_$somatic\_maf0.txt\n\n";

	`$PYTHON/python $Bin/maf/vcf2maf0.py -i $vcf -c $caller -o $vcf\_PAIRED.maf -p $pairing`;
	`cat $vcf\_PAIRED.maf | $PYTHON/python $Bin/maf/pA_qSomHC.py | /usr/bin/tee $vcf\_$somatic\_maf0.txt > $vcf\_$somatic\_maf0.log 2>&1`;
    }
    else{
	print "$PYTHON/python $Bin/maf/vcf2maf0.py -i $vcf -c $caller -o $vcf\_UNPAIRED.maf\n";
	print "cat $vcf\_UNPAIRED.maf | $PYTHON/python $Bin/maf/pA_Cov+noLow.py | /usr/bin/tee $vcf\_$somatic\_maf0.txt\n\n";
	`$PYTHON/python $Bin/maf/vcf2maf0.py -i $vcf -c $caller -o $vcf\_UNPAIRED.maf`;
	`cat $vcf\_UNPAIRED.maf | $PYTHON/python $Bin/maf/pA_Cov+noLow.py | /usr/bin/tee $vcf\_$somatic\_maf0.txt > $vcf\_$somatic\_maf0.log 2>&1`;
    }
}
else{
    my $af = '';
    if($caller =~ /mutect|mu/i){
	my $mutext = $vcf;
	$mutext =~ s/\.vcf$/\.txt/;
	$af = "-aF $mutext";
    }

    my $n_sample = '';
    my $t_sample = '';
    if($normal_sample && $tumor_sample){
	$n_sample = "-n $normal_sample";
	$t_sample = "-t $tumor_sample";
    }

    print "$PYTHON/python $Bin/maf/vcf2maf0.py -i $vcf $af -c $caller -o $vcf\_$somatic\_maf0.txt -p $pairing $n_sample $t_sample\n\n";
    `$PYTHON/python $Bin/maf/vcf2maf0.py -i $vcf $af -c $caller -o $vcf\_$somatic\_maf0.txt -p $pairing $n_sample $t_sample`;

    if($caller =~ /mutect|mu/i){
	`/bin/mv $vcf\_$somatic\_maf0.txt $vcf\_$somatic\_UNFILTERED.txt`;
	print "$PYTHON/python $Bin/rescue/DMP_rescue.py <$vcf\_$somatic\_UNFILTERED.txt> $vcf\_$somatic\_rescued.txt 2> $vcf\_$somatic\_maf0_rescue.log";
	`$PYTHON/python $Bin/rescue/DMP_rescue.py <$vcf\_$somatic\_UNFILTERED.txt> $vcf\_$somatic\_rescued.txt 2> $vcf\_$somatic\_maf0_rescue.log`;
	
	open(MUT, "$vcf\_$somatic\_rescued.txt");
	open(OUT, ">$vcf\_$somatic\_maf0.txt");
	my $header = <MUT>;
	print OUT "$header";
	my @columns = split(/\t/, $header);
	my $index_keep = -1;

	for(my $i=0; $i<scalar(@columns); $i++){
	    if($columns[$i] eq 'MUT_KEEP'){
		$index_keep = $i;
	    }
	}
	
	if($index_keep == -1){
	    die "Can find MUT_KEEP column in $vcf\_$somatic\_UNFILTERED.txt";
	}

	while(my $line=<MUT>){
	    chomp $line;
	    
	    my @data = split(/\t/, $line);
	    if($data[$index_keep] eq 'KEEP'){
		print OUT "$line\n";
	    }
	}
	close MUT;
	close OUT;
    }
}

print "converting to new MAF format using species $species ... \n";
print "$PYTHON/python $Bin/maf/oldMAF2tcgaMAF.py $species \<$vcf\_$somatic\_maf0.txt\> $vcf\_$somatic\_maf1.txt\n\n";
### Convert old (NDS) MAF to official TCGA MAF
### NOTE; DON'T FORGET <> AROUND INPUT FILE (maf0.txt)
`$PYTHON/python $Bin/maf/oldMAF2tcgaMAF.py $species $vcf\_$somatic\_maf0.txt $vcf\_$somatic\_maf1.txt`;

print "adding oncotator annotations... \n";
print "$ONCOTATOR/oncotateMaf.sh $vcf\_$somatic\_maf1.txt $vcf\_$somatic\_maf2.txt\n\n";;
### Annotate with Oncotator
### expects db.properties to be in working directory
### NOTE: ALWAYS DOUBLE CHECK TO MAKE SURE ONCOTATOR WENT THROUGH ENTIRE MAF1 FILE
###       IT DOESN'T ALWAYS DO SO FOR SOME REASON
`/bin/ln -s $ONCOTATOR/db.properties .`;
`$ONCOTATOR/oncotateMaf.sh $vcf\_$somatic\_maf1.txt $vcf\_$somatic\_maf2.txt`;

print "modifying hugo_symbol column\n";
print "/bin/cat $vcf\_$somatic\_maf2.txt | $PYTHON/python $Bin/maf/pA_fixHugo.py > $vcf\_$somatic\_maf3.txt\n\n";
### modify hugo_symbol column
`/bin/cat $vcf\_$somatic\_maf2.txt | $PYTHON/python $Bin/maf/pA_fixHugo.py > $vcf\_$somatic\_maf3.txt`;

print "updating hugo symbol\n";
print "$PERL/perl $Bin/update_gene_names_and_ids.pl $vcf\_$somatic\_maf3.txt\n\n";
### update hugo_symbol
### deletes old copy and get fresh copy every time
#`/bin/rm $Bin/lib/hugo_data.tsv`;
`$PERL/perl $Bin/update_gene_names_and_ids.pl $vcf\_$somatic\_maf3.txt > $vcf\_$somatic\_MAF3_HUGO.log 2>&1`;

print "creating TCGA-formatted MAF file... \n";
print "/bin/cat $vcf\_$somatic\_maf3.txt_hugo_modified | $PYTHON/python $Bin/maf/pA_Functional_Oncotator.py\n\n";
# Create annotated TCGA MAF
`/bin/cat $vcf\_$somatic\_maf3.txt_hugo_modified | $PYTHON/python $Bin/maf/pA_Functional_Oncotator.py > $vcf\_$somatic\_TCGA_MAF.txt`;

print "creating MAF for cbio portal submission";
print "cat $vcf\_$somatic\_TCGA_MAF.txt | $PYTHON/python $Bin/maf/pA_reSortCols.py $Bin/maf/finalCols_PORTAL.txt > $vcf\_$somatic\_TCGA_MAF_PORTAL.txt\n";
`cat $vcf\_$somatic\_TCGA_MAF.txt | $PYTHON/python $Bin/maf/pA_reSortCols.py $Bin/maf/finalCols_PORTAL.txt > $vcf\_$somatic\_TCGA_MAF_PORTAL.txt`;


print "creating clean MAF file\n";
print "/bin/cat $vcf\_$somatic\_maf3.txt_hugo_modified | $PYTHON/python $Bin/maf/pA_Functional_Oncotator.py | $PYTHON/python $Bin/maf/pA_reSortCols.py $Bin/maf/finalCols.txt > $vcf\_$somatic\_MAF4.txt\n\n";
# Create nice MAF with essential columns
`/bin/cat $vcf\_$somatic\_maf3.txt_hugo_modified | $PYTHON/python $Bin/maf/pA_Functional_Oncotator.py | $PYTHON/python $Bin/maf/pA_reSortCols.py $Bin/maf/finalCols.txt > $vcf\_$somatic\_MAF4.txt`;

print "annotating with cosmic\n";
print "$PYTHON/python $Bin/maf/maf_annotations/addCosmicAnnotation.py -i $vcf\_$somatic\_TCGA_MAF.txt -o $vcf\_$somatic\_TCGA_MAF_COSMIC_STANDARD.txt -f $Bin/data/CosmicMutantExport_v67_241013.tsv\n\n";
print "$PYTHON/python $Bin/maf/maf_annotations/addCosmicAnnotation.py -i $vcf\_$somatic\_TCGA_MAF.txt -o $vcf\_$somatic\_TCGA_MAF_COSMIC_DETAILED.txt -f $Bin/data/CosmicMutantExport_v67_241013.tsv -d\n\n";
`$PYTHON/python $Bin/maf/maf_annotations/addCosmicAnnotation.py -i $vcf\_$somatic\_TCGA_MAF.txt -o $vcf\_$somatic\_TCGA_MAF_COSMIC_STANDARD.txt -f $Bin/data/CosmicMutantExport_v67_241013.tsv`;
`$PYTHON/python $Bin/maf/maf_annotations/addCosmicAnnotation.py -i $vcf\_$somatic\_TCGA_MAF.txt -o $vcf\_$somatic\_TCGA_MAF_COSMIC_DETAILED.txt -f $Bin/data/CosmicMutantExport_v67_241013.tsv -d`;

print "annotating with mutation assessor\n";
print "$PYTHON/python $Bin/maf/maf_annotations/addMAannotation.py -i $vcf\_$somatic\_TCGA_MAF_COSMIC_STANDARD.txt -o $vcf\_$somatic\_TCGA_MAF_COSMIC_MA_STANDARD.txt\n";
print "$PYTHON/python $Bin/maf/maf_annotations/addMAannotation.py -i $vcf\_$somatic\_TCGA_MAF_COSMIC_DETAILED.txt -o $vcf\_$somatic\_TCGA_MAF_COSMIC_MA_DETAILED.txt -d\n\n";
`$PYTHON/python $Bin/maf/maf_annotations/addMAannotation.py -i $vcf\_$somatic\_TCGA_MAF_COSMIC_STANDARD.txt -o $vcf\_$somatic\_TCGA_MAF_COSMIC_MA_STANDARD.txt`;
`$PYTHON/python $Bin/maf/maf_annotations/addMAannotation.py -i $vcf\_$somatic\_TCGA_MAF_COSMIC_DETAILED.txt -o $vcf\_$somatic\_TCGA_MAF_COSMIC_MA_DETAILED.txt -d`;

if($patient && $bam_dir){
    if($pairing){

        print "Starting maf fillout\n";
        # open patient file, get each sample name:
        # then find file with that name in the alignement directory
        # make sure it there is only 1 bam per sample
        # add that to a array
        open(PATIENT, "$patient") || die "Can't open patient file $patient $!";
        my $header = <PATIENT>;
        my @header = split(/\s+/,$header);

        my ($sID_index) = grep {$header[$_] =~ /Sample_ID/} 0..$#header;
        #print "Sample index: $sID_index\n";

        my @bamList;
 
        while(<PATIENT>) {
            chomp;
            my @patient=split(/\s+/,$_);
            #print "Sample: $patient[$sID_index] \n";
            my $bamFile = `find $bam_dir -name "Proj_*_indelRealigned_recal_$patient[$sID_index].bam"`;
            chomp($bamFile);
            #print "Bam file: $bamFile \n";
        
            push(@bamList, "--bam $patient[$sID_index]:$bamFile");
        }

        my $bam_inputs = join(" ", @bamList);

        print "$Bin/maf/fillout/GetBaseCountsMutliSample/GetBaseCountsMultiSample --fasta $HG19_FASTA $bam_inputs --output $vcf\_$somatic\_TCGA_basecounts.txt --maf $vcf\_$somatic\_TCGA_MAF.txt --filter_improper_pair 0\n\n";
        `$Bin/maf/fillout/GetBaseCountsMutliSample/GetBaseCountsMultiSample --fasta $HG19_FASTA $bam_inputs --output $vcf\_$somatic\_TCGA_basecounts.txt --maf $vcf\_$somatic\_TCGA_MAF.txt --filter_improper_pair 0`;

        print "$PYTHON/python $Bin/maf/fillout/dmp2MAF0 -m $vcf\_$somatic\_TCGA_MAF.txt -p $pairing -P $patient -b $vcf\_$somatic\_TCGA_basecounts.txt -o $vcf\_$somatic\_TCGA_MAF_fillout.txt\n";    
        `$PYTHON/python $Bin/maf/fillout/dmp2MAF0 -m $vcf\_$somatic\_TCGA_MAF.txt -p $pairing -P $patient -b $vcf\_$somatic\_TCGA_basecounts.txt -o $vcf\_$somatic\_TCGA_MAF_fillout.txt`;
    } else {
        print "As of right now you cannot do fillout without a pairing file. Please check back for updates.\n";
    }
}


if($delete_temp){
    `/bin/rm $vcf\_PAIRED.maf $vcf\_$somatic\_maf0.txt $vcf\_$somatic\_maf0.log $vcf\_UNPAIRED.maf $vcf\_$somatic\_UNFILTERED.txt $vcf\_$somatic\_maf1.txt $vcf\_$somatic\_maf2.txt $vcf\_$somatic\_maf3.txt $vcf\_$somatic\_MAF3_HUGO.log $vcf\_$somatic\_maf3.txt_ambiguous $vcf\_$somatic\_maf3.txt_hugo_modified $vcf\_$somatic\_TCGA_MAF_COSMIC_STANDARD.txt $vcf\_$somatic\_TCGA_MAF_COSMIC_DETAILED.txt $vcf\_$somatic\_UNFILTERED.txt $vcf\_$somatic\_rescued.txt $vcf\_$somatic\_maf0_rescue.log`;
}
