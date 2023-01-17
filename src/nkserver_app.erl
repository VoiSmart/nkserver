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

%% @doc NkSERVER
-module(nkserver_app).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(application).

-export([start/0, start/1, start/2, stop/1]).
-export([set_nodes/1]).
-export([get/1, get/2, put/2, del/1]).

-include("nkserver.hrl").
-include_lib("nklib/include/nklib.hrl").

-define(APP, nkserver).
-compile({no_auto_import, [get/1, put/2]}).

%% ===================================================================
%% Private
%% ===================================================================

%% @doc Starts NkSERVER stand alone.
-spec start() ->
    ok | {error, Reason::term()}.

start() ->
    start(permanent).


%% @doc Starts NkSERVER stand alone.
-spec start(permanent|transient|temporary) ->
    ok | {error, Reason::term()}.

start(Type) ->
    case application:ensure_all_started(?APP, Type) of
        {ok, _Started} ->
            ok;
        Error ->
            Error
    end.


%% @doc
start(_Type, _Args) ->
    pg:start_link(),
    Syntax = #{
        log_path => binary,
        save_dispatcher_source => boolean,
        nodes => {list, binary},
        '__defaults' => #{
            log_path => <<"log">>,
            save_dispatcher_source => true
        }
    },
    case nklib_config:load_env(?APP, Syntax) of
        {ok, _} ->
            file:make_dir(get(log_path)),
            {ok, Pid} = nkserver_sup:start_link(),
            {ok, Vsn} = application:get_key(nkserver, vsn),
            % register_packages(),
            %CallbacksHttpUrl = get(callbacksHttpUrl),
            %put(callbacksHttpUrl, nklib_url:norm(CallbacksHttpUrl)),
            ?I("NkSERVER v~s has started.", [Vsn]),
            % Dummy package for tests
            nkserver_util:register_package_class(<<"Service">>, nkserver),
            ?MODULE:put(nkserver_start_time, nklib_util:l_timestamp()),
            {ok, Pid};
        {error, Error} ->
            ?E("Error parsing config: ~p", [Error]),
            error(Error)
    end.



%% @doc
set_nodes(Nodes) when is_list(Nodes) ->
    ?MODULE:put(nodes, [nklib_util:to_binary(Node) || Node <- Nodes]).



%% @private OTP standard stop callback
stop(_) ->
    ok.


%% @doc gets a configuration value
get(Key) ->
    get(Key, undefined).


%% @doc gets a configuration value
get(Key, Default) ->
    nklib_config:get(?APP, Key, Default).


%% @doc updates a configuration value
put(Key, Value) ->
    nklib_config:put(?APP, Key, Value).


%% @doc updates a configuration value
del(Key) ->
    nklib_config:del(?APP, Key).
