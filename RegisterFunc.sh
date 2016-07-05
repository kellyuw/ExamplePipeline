#!/bin/bash
# RegisterFunc.sh
## 23. Use FSL's epi_reg to register functional (despiked) images to T1. 
## 24. Use c3d_affine_tool to convert FSL’s epi_reg registration matrices from step 23 (functional -> T1) to ITK format (suffix: _ras.txt). 
## 25. Use epi_reg ITK matrices from step 23 (functional -> T1) and ANTs deformation fields (T1 -> NIH) to register functional images to NIH space with ANTs WarpImageMultiTransform.
## 26. Use epi_reg ITK matrices from step 23 (functional -> T1) and ANTs deformation fields (T1 -> NIH, NIH -> MNI) to register functional images to MNI space with ANTs WarpImageMultiTransform.
## 27. Use BBRegister to create registration matrices from functional -> fs space and convert_xfm to create inverse of those registration matrices (for fs -> functional registrations).
## 28. Use c3d_affine_tool to convert bbregister registration matrices from step 27 (functional ->  fs and fs -> functional). 
## 29. Use bbregister ITK matrices from step 27 (functional -> fs) and ANTs deformation fields (fs -> NIH) to register functional images to NIH space with ANTs WarpImageMultiTransform.
## 30. Use bbregister ITK matrices from step 27 (functional -> fs) and ANTs deformation fields (fs -> NIH, NIH -> MNI) to register functional images to MNI space with ANTs WarpImageMultiTransform.



if [ $# -lt 1 ]; then
	echo
	echo   "bash RegisterFunc.sh <subject_id>"
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
LOGFILE=${SUBJECT_DIR}/logfiles/RegisterFunc.log

FWHM=5

cd ${SUBJECT_DIR}
source /usr/local/freesurfer/stable5_3/SetUpFreeSurfer.sh
export SUBJECTS_DIR=${FS_DIR}
export ANTSPATH=${ANTS_DIR}


## 23. Use FSL's epi_reg to register functional (despiked) images to T1. 

if [[ ! -f xfm_dir/Emo2_to_T1.mat ]]; then
	echo " **** 23. Using epi_reg to register despiked functional images to T1..." | ts | tee -a ${LOGFILE}
	
	for i in emo/Emo1 emo/Emo2; do
		RUN=`basename $i`
		fslroi ${i}_despike.nii.gz ${i}_despike_vol0.nii.gz 0 1
		epi_reg --epi=${i}_despike_vol0.nii.gz --t1=mprage/T1.nii.gz --t1brain=mprage/T1_brain.nii.gz --out=xfm_dir/${RUN}_to_T1
		convert_xfm -omat xfm_dir/T1_to_${RUN}.mat -inverse xfm_dir/${RUN}_to_T1.mat
	done
fi


## 24. Use c3d_affine_tool to convert FSL’s epi_reg registration matrices from step 23 (functional -> T1) to ITK format (suffix: _ras.txt). 

if [[ ! -f xfm_dir/Emo2_to_T1_ras.txt ]]; then
	echo " **** 24. Using c3d_affine_tool to convert epi_reg registration matrices to ITK format..." | ts | tee -a ${LOGFILE}
	
	for i in emo/Emo1 emo/Emo2; do
		RUN=`basename ${i}`
		${SCRIPTS_DIR}/c3d/bin/c3d_affine_tool -ref mprage/T1_brain.nii.gz -src ${i}_despike_vol0.nii.gz xfm_dir/${RUN}_to_T1.mat -fsl2ras -oitk xfm_dir/${RUN}_to_T1_ras.txt
		${SCRIPTS_DIR}/c3d/bin/c3d_affine_tool -ref ${i}_despike_vol0.nii.gz -src mprage/T1_brain.nii.gz xfm_dir/T1_to_${RUN}.mat -fsl2ras -oitk xfm_dir/T1_to_${RUN}_ras.txt
	done
fi


## 25. Use epi_reg ITK matrices from step 23 (functional -> T1) and ANTs deformation fields (T1 -> NIH) to register functional images to NIH space with ANTs WarpImageMultiTransform.
if [[ ! -f xfm_dir/Emo2_to_nih_epireg_ants.nii.gz ]]; then
	echo " **** 25. Using ANTs WarpImageMultiTransform to warp functional image to NIH space..." | ts | tee -a ${LOGFILE}
	
	for i in emo/Emo1 emo/Emo2; do
		RUN=`basename ${i}`
		${ANTS_DIR}/WarpImageMultiTransform 3 ${i}_despike_vol0.nii.gz xfm_dir/${RUN}_to_nih_epireg_ants.nii.gz -R ${NIH_BRAIN} xfm_dir/T1_to_nih_Warp.nii.gz xfm_dir/T1_to_nih_Affine.txt xfm_dir/${RUN}_to_T1_ras.txt
	done
fi


## 26. Use epi_reg ITK matrices from step 23 (functional -> T1) and ANTs deformation fields (T1 -> NIH, NIH -> MNI) to register functional images to MNI space with ANTs WarpImageMultiTransform.
if [[ ! -f xfm_dir/Emo2_to_mni_epireg_ants.nii.gz ]]; then
	echo " **** 26. Using ANTs WarpImageMultiTransform to warp functional image to MNI space..." | ts | tee -a ${LOGFILE}
	
	for i in emo/Emo1 emo/Emo2; do
		RUN=`basename ${i}`
		${ANTS_DIR}/WarpImageMultiTransform 3 ${i}_despike_vol0.nii.gz xfm_dir/${RUN}_to_mni_epireg_ants.nii.gz -R ${MNI_BRAIN} ${PROJECT_DIR}/Standard/NIHtoMNIWarp.nii.gz ${PROJECT_DIR}/Standard/NIHtoMNIAffine.txt xfm_dir/T1_to_nih_Warp.nii.gz xfm_dir/T1_to_nih_Affine.txt xfm_dir/${RUN}_to_T1_ras.txt
	done
fi


## 27. Use BBRegister to create registration matrices from functional -> fs space and convert_xfm to create inverse of those registration matrices (for fs -> functional registrations).
if [[ ! -f xfm_dir/Emo2_to_fs.mat ]]; then
	echo " **** 27. Using BBRegister to calculate Functional --> FreeSurfer registrations..." | ts | tee -a ${LOGFILE}
	
	for i in emo/Emo1 emo/Emo2; do
		RUN=`basename ${i}`
		bbregister --s ${SUBJECT} --mov ${i}_despike_vol0.nii.gz --reg xfm_dir/${RUN}_to_fs.dat --init-fsl --bold --o xfm_dir/${RUN}_to_fs.nii.gz --fslmat xfm_dir/${RUN}_to_fs.mat
		convert_xfm -omat xfm_dir/fs_to_${RUN}.mat -inverse xfm_dir/${RUN}_to_fs.mat
	done
fi


## 28. Use c3d_affine_tool to convert bbregister registration matrices from step 27 (functional ->  fs and fs -> functional). 
if [[ ! -f xfm_dir/Emo2_to_fs_ras.txt ]]; then
	echo " **** 28. Using c3d_affine_tool to convert BBRegister registration matrices..." | ts | tee -a ${LOGFILE}

	for i in emo/Emo1 emo/Emo2; do
		RUN=`basename ${i}`
		${SCRIPTS_DIR}/c3d/bin/c3d_affine_tool -ref ${FS_SUBJECT_DIR}/mri/brainmask.nii.gz -src ${i}_despike_vol0.nii.gz xfm_dir/${RUN}_to_fs.mat -fsl2ras -oitk xfm_dir/${RUN}_to_fs_ras.txt
		${SCRIPTS_DIR}/c3d/bin/c3d_affine_tool -ref ${i}_despike_vol0.nii.gz -src ${FS_SUBJECT_DIR}/mri/brainmask.nii.gz xfm_dir/fs_to_${RUN}.mat -fsl2ras -oitk xfm_dir/fs_to_${RUN}_ras.txt
	done
fi


## 29. Use bbregister ITK matrices from step 27 (functional -> fs) and ANTs deformation fields (fs -> NIH) to register functional images to NIH space with ANTs WarpImageMultiTransform.
if [[ -f xfm_dir/Emo2_to_nih_bbr_ants.nii.gz ]]; then
	echo " **** 29. Using ANTs WarpImageMultiTransform to warp functional image to NIH space..." | ts | tee -a ${LOGFILE}

	for i in emo/Emo1 emo/Emo2; do
		RUN=`basename ${i}`
		${ANTS_DIR}/WarpImageMultiTransform 3 ${i}_despike_vol0.nii.gz xfm_dir/${RUN}_to_nih_bbr_ants.nii.gz -R ${NIH_BRAIN} xfm_dir/fs_to_nih_Warp.nii.gz xfm_dir/fs_to_nih_Affine.txt xfm_dir/${RUN}_to_fs_ras.txt
	done
fi


## 30. Use bbregister ITK matrices from step 27 (functional -> fs) and ANTs deformation fields (fs -> NIH, NIH -> MNI) to register functional images to MNI space with ANTs WarpImageMultiTransform.
if [[ -f xfm_dir/Emo2_to_mni_bbr_ants.nii.gz ]]; then
	echo " **** 30. Using ANTs WarpImageMultiTransform to warp functional image to MNI space..." | ts | tee -a ${LOGFILE}

	for i in emo/Emo1 emo/Emo2; do
		RUN=`basename ${i}`
		
		${ANTS_DIR}/WarpImageMultiTransform 3 ${i}_despike_vol0.nii.gz ${i}_to_mni_bbr_ants.nii.gz -R ${MNI_BRAIN} ${PROJECT_DIR}/Standard/NIHtoMNIWarp.nii.gz ${PROJECT_DIR}/Standard/NIHtoMNIAffine.txt xfm_dir/fs_to_nih_Warp.nii.gz xfm_dir/fs_to_nih_Affine.txt xfm_dir/${RUN}_to_fs_ras.txt
	done
fi
