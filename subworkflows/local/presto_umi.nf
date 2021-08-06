def modules = params.modules.clone()

include { MERGE_UMI }                               from '../../modules/local/merge_UMI'                 addParams( options: [:] )
include { RENAME_FASTQ      as RENAME_FASTQ_UMI }   from '../../modules/local/rename_fastq'              addParams( options: [:] )
include { GUNZIP            as GUNZIP_UMI }         from '../../modules/local/gunzip'                    addParams( options: [:] )
include { FASTQC_POSTASSEMBLY as FASTQC_POSTASSEMBLY_UMI } from '../../modules/local/fastqc_postassembly'                                addParams( options: [:] )

//PRESTO
include { PRESTO_FILTERSEQ      as  PRESTO_FILTERSEQ_UMI }      from '../../modules/local/presto/presto_filterseq'                             addParams( options: modules['presto_filterseq'] )
include { PRESTO_MASKPRIMERS    as  PRESTO_MASKPRIMERS_UMI }    from '../../modules/local/presto/presto_maskprimers'                           addParams( options: modules['presto_maskprimers'] )
include { PRESTO_PAIRSEQ        as  PRESTO_PAIRSEQ_UMI }        from '../../modules/local/presto/presto_pairseq'                               addParams( options: modules['presto_pairseq'] )
include { PRESTO_CLUSTERSETS    as  PRESTO_CLUSTERSETS_UMI }    from '../../modules/local/presto/presto_clustersets'                           addParams( options: modules['presto_clustersets'] )
include { PRESTO_PARSE_CLUSTER  as  PRESTO_PARSE_CLUSTER_UMI }  from '../../modules/local/presto/presto_parse_cluster'                         addParams( options: modules['presto_parse_clusters'] )
include { PRESTO_BUILDCONSENSUS as  PRESTO_BUILDCONSENSUS_UMI } from '../../modules/local/presto/presto_buildconsensus'                        addParams( options: modules['presto_buildconsensus'] )
include { PRESTO_POSTCONSENSUS_PAIRSEQ as PRESTO_POSTCONSENSUS_PAIRSEQ_UMI }    from '../../modules/local/presto/presto_postconsensus_pairseq'     addParams( options: modules['presto_postconsensus_pairseq'] )
include { PRESTO_ASSEMBLEPAIRS  as  PRESTO_ASSEMBLEPAIRS_UMI }  from '../../modules/local/presto/presto_assemblepairs'                         addParams( options: modules['presto_assemblepairs_umi'] )
include { PRESTO_PARSEHEADERS   as  PRESTO_PARSEHEADERS_COLLAPSE_UMI } from '../../modules/local/presto/presto_parseheaders'                   addParams( options: modules['presto_parseheaders_collapse_umi'] )
include { PRESTO_PARSEHEADERS_PRIMERS   as PRESTO_PARSEHEADERS_PRIMERS_UMI }    from '../../modules/local/presto/presto_parseheaders_primers'      addParams( options: modules['presto_parseheaders_primers_umi'] )
include { PRESTO_PARSEHEADERS_METADATA  as PRESTO_PARSEHEADERS_METADATA_UMI }   from '../../modules/local/presto/presto_parseheaders_metadata'     addParams( options: modules['presto_parseheaders_metadata'] )
include { PRESTO_COLLAPSESEQ    as PRESTO_COLLAPSESEQ_UMI }     from '../../modules/local/presto/presto_collapseseq'                           addParams( options: modules['presto_collapseseq_umi'] )
include { PRESTO_SPLITSEQ       as PRESTO_SPLITSEQ_UMI}         from '../../modules/local/presto/presto_splitseq'                              addParams( options: modules['presto_splitseq_umi'] )


workflow PRESTO_UMI {
    take:
    ch_reads       // channel: [ val(meta), [ reads ] ]
    ch_cprimers    // channel: [ cprimers.fasta ]
    ch_vprimers    // channel: [ vprimers.fasta ]

    main:

    ch_software_versions = Channel.empty()
    // Merge UMI from index file to R1 if provided
    if (params.index_file) {
        MERGE_UMI ( ch_reads )
        .set{ ch_gunzip }
    } else {
        RENAME_FASTQ_UMI ( ch_reads )
        .set{ ch_gunzip }
    }

    // gunzip fastq.gz to fastq
    GUNZIP_UMI ( ch_gunzip )
    ch_software_versions = ch_software_versions.mix(GUNZIP_UMI.out.version.first().ifEmpty(null))

    // Filter sequences by quality score
    PRESTO_FILTERSEQ_UMI ( GUNZIP_UMI.out.reads )
    ch_software_versions = ch_software_versions.mix(PRESTO_FILTERSEQ_UMI.out.version.first().ifEmpty(null))

    // Mask primers
    PRESTO_MASKPRIMERS_UMI (
        PRESTO_FILTERSEQ_UMI.out.reads,
        ch_cprimers.collect(),
        ch_vprimers.collect()
    )

    // Pre-consensus pair
    PRESTO_PAIRSEQ_UMI (
        PRESTO_MASKPRIMERS_UMI.out.reads
    )

    // Cluster sequences by similarity
    PRESTO_CLUSTERSETS_UMI (
        PRESTO_PAIRSEQ_UMI.out.reads
    )
    ch_software_versions = ch_software_versions.mix(PRESTO_CLUSTERSETS_UMI.out.version.first().ifEmpty(null))

    // Annotate cluster into barcode field
    PRESTO_PARSE_CLUSTER_UMI (
        PRESTO_CLUSTERSETS_UMI.out.reads
    )

    // Build consensus of sequences with same UMI barcode
    PRESTO_BUILDCONSENSUS_UMI (
        PRESTO_PARSE_CLUSTER_UMI.out.reads
    )

    // Post-consensus pair
    PRESTO_POSTCONSENSUS_PAIRSEQ_UMI (
        PRESTO_BUILDCONSENSUS_UMI.out.reads
    )

    // Assemble read pairs
    PRESTO_ASSEMBLEPAIRS_UMI (
        PRESTO_POSTCONSENSUS_PAIRSEQ_UMI.out.reads
    )

    // Generate QC stats after reads paired and filtered but before collapsed
    FASTQC_POSTASSEMBLY_UMI (
        PRESTO_ASSEMBLEPAIRS_UMI.out.reads
    )

    // Combine UMI duplicate count
    PRESTO_PARSEHEADERS_COLLAPSE_UMI (
        PRESTO_ASSEMBLEPAIRS_UMI.out.reads
    )

    // Annotate primers in C_PRIMER and V_PRIMER field
    PRESTO_PARSEHEADERS_PRIMERS_UMI (
        PRESTO_PARSEHEADERS_COLLAPSE_UMI.out.reads
    )

    // Annotate metadata on primer headers
    PRESTO_PARSEHEADERS_METADATA_UMI (
        PRESTO_PARSEHEADERS_PRIMERS_UMI.out.reads
    )

    // Mark and count duplicate sequences with different UMI barcodes (DUPCOUNT)
    PRESTO_COLLAPSESEQ_UMI (
        PRESTO_PARSEHEADERS_METADATA_UMI.out.reads
    )

    // Filter out sequences with less than 2 representative duplicates with different UMIs
    PRESTO_SPLITSEQ_UMI (
        PRESTO_COLLAPSESEQ_UMI.out.reads
    )

    emit:
    fasta = PRESTO_SPLITSEQ_UMI.out.fasta
    software = ch_software_versions
    fastqc_postassembly_gz = FASTQC_POSTASSEMBLY_UMI.out.zip
    presto_filterseq_logs = PRESTO_FILTERSEQ_UMI.out.logs
    presto_maskprimers_logs = PRESTO_MASKPRIMERS_UMI.out.logs.collect()
    presto_pairseq_logs = PRESTO_PAIRSEQ_UMI.out.logs.collect()
    presto_clustersets_logs = PRESTO_CLUSTERSETS_UMI.out.logs.collect()
    presto_buildconsensus_logs = PRESTO_BUILDCONSENSUS_UMI.out.logs.collect()
    presto_postconsensus_pairseq_logs = PRESTO_POSTCONSENSUS_PAIRSEQ_UMI.out.logs.collect()
    presto_assemblepairs_logs = PRESTO_ASSEMBLEPAIRS_UMI.out.logs.collect()
    presto_collapseseq_logs = PRESTO_COLLAPSESEQ_UMI.out.logs.collect()
    presto_splitseq_logs = PRESTO_SPLITSEQ_UMI.out.logs.collect()
}
