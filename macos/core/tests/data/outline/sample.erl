%% Erlang のアウトライン解析のサンプル
-module(sample).
-export([start/0, add/2]).

start() ->
    io:format("hello~n").

add(A, B) when is_integer(A) ->
    A + B;
add(A, B) ->
    A ++ B.

%% comment() -> ok.
loop(State) ->
    receive
        stop -> ok;
        {msg, M} -> loop([M | State])
    end.

'quoted atom'(X) -> X.
