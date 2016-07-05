import numpy as np
import argparse
import csv

#Pull the data in based on a parameter entered at the command line
parser = argparse.ArgumentParser()
parser.add_argument('--input', '-i', required=True, help='Name of tab-delimited text file to import')
parser.add_argument('--output', '-o', required=True, help='Output path')

filename = parser.parse_args().input
Output=parser.parse_args().output

#Get the data into an array
data=np.genfromtxt(filename, dtype=None, delimiter='\t', names=True, autostrip=True)

for Run in ['1','2']:
    
    #Find trials that need to be regressed out
    GameStim = 'GameStim' + str(Run)
    GameStimOnset=((data[GameStim + '_OnsetTime'][data[GameStim + '_OnsetTime']>0]-data['TriggerWAIT_RTTime'][data[GameStim + '_OnsetTime']>0])/float(1000))[0]
    GameStimDuration=((data[GameStim + '_OnsetToOnsetTime'][data[GameStim + '_OnsetTime']>0])/float(1000))[0]
    
    print 'GameStim' + str(Run) + 'Onset: ' + str(GameStimOnset)
    print 'GameStim' + str(Run) + 'Duration: ' + str(GameStimDuration)
    
    OutputFile=open((Output + 'Emo' + str(Run) + '_GameStim.txt'), "w")
    writer = csv.writer(OutputFile, delimiter=' ')
    writer.writerow([str(GameStimOnset), str(GameStimDuration), str(1)])
    OutputFile.close()
    

    #Get Block Onsets
    ProcBlock = 'ThreatReactivity'+str(Run)
    for List in ['CalmList','HappyList','FearList','ScrambledListOne','ScrambledListTwo']:
        print List    
        
        NumBlocks = len((data['ReactivityITI_OnsetTime'][np.logical_and(np.logical_and(data['ProcedureBlock']==str(ProcBlock),data['RunningSubTrial']==List),data['SubTrial']==1)]))
        #print NumBlocks
        
        FirstTriggerWaitRTTime = (data['TriggerWAIT_RTTime'][np.logical_and(np.logical_and(data['ProcedureBlock']==str(ProcBlock),data['RunningSubTrial']==List),data['SubTrial']==1)])
        #print FirstTriggerWaitRTTime
        
        FirstReactivityITIOnsetTime = (data['ReactivityITI_OnsetTime'][np.logical_and(np.logical_and(data['ProcedureBlock']==str(ProcBlock),data['RunningSubTrial']==List),data['SubTrial']==1)])
        #print FirstReactivityITIOnsetTime
        
        BlockOnsets = (FirstReactivityITIOnsetTime - FirstTriggerWaitRTTime) / float(1000)
        print BlockOnsets
        
        LastTriggerWaitRTTime = (data['TriggerWAIT_RTTime'][np.logical_and(np.logical_and(data['ProcedureBlock']==str(ProcBlock),data['RunningSubTrial']==List),data['SubTrial']==36)])
        #print LastTriggerWaitRTTime
        
        LastReactivityITIOnsetTime = (data['ReactivityITI_OnsetTime'][np.logical_and(np.logical_and(data['ProcedureBlock']==str(ProcBlock),data['RunningSubTrial']==List),data['SubTrial']==36)])
        #print LastReactivityITIOnsetTime
        
        BlockOffsets = (LastReactivityITIOnsetTime - LastTriggerWaitRTTime) / float(1000)
        #print BlockOffsets
        
        BlockDurations = BlockOffsets - BlockOnsets
        print BlockDurations
        
        #Make short name for conditions
        ShortCon = str(List)[0]

        if (ShortCon == 'S' ):        
            OutputFile=open(Output + 'Emo' + str(Run) + '_' + str(ShortCon) + '.txt', "a")
        else:
            OutputFile=open(Output + 'Emo' + str(Run) + '_' + str(ShortCon) + '.txt', "w")

        writer = csv.writer(OutputFile, delimiter=' ')
        for row in range(0,len(BlockOnsets)):
            writer.writerow([str(BlockOnsets[row]), str(BlockDurations[row]), str(1)])
        OutputFile.close()
