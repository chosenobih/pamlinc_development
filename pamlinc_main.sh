#!/bin/bash
#Chosen Obih
#Script to process and analyze Illuminaa RNA-Seq data for the annotation of modified RNAs, lincRNAs and quantification of transcript abundance

usage() {
      echo ""
      echo "Usage : sh $0 -g <reference_genome>  -a <reference_annotation> -i <genome_indexes_folder> -l lib_type {-1 <left_reads> -2 <right_reads> | -u <single_reads> | -S <sra_id>} -o <output_folder for pipeline files> -p num_threads -d reads_mismatches -t tophat -s star -w trimmomatic -x fastp -c sjdbOverhang -f genomeSAindexNbases -q transcript_abundance_quantification -e evolinc_i <-E TE_RNA> <-C CAGE_RNA> <-D Known_lincRNA> -m HAMR -r gene_attribute -n strandedness -k feature_type"
      echo ""

cat <<'EOF'
  
  ######################################### COMMAND LINE OPTIONS #############################
  -g <reference genome fasta file>
  -a <reference genome annotation>
  -i </path/to/genome indexes>
  -l library type #note that this is a lower case L
  -1 <reads_1>
               # Ends with R1 and is in the same order as reverse reads
  -2 <reads_2>
               # Ends with R2, must be present, and is in the same order as forward reads
  -u <single_reads> # Do not use single reads along with paired end reads
  -o </path/to/ pipeline output folder>
  -S SRA ID number
  -p number of threads
  -q transcript abundance quantification
  -t tophat2 mapping #needed if you want to run HAMR
  -s star mapping #deactivates tophat2 and HAMR
  -w use trimmomatic for trimming reads
  -x use fastp for trimming reads #deactivates trimmomatic
  -c sjdbOverhang #value is dependent on the read length of your fastq files (read length minus 1)
  -f genomeSAindexNbases #default value is 14 but it should be scaled downed for small genomes, with a typical value of min(14, log2(GenomeLength)/2 - 1)
  -y type of reads (single end or paired end) #denoted as "SE" or "PE", include double quotation on command line
  -d reads_mismatches (% reads mismatches to allow. Needed for tophat2)
  -m HAMR
  -e evolinc_i
  -E </path/to/transposable Elements file>
  -C </path/to/CAGE RNA file>
  -D </path/to/known lincRNA file>
  -k feature type #Feature type (Default is exon)
  -r gene attribute (Default is gene_id)
  -n strandedness (Default is 0 (unstranded), 1 (stranded), 2 (reversely stranded)
################################################# END ########################################
EOF
    exit 0
}


trimmomatic=0
fastp=0
star=0
tophat=0
referencegenome=0
referenceannotation=0
HAMR=0
evolinc_i=0
transcript_abun_quant=0

while getopts ":g:a:A:i:l:1:2:u:o:S:p:d:k:c:f:r:n:htswxqeECDmy:" opt; do
  case $opt in
    g)
    referencegenome=$OPTARG # Reference genome file
     ;;
    a)
    referenceannotation=$OPTARG # Reference genome annotation
     ;;
    i)
    index_folder=$OPTARG # Input folder
     ;;
    l)
    lib_type=$OPTARG # Library type (lib-type can be fr-unstranded, fr-firststrand or fr-secondstrand. If you are not sure of the library type of your reads, you can infer it using salmon.)
     ;;
    1)
    left_reads+=("$OPTARG") # Left reads
     ;;
    2)
    right_reads=("$OPTARG") # Right reads
     ;;
    u)
    single_reads+=("$OPTARG") # single end reads
     ;;
    o)
    pipeline_output=$OPTARG # pipeline output files
     ;;
    S)
    sra_id=$OPTARG # SRA ID or SRA ID's in a file
     ;;
    p)
    num_threads=$OPTARG # Number of threads
     ;;
    d)
    reads_mismatches=$OPTARG # Number of mismatches to allow in tophat2 run
     ;;
    q)
    transcript_abun_quant=$OPTARG # transcript abundance quantification
     ;;
    m)
    HAMR=$OPTARG # HAMR
     ;;
    e)
    evolinc_i=$OPTARG # evolinc_i
     ;;
    E)
    blast_file=$OPTARG # evolinc_i
     ;;
    C)
    cage_file=$OPTARG # evolinc_i
     ;;
    D)
    known_linc=$OPTARG # evolinc_i
     ;;
    s)
    star=$OPTARG # star
     ;;
    w)
    trimmomatic=$OPTARG # trimmomatic
     ;;
    x)
    fastp=$OPTARG # fastp
     ;;
    c)
    sjdbOverhang=$OPTARG # need for star genome index building. Value is dependent on the read length of your fastq files (sjdbOverhang = read length - 1)
     ;;
    f)
    genomeSAindexNbases=$OPTARG # needed for star genome index building. Default value is 14 but it should be scaled downed for small genomes, with a typical value of min(14, log2(GenomeLength)/2 - 1)
     ;;
    t)
    tophat=$OPTARG # tophat
     ;;
    k) 
    feature_type=$OPTARG # Feature type (Default is exon)
     ;;
    r) 
    gene_attribute=$OPTARG # (Default is gene_id)
     ;;
    n)
    strandedness=$OPTARG # (Default is 0 (unstranded), 1 (stranded), 2 (reversely stranded))
     ;;
    y)
    seq_type=$OPTARG # Type of Sequence data (SE or PE. Mainly needed for SRA and featurecounts)
     ;;
    h)
    usage
     exit 1
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

echo "pipeline starts"
date

# Create the output directory
if [ ! -d "$pipeline_output" ]; then
  mkdir $pipeline_output
  elif [ -d "$pipeline_ouput" ]; then
  rm -r $pipeline_output; mkdir $pipeline_output
fi

###################################################################################################################
# # Check reference genome annotation file type and convert to .gtf if .gff file was supplied by user.
###################################################################################################################
#extract the basename of input reference genome
gname=$(basename "$referencegenome" | cut -d. -f1)

if (grep -q -E 'transcript_id | gene_id' $referenceannotation); then
    echo "$referenceannotation is in .gtf format"
    else
    gffread $referenceannotation -T -o "$gname".gtf
    referenceannotation="$gname".gtf
fi

###################################################################################################################
# # pipeline house keeping - move output files into user input directory; delete some intermediate output files
###################################################################################################################

house_keeping()
{
      mkdir intermediate_files
      if [ -e "./$gname.gtf" ]; then
          rm "$gname".gtf
      fi

      if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
            mkdir trimmomatic_output
            if [ "$seq_type" == "SE" ]; then
                mv *_trimmed.* trimmomatic_output
            else
                mv *_1P.* *_1U.* *_2P.* *_2U.* trimmomatic_output
            fi
            mv trimmomatic_output "$pipeline_output"

      elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
            mkdir fastp_output
            if [ "$seq_type" == "SE" ]; then
                mv *_fastp.* *_trimmed.* fastp_output
            else
                mv *_fastp.* *_trimmed_* fastp_output
            
            fi
            mv fastp_output "$pipeline_output"
      fi

      if [ ! -z "$index_folder" ]; then
            if [ "$tophat" != 0 ] && [ "$star" == 0 ]; then
            mv *.bt2 "$index_folder"
            elif [ "$tophat" == 0 ] && [ "$star" != 0 ]; then
            mv star_index "$index_folder"
            rm *.tab *.out
            fi
      elif [ -z "$index_folder" ]; then
            if [ "$tophat" != 0 ] && [ "$star" == 0 ]; then
            mkdir index_folder
            mv *.bt2 index_folder && mv index_folder "$pipeline_output"
            elif [ "$tophat" == 0 ] && [ "$star" != 0 ]; then
            mkdir index_folder && mv star_index index_folder
            mv index_folder "$pipeline_output"
            rm *.tab *.out
            fi
      fi
      if [ "$transcript_abun_quant" != 0 ]; then
          mkdir featurecount && mv *_featurecount.txt* featurecount
          mkdir transcript_abund_quant && mv featurecount transcript_abund_quant
          mv transcript_abund_quant "$pipeline_output"
      fi
      if [ "$evolinc_i" != 0 ]; then
          rm *.loci *.stats *.tracking
          mv *_lincRNA* "$pipeline_output"
          mv *.gtf intermediate_files
      fi
      if [ "$HAMR" != 0 ]; then
          mv *_HAMR* "$pipeline_output"
          mv *.bai intermediate_files
          mv *.sam intermediate_files
          rm "$gname".dict
          if [ -e "./$gname.fa.fai" ]; then
          rm "$gname".fa.fai
          fi
      fi
      if [ "$tophat" != 0 ]; then
          mkdir mapped_files
          mv *_tophat* mapped_files
          mv mapped_files "$pipeline_output"
      fi
      mv *.bam intermediate_files
      mv intermediate_files "$pipeline_output"

      echo "##############################"
      echo "pipeline done"
      echo "##############################"
      date
}
	
##################################################################################################################
# # Transcript abundance quantification
###################################################################################################################

tophat_mapping_transcript_quantification()
{
      if [ "$transcript_abun_quant" != 0 ]; then
      echo "###########################################################################"
      echo "Running featureCounts to quantify transcript"
      echo "###########################################################################"    
            if [ "$evolinc_i" != 0 ]; then
                if [ "$seq_type" == "PE" ]; then
                echo "featureCounts -p -T $num_threads -t $feature_type -g $gene_attribute -s $strandedness -a ./${filename3}_lincRNA/${filename3}.lincRNA.updated.gtf -o ${filename3}_featurecount.txt ${filename3}_merged.bam"
                featureCounts -p -T $num_threads -a ./${filename3}_lincRNA/${filename3}.lincRNA.updated.gtf -o ${filename3}_featurecount.txt ${filename3}_merged.bam
                elif [ "$seq_type" == "SE" ]; then
                echo "featureCounts -T $num_threads -s $strandedness -a ./${filename}_lincRNA/${filename}.lincRNA.updated.gtf -o ${filename}_featurecount.txt ${filename}_sorted.bam"
                featureCounts -T $num_threads -s $strandedness -a ./${filename}_lincRNA/${filename}.lincRNA.updated.gtf -o ${filename}_featurecount.txt ${filename}_sorted.bam
                fi 
            elif [ "$evolinc_i" = 0 ]; then
                if [ "$seq_type" == "PE" ]; then
                echo "featureCounts -p -T $num_threads -t $feature_type -g $gene_attribute -s $strandedness -a $referenceannotation -o ${filename3}_featurecount.txt ${filename3}_merged.bam"
                featureCounts -p -T $num_threads -a $referenceannotation -o ${filename3}_featurecount.txt ${filename3}_merged.bam
                elif [ "$seq_type" == "SE" ]; then
                echo "featureCounts -T $num_threads -s $strandedness -a $referenceannotation -o ${filename}_featurecount.txt ${filename}_sorted.bam"
                featureCounts -T $num_threads -s $strandedness -a $referenceannotation -o ${filename}_featurecount.txt ${filename}_sorted.bam
                fi 
            fi
      fi
}

star_mapping_transcript_quantification()
{
      if [ "$transcript_abun_quant" != 0 ]; then
      echo "###########################################################################"
      echo "Running featureCounts to quantify transcript"
      echo "###########################################################################"    6
            if [ "$evolinc_i" != 0 ]; then
                if [ "$seq_type" == "PE" ]; then
                echo "featureCounts -p -T $num_threads -t $feature_type -g $gene_attribute -s $strandedness -a ./${filename3}_lincRNA/${filename3}.lincRNA.updated.gtf -o ${filename3}_featurecount.txt ${filename3}_Aligned.sortedByCoord.out.bam"
                featureCounts -p -T $num_threads -a ./${filename3}_lincRNA/${filename3}.lincRNA.updated.gtf -o ${filename3}_featurecount.txt ${filename3}_Aligned.sortedByCoord.out.bam
                elif [ "$seq_type" == "SE" ]; then
                echo "featureCounts -T $num_threads -s $strandedness -a ./${filename}_lincRNA/${filename}.lincRNA.updated.gtf -o ${filename}_featurecount.txt ${filename}_Aligned.sortedByCoord.out.bam"
                featureCounts -T $num_threads -s $strandedness -a ./${filename}_lincRNA/${filename}.lincRNA.updated.gtf -o ${filename}_featurecount.txt ${filename}_Aligned.sortedByCoord.out.bam
                fi
            elif [ "$evolinc_i" = 0 ]; then
                if [ "$seq_type" == "PE" ]; then
                echo "featureCounts -p -T $num_threads -t $feature_type -g $gene_attribute -s $strandedness -a $referenceannotation -o ${filename3}_featurecount.txt ${filename3}_Aligned.sortedByCoord.out.bam"
                featureCounts -p -T $num_threads -a $referenceannotation -o ${filename3}_featurecount.txt ${filename3}_Aligned.sortedByCoord.out.bam
                elif [ "$seq_type" == "SE" ]; then
                echo "featureCounts -T $num_threads -s $strandedness -a $referenceannotation -o ${filename}_featurecount.txt ${filename}_Aligned.sortedByCoord.out.bam"
                featureCounts -T $num_threads -s $strandedness -a $referenceannotation -o ${filename}_featurecount.txt ${filename}_Aligned.sortedByCoord.out.bam
                fi
            fi
      fi
}

sra_id_transcript_quantification()
{
      if [ "$transcript_abun_quant" != 0 ]; then
      echo "###########################################################################"
      echo "Running featureCounts to quantify transcript"
      echo "###########################################################################"    
            if [ "$evolinc_i" != 0 ]; then
                if [ "$seq_type" == "PE" ]; then
                echo "featureCounts -p -T $num_threads -t $feature_type -g $gene_attribute -s $strandedness -a ./${sra_id}_lincRNA/${sra_id}.lincRNA.updated.gtf -o ${sra_id}_featurecount.txt ${sra_id}_merged.bam"
                featureCounts -p -T $num_threads -a ./${sra_id}_lincRNA/${sra_id}.lincRNA.updated.gtf -o ${sra_id}_featurecount.txt ${sra_id}_merged.bam
                elif [ "$seq_type" == "SE" ]; then
                echo "featureCounts -T $num_threads -s $strandedness -a ./${sra_id}_lincRNA/${sra_id}.lincRNA.updated.gtf -o ${sra_id}_featurecount.txt ${sra_id}_sorted.bam"
                featureCounts -T $num_threads -s $strandedness -a ./${sra_id}_lincRNA/${sra_id}.lincRNA.updated.gtf -o ${sra_id}_featurecount.txt ${sra_id}_sorted.bam
                fi
            elif [ "$evolinc_i" = 0 ]; then
                if [ "$seq_type" == "PE" ]; then
                echo "featureCounts -p -T $num_threads -t $feature_type -g $gene_attribute -s $strandedness -a $referenceannotation -o ${sra_id}_featurecount.txt ${sra_id}_merged.bam"
                featureCounts -p -T $num_threads -a $referenceannotation -o ${sra_id}_featurecount.txt ${sra_id}_merged.bam
                elif [ "$seq_type" == "SE" ]; then
                echo "featureCounts -T $num_threads -s $strandedness -a $referenceannotation -o ${sra_id}_featurecount.txt ${sra_id}_sorted.bam"
                featureCounts -T $num_threads -s $strandedness -a $referenceannotation -o ${sra_id}_featurecount.txt ${sra_id}_sorted.bam
                fi
            fi
      fi
}

##################################################################################################################
# # lincRNA identification
###################################################################################################################

tophat_mapping_lincRNA_annotation()
{
      if [ "$evolinc_i" != 0 ]; then
      echo "###########################################################################"
      echo "Converting .bam file(s) containing uniquely mapped and sorted reads to .gtf"
      echo "###########################################################################"
            if [ "$seq_type" == "PE" ]; then
                if [ "$lib_type" == fr-secondstrand ]; then      
                echo "stringtie ${filename3}_merged.bam -o ${filename3}_merged.gtf -G $referenceannotation -p $num_threads --fr"
                stringtie ${filename3}_merged.bam -o ${filename3}_merged.gtf -G $referenceannotation -p $num_threads --fr
                echo "cuffcompare ${filename3}_merged.gtf -r $referenceannotation -s $referencegenome -T -o ${filename3}"
                cuffcompare ${filename3}_merged.gtf -r $referenceannotation -s $referencegenome -T -o ${filename3}
                echo "evolinc-part-I.sh -c ./${filename3}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename3}_lincRNA -b $blast_file -t $cage_file -x $known_linc"
                evolinc-part-I.sh -c ./${filename3}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename3}_lincRNA -b $blast_file -t $cage_file -x $known_linc
                elif [ "$lib_type" == fr-firststrand ]; then
                echo "stringtie ${filename3}_merged.bam -o ${filename3}_merged.gtf -G $referenceannotation -p $num_threads --rf"
                stringtie ${filename3}_merged.bam -o ${filename3}_merged.gtf -G $referenceannotation -p $num_threads --rf
                echo "cuffcompare ${filename3}_merged.gtf -r $referenceannotation -s $referencegenome -T -o ${filename3}"
                cuffcompare ${filename3}_merged.gtf -r $referenceannotation -s $referencegenome -T -o ${filename3}
                echo "evolinc-part-I.sh -c ./${filename3}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename3}_lincRNA -b $blast_file -t $cage_file -x $known_linc"
                evolinc-part-I.sh -c ./${filename3}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename3}_lincRNA -b $blast_file -t $cage_file -x $known_linc
                fi   
            elif [ "$seq_type" == "SE" ]; then
                if [ "$lib_type" == fr-secondstrand ]; then      
                echo "stringtie ${filename}_sorted.bam -o ${filename}.gtf -G $referenceannotation -p $num_threads --fr"
                stringtie ${filename}_sorted.bam -o ${filename}.gtf -G $referenceannotation -p $num_threads --fr
                echo "cuffcompare ${filename}.gtf -r $referenceannotation -s $referencegenome -T -o ${filename}"
                cuffcompare ${filename}.gtf -r $referenceannotation -s $referencegenome -T -o ${filename}
                echo "evolinc-part-I.sh -c ./${filename}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename}_lincRNA -b $blast_file -t $cage_file -x $known_linc"
                evolinc-part-I.sh -c ./${filename}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename}_lincRNA -b $blast_file -t $cage_file -x $known_linc
                elif [ "$lib_type" == fr-firststrand ]; then
                echo "stringtie ${filename}_sorted.bam -o ${filename}.gtf -G $referenceannotation -p $num_threads --rf"
                stringtie ${filename}_sorted.bam -o ${filename}.gtf -G $referenceannotation -p $num_threads --rf
                echo "cuffcompare ${filename}.gtf -r $referenceannotation -s $referencegenome -T -o ${filename}"
                cuffcompare ${filename}.gtf -r $referenceannotation -s $referencegenome -T -o ${filename}
                echo "evolinc-part-I.sh -c ./${filename}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename}_lincRNA -b $blast_file -t $cage_file -x $known_linc"
                evolinc-part-I.sh -c ./${filename}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename}_lincRNA -b $blast_file -t $cage_file -x $known_linc
                fi
            fi
      fi
}

star_mapping_lincRNA_annotation()
{
      if [ "$evolinc_i" != 0 ]; then
      echo "###########################################################################"
      echo "Converting .bam file(s) containing uniquely mapped and sorted reads to .gtf"
      echo "###########################################################################"
            if [ "$seq_type" == "PE" ]; then
                if [ "$lib_type" == fr-secondstrand ]; then      
                echo "stringtie ${filename3}_Aligned.sortedByCoord.out.bam -o ${filename3}.gtf -G $referenceannotation -p $num_threads --fr"
                stringtie ${filename3}_Aligned.sortedByCoord.out.bam -o ${filename3}.gtf -G $referenceannotation -p $num_threads --fr
                echo "cuffcompare ${filename3}.gtf -r $referenceannotation -s $referencegenome -T -o ${filename3}"
                cuffcompare ${filename3}.gtf -r $referenceannotation -s $referencegenome -T -o ${filename3}
                echo "evolinc-part-I.sh -c ./${filename3}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename3}_lincRNA -b $blast_file -t $cage_file -x $known_linc"
                evolinc-part-I.sh -c ./${filename3}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename3}_lincRNA -b $blast_file -t $cage_file -x $known_linc
                elif [ "$lib_type" == fr-firststrand ]; then
                echo "stringtie ${filename3}_Aligned.sortedByCoord.out.bam -o ${filename3}.gtf -G $referenceannotation -p $num_threads --rf"
                stringtie ${filename3}_Aligned.sortedByCoord.out.bam -o ${filename3}.gtf -G $referenceannotation -p $num_threads --rf
                echo "cuffcompare ${filename3}.gtf -r $referenceannotation -s $referencegenome -T -o ${filename3}"
                cuffcompare ${filename3}.gtf -r $referenceannotation -s $referencegenome -T -o ${filename3}
                echo "evolinc-part-I.sh -c ./${filename3}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename3}_lincRNA -b $blast_file -t $cage_file -x $known_linc"
                evolinc-part-I.sh -c ./${filename3}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename3}_lincRNA -b $blast_file -t $cage_file -x $known_linc
                fi   
            elif [ "$seq_type" == "SE" ]; then
                if [ "$lib_type" == fr-secondstrand ]; then      
                echo "stringtie ${filename}_Aligned.sortedByCoord.out.bam -o ${filename}.gtf -G $referenceannotation -p $num_threads --fr"
                stringtie ${filename}_Aligned.sortedByCoord.out.bam -o ${filename}.gtf -G $referenceannotation -p $num_threads --fr
                echo "cuffcompare ${filename}.gtf -r $referenceannotation -s $referencegenome -T -o ${filename}"
                cuffcompare ${filename}.gtf -r $referenceannotation -s $referencegenome -T -o ${filename}
                echo "evolinc-part-I.sh -c ./${filename}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename}_lincRNA -b $blast_file -t $cage_file -x $known_linc"
                evolinc-part-I.sh -c ./${filename}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename}_lincRNA -b $blast_file -t $cage_file -x $known_linc
                elif [ "$lib_type" == fr-firststrand ]; then
                echo "stringtie ${filename}_Aligned.sortedByCoord.out.bam -o ${filename}.gtf -G $referenceannotation -p $num_threads --rf"
                stringtie ${filename}_Aligned.sortedByCoord.out.bam -o ${filename}.gtf -G $referenceannotation -p $num_threads --rf
                echo "cuffcompare ${filename}.gtf -r $referenceannotation -s $referencegenome -T -o ${filename}"
                cuffcompare ${filename}.gtf -r $referenceannotation -s $referencegenome -T -o ${filename}
                echo "evolinc-part-I.sh -c ./${filename}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename}_lincRNA -b $blast_file -t $cage_file -x $known_linc"
                evolinc-part-I.sh -c ./${filename}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${filename}_lincRNA -b $blast_file -t $cage_file -x $known_linc
                fi
            fi
      fi
}

sra_id_lincRNA_annotation()
{
      if [ "$evolinc_i" != 0 ]; then
      echo "###########################################################################"
      echo "Converting .bam file(s) containing uniquely mapped and sorted reads to .gtf"
      echo "###########################################################################"
            if [ "$seq_type" == "PE" ]; then
                if [ "$lib_type" == fr-secondstrand ]; then      
                echo "stringtie ${sra_id}_merged.bam -o ${sra_id}_merged.gtf -G $referenceannotation -p $num_threads --fr"
                stringtie ${sra_id}_merged.bam -o ${sra_id}_merged.gtf -G $referenceannotation -p $num_threads --fr
                echo "cuffcompare ${sra_id}_merged.gtf -r $referenceannotation -s $referencegenome -T -o ${sra_id}"
                cuffcompare ${sra_id}_merged.gtf -r $referenceannotation -s $referencegenome -T -o ${sra_id}
                echo "evolinc-part-I.sh -c ./${sra_id}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${sra_id}_lincRNA -b $blast_file -t $cage_file -x $known_linc"
                evolinc-part-I.sh -c ./${sra_id}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${sra_id}_lincRNA -b $blast_file -t $cage_file -x $known_linc
                elif [ "$lib_type" == fr-firststrand ]; then
                echo "stringtie ${sra_id}_merged.bam -o ${sra_id}_merged.gtf -G $referenceannotation -p $num_threads --rf"
                stringtie ${sra_id}_merged.bam -o ${sra_id}_merged.gtf -G $referenceannotation -p $num_threads --rf
                echo "cuffcompare ${sra_id}_merged.gtf -r $referenceannotation -s $referencegenome -T -o ${sra_id}"
                cuffcompare ${sra_id}_merged.gtf -r $referenceannotation -s $referencegenome -T -o ${sra_id}
                echo "evolinc-part-I.sh -c ./${sra_id}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${sra_id}_lincRNA -b $blast_file -t $cage_file -x $known_linc"
                evolinc-part-I.sh -c ./${sra_id}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${sra_id}_lincRNA -b $blast_file -t $cage_file -x $known_linc
                fi     
            elif [ "$seq_type" == "SE" ]; then
                if [ "$lib_type" == fr-secondstrand ]; then      
                echo "stringtie ${sra_id}_sorted.bam -o ${sra_id}.gtf -G $referenceannotation -p $num_threads --fr"
                stringtie ${sra_id}_sorted.bam -o ${sra_id}.gtf -G $referenceannotation -p $num_threads --fr
                echo "cuffcompare ${sra_id}.gtf -r $referenceannotation -s $referencegenome -T -o ${sra_id}"
                cuffcompare ${sra_id}.gtf -r $referenceannotation -s $referencegenome -T -o ${sra_id}
                echo "evolinc-part-I.sh -c ./${sra_id}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${sra_id}_lincRNA -b $blast_file -t $cage_file -x $known_linc"
                evolinc-part-I.sh -c ./${sra_id}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${sra_id}_lincRNA -b $blast_file -t $cage_file -x $known_linc
                elif [ "$lib_type" == fr-firststrand ]; then
                echo "stringtie ${sra_id}_sorted.bam -o ${sra_id}.gtf -G $referenceannotation -p $num_threads --rf"
                stringtie ${sra_id}_sorted.bam -o ${sra_id}.gtf -G $referenceannotation -p $num_threads --rf
                echo "cuffcompare ${sra_id}.gtf -r $referenceannotation -s $referencegenome -T -o ${sra_id}"
                cuffcompare ${sra_id}.gtf -r $referenceannotation -s $referencegenome -T -o ${sra_id}
                echo "evolinc-part-I.sh -c ./${sra_id}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${sra_id}_lincRNA -b $blast_file -t $cage_file -x $known_linc"
                evolinc-part-I.sh -c ./${sra_id}.combined.gtf -g ./$referencegenome -u ./$referenceannotation -r ./$referenceannotation -n $num_threads -o ./${sra_id}_lincRNA -b $blast_file -t $cage_file -x $known_linc
                fi
            fi
      fi
}

############################################################################################################################################################################################################################
# # Trimmming, Mapping, Grepping unique reads, Resolving spliced alignment and RNA modification annotation
############################################################################################################################################################################################################################

# Paired end reads

paired_fq_gz()
{
    filename=$(basename "$f" ".fq.gz")
    filename2=${filename/_R1/_R2}
    filename3=$(echo $filename | sed 's/_R1//')
          
          if [ "$seq_type" == "PE" ]; then
          echo "###############################"
          echo "Trimming paired-end input reads"
          echo "###############################"
          fi
          if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                echo "trimmomatic PE -threads $num_threads ${filename}.fq.gz ${filename2}.fq.gz ${filename3}_1P.fq.gz ${filename3}_1U.fq.gz ${filename3}_2P.fq.gz ${filename3}_2U.fq.gz ILLUMINACLIP:$ADAPTERPATH/TruSeq3-PE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36"
                trimmomatic PE -threads $num_threads ${filename}.fq.gz ${filename2}.fq.gz ${filename3}_1P.fq.gz ${filename3}_1U.fq.gz ${filename3}_2P.fq.gz ${filename3}_2U.fq.gz ILLUMINACLIP:$ADAPTERPATH/TruSeq3-PE.fa:2:30:10:2 LEADING:3 TRAILING:3 MINLEN:36
          elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                  echo "fastp -w $num_threads -i ${filename}.fq.gz -I ${filename2}.fq.gz -o ${filename3}_trimmed_R1.fq.gz -O ${filename3}_trimmed_R2.fq.gz -j ${filename3}_fastp.json -h ${filename3}_fastp.html"
                  fastp -w $num_threads -i ${filename}.fq.gz -I ${filename2}.fq.gz -o ${filename3}_trimmed_R1.fq.gz -O ${filename3}_trimmed_R2.fq.gz -j ${filename3}_fastp.json -h ${filename3}_fastp.html
          fi

          if [ "$tophat" != 0 ] && [ "$star" == 0 ]; then
          echo "###################################"
          echo "Running tophat2 in paired end mode"
          echo "###################################"
                if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                      echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_1P.fq.gz,${filename3}_1U.fq.gz"
                      tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_1P.fq.gz,${filename3}_1U.fq.gz
                      echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_2P.fq.gz"
                      tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_2P.fq.gz
                      
                elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                        echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R1.fq.gz"
                        tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R1.fq.gz
                        echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R2.fq.gz"
                        tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R2.fq.gz
                fi

          echo "########################"
          echo "Converting .bam to .sam"
          echo "########################"
          echo "samtools view -h -@ $num_threads -o ${filename3}_fwd.sam ${filename3}_fwd_tophat/accepted_hits.bam"
          samtools view -h -@ $num_threads -o ${filename3}_fwd.sam ${filename3}_fwd_tophat/accepted_hits.bam
          echo "samtools view -h -o ${filename3}_rev.sam ${filename3}_rev_tophat/accepted_hits.bam"
          samtools view -h -o ${filename3}_rev.sam ${filename3}_rev_tophat/accepted_hits.bam
         
          echo "#######################"
          echo "Grepping unique reads"
          echo "#######################"
          echo "grep -P '^\@|NH:i:1$' ${filename3}_fwd.sam > ${filename3}_fwd_unique.sam"
          grep -P '^\@|NH:i:1$' ${filename3}_fwd.sam > ${filename3}_fwd_unique.sam
          echo "grep -P '^\@|NH:i:1$' ${filename3}_rev.sam > ${filename3}_rev_unique.sam"
          grep -P '^\@|NH:i:1$' ${filename3}_rev.sam > ${filename3}_rev_unique.sam
         
          echo "######################################################"
          echo "Converting .sam to .bam before running samtools sort"
          echo "######################################################"
          echo "samtools view -bSh -@ $num_threads ${filename3}_fwd_unique.sam > ${filename3}_fwd_unique.bam"
          samtools view -bSh -@ $num_threads ${filename3}_fwd_unique.sam > ${filename3}_fwd_unique.bam
          echo "samtools view -bSh -@ $num_threads ${filename3}_rev_unique.sam > ${filename3}_rev_unique.bam"
          samtools view -bSh -@ $num_threads ${filename3}_rev_unique.sam > ${filename3}_rev_unique.bam
         
          echo "#######################"
          echo "Sorting unique reads"
          echo "#######################"
          echo "samtools sort -@ $num_threads ${filename3}_fwd_unique.bam > ${filename3}_fwd_sorted.bam"
          samtools sort -@ $num_threads ${filename3}_fwd_unique.bam > ${filename3}_fwd_sorted.bam
          echo "samtools sort -@ $num_threads ${filename3}_rev_unique.bam > ${filename3}_rev_sorted.bam"
          samtools sort -@ $num_threads ${filename3}_rev_unique.bam > ${filename3}_rev_sorted.bam
         
          echo "########################"
          echo "Merging fwd and rev reads"
          echo "########################"
          echo "samtools merge -@ $num_threads -f ${filename3}_merged.bam ${filename3}_fwd_sorted.bam ${filename3}_rev_sorted.bam"
          samtools merge -@ $num_threads -f ${filename3}_merged.bam ${filename3}_fwd_sorted.bam ${filename3}_rev_sorted.bam
          
          if [ "$HAMR" != 0 ]; then
          echo "######################################################"
          echo "Resolving spliced alignments"
          echo "######################################################"
          echo "picard AddOrReplaceReadGroups I=${filename3}_merged.bam O=${filename3}_RG.bam ID=${filename3} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${filename3}"
          picard AddOrReplaceReadGroups I=${filename3}_merged.bam O=${filename3}_RG.bam ID=${filename3} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${filename3}
          echo "picard ReorderSam I=${filename3}_RG.bam O=${filename3}_RGO.bam R=$referencegenome"
          picard ReorderSam I=${filename3}_RG.bam O=${filename3}_RGO.bam R=$referencegenome
          echo "samtools index ${filename3}_RGO.bam ${filename3}_RGO.bam.bai"
          samtools index ${filename3}_RGO.bam ${filename3}_RGO.bam.bai
          echo " gatk --java-options "-Xmx8g" SplitNCigarReads -R $referencegenome -I ${filename3}_RGO.bam -O ${filename3}_resolvedalig.bam -OBI false"
          gatk --java-options "-Xmx8g" SplitNCigarReads -R $referencegenome -I ${filename3}_RGO.bam -O ${filename3}_resolvedalig.bam -OBI false
          
          echo "######################################################"
          echo "Running HAMR"
          echo "######################################################"
          echo "python hamr.py -fe ${filename3}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${filename3}_HAMR ${filename3} 30 10 0.01 H4 1 .05 .05"
          python /HAMR/hamr.py -fe ${filename3}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${filename3}_HAMR ${filename3} 30 10 0.01 H4 1 .05 .05
          fi
          tophat_mapping_lincRNA_annotation
          tophat_mapping_transcript_quantification
          fi
          
          if [ "$tophat" == 0 ] && [ "$star" != 0 ]; then
          echo "###################################"
          echo "Running STAR in paired end mode"
          echo "###################################"
              if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                    echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_1P.fq.gz ${filename3}_2P.fq.gz"
                    STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_1P.fq.gz ${filename3}_2P.fq.gz
              elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                      echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_trimmed_R1.fq.gz ${filename3}_trimmed_R2.fq.gz"
                      STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_trimmed_R1.fq.gz ${filename3}_trimmed_R2.fq.gz
              fi
              star_mapping_lincRNA_annotation
              star_mapping_transcript_quantification
          fi
          house_keeping
}

paired_fastq_gz()
{
    filename=$(basename "$f" ".fastq.gz")
    filename2=${filename/_R1/_R2}
    filename3=$(echo $filename | sed 's/_R1//')
          
          if [ "$seq_type" == "PE" ]; then
          echo "###############################"
          echo "Trimming paired-end input reads"
          echo "###############################"
          fi
          if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                echo "trimmomatic PE -threads $num_threads ${filename}.fastq.gz ${filename2}.fastq.gz ${filename3}_1P.fastq.gz ${filename3}_1U.fastq.gz ${filename3}_2P.fastq.gz ${filename3}_2U.fastq.gz ILLUMINACLIP:$ADAPTERPATH/TruSeq3-PE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36"
                trimmomatic PE -threads $num_threads ${filename}.fastq.gz ${filename2}.fastq.gz ${filename3}_1P.fastq.gz ${filename3}_1U.fastq.gz ${filename3}_2P.fastq.gz ${filename3}_2U.fastq.gz ILLUMINACLIP:$ADAPTERPATH/TruSeq3-PE.fa:2:30:10:2 LEADING:3 TRAILING:3 MINLEN:36
          elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                  echo "fastp -w $num_threads -i ${filename}.fastq.gz -I ${filename2}.fastq.gz -o ${filename3}_trimmed_R1.fastq.gz -O ${filename3}_trimmed_R2.fastq.gz -j ${filename3}_fastp.json -h ${filename3}_fastp.html"
                  fastp -w $num_threads -i ${filename}.fastq.gz -I ${filename2}.fastq.gz -o ${filename3}_trimmed_R1.fastq.gz -O ${filename3}_trimmed_R2.fastq.gz -j ${filename3}_fastp.json -h ${filename3}_fastp.html
          fi

          if [ "$tophat" != 0 ] && [ "$star" == 0 ]; then
          echo "###################################"
          echo "Running tophat2 in paired end mode"
          echo "###################################"
                if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                      echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_1P.fastq.gz,${filename3}_1U.fastq.gz"
                      tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_1P.fastq.gz,${filename3}_1U.fastq.gz
                      echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_2P.fastq.gz"
                      tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_2P.fastq.gz
                      
                elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                        echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R1.fastq.gz"
                        tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R1.fastq.gz
                        echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R2.fastq.gz"
                        tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R2.fastq.gz
                fi

          echo "########################"
          echo "Converting .bam to .sam"
          echo "########################"
          echo "samtools view -h -@ $num_threads -o ${filename3}_fwd.sam ${filename3}_fwd_tophat/accepted_hits.bam"
          samtools view -h -@ $num_threads -o ${filename3}_fwd.sam ${filename3}_fwd_tophat/accepted_hits.bam
          echo "samtools view -h -o ${filename3}_rev.sam ${filename3}_rev_tophat/accepted_hits.bam"
          samtools view -h -o ${filename3}_rev.sam ${filename3}_rev_tophat/accepted_hits.bam
         
          echo "#######################"
          echo "Grepping unique reads"
          echo "#######################"
          echo "grep -P '^\@|NH:i:1$' ${filename3}_fwd.sam > ${filename3}_fwd_unique.sam"
          grep -P '^\@|NH:i:1$' ${filename3}_fwd.sam > ${filename3}_fwd_unique.sam
          echo "grep -P '^\@|NH:i:1$' ${filename3}_rev.sam > ${filename3}_rev_unique.sam"
          grep -P '^\@|NH:i:1$' ${filename3}_rev.sam > ${filename3}_rev_unique.sam
         
          echo "######################################################"
          echo "Converting .sam to .bam before running samtools sort"
          echo "######################################################"
          echo "samtools view -bSh -@ $num_threads ${filename3}_fwd_unique.sam > ${filename3}_fwd_unique.bam"
          samtools view -bSh -@ $num_threads ${filename3}_fwd_unique.sam > ${filename3}_fwd_unique.bam
          echo "samtools view -bSh -@ $num_threads ${filename3}_rev_unique.sam > ${filename3}_rev_unique.bam"
          samtools view -bSh -@ $num_threads ${filename3}_rev_unique.sam > ${filename3}_rev_unique.bam
         
          echo "#######################"
          echo "Sorting unique reads"
          echo "#######################"
          echo "samtools sort -@ $num_threads ${filename3}_fwd_unique.bam > ${filename3}_fwd_sorted.bam"
          samtools sort -@ $num_threads ${filename3}_fwd_unique.bam > ${filename3}_fwd_sorted.bam
          echo "samtools sort -@ $num_threads ${filename3}_rev_unique.bam > ${filename3}_rev_sorted.bam"
          samtools sort -@ $num_threads ${filename3}_rev_unique.bam > ${filename3}_rev_sorted.bam
         
          echo "########################"
          echo "Merging fwd and rev reads"
          echo "########################"
          echo "samtools merge -@ $num_threads -f ${filename3}_merged.bam ${filename3}_fwd_sorted.bam ${filename3}_rev_sorted.bam"
          samtools merge -@ $num_threads -f ${filename3}_merged.bam ${filename3}_fwd_sorted.bam ${filename3}_rev_sorted.bam
          
          if [ "$HAMR" != 0 ]; then
          echo "######################################################"
          echo "Resolving spliced alignments"
          echo "######################################################"
          echo "picard AddOrReplaceReadGroups I=${filename3}_merged.bam O=${filename3}_RG.bam ID=${filename3} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${filename3}"
          picard AddOrReplaceReadGroups I=${filename3}_merged.bam O=${filename3}_RG.bam ID=${filename3} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${filename3}
          echo "picard ReorderSam I=${filename3}_RG.bam O=${filename3}_RGO.bam R=$referencegenome"
          picard ReorderSam I=${filename3}_RG.bam O=${filename3}_RGO.bam R=$referencegenome
          echo "samtools index ${filename3}_RGO.bam ${filename3}_RGO.bam.bai"
          samtools index ${filename3}_RGO.bam ${filename3}_RGO.bam.bai
          echo "java -Xmx8g -jar gatk SplitNCigarReads -R $referencegenome -I ${filename3}_RGO.bam -O ${filename3}_resolvedalig.bam -OBI false"
          gatk --java-options "-Xmx8g" SplitNCigarReads -R $referencegenome -I ${filename3}_RGO.bam -O ${filename3}_resolvedalig.bam -OBI false
          
          echo "######################################################"
          echo "Running HAMR"
          echo "######################################################"
          
          echo "python hamr.py -fe ${filename3}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${filename3}_HAMR ${filename3} 30 10 0.01 H4 1 .05 .05"
          python /HAMR/hamr.py -fe ${filename3}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${filename3}_HAMR ${filename3} 30 10 0.01 H4 1 .05 .05
          fi
          tophat_mapping_lincRNA_annotation
          tophat_mapping_transcript_quantification
          fi

          if [ "$tophat" == 0 ] && [ "$star" != 0 ]; then
          echo "###################################"
          echo "Running STAR in paired end mode"
          echo "###################################"
              if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                    echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_1P.fastq.gz ${filename3}_2P.fastq.gz"
                    STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_1P.fastq.gz ${filename3}_2P.fastq.gz
              elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                      echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_trimmed_R1.fastq.gz ${filename3}_trimmed_R2.fastq.gz"
                      STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_trimmed_R1.fastq.gz ${filename3}_trimmed_R2.fastq.gz
              fi
              star_mapping_lincRNA_annotation
              star_mapping_transcript_quantification
          fi
          house_keeping
}
paired_fq()
{
    filename=$(basename "$f" ".fq")
    filename2=${filename/_R1/_R2}
    filename3=$(echo $filename | sed 's/_R1//')

          if [ "$seq_type" == "PE" ]; then
          echo "###############################"
          echo "Trimming paired-end input reads"
          echo "###############################"
          fi
          if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                echo "trimmomatic PE -threads $num_threads ${filename}.fq ${filename2}.fq ${filename3}_1P.fq ${filename3}_1U.fq ${filename3}_2P.fq ${filename3}_2U.fq ILLUMINACLIP:$ADAPTERPATH/TruSeq3-PE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36"
                trimmomatic PE -threads $num_threads ${filename}.fq ${filename2}.fq ${filename3}_1P.fq ${filename3}_1U.fq ${filename3}_2P.fq ${filename3}_2U.fq ILLUMINACLIP:$ADAPTERPATH/TruSeq3-PE.fa:2:30:10:2 LEADING:3 TRAILING:3 MINLEN:36
          elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                  echo "fastp -w $num_threads -i ${filename}.fq -I ${filename2}.fq -o ${filename3}_trimmed_R1.fq -O ${filename3}_trimmed_R2.fq -j ${filename3}_fastp.json -h ${filename3}_fastp.html"
                  fastp -w $num_threads -i ${filename}.fq -I ${filename2}.fq -o ${filename3}_trimmed_R1.fq -O ${filename3}_trimmed_R2.fq -j ${filename3}_fastp.json -h ${filename3}_fastp.html
          fi

          if [ "$tophat" != 0 ] && [ "$star" == 0 ]; then
          echo "###################################"
          echo "Running tophat2 in paired end mode"
          echo "###################################"
                if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                      echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_1P.fq,${filename3}_1U.fq"
                      tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_1P.fq,${filename3}_1U.fq
                      echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_2P.fq"
                      tophat2-p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_2P.fq
                      
                elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                        echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R1.fq"
                        tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R1.fq
                        echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R2.fq"
                        tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R2.fq
                fi

          echo "########################"
          echo "Converting .bam to .sam"
          echo "########################"
          echo "samtools view -h -@ $num_threads -o ${filename3}_fwd.sam ${filename3}_fwd_tophat/accepted_hits.bam"
          samtools view -h -@ $num_threads -o ${filename3}_fwd.sam ${filename3}_fwd_tophat/accepted_hits.bam
          echo "samtools view -h -o ${filename3}_rev.sam ${filename3}_rev_tophat/accepted_hits.bam"
          samtools view -h -o ${filename3}_rev.sam ${filename3}_rev_tophat/accepted_hits.bam
         
          echo "#######################"
          echo "Grepping unique reads"
          echo "#######################"
          echo "grep -P '^\@|NH:i:1$' ${filename3}_fwd.sam > ${filename3}_fwd_unique.sam"
          grep -P '^\@|NH:i:1$' ${filename3}_fwd.sam > ${filename3}_fwd_unique.sam
          echo "grep -P '^\@|NH:i:1$' ${filename3}_rev.sam > ${filename3}_rev_unique.sam"
          grep -P '^\@|NH:i:1$' ${filename3}_rev.sam > ${filename3}_rev_unique.sam
         
          echo "######################################################"
          echo "Converting .sam to .bam before running samtools sort"
          echo "######################################################"
          echo "samtools view -bSh -@ $num_threads ${filename3}_fwd_unique.sam > ${filename3}_fwd_unique.bam"
          samtools view -bSh -@ $num_threads ${filename3}_fwd_unique.sam > ${filename3}_fwd_unique.bam
          echo "samtools view -bSh -@ $num_threads ${filename3}_rev_unique.sam > ${filename3}_rev_unique.bam"
          samtools view -bSh -@ $num_threads ${filename3}_rev_unique.sam > ${filename3}_rev_unique.bam
         
          echo "#######################"
          echo "Sorting unique reads"
          echo "#######################"
          echo "samtools sort -@ $num_threads ${filename3}_fwd_unique.bam > ${filename3}_fwd_sorted.bam"
          samtools sort -@ $num_threads ${filename3}_fwd_unique.bam > ${filename3}_fwd_sorted.bam
          echo "samtools sort -@ $num_threads ${filename3}_rev_unique.bam > ${filename3}_rev_sorted.bam"
          samtools sort -@ $num_threads ${filename3}_rev_unique.bam > ${filename3}_rev_sorted.bam
         
          echo "########################"
          echo "Merging fwd and rev reads"
          echo "########################"
          echo "samtools merge -@ $num_threads -f ${filename3}_merged.bam ${filename3}_fwd_sorted.bam ${filename3}_rev_sorted.bam"
          samtools merge -@ $num_threads -f ${filename3}_merged.bam ${filename3}_fwd_sorted.bam ${filename3}_rev_sorted.bam

          if [ "$HAMR" != 0 ]; then
          echo "######################################################"
          echo "Resolving spliced alignments"
          echo "######################################################"
          echo "picard AddOrReplaceReadGroups I=${filename3}_merged.bam O=${filename3}_RG.bam ID=${filename3} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${filename3}"
          picard AddOrReplaceReadGroups I=${filename3}_merged.bam O=${filename3}_RG.bam ID=${filename3} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${filename3}
          echo "picard ReorderSam I=${filename3}_RG.bam O=${filename3}_RGO.bam R=$referencegenome"
          picard ReorderSam I=${filename3}_RG.bam O=${filename3}_RGO.bam R=$referencegenome
          echo "samtools index ${filename3}_RGO.bam ${filename3}_RGO.bam.bai"
          samtools index ${filename3}_RGO.bam ${filename3}_RGO.bam.bai
          echo " gatk --java-options "-Xmx8g" SplitNCigarReads -R $referencegenome -I ${filename3}_RGO.bam -O ${filename3}_resolvedalig.bam -OBI false"
          gatk --java-options "-Xmx8g" SplitNCigarReads -R $referencegenome -I ${filename3}_RGO.bam -O ${filename3}_resolvedalig.bam -OBI false
          
          echo "######################################################"
          echo "Running HAMR"
          echo "######################################################"
          echo "python hamr.py -fe ${filename3}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${filename3}_HAMR ${filename3} 30 10 0.01 H4 1 .05 .05"
          python /HAMR/hamr.py -fe ${filename3}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${filename3}_HAMR ${filename3} 30 10 0.01 H4 1 .05 .05
          fi
          tophat_mapping_lincRNA_annotation
          tophat_mapping_transcript_quantification
          fi

          if [ "$tophat" == 0 ] && [ "$star" != 0 ]; then
          echo "###################################"
          echo "Running STAR in paired end mode"
          echo "###################################"
              if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                    echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_1P.fq ${filename3}_2P.fq"
                    STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_1P.fq ${filename3}_2P.fq
              elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                      echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_trimmed_R1.fq ${filename3}_trimmed_R2.fq"
                      STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_trimmed_R1.fq ${filename3}_trimmed_R2.fq
              fi
              star_mapping_lincRNA_annotation
              star_mapping_transcript_quantification
          fi
          house_keeping
}

paired_fastq()
{
    filename=$(basename "$f" ".fastq")
    filename2=${filename/_R1/_R2}
    filename3=$(echo $filename | sed 's/_R1//')

          if [ "$seq_type" == "PE" ]; then
          echo "###############################"
          echo "Trimming paired-end input reads"
          echo "###############################"
          fi
          if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                echo "trimmomatic PE -threads $num_threads ${filename}.fastq ${filename2}.fastq ${filename3}_1P.fastq ${filename3}_1U.fastq ${filename3}_2P.fastq ${filename3}_2U.fastq ILLUMINACLIP:$ADAPTERPATH/TruSeq3-PE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36"
                trimmomatic PE -threads $num_threads ${filename}.fastq ${filename2}.fastq ${filename3}_1P.fastq ${filename3}_1U.fastq ${filename3}_2P.fastq ${filename3}_2U.fastq ILLUMINACLIP:$ADAPTERPATH/TruSeq3-PE.fa:2:30:10:2 LEADING:3 TRAILING:3 MINLEN:36
          elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                  echo "fastp -w $num_threads -i ${filename}.fastq -I ${filename2}.fastq -o ${filename3}_trimmed_R1.fastq -O ${filename3}_trimmed_R2.fastq -j ${filename3}_fastp.json -h ${filename3}_fastp.html"
                  fastp -w $num_threads -i ${filename}.fastq -I ${filename2}.fastq -o ${filename3}_trimmed_R1.fastq -O ${filename3}_trimmed_R2.fastq -j ${filename3}_fastp.json -h ${filename3}_fastp.html
          fi

          if [ "$tophat" != 0 ] && [ "$star" == 0 ]; then
          echo "###################################"
          echo "Running tophat2 in paired end mode"
          echo "###################################"
                if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                      echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_1P.fastq,${filename3}_1U.fastq"
                      tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_1P.fastq,${filename3}_1U.fastq
                      echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_2P.fastq"
                      tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_2P.fastq
                      
                elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                        echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R1.fastq"
                        tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_fwd_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R1.fastq
                        echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R2.fastq"
                        tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename3}_rev_tophat -G $referenceannotation $fbname ${filename3}_trimmed_R2.fastq
                fi

          echo "########################"
          echo "Converting .bam to .sam"
          echo "########################"
          echo "samtools view -h -@ $num_threads -o ${filename3}_fwd.sam ${filename3}_fwd_tophat/accepted_hits.bam"
          samtools view -h -@ $num_threads -o ${filename3}_fwd.sam ${filename3}_fwd_tophat/accepted_hits.bam
          echo "samtools view -h -o ${filename3}_rev.sam ${filename3}_rev_tophat/accepted_hits.bam"
          samtools view -h -o ${filename3}_rev.sam ${filename3}_rev_tophat/accepted_hits.bam
         
          echo "#######################"
          echo "Grepping unique reads"
          echo "#######################"
          echo "grep -P '^\@|NH:i:1$' ${filename3}_fwd.sam > ${filename3}_fwd_unique.sam"
          grep -P '^\@|NH:i:1$' ${filename3}_fwd.sam > ${filename3}_fwd_unique.sam
          echo "grep -P '^\@|NH:i:1$' ${filename3}_rev.sam > ${filename3}_rev_unique.sam"
          grep -P '^\@|NH:i:1$' ${filename3}_rev.sam > ${filename3}_rev_unique.sam
         
          echo "######################################################"
          echo "Converting .sam to .bam before running samtools sort"
          echo "######################################################"
          echo "samtools view -bSh -@ $num_threads ${filename3}_fwd_unique.sam > ${filename3}_fwd_unique.bam"
          samtools view -bSh -@ $num_threads ${filename3}_fwd_unique.sam > ${filename3}_fwd_unique.bam
          echo "samtools view -bSh -@ $num_threads ${filename3}_rev_unique.sam > ${filename3}_rev_unique.bam"
          samtools view -bSh -@ $num_threads ${filename3}_rev_unique.sam > ${filename3}_rev_unique.bam
         
          echo "#######################"
          echo "Sorting unique reads"
          echo "#######################"
          echo "samtools sort -@ $num_threads ${filename3}_fwd_unique.bam > ${filename3}_fwd_sorted.bam"
          samtools sort -@ $num_threads ${filename3}_fwd_unique.bam > ${filename3}_fwd_sorted.bam
          echo "samtools sort -@ $num_threads ${filename3}_rev_unique.bam > ${filename3}_rev_sorted.bam"
          samtools sort -@ $num_threads ${filename3}_rev_unique.bam > ${filename3}_rev_sorted.bam
         
          echo "########################"
          echo "Merging fwd and rev reads"
          echo "########################"
          echo "samtools merge -@ $num_threads -f ${filename3}_merged.bam ${filename3}_fwd_sorted.bam ${filename3}_rev_sorted.bam"
          samtools merge -@ $num_threads -f ${filename3}_merged.bam ${filename3}_fwd_sorted.bam ${filename3}_rev_sorted.bam

          if [ "$HAMR" != 0 ]; then
          echo "######################################################"
          echo "Resolving spliced alignments"
          echo "######################################################"
          echo "picard AddOrReplaceReadGroups I=${filename3}_merged.bam O=${filename3}_RG.bam ID=${filename3} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${filename3}"
          picard AddOrReplaceReadGroups I=${filename3}_merged.bam O=${filename3}_RG.bam ID=${filename3} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${filename3}
          echo "picard ReorderSam I=${filename3}_RG.bam O=${filename3}_RGO.bam R=$referencegenome"
          picard ReorderSam I=${filename3}_RG.bam O=${filename3}_RGO.bam R=$referencegenome
          echo "samtools index ${filename3}_RGO.bam ${filename3}_RGO.bam.bai"
          samtools index ${filename3}_RGO.bam ${filename3}_RGO.bam.bai
          echo "gatk --java-options "-Xmx8g" SplitNCigarReads -R $referencegenome -I ${filename3}_RGO.bam -O ${filename3}_resolvedalig.bam -OBI false"
          gatk --java-options "-Xmx8g" SplitNCigarReads -R $referencegenome -I ${filename3}_RGO.bam -O ${filename3}_resolvedalig.bam -OBI false
          
          echo "######################################################"
          echo "Running HAMR"
          echo "######################################################"
          echo "python hamr.py -fe ${filename3}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${filename3}_HAMR ${filename3} 30 10 0.01 H4 1 .05 .05"
          python /HAMR/hamr.py -fe ${filename3}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${filename3}_HAMR ${filename3} 30 10 0.01 H4 1 .05 .05
          fi
          tophat_mapping_lincRNA_annotation
          tophat_mapping_transcript_quantification
          fi

          if [ "$tophat" == 0 ] && [ "$star" != 0 ]; then
          echo "###################################"
          echo "Running STAR in paired end mode"
          echo "###################################"
              if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                    echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_1P.fastq ${filename3}_2P.fastq"
                    STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_1P.fastq ${filename3}_2P.fastq
              elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                      echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_trimmed_R1.fastq ${filename3}_trimmed_R2.fastq"
                      STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename3}_ --readFilesIn ${filename3}_trimmed_R1.fastq ${filename3}_trimmed_R2.fastq
              fi
              star_mapping_lincRNA_annotation
              star_mapping_transcript_quantification
          fi
          house_keeping
}

single_end()
{
    extension=$(echo "$f" | sed -r 's/.*(fq|fq.gz|fastq|fastq.gz)$/\1/')
    filename=$(basename "$f" ".$extension")

          echo "##############################"
          echo "Trimming single-end input read"
          echo "##############################"
          if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                echo "trimmomatic SE -threads $num_threads ${filename}.${extension} ${filename}_trimmed.${extension} ILLUMINACLIP:$ADAPTERPATH/TruSeq3-SE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36"
                trimmomatic SE -threads $num_threads ${filename}.${extension} ${filename}_trimmed.${extension} ILLUMINACLIP:$ADAPTERPATH/TruSeq3-SE.fa:2:30:10:2 LEADING:3 TRAILING:3 MINLEN:36
          elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                  echo "fastp -w $num_threads -i ${filename}.${extension} -o ${filename}_trimmed.${extension} -j ${filename}_fastp.json -h ${filename}_fastp.html"
                  fastp -w $num_threads -i ${filename}.${extension} -o ${filename}_trimmed.${extension} -j ${filename}_fastp.json -h ${filename}_fastp.html
          fi

          if [ "$tophat" != 0 ] && [ "$star" == 0 ]; then
              echo "###################################"
              echo "Running tophat2 in single end mode"
              echo "###################################"
              echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename}_tophat -G $referenceannotation $fbname ${filename}_trimmed.${extension}"
              tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${filename}_tophat -G $referenceannotation $fbname ${filename}_trimmed.${extension}

              echo "########################"
              echo "Converting .bam to .sam"
              echo "########################"
              echo "samtools view -h -@ $num_threads -o ${filename}.sam ${filename}_tophat/accepted_hits.bam"
              samtools view -h -@ $num_threads -o ${filename}.sam ${filename}_tophat/accepted_hits.bam
                      
              echo "#######################"
              echo "Grepping unique reads"
              echo "#######################"
              echo "grep -P '^\@|NH:i:1$' ${filename}.sam > ${filename}_unique.sam"
              grep -P '^\@|NH:i:1$' ${filename}.sam > ${filename}_unique.sam
              
              echo "######################################################"
              echo "Converting .sam to .bam before running samtools sort"
              echo "######################################################"
              echo "samtools view -bSh -@ $num_threads ${filename}_unique.sam > ${filename}_unique.bam"
              samtools view -bSh -@ $num_threads ${filename}_unique.sam > ${filename}_unique.bam
              
              echo "#######################"
              echo "Sorting unique reads"
              echo "#######################"
              echo "samtools sort -@ $num_threads ${filename}_unique.bam > ${filename}_sorted.bam"
              samtools sort -@ $num_threads ${filename}_unique.bam > ${filename}_sorted.bam
              
              if [ "$HAMR" != 0 ]; then
              echo "######################################################"
              echo "Resolving spliced alignments"
              echo "######################################################"
              echo "picard AddOrReplaceReadGroups I=${filename}_sorted.bam O=${filename}_RG.bam ID=${filename} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${filename}"
              picard AddOrReplaceReadGroups I=${filename}_sorted.bam O=${filename}_RG.bam ID=${filename} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${filename}
              echo "picard ReorderSam I=${filename}_RG.bam O=${filename}_RGO.bam R=$referencegenome"
              picard ReorderSam I=${filename}_RG.bam O=${filename}_RGO.bam R=$referencegenome
              echo "samtools index ${filename}_RGO.bam ${sra_id}_RGO.bam.bai"
              samtools index ${filename}_RGO.bam ${filename}_RGO.bam.bai
              echo "gatk --java-options "-Xmx8g" SplitNCigarReads -R $referencegenome -I ${filename}_RGO.bam -O ${filename}_resolvedalig.bam -OBI false"
              gatk --java-options "-Xmx8g" SplitNCigarReads -R $referencegenome -I ${filename}_RGO.bam -O ${filename}_resolvedalig.bam -OBI false
        
              echo "######################################################"
              echo "Running HAMR"
              echo "######################################################"
              echo "python hamr.py -fe ${filename}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${filename}_HAMR ${filename} 30 10 0.01 H4 1 .05 .05"
              python /HAMR/hamr.py -fe ${filename}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${filename}_HAMR ${filename} 30 10 0.01 H4 1 .05 .05
              fi
              tophat_mapping_lincRNA_annotation
              tophat_mapping_transcript_quantification

          elif [ "$tophat" == 0 ] && [ "$star" != 0 ]; then
                    if [[ "$extension" =~ "fq.gz" ]]; then
                    echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename}_ --readFilesIn ${filename}_trimmed.${extension}"
                    STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename}_ --readFilesIn ${filename}_trimmed.${extension}
                    elif [[ "$extension" =~ "fastq.gz" ]]; then
                    echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename}_ --readFilesIn ${filename}_trimmed.${extension}"
                    STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${filename}_ --readFilesIn ${filename}_trimmed.${extension}
                    elif [[ "$extension" =~ "fq" ]]; then
                    echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --genomeDir ./star_index --outFileNamePrefix ${filename}_ --readFilesIn ${filename}_trimmed.${extension}"
                    STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --genomeDir ./star_index --outFileNamePrefix ${filename}_ --readFilesIn ${filename}_trimmed.${extension}
                    elif [[ "$extension" =~ "fastq" ]]; then
                    echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --genomeDir ./star_index --outFileNamePrefix ${filename}_ --readFilesIn ${filename}_trimmed.${extension}"
                    STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --genomeDir ./star_index --outFileNamePrefix ${filename}_ --readFilesIn ${filename}_trimmed.${extension}
                    fi
                star_mapping_lincRNA_annotation
                star_mapping_transcript_quantification
          fi
          house_keeping
}

#############################################################################################################################################################################################################################
# Check if user supplied index folder which contains bowtie2 and star indexes. Build the indexes if not supplied.
#############################################################################################################################################################################################################################

if [ "$HAMR" != 0 ]; then
  echo "samtools dict $referencegenome -o $gname.dict"
  samtools dict $referencegenome -o "$gname".dict
  echo "samtools faidx $referencegenome"
  samtools faidx $referencegenome
fi

if [ "$tophat" != 0 ] && [ "$star" == 0 ]; then
  if [ ! -z "$index_folder" ]; then
    for i in $index_folder/*.bt2; do
      mv -f $i .
      fbname=$(basename "$i" .bt2 | cut -d. -f1)
    done
  elif [ ! -z "$referencegenome" ] && [ -z "$index_folder" ]; then
    echo "##########################################"
    echo "Building reference genome index for Tophat"
    echo "##########################################"
    echo "bowtie2-build --threads -f $referencegenome $gname"
    bowtie2-build -f $referencegenome "$gname"
    echo "fbname=$(basename "$gname" .bt2 | cut -d. -f1)"
    fbname=$(basename "$gname" .bt2 | cut -d. -f1)
  fi
elif [ "$tophat" == 0 ] && [ "$star" != 0 ]; then
  if [ ! -z "$index_folder" ]; then
      mv -f $index_folder/star_index/ .
  elif [ ! -z "$referencegenome" ] && [ -z "$index_folder" ]; then
    echo "########################################"
    echo "Building reference genome index for STAR"
    echo "########################################"
    echo "STAR --runThreadN $num_threads --runMode genomeGenerate --genomeDir star_index --genomeFastaFiles $referencegenome --sjdbGTFfile $referenceannotation --sjdbOverhang $sjdbOverhang --genomeSAindexNbases $genomeSAindexNbases"
    STAR --runThreadN $num_threads --runMode genomeGenerate --genomeDir star_index --genomeFastaFiles $referencegenome --sjdbGTFfile $referenceannotation --sjdbOverhang $sjdbOverhang --genomeSAindexNbases $genomeSAindexNbases
  fi
fi

#############################################################################################################################################################################################################################
# # Check that the input fastq files has the appropriate extension and then trim reads, align the reads to the reference genome, quantify transcript abundance, identify RNA Mod. and LincRNA
#############################################################################################################################################################################################################################

if [ ! -z "$left_reads" ] && [ ! -z "$right_reads" ]; then
    numb=$(ls "${left_reads[@]}" | wc -l)
    for f in "${left_reads[@]}"; do
      extension=$(echo "$f" | sed -r 's/.*(fq|fq.gz|fastq|fastq.gz)$/\1/')
      if [[ "$extension" =~ "fq.gz" ]]; then
        paired_fq_gz
      elif [[ "$extension" =~ "fastq.gz" ]]; then
        paired_fastq_gz
      elif [[ "$extension" =~ "fq" ]]; then
        echo "gzip" "$f"
        paired_fq
      elif [[ "$extension" =~ "fastq" ]]; then
        echo "gzip" "$f"
        paired_fastq
      elif [ "$extension" != "fastq" ] || [ "$extension" != "fq" ] || [ "$extension" != "fastq.gz" ] || [ "$extension" != "fq.gz" ]; then
        echo "The extension" "$extension" "is not supported. Only .fq, .fq.gz, .fastq, .fastq.gz are only supported" 1>&2        
        exit 64
      fi
    done

#single end reads

elif [ ! -z "$single_reads" ]; then
        numb=$(ls "${single_reads[@]}" | wc -l)
	      for f in "${single_reads[@]}"; do
          if [ ! -d "$pipeline_output" ]; then
            mkdir $pipeline_output
          fi
          single_end
      done

elif [ ! -z "$sra_id" ]; then
        if [ "$seq_type" == "PE" ]; then

              echo "######################"
              echo "Downloading SRA data"
              echo "######################"

              echo "prefetch $sra_id"
              prefetch $sra_id
              echo "fasterq-dump -e $num_threads $sra_id"
              fasterq-dump -e $num_threads $sra_id
              
              echo "###############################"
              echo "Trimming paired-end input reads"
              echo "###############################"
              if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                    echo "trimmomatic PE -threads $num_threads ${sra_id}_1.fastq ${sra_id}_2.fastq ${sra_id}_1P.fastq.gz ${sra_id}_1U.fastq.gz ${sra_id}_2P.fastq.gz ${sra_id}_2U.fastq.gz ILLUMINACLIP:$ADAPTERPATH/TruSeq3-PE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36"
                    trimmomatic PE -threads $num_threads ${sra_id}_1.fastq ${sra_id}_2.fastq ${sra_id}_1P.fastq.gz ${sra_id}_1U.fastq.gz ${sra_id}_2P.fastq.gz ${sra_id}_2U.fastq.gz ILLUMINACLIP:$ADAPTERPATH/TruSeq3-PE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36
              elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                      echo "fastp -w $num_threads -i ${sra_id}_1.fastq -I ${sra_id}_2.fastq -o ${sra_id}_trimmed_R1.fastq.gz -O ${sra_id}_trimmed_R2.fastq.gz -j ${sra_id}_fastp.json -h ${sra_id}_fastp.html"
                      fastp -w $num_threads -i ${sra_id}_1.fastq -I ${sra_id}_2.fastq -o ${sra_id}_trimmed_R1.fastq.gz -O ${sra_id}_trimmed_R2.fastq.gz -j ${sra_id}_fastp.json -h ${sra_id}_fastp.html
              fi

              if [ "$tophat" != 0 ] && [ "$star" == 0 ]; then
              echo "###################################"
              echo "Running tophat2 in paired end mode"
              echo "###################################"
                    if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                          echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${sra_id}_fwd_tophat -G $referenceannotation $fbname ${sra_id}_1P.fastq.gz,${sra_id}_1U.fastq.gz"
                          tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${sra_id}_fwd_tophat -G $referenceannotation $fbname ${sra_id}_1P.fastq.gz,${sra_id}_1U.fastq.gz
                          echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${sra_id}_rev_tophat -G $referenceannotation $fbname ${sra_id}_2P.fastq.gz"
                          tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${sra_id}_rev_tophat -G $referenceannotation $fbname ${sra_id}_2P.fastq.gz
                          
                    elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                            echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${sra_id}_fwd_tophat -G $referenceannotation $fbname ${sra_id}_trimmed_R1.fastq.gz"
                            tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${sra_id}_fwd_tophat -G $referenceannotation $fbname ${sra_id}_trimmed_R1.fastq.gz
                            echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${sra_id}_rev_tophat -G $referenceannotation $fbname ${sra_id}_trimmed_R2.fastq.gz"
                            tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${sra_id}_rev_tophat -G $referenceannotation $fbname ${sra_id}_trimmed_R2.fastq.gz
                    fi

              echo "########################"
              echo "Converting .bam to .sam"
              echo "########################"
              echo "samtools view -h -@ $num_threads -o ${sra_id}_fwd.sam ${sra_id}_fwd_tophat/accepted_hits.bam"
              samtools view -h -@ $num_threads -o ${sra_id}_fwd.sam ${sra_id}_fwd_tophat/accepted_hits.bam
              echo "samtools view -h -o ${sra_id}_rev.sam ${sra_id}_rev_tophat/accepted_hits.bam"
              samtools view -h -o ${sra_id}_rev.sam ${sra_id}_rev_tophat/accepted_hits.bam
              
              echo "#######################"
              echo "Grepping unique reads"
              echo "#######################"
              echo "grep -P '^\@|NH:i:1$' ${sra_id}_fwd.sam > ${sra_id}_fwd_unique.sam"
              grep -P '^\@|NH:i:1$' ${sra_id}_fwd.sam > ${sra_id}_fwd_unique.sam
              echo "grep -P '^\@|NH:i:1$' ${sra_id}_rev.sam > ${sra_id}_rev_unique.sam"
              grep -P '^\@|NH:i:1$' ${sra_id}_rev.sam > ${sra_id}_rev_unique.sam
              
              echo "######################################################"
              echo "Converting .sam to .bam before running samtools sort"
              echo "######################################################"
              echo "samtools view -bSh -@ $num_threads ${sra_id}_fwd_unique.sam > ${sra_id}_fwd_unique.bam"
              samtools view -bSh -@ $num_threads ${sra_id}_fwd_unique.sam > ${sra_id}_fwd_unique.bam
              echo "samtools view -bSh -@ $num_threads ${sra_id}_rev_unique.sam > ${sra_id}_rev_unique.bam"
              samtools view -bSh -@ $num_threads ${sra_id}_rev_unique.sam > ${sra_id}_rev_unique.bam
              
              echo "#######################"
              echo "Sorting unique reads"
              echo "#######################"
              echo "samtools sort -@ $num_threads ${sra_id}_fwd_unique.bam > ${sra_id}_fwd_sorted.bam"
              samtools sort -@ $num_threads ${sra_id}_fwd_unique.bam > ${sra_id}_fwd_sorted.bam
              echo "samtools sort -@ $num_threads ${sra_id}_rev_unique.bam > ${sra_id}_rev_sorted.bam"
              samtools sort -@ $num_threads ${sra_id}_rev_unique.bam > ${sra_id}_rev_sorted.bam
              
              echo "########################"
              echo "Merging fwd and rev reads"
              echo "########################"
              echo "samtools merge -@ $num_threads -f ${sra_id}_merged.bam ${sra_id}_fwd_sorted.bam ${sra_id}_rev_sorted.bam"
              samtools merge -@ $num_threads -f ${sra_id}_merged.bam ${sra_id}_fwd_sorted.bam ${sra_id}_rev_sorted.bam

              if [ "$HAMR" != 0 ]; then
              echo "######################################################"
              echo "Resolving spliced alignments"
              echo "######################################################"
              echo "picard AddOrReplaceReadGroups I=${sra_id}_merged.bam O=${sra_id}_RG.bam ID=${sra_id} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${sra_id}"
              picard AddOrReplaceReadGroups I=${sra_id}_merged.bam O=${sra_id}_RG.bam ID=${sra_id} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${sra_id}
              echo "picard ReorderSam I=${sra_id}_RG.bam O=${sra_id}_RGO.bam R=$referencegenome"
              picard ReorderSam I=${sra_id}_RG.bam O=${sra_id}_RGO.bam R=$referencegenome
              echo "samtools index ${sra_id}_RGO.bam ${sra_id}_RGO.bam.bai"
              samtools index ${sra_id}_RGO.bam ${sra_id}_RGO.bam.bai
              echo "gatk --java-options "-Xmx8g" SplitNCigarReads -R $referencegenome -I ${sra_id}_RGO.bam -O ${sra_id}_resolvedalig.bam -OBI false"
              gatk --java-options "-Xmx8g" SplitNCigarReads -R $referencegenome -I ${sra_id}_RGO.bam -O ${sra_id}_resolvedalig.bam -OBI false
          
              echo "######################################################"
              echo "Running HAMR"
              echo "######################################################"
              echo "python hamr.py -fe ${sra_id}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${sra_id}_HAMR ${sra_id} 30 10 0.01 H4 1 .05 .05"
              python /HAMR/hamr.py -fe ${sra_id}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${sra_id}_HAMR ${sra_id} 30 10 0.01 H4 1 .05 .05
              fi
              sra_id_lincRNA_annotation
              sra_id_transcript_quantification
              fi
              
              if [ "$tophat" == 0 ] && [ "$star" != 0 ]; then
                  echo "###################################"
                  echo "Running STAR in paired end mode"
                  echo "###################################"
                    if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                          echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${sra_id}_ --readFilesIn ${sra_id}_1P.fastq.gz ${sra_id}_2P.fastq.gz"
                          STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${sra_id}_ --readFilesIn ${sra_id}_1P.fastq.gz ${sra_id}_2P.fastq.gz
                    elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                            echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${sra_id}_ --readFilesIn ${sra_id}_trimmed_R1.fastq.gz ${sra_id}_trimmed_R2.fastq.gz"
                            STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${sra_id}_ --readFilesIn ${sra_id}_trimmed_R1.fastq.gz ${sra_id}_trimmed_R2.fastq.gz
                    fi
              star_mapping_lincRNA_annotation
              star_mapping_transcript_quantification
              fi
              house_keeping
              
        elif [ "$seq_type" == "SE" ]; then
                echo "######################"
                echo "Downloading SRA data"
                echo "######################"

                echo "prefetch $sra_id"
                prefetch $sra_id
                echo "fasterq-dump -e $num_threads $sra_id"
                fasterq-dump -e $num_threads $sra_id
                
                echo "##############################"
                echo "Trimming single-end input read"
                echo "##############################"
                if [ "$trimmomatic" != 0 ] && [ "$fastp" == 0 ]; then
                      echo "trimmomatic SE -threads $num_threads ${sra_id}.fastq ${sra_id}_trimmed.fastq.gz ILLUMINACLIP:$ADAPTERPATH/TruSeq3-SE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36"
                      trimmomatic SE -threads $num_threads ${sra_id}.fastq ${sra_id}_trimmed.fastq.gz ILLUMINACLIP:$ADAPTERPATH/TruSeq3-SE.fa:2:30:10:2 LEADING:3 TRAILING:3 MINLEN:36
                elif [ "$trimmomatic" == 0 ] && [ "$fastp" != 0 ]; then
                        echo "fastp -w $num_threads -i ${sra_id}.fastq -o ${sra_id}_trimmed.fastq.gz -j ${sra_id}_fastp.json -h ${sra_id}_fastp.html"
                        fastp -w $num_threads -i ${sra_id}.fastq -o ${sra_id}_trimmed.fastq.gz -j ${sra_id}_fastp.json -h ${sra_id}_fastp.html
                fi

                if [ "$tophat" != 0 ] && [ "$star" == 0 ]; then
                echo "###################################"
                echo "Running tophat2 in single end mode"
                echo "###################################"
                echo "tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${sra_id}_tophat -G $referenceannotation $fbname ${sra_id}_trimmed.fastq.gz"
                tophat -p $num_threads --library-type $lib_type --read-mismatches $reads_mismatches --read-edit-dist $reads_mismatches --max-multihits 10 --b2-very-sensitive --transcriptome-max-hits 10 --no-coverage-search --output-dir ${sra_id}_tophat -G $referenceannotation $fbname ${sra_id}_trimmed.fastq.gz
                
                echo "########################"
                echo "Converting .bam to .sam"
                echo "########################"
                echo "samtools view -h -@ $num_threads -o ${sra_id}.sam ${sra_id}_tophat/accepted_hits.bam"
                samtools view -h -@ $num_threads -o ${sra_id}.sam ${sra_id}_tophat/accepted_hits.bam
                          
                echo "#######################"
                echo "Grepping unique reads"
                echo "#######################"
                echo "grep -P '^\@|NH:i:1$' ${sra_id}.sam > ${sra_id}_unique.sam"
                grep -P '^\@|NH:i:1$' ${sra_id}.sam > ${sra_id}_unique.sam
                  
                echo "######################################################"
                echo "Converting .sam to .bam before running samtools sort"
                echo "######################################################"
                echo "samtools view -bSh -@ $num_threads ${sra_id}_unique.sam > ${sra_id}_unique.bam"
                samtools view -bSh -@ $num_threads ${sra_id}_unique.sam > ${sra_id}_unique.bam
                  
                echo "#######################"
                echo "Sorting unique reads"
                echo a "samtools sort -@ $num_threads ${sra_id}_unique.bam > ${sra_id}_sorted.bam"
                samtools sort -@ $num_threads ${sra_id}_unique.bam > ${sra_id}_sorted.bam
                
                if [ "$HAMR" != 0 ]; then
                echo "######################################################"
                echo "Resolving spliced alignments"
                echo "######################################################"
                echo "picard AddOrReplaceReadGroups I=${sra_id}_sorted.bam O=${sra_id}_RG.bam ID=${sra_id} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${sra_id}"
                picard AddOrReplaceReadGroups I=${sra_id}_sorted.bam O=${sra_id}_RG.bam ID=${sra_id} LB=D4 PL=illumina PU=HWUSI-EAS1814:28:2 SM=${sra_id}
                echo "picard ReorderSam I=${sra_id}_RG.bam O=${sra_id}_RGO.bam R=$referencegenome"
                picard ReorderSam I=${sra_id}_RG.bam O=${sra_id}_RGO.bam R=$referencegenome
                echo "samtools index ${sra_id}_RGO.bam ${sra_id}_RGO.bam.bai"
                samtools index ${sra_id}_RGO.bam ${sra_id}_RGO.bam.bai
                echo "gatk --java-options "-Xmx8g" SplitNCigarReads -R $referencegenome -I ${sra_id}_RGO.bam -O ${sra_id}_resolvedalig.bam -OBI false"
                gatk --java-options "-Xmx8g" SplitNCigarReads -R $referencegenome -I ${sra_id}_RGO.bam -O ${sra_id}_resolvedalig.bam -OBI false
  
                echo "######################################################"
                echo "Running HAMR"
                echo "######################################################"
                echo "python hamr.py -fe ${sra_id}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${sra_id}_HAMR ${sra_id} 30 10 0.01 H4 1 .05 .05"
                python /HAMR/hamr.py -fe ${sra_id}_resolvedalig.bam $referencegenome $HAMR_MODELS_PATH/euk_trna_mods.Rdata ${sra_id}_HAMR ${sra_id} 30 10 0.01 H4 1 .05 .05
                fi
                sra_id_lincRNA_annotation
                sra_id_transcript_quantification
                fi

                if [ "$tophat" == 0 ] && [ "$star" != 0 ]; then
                      echo "STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${sra_id}_ --readFilesIn ${sra_id}_trimmed.fastq.gz"
                      STAR --runMode alignReads --outSAMtype BAM SortedByCoordinate --readFilesCommand zcat --genomeDir ./star_index --outFileNamePrefix ${sra_id}_ --readFilesIn ${sra_id}_trimmed.fastq.gz
                      sra_id_lincRNA_annotation
                      sra_id_transcript_quantification
                fi
                house_keeping
          fi
                
fi
######### End ########