Sqerl
=====

<img src="http://cloud.github.com/downloads/devinus/sqerl/sqerl.jpg" align="right" />

Sqerl is a domain specific embedded language for expressing SQL
statements in Erlang as well as a library for generating the literal
equivalents of Sqerl expressions.

Sqerl lets you describe SQL queries using a combination of Erlang
lists, tuples, atoms and values in a way that resembles the structure
of SQL statements. You can pass this structure to the `sql/1` or
`sql/2` functions, which parse it and return an iolist (a tree of
strings and/or binaries) or a single binary, either of which can be
sent to database engine through a socket (usually via a
database-specific driver).

Sqerl supports a large subset of the SQL language implemented by some
popular RDBMS's, including most common `INSERT`, `UPDATE`, `DELETE` and
`SELECT` statements. Sqerl can generate complex queries including those
with unions, nested statements and aggregate functions, but it does
not currently attempt to cover every feature and extension of the SQL
language.

Sqerl's benefits are:

- Easy dynamic generation of SQL queries from Erlang by combining
  native Erlang types rather than string fragments.
- Prevention of most, if not all, SQL injection attacks by assuring
  that all string values are properly escaped.
- Efficient generation of iolists as nested lists of binaries.

*Warning*: Sqerl allows you to write verbatim `WHERE` clauses as well
as verbatim `LIMIT` and other trailing clauses, but using this feature
is highly discouraged because it exposes you to SQL injection attacks.

For usage examples, look at the file `test/sqerl_tests.erl`.

Acknowledgements
================

Almost entirely based on ErlyWeb's ErlSQL by Yariv Sadan.