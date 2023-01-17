
%% -------------------------------------------------------------------
%%
%% Copyright (c) 2019 Carlos Gonzalez Florido.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc When option 'use_master' is used, this server is started at each node,
%% managed by the server's process, one of them will become 'master'


-module(nkserver_master).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([get_leader_pid/1, call_leader/2, call_leader/3]).
-export([start_link/1]).
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2,
         handle_info/2]).
-export([strategy_min_nodes/1]).

-include("nkserver.hrl").
-include_lib("nklib/include/nklib.hrl").


-define(CHECK_TIME, 5000).

%% ===================================================================
%% Types
%% ===================================================================

-type id() :: nkactor:id().


%% ===================================================================
%% Public
%% ===================================================================



%% @doc Gets the service actor master
-spec get_leader_pid(nkactor:id()) ->
    pid() | undefined.

get_leader_pid(SrvId) ->
    global:whereis_name(global_name(SrvId)).


%% @doc
call_leader(SrvId, Msg) ->
    call_leader(SrvId, Msg, 5000).

%% @doc
call_leader(SrvId, Msg, Timeout) ->
    call_leader(SrvId, Msg, Timeout, 30).


%% @private
call_leader(SrvId, Msg, Timeout, Tries) when Tries > 0 ->
    case get_leader_pid(SrvId) of
        Pid when is_pid(Pid) ->
            case nklib_util:call2(Pid, Msg, Timeout) of
                process_not_found ->
                    ?N("master for service '~s' not available, retrying...", [SrvId]),
                    timer:sleep(500),
                    call_leader(SrvId, Msg, Timeout, Tries-1);
                Other ->
                    Other
            end;
        undefined ->
            case whereis(SrvId) of
                undefined ->
                    {error, service_not_started};
                _ ->
                    ?N("master for service '~s' not available, retrying...", [SrvId]),
                    timer:sleep(500),
                    call_leader(SrvId, Msg, Timeout, Tries-1)
            end
    end;

call_leader(_SrvId, _Msg, _Timeout, _Tries) ->
    {error, leader_not_found}.




%% ===================================================================
%% Private
%% ===================================================================


%% @private
-spec start_link(id()) ->
    {ok, pid()} | {error, term()}.

start_link(SrvId) ->
    gen_server:start_link(?MODULE, [SrvId], []).



%% ===================================================================
%% gen_server
%% ===================================================================


-record(state, {
    id :: nkactor:id(),
    is_leader :: boolean(),
    leader_pid :: pid() | undefined,
    user_state :: map()
}).


%% @private
init([SrvId]) ->
    State = #state{
        id = SrvId,
        is_leader = false,
        leader_pid = undefined,
        user_state = #{}
    },
    ?N("master started (~p)", [self()]),
    {ok, UserState} = ?CALL_SRV(SrvId, srv_master_init, [SrvId, #{}]),
    self() ! nkserver_timed_check_leader,
    {ok, State#state{user_state = UserState}}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}} | {reply, term(), #state{}} |
    {stop, Reason::term(), #state{}} | {stop, Reason::term(), Reply::term(), #state{}}.

handle_call(Msg, From, State) ->
    case handle(srv_master_handle_call, [Msg, From], State) of
        continue ->
            ?E("received unexpected call ~p", [Msg]),
            {noreply, State};
        Other ->
            Other
    end.


%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_cast(Msg, State) ->
    case handle(srv_master_handle_cast, [Msg], State) of
        continue ->
            ?E("received unexpected cast ~p", [Msg]),
            {noreply, State};
        Other ->
            Other
    end.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_info(nkserver_timed_check_leader, State) ->
    case check_leader(State) of
        {ok, State2} ->
            erlang:send_after(?CHECK_TIME, self(), nkserver_timed_check_leader),
            {noreply, State2};
        {error, Error} ->
            {stop, Error, State}
    end;

handle_info({'DOWN', _Ref, process, Pid, _Reason}, #state{leader_pid=Pid}=State) ->
    #state{is_leader=false} = State,
    ?W("current leader (~p) is down!", [Pid]),
    Time = nklib_util:rand(1, 1000),
    timer:sleep(Time),
    case check_leader(State) of
        {ok, State2} ->
            {noreply, State2};
        {error, Error} ->
            {stop, Error, State}
    end;

handle_info(Msg, State) ->
    case handle(srv_master_handle_info, [Msg], State) of
        continue ->
            ?N("received unexpected info ~p", [Msg]),
            {noreply, State};
        Other ->
            Other
    end.


%% @private
-spec code_change(term(), #state{}, term()) ->
    {ok, #state{}}.

code_change(OldVsn, #state{id=SrvId, user_state=UserState}=State, Extra) ->
    case apply(SrvId, srv_master_code_change, [OldVsn, SrvId, UserState, Extra]) of
        {ok, UserState2} ->
            {ok, State#state{user_state=UserState2}};
        {error, Error} ->
            {error, Error}
    end.


%% @private
-spec terminate(term(), #state{}) ->
    ok.

terminate(Reason, State) ->
    ?N("is stopped (~p)", [Reason]),
    catch handle(srv_master_terminate, [Reason], State),
    ok.


%% ===================================================================
%% Internal - Leader election
%% ===================================================================

check_leader(State) ->
    case find_leader(State) of
        {ok, #state{is_leader=IsLeader}=State2} ->
            {ok, State3} = handle(srv_master_timed_check, [IsLeader], State2),
            {ok, State3};
        {error, Error} ->
            {error, Error}
    end.


% We don't have a registered leader
find_leader(#state{id=SrvId, leader_pid=undefined}=State) ->
    case get_leader_pid(SrvId) of
        Pid when is_pid(Pid) ->
            ?N("new leader is ~s (~p) (me:~p)", [node(Pid), Pid, self()]),
            monitor(process, Pid),
            {ok, State#state{is_leader=false, leader_pid=Pid}};
        undefined ->
            case handle(srv_master_become_leader, [], State) of
                {yes, State2} ->
                    {ok, State2#state{is_leader=true, leader_pid=self()}};
                {no, State2} ->
                    {ok, State2}
            end
    end;

% We are the registered leader
% We recheck now that we are the real registered leader
find_leader(#state{id=SrvId, is_leader=true}=State) ->
    case get_leader_pid(SrvId) of
        Pid when Pid==self() ->
            {ok, State};
        Other ->
            ?W("we were leader but is NOT the registered leader: ~p (me:~p)",
                  [Other, self()]),
            {error, other_is_leader}
    end;

% We already have a registered leader
% We recheck the current leader is the one we have registered, and we re-register with it
find_leader(#state{id=SrvId, leader_pid=Pid}=State) ->
    case get_leader_pid(SrvId) of
        Pid ->
            ok;
        Other ->
            % Wait for old leader to fail and detect 'DOWN'
            ?W("my old leader (~p) is NOT the registered leader (~p)"
                  " (me:~p), waiting", [Pid, Other, self()])
    end,
    {ok, State}.


%% @private
global_name(SrvId) ->
    {nkserver_leader, SrvId}.


%% @private
%% Will call the service's functions
handle(Fun, Args, #state{id=SrvId, user_state=UserState}=State) ->
    case ?CALL_SRV(SrvId, Fun, Args++[SrvId, UserState]) of
        {reply, Reply, UserState2} ->
            {reply, Reply, State#state{user_state=UserState2}};
        {reply, Reply, UserState2, Time} ->
            {reply, Reply, State#state{user_state=UserState2}, Time};
        {noreply, UserState2} ->
            {noreply, State#state{user_state=UserState2}};
        {noreply, UserState2, Time} ->
            {noreply, State#state{user_state=UserState2}, Time};
        {stop, Reason, Reply, UserState2} ->
            {stop, Reason, Reply, State#state{user_state=UserState2}};
        {stop, Reason, UserState2} ->
            {stop, Reason, State#state{user_state=UserState2}};
        {Atom, UserState2} when Atom==yes; Atom==no; Atom==ok ->
            {Atom, State#state{user_state=UserState2}};
        continue ->
            continue;
        Other ->
            ?W("invalid response for ~p(~p): ~p", [Fun, Args, Other]),
            error(invalid_handle_response)
    end.


%% ===================================================================
%% Standard strategy for min nodes
%% ===================================================================

strategy_min_nodes(SrvId) ->
    MinNodes = ?CALL_SRV(SrvId, master_min_nodes, []),
    Nodes = length(nodes()),
    case Nodes >= MinNodes of
        true ->
            case global:register_name(global_name(SrvId), self()) of
                yes ->
                    ?N("WE are the new leader (~s) (~p)", [SrvId, self()]),
                    yes;
                no ->
                    ?N("could not register as leader (~s), waiting (me:~p)", [SrvId, self()]),
                    % Wait for next iteration
                    no
            end;
        false ->
            ?W("NOT TRYING to become leader, we are in split-brain (~s), (~p/~p nodes)",
                 [SrvId, Nodes, MinNodes]),
            no
    end.


%%%% @private
%%resolve({nkserver_leader, _SrvId}, Pid1, _Pid2) ->
%%    Pid1.
