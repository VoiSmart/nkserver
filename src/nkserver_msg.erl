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

-module(nkserver_msg).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([is_msg/2, msg/2]).

-include("nkserver.hrl").
-include_lib("nklib/include/nklib.hrl").


%% ===================================================================
%% Public
%% ===================================================================


%% @private
-spec is_msg(nkserver:id(), nkserver:msg()) ->
    {true, term(), term()} | false.

is_msg(SrvId, Msg) ->
    case ?CALL_SRV(SrvId, msg, [SrvId, Msg]) of
        {Code, Fmt, List} when is_list(Fmt), is_list(List) ->
            {true, get_msg_code(Code), get_msg_fmt(Fmt, List)};
        {Fmt, List} when is_list(Fmt), is_list(List) ->
            {true, get_msg_code(Msg), get_msg_fmt(Fmt, List)};
        {Code, Reason} when is_list(Reason); is_binary(Reason) ->
            {true, get_msg_code(Code), to_bin(Reason)};
        Reason when is_list(Reason) ->
            {true, get_msg_code(Msg), to_bin(Reason)};
        _ ->
            false
    end.


%% @private
-spec msg(nkserver:id(), nkserver:msg()) ->
    {binary(), binary()}.

msg(SrvId, Msg) ->
    case is_msg(SrvId, Msg) of
        {true, Code, Reason} ->
            {Code, Reason};
        false ->
            % This msg is not in any table, but it can be an already processed one
            case Msg of
                {Code, Reason} when is_binary(Code), is_binary(Reason) ->
                    {Code, Reason};
                {Code, _} when is_atom(Code); is_binary(Code) ->
                    ?I("NkSERVER unknown msg: ~p (~p)", [Msg, SrvId]),
                    {to_bin(Code), <<>>};
                Code when is_atom(Code); is_binary(Code) ->
                    ?I("NkSERVER unknown msg: ~p (~p)", [Msg, SrvId]),
                    {to_bin(Code), <<>>};
                Other ->
                    Ref = erlang:phash2(make_ref()) rem 10000,
                    ?N("NkSERVER unknown internal msg (~p): ~p (~p)", [Ref, Other, SrvId]),
                    {<<"internal_error">>, get_msg_fmt("Internal msg (~p)", [Ref])}
            end
    end.


%% @private
get_msg_code(Term) when is_atom(Term); is_binary(Term); is_list(Term) ->
    to_bin(Term);

get_msg_code(Tuple) when is_tuple(Tuple) ->
    get_msg_code(element(1, Tuple));

get_msg_code(Error) ->
    ?N("Invalid format in API reason: ~p", [Error]),
    <<"internal_error">>.


%% @private
get_msg_fmt(Fmt, List) ->
    case catch io_lib:format(Fmt, List) of
        {'EXIT', _} ->
            ?N("Invalid format API reason: ~p, ~p", [Fmt, List]),
            <<>>;
        Val ->
            list_to_binary(Val)
    end.



%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).
