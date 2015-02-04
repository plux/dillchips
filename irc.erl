-module(irc).
-compile(export_all).

-record(state, {sock, config}).

%% API
start() ->
    start("bot.config").

start(ConfigFile) ->
    {ok, Config} = file:consult(ConfigFile),
    log("Loaded config: ~p", [Config]),
    spawn(fun() -> connect(Config) end).

join(Pid, Channel) ->
    Pid ! {join, Channel}.

reload(Pid) ->
    Pid ! reload.

say(Pid, Channel, Msg) ->
    Pid ! {say, Channel, Msg}.

quit(Pid) ->
    Pid ! quit.

reconnect(Pid) ->
    Pid ! reconnect.

%% Internal
connect(Config) ->
    Server = proplists:get_value(server, Config),
    Port   = proplists:get_value(port, Config),
    Nick   = proplists:get_value(nick, Config),
    log("~s connecting to ~s:~p", [Nick, Server, Port]),
    {ok, Sock} = gen_tcp:connect(Server, Port, [{packet, line}]),
    State = #state{sock = Sock, config = Config},
    ok = send(State, ["NICK ", Nick]),
    ok = send(State, ["USER ", Nick, " 8 * :", Nick]),
    safe_loop(State).

safe_loop(State) ->
    try
	loop(State)
    catch
	A:B ->
	    log("caught exception: ~p:~p ~p",
		[A, B, erlang:get_stacktrace()]),
	    safe_loop(State)
    end.

loop(#state{sock = Sock, config = Config} = State) ->
    receive
	reconnect ->
	    catch gen_tcp:close(Sock),
	    connect(Config);
	{tcp, Sock, Data} ->
	    log("recv: ~p", [Data]),
	    respond(State, string:tokens(Data, ": "));
	reload ->
	    ok;
        {join, Channel} ->
	    join_channel(State, Channel);
	{say, Channel, Msg} ->
	    msg(State, Channel, Msg);
	quit ->
	    log("Quitting, bye!"),
	    catch gen_tcp:close(Sock),
	    throw(quit)
    end,
    ?MODULE:loop(State).

%% Ping
respond(State, ["PING"|Rest]) ->
    send(State, "PONG " ++ Rest);
%% Privmsg
respond(State, [Who, "PRIVMSG", Chan | Rest]) ->
    Msg = string:join(Rest, " "),
    case Msg of
	"hej" ++ _ ->
	    Answer = io_lib:format("hej ~s!", [nick(Who)]),
	    msg(State, Chan, Answer);
	_ ->
	    log("message is: " ++ Msg)
    end;
%% End of MOTD
respond(State, [_, "376"|_]) ->
    join_channels(State);
%% Rest
respond(_State, Tokens) ->
    log("Tokens: ~p", [Tokens]).

nick(Who) ->
    [Nick|_] = string:tokens(Who, "!"),
    Nick.

msg(State, To, Message) ->
    send(State, ["PRIVMSG ", To, " :", Message]).

send(State, Msg) ->
    log("send: ~p\n", [Msg]),
    gen_tcp:send(sock(State),  [Msg, "\r\n"]).

sock(#state{sock = Sock}) ->
    Sock.

config(#state{config = Config}) ->
    Config.

log(Fmt) ->
    log(Fmt, []).

log(Fmt, Args) ->
    io:format(timestamp() ++ Fmt ++ "\n", Args).

timestamp() ->
    {_Date, {H, M, S}} = calendar:local_time(),
    Ts = io_lib:format("[~2..0B:~2..0B:~2..0B] ", [H, M, S]),
    lists:flatten(Ts).

join_channels(State) ->
    Config = config(State),
    Channels = proplists:get_value(channels, Config),
    log("Joining channels: ~p", [Channels]),
    [join_channel(State, Channel) || Channel <- Channels].

join_channel(State, Channel) ->
    send(State, ["JOIN ", Channel]).
