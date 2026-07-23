import json
import itertools
import sys




NECESSARY_EXPERIMENT_KEYS_AND_INDICES = {
    "implementation":1,
    "congestion":3,
    "download":-1,
    "rateMbit":7,
    "delayMs":5,
    "lossPercent":9,
    "outageType":15,
    "maxIdleTimeout":-1,
    "outageAmount":13,
    "outageDuration":11,
}

    

OPTIONAL_EXPERIMENT_KEYS_AND_INDICES= {
    "ackThreshold":15,
    "ackDelay":17,
    "carefulResume":16,
}




def resolve_ack_delay(value, delay):
    """Resolve delay expressions into numeric values."""
    if isinstance(value, int):
        return value

    expressions = {
        "delay*2/4": delay * 2 // 4,
        "delay*2/2": delay * 2 // 2,
        "delay*2*3/4": delay * 2 * 3 // 4,
        "delay*2": delay * 2,
        "delay*2*2": delay * 2 * 2,
        "delay*2*4": delay * 2 * 4,
    }

    return expressions.get(value, value)


def createName(exp):
    try:
        ackThreshold = exp['ackThreshold']
    except KeyError:
        ackThreshold = 2
    
    try:
        maxAckDelay = exp['ackDelay']
    except KeyError:
        maxAckDelay = 25

    return (
        f"implementation_{exp['implementation']}-"
        f"cca_{exp['congestion']}-"
        f"delay_{exp['delayMs']}ms-"
        f"rate_{exp['rateMbit']}Mbps-"
        f"download_{exp['download']}-"
        f"loss_{exp['lossPercent']}-"
        f"outageDuration_{exp['outageDuration']}-"
        f"outageAmount_{exp['outageAmount']}-"
        f"outageType_{exp['outageType']}-"
        f"ackThreshold_{ackThreshold}-"
        f"maxAckDelay_{maxAckDelay}"
    )


def generateExperiments(config):
    experiments = []
    missing = [
        k for k in NECESSARY_EXPERIMENT_KEYS_AND_INDICES.keys()
        if k not in config
    ]
    if missing:
        raise KeyError(f"Missing required config keys: {missing}")

    # Include optional keys only if present
    experimentKeys =  set(NECESSARY_EXPERIMENT_KEYS_AND_INDICES.keys()).union(
        k for k in OPTIONAL_EXPERIMENT_KEYS_AND_INDICES.keys() if k in config
    )


    experimentValues = [config[k] for k in experimentKeys]


    for combination in itertools.product(*experimentValues):
        exp = dict(zip(experimentKeys, combination))
        if "ackDelay" in exp:
            exp["ackDelay"] = resolve_ack_delay(
                exp.pop("ackDelay"),
                exp["delayMs"]
            )

        exp["name"] = createName(exp)

        experiments.append(exp)

    sortingBuckets = []
    sortingParameters = {
        k: v
        for k, v in (
            NECESSARY_EXPERIMENT_KEYS_AND_INDICES
            | OPTIONAL_EXPERIMENT_KEYS_AND_INDICES
        ).items()
        if k in config
    }
    for parameter, index in sortingParameters.items():
        length = len(config[parameter])

        sortingBuckets.append({
            "length": length,
            "index": index
        })
    evaluations = []
    try:
        evaluationValues = config["evaluationParams"] 
        evaluationDetails = []
        evaluationValues = config["evaluationParams"] 
        for e in evaluationValues:
            e["sortingBucketsAndIndices"] = sortingBuckets
            evaluations.append(e)
   
    except KeyError:
        print("No evaluation parameters provided!")    
    result = {
        "experiments": experiments,
        "evaluations": evaluations,
    }
    return result

def genExperiment(configFile):
    with open(configFile) as f:
        config = json.load(f)

    result = generateExperiments(config)
    with open(f"../experiments/{configFile}", "w") as f:
        json.dump(result, f, indent=4)
    print(f"Generated {len(result['experiments'])} experiments in ../experiments/{configFile}\n")

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(f"""
============================================================
Experiment Description Generator
============================================================

Generate experiment descriptions from a single JSON configuration file.

Usage:
    python {sys.argv[0]} <config>.json

Required configuration keys:
    {NECESSARY_EXPERIMENT_KEYS}

Optional configuration keys:
    {OPTIONAL_EXPERIMENT_KEYS}

Notes:
  • The script will fail if any required configuration key is missing.
  • The provided values is used to determine:
      - the order and the sorting parameter index (based on '_' and '-' separation)
      - the length of each parameter
  • Evaluation parameters must also be provided.
    Each evaluation parameter consists of:
      - a name
      - evaluationDetails

The final experiment config will bear the same name as the provided config and be found in ../experiments.
For examples and a description of the evaluation parameters,
please refer to the provided configuration files.

============================================================
""")
        exit(0)
    genExperiment(sys.argv[1])