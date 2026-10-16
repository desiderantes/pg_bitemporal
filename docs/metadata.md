# Bitemporal Metadata

Bitemporal tables need to store information about constraints
that are specific to bitemporal tables. This implementation has
chosen to leverage the existing catalog to store this information.
As there is no specific bitemporal support in PostgreSQL, the
information must be encoded into existing catalog entry types.
This encoded data must be read and parsed to return the actionable
information.

This metadata deals with three constraints: Foreign Key, Primary Key, and
Unique.

The other constraints are not considered to be different in the case of
bitemporal tables vs normal tables. The NOT NULL constraint is the same
on both tables. Triggers, Exclusion, and Check constraints
will need to be written as bitemporal-aware.
There is no support for them in these functions.


## Create Constraints

There are three functions to create the necessary clauses for a `CREATE TABLE`
or an `ALTER TABLE` statement to add the particular bitemporal constraint.

These constraints are not enforced by PostgreSQL itself. Therefore, it is
necessary to store information about the constraints in the pg catalog. These
entries are encoded in the source column of specially named check constraints.
The check constraint is supposed to always be true
and contains a string with @ at the beginning and end to delimit the
information about the bitemporal constraint.

### PK

The Primary Key supports a single column which is encoded as the column name
delimited by @.

This creates a clause for recording a single column as a primary key of a
bitemporal table.

```sql
    select bitemporal_internal.pk_constraint('id')
```

### FK

The Foreign Key supports a single column-to-column FK. The tuple of column,
foreign table, and foreign column are encoded like this:
`'@local_column -> remote_table(remote_column)@'`

This creates a clause for recording a foreign key relationship between
a single column in the local table and a referenced column in a foreign table.
This takes three arguments: the first is the local column, the second is the
foreign table, and the third is the foreign table column.

```sql
    select bitemporal_internal.fk_constraint('user_id', 'users', 'user_id')
```


### Unique

PostgreSQL enforces the Unique constraint by re-encoding a bitemporal
unique constraint as an exclude constraint with the unique column and
the bitemporal time ranges.

This creates a constraint to maintain a unique column of values across the
bitemporal dimensions.

```sql
    select string_agg(a, ',\n') from
        bitemporal_internal.unique_constraint('username') as s(a)
```


### Alter helper

This method constructs the `ALTER TABLE` statement given the output of one of
the functions above.

```sql
    select bitemporal_internal.add_constraint('users', bitemporal_internal.pk_constraint('username') );
```


## Search for Bitemporal Constraints

There are two functions to find bitemporal Primary Key and bitemporal
Foreign Key constraints. These functions decode the information embedded in the catalog.


### Primary Key

The function finds the bitemporal primary key for the given table. The name
of the column is returned as a text value. Only one column is supported.

```sql
  select bitemporal_internal.find_pk('schema.table_name')
```

### Foreign Key

The function finds all the bitemporal Foreign Key constraints for a given
table. The function returns the complete set of all Foreign Keys for the
given table.

There is a special composite type in the
form of a table *bitemporal\_internal.fk\_constraint\_type*.

```sql
    create table if not exists bitemporal_internal.fk_constraint_type (
       conname name
      , src_column  name
      , fk_table text
      , fk_column name
    );
```

The `conname` column exists to assist debugging and is not required to determine the FK
relationship. The type also only supports foreign keys of one column.

```sql
    select * from bitemporal_internal.find_fk('schema.table_name')
```




# Examples

The two main use cases are adding constraints at table creation time or after
the table exists.


To add a unique constraint to an existing table *users* for the column
*username*, you would do the following. Using the `unique_constraint`
function to create valid constraint clauses, the `add_constraint` function
places the clauses in an `ALTER TABLE` statement that can be executed dynamically.

```sql
DO $do$
DECLARE
  rc text;
BEGIN
    select string_agg(a, ';') into rc from
        ( select bitemporal_internal.add_constraint('users', aa) from
                bitemporal_internal.unique_constraint('username') as s(aa)
        ) as t(a);
    execute rc;
END;
$do$;
```

Alternatively, the `execute_add_constraint` function can dynamically execute the `ALTER TABLE` statements directly:
```sql
    select bitemporal_internal.execute_add_constraint('users', a) from
           bitemporal_internal.unique_constraint('username') as s(a);
```



If you wish to create a primary key clause to add to a `CREATE TABLE`, you can get the
clause by the following:

```sql
    select bitemporal_internal.pk_constraint('id')
```


If you wish to create a table with a FK clause at the same time, you may do something like
the following:


```sql
    DO $do$ BEGIN
      execute format($$create table groups ( group_id serial,
           group_name text, user_id int,
           %s ); $$,
          bitemporal_internal.fk_constraint('user_id', 'users', 'user_id') );
    END; $do$;
```


## Example of how Catalog is Used

This example demonstrates how bitemporal constraint clauses are generated, incorporated into a `CREATE TABLE` statement, and stored in and queried from the PostgreSQL catalog (`pg_constraint`).

### 1. Generating Constraint Clauses

Call the metadata helper functions to construct the synthetic bitemporal constraint definitions:

```sql
SELECT bitemporal_internal.pk_constraint('group_id');
-- Output: CONSTRAINT "bitemporal pk group_id" check(true or 'pk' <> '@group_id@')

SELECT bitemporal_internal.fk_constraint('user_id', 'users', 'user_id');
-- Output: CONSTRAINT "bitemporal fk user_id users user_id" check(true or 'fk' <> '@user_id -> users(user_id)@')
```

### 2. Resulting Table Definition

Include the generated constraint clauses directly in your `CREATE TABLE` statement:

```sql
CREATE TABLE groups (
    group_id integer,
    group_name text,
    user_id integer,
    effective temporal_relationships.timeperiod,
    asserted temporal_relationships.timeperiod,
    CONSTRAINT "bitemporal pk group_id" CHECK (true OR 'pk' <> '@group_id@'),
    CONSTRAINT "bitemporal fk user_id users user_id" CHECK (true OR 'fk' <> '@user_id -> users(user_id)@')
);
```

### 3. Inspecting the Catalog

Query `pg_constraint` to inspect the stored constraint definitions:

```sql
SELECT conname, contype, pg_get_expr(conbin, conrelid) AS consrc
FROM pg_constraint
WHERE conrelid = 'groups'::regclass
  AND conname LIKE 'bitemporal %';
```

Output:
```text
              conname               | contype |                              consrc                               
------------------------------------+---------+-------------------------------------------------------------------
 bitemporal pk group_id             | c       | (true OR ('pk'::text <> '@group_id@'::text))
 bitemporal fk user_id users user_id | c       | (true OR ('fk'::text <> '@user_id -> users(user_id)@'::text))
```

You can then retrieve these constraints programmatically via the bitemporal metadata query functions:

```sql
-- Find Primary Key column
SELECT bitemporal_internal.find_pk('groups');
-- Result: group_id

-- Find Foreign Key definitions
SELECT conname, src_column, fk_table, fk_column
FROM bitemporal_internal.find_fk('groups');
-- Result:
--               conname              | src_column | fk_table | fk_column 
-- -----------------------------------+------------+----------+-----------
--  bitemporal fk user_id users user_id | user_id    | users    | user_id
```

