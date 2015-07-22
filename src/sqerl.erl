-module(sqerl).
-export([sql/1, sql/2, unsafe_sql/1, unsafe_sql/2, encode/1]).

%% @doc Generate an iolist (a tree of strings and/or binaries)
%% for a literal SQL statement that corresponds to the Sqerl
%% structure. If the structure is invalid, this function would
%% crash.
%%
%% This function does not allow writing literal `WHERE', `LIMIT'
%% and other trailing clauses. To write such clauses,
%% call `unsafe_sql/1' or `unsafe_sql/2'.
-spec sql(Sqerl::term()) -> iolist().
sql(Sqerl) ->
    sql2(Sqerl, true).

%% @doc Similar to sql/1, but accepts a boolean parameter
%% indicating if the return value should be a single binary
%% rather than an iolist.
-spec sql(Sqerl::term(), boolean()) -> binary() | iolist().
sql(Sqerl, true) ->
    iolist_to_binary(sql(Sqerl));
sql(Sqerl, false) ->
    sql(Sqerl).

%% @doc Generate an iolist (a tree of strings and/or binaries)
%% for a literal SQL statement that corresponds to the Sqerl
%% structure. If the structure is invalid, this function
%% throws an exception.
%%
%% This function allows writing literal `WHERE', `LIMIT'
%% and other trailing clauses, such as `{where, "a=" ++ Val}',
%% or `"WHERE a=" ++ Str ++ " LIMIT 5"'.
%%
%% Such clauses are unsafe because they expose you to SQL
%% injection attacks. When you use `unsafe_sql', make sure to
%% quote all your strings using the `encode/1' function.
%%
%% @throws {error, {unsafe_expression, Expr}}
-spec unsafe_sql(Sqerl::term()) -> iolist().
unsafe_sql(Sqerl) ->
    sql2(Sqerl, false).

%% @doc Similar to `unsafe_sql/1', but accepts a boolean parameter
%% indicating if the return value should be a binary or an iolist.
%%
%% @throws {error, {unsafe_expression, Expr}}
-spec unsafe_sql(Sqerl::term(), AsBinary::boolean()) -> binary() | iolist().
unsafe_sql(Sqerl, true) ->
    iolist_to_binary(unsafe_sql(Sqerl));
unsafe_sql(Sqerl, false) ->
    unsafe_sql(Sqerl).

%% @doc Calls `encode(Val, true)'.
-spec encode(Val::term()) -> binary().
encode(Val) ->
    encode(Val, true).

%% @doc Encode a value as a string or a binary to be embedded in
%% a SQL statement.
%%
%% This function can encode numbers, atoms, date/time/datetime values,
%% strings and binaries (which it escapes automatically).
-spec encode(Val::term(), AsBinary::boolean()) -> string() | binary().
encode(Val, false) when Val =:= undefined; Val =:= null ->
    "null";
encode(Val, true) when Val =:= undefined; Val =:= null ->
    <<"null">>;
encode(Val, false) when is_binary(Val) ->
    binary_to_list(quote(Val));
encode(Val, true) when is_binary(Val) ->
    quote(Val);
encode(Val, true) ->
    list_to_binary(encode(Val,false));
encode(Val, false) when is_atom(Val) ->
    quote(atom_to_list(Val));
encode(Val, false) when is_list(Val) ->
    quote(Val);
encode(Val, false) when is_integer(Val) ->
    integer_to_list(Val);
encode(Val, false) when is_float(Val) ->
    nicedecimal:format(Val);
encode({datetime, Val}, AsBinary) ->
    encode(Val, AsBinary);
encode({{Year,Month,Day}, {Hour,Minute,Second}}, false) ->
    [Year1,Month1,Day1,Hour1,Minute1,Second1] =
        lists:map(fun two_digits/1,[Year, Month, Day, Hour, Minute,Second]),
    lists:flatten(io_lib:format("'~s-~s-~s ~s:~s:~s'",
        [Year1,Month1,Day1,Hour1,Minute1,Second1]));
encode({date, {Year, Month, Day}}, false) ->
    [Year1,Month1,Day1] =
        lists:map(fun two_digits/1,[Year, Month, Day]),
    lists:flatten(io_lib:format("'~s-~s-~s'",[Year1,Month1,Day1]));
encode({time, {Hour, Minute, Second}}, false) ->
    [Hour1,Minute1,Second1] =
        lists:map(fun two_digits/1,[Hour, Minute, Second]),
    lists:flatten(io_lib:format("'~s:~s:~s'",[Hour1,Minute1,Second1]));
encode(Val, _AsBinary) ->
    {error, {unrecognized_value, {Val}}}.

two_digits(Nums) when is_list(Nums) ->
    [two_digits(Num) || Num <- Nums];
two_digits(Num) ->
    [Str] = io_lib:format("~b", [Num]),
    case length(Str) of
        1 -> [$0 | Str];
        _ -> Str
    end.

sql2({select, Tables}, Safe)->
    select(Tables, Safe);
sql2({select, Fields, {from, Tables}}, Safe) ->
    select(Fields, Tables, Safe);
sql2({select, Fields, {from, Tables}, {where, WhereExpr}}, Safe) ->
    select(undefined, Fields, Tables, WhereExpr, undefined, Safe);
sql2({select, Fields, {from, Tables}, {where, WhereExpr}, Extras}, Safe) ->
    select(undefined, Fields, Tables, WhereExpr, Extras, Safe);
sql2({select, Fields, {from, Tables}, WhereExpr, Extras}, Safe) ->
    select(undefined, Fields, Tables, WhereExpr, Extras, Safe);
sql2({select, Fields, {from, Tables}, Extras}, Safe) ->
    select(undefined, Fields, Tables, undefined, Extras, Safe);
sql2({select, Tables, {where, WhereExpr}}, Safe) ->
    select(undefined, undefined, Tables, WhereExpr, Safe);
sql2({select, Tables, WhereExpr}, Safe) ->
    select(undefined, undefined, Tables, WhereExpr, Safe);
sql2({select, Modifier, Fields, {from, Tables}}, Safe) ->
    select(Modifier, Fields, Tables, Safe);
sql2({select, Modifier, Fields, {from, Tables}, {where, WhereExpr}}, Safe) ->
    select(Modifier, Fields, Tables, WhereExpr, Safe);
sql2({select, Modifier, Fields, {from, Tables}, Extras}, Safe) ->
    select(Modifier, Fields, Tables, undefined, Extras, Safe);
sql2({select, Modifier, Fields, {from, Tables}, {where, WhereExpr}, Extras},
    Safe) ->
    select(Modifier, Fields, Tables, WhereExpr, Extras, Safe);
sql2({select, Modifier, Fields, {from, Tables}, WhereExpr, Extras}, Safe) ->
    select(Modifier, Fields, Tables, WhereExpr, Extras, Safe);

sql2({Select1, union, Select2}, Safe) ->
    [$(, sql2(Select1, Safe), <<") UNION (">>, sql2(Select2, Safe), $)];
sql2({Select1, union, Select2, {where, WhereExpr}}, Safe) ->
    [sql2({Select1, union, Select2}, Safe), where(WhereExpr, Safe)];
sql2({Select1, union, Select2, Extras}, Safe) ->
    [sql2({Select1, union, Select2}, Safe), extra_clause(Extras, Safe)];
sql2({Select1, union, Select2, {where, _} = Where, Extras}, Safe) ->
    [sql2({Select1, union, Select2, Where}, Safe), extra_clause(Extras, Safe)];

sql2({Select1, union_all, Select2}, Safe) ->
    [$(, sql2(Select1, Safe), <<") UNION ALL (">>, sql2(Select2, Safe), $)];
sql2({Select1, union_all, Select2, {where, WhereExpr}}, Safe) ->
    [sql2({Select1, union, Select2}, Safe), where(WhereExpr, Safe)];
sql2({Select1, union_all, Select2, Extras}, Safe) ->
    [sql2({Select1, union, Select2}, Safe), extra_clause(Extras, Safe)];
sql2({Select1, union_all, Select2, {where, _} = Where, Extras}, Safe) ->
    [sql2({Select1, union, Select2, Where}, Safe), extra_clause(Extras, Safe)];

sql2({insert, Table, Params}, _Safe) ->
    insert(Table, Params);
sql2({insert, Table, Params, Returning}, Safe) ->
    insert(Table, Params, Returning, Safe);

sql2({update, Table, Props}, Safe) ->
    update(Table, Props, Safe);
sql2({update, Table, Props, {where, Where}}, Safe) ->
    update(Table, Props, Where, Safe);
sql2({update, Table, Props, Where}, Safe) ->
    update(Table, Props, Where, Safe);

sql2({delete, {from, Table}}, Safe) ->
    delete(Table, Safe);
sql2({delete, Table}, Safe) ->
    delete(Table, Safe);
sql2({delete, {from, Table}, {where, Where}}, Safe) ->
    delete(Table, undefined, Where, Safe);
sql2({delete, Table, {where, Where}}, Safe) ->
    delete(Table, undefined, Where, Safe);
sql2({delete, Table, Where}, Safe) ->
    delete(Table, undefined, Where, Safe);
sql2({delete, Table, Using, Where}, Safe) ->
    delete(Table, Using, Where, Safe);
sql2({delete, Table, Using, Where, Extras}, Safe) ->
    delete(Table, Using, Where, Extras, Safe).

select(Fields, Safe) ->
    select(undefined, Fields, undefined, undefined, undefined, Safe).

select(Fields, Tables, Safe) ->
    select(undefined, Fields, Tables, undefined, undefined, Safe).

select(Modifier, Fields, Tables, Safe) ->
    select(Modifier, Fields, Tables, undefined, undefined, Safe).

select(Modifier, Fields, Tables, WhereExpr, Safe) ->
    select(Modifier, Fields, Tables, WhereExpr, undefined, Safe).

select(Modifier, Fields, Tables, WhereExpr, Extras, Safe) ->
    S1 = <<"SELECT ">>,
    S2 = case Modifier of
        undefined -> S1;
        Modifier ->
            Modifier1 = case Modifier of
                distinct -> 'DISTINCT';
                'all' -> 'ALL';
                Other -> Other
            end,
            [S1, convert(Modifier1), $\s]
    end,

    ListFun = fun(Val) -> expr2(Val, Safe) end,
    S3 = [S2, make_list(Fields, ListFun)],
    S4 = case Tables of
        undefined -> S3;
        _Other -> [S3, <<" FROM ">>, make_list(Tables, ListFun)]
    end,

    S5 = case where(WhereExpr, Safe) of
        undefined -> S4;
        WhereClause -> [S4, WhereClause]
    end,

    case extra_clause(Extras, Safe) of
        undefined -> S5;
        Expr -> [S5, Expr]
    end.

where(undefined, _) -> [];
where(Expr, true) when is_list(Expr); is_binary(Expr) ->
    throw({error, {unsafe_expression, Expr}});
where(Expr, false) when is_binary(Expr) ->
    Res = case Expr of
        <<"WHERE ", _Rest/binary>> = Expr1 ->
            Expr1;
        <<"where ", Rest/binary>> ->
            <<"WHERE ", Rest/binary>>;
        Expr1 ->
            <<"WHERE ", Expr1/binary>>
    end,
    [$\s, Res];
where(Exprs, false) when is_list(Exprs)->
    where(list_to_binary(Exprs), false);
where(Expr, Safe) when is_tuple(Expr) ->
    case expr(Expr, Safe) of
        undefined -> [];
        Other -> [<<" WHERE ">>, Other]
    end.

extra_clause(undefined, _Safe) -> undefined;
extra_clause(Expr, true) when is_binary(Expr) ->
    throw({error, {unsafe_expression, Expr}});
extra_clause(Expr, false) when is_binary(Expr) -> [$\s, Expr];
extra_clause([Expr], false) when is_binary(Expr) -> [$\s, Expr];
extra_clause(Exprs, Safe) when is_list(Exprs) ->
    case is_tuple(hd(Exprs)) of
        true ->
            extra_clause2(Exprs, false);
        false ->
            if not Safe ->
                [$\s, list_to_binary(Exprs)];
            true ->
                throw({error, {unsafe_expression, Exprs}})
            end
    end;
extra_clause(Exprs, true) when is_list(Exprs) ->
    extra_clause2(Exprs, true);
extra_clause({limit, Num}, _Safe) ->
    [<<" LIMIT ">>, encode(Num)];
extra_clause({limit, Offset, Num}, _Safe) ->
    [<<" LIMIT ">>, encode(Offset), <<", ">> , encode(Num)];
extra_clause({group_by, ColNames}, _Safe) ->
    [<<" GROUP BY ">>, make_list(ColNames, fun convert/1)];
extra_clause({group_by, ColNames, having, Expr}, Safe) ->
    [extra_clause({group_by, ColNames}, Safe), <<" HAVING ">>,
     expr(Expr, Safe)];
extra_clause({order_by, ColNames}, Safe) ->
    [<<" ORDER BY ">>,
     make_list(ColNames, fun({Name, Modifier}) when Modifier =:= 'asc' ->
                                [expr(Name, Safe), $\s, convert('ASC')];
                            ({Name, Modifier}) when Modifier =:= 'desc' ->
                                [expr(Name, Safe), $\s, convert('DESC')];
                            (Name) ->
                                expr(Name, Safe)
                         end)].

extra_clause2(Exprs, Safe) ->
    Res = [extra_clause(Expr,Safe) || Expr <- Exprs, Expr =/= undefined],
    [Res].

insert(Table, Params) when is_list(Params) ->
    Names = make_list(Params, fun({Name, _}) -> convert(Name) end),
    Values = [$(, make_list(Params, fun({_, Val}) -> encode(Val) end), $)],
    make_insert_query(Table, Names, Values);
insert(Table, {Fields, Records}) ->
    Names = make_list(Fields, fun convert/1),
    Values = make_list(Records, fun(Record) ->
        Record1 = if is_tuple(Record) -> tuple_to_list(Record);
            true -> Record
        end,
        [$(, make_list(Record1, fun encode/1), $)]
    end),
    make_insert_query(Table, Names, Values).

insert(Table, Params, undefined, _Safe) ->
    insert(Table, Params);
insert(Table, Params, {returning, Ret}, Safe) ->
    insert(Table, Params, Ret, Safe);
insert(Table, Params, Returning, Safe) ->
    [insert(Table, Params), <<" RETURNING ">>, expr(Returning, Safe)].

make_insert_query(Table, Names, Values) ->
    [<<"INSERT INTO ">>, convert(Table),
     <<"(">>, Names, <<") VALUES ">>, Values].

update(Table, Props, Safe) ->
    update(Table, Props, undefined, Safe).

update(Table, Props, Where, Safe) when not is_list(Props) ->
    update(Table, [Props], Where, Safe);
update(Table, Props, Where, Safe) ->
    S1 = [<<"UPDATE ">>, convert(Table), <<" SET ">>],
    S2 = make_list(Props, fun({Field, Val}) ->
        [convert(Field), <<" = ">>, expr(Val, Safe)]
    end),
    [S1, S2, where(Where, Safe)].

delete(Table, Safe) ->
    delete(Table, undefined, undefined, undefined, Safe).

delete(Table, Using, WhereExpr, Safe) ->
    delete(Table, Using, WhereExpr, undefined, Safe).

delete(Table, Using, WhereExpr, Extras, Safe) ->
    S1 = [<<"DELETE FROM ">>, convert(Table)],
    S2 = if Using =:= undefined -> S1;
        true -> [S1, <<" USING ">>, make_list(Using, fun convert/1)]
    end,
    S3 = case where(WhereExpr, Safe) of
        undefined -> S2;
        WhereClause -> [S2, WhereClause]
    end,
    if Extras =:= undefined ->
        S3;
    true ->
        [S3, extra_clause(Extras, Safe)]
    end.

convert(Val) when is_atom(Val)->
    atom_to_binary(Val, utf8).

make_list(Vals, ConvertFun) when is_list(Vals) ->
    string:join([[ConvertFun(Val)] || Val <- Vals],", ");
make_list(Val, ConvertFun) ->
    ConvertFun(Val).

expr(undefined, _Safe) -> <<"NULL">>;
expr({Not, Expr}, Safe) when (Not =:= 'not' orelse Not =:= '!') ->
    [<<"NOT ">>, check_expr(Expr, Safe)];
expr({Table, Field}, _Safe) when is_atom(Table), is_atom(Field) ->
    [convert(Table), $., convert(Field)];
expr({Expr1, as, Alias}, Safe) when is_atom(Alias) ->
    [expr2(Expr1, Safe), <<" AS ">>, convert(Alias)];
expr({call, FuncName, []}, _Safe) ->
    [convert(FuncName), <<"()">>];
expr({call, FuncName, Params}, _Safe) ->
    [convert(FuncName), $(, make_list(Params, fun param/1), $)];
expr({Val, Op, {select, _} = Subquery}, Safe) ->
    subquery(Val, Op, Subquery, Safe);
expr({Val, Op, {select, _, _} = Subquery}, Safe) ->
    subquery(Val, Op, Subquery, Safe);
expr({Val, Op, {select, _, _, _} = Subquery}, Safe) ->
    subquery(Val, Op, Subquery, Safe);
expr({Val, Op, {select, _, _, _, _} = Subquery}, Safe) ->
    subquery(Val, Op, Subquery, Safe);
expr({Val, Op, {select, _, _, _, _, _} = Subquery}, Safe) ->
    subquery(Val, Op, Subquery, Safe);
expr({Val, Op, {select, _, _, _, _, _, _} = Subquery}, Safe) ->
    subquery(Val, Op, Subquery, Safe);
expr({Val, Op, {_, union, _} = Subquery}, Safe) ->
    subquery(Val, Op, Subquery, Safe);
expr({Val, Op, {_, union, _, _} = Subquery}, Safe) ->
    subquery(Val, Op, Subquery, Safe);
expr({Val, Op, {_, union, _, _, _} = Subquery}, Safe) ->
    subquery(Val, Op, Subquery, Safe);
expr({_, in, []}, _Safe) -> <<"0">>;
expr({Val, Op, Values}, Safe) when (Op =:= in orelse
                                    Op =:= any orelse
                                    Op =:= some) andalso is_list(Values) ->
    [expr2(Val, Safe), subquery_op(Op), make_list(Values, fun encode/1), $)];
expr({undefined, Op, Expr2}, Safe) when Op =:= 'and'; Op =:= 'not' ->
    expr(Expr2, Safe);
expr({Expr1, Op, undefined}, Safe) when Op =:= 'and'; Op =:= 'not' ->
    expr(Expr1, Safe);
expr({Expr1, Op, Expr2}, Safe)  ->
    {B1, B2} = if (Op =:= 'and' orelse Op =:= 'or') ->
        {check_expr(Expr1, Safe), check_expr(Expr2, Safe)};
    true ->
        {expr2(Expr1, Safe), expr2(Expr2, Safe)}
    end,
    [$(, B1, $\s, op(Op), $\s, B2, $)];

expr({list, Vals}, _Safe) when is_list(Vals) ->
    [$(, make_list(Vals, fun encode/1), $)];
expr({Op, Exprs}, Safe) when is_list(Exprs) ->
    Res = [[expr(Expr,Safe)] || Expr <- Exprs ],
    [$(, string:join(Res,[$\s, op(Op), $\s]), $)];
expr('?', _Safe) -> $?;
expr(null, _Safe) -> <<"NULL">>;
expr(Val, _Safe) when is_atom(Val) -> convert(Val);
expr(Val, _Safe) -> encode(Val).

check_expr(Expr, Safe) when is_list(Expr); is_binary(Expr) ->
    if Safe -> throw({error, {unsafe_expression, Expr}});
        true -> iolist_to_binary([$(, Expr, $)])
    end;
check_expr(Expr, Safe) -> expr(Expr, Safe).

op(Op) -> convert(op1(Op)).
op1('and') -> 'AND';
op1('or') -> 'OR';
op1(like) -> 'LIKE';
op1(Op) -> Op.

subquery(Val, Op, Subquery, Safe) ->
    [expr2(Val, Safe), subquery_op(Op), sql2(Subquery, Safe), $)].

subquery_op(in) -> <<" IN (">>;
subquery_op(any) -> <<" ANY (">>;
subquery_op(some) -> <<" SOME (">>.

expr2(undefined, _Safe) -> <<"NULL">>;
expr2(Expr, _Safe) when is_atom(Expr) -> convert(Expr);
expr2(Expr, Safe) -> expr(Expr, Safe).

param({Key, Value}) when is_atom(Key) ->
    case Value of
        {call, _FuncName, _Params} = Call ->
            [convert(Key), <<" := ">>, expr(Call, undefined)];
        _ ->
            [convert(Key), <<" := ">>, encode(Value)]
    end;
param(Key) when is_atom(Key) ->
    convert(Key);
param({call, _FuncName, _Params} = Call) ->
    expr(Call, undefined);
param(Value) ->
    encode(Value).

quote(String) when is_list(String) ->
    [$' | lists:reverse([$' | quote(String, [])])];
quote(Bin) when is_binary(Bin) ->
    list_to_binary(quote(binary_to_list(Bin))).

quote([], Acc) ->
    Acc;
quote([$\0 | Rest], Acc) ->
    quote(Rest, [$0, $\\ | Acc]);
quote([$\n | Rest], Acc) ->
    quote(Rest, [$n, $\\ | Acc]);
quote([$\r | Rest], Acc) ->
    quote(Rest, [$r, $\\ | Acc]);
quote([$\\ | Rest], Acc) ->
    quote(Rest, [$\\ , $\\ | Acc]);
quote([$' | Rest], Acc) ->
    quote(Rest, [$', $\\ | Acc]);
quote([$" | Rest], Acc) ->
    quote(Rest, [$", $\\ | Acc]);
quote([$\^Z | Rest], Acc) ->
    quote(Rest, [$Z, $\\ | Acc]);
quote([C | Rest], Acc) ->
    quote(Rest, [C | Acc]).
