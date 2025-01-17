-module(dog_ips).
-behaviour(gen_server).

-include("dog_trainer.hrl").
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-export([ 
        filter_ipv4/1, 
        filter_ipv6/1,
        is_ipv4/1, 
        is_ipv6/1, 
        loop/4,
        subscriber_callback/3,
        uniq/1
        ]).

-export([
        add_net_to_ipv4/1,
        addresses_from_interfaces/1, 
        remove_local_ips/1,
        remove_local_ipv4_ips/1,
        remove_local_ipv6_ips/1
        ]).

%gen_server functions
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    {ok, []}.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
%    loop(RoutingKey, ContentType, Payload, State) ->
%        {remove, State} | {reject, State} | {stop, Reason, State}
%        | {ack, State'} | {reply, CType, Payload, State}
loop(_RoutingKey, _CType, Payload, State) ->
  try
      Proplist = binary_to_term(Payload),
      UserData = proplists:get_value(user_data, Proplist),
      logger:info("UserData: ~p",[UserData]),
      Config = maps:get(config, UserData),
      logger:info("Config: ~p",[Config]),
      logger:info("dog_state:from_map(Config) : ~p",[dog_state:from_map(Config)]),
      GroupName = maps:get(<<"group">>, Config),
      UpdateType = maps:get(<<"updatetype">>, Config),
      imetrics:add_m(ips_update,erlang:atom_to_list(UpdateType)),
      logger:info("UpdateType: ~p",[UpdateType]),
      Hostname = maps:get(<<"name">>,Config),
      Hostkey = maps:get(<<"hostkey">>,Config),
      logger:info("Hostname: ~p, Hostkey: ~p",[Hostname,Hostkey]),
      dog_config:update_host_keepalive(Hostkey),
      case dog_host:get_by_hostkey(Hostkey) of
          {ok, HostExists} -> 
              %HostId = maps:get(<<"id">>, HostExists),
              Host = maps:merge(HostExists,Config),
              %Host = dog_state:to_map(dog_state:from_map(UpdatedHost)),
              case dog_host:hash_check(Host) of
                  {pass,HashStatus} ->
                      dog_host:state_event(Host, pass_hashcheck, HashStatus);
                  {fail,HashStatus} ->
                      dog_host:state_event(Host, fail_hashcheck, HashStatus)
              end,
              case UpdateType of
                  force ->
                      logger:info("got force: ~p",[Hostkey]),
                      dog_host:update_by_hostkey(Hostkey, Config),
                      dog_ipset_update_agent:queue_force(),
                      dog_iptables:update_group_iptables(GroupName, <<"role">>);
                  update -> 
                      logger:info("got update: ~p",[Hostkey]),
                      dog_host:update_by_hostkey(Hostkey, Config),
                      dog_ipset_update_agent:queue_update(),
                      dog_iptables:update_group_iptables(GroupName, <<"role">>);
                  keepalive ->
                      logger:info("got keepalive: ~p",[Hostkey]),
                      dog_host:update_by_hostkey(Hostkey, Config)
              end;
          {error, Reason} ->
              case UpdateType of
                  force ->
                      logger:info("New host reporting: ~p",[Hostkey]),
                      dog_host:create(Config);
                  _ ->
                      logger:info("Host update for unknown host: ~p, Reason: ~p",[Hostkey,Reason])
              end
      end,
      dog_agent_checker:go()
  catch
    Exception:ExceptionReason:Stacktrace ->
      imetrics:add_m(ips_update,"exception"),
      logger:error("Exception: ~p, ExceptionReason: ~p, Stacktrace: ~p",[Exception,ExceptionReason,Stacktrace])
  end,
  {ack,State}.

-spec subscriber_callback(DeliveryTag :: binary() , RoutingKey :: binary() ,Payload :: binary()) -> 'ack'. 
subscriber_callback(_DeliveryTag, _RoutingKey, Payload) ->
  try
      Proplist = binary_to_term(Payload),
      UserData = proplists:get_value(user_data, Proplist),
      logger:info("UserData: ~p",[UserData]),
      Config = maps:get(config, UserData),
      logger:info("Config: ~p",[Config]),
      logger:info("dog_state:from_map(Config) : ~p",[dog_state:from_map(Config)]),
      GroupName = maps:get(<<"group">>, Config),
      UpdateType = maps:get(<<"updatetype">>, Config),
      imetrics:add_m(ips_update,erlang:atom_to_list(UpdateType)),
      logger:info("UpdateType: ~p",[UpdateType]),
      Hostname = maps:get(<<"name">>,Config),
      Hostkey = maps:get(<<"hostkey">>,Config),
      logger:info("Hostname: ~p, Hostkey: ~p",[Hostname,Hostkey]),
      dog_config:update_host_keepalive(Hostkey),
      case dog_host:get_by_hostkey(Hostkey) of
          {ok, HostExists} -> 
              %HostId = maps:get(<<"id">>, HostExists),
              Host = maps:merge(HostExists,Config),
              %Host = dog_state:to_map(dog_state:from_map(UpdatedHost)),
              case dog_host:hash_check(Host) of
                  {pass,HashStatus} ->
                      dog_host:state_event(Host, pass_hashcheck, HashStatus);
                  {fail,HashStatus} ->
                      dog_host:state_event(Host, fail_hashcheck, HashStatus)
              end,
              case UpdateType of
                  force ->
                      logger:info("got force: ~p",[Hostkey]),
                      dog_host:update_by_hostkey(Hostkey, Config),
                      dog_ipset_update_agent:queue_force(),
                      dog_iptables:update_group_iptables(GroupName, <<"role">>);
                  update -> 
                      logger:info("got update: ~p",[Hostkey]),
                      dog_host:update_by_hostkey(Hostkey, Config),
                      dog_ipset_update_agent:queue_update(),
                      dog_iptables:update_group_iptables(GroupName, <<"role">>);
                  keepalive ->
                      logger:info("got keepalive: ~p",[Hostkey]),
                      dog_host:update_by_hostkey(Hostkey, Config)
              end;
          {error, Reason} ->
              case UpdateType of
                  force ->
                      logger:info("New host reporting: ~p",[Hostkey]),
                      dog_host:create(Config);
                  _ ->
                      logger:info("Host update for unknown host: ~p, Reason: ~p",[Hostkey,Reason])
              end
      end,
      dog_agent_checker:go()
  catch
    Exception:ExceptionReason:Stacktrace ->
      imetrics:add_m(ips_update,"exception"),
      logger:error("Exception: ~p, ExceptionReason: ~p, Stacktrace: ~p",[Exception,ExceptionReason,Stacktrace])
  end,
  ack.


-spec addresses_from_interfaces( list() ) -> {'ok', list()}.
addresses_from_interfaces(Interfaces) ->
    Interfaces@1 = case Interfaces of
        [] -> [];
        _ -> Interfaces 
    end,
    IPs = lists:flatten([ element(2,X) || X <- Interfaces@1]),
    NonLocalhostIPs = remove_local_ips(IPs),
    {ok, NonLocalhostIPs}.

-spec is_ipv4(IP :: iolist()) -> boolean().
is_ipv4(IP) ->
    {ok,Regex} = re:compile("^([0-9]{1,3}\.){3}[0-9]{1,3}(\/([0-9]|[1-2][0-9]|3[0-2]))?$"),
    case re:run(IP,Regex,[]) of
        nomatch ->
            false;
        _ ->
            true
    end.

-spec add_net_to_ipv4(Ipv4 :: binary()) -> binary().
add_net_to_ipv4(Ipv4) ->
    Ipv4String = binary_to_list(Ipv4),
    NewIpv4 = case string:find(Ipv4String,"/") of
        nomatch ->
            Ipv4String ++ "/32";
        _ ->
            Ipv4String
    end,
    list_to_binary(NewIpv4).

-spec add_net_to_ipv6(Ipv6 :: binary()) -> binary().
add_net_to_ipv6(Ipv6) ->
    Ipv6String = binary_to_list(Ipv6),
    NewIpv6 = case string:find(Ipv6String,"/") of
        nomatch ->
            Ipv6String ++ "/128";
        _ ->
            Ipv6String
    end,
    list_to_binary(NewIpv6).

-spec uniq( List :: list() ) -> list().
uniq(List) ->
    ordsets:to_list(ordsets:from_list(List)).

-spec filter_ipv4([any()]) -> list().
filter_ipv4(IPs) ->
    uniq(
      lists:map(fun(X) -> add_net_to_ipv4(X) end,
              lists:filter(fun(X) -> is_ipv4(X) end, IPs))).

-spec is_ipv6(IP :: binary()) -> boolean(). 
is_ipv6(IP) ->
    {ok, Regex } = re:compile("(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"),
    case re:run(binary_to_list(IP),Regex,[]) of
        nomatch ->
            false;
        _ ->
            true
    end.

-spec filter_ipv6(list()) -> list().
filter_ipv6(IPs) ->
    uniq(
        lists:map(fun(X) -> add_net_to_ipv6(X) end,
                  lists:filter(fun(X) -> is_ipv6(X) end, IPs))).

-spec is_ipv4_localhost(IP :: iolist()) -> boolean().
is_ipv4_localhost(IP) ->
    Match = re:run(IP,"^127(?:\.[0-9]+){0,2}\.[0-9]+$|^(?:0*\:)*?:?0*1$",[]),
    case Match of
       {match, _} ->
           false;
        _  ->
           true
    end.

-spec is_ipv6_localhost(IP :: iolist() ) -> boolean().
is_ipv6_localhost(IP) ->
    Match = re:run(IP,"^fe80::",[caseless]),
    case Match of
       {match, _} ->
           false;
        _  ->
           true
    end.

-spec remove_local_ipv4_ips([any()]) -> [any()].
remove_local_ipv4_ips(IPs) ->
    lists:filter(fun(X) -> is_ipv4_localhost(X) end, IPs).

-spec remove_local_ipv6_ips([any()]) -> [any()].
remove_local_ipv6_ips(IPs) ->
    lists:filter(fun(X) -> is_ipv6_localhost(X) end, IPs).

remove_local_ips(IPs) ->
    NonLocalhostIPs@0 = remove_local_ipv4_ips(IPs),
    NonLocalhostIPs@1 = remove_local_ipv6_ips(NonLocalhostIPs@0),
    NonLocalhostIPs@1.
