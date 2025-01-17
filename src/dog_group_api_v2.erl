-module(dog_group_api_v2).

-include("dog_trainer.hrl").

-define(VALIDATION_TYPE, <<"group">>).
-define(TYPE_TABLE, group).

%API
-export([
        create/1,
        delete/1,
        get_all/0,
        get_by_id/1,
        get_by_name/1,
        replace/2,
        replace_profile_by_profile_id/2,
        replace_profile_by_profile_id/3,
        update/2
        ]).

get_by_id(Id) ->
  dog_group:get_by_id(Id).

get_by_name(Name) ->
  dog_group:get_by_name(Name).

all_active() ->
  dog_group:all_active().

in_active_profile(Id) ->
  dog_group:in_active_profile(Id).

-spec create(Group :: map()) -> {ok, Key :: iolist()}.
create(Group@0) when is_map(Group@0)->
    GroupName = maps:get(<<"name">>,Group@0),
    GroupResult = get_by_name(GroupName),
    DefaultMap = #{
        <<"hash4_ipsets">> => <<"">>,
        <<"hash6_ipsets">> => <<"">>,
        <<"hash4_iptables">> => <<"">>,
        <<"hash6_iptables">> => <<"">>,
        <<"ipset_hash">> => <<"">>,
        <<"external_ipv4_addresses">> => [],
        <<"external_ipv6_addresses">> => []
    },
    case GroupResult of
        {error, notfound} ->
            Timestamp = dog_time:timestamp(),
            Group@1 = maps:put(<<"created">>,Timestamp,Group@0),
            Group@2 = case maps:find(<<"profile_name">>,Group@1) of
                error ->
                   NewMap = maps:merge(DefaultMap,Group@1),
                   logger:info("NewMap: ~p",[NewMap]),
                   NewMap;
                {ok, _ProfileName} ->
                    ProfileId = case maps:find(<<"profile_version">>,Group@1) of
                        error ->
                            "";
                        {ok, <<"latest">>} ->
                            ProfileName = maps:get(<<"profile_name">>,Group@1),
                            case dog_profile:get_latest_profile(ProfileName) of
                                {ok, DogProfile} ->
                                    maps:get(<<"id">>,DogProfile);
                                {error, notfound} ->
                                    #{error => not_found}
                            end;
                        {ok, Id} ->
                            Id
                    end,
                    
                    NewMap = maps:merge(DefaultMap,Group@1),
                    logger:info("NewMap: ~p",[NewMap]),
                    maps:merge(NewMap,#{<<"profile_id">> => ProfileId})
            end,
            case dog_json_schema:validate(?VALIDATION_TYPE,Group@2) of
                ok ->
                    {ok, R} = dog_rethink:run(
                                              fun(X) ->
                                                      reql:db(X, dog),
                                                      reql:table(X, ?TYPE_TABLE),
                                                      reql:insert(X, Group@2,#{return_changes => always})
                                              end),
                    NewVal = maps:get(<<"new_val">>,hd(maps:get(<<"changes">>,R))),
                    {ok, NewVal};
                {error, Error} ->
                    Response = dog_parse:validation_error(Error),
                    {validation_error, Response}
            end;
        {ok, _} ->
            {error, exists}
     end.

-spec delete(GroupId :: binary()) -> (ok | {error, Error :: iolist()}).
delete(Id) ->
    case in_active_profile(Id) of
        {false,[]} -> 
            {ok, R} = dog_rethink:run(
                                      fun(X) -> 
                                              reql:db(X, dog),
                                              reql:table(X, ?TYPE_TABLE),
                                              reql:get(X, Id),
                                              reql:delete(X)
                                      end),
            logger:debug("delete R: ~p~n",[R]),
            Deleted = maps:get(<<"deleted">>, R),
            case Deleted of
                1 -> ok;
                _ -> {error,#{<<"error">> => <<"error">>}}
            end;
        {true,Profiles} ->
            logger:error("group ~p not deleted, in profiles: ~p~n",[Id,Profiles]),
            {error,#{<<"errors">> => #{<<"in active profile">> => Profiles}}}
     end.

-spec get_all() -> {ok, list()}.
get_all() ->
    {ok, R} = dog_rethink:run(
    fun(X) ->
        reql:db(X, dog),
        reql:table(X, ?TYPE_TABLE)
    end),
    {ok, Result} = rethink_cursor:all(R),
    Groups = case lists:flatten(Result) of
        [] -> [];
        Else -> Else
    end,
    Groups@1 = lists:append(Groups,[all_active()]),
    {ok, Groups@1}.

-spec replace(Id :: binary(), ReplaceMap :: map()) -> {'false','no_replaced' | 'notfound' | binary()} | {'true',binary()} | {'validation_error',binary()}.
replace(Id, ReplaceMap) ->
    case get_by_id(Id) of
        {ok, OldExternal} ->
            NewItem = maps:merge(OldExternal,ReplaceMap),
            NewItem2  = dog_time:merge_timestamp(NewItem),
            NewItem3 = maps:put(<<"id">>, Id, NewItem2),
            case dog_json_schema:validate(?VALIDATION_TYPE,NewItem3) of
                ok ->
                    {ok, R} = dog_rethink:run(
                          fun(X) -> 
                                  reql:db(X, dog),
                                  reql:table(X, ?TYPE_TABLE),
                                  reql:get(X, Id),
                                  reql:replace(X,NewItem3,#{return_changes => always})
                              end),
                    logger:debug("replaced R: ~p~n", [R]),
                    Replaced = maps:get(<<"replaced">>, R),
                    Unchanged = maps:get(<<"unchanged">>, R),
                    case {Replaced,Unchanged} of
                        {1,0} -> 
                          NewVal = maps:get(<<"new_val">>,hd(maps:get(<<"changes">>,R))),
                          {true,NewVal};
                        {0,1} -> 
                          OldVal = maps:get(<<"old_val">>,hd(maps:get(<<"changes">>,R))),
                          {false,OldVal};
                        _ -> 
                        {false, no_updated}
                    end;
                {error, Error} ->
                    Response = dog_parse:validation_error(Error),
                    {validation_error, Response}
            end;
        {error, Error} ->
            {false, Error}
    end.

-spec replace_profile_by_profile_id(OldId :: binary(), NewId :: binary()) ->  list().
replace_profile_by_profile_id(OldId, NewId) ->
    GroupIds = dog_group:get_ids_with_profile_id(OldId),
    Results = lists:map(fun(GroupId) ->
        update(GroupId, #{<<"profile_id">> => NewId}) end, GroupIds),
    Results.

-spec replace_profile_by_profile_id(OldId :: binary(), NewId :: binary(), ProfileName :: iolist() ) ->  list().
replace_profile_by_profile_id(OldId, NewId, ProfileName) ->
    logger:debug("OldId: ~p, NewId: ~p, ProfileName: ~p", [OldId, NewId, ProfileName]),
    GroupIds = dog_group:get_ids_with_profile_id(OldId),
    Results = lists:map(fun(GroupId) ->
        update(GroupId, #{<<"profile_id">> => NewId, <<"profile_name">> => ProfileName}) end, GroupIds),
    Results.

-spec update(GroupId :: binary(), UpdateMap :: map()) -> {atom(), any()} .
update(Id, UpdateMap) ->
    case get_by_id(Id) of
        {ok,OldService} ->
            NewService = maps:merge(OldService,UpdateMap),
            case dog_json_schema:validate(?VALIDATION_TYPE,NewService) of
                ok ->
                    %{ok, RethinkTimeout} = application:get_env(dog_trainer,rethink_timeout_ms),
                    %{ok, Connection} = gen_rethink_session:get_connection(dog_session),
                    {ok, R} = dog_rethink:run(
                          fun(X) ->
                                  reql:db(X, dog),
                                  reql:table(X, ?TYPE_TABLE),
                                  reql:get(X, Id),
                                  reql:update(X,UpdateMap,#{return_changes => always})
                          end),
                    logger:debug("update R: ~p~n", [R]),
                    Replaced = maps:get(<<"replaced">>, R),
                    Unchanged = maps:get(<<"unchanged">>, R),
                    case {Replaced,Unchanged} of
                        {1,0} -> 
                          NewVal = maps:get(<<"new_val">>,hd(maps:get(<<"changes">>,R))),
                          {true,NewVal};
                        {0,1} -> 
                          OldVal = maps:get(<<"old_val">>,hd(maps:get(<<"changes">>,R))),
                          {false,OldVal};
                        _ -> 
                        {false, no_updated}
                    end;
                {error, Error} ->
                    Response = dog_parse:validation_error(Error),
                    {validation_error, Response}
            end;
        {error, Error} ->
            {false, Error}
    end.
