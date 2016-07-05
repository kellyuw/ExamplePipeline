#!/bin/bash -X
# subject_setup.sh 
## 1. Make directory structure for new subject folder.
## 2. Copy behavioral data from incoming folder to subject folder.
## 3. Copy folder containing PAR/RECs from incoming folder to subject folder and unzip contents.
## 4. Convert PAR/RECs to NIFTI files with ConvertR2A.
## 5. Convert DTI PAR/RECs with dcm2nii.
## 6. Clean names of converted NIFTI files and compress with gzip.


if [ $# -lt 1 ]; then
	echo
	echo   "bash subject_setup.sh <subject_id>"
	echo
	exit
fi

PROJECT_DIR=/mnt/stressdevlab/example_pipeline
SUBJECT=$1
SUBJECT_DIR=${PROJECT_DIR}/${SUBJECT}
SCRIPT_DIR=${PROJECT_DIR}/bin
STD_DIR=${PROJECT_DIR}/Standard
FS_DIR=${PROJECT_DIR}/raw_FreeSurfer
NIH_DIR="${PROJECT_DIR}/Standard"
FS_DIR=${PROJECT_DIR}/raw_FreeSurfer
ANTS_DIR=/usr/local/ANTs-2.1.0-rc3/bin
MNI_BRAIN=/usr/share/fsl/5.0/data/standard/MNI152_T1_2mm_brain.nii.gz
NIH_BRAIN="${NIH_DIR}/nihpd_t1_brain.nii.gz"
HWHM=3
FDTHRESH=3
TR=2

## 1. Make directory structure for new subject folder.
for FOLDER_NAME in behavior mprage emo dti parrecs nifti xfm_dir QA/Images QA/Reports; do
	mkdir -p ${SUBJECT_DIR}/${FOLDER_NAME}
done


## 2. Copy behavioral data from incoming folder to subject folder.
if [[ ! ${SUBJECT_DIR}/behavior/fMRI_COMBINED_TASKS_${SUBJECT}.txt ]]; then
	cp ${PROJECT_DIR}/incoming/*${SUBJECT}*.txt ${SUBJECT_DIR}/behavior/fMRI_COMBINED_TASKS_${SUBJECT}.txt
	cp ${PROJECT_DIR}/incoming/*${SUBJECT}*.edat2 ${SUBJECT_DIR}/behavior/fMRI_COMBINED_TASKS_${SUBJECT}.edat2
fi

## 3. Copy folder containing PAR/RECs from incoming folder to SUBJECT folder and unzip contents.
if [[ ! ${SUBJECT_DIR}/parrecs/*.PAR ]]; then
	Zipfile=`find ${PROJECT_DIR}/incoming -iname "*${SUBJECT}*.zip"`
	cp ${Zipfile} ${SUBJECT_DIR}/

	cd ${SUBJECT_DIR}
	unzip ${Zipfile}

	for i in PAR REC; do
		find -iname "*${i}" -exec mv -t ./ {} \+
		mv ${SUBJECT_DIR}/*.${i} parrecs/
	done

	rm -r *${SUBJECT}*
fi

## 4. Convert all PAR/RECs to NIFTI files with ConvertR2A.
if [[ ! ${SUBJECT_DIR}/nifti/*.nii ]]; then
	cp /mnt/home/ibic/bin/run_ConvertR2A.sh ${SUBJECT_DIR}
	cp /mnt/home/ibic/bin/ConvertR2A ${SUBJECT_DIR}
	bash run_ConvertR2A.sh /usr/local/MATLAB/MATLAB_Compiler_Runtime_8.1/v81 ${SUBJECT_DIR}/parrecs/
	mv ${SUBJECT_DIR}/parrecs/*.nii ${SUBJECT_DIR}/nifti
	rm ${SUBJECT_DIR}/run_ConvertR2A.sh
	rm -r ${SUBJECT_DIR}/ConvertR2A
fi

## 5. Convert DTI PAR/RECs separately with dcm2nii.
if [[ nifti/*DTI* ]]; then
	rm nifti/*DTI*
	for i in `ls parrecs/*DTI*.PAR`; do
		dcm2nii -d N -e N -o nifti -f N -g N -i N -n Y -p Y -v N ${i}
	done
fi

## 6. Clean names of converted NIFTI files and compress with gzip.
cd ${SUBJECT_DIR}/nifti
for i in `ls *.nii`; do
	if [[ ${i} == *Emo* ]] || [[ ${i} == *MPRAGE* ]] || [[ ${i} == *RS* ]] || [[ ${i} == *Survey* ]]; then
		NewName=`echo ${i} | awk -F "_" '{print $4}'`
		mv ${i} ${NewName}.nii
		gzip ${NewName}.nii
	else
		gzip ${i}
	fi
done



# PreReconAll.sh
## 7. Convert E-Prime text file to tab-delimited file and get onsets for tasks with python script.
## 8. Create movies of raw functional data (for later inclusion in QA reports).
## 9. Create symbolic links for processing of the data, while leaving the raw data in nifti directory for backup.
## 10. Start FreeSurfer recon-all with reoriented T1 image as input.

cd ${SUBJECT_DIR}
source /usr/local/freesurfer/stable5_3/SetUpFreeSurfer.sh
export SUBJECTS_DIR=${FS_DIR}

## 7. Convert E-Prime text file to tab-delimited file and get onsets for tasks with python script.
/usr/bin/eprime2tabfile behavior/fMRI_COMBINED_TASKS_${SUBJECT}.txt -o TempBeh.csv
NumLines=`cat TempBeh.csv | wc -l`
head -n 1 TempBeh.csv | sed 's/\./_/g' | sed 's/\(\[\|\]\)//g' > behavior/${SUBJECT}_reformatted_eprime.csv
tail -n `echo "${NumLines} - 1" | bc` TempBeh.csv >> behavior/${SUBJECT}_reformatted_eprime.csv
python ${PROJECT_DIR}/bin/Emo_onsets.py -i behavior/${SUBJECT}_reformatted_eprime.csv -o emo/
rm TempBeh.csv

## 8. Create movies of raw functional data (for later inclusion in QA reports).
for i in `ls nifti/*.nii.gz`; do
	if [[ ${i} != *DTI* ]]; then
		${PROJECT_DIR}/bin/functional_movies_new ${i} QA/Images 2
	fi
done

## 9. Create symbolic links for processing of the data, while leaving the raw data in nifti directory for backup.
ln -s ${SUBJECT_DIR}/nifti/MPRAGE.nii.gz ${SUBJECT_DIR}/mprage/MPRAGE.nii.gz
ln -s ${SUBJECT_DIR}/nifti/Emo1.nii.gz ${SUBJECT_DIR}/emo/Emo1.nii.gz
ln -s ${SUBJECT_DIR}/nifti/Emo2.nii.gz ${SUBJECT_DIR}/emo/Emo2.nii.gz
ln -s ${SUBJECT_DIR}/nifti/RS.nii.gz ${SUBJECT_DIR}/rest/REST.nii.gz
#ln -s ${SUBJECT_DIR}/nifti/DTI.nii.gz ${SUBJECT_DIR}/dti/DTI.nii.gz

## 10. Start FreeSurfer recon-all with reoriented T1 image as input.
fslreorient2std mprage/MPRAGE.nii.gz mprage/T1.nii.gz
#/usr/local/freesurfer/stable5_3/bin/recon-all -i mprage/T1.nii.gz -subjid ${SUBJECT} -all


# PostReconAll.sh
## 11. Use mri_binarize to extract WM and CSF masks in FreeSurfer space.
## 12. Register FreeSurfer brain to T1 space and perform skullstripping of T1 image (with FreeSurfer brainmask).
## 13. Use FreeSurfer brainmask to skullstrip T1 image.
## 14. Do segmentation with fast (required by epi-reg in later parts of pipeline).
## 15. Register T1 to NIH (custom template), MNI (2mm FSL), and FreeSurfer with ANTs.
## 16. Use optiBET for skull-stripping and register new skull-strip to nih and mni space (with ANTs).
## 17. Calculate similarity between the T1 image and template (for later inclusion in QA reports).


cd ${SUBJECT_DIR}
source /usr/local/freesurfer/stable5_3/SetUpFreeSurfer.sh
export SUBJECTS_DIR=${FS_DIR}
export ANTSPATH=${ANTS_DIR}

## 11. Use mri_binarize to extract WM and CSF masks in FreeSurfer space.
mri_binarize --i ${FS_DIR}/${SUBJECT}/mri/aparc+aseg.mgz --o fs_wm_mask.nii.gz --erode 1 --wm; mv fs_wm_mask.nii.gz xfm_dir/
mri_binarize --i ${FS_DIR}/${SUBJECT}/mri/aparc+aseg.mgz --o fs_csf_mask.nii.gz --erode 1 --ventricles; mv fs_csf_mask.nii.gz xfm_dir/

## 12. Register FreeSurfer brain to T1 space and perform skullstripping of T1 image (with FreeSurfer brainmask).
tkregister2 --mov ${FS_DIR}/${SUBJECT}/mri/orig.mgz --targ ${FS_DIR}/${SUBJECT}/mri/aparc+aseg.mgz --noedit --regheader --reg xfm_dir/fs_to_T1.dat --fslregout xfm_dir/fs_to_T1_init.mat
mri_convert ${FS_DIR}/${SUBJECT}/mri/orig.mgz ${FS_DIR}/${SUBJECT}/mri/orig.nii.gz
flirt -ref mprage/T1.nii.gz -in ${FS_DIR}/${SUBJECT}/mri/orig.nii.gz -init xfm_dir/fs_to_T1_init.mat -omat xfm_dir/fs_to_T1.mat
convert_xfm -omat xfm_dir/T1_to_fs.mat -inverse xfm_dir/fs_to_T1.mat

## 13. Use FreeSurfer brainmask to skullstrip T1 image.
mri_convert ${FS_DIR}/${SUBJECT}/mri/brainmask.mgz ${FS_DIR}/${SUBJECT}/mri/brainmask.nii.gz
flirt -ref mprage/T1.nii.gz -in ${FS_DIR}/${SUBJECT}/mri/brainmask.nii.gz -init xfm_dir/fs_to_T1.mat -applyxfm -out mprage/T1_brain.nii.gz
fslmaths mprage/T1_brain.nii.gz -bin mprage/T1_brain_mask.nii.gz

## 14. Do segmentation with fast (required by epi-reg in later parts of pipeline).
fast -n 3 -t 1 -o mprage/T1_brain mprage/T1_brain.nii.gz


## 15. Register T1 to NIH (custom template), MNI (2mm FSL), and FreeSurfer with ANTs.
# T1_to_nih registration
${ANTS_DIR}/antsIntroduction.sh -d 3 -i ${SUBJECT_DIR}/mprage/T1_brain.nii.gz -m 30x90x20 -o ${SUBJECT_DIR}/xfm_dir/T1_to_nih_ -s CC -r ${NIH_BRAIN} -t GR

# T1_to_mni registration
${ANTS_DIR}/WarpImageMultiTransform 3 ${SUBJECT_DIR}/mprage/T1_brain.nii.gz ${SUBJECT_DIR}/xfm_dir/T1_to_mni_deformed.nii.gz -R ${MNI_BRAIN} ${NIH_DIR}/NIHtoMNIAffine.txt ${NIH_DIR}/NIHtoMNIWarp.nii.gz ${SUBJECT_DIR}/xfm_dir/T1_to_nih_Affine.txt

# fs_to_nih registration
${ANTS_DIR}/antsIntroduction.sh -d 3 -i ${FS_DIR}/${SUBJECT}/mri/brainmask.mgz -m 30x90x20 -o ${SUBJECT_DIR}/xfm_dir/fs_to_nih_ -s CC -r ${NIH_BRAIN} -t GR

# fs_to_mni registration
${ANTS_DIR}/WarpImageMultiTransform 3 ${FS_DIR}/${SUBJECT}/mri/brainmask.mgz ${SUBJECT_DIR}/xfm_dir/fs_to_mni_deformed.nii.gz -R ${MNI_BRAIN} ${NIH_DIR}/NIHtoMNIWarp.nii.gz ${NIH_DIR}/NIHtoMNIAffine.txt ${SUBJECT_DIR}/xfm_dir/fs_to_nih_Warp.nii.gz ${SUBJECT_DIR}/xfm_dir/fs_to_nih_Affine.txt


## 16. Use optiBET for skull-stripping and register new skull-strip to nih and mni space (with ANTs).
#mprage/T1_optiBET_brain_mask.nii.gz
bash ${PROJECT_DIR}/bin/optiBET.sh -i mprage/T1.nii.gz -t

#xfm_dir/T1_optiBET_to_nih_flirt.mat
flirt -ref ${NIH_BRAIN} -in mprage/T1_optiBET_brain.nii.gz -omat xfm_dir/T1_optiBET_to_nih_flirt.mat -out xfm_dir/T1_optiBET_to_nih_flirt.nii.gz

#xfm_dir/nih_to_T1_optiBET_flirt.mat
convert_xfm -omat xfm_dir/nih_to_T1_optiBET_flirt.mat -inverse xfm_dir/T1_optiBET_to_nih_flirt.mat

#xfm_dir/T1_optiBET_to_mni_deformed.nii.gz
${ANTS_DIR}/WarpImageMultiTransform 3 ${SUBJECT_DIR}/mprage/T1_optiBET_brain.nii.gz ${SUBJECT_DIR}/xfm_dir/T1_optiBET_to_mni_deformed.nii.gz -R ${MNI_BRAIN} ${NIH_DIR}/NIHtoMNIWarp.nii.gz ${NIH_DIR}/NIHtoMNIAffine.txt ${SUBJECT_DIR}/xfm_dir/T1_to_nih_Warp.nii.gz ${SUBJECT_DIR}/xfm_dir/T1_to_nih_Affine.txt


## 17. Calculate similarity between the T1 image and template (for later inclusion in QA reports).
for i in nih mni; do

	if [[ ${i} == "nih" ]]; then
		TemplateBrain=${NIH_BRAIN}
	elif [[ ${i} == "mni" ]]; then
		TemplateBrain=${MNI_BRAIN}
	else
		echo "Error, unspecified template brain."
		exit 1
	fi

	MSQ=`${ANTS_DIR}/MeasureImageSimilarity 3 0 ${TemplateBrain} ${SUBJECT_DIR}/xfm_dir/T1_to_${i}_deformed.nii.gz | grep "MSQ" | awk '{print $$NF}'`
	CC=`${ANTS_DIR}/MeasureImageSimilarity 3 1 ${TemplateBrain} ${SUBJECT_DIR}/xfm_dir/T1_to_${i}_deformed.nii.gz | grep "CC" | awk '{print $$NF}'`
	MI=`${ANTS_DIR}/MeasureImageSimilarity 3 2 ${TemplateBrain} ${SUBJECT_DIR}/xfm_dir/T1_to_${i}_deformed.nii.gz | grep "MI" | awk '{print $$NF}'`
	echo "MSQ,CC,MI" > "QA/Images/T1_to_${i}_similarity.csv"
	echo "${MSQ},${CC},${MI}" >> "QA/Images/T1_to_${i}_similarity.csv"

done



# PreprocessFunc.sh
## 18. Use Alexis Roche's 4dRegister algorithm (from NiPy) for simultaneous slice-timing and motion correction of functional images.
## 19. Use fslval to find number of volumes and TR for each run.
## 20. Use bet for skull-stripping functional images with fractional intensity threshold of 0.3 (more conservative than default of 0.5).
## 21. Use AFNI 3dDespike to remove spikes from data.
## 22. Use SUSAN to spatially smooth despiked data.
## 23. Identify scanner spikes by interrogating the signal outside of the brain.
## 24. Use fslMotionOutliers (to find DVARS and FD outliers).
## 25. Make formatted list of all unique outliers.
## 26. Use SinglePointGenerator.py to create single-point regressor files
## 27. Use MotionRegressorGenerator.py to calculate summary statistics about motion.

cd ${SUBJECT_DIR}
source /usr/local/freesurfer/stable5_3/SetUpFreeSurfer.sh
export SUBJECTS_DIR=${FS_DIR}
export ANTSPATH=${ANTS_DIR}

## 18. Use Alexis Roche's 4dRegister algorithm (from NiPy) for simultaneous slice-timing and motion correction of functional images.
python ${SCRIPT_DIR}/4dRegister.py --inputs `ls emo/Emo?.nii.gz` --tr ${TR} --slice_order 'ascending'
python ${SCRIPT_DIR}/4dRegister.py --inputs `ls rest/REST.nii.gz` --tr ${TR} --slice_order 'ascending'


for i in emo/Emo1 emo/Emo2 rest/REST ; do

	## 19. Use fslval to find number of volumes and TR for each run.
	vols=`fslval ${i}.nii.gz dim4`
	TR=`fslval ${i}.nii.gz pixdim4`

	## 20. Use bet for skull-stripping functional images with fractional intensity threshold of 0.3 (more conservative than default of 0.5).
	fslroi ${i}_mc.nii.gz vol0 0 1
	bet vol0 vol0 -f 0.3
	fslmaths vol0 -bin vol0
	fslmaths ${i}_mc.nii.gz -mas vol0 ${i}_bet.nii.gz
	rm vol0

	## 21. Use AFNI 3dDespike to remove spikes from data.
	3dDespike -ssave spikiness -q ${i}.nii.gz

	for j in despike spikiness; do
		3dAFNItoNIFTI ${j}+orig.BRIK
		mv ${j}.nii ${i}_${j}.nii
		gzip ${i}_${j}.nii
		rm -f ${j}+orig*
	done

	## 22. Use SUSAN to spatially smooth despiked data.
	susan ${i}_despike.nii.gz -1.0 ${HWHM} 3 1 0 ${i}_ssmooth.nii.gz

	## 23. Identify scanner spikes by interrogating the signal outside of the brain.
	bash ${SCRIPT_DIR}/ibicIDSN.sh ${i}.nii.gz ${TR}

	## 24. Use fslMotionOutliers (to find DVARS and FD outliers).
	${SCRIPT_DIR}/motion_outliers -i ${i}_bet.nii.gz -o ${i}_dvars_regressors --dvars -s ${i}_dvars_vals --nomoco
	${SCRIPT_DIR}/motion_outliers -i ${i}_bet.nii.gz -o ${i}_fd_regressors --fd -s ${i}_fd_vals -c ${i}.par --nomoco --thresh=${FDTHRESH}

	for j in dvars fd; do
		mv `dirname ${i}`/${j}_thresh ${i}_${j}_thresh
		mv `dirname ${i}`/${j}_spike_vols ${i}_${j}_spike_vols
	done

	## 25. Make formatted list of all unique outliers.
	cat ${i}_dvars_spike_vols | transpose > alloutliers.txt
	cat ${i}_fd_spike_vols | transpose >> alloutliers.txt
	cat "${i}_SN_outliers.txt" >> alloutliers.txt
	sort -nu alloutliers.txt > "${i}_all_outliers.txt"
	rm alloutliers.txt

	## 26. Use SinglePointGenerator.py to create single-point regressor files
	python ${SCRIPT_DIR}/SinglePointGenerator.py -i ${i}_all_outliers.txt -v ${vols} -o ${i}_outlier_regressors.txt -p ${i}_percent_outliers.txt

	## 27. Use MotionRegressorGenerator.py to calculate summary statistics about motion.
	python ${SCRIPT_DIR}/MotionRegressorGenerator.py -i ${i}.par -o ${i}

done

