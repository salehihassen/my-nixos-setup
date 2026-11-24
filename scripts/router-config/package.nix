{ writeShellApplication, python3, openssh, age, networkmanager }:
writeShellApplication {
  name = "router-config";
  runtimeInputs = [ openssh age networkmanager ];
  text = ''
    exec ${python3}/bin/python3 ${./router_config.py} "$@"
  '';
}
