version 1.0

import "../../structs/farm5/RunTimeSettings.wdl"

task ImportIRODS {
  input {
    String irods_path
    String sample_id

    RunTimeSettings runTimeSettings
  }

  String lanelet_basename = basename(irods_path)

  command {

    set -e
    set -o pipefail


    # Test that we can download from IRODS
    # -K verifies checksum
    # -f force overwite
    iget -K -f ${irods_path} ./${sample_id}.${lanelet_basename}
  }

  runtime {
    singularity: runTimeSettings.irods_singularity_image
    memory: 1000
    cpu: "1"
    lsf_group: select_first([runTimeSettings.lsf_group, "malaria-dk"])
    lsf_queue: select_first([runTimeSettings.lsf_queue, "normal"])
  }

  output {
      File output_file = "${sample_id}.${lanelet_basename}"
  }

}


# Given a tsv sample manifest where each row contains
# file locations of each lanelet of sequencing,
# separate each sample into separate tsv manifests with no header.
# The per-sample manifests can then be used to process each sample in parallel tasks,
# where each task in turn scatters the per-sample manifests by lanelet.

task BatchSplitUpInputFile {

  input {
    File batch_sample_manifest_file

    RunTimeSettings runTimeSettings
  }

  command <<<

  python <<CODE
  import pandas as pd

  sample_mf = pd.read_csv("~{batch_sample_manifest_file}", sep="\t")
  sample_mf = sample_mf.sort_values(["sample_id", "irods_path"])

  assert 'sample_id' in sample_mf.columns, "sample_id is not in header"
  assert 'irods_path' in sample_mf.columns, "irods_path is not in header"

  # Split the manifest into separate files
  for sample_id in sample_mf["sample_id"].unique():
      sample_mf[sample_mf["sample_id"] == sample_id].to_csv("{}_manifest.tsv".format(sample_id),
                                                            header=False,
                                                            sep="\t",
                                                            index=False)
  CODE
  >>>

  runtime {
    singularity: runTimeSettings.binder_singularity_image
    memory: 3000
    cpu: "1"
    lsf_group: select_first([runTimeSettings.lsf_group, "malaria-dk"])
    lsf_queue: select_first([runTimeSettings.lsf_queue, "normal"])
  }

  output {
      Array[File] per_sample_manifest_files = glob("*_manifest.tsv")
  }

}
