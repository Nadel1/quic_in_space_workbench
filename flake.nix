{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixnet.url = "github:Nadel1/nixnet?ref=workbench-integration";
    test-certs.url = "github:Nadel1/test-certs";
    quiche.url = "git+https://github.com/Nadel1/quiche?ref=further-research-plateau";
    quinn.url = "git+https://github.com/Nadel1/quinn/?ref=further-research";
  };

  outputs = inputs@{ flake-parts, ... }:
    let
      experimentDir = ./experiments;

      files = builtins.readDir experimentDir;

      configFiles =
        map (name: experimentDir + "/${name}")
          (builtins.filter
            (name:
              files.${name} == "regular"
              && builtins.match ".*\\.json" name != null)
            (builtins.attrNames files));

      experiments =
        builtins.concatLists (
          map
            (file:
              (builtins.fromJSON (builtins.readFile file)).experiments)
            configFiles
        );
      

      evaluationDetailFields = [
        "displayFunction"
        "evaluationFunction"
        "dataIndex"
        "colorBarName"
        "relevantEndpoint"
        "relevantFileEnding"
      ];
      prepareDirectory=dirName:
        ''
          i=0
          while [ -e "out/${dirName}$i" ]; do
            i=$((i+1))
          done
          mkdir -p "out/${dirName}$i"
          echo "Results will be stored in out/${dirName}$i"
          cd "out/${dirName}$i"
        ''
      ;


      generateEvaluationCsv = evaluations:
        builtins.concatStringsSep "\n"
          (map (evaluation: ''
            echo "Creating evaluation CSV: ${evaluation.name}.csv"
            echo "${builtins.concatStringsSep "," (builtins.concatLists (builtins.genList
              (i: [
                "length${toString i}"
                "index${toString i}"
              ])
              (builtins.length evaluation.sortingBucketsAndIndices)))}" > ${evaluation.name}.csv
            echo "${builtins.concatStringsSep "," (builtins.concatLists (map (length:
              [
                (toString length.length)
                (toString length.index)
              ]
            ) evaluation.sortingBucketsAndIndices))}" >> ${evaluation.name}.csv
            echo "${builtins.concatStringsSep "," evaluationDetailFields}" >> ${evaluation.name}.csv
            echo "${builtins.concatStringsSep "," (map (field:
              toString evaluation.evaluationDetails.${field}
            ) evaluationDetailFields)}" >> ${evaluation.name}.csv
          '') evaluations);

    in
    flake-parts.lib.mkFlake { inherit inputs; } {

      systems = inputs.nixnet.supportedSystems;

      perSystem = { inputs', pkgs, ... }:

        let
          buildExperiments = runName: exps:
          map (exp:
            let
              built = (import ./experiment.nix {
                inherit inputs' pkgs;
                experiment = exp;
                workDir = "out/{run}";
              }).default;
            in {
              name = exp.name;
              path = built;
            }
          ) exps;
        
      
        builtAllExperiments =
          buildExperiments "allExperiments" experiments;



        mkExperimentRunner =
          { name, config }:
          let
            experiments = buildExperiments name config.experiments;
          in
          pkgs.writeShellScriptBin name ''
            set -euo pipefail
        
            ${prepareDirectory name}
            ${generateEvaluationCsv config.evaluations}
        
            ${builtins.concatStringsSep "\n" (map (e: ''
              echo "Running ${e.name}"
              "${e.path}/bin/testbed"
            '') experiments)}
          '';
        in {

          packages.default =
            pkgs.runCommand "all-experiments" {} ''
              mkdir -p $out

              ${builtins.concatStringsSep "\n" (map (e: ''
                mkdir -p $out/${e.name}
                cp -r ${e.path}/* $out/${e.name}/
              '') builtAllExperiments)}
            '';
          # gather the outage experiments into one numbered subfolder
          packages.singleOutageSteadyExperiments =
            mkExperimentRunner {
              name = "singleOutageSteadyExperiments";
              config=(builtins.fromJSON(builtins.readFile ./experiments/single-outage-steady.json));
            };
          

          packages.singleOutageSlowstartExperiments =
            mkExperimentRunner {
              name = "singleOutageSlowstartExperiments";
              config=(builtins.fromJSON(builtins.readFile ./experiments/single-outage-slow-start.json));
            };

          packages.singleOutageSlowstartExperimentsQuiche =
            mkExperimentRunner {
              name = "singleOutageSlowstartExperimentsQuiche";
              config=(builtins.fromJSON(builtins.readFile ./experiments/single-outage-slow-start-quiche.json));
            };

          packages.twoOutagesSteadyExperiments =
            mkExperimentRunner {
              name = "twoOutagesSteadyExperiments";
              config=(builtins.fromJSON(builtins.readFile ./experiments/two-outages-steady.json));
            };
          
          packages.twoOutagesSlowstartExperiments =
            mkExperimentRunner {
              name = "twoOutagesSlowstartExperiments";
              config=(builtins.fromJSON(builtins.readFile ./experiments/two-outages-slow-start.json));
            };
          packages.carefulResumeExperiments =
             mkExperimentRunner {
              name = "carefulResume";
              config=(builtins.fromJSON(builtins.readFile ./experiments/careful-resume.json));
            };
          packages.ackFrequencyExperiments =
             mkExperimentRunner {
              name = "ackFrequency";
              config=(builtins.fromJSON(builtins.readFile ./experiments/ack-frequency.json));
            };
            
          };

          


    };
}