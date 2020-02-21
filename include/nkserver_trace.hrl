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

-ifndef(NKSERVER_TRACE_HRL_).
-define(NKSERVER_TRACE_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================

-define(LEVEL_DEBUG, 1).
-define(LEVEL_TRACE, 2).
-define(LEVEL_INFO, 3).
-define(LEVEL_EVENT, 4).
-define(LEVEL_NOTICE, 5).
-define(LEVEL_WARNING, 6).
-define(LEVEL_ERROR, 7).
-define(LEVEL_OFF, 9).

-record(nkserver_span, {
    id :: term(),
    name :: binary(),
    levels :: [{atom(), nkserver_trace:level_num()}],
    meta = #{}
}).

-endif.

