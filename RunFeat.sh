#!/bin/bash
# RunFeat.sh
## 37. Substitute subject and run-specific values into the first-level FSF template.
## 38. Use FSL's FEAT to run first-level FEAT analyses.
## 39. Use RegisterANTs.sh to register the first-level FEAT result images. 
## 40. Substitute subject and run-specific values into the second-level FSF templates.
## 41. Use FSL's FEAT to run higher-level FEAT analyses.


if [ $# -lt 1 ]; then
	echo
	echo   "bash RunFeat.sh <subject_id>"
	echo
	exit
fi

SUBJECT=$1
PROJECT_DIR=/mnt/stressdevlab/example_pipeline
SUBJECT_DIR=${PROJECT_DIR}/${SUBJECT}
SCRIPTS_DIR=/mnt/stressdevlab/scripts/Preprocessing
LOGFILE=${SUBJECT_DIR}/logfiles/RunFeat.log


cd ${SUBJECT_DIR}


## 37. Substitute subject and run-specific values into the first-level FSF template.

if [[ ! -f emo/Emo2.fsf ]]; then
	echo " **** 37. Customizing first-level FEAT template (FSF) file..." | ts | tee -a ${LOGFILE}
	
	for i in Emo1 Emo2; do
		NBVOLS=`cat emo/${i}_NVOLS.txt`
		sed -e "s|RUN|${i}|g" -e "s|NB|${NBVOLS}|g" -e "s|SUBJECT|${SUBJECT}|g" ${PROJECT_DIR}/templates/Emo_FL.fsf > emo/${i}.feat.fsf
	done
fi


## 38. Use FSL's FEAT to run first-level FEAT analyses.

if [[ ! -f emo/Emo2.feat/stats/cope9.nii.gz ]]; then
	echo " **** 38. Running first-level FEAT analyses..." | ts | tee -a ${LOGFILE}
	
	for i in Emo1 Emo2; do
		if [[ -d emo/${i}.feat ]]; then
			rm -r emo/${i}.feat
		fi

		feat emo/${i}.feat.fsf
	done
fi

## 39. Use RegisterANTs.sh to register the first-level FEAT result images. 

if [[ ! -f emo/Emo2.feat/reg-standard/stats/varcope9.nii.gz ]]; then
	echo " **** 39. Registering result images from the first-level FEAT analyses..." | ts | tee -a ${LOGFILE}
	
	for i in Emo1 Emo2; do
		bash ${SCRIPTS_DIR}/RegisterANTs.sh ${SUBJECT_DIR}/emo/${i}.feat emo ${i}
	done
fi


## 40. Substitute subject and run-specific values into the second-level FSF templates.

if [[ ! -f emo/EmoCompared.gfeat.fsf ]]; then
	echo " **** 40. Customizing higher-level FEAT template (FSF) files..." | ts | tee -a ${LOGFILE}
	
	sed -e "s|SUBJECT|${SUBJECT}|g" ${PROJECT_DIR}/templates/Emo_HL_1Sample.fsf > emo/EmoCombined.gfeat.fsf
	sed -e "s|SUBJECT|${SUBJECT}|g" ${PROJECT_DIR}/templates/Emo_HL_2Sample.fsf > emo/EmoCompared.gfeat.fsf
fi


## 41. Use FSL's FEAT to run higher-level FEAT analyses.

if [[ ! -f emo/EmoCombined.gfeat/cope1.feat/stats/cope1.nii.gz ]]; then
	echo " **** 41. Running higher-level FEAT analyses..." | ts | tee -a ${LOGFILE}
	
	for i in EmoCombined EmoCompared; do
		if [[ -d emo/${i}.gfeat ]]; then
			rm -r emo/${i}.gfeat
		fi

		feat emo/${i}.gfeat.fsf
	done
fi

