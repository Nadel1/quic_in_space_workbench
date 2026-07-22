import os 
import generateExperiments

for entry in os.scandir("."):  
    if entry.is_file() and entry.path.endswith('.json'): 
        print(entry.path)
        generateExperiments.genExperiment(entry.path)
