-module(dog_ec2_sg).

-include("dog_trainer.hrl").
-include_lib("erlcloud/include/erlcloud.hrl").
-include_lib("erlcloud/include/erlcloud_aws.hrl").
-include_lib("erlcloud/include/erlcloud_ec2.hrl").

-export([
        config/1,
        %create_port_anywhere_ingress_rules/1,
        %create_port_anywhere_ingress_rules_by_id/1,
        %ingress_record_to_ppps/1,
        %ingress_records_to_ppps/1,
        %ip_permissions/2,
        %ppps_to_spps/1,
        publish_ec2_sg/1,
        %publish_ec2_sg_by_id/1,
        publish_ec2_sg_by_name/1
        %publish_ec2_sgs/1,
        %tuple_to_ingress_records/1,
        %update_sg/3
 %       create_ingress_port_rules/4,
%        create_ingress_rules/1,
        ]).

-export([
        diff_sg_egress/3,
        diff_sg_ingress/3,
        ip_permissions_egress/2,
        ip_permissions_ingress/2
        ]).

-spec config(Region :: binary()) -> tuple().
config(Region) ->
    {ok, Key} = application:get_env(dog_trainer, aws_key),
    {ok,Secret} = application:get_env(dog_trainer, aws_secret),
    Url = "ec2." ++ binary:bin_to_list(Region) ++ ".amazonaws.com",
    logger:debug("Url: ~s~n",[Url]),
    erlcloud_ec2:new(Key,
                     Secret, Url).

default_ingress_spps_rules(Ec2SecurityGroupId) ->
    [
    %{tcp,0,65535,{group_id,binary:bin_to_list(Ec2SecurityGroupId)}},
    %{udp,0,65535,{group_id,binary:bin_to_list(Ec2SecurityGroupId)}}
    {'-1',0,0,{group_id,binary:bin_to_list(Ec2SecurityGroupId)}}
     ].

default_egress_spps_rules() ->
    [
    %{-1,0,0,{cidr_ip,["0.0.0.0/0"]}}
    %{tcp,0,0,{cidr_ip,["0.0.0.0/0"]}},
    %{udp,0,0,{cidr_ip,["0.0.0.0/0"]}},
    %{icmp,0,0,{cidr_ip,["0.0.0.0/0"]}}
     ].

publish_ec2_sg_by_name(DogGroupName) ->
    case dog_group:get_by_name(DogGroupName) of
        {ok,DogGroup} ->
            publish_ec2_sgs(DogGroup);
        _ ->
            logger:error("Group not found: ~p~n",[DogGroupName]),
            []
    end.

%-spec publish_ec2_sg_by_id(DogGroupId :: string()) -> {ok|error,DetailedResults :: list()}.
%publish_ec2_sg_by_id(DogGroupId) ->
%    case dog_group:get_by_id(DogGroupId) of
%        {ok,DogGroup} ->
%            publish_ec2_sgs(DogGroup);
%        _ ->
%            logger:error("Group not found: ~p~n",[DogGroupId]),
%            []
%    end.
   
-spec publish_ec2_sgs(DogGroup :: map()) -> {ok|error,DetailedResults :: list()}.
publish_ec2_sgs(DogGroup) ->
    Ec2SecurityGroupList = maps:get(<<"ec2_security_group_ids">>,DogGroup,[]),
    DogGroupName = maps:get(<<"name">>,DogGroup),
    Results = plists:map(fun(Ec2Sg) ->
                      Region = maps:get(<<"region">>,Ec2Sg),
                      SgId = maps:get(<<"sgid">>,Ec2Sg),
                      logger:debug("Region, SgId: ~p, ~p~n",[Region,SgId]),
                      Ec2SgIds = dog_ec2_update_agent:ec2_security_group_ids(Region),
                      case lists:member(binary:bin_to_list(SgId),Ec2SgIds) of
                          true ->
                              {publish_ec2_sg({DogGroup, Region, SgId}),DogGroupName,Region,SgId};
                          false ->
                              {{error,<<"ec2 security group not found">>},DogGroupName,Region,SgId}
                      end
              end, Ec2SecurityGroupList),
    Results.
    %AllResultTrueFalse = lists:all(fun({{{R,_}},_GroupName,_Region,_SgId}) -> R == ok end, Results),
    %AllResult = case AllResultTrueFalse of
    %    true -> ok;
    %    false -> error
    %end,
    %UpdateEc2SgResults = {AllResult,Results},
    %case UpdateEc2SgResults of
    %    {ok,_} ->
    %        logger:info("UpdateEc2SgResults: ~p~n",[UpdateEc2SgResults]);
    %    {error,_} ->
    %        logger:error("UpdateEc2SgResults: ~p~n",[UpdateEc2SgResults])
    %end,
    %UpdateEc2SgResults.

-spec publish_ec2_sg({DogGroup :: map(), Region :: string(), SgId :: string()} ) -> {ok|error,DetailedResults :: list()}.
publish_ec2_sg({DogGroup, Region, SgId}) ->
            DogGroupId = maps:get(<<"id">>,DogGroup),
            AddRemoveMapIngress = diff_sg_ingress(SgId, Region, DogGroupId),
            ResultsIngress = {update_sg_ingress(
                  SgId,
                  Region,
                  AddRemoveMapIngress
                  )},
            logger:debug("Ingress Results: ~p~n",[ResultsIngress]),
            AddRemoveMapEgress = diff_sg_egress(SgId, Region, DogGroupId),
            ResultsEgress = {update_sg_egress(
                  SgId,
                  Region,
                  AddRemoveMapEgress
                  )},
            logger:debug("Egress Results: ~p~n",[ResultsEgress]),
           [ResultsIngress,ResultsEgress].

diff_sg_ingress(Ec2SecurityGroupId, Region, DogGroupId) ->
    {ok,DogGroup} = dog_group:get_by_id(DogGroupId),
    Ppps = dog_group:get_ppps_inbound_ec2(DogGroup,Region),
    DefaultPpps = default_ingress_spps_rules(Ec2SecurityGroupId),
    IngressRulesPpps = ordsets:to_list(ordsets:from_list(Ppps ++ DefaultPpps)),
    logger:debug("IngressRulesPpps: ~p",[IngressRulesPpps]),
    IngressRulesSpps = ppps_to_spps_ingress(IngressRulesPpps),
    logger:debug("IngressRulesSpecs: ~p~n",[IngressRulesSpps]),
    case dog_ec2_update_agent:ec2_security_group(Ec2SecurityGroupId,Region) of
        {error,Reason} ->
            logger:error("Ec2SecurityGroupId doesn't exist: ~p~n",[Ec2SecurityGroupId]),
            {error,Reason};
        _ ->
            ExistingRulesSpps = ip_permissions_ingress(Region, Ec2SecurityGroupId),
            logger:debug("ExistingRulesSpps: ~p~n",[ExistingRulesSpps]),
            ExistingRulesPpps = ingress_records_to_ppps(ExistingRulesSpps),
            NewAddVpcIngressPpps = ordsets:subtract(ordsets:from_list(IngressRulesPpps),ordsets:from_list(ExistingRulesPpps)), 
            logger:debug("ExistingRulesPpps: ~p~n",[ExistingRulesPpps]),
            RemoveVpcIngressPpps = ordsets:subtract(ordsets:from_list(ExistingRulesPpps),ordsets:from_list(IngressRulesPpps)), 
            logger:debug("NewAddVpcIngressPpps: ~p~n",[NewAddVpcIngressPpps]),
            logger:debug("RemoveVpcIngressPpps: ~p~n",[RemoveVpcIngressPpps]),
            NewAddVpcIngressSpps = ppps_to_spps_ingress(NewAddVpcIngressPpps),
            RemoveVpcIngressSpps = ppps_to_spps_ingress(RemoveVpcIngressPpps),
            SgDiff = #{<<"Add">> => NewAddVpcIngressSpps, 
              <<"Remove">> => RemoveVpcIngressSpps},
            logger:debug("SgDiff: ~p~n",[SgDiff]),
            SgDiff
    end.

-spec update_sg_ingress(Ec2SecurityGroupId :: string(), Region :: string(), AddRemoveMap :: map()) -> {ok,tuple()} | {error, tuple()}.
update_sg_ingress(Ec2SecurityGroupId, Region, AddRemoveMap) ->
    Ec2SecurityGroupIdList = binary:bin_to_list(Ec2SecurityGroupId),
    Config = config(Region),
    NewAddVpcIngressSpecs = maps:get(<<"Add">>,AddRemoveMap),
    logger:debug("NewAddVpcIngressSpecs: ~p~n",[NewAddVpcIngressSpecs]),
    AddResults = case NewAddVpcIngressSpecs of
                  [] ->
                      [];
                  _ ->
                    parse_authorize_response(erlcloud_ec2:authorize_security_group_ingress(Ec2SecurityGroupIdList, NewAddVpcIngressSpecs, Config))
              end,
    logger:debug("~p~n",[AddResults]),
    RemoveVpcIngressSpecs = maps:get(<<"Remove">>,AddRemoveMap),
    RemoveResults = case RemoveVpcIngressSpecs of
                  [] ->
                      [];
                  _ ->
                    parse_authorize_response(erlcloud_ec2:revoke_security_group_ingress(Ec2SecurityGroupIdList, RemoveVpcIngressSpecs, Config))
              end,
    AllResults = [AddResults,RemoveResults],
    logger:debug("AllResults: ~p~n",[AllResults]),
    AllResultTrueFalse = lists:all(fun(X) -> (X == ok) or (X == []) end, AllResults),
    AllResult = case AllResultTrueFalse of
        true -> ok;
        false -> error
    end,
    {AllResult,ingress,{{add_results,AddResults},{remove_results,RemoveResults}}}.


diff_sg_egress(Ec2SecurityGroupId, Region, DogGroupId) ->
    {ok,DogGroup} = dog_group:get_by_id(DogGroupId),
    Ppps = dog_group:get_ppps_outbound_ec2(DogGroup,Region),
    DefaultPpps = default_egress_spps_rules(),
    EgressRulesPpps = ordsets:to_list(ordsets:from_list(Ppps ++ DefaultPpps)),
    %EgressRulesPpps = Ppps ++ DefaultPpps,
    EgressRulesSpps = ppps_to_spps_egress(EgressRulesPpps),
    logger:debug("EgressRulesSpecs: ~p~n",[EgressRulesSpps]),
    case dog_ec2_update_agent:ec2_security_group(Ec2SecurityGroupId,Region) of
        {error,Reason} ->
            logger:error("Ec2SecurityGroupId doesn't exist: ~p~n",[Ec2SecurityGroupId]),
            {error,Reason};
        _ ->
            ExistingRulesSpps = ip_permissions_egress(Region, Ec2SecurityGroupId),
            logger:debug("ExistingRulesSpps: ~p~n",[ExistingRulesSpps]),
            ExistingRulesPpps = egress_records_to_ppps(ExistingRulesSpps),
            NewAddVpcEgressPpps = ordsets:subtract(ordsets:from_list(EgressRulesPpps),ordsets:from_list(ExistingRulesPpps)), 
            logger:debug("ExistingRulesPpps: ~p~n",[ExistingRulesPpps]),
            RemoveVpcEgressPpps = ordsets:subtract(ordsets:from_list(ExistingRulesPpps),ordsets:from_list(EgressRulesPpps)), 
            logger:debug("NewAddVpcEgressPpps: ~p~n",[NewAddVpcEgressPpps]),
            logger:debug("RemoveVpcEgressPpps: ~p~n",[RemoveVpcEgressPpps]),
            NewAddVpcEgressSpps = ppps_to_spps_egress(NewAddVpcEgressPpps),
            RemoveVpcEgressSpps = ppps_to_spps_egress(RemoveVpcEgressPpps),
            SgDiff = #{<<"Add">> => NewAddVpcEgressSpps, 
              <<"Remove">> => RemoveVpcEgressSpps},
            logger:debug("SgDiff: ~p~n",[SgDiff]),
            SgDiff
    end.

-spec update_sg_egress(Ec2SecurityGroupId :: string(), Region :: string(), AddRemoveMap :: map()) -> {ok,tuple()} | {error, tuple()}.
update_sg_egress(Ec2SecurityGroupId, Region, AddRemoveMap) ->
    Ec2SecurityGroupIdList = binary:bin_to_list(Ec2SecurityGroupId),
    Config = config(Region),
    NewAddVpcIngressSpecs = maps:get(<<"Add">>,AddRemoveMap),
    logger:debug("NewAddVpcIngressSpecs: ~p~n",[NewAddVpcIngressSpecs]),
    AddResults = case NewAddVpcIngressSpecs of
                  [] ->
                      [];
                  _ ->
                    parse_authorize_response(erlcloud_ec2:authorize_security_group_egress(Ec2SecurityGroupIdList, NewAddVpcIngressSpecs, Config))
              end,
    logger:debug("~p~n",[AddResults]),
    RemoveVpcIngressSpecs = maps:get(<<"Remove">>,AddRemoveMap),
    RemoveResults = case RemoveVpcIngressSpecs of
                  [] ->
                      [];
                  _ ->
                    parse_authorize_response(erlcloud_ec2:revoke_security_group_egress(Ec2SecurityGroupIdList, RemoveVpcIngressSpecs, Config))
              end,
    AllResults = [AddResults,RemoveResults],
    logger:debug("AllResults: ~p~n",[AllResults]),
    AllResultTrueFalse = lists:all(fun(X) -> (X == ok) or (X == []) end, AllResults),
    AllResult = case AllResultTrueFalse of
        true -> ok;
        false -> error
    end,
    {AllResult,egress,{{add_results,AddResults},{remove_results,RemoveResults}}}.

-spec parse_authorize_response(AuthorizeResponse :: tuple()) -> ok | string().
parse_authorize_response(AuthorizeResponse) ->
    logger:debug("AuthorizeResponse: ~p~n",[AuthorizeResponse]),
		case AuthorizeResponse of
            {error,{_ErrorType,_ErrorCode,_ErrorHeader,ErrorDescription}} ->
			%{error,Error} ->
                %{error,{http_error,400,"Bad Request",<<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Response><Errors><Error><Code>InvalidPermission.Duplicate</Code><Message>the specified rule \"peer: sg-0d741a6be4fa9691d, UDP, from port: 0, to port: 65535, ALLOW\" already exists</Message></Error></Errors><RequestID>3cbe6e0d-179d-4481-8589-34eea28bfc65</RequestID></Response>">>}}
                %{error,{http_error,503,"Service Unavailable",<<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Response><Errors><Error><Code>Unavailable</Code><Message>The service is unavailable. Please try again shortly.</Message></Error></Errors><RequestID>c7413e5f-800a-4bdc-8f96-24c69ea1ad9e</RequestID></Response>">>}}}
                Xml = element(2,(erlsom:simple_form(ErrorDescription))),
                %{"Response",[],
                % [{"Errors",[],
                %    [{"Error",[],
                %         [{"Code",[],["InvalidPermission.Duplicate"]},
                %               {"Message",[],
                %                      ["the specified rule \"peer: sg-0d741  a6be4fa9691d, UDP, from port: 0, to port: 65535, ALLOW\" already exists"]}]}]},
                %                        {"RequestID",[],["3cbe6e0d-179d-4481-8589-34eea28bfc65"]}]}     
                {"Response",[],
                 [{"Errors",[],
                   [{"Error",[],
                     [{"Code",[],[Code]},
                      {"Message",[],
                       [Message]}]}]},
                  {"RequestID",[],[_RequestId]}]} = Xml,
               case Code of
                   %Ignore duplicate entry error
                   "InvalidPermission.Duplicate" -> 
                       ok;
                   _ ->
                       {Code,Message}
               end;
			Other ->
				Other
        end.

%create_port_anywhere_ingress_rule(Protocol, Ports) ->
%    lists:map(fun(Port) ->
%                      {From,To} = case string:split(Port,":") of
%                                      [F,T] ->
%                                          {F,T};
%                                      [F] ->
%                                          case Protocol of
%                                              <<"icmp">> -> 
%                                                  {F,<<"-1">>};
%                                              _ ->
%                                                  {F,F}
%                                          end
%                                  end,
%                      #vpc_ingress_spec{
%                         ip_protocol = binary_to_atom(Protocol),
%                         from_port = binary_to_integer(From),
%                         to_port = binary_to_integer(To),
%                         cidr_ip= ["0.0.0.0/0"]
%                        }
%              end, Ports).

%create_port_anywhere_ingress_rules(DogGroupName) ->
%    ProtocolPorts = dog_group:get_all_inbound_ports_by_protocol(DogGroupName),
%    AnywhereIngressRules = lists:map(fun({Protocol, Ports}) ->
%                                             create_port_anywhere_ingress_rule(Protocol,Ports)
%              end, ProtocolPorts),
%    lists:flatten(AnywhereIngressRules).
%
%create_port_anywhere_ingress_rules_by_id(DogGroupId) ->
%    {ok, DogGroup} = dog_group:get_by_id(DogGroupId),
%    DogGroupName = maps:get(<<"name">>,DogGroup),
%    create_port_anywhere_ingress_rules(DogGroupName).

%-spec create_ingress_rules(Spps :: list() ) -> Rules :: list().
%create_ingress_rules(Spps) ->
%    Rules = lists:map(fun({{SourceType,Source},Protocol,Ports}) ->
%                              create_ingress_port_rules(SourceType,Source,Protocol,Ports)
%                      end, Spps),
%    lists:flatten(Rules).
%                      
%-spec create_ingress_port_rules(SourceType :: string(),Source :: string(),Protocol :: string(), Ports :: list()) -> list().
%create_ingress_port_rules(SourceType,Source,Protocol,Ports) ->
%    PortRule = lists:map(fun(Port) ->
%                                 logger:debug("Protocol: ~p, Port : ~p",[Protocol,Port]),
%                                 {From,To} = case string:split(Port,":") of
%                                                 [F,T] ->
%                                                     {F,T};
%                                                 [F] ->
%                                                     case Protocol of
%                                                         <<"icmp">> ->
%                                                             {F,-1};
%                                                         _ ->
%                                                             {F,F}
%                                                     end
%                                             end,
%                                 case SourceType of
%                                     cidr_ip ->
%                                         #vpc_ingress_spec{
%                                            ip_protocol = binary_to_atom(Protocol),
%                                            from_port = binary_to_integer(From),
%                                            to_port = binary_to_integer(To),
%                                            cidr_ip = [Source]
%                                           };
%                                     group_id ->
%                                         #vpc_ingress_spec{
%                                            ip_protocol = binary_to_atom(Protocol),
%                                            from_port = binary_to_integer(From),
%                                            to_port = binary_to_integer(To),
%                                            group_id = [binary_to_list(Source)]
%                                           }
%                                 end
%                         end, Ports),
%    lists:flatten(PortRule).

ppps_to_spps_ingress(Ppps) ->
    Function = fun tuple_to_ingress_records/1,
    Accum = ppps_to_spps(Ppps,#{}),
    L = maps:to_list(Accum),
    lists:map(fun(E) -> Function(element(2,E)) end, L).

ppps_to_spps_egress(Ppps) ->
    Function = fun tuple_to_egress_records/1,
    Accum = ppps_to_spps(Ppps,#{}),
    L = maps:to_list(Accum),
    lists:map(fun(E) -> Function(element(2,E)) end, L).

ppps_to_spps([],Accum) ->
    Accum;
ppps_to_spps(Ppps,Accum) ->
    [Head|Rest] = Ppps,
    {Protocol,FromPort,ToPort,SourceDest} = Head,
    Key = {Protocol,FromPort,ToPort},
    Value = maps:get(Key,Accum,[]),
    NewValue = case Value of
        [] ->
            case SourceDest of
                {group_id,SgId} ->
                    [
                     {ip_protocol,Protocol},
                     {from_port,FromPort},
                     {to_port,ToPort},
                     {groups,[SgId]},
                     {ip_ranges,[]}
                    ];
                {cidr_ip,Cidr} ->
                    [
                     {ip_protocol,Protocol},
                     {from_port,FromPort},
                     {to_port,ToPort},
                     {groups,[]},
                     {ip_ranges,[Cidr]}
                    ]
            end;
        _ ->
            case SourceDest of
                {group_id,SgId} ->
                    ExistingIpRanges = proplists:get_value(ip_ranges,Value,[]),
                    ExistingGroups = proplists:get_value(groups,Value,[]),
                    NewGroups = ordsets:to_list(ordsets:from_list(ExistingGroups ++ [SgId])),
                    [
                     {ip_protocol,Protocol},
                     {from_port,FromPort},
                     {to_port,ToPort},
                     {groups,NewGroups},
                     {ip_ranges,ExistingIpRanges}
                    ];
                {cidr_ip,Cidr} ->
                    ExistingGroups = proplists:get_value(groups,Value,[]),
                    ExistingIpRanges = proplists:get_value(ip_ranges,Value,[]),
                    NewIpRanges = ordsets:to_list(ordsets:from_list(ExistingIpRanges ++ [Cidr])),
                    [
                     {ip_protocol,Protocol},
                     {from_port,FromPort},
                     {to_port,ToPort},
                     {groups,ExistingGroups},
                     {ip_ranges,NewIpRanges}
                    ]
            end
               end,
    AccumNew = maps:put(Key,NewValue,Accum),
    ppps_to_spps(Rest,AccumNew).

%-record(vpc_ingress_spec, {
%          ip_protocol::tcp|udp|icmp,
%          from_port::-1 | 0..65535,
%          to_port::-1 | 0..65535,
%          user_id::undefined|[string()],
%          group_name::undefined|[string()],
%          group_id::undefined|[string()],
%          cidr_ip::undefined|[string()]
%         }).
% 
       
%#vpc_egress_spec{user_id = UserP,
%                   group_name = GNameP,
%                   group_id = GIdP,
%                   cidr_ip = CidrP,
%                   ip_protocol = IpProtocol,
%                   from_port = FromPort,
%                   to_port = ToPort}.
 

-spec ip_permissions_ingress(Ec2Region :: string(), Ec2SecurityGroupId :: string()) -> IpPermisions :: list().
ip_permissions_ingress(Ec2Region, Ec2SecurityGroupId) ->
    Config = config(Ec2Region),
    case erlcloud_ec2:describe_security_groups([Ec2SecurityGroupId],[],[],Config) of
        {ok, Permissions} ->
            IpPermissions = maps:get(ip_permissions, maps:from_list(hd(Permissions))),
            IpPermissionSpecs = [from_describe_tuple_to_ingress_records(T) || T <- IpPermissions],
            lists:flatten(IpPermissionSpecs);
        _ ->
            []
    end.

-spec ip_permissions_egress(Ec2Region :: string(), Ec2SecurityGroupId :: string()) -> IpPermisions :: list().
ip_permissions_egress(Ec2Region, Ec2SecurityGroupId) ->
    Config = config(Ec2Region),
    case erlcloud_ec2:describe_security_groups([Ec2SecurityGroupId],[],[],Config) of
        {ok, Permissions} ->
            IpPermissions = maps:get(ip_permissions_egress, maps:from_list(hd(Permissions))),
            IpPermissionSpecs = [from_describe_tuple_to_egress_records(T) || T <- IpPermissions],
            lists:flatten(IpPermissionSpecs);
        _ ->
            []
    end.

%Only creates ingress_specs for rules with ip_ranges, so doesn't create/delete rules with SGs as source
tuple_to_ingress_records(Keyvalpairs) ->
    IpRanges = proplists:get_value(ip_ranges,Keyvalpairs,[]),
    Groups = proplists:get_value(groups, Keyvalpairs,[]),
    Keyvalpairs1 = proplists:delete(groups,Keyvalpairs),
    Keyvalpairs2 = proplists:delete(ip_ranges,Keyvalpairs1),
    Keyvalpairs3 = Keyvalpairs2 ++ [{cidr_ip,IpRanges}],
    Keyvalpairs4 = Keyvalpairs3 ++ [{group_id,Groups}],
    Foorecord = list_to_tuple([vpc_ingress_spec|[proplists:get_value(X, Keyvalpairs4)
                                                            || X <- record_info(fields, vpc_ingress_spec)]]),
    Foorecord.

tuple_to_egress_records(Keyvalpairs) ->
    IpRanges = proplists:get_value(ip_ranges,Keyvalpairs,[]),
    Groups = proplists:get_value(groups, Keyvalpairs,[]),
    Keyvalpairs1 = proplists:delete(groups,Keyvalpairs),
    Keyvalpairs2 = proplists:delete(ip_ranges,Keyvalpairs1),
    Keyvalpairs3 = Keyvalpairs2 ++ [{cidr_ip,IpRanges}],
    Keyvalpairs4 = Keyvalpairs3 ++ [{group_id,Groups}],
    Foorecord = list_to_tuple([vpc_egress_spec|[proplists:get_value(X, Keyvalpairs4)
                                                            || X <- record_info(fields, vpc_egress_spec)]]),
    Foorecord.
%-record(vpc_ingress_spec, {
%          ip_protocol::tcp|udp|icmp,
%          from_port::-1 | 0..65535,
%          to_port::-1 | 0..65535,
%          user_id::undefined|[string()],
%          group_name::undefined|[string()],
%          group_id::undefined|[string()],
%          cidr_ip::undefined|[string()]
%         }).

ingress_records_to_ppps(IngressRecords) ->
   lists:flatten([ingress_record_to_ppps(Record) || Record <- IngressRecords]).

ingress_record_to_ppps(IpPermissionSpecs) ->
    Protocol = IpPermissionSpecs#vpc_ingress_spec.ip_protocol,
    FromPort = IpPermissionSpecs#vpc_ingress_spec.from_port,
    ToPort = IpPermissionSpecs#vpc_ingress_spec.to_port,
    GroupIds = IpPermissionSpecs#vpc_ingress_spec.group_id,
    CidrIps = IpPermissionSpecs#vpc_ingress_spec.cidr_ip,
    GroupIdsList = lists:map(fun(GroupId) ->
                       {Protocol,FromPort,ToPort,{group_id, GroupId}}
              end, GroupIds),
    CidrIpsList = lists:map(fun(CidrIp) ->
                       {Protocol,FromPort,ToPort,{cidr_ip, CidrIp}}
              end, CidrIps),
    lists:flatten(GroupIdsList ++ CidrIpsList).
                       
egress_records_to_ppps(IngressRecords) ->
   lists:flatten([egress_record_to_ppps(Record) || Record <- IngressRecords]).

egress_record_to_ppps(IpPermissionSpecs) ->
    Protocol = IpPermissionSpecs#vpc_egress_spec.ip_protocol,
    FromPort = IpPermissionSpecs#vpc_egress_spec.from_port,
    ToPort = IpPermissionSpecs#vpc_egress_spec.to_port,
    GroupIds = IpPermissionSpecs#vpc_egress_spec.group_id,
    CidrIps = IpPermissionSpecs#vpc_egress_spec.cidr_ip,
    GroupIdsList = lists:map(fun(GroupId) ->
                       {Protocol,FromPort,ToPort,{group_id, GroupId}}
              end, GroupIds),
    CidrIpsList = lists:map(fun(CidrIp) ->
                       {Protocol,FromPort,ToPort,{cidr_ip, CidrIp}}
              end, CidrIps),
    lists:flatten(GroupIdsList ++ CidrIpsList).
                       
%erlcoud describe_security_groups returns more info on group_id, must simplify to compare to add specs.
from_describe_tuple_to_ingress_records(Keyvalpairs) ->
    IpRanges = proplists:get_value(ip_ranges,Keyvalpairs),
    Groups = proplists:get_value(groups, Keyvalpairs),
    Keyvalpairs1 = proplists:delete(groups,Keyvalpairs),
    Keyvalpairs2 = proplists:delete(ip_ranges,Keyvalpairs1),
    Keyvalpairs3 = Keyvalpairs2 ++ [{cidr_ip,IpRanges}],
    GroupIds = case Groups of
                   [] ->
                       [];
                   _ ->
                       lists:map(fun(Id) ->
                                         proplists:get_value(group_id,Id)
                                 end,Groups)
               end,
    Keyvalpairs4 = Keyvalpairs3 ++ [{group_id,GroupIds}],
    Foorecord = list_to_tuple([vpc_ingress_spec|[proplists:get_value(X, Keyvalpairs4)
                                                            || X <- record_info(fields, vpc_ingress_spec)]]),
    Foorecord.

from_describe_tuple_to_egress_records(Keyvalpairs) ->
    IpRanges = proplists:get_value(ip_ranges,Keyvalpairs),
    Groups = proplists:get_value(groups, Keyvalpairs),
    Keyvalpairs1 = proplists:delete(groups,Keyvalpairs),
    Keyvalpairs2 = proplists:delete(ip_ranges,Keyvalpairs1),
    Keyvalpairs3 = Keyvalpairs2 ++ [{cidr_ip,IpRanges}],
    GroupIds = case Groups of
                   [] ->
                       [];
                   _ ->
                       lists:map(fun(Id) ->
                                         proplists:get_value(group_id,Id)
                                 end,Groups)
               end,
    Keyvalpairs4 = Keyvalpairs3 ++ [{group_id,GroupIds}],
    Foorecord = list_to_tuple([vpc_egress_spec|[proplists:get_value(X, Keyvalpairs4)
                                                            || X <- record_info(fields, vpc_egress_spec)]]),
    Foorecord.
