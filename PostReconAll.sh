#!/bin/bash
# PostReconAll.sh
## 10. Use mri_binarize to extract WM and CSF masks in FreeSurfer space.
## 11. Register FreeSurfer brain to T1 space and perform skullstripping of T1 image (with FreeSurfer brainmask).
## 12. Use FreeSurfer brainmask to skullstrip T1 image.
## 13. Do segmentation with fast (required by epi-reg in later parts of pipeline).
## 14. Register T1 to NIH (custom template), MNI (2mm FSL), and FreeSurfer with ANTs.
## 15. Use optiBET for skull-stripping and register new skull-strip to nih and mni space (with ANTs).
## 16. Calculate similarity between the T1 image and template (for later inclusion in QA reports).

if [ $# -lt 1 ]; then
	echo
	echo   "bash PostReconAll.sh <subject_id>"
	echo
	exit
fi

SUBJECT=$1
PROJECT_DIR=/mnt/stressdevlab/example_pipeline
SUBJECT_DIR=${PROJECT_DIR}/${SUBJECT}
FS_DIR=${PROJECT_DIR}/FreeSurfer
FS_SUBJECT_DIR=${FS_DIR}/${SUBJECT}
ANTS_DIR=/usr/local/ANTs-2.1.0-rc3/bin
MNI_BRAIN=/usr/share/fsl/5.0/data/standard/MNI152_T1_2mm_brain.nii.gz
NIH_BRAIN=${PROJECT_DIR}/Standard/nihpd_t1_brain.nii.gz
LOGFILE=${SUBJECT_DIR}/logfiles/PostReconAll.log

cd ${SUBJECT_DIR}
source /usr/local/freesurfer/stable5_3/SetUpFreeSurfer.sh
export SUBJECTS_DIR=${FS_DIR}
export ANTSPATH=${ANTS_DIR}


## 10. Use mri_binarize to extract WM and CSF masks in FreeSurfer space.
if [[ ! -f xfm_dir/fs_csf_mask.nii.gz ]]; then
	echo "      10. Using mri_binarize to get WM and CSF masks in FreeSurfer space..." | ts | tee -a ${LOGFILE}

	mri_binarize --i ${FS_SUBJECT_DIR}/mri/aparc+aseg.mgz --o fs_wm_mask.nii.gz --erode 1 --wm; mv fs_wm_mask.nii.gz xfm_dir/
	mri_binarize --i ${FS_SUBJECT_DIR}/mri/aparc+aseg.mgz --o fs_csf_mask.nii.gz --erode 1 --ventricles; mv fs_csf_mask.nii.gz xfm_dir/
fi


## 11. Register FreeSurfer brain to T1 space.
if [[ ! -f xfm_dir/T1_to_fs.mat ]]; then
	echo "      11. Registering FreeSurfer brain to T1 space..." | ts | tee -a ${LOGFILE}

	tkregister2 --mov ${FS_SUBJECT_DIR}/mri/orig.mgz --targ ${FS_SUBJECT_DIR}/mri/aparc+aseg.mgz --noedit --regheader --reg xfm_dir/fs_to_T1.dat --fslregout xfm_dir/fs_to_T1_init.mat
	mri_convert ${FS_SUBJECT_DIR}/mri/orig.mgz ${FS_SUBJECT_DIR}/mri/orig.nii.gz
	flirt -ref mprage/T1.nii.gz -in ${FS_SUBJECT_DIR}/mri/orig.nii.gz -init xfm_dir/fs_to_T1_init.mat -omat xfm_dir/fs_to_T1.mat
	convert_xfm -omat xfm_dir/T1_to_fs.mat -inverse xfm_dir/fs_to_T1.mat
fi


## 12. Use FreeSurfer brainmask to skullstrip T1 image.
if [[ ! -f mprage/T1_brain.nii.gz ]]; then
	echo "      12. Using FreeSurfer brainmask to skullstrip T1 image..." | ts | tee -a ${LOGFILE}

	mri_convert ${FS_SUBJECT_DIR}/mri/brainmask.mgz ${FS_SUBJECT_DIR}/mri/brainmask.nii.gz
	flirt -ref mprage/T1.nii.gz -in ${FS_SUBJECT_DIR}/mri/brainmask.nii.gz -init xfm_dir/fs_to_T1.mat -applyxfm -out mprage/T1_brain.nii.gz
	fslmaths mprage/T1_brain.nii.gz -bin mprage/T1_brain_mask.nii.gz
fi


## 13. Register T1 to NIHPD (custom template) brain with ANTs.
if [[ ! -f xfm_dir/T1_to_nih_deformed.nii.gz ]]; then
	echo "      13. Using antsIntroduction.sh script to calculate T1 -> NIH registration transforms..." | ts | tee -a ${LOGFILE}

	${ANTS_DIR}/antsIntroduction.sh -d 3 -i ${SUBJECT_DIR}/mprage/T1_brain.nii.gz -m 30x90x20 -o ${SUBJECT_DIR}/xfm_dir/T1_to_nih_ -s CC -r ${NIH_BRAIN} -t GR
fi


## 14. Register T1 to MNI brain with ANTs.
if [[ ! -f xfm_dir/T1_to_mni_deformed.nii.gz ]]; then
	echo "      14. Using WarpImageMultiTransform to concatenate ANTs registration transforms (T1 -> NIH -> MNI)..." | ts | tee -a ${LOGFILE}

	${ANTS_DIR}/WarpImageMultiTransform 3 ${SUBJECT_DIR}/mprage/T1_brain.nii.gz ${SUBJECT_DIR}/xfm_dir/T1_to_mni_deformed.nii.gz -R ${MNI_BRAIN} ${PROJECT_DIR}/Standard/NIHtoMNIWarp.nii.gz ${PROJECT_DIR}/Standard/NIHtoMNIAffine.txt ${SUBJECT_DIR}/xfm_dir/T1_to_nih_Warp.nii.gz ${SUBJECT_DIR}/xfm_dir/T1_to_nih_Affine.txt
fi


## 15. Register FS to NIHPD (custom template) brain with ANTs.
if [[ ! -f xfm_dir/fs_to_nih_deformed.nii.gz ]]; then
	echo "      15. Using antsIntroduction.sh script to calculate T1 -> FS registration transforms..." | ts | tee -a ${LOGFILE}

	${ANTS_DIR}/antsIntroduction.sh -d 3 -i ${FS_SUBJECT_DIR}/mri/brainmask.nii.gz -m 30x90x20 -o ${SUBJECT_DIR}/xfm_dir/fs_to_nih_ -s CC -r ${NIH_BRAIN} -t GR
fi


## 16. Register FS to MNI brain with ANTs.
if [[ ! -f xfm_dir/fs_to_mni_deformed.nii.gz ]]; then
	echo "      16. Using WarpImageMultiTransform to concatenate ANTs registration transforms (FS -> NIH -> MNI)..." | ts | tee -a ${LOGFILE} 

	${ANTS_DIR}/WarpImageMultiTransform 3 ${FS_SUBJECT_DIR}/mri/brainmask.nii.gz ${SUBJECT_DIR}/xfm_dir/fs_to_mni_deformed.nii.gz -R ${MNI_BRAIN} ${PROJECT_DIR}/Standard/NIHtoMNIWarp.nii.gz ${PROJECT_DIR}/Standard/NIHtoMNIAffine.txt ${SUBJECT_DIR}/xfm_dir/fs_to_nih_Warp.nii.gz ${SUBJECT_DIR}/xfm_dir/fs_to_nih_Affine.txt
fi


## 17. Calculate similarity between the T1 image and template (for later inclusion in QA reports).
if [[ ! -f QA/T1_to_mni_similarity.csv ]]; then
	echo "      17. Calculating similarity metrics between the T1 image and standard template brains (NIH and MNI)..." | ts | tee -a ${LOGFILE}

	for i in nih mni; do

		if [[ ${i} == "nih" ]]; then
			TemplateBrain=${NIH_BRAIN}
		elif [[ ${i} == "mni" ]]; then
			TemplateBrain=${MNI_BRAIN}
		else
			echo "Error, unspecified template brain."
			exit 1
		fi

		MSQ=`${ANTS_DIR}/MeasureImageSimilarity 3 0 ${TemplateBrain} ${SUBJECT_DIR}/xfm_dir/T1_to_${i}_deformed.nii.gz | grep "MSQ" | awk '{print $NF}'`
		CC=`${ANTS_DIR}/MeasureImageSimilarity 3 1 ${TemplateBrain} ${SUBJECT_DIR}/xfm_dir/T1_to_${i}_deformed.nii.gz | grep "CC" | awk '{print $NF}'`
		MI=`${ANTS_DIR}/MeasureImageSimilarity 3 2 ${TemplateBrain} ${SUBJECT_DIR}/xfm_dir/T1_to_${i}_deformed.nii.gz | grep "MI" | awk '{print $NF}'`
		echo "MSQ,CC,MI" > "QA/T1_to_${i}_similarity.csv"
		echo "${MSQ},${CC},${MI}" >> "QA/T1_to_${i}_similarity.csv"

	done
fi
