-ifndef(NKSERVER_HRL_).
-define(NKSERVER_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================

-define(SRV_DELAYED_DESTROY, 3000).


%% ===================================================================
%% Records
%% ===================================================================


%% The callback module should have generated this function after parse transform
-define(CALL_SRV(Id, Fun, Args), apply(Id, nkserver_callback, [Fun, Args])).


-endif.

