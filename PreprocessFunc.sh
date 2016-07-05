#!/bin/bash
# PreprocessFunc.sh
## 18. Use Alexis Roche's 4dRegister algorithm (from NiPy) for simultaneous slice-timing and motion correction of functional images.
## 19. Use fslval to find number of volumes and TR for each run.
## 20. Use bet for skull-stripping functional images with fractional intensity threshold of 0.3 (more conservative than default of 0.5).
## 21. Use AFNI 3dDespike to remove spikes from data.
## 22. Use SUSAN to spatially smooth despiked data.


if [ $# -lt 1 ]; then
	echo
	echo   "bash PreprocessFunc.sh <subject_id>"
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
LOGFILE=${SUBJECT_DIR}/logfiles/PreprocessFunc.log

FWHM=5


cd ${SUBJECT_DIR}
source /usr/local/freesurfer/stable5_3/SetUpFreeSurfer.sh
export SUBJECTS_DIR=${FS_DIR}
export ANTSPATH=${ANTS_DIR}


##18. Use fslval to get TR and number of volumes for each run.
if [[ ! -f emo/Emo2_TR.txt ]]; then
	echo " **** 18. Using fslval to find number of volumes and TR for each run..." | ts | tee -a ${LOGFILE}
	
	for i in emo/Emo1 emo/Emo2; do
		fslval ${i}.nii.gz dim4 | tee ${i}_NVOLS.txt
		fslval ${i}.nii.gz pixdim4 | tee ${i}_TR.txt
	done
fi


## 19. Use Alexis Roche's 4dRegister algorithm (from NiPy) for simultaneous slice-timing and motion correction of functional images.
if [[ ! -f ${SUBJECT_DIR}/emo/Emo2_mc.nii.gz ]]; then
	echo " **** 19. Using 4dRegister.py to apply simultaneous slice-timing and motion correction to functional images..." | ts | tee -a ${LOGFILE}
	python ${SCRIPTS_DIR}/4dRegister.py --inputs `ls emo/Emo?.nii.gz` --tr `cat emo/Emo1_TR.txt` --slice_order 'ascending'
fi


for i in emo/Emo1 emo/Emo2; do

	## 20. Use bet for skull-stripping functional images with fractional intensity threshold of 0.3 (more conservative than default of 0.5).
	if [[ ! -f ${i}_bet.nii.gz ]]; then
		echo " **** 20. Using bet to skull-strip functional images..." | ts | tee -a ${LOGFILE}

		fslroi ${i}_mc.nii.gz vol0 0 1
		bet vol0 vol0 -f 0.3
		fslmaths vol0 -bin vol0
		fslmaths ${i}_mc.nii.gz -mas vol0 ${i}_bet.nii.gz
		rm vol0
	fi

	## 21. Use AFNI 3dDespike to remove spikes from data.
	if [[ ! -f ${i}_despike.nii.gz ]]; then
		echo " **** 21. Using AFNI 3dDespike to despike functional images..." | ts | tee -a ${LOGFILE}

		3dDespike -ssave spikiness -q ${i}_bet.nii.gz

		for j in despike spikiness; do
			3dAFNItoNIFTI ${j}+orig.BRIK
			mv ${j}.nii ${i}_${j}.nii
			gzip ${i}_${j}.nii
			rm -f ${j}+orig*
		done
	fi


	## 22. Use SUSAN to spatially smooth despiked data.
	if [[ ! -f ${i}_ssmooth.nii.gz ]]; then
		echo " **** 22. Using SUSAN to spatially smooth despiked data..." | ts | tee -a ${LOGFILE}

		fslmaths ${i}_despike.nii.gz -Tmean ${i}_despike_mean.nii.gz
		fslmaths ${i}_despike.nii.gz -bin ${i}_despike_mask.nii.gz

		HWHM=`echo ${FWHM} | awk '{print $1/(2*sqrt(2*log(2)))}'`
		MedBT=`fslstats ${i}_despike.nii.gz -k ${i}_despike_mask.nii.gz -p 50`
		BTThresh=`echo $${MedBT} | awk '{print ($1*0.75) }'`
		echo "Sigma is $HWHM mm" 
		echo "Brightness Threshold is $BTThresh"
		susan ${i}_despike.nii.gz ${BTThresh} ${HWHM} 3 1 1 ${i}_despike_mean.nii.gz ${BTThresh} ${i}_ssmooth.nii.gz
	fi
done
exit

#Move to PrepareFeat.sh

	## 23. Identify scanner spikes by interrogating the signal outside of the brain.
	if [[ ! -f ${i}_SN_outliers ]]; then
		echo " **** 23. Running ibicIDSN to identify signal noise outliers..." | ts | tee -a ${LOGFILE}
		bash ${SCRIPTS_DIR}/ibicIDSN.sh ${i}.nii.gz `cat ${i}_TR.txt`
	fi


	## 24. Use fslMotionOutliers (to find DVARS and FD outliers).
	if [[ ! -f ${i}_fd_regressors ]]; then

		echo " **** 24. Using fslMotionOutliers to find DVARS and FD outlier volumes..." | ts | tee -a ${LOGFILE}

		${SCRIPTS_DIR}/motion_outliers -i ${i}_bet.nii.gz -o ${i}_dvars_regressors --dvars -s ${i}_dvars_vals --nomoco
		${SCRIPTS_DIR}/motion_outliers -i ${i}_bet.nii.gz -o ${i}_fd_regressors --fd -s ${i}_fd_vals -c ${i}.par --nomoco --thresh=${FDTHRESH}

		for j in dvars fd; do
			mv `dirname ${i}`/${j}_thresh ${i}_${j}_thresh
			mv `dirname ${i}`/${j}_spike_vols ${i}_${j}_spike_vols
		done
	fi


	## 25. Make formatted list of all unique outliers
	if [[ ! -f ${i}_all_outliers.txt ]]; then
		echo " **** 25. Making list of unique outlier volumes..." | ts | tee -a ${LOGFILE}

		cat ${i}_dvars_spike_vols | ${SCRIPTS_DIR}/transpose.awk > alloutliers.txt
		cat ${i}_fd_spike_vols | ${SCRIPTS_DIR}/transpose.awk >> alloutliers.txt
		cat "${i}_SN_outliers.txt" >> alloutliers.txt
		sort -nu alloutliers.txt > "${i}_all_outliers.txt"
		rm alloutliers.txt
	fi

	
	## 26. Use SinglePointGenerator.py to create single-point regressor files
	if [[ ! -f ${i}_percent_outliers.txt ]]; then
		
		echo "Using SinglePointGenerator.py to create formatted single-point regressor files..." | ts | tee -a ${LOGFILE}
		python ${SCRIPTS_DIR}/SinglePointGenerator.py -i ${i}_all_outliers.txt -v `cat ${i}_NVOLS.txt` -o ${i}_outlier_regressors.txt -p ${i}_percent_outliers.txt
	
	fi

	## 27. Use MotionRegressorGenerator.py to calculate summary statistics about motion.
	#python ${SCRIPTS_DIR}/MotionRegressorGenerator.py -i ${i}.par -o ${i}

done

