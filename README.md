# Quic in space workbench

## Installation and Setup

Nix has to be installed to execute this workbench. See [the official NixOS website](https://nixos.org/download/) for instructions.

> If the installation fails with ``~~> Setting up the build group nixbld groupadd: GID '30000' already exists``, first verify that this id is truly taken (`getent group 30000`). Look for a free range, for example by testing other group ids. Export the new id using ` export NIX_BUILD_GROUP_ID=<x>` and `export NIX_FIRST_BUILD_UID=<x>` and retry the installation. (see: [NixOS issue](https://github.com/NixOS/nix/issues/6224#issuecomment-1063294431))


We use experimental Nix features, namely `nix-command` and `flakes`  which need to be enabled first to work seamlessly. Modify your config file found under `~/.config/nix/nix.conf` with this line:

    experimental-features = nix-command flakes

Create the file and directory if they do not exist. 

## Executing an experiment group

The idea of this workbench is to allow the easy execution of groups of experiments (family of experiments) with varying parameters, to evaluate how these parameters influence the performance of the connection. 

To build all experiments execute

    nix build

To execute a group a experiments, execute:

    nix run .#<name>

Currently supported experiments are:

    - singleOutageSteadyExperiments
    - singleOutageSlowstartExperiments 
    - singleOutageSlowstartExperimentsQuiche
    - twoOutagesSteadyExperiments 
    - twoOutagesSlowstartExperiments
    - carefulResumeExperiments 
    - ackFrequencyExperiments 

## Adding a new experiment group

To add a new experiment group, add a new config in the *configs* folder. You have to define the following parameters:

    "implementation"
    "congestion"
    "download"
    "rateMbit"
    "delayMs"
    "lossPercent"
    "outageType"
    "maxIdleTimeout"
    "outageAmount"
    "outageDuration"

Currently, the only two supported implementations are "quiche" and "quinn". For outageTypes currently supported are "none", "steady" and "slowstart". Up to two outages are allowed. 

You can also define optional parameters:

    "ackThreshold"
    "ackDelay"
    "carefulResume"

While only Quinn currently supports ACK Frequency, both Quiche and Quinn have Careful Resume implemented. The ackDelay is defined relative to the currently used rtt.

You can also define evaluationParameters; this is optional, as I did not have the time implement automatic evaluation. 

This is an example how to populate the evaluationParams:

    "evaluationParams": [
        {
            "name": "evaluationParams",
            "evaluationDetails": {
                "displayFunction": "displayHeatmapCumulative",
                "evaluationFunction": "calculateCumulativeDataOverTime",
                "dataIndex": "3",
                "colorBarName": "Throughput [Bps]",
                "relevantEndpoint": "client",
                "relevantFileEnding": "csv"
            }
        }
    ]

The name will be the name of the .csv in which these evaluation parameters will be copied and then used to evaluate the experiment. The script deducts which parameters were given and how manye (1 or 2 implementations, 2 or 3 RTTs and so on) and populate the csv with both the index of said parameter in each experiment name and the number of possible choices. This can then be used to order the experiments and evaluate them. The details given in the evaluationParams can be used to define the display Function, evaluationFunction, which endpoint is relevant for the respective evaluation and so on. You can also add multiple evaluationParams which will then translate to multiple .csv files.


To translate your config into actual experiment descriptions that can then be used by the flake, you can either execute the `generateExperiment.py` script, which will translate a single experiment config into experiments, or `generateAllExperiments.py` to generate all experiments based on the configs in the configs directory.

Once you have your experiments set up, you have to add them to the `flake.nix`:

          packages.<nameOfExperiment> =
             mkExperimentRunner {
              name = <nameOfExperiment>;
              config=(builtins.fromJSON(builtins.readFile <
              ./experiments/experimentConfig>));
            };

And then you are good to go.


## Notes

Nix does not run out of the box on _all_ machines. If you dont fully own the machine you are trying to run Nix on... good luck. Figuring this out cost me a good chunk of time, so here is what I learned;

1. Installing Nix can be tricky (see installation point of this readme)
2. If executing nix terminates with a write error, this may be due to the fact that your home directory is not writable by other users besides yourself. The nix builders _are_ other users, so they need to be able to write to the home directory. You can either check if you have a data mount available and execute your nix experiments there, or add your own user to the same users as the nix builders (I went the second route, but never got it to work because of the next error)
3. If you get `error: cannot open connection to remote store 'daemon': error: read of 32768 bytes: Connection reset by peer` ... good luck. 
4. If you get `unshare: unshare failed: Invalid argument`, check out https://github.com/birneee/nixnet/issues/23

### Connection reset by peer

If you get 

> error: cannot open connection to remote store 'daemon': error: read of 32768 bytes: Connection reset by peer

for example when you are trying to execute 

    nix store info

you are in for a rough ride. Try an strace ( `strace -f -s 256  nix store info` ) to see what is going on. In my case, my user was explicitly not accepted and a ECONNRESET was triggered, even though my user was explicitly allowed and trusted (check with `cat /etc/nix/nix.conf`).

In the end, I simply moved to another machine where Nix was already working. To this day, I do not know why I never got it to work. If you are ever able to recover from this error, let me know.