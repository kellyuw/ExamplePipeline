#!/bin/bash
# PrepareFEAT.sh
## 31. Use FLIRT to register FreeSurfer CSF and WM masks to functional space.
## 32. Identify scanner spikes by interrogating the signal outside of the brain with ibicIDSN.sh.
## 33. Use FSL motion_outliers to find DVARS and FD outliers.
## 34. Make list of unique outlier volumes.
## 35. Use SinglePointGenerator.py to get formatted list of outlier volumes (as single point regressors). 
## 36. Combine csf, wm, and outlier regressors to create single nuisance_regressors.txt file for FEAT.

if [ $# -lt 1 ]; then
	echo
	echo   "bash PrepareFeat.sh <subject_id>"
	echo
	exit
fi

SUBJECT=$1
PROJECT_DIR=/mnt/stressdevlab/example_pipeline
SUBJECT_DIR=${PROJECT_DIR}/${SUBJECT}
FS_DIR=${PROJECT_DIR}/FreeSurfer
FS_SUBJECT_DIR=${FS_DIR}/${SUBJECT}
SCRIPTS_DIR=/mnt/stressdevlab/scripts/Preprocessing
ANTS_DIR=/usr/local/ANTs-2.1.0-rc3/bin
MNI_BRAIN=/usr/share/fsl/5.0/data/standard/MNI152_T1_2mm_brain.nii.gz
NIH_BRAIN=${PROJECT_DIR}/Standard/nihpd_t1_brain.nii.gz
LOGFILE=${SUBJECT_DIR}/logfiles/PrepareFeat.log

FWHM=5


cd ${SUBJECT_DIR}
source /usr/local/freesurfer/stable5_3/SetUpFreeSurfer.sh
export SUBJECTS_DIR=${FS_DIR}
export ANTSPATH=${ANTS_DIR}



## 31. Use FSL's FLIRT to register FreeSurfer CSF and WM masks to functional space.

if [[ ! -f emo/Emo2_wm.txt ]]; then
	echo " **** 31. Using FSL's FLIRT tor register FreeSurfer CSF and WM masks to functional space..." | ts | tee -a ${LOGFILE}
	
	mri_binarize --i ${FS_SUBJECT_DIR}/mri/aparc+aseg.mgz --o mprage/fs_csf_mask.nii.gz --erode 1 --ventricles
	mri_binarize --i ${FS_SUBJECT_DIR}/mri/aparc+aseg.mgz --o mprage/fs_wm_mask.nii.gz --erode 1 --wm
	
	for i in emo/Emo1 emo/Emo2; do
		RUN=`basename $i`
		flirt  -ref ${i}_despike.nii.gz -in mprage/fs_csf_mask.nii.gz -out ${i}_csf.nii.gz -applyxfm -init xfm_dir/fs_to_${RUN}.mat
		flirt  -ref ${i}_despike.nii.gz -in mprage/fs_wm_mask.nii.gz -out ${i}_wm.nii.gz -applyxfm -init xfm_dir/fs_to_${RUN}.mat

		for j in csf wm; do
			fslmaths ${i}_${j}.nii.gz -thr .5 -bin ${i}_${j}.nii.gz
			fslmeants -i ${i}_despike.nii.gz -o ${i}_${j}.txt -m ${i}_${j}.nii.gz
		done
	done
fi


## 32. Identify scanner spikes by interrogating the signal outside of the brain (with ibicIDSN.sh).

if [[ ! -f emo/Emo2_SN_outliers.txt ]]; then
	echo " **** 32. Identifying scanner spikes with ibicIDSN.sh..." | ts | tee -a ${LOGFILE}

	for i in emo/Emo1 emo/Emo2; do
		bash ${SCRIPTS_DIR}/ibicIDSN.sh ${i}.nii.gz `cat ${i}_TR.txt`
	done
fi


## 33. Use FSL motion_outliers to find DVARS and FD outliers.

if [[ ! -f emo/Emo2_fd_spike_vols ]]; then
	echo " **** 33. Using FSL motion outliers to find DVARS and FD outliers..." | ts | tee -a ${LOGFILE}

	for i in emo/Emo1 emo/Emo2; do
		RUN=`basename $i`
		${SCRIPTS_DIR}/motion_outliers -i ${i}_bet.nii.gz -o ${i}_dvars_regressors --dvars -s ${i}_dvars_vals –p QA/Images/${RUN}_dvars.png –nomoco
		${SCRIPTS_DIR}/motion_outliers -i ${i}_bet.nii.gz -o ${i}_fd_regressors --fd -s ${i}_fd_vals –p QA/Images/${RUN}_fd.png  –nomoco
	done
fi


## 34. Make list of unique outlier volumes.

if [[ ! -f emo/Emo2_all_outliers.txt ]]; then
	echo " **** 34. Generating list of unique outlier volumes..." | ts | tee -a ${LOGFILE}

	for i in emo/Emo1 emo/Emo2; do
		cat ${i}_dvars_spike_vols | ${SCRIPTS_DIR}/transpose.awk > alloutliers.txt
		cat ${i}_fd_spike_vols | ${SCRIPTS_DIR}/ transpose.awk >> alloutliers.txt
		cat ${i}_SN_outliers.txt >> alloutliers.txt
		sort -nu alloutliers.txt > ${i}_all_outliers.txt
		rm alloutliers.txt
	done
fi


## 35. Use SinglePointGenerator.py to get formatted list of outlier volumes (as single point regressors). 

if [[ ! -f emo/Emo2_outlier_regressors.txt ]]; then
	echo " **** 35. Using SinglePointGenerator.py to get formatted list of outlier volumes (as single point regressors)..." | ts | tee -a ${LOGFILE}

	for i in emo/Emo1 emo/Emo2; do
		python ${SCRIPTS_DIR}/SinglePointGenerator.py -i ${i}_all_outliers.txt -v `cat ${i}_NVOLS.txt` -o ${i}_outlier_regressors.txt -p ${i}_percent_outliers.txt
	done
fi


## 36. Combine csf, wm, and outlier regressors to create single nuisance_regressors.txt file for FEAT.

if [[ ! -f emo/Emo1_nuisance_regressors.txt ]]; then
	echo " **** 36. Combininig csf, wm, and outlier regressors to create single nuisance_regressors.txt file for FEAT..." | ts | tee -a ${LOGFILE}

	for i in emo/Emo1 emo/Emo2; do
		paste ${i}_csf.txt ${i}_wm.txt ${i}.par ${i}_outlier_regressors.txt > ${i}_nuisance_regressors.txt
	done
fi
