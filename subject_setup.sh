#!/bin/bash -X
# subject_setup.sh 
## 1. Make directory structure for new subject folder.
## 2. Copy behavioral data from incoming folder to subject folder.
## 3. Copy folder containing PAR/RECs from incoming folder to subject folder and unzip contents.
## 4. Convert PAR/RECs to NIFTI files with ConvertR2A.
## 5. Convert DTI PAR/RECs with parrec2nii.
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


## 1. Make directory structure for new subject folder.
if [[ ! -d ${SUBJECT_DIR}/nifti ]]; then
	echo "1. Making directory structure for new subject folder (/mnt/stressdevlab/example_pipeline/100)..."
	for FOLDER_NAME in behavior mprage emo dti parrecs nifti xfm_dir QA/Images QA/Reports; do
		mkdir -p ${SUBJECT_DIR}/${FOLDER_NAME}
	done
fi
exi


## 2. Copy behavioral data from incoming folder to subject folder.
if [[ ! -f ${SUBJECT_DIR}/behavior/fMRI_COMBINED_TASKS_${SUBJECT}.txt ]]; then
	echo "2. Copying behavioral data from incoming directory to subject folder..."

	cp ${PROJECT_DIR}/incoming/*${SUBJECT}*.txt ${SUBJECT_DIR}/behavior/fMRI_COMBINED_TASKS_${SUBJECT}.txt
	cp ${PROJECT_DIR}/incoming/*${SUBJECT}*.edat2 ${SUBJECT_DIR}/behavior/fMRI_COMBINED_TASKS_${SUBJECT}.edat2
fi


## 3. Copy folder containing PAR/RECs from incoming folder to SUBJECT folder and unzip contents.
if [[ ! -f ${SUBJECT_DIR}/parrecs/MPRAGE.PAR ]]; then
	echo "3. Copying imaging data from incoming directory to subject folder..."

	Zipfile=`find ${PROJECT_DIR}/incoming -iname "*${SUBJECT}*.zip"`
	echo ${Zipfile}
	cp ${Zipfile} ${SUBJECT_DIR}/

	cd ${SUBJECT_DIR}
	unzip ${Zipfile}
	cd `basename ${Zipfile} .zip`

	mv *.PAR ${SUBJECT_DIR}/parrecs/
	mv *.REC ${SUBJECT_DIR}/parrecs/

	cd ${SUBJECT_DIR}
	rm -r `basename ${Zipfile} .zip`
fi


## 4. Convert all PAR/RECs to NIFTI files with ConvertR2A.
if [[ ! -f ${SUBJECT_DIR}/nifti/MPRAGE.nii ]]; then
	echo "4. Converting PAR/RECs to NIFTI files with ConvertR2A..."

	cp /mnt/home/ibic/bin/run_ConvertR2A.sh ${SUBJECT_DIR}
	cp /mnt/home/ibic/bin/ConvertR2A ${SUBJECT_DIR}
	bash run_ConvertR2A.sh /usr/local/MATLAB/MATLAB_Compiler_Runtime/v81 ${SUBJECT_DIR}/parrecs/
	mv ${SUBJECT_DIR}/parrecs/*.nii ${SUBJECT_DIR}/nifti
	rm ${SUBJECT_DIR}/run_ConvertR2A.sh
	rm -r ${SUBJECT_DIR}/ConvertR2A
fi


## 5. Convert DTI PAR/RECs separately with parrec2nii.
if [[ ! -f ${SUBJECT_DIR}/nifti/*DTI* ]]; then
	echo "5. Converting DTI PAR/RECs with parrec2nii..."

	rm ${SUBJECT_DIR}/nifti/*DTI*
	for i in `ls parrecs/*DTI*.PAR`; do
		parrec2nii -v -b -d --field-strength=3 --keep-trace --store-header -c -o ${SUBJECT_DIR}/nifti ${SUBJECT_DIR}/${i}
	done
fi


## 6. standardize names of converted NIFTI files, compress with gzip, and add symbolic links.
if [[ ! -f ${SUBJECT_DIR}/mprage/MPRAGE.nii.gz ]]; then

	cd ${SUBJECT_DIR}/nifti
	for i in `ls *.nii`; do
		if [[ ${i} == *Emo* ]] || [[ ${i} == *MPRAGE* ]] || [[ ${i} == *Survey* ]]; then
			NewName=`echo ${i} | awk -F "_" '{print $4}'`
			echo "6. Renaming NIFTI image: **** ${i} --> ${NewName} ****"
			mv ${i} ${NewName}.nii
			gzip ${NewName}.nii


			if [[ ${NewName} == *Emo* ]]; then
				ln -s ${SUBJECT_DIR}/nifti/${NewName}.nii.gz ${SUBJECT_DIR}/emo/${NewName}.nii.gz
			elif [[ ${NewName} == *MPRAGE* ]]; then
				ln -s ${SUBJECT_DIR}/nifti/${NewName}.nii.gz ${SUBJECT_DIR}/mprage/${NewName}.nii.gz
			elif [[ ${NewName} == *RS* ]]; then
				ln -s ${SUBJECT_DIR}/nifti/${NewName}.nii.gz ${SUBJECT_DIR}/rest/${NewName}.nii.gz
			elif [[ ${NewName} == *DTI* ]]; then
				ln -s ${SUBJECT_DIR}/nifti/${NewName}.nii.gz ${SUBJECT_DIR}/dti/${NewName}.nii.gz
			fi

		else
			gzip ${i}
		fi
	done
fi
