#!/bin/bash
# PreReconAll.sh
## 7. Convert E-Prime text file to tab-delimited file and get onsets for tasks with python script.
## 8. Create movies of raw functional data (for later inclusion in QA reports).
## 9. Start FreeSurfer recon-all with reoriented T1 image as input.

if [ $# -lt 1 ]; then
	echo
	echo   "bash PreReconAll.sh <subject_id>"
	echo
	exit
fi

SUBJECT=$1
PROJECT_DIR=/mnt/stressdevlab/example_pipeline
SUBJECT_DIR=${PROJECT_DIR}/${SUBJECT}
FS_DIR=${PROJECT_DIR}/FreeSurfer
FS_SUBJECT_DIR=${FS_DIR}/${SUBJECT}
SCRIPTS_DIR=/mnt/stressdevlab/scripts/Preprocessing
LOGFILE=${SUBJECT_DIR}/logfiles/PreReconAll.log

cd ${SUBJECT_DIR}
source /usr/local/freesurfer/stable5_3/SetUpFreeSurfer.sh
export SUBJECTS_DIR=${FS_DIR}


## 7. Convert E-Prime text file to tab-delimited file and get onsets for tasks with python script.
if [[ ! -f ${SUBJECT_DIR}/emo/Emo2_GameStim.txt ]]; then
	echo "7. Converting E-Prime text-file to csv and getting task onsets..."
	ruby /usr/local/bin/eprime2tabfile ${SUBJECT_DIR}/behavior/fMRI_COMBINED_TASKS_${SUBJECT}.txt -o TempBeh.csv
	NumLines=`cat TempBeh.csv | wc -l`
	head -n 1 TempBeh.csv | sed 's/\./_/g' | sed 's/\(\[\|\]\)//g' > behavior/${SUBJECT}_reformatted_eprime.csv
	tail -n `echo "${NumLines} - 1" | bc` TempBeh.csv >> behavior/${SUBJECT}_reformatted_eprime.csv
	python ${PROJECT_DIR}/bin/Emo_onsets.py -i behavior/${SUBJECT}_reformatted_eprime.csv -o emo/
	rm TempBeh.csv
fi

## 8. Create movies of raw functional data (for later inclusion in QA reports).
if [[ ! -f ${SUBJECT_DIR}/QA/Images/Emo2_z_animation.gif ]]; then
	echo "8. Creating movies of raw data (for later inclusion in QA reports)..."

	for i in `ls nifti/*.nii.gz`; do
		if [[ ${i} != *DTI* ]]; then
			${SCRIPTS_DIR}/functional_movies_new ${i} QA/Images 2
		fi
	done
fi

## 9. Start FreeSurfer recon-all with reoriented T1 image as input.
if [[ ! -f ${FS_SUBJECT_DIR}/mri/aparc+aseg.mgz ]]; then
	echo "9. Starting FreeSurfer recon-all with reoriented T1 image as input..."

	fslreorient2std mprage/MPRAGE.nii.gz mprage/T1.nii.gz
	/usr/local/freesurfer/stable5_3/bin/recon-all -i mprage/T1.nii.gz -subjid ${SUBJECT} -all
fi
