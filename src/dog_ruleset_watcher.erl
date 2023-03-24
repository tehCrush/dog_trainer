-module(dog_ruleset_watcher).
-behaviour(gen_requery).

%% ------------------------------------------------------------------
%% Record and Type Definitions
%% ------------------------------------------------------------------

-include("dog_trainer.hrl").
%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([
    start_link/0,
    state/1
]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

% These are the callback function specific to the gen_requery behavior
-export([
    handle_connection_up/2,
    handle_connection_down/1,
    handle_query_result/2,
    handle_query_done/1,
    handle_query_error/2
]).

%% ------------------------------------------------------------------
%% test Function Exports
%% ------------------------------------------------------------------

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    {ok, _Ref} = gen_requery:start_link(?MODULE, [], []).

state(Ref) ->
    gen_requery:call(Ref, state, infinity).

-spec init(_) -> no_return().
init([]) ->
    ?LOG_INFO("init"),
    % The ConnectOptions are provided to gen_rethink:connect_unlinked
    RethinkdbHost = application:get_env(dog_trainer, rethinkdb_host, "localhost"),
    RethinkdbPort = application:get_env(dog_trainer, rethinkdb_port, 28015),
    RethinkdbUser = application:get_env(dog_trainer, rethinkdb_username, "admin"),
    RethinkdbPassword = application:get_env(dog_trainer, rethinkdb_password, ""),
    RethinkTimeoutMs = application:get_env(dog_trainer, rethink_timeout_ms, 1000),
    ConnectOptions = #{
        host => RethinkdbHost,
        port => RethinkdbPort,
        timeout => RethinkTimeoutMs,
        user => binary:list_to_bin(RethinkdbUser),
        password => binary:list_to_bin(RethinkdbPassword)
    },

    % The State is up to you -- it can be any term
    State = [],
    dog_profile:init(),

    {ok, ConnectOptions, State}.

%% @doc handle_connection_up/2 is called with a valid Connection pid whenever
%% the managed connection is newly established
handle_connection_up(Connection, State) ->
    {ok, RethinkSquashSec} = application:get_env(dog_trainer, rethink_squash_sec),
    ?LOG_INFO("handle_connection_up"),
    ?LOG_INFO("Connection: ~p", [Connection]),
    Reql = reql:db(<<"dog">>),
    reql:table(Reql, <<"ruleset">>),
    reql:changes(Reql, #{<<"include_initial">> => false, <<"squash">> => RethinkSquashSec}),
    {noreply, Reql, State}.

%% @doc handle_connection_down/1 is called when the managed connection goes
%% down unexpectedly. The gen_requery implementation will then enter a
%% reconnect state with exponential backoffs. Your module can still process
%% requests during this time.
handle_connection_down(State) ->
    ?LOG_INFO("handle_connection_down"),
    {noreply, State}.

handle_query_result(Result, State) ->
    ?LOG_INFO("Result: ~p", [Result]),
    case Result of
        [] ->
            pass;
        _ ->
            imetrics:add_m(watcher, ruleset_update),
            lists:foreach(
                fun(Entry) ->
                    ?LOG_INFO("Entry: ~p", [Entry]),
                    PossibleProfileId =
                        case maps:get(<<"new_val">>, Entry) of
                            null ->
                                maps:get(<<"profile_id">>, maps:get(<<"old_val">>, Entry), []);
                            _ ->
                                maps:get(<<"profile_id">>, maps:get(<<"new_val">>, Entry), [])
                        end,
                    %TODO Fix race condition
                    timer:sleep(1000),
                    case PossibleProfileId of
                        [] ->
                            pass;
                        ProfileId ->
                            GroupIds = dog_group:get_ids_with_profile_id(ProfileId),
                            %{ok,GroupIds} = dog_profile:where_used(ProfileId),
                            ?LOG_INFO("GroupIds: ~p", [GroupIds]),
                            lists:foreach(
                                fun(GroupId) ->
                                    {ok, GroupName} = dog_group:get_name_by_id(GroupId),
                                    ?LOG_INFO(GroupName),
                                    GroupType = <<"group">>,
                                    dog_iptables:update_group_iptables(GroupName, GroupType),
                                    dog_iptables:update_group_ec2_sgs(GroupName)
                                end,
                                GroupIds
                            )
                    end
                end,
                Result
            )
    end,
    {noreply, [Result | State]}.

handle_query_done(State) ->
    {stop, changefeeds_shouldnt_be_done, State}.

handle_query_error(Error, State) ->
    {stop, Error, State}.

handle_call(state, _From, State) ->
    ?LOG_DEBUG("handle_call changefeed: ~p", [State]),
    {reply, State, State}.

handle_cast(_Msg, State) ->
    ?LOG_DEBUG("handle_cast changefeed: ~p", [State]),
    {noreply, State}.

handle_info(_Info, State) ->
    ?LOG_DEBUG("handle_info changefeed: ~p", [State]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
