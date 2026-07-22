{ inputs', pkgs, experiment, workDir ? "out/{run}" }:

let
  nixnet = inputs'.nixnet.legacyPackages;

  # --- parameters from JSON ---
  name=experiment.name;
  rateMbit = experiment.rateMbit;
  delayMs  = experiment.delayMs;
  lossPercent = experiment.lossPercent;
  congestion = experiment.congestion;
  implementation = experiment.implementation;
  download = experiment.download;
  maxIdleTimeout=toString experiment.maxIdleTimeout;
  outageDuration = if experiment?"outageDuration" then experiment.outageDuration else "0";
  outageAmount = if experiment?"outageAmount" then experiment.outageAmount else "0";
  outageType = if experiment?"outageType" then experiment.outageType else "None";
  carefulResume = if experiment?"carefulResume" then experiment.carefulResume else false;
  ackThreshold = if experiment?"ackThreshold" then toString experiment.ackThreshold else "2";#2 is the default, see rfc9000
  ackDelay = if experiment? "ackDelay" then toString experiment.ackDelay else "25";#25 ms is the default, see "max_ack_delay" in rfc9000
  outagesConfig =
    (builtins.fromJSON (builtins.readFile ./outagesConfig.json));

  mkClientCmd = loggingName:
    if implementation == "quiche" then
      "tokio-client --no-verify http://10.0.3.2:4433/${download} "
      + "--cc-algorithm ${if congestion?"bbr" then "bbr2" else congestion} "
      + "--idle-timeout ${maxIdleTimeout} "
      + " --saved-params saved-params-client.csv "
      + "--logging-file ${loggingName}"
    else
      "quinn-client http://10.0.3.2:4433/${download}  "
      + "--congestion-control ${congestion} "
      + "--ack-eliciting-threshold ${ackThreshold} "
      + "--requested-max-ack-delay ${ackDelay} "
      + "--idle-timeout ${maxIdleTimeout} "
      + "--logging-file ${loggingName}";


  mkServerCmd = loggingName:
    if implementation == "quiche" then
      "tokio-server --listen 10.0.3.2:4433 "
      + "--root ./ "
      + "--cert ${inputs'.test-certs.packages.default}/cert.crt "
      + "--key ${inputs'.test-certs.packages.default}/cert.key "
      + "--cc-algorithm ${if congestion?"bbr" then "bbr2" else congestion} "
      + "--idle-timeout ${maxIdleTimeout} "
      + " --saved-params saved-params-server.csv "
      + "--logging-file ${loggingName}"
    else
      "quinn-server ./ --listen 10.0.3.2:4433 "
      + "--idle-timeout ${maxIdleTimeout} "
      + "--congestion-control ${congestion} "
      + "--ack-eliciting-threshold ${ackThreshold} "
      + "--requested-max-ack-delay ${ackDelay} "
      + "--logging-file ${loggingName}";
  clientBaseline = mkClientCmd "${name}client-baseline.csv";
  clientCR = "CAREFUL_RESUME=true ${mkClientCmd "${name}client-cr.csv"}";
  
  serverBaseline = mkServerCmd "${name}server-baseline.csv";
  serverCR = "CAREFUL_RESUME=true ${mkServerCmd "${name}server-cr.csv"}";
  outageStart =
    if outageType == "none" then
      []
    else
      outagesConfig.${outageType}.${implementation}.${congestion}."delay-${toString delayMs}";
  ip = "${pkgs.iproute2}/bin/ip"; #used for jail
  bash = "${pkgs.bash}/bin/bash";
  config = {
  inherit workDir;
  arp = false;
  arpPrefill = true;
  nodePackages = with pkgs; [
      inputs'.quiche.packages.default
      inputs'.quinn.packages.default
      coreutils
      iputils
    ];


    nodes = {

      client = {

        networking.interfaces = {
          eth1.ipv4 = {
            addresses = [{
              address = "10.0.1.1";
              prefixLength = 24;
            }];

            routes = [{
              address = "10.0.3.0";
              prefixLength = 24;
              via = "10.0.1.2";
              options.metric = "100";
            }];
          };

          eth2.ipv4 = {
            addresses = [{
              address = "10.0.2.1";
              prefixLength = 24;
            }];

            routes = [{
              address = "10.0.3.0";
              prefixLength = 24;
              via = "10.0.2.2";
              options.metric = "200";
            }];
          };
        };

      };

      server = {
        networking.interfaces = {
          eth1.ipv4.addresses = [
            {
              address = "10.0.1.2";
              prefixLength = 24;
            }
            {
              address = "10.0.3.2";
              prefixLength = 24;
            }
          ];

          eth2.ipv4.addresses = [
            {
              address = "10.0.2.2";
              prefixLength = 24;
            }
            {
              address = "10.0.3.2";
              prefixLength = 24;
            }
          ];
        };
      };
    };

  scripts.main = {
  exec =
    ''
    ${if outageType != "none" then ''
      down() { jail enter "$1" ${ip} link set "$2" down; }
      up()   { jail enter "$1" ${ip} link set "$2" up; }

      outages() {
        outageStart=(${builtins.concatStringsSep " " (map toString outageStart)})

        for ((i=0; i<${toString outageAmount}; i++)); do
          
          sleep ''${outageStart[$i]}
          
          echo "Outage start"

          down client eth1
          down client eth2
          down server eth1
          down server eth2

          sleep ${toString outageDuration}

          echo "Outage end"

          up client eth1
          up client eth2
          up server eth1
          up server eth2

          _MAC=$(jail enter server ${ip} link show dev eth1 | sed -n 's/.*link\/ether \([0-9a-f:]*\).*/\1/p')
          jail enter client ${ip} neigh add 10.0.1.2 lladdr "$_MAC" dev eth1
          jail enter client ${ip} neigh add 10.0.3.2 lladdr "$_MAC" dev eth1

          _MAC=$(jail enter client ${ip} link show dev eth1 | sed -n 's/.*link\/ether \([0-9a-f:]*\).*/\1/p')
          jail enter server ${ip} neigh add 10.0.1.1 lladdr "$_MAC" dev eth1

          _MAC=$(jail enter server ${ip} link show dev eth2 | sed -n 's/.*link\/ether \([0-9a-f:]*\).*/\1/p')
          jail enter client ${ip} neigh add 10.0.2.2 lladdr "$_MAC" dev eth2
          jail enter client ${ip} neigh add 10.0.3.2 lladdr "$_MAC" dev eth2

          _MAC=$(jail enter client ${ip} link show dev eth2 | sed -n 's/.*link\/ether \([0-9a-f:]*\).*/\1/p')
          jail enter server ${ip} neigh add 10.0.2.1 lladdr "$_MAC" dev eth2

          jail enter client ${ip} route add 10.0.3.0/24 via 10.0.1.2 dev eth1 metric 100
          jail enter client ${ip} route add 10.0.3.0/24 via 10.0.2.2 dev eth2 metric 200
        done
      }

      outages &
      echo "Started outages"
      OUTAGE_PID=$!
    '' else ''
      OUTAGE_PID=""
    ''}

    ${if carefulResume then ''
      echo "Starting baseline server"

      jail enter server ${bash} -c '
        ${mkServerCmd "${name}server-baseline.csv"}
      ' &
      SERVER_PID=$!

      sleep 1

      echo "Starting baseline client"
      jail enter client ${bash} -c '
        ${mkClientCmd "${name}client-baseline.csv"}
      '

      echo "Stopping baseline server"
      kill $SERVER_PID
      wait $SERVER_PID || true


      echo "Starting careful resume server"

      jail enter server ${bash} -c '
        cd server
        CAREFUL_RESUME=true ${mkServerCmd "${name}server-cr.csv"}
      ' &
      SERVER_PID=$!

      sleep 1

      echo "Starting careful resume client"
      jail enter client ${bash} -c '
        CAREFUL_RESUME=true ${mkClientCmd "${name}client-cr.csv"}
      '

      kill $SERVER_PID
      wait $SERVER_PID || true
    '' else ''
      echo "Starting server"

      jail enter server ${bash} -c '
        ${mkServerCmd "${name}server.csv"}
      ' &
      SERVER_PID=$!
      echo "Server_PID: $SERVER_PID"

      sleep 1

      echo "Starting client here"

      jail enter client ${bash} -c '
        ${mkClientCmd "${name}client.csv"}
        
      '&
      CLIENT_PID=$!
      echo "Client: " $CLIENT_PID
      echo "Server: " $SERVER_PID
      wait $CLIENT_PID
      kill $SERVER_PID
      wait $SERVER_PID || true
    ''}

    ${if outageType != "none" then ''
      echo "Killed outages"
      wait $OUTAGE_PID
    '' else ''''}
    '';
    
  await = true;
  };


    veths.eth1 = {
      arpPrefill = true;
      arp = false;
      mtu = 1500;

      netem = {
        rateMbit = rateMbit;
        delayMs = delayMs;
        autoLimit = true;
        lossPercent = lossPercent;
      };

      a.node = "client";
      b.node = "server";
    };

    veths.eth2 = {
      arpPrefill = true;
      arp = false;
      mtu = 1500;

      netem = {
        rateMbit = rateMbit;
        delayMs = delayMs;
        autoLimit = true;
        lossPercent = lossPercent;
      };

      a.node = "client";
      b.node = "server";
    };
  };
  
in
{
  # main experiment output
  default = nixnet.mkExperiment config;

  # optional visualizations
  mermaid = nixnet.mkMermaid config;
  mermaid-svg = nixnet.mkMermaidSvg config;
}