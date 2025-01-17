-module(dog_api_router).

-include("dog_trainer.hrl"). 

-export([start_link/0]).

start_link() ->
    Dispatch = cowboy_router:compile([
		{'_', [
            {"/api/external", api_handler, #{} },
            {"/api/external/:id", api_handler, #{}},
            {"/api/external/:id/:sub", api_handler, #{}},
            {"/api/externals", plural_api_handler, #{}},
            {"/api/externals/:sub", plural_api_handler, #{}},
            {"/api/V2/external", api_handler_v2, #{} },
            {"/api/V2/external/:id", api_handler_v2, #{}},
            {"/api/V2/external/:id/:sub", api_handler_v2, #{}},
            {"/api/V2/externals", plural_api_handler_v2, #{}},
            {"/api/V2/externals/:sub", plural_api_handler_v2, #{}},
            {"/api/V2/file_transfer/:id", dog_file_transfer_api_v2, #{} },
            {"/api/V2/external/:id", api_handler_v2, #{}},
            {"/api/group", api_handler, #{} },
            {"/api/group/:id", api_handler, #{}},
            {"/api/group/:id/:sub", api_handler, #{}},
            {"/api/groups", plural_api_handler, #{}},
            {"/api/groups/:sub", plural_api_handler, #{}},
            {"/api/group", api_handler, #{} },
            {"/api/group/:id", api_handler, #{}},
            {"/api/group/:id/:sub", api_handler, #{}},
            {"/api/groups", plural_api_handler, #{}},
            {"/api/groups/:sub", plural_api_handler, #{}},
            {"/api/V2/group", api_handler_v2, #{} },
            {"/api/V2/group/:id", api_handler_v2, #{}},
            {"/api/V2/group/:id/:sub", api_handler_v2, #{}},
            {"/api/V2/groups", plural_api_handler_v2, #{}},
            {"/api/V2/groups/:sub", plural_api_handler_v2, #{}},
            {"/api/V2/group", api_handler_v2, #{} },
            {"/api/V2/group/:id", api_handler_v2, #{}},
            {"/api/V2/group/:id/:sub", api_handler_v2, #{}},
            {"/api/V2/groups", plural_api_handler_v2, #{}},
            {"/api/V2/groups/:sub", plural_api_handler_v2, #{}},
            {"/api/healthcheck", healthcheck_api_handler, #{}},
            {"/api/V2/host", api_handler_v2, #{} },
            {"/api/V2/host/:id", api_handler_v2, #{}},
            {"/api/V2/hosts", plural_api_handler_v2, #{}},
            {"/api/V2/hosts/:sub", plural_api_handler_v2, #{}},
            {"/api/V2/hosts/ips", plural_api_handler_v2, #{}},
            {"/api/host", api_handler, #{} },
            {"/api/host/:id", api_handler, #{}},
            {"/api/hosts", plural_api_handler, #{}},
            {"/api/hosts/:sub", plural_api_handler, #{}},
            {"/api/hosts/ips", plural_api_handler, #{}},
            {"/api/link", api_handler, #{} },
            {"/api/link/:id", api_handler, #{}},
            {"/api/links", plural_api_handler, #{}},
            {"/api/links/:sub", plural_api_handler, #{}},
            {"/api/V2/link", api_handler_v2, #{} },
            {"/api/V2/link/:id", api_handler_v2, #{}},
            {"/api/V2/links", plural_api_handler_v2, #{}},
            {"/api/V2/links/:sub", plural_api_handler_v2, #{}},
            {"/api/profile", api_handler, #{}},
            {"/api/profile/:id", api_handler, #{}},
            {"/api/profile/:id/:sub", api_handler, #{}},
            {"/api/profiles", plural_api_handler, #{}},
            {"/api/profiles/:sub", plural_api_handler, #{}},
            {"/api/V2/profile", api_handler_v2, #{}},
            {"/api/V2/profile/:id", api_handler_v2, #{}},
            {"/api/V2/profile/:id/:sub", api_handler_v2, #{}},
            {"/api/V2/profiles", plural_api_handler_v2, #{}},
            {"/api/V2/profiles/:sub", plural_api_handler_v2, #{}},
            {"/api/publish", publish_api_handler, #{}},
            {"/api/service", api_handler, #{} },
            {"/api/service/:id", api_handler, #{}},
            {"/api/services", plural_api_handler, #{}},
            {"/api/services/:sub", plural_api_handler, #{}},
            {"/api/V2/service", api_handler_v2, #{} },
            {"/api/V2/service/:id", api_handler_v2, #{}},
            {"/api/V2/services", plural_api_handler_v2, #{}},
            {"/api/V2/services/:sub", plural_api_handler_v2, #{}},
            {"/api/zone/", api_handler, #{}},
            {"/api/zone/:id", api_handler, #{}},
            {"/api/zones", plural_api_handler, #{}},
            {"/api/zones/:sub", plural_api_handler, #{}},
            {"/api/zones/ips", plural_api_handler, #{}},
            {"/api/V2/zone/", api_handler_v2, #{}},
            {"/api/V2/zone/:id", api_handler_v2, #{}},
            {"/api/V2/zones", plural_api_handler_v2, #{}},
            {"/api/V2/zones/:sub", plural_api_handler_v2, #{}},
            {"/api/V2/zones/ips", plural_api_handler_v2, #{}}
		]}
	]),
	{ok, _} = cowboy:start_clear(http, 
        [{port, 7070}, {ip, {0,0,0,0}}], 
        #{ env => #{dispatch => Dispatch} }
    ),
    %{ok, _} = cowboy:start_tls(api_mtls, 
    %    [
    %        {port, 8443},
    %        {cacertfile, "/opt/dog_trainer/consul-root.cer"},
    %        {certfile, "/opt/dog_trainer/server.cert.pem"},
    %        {keyfile, "/opt/dog_trainer/server.key.pem"},
    %        %{cert, "/var/consul/data/pki/certs/server.crt"},
    %        %{cacertfile, "/var/consul/data/pki/certs/ca.crt"},
    %        %{keyfile, "/var/consul/data/pki/private/server.key"}%,
    %        {verify, verify_peer}%,
    %        %                            {server_name_indication, disable},
    %        %{fail_if_no_peer_cert, true}
    %    ],
    %    #{
    %        env => #{dispatch => Dispatch} 
    %    }
    %),
dog_api_sup:start_link().
