begin;

/**
 * @defgroup bitemporal_schema Bitemporal Schema & Table Management
 */
/**
 * @defgroup bitemporal_dml Bitemporal Data Manipulation Operations (DML)
 */
/**
 * @defgroup temporal_relationships Temporal Interval Relationships
 */
/**
 * @defgroup allen_simple Simple Allen Relationships
 */
/**
 * @defgroup allen_during During Allen Relationships
 */
/**
 * @defgroup allen_overlaps Overlaps Allen Relationships
 */
/**
 * @defgroup allen_before Before & After Allen Relationships
 */
/**
 * @defgroup allen_meets Meets Allen Relationships
 */
/**
 * @defgroup allen_partitions Binary Partition Groups
 */
/**
 * @defgroup temporal_support Support Utilities & Domain Constructors
 */

/**
 * @file relationships.sql
 * @ingroup temporal_relationships
 * @brief Allen's 13 Temporal Interval Relationships for PostgreSQL.
 *
 * @details
 * Implements James F. Allen's 13 temporal interval relationships (Allen 1983)
 * along with binary relationship partitions described by Johnston (2014) and Johnston & Weis (2010).
 *
 * ### Naming Conventions
 * - `is_`: Denotes a directional, single relationship (e.g., `is_before` implements `[Before]`, `is_after` implements `[Before^-1]`).
 * - `has_`: Denotes an order-agnostic relationship covering both a relationship and its inverse (e.g., `has_starts` implements `[Starts]` and `[Starts^-1]`).
 * - `equals`: Implements `[Equals]`, which is its own inverse.
 *
 * ### Binary Partition Groups
 * The 13 basic relationships are organized into 5 hierarchical binary partition groups:
 * - **Excludes**: `[Before]`, `[Before^-1]`, `[Meets]`, `[Meets^-1]`
 * - **Includes**: `[Overlaps]`, `[Overlaps^-1]`, and **Contains** group
 * - **Contains**: `[Equals]` and **Encloses** group
 * - **Encloses**: `[During]`, `[During^-1]`, and **AlignsWith** group
 * - **AlignsWith**: `[Starts]`, `[Starts^-1]`, `[Finishes]`, `[Finishes^-1]`
 *
 * ### References
 * 1. James F. Allen. 1983. *"Maintaining knowledge about temporal intervals."* Commun. ACM 26, 11 (Nov 1983), 832-843.
 * 2. Tom Johnston. 2014. *"Bitemporal Data: Theory and Practice (1st ed.)."* Morgan Kaufmann.
 * 3. Tom Johnston & Randall Weis. 2010. *"Managing Time in Relational Databases."* Morgan Kaufmann.
 */

create schema if not exists temporal_relationships;
grant usage on schema temporal_relationships to public;
set local search_path to temporal_relationships, public;

/**
 * @ingroup temporal_support
 * @brief Initializes domain types `timeperiod` and `time_endpoint` if they do not exist.
 * @details Defaults `timeperiod` to `tstzrange` and `time_endpoint` to `timestamptz`.
 */
DO $d$
DECLARE
  domain_range_name text default 'timeperiod';
  domain_range_type text default 'tstzrange';
  domain_i_name text default 'time_endpoint';
  domain_i_type text default 'timestamptz';
BEGIN
-- Create timeperiod domain
PERFORM n.nspname as "Schema",
        t.typname as "Name",
        pg_catalog.format_type(t.typbasetype, t.typtypmod) as "Type"
FROM pg_catalog.pg_type t
      LEFT JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
WHERE t.typtype = 'd'
       AND n.nspname <> 'pg_catalog'
       AND n.nspname <> 'information_schema'
       AND pg_catalog.pg_type_is_visible(t.oid)
   AND t.typname = domain_range_name;
   if FOUND then
     raise NOTICE 'Domain % already exists', domain_range_name;
   else
     execute format('create domain %I as %I', domain_range_name, domain_range_type);
   end if;
-- Create time_endpoint domain
PERFORM n.nspname as "Schema",
        t.typname as "Name",
        pg_catalog.format_type(t.typbasetype, t.typtypmod) as "Type"
FROM pg_catalog.pg_type t
      LEFT JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
WHERE t.typtype = 'd'
       AND n.nspname <> 'pg_catalog'
       AND n.nspname <> 'information_schema'
       AND pg_catalog.pg_type_is_visible(t.oid)
   AND t.typname = domain_i_name;
   if FOUND then
     raise NOTICE 'Domain % already exists', domain_i_name;
   else
     execute format('create domain %I as %I', domain_i_name, domain_i_type);
   end if;
END;
$d$;

/**
 * @ingroup temporal_support
 * @brief Constructs a `timeperiod` interval range from start and end endpoints.
 * @param[in] p_range_start time_endpoint Start endpoint timestamp.
 * @param[in] p_range_end time_endpoint End endpoint timestamp.
 * @return timeperiod Range constructed as `[p_range_start, p_range_end)`.
 */
create or replace
function timeperiod( p_range_start time_endpoint, p_range_end time_endpoint)
RETURNS timeperiod
language sql IMMUTABLE
as
$func$
   select tstzrange(p_range_start, p_range_end,'[)')::timeperiod;
$func$
SET search_path = 'temporal_relationships';

/**
 * @ingroup temporal_support
 * @brief Backwards compatible range constructor function.
 * @param[in] _s time_endpoint Start endpoint timestamp.
 * @param[in] _e time_endpoint End endpoint timestamp.
 * @param[in] _ignored text Ignored parameter maintained for compatibility.
 * @return timeperiod Range constructed via `timeperiod(_s, _e)`.
 */
create or replace
function timeperiod_range( _s time_endpoint, _e time_endpoint, _ignored text)
returns timeperiod
language sql
as
$func$
   select timeperiod(_s,_e);
$func$
SET search_path = 'temporal_relationships';

/**
 * @ingroup temporal_support
 * @brief Logical exclusive-OR (XOR) function.
 * @param[in] a boolean First boolean operand.
 * @param[in] b boolean Second boolean operand.
 * @retval true Exactly one operand is true.
 * @retval false Both operands are true or both are false.
 */
create or replace 
function xor(a boolean, b boolean) returns boolean
language sql IMMUTABLE
as 
$$ select  ( (not a) <> (not b)); $$;

/**
 * @ingroup temporal_support
 * @brief Returns the lower bound (first element) of a range.
 * @param[in] x anyrange Input range.
 * @return anyelement Lower bound element of the range.
 */
create or replace 
function fst( x anyrange ) returns anyelement
language SQL IMMUTABLE 
as
$$ select lower(x); $$;

/**
 * @ingroup temporal_support
 * @brief Returns the upper bound (second element) of a range.
 * @param[in] x anyrange Input range.
 * @return anyelement Upper bound element of the range.
 */
create or replace
function snd( x anyrange ) returns anyelement
language SQL IMMUTABLE 
as
$$ select upper(x); $$;

/**
 * @ingroup allen_simple
 * @brief Evaluates whether two time periods share the same start endpoint (`[Starts]` or `[Starts^-1]`).
 * @details
 * Evaluates whether two time periods start at the exact same instant but end at different times.
 * ```
 *  [starts A B]
 *   A  |---|
 *   B  |-------|
 *
 *  [starts^-1 A B]
 *   A  |-------|
 *   B  |---|
 * ```
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Both time periods start at the same timestamp but have different end timestamps.
 * @retval false Start timestamps differ, or both start and end timestamps match.
 * @sa has_finishes, equals, has_aligns_with
 */
create or replace
function has_starts(a timeperiod , b timeperiod )
returns boolean language SQL IMMUTABLE 
as $$
  select fst(a) = fst(b) and snd(a) <> snd(b);
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_simple
 * @brief Evaluates whether two time periods share the same end endpoint (`[Finishes]` or `[Finishes^-1]`).
 * @details
 * Evaluates whether two time periods finish at the exact same instant but start at different times.
 * ```
 *  [finishes A B]
 *   A  |-------|
 *   B      |---|
 *
 *  [finishes^-1 A B]
 *   A      |---|
 *   B  |-------|
 * ```
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Both time periods finish at the same timestamp but have different start timestamps.
 * @retval false End timestamps differ, or both start and end timestamps match.
 * @sa has_starts, equals, has_aligns_with
 */
create or replace
function has_finishes(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
  select snd(a) = snd(b) and fst(a) <> fst(b);
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_simple
 * @brief Evaluates whether two time periods are identical (`[Equals]`).
 * @details
 * Evaluates whether two time periods start and end at the exact same timestamps.
 * ```
 *  [equals A B]
 *   A  |----|
 *   B  |----|
 * ```
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Both start and end endpoints are identical.
 * @retval false Endpoints differ.
 * @sa has_starts, has_finishes, has_contains
 */
create or replace
function equals(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
  -- doubtful = operator exists for timeperiod
 select fst(a) = fst(b) and snd(a) = snd(b) ;
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_during
 * @brief Evaluates whether time period A is strictly during time period B (`[During]`).
 * @details
 * Returns true if period A starts strictly after period B starts and finishes strictly before period B finishes.
 * ```
 *  [during A B]
 *   A    |---|
 *   B  |-------|
 * ```
 * @param[in] a timeperiod Subject time period.
 * @param[in] b timeperiod Container time period.
 * @retval true Period A is strictly contained inside period B.
 * @retval false Period A is not strictly inside period B.
 * @sa is_contained_in, has_during, has_encloses
 */
create or replace
function is_during(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
  select (fst(a) > fst(b)) and (snd(a) < snd(b));
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_during
 * @brief Evaluates whether time period A contains time period B strictly (`[During^-1]`).
 * @details
 * Inverse of `is_during(a, b)`. Returns true if period B is strictly inside period A.
 * ```
 *  [during^-1 A B]
 *   A  |-------|
 *   B    |---|
 * ```
 * @param[in] a timeperiod Container time period.
 * @param[in] b timeperiod Subject time period.
 * @retval true Period B is strictly contained inside period A.
 * @retval false Period B is not strictly inside period A.
 * @sa is_during, has_during, has_encloses
 */
create or replace
function is_contained_in(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
  select is_during(b, a);
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_during
 * @brief Evaluates whether either period is strictly during the other (`[During]` or `[During^-1]`).
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Either period A is during period B or period B is during period A.
 * @retval false Neither period is strictly during the other.
 * @sa is_during, is_contained_in, has_encloses
 */
create or replace
function has_during(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
  select is_during(a, b) or is_during(b,a);
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_overlaps
 * @brief Evaluates whether time period A starts before and overlaps into time period B (`[Overlaps]`).
 * @details
 * Returns true if period A starts before period B, ends after period B starts, and ends before period B finishes.
 * ```
 *  [overlaps A B]
 *   A  |-----|
 *   B     |-----|
 * ```
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Period A overlaps period B.
 * @retval false Period A does not overlap period B.
 * @sa has_overlaps, has_includes
 */
create or replace
function is_overlaps(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
  select  fst(a) < fst(b) and snd(a) > fst(b) and snd(a) < snd(b);
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_overlaps
 * @brief Evaluates whether either time period overlaps the other (`[Overlaps]` or `[Overlaps^-1]`).
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Either period A overlaps period B or period B overlaps period A.
 * @retval false Neither period overlaps the other.
 * @sa is_overlaps, has_includes
 */
create or replace
function has_overlaps(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
  select  is_overlaps(a , b ) or is_overlaps(b , a ) ;
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_before
 * @brief Evaluates whether time period A strictly precedes time period B (`[Before]`).
 * @details
 * Returns true if period A finishes strictly before period B starts (with a gap between them).
 * ```
 *  [before A B]
 *   A  |-----|
 *   B           |-----|
 * ```
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Period A ends strictly before period B starts.
 * @retval false Period A does not end before period B starts.
 * @sa is_after, has_before, is_meets, has_excludes
 */
create or replace
function is_before(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
  select  snd(a) < fst(b);
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_before
 * @brief Evaluates whether time period A strictly succeeds time period B (`[Before^-1]`).
 * @details
 * Inverse of `is_before(a, b)`. Returns true if period B finishes strictly before period A starts.
 * ```
 *  [before^-1 A B]
 *   A           |-----|
 *   B  |-----|
 * ```
 * @param[in] a timeperiod Subject time period.
 * @param[in] b timeperiod Preceding time period.
 * @retval true Period A starts strictly after period B finishes.
 * @retval false Period A does not start after period B finishes.
 * @sa is_before, has_before, has_excludes
 */
create or replace
function is_after(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
   select snd(b) < fst(a);
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_before
 * @brief Evaluates whether either period is strictly before the other (`[Before]` or `[Before^-1]`).
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Either period A is before period B or period B is before period A.
 * @retval false The periods overlap or touch.
 * @sa is_before, is_after, has_excludes
 */
create or replace
function has_before(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
  select  snd(a) < fst(b) or snd(b) < fst(a);
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_meets
 * @brief Evaluates whether time period A meets time period B seamlessly without gap or overlap (`[Meets]`).
 * @details
 * Returns true if the end timestamp of period A equals the start timestamp of period B.
 * ```
 *  [meets A B]
 *   A  |-----|
 *   B        |-----|
 * ```
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Period A finishes exactly when period B starts.
 * @retval false End of A does not equal start of B.
 * @sa has_meets, is_before, has_excludes
 */
create or replace
function is_meets(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
 select  snd(a) = fst(b) ;
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_meets
 * @brief Evaluates whether two time periods meet in either direction (`[Meets]` or `[Meets^-1]`).
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true End of A equals start of B, or end of B equals start of A.
 * @retval false Neither boundary meets.
 * @sa is_meets, has_excludes
 */
create or replace
function has_meets(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
  select snd(a) = fst(b) or snd(b) = fst(a);
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_partitions
 * @brief Evaluates the `[Includes]` binary partition group.
 * @details
 * Evaluates whether two periods fall into the `[Includes]` partition, which encompasses `[Contains]` or `[Overlaps]`.
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Relationship is in `[Includes]` partition.
 * @retval false Relationship is excluded from `[Includes]`.
 * @sa has_contains, has_overlaps
 */
create or replace
function has_includes(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
  select  fst(a) = fst(b) or snd(a) = snd(b) or 
      (snd(a) <= snd(b) and (fst(a) >= fst(b) or fst(b) < snd(a))) or 
        (snd(a) >= snd(b) and (fst(a) < snd(b) or fst(a) <= fst(b)));
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_partitions
 * @brief Evaluates the `[Contains]` binary partition group.
 * @details
 * Evaluates whether two periods fall into the `[Contains]` partition, which encompasses `[Encloses]` or `[Equals]`.
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Relationship is in `[Contains]` partition.
 * @retval false Relationship is excluded from `[Contains]`.
 * @sa has_encloses, equals, has_includes
 */
create or replace
function has_contains(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
 select fst(a) = fst(b) or snd(a) = snd(b) or 
     (snd(a) < snd(b) and fst(a) > fst(b)) or 
       (snd(b) < snd(a) and fst(b) > fst(a));
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_partitions
 * @brief Evaluates the `[Aligns With]` binary partition group.
 * @details
 * Evaluates whether two periods fall into the `[Aligns With]` partition, which encompasses `[Starts]` or `[Finishes]`.
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Relationship is in `[Aligns With]` partition.
 * @retval false Relationship is excluded from `[Aligns With]`.
 * @sa has_starts, has_finishes, has_encloses
 */
create or replace
function has_aligns_with(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
   select   xor( fst(a) = fst(b) , snd(a) = snd(b) );
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_partitions
 * @brief Evaluates the `[Encloses]` binary partition group.
 * @details
 * Evaluates whether two periods fall into the `[Encloses]` partition, which encompasses `[Aligns With]` or `[During]`.
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Relationship is in `[Encloses]` partition.
 * @retval false Relationship is excluded from `[Encloses]`.
 * @sa has_during, has_aligns_with, has_contains
 */
create or replace
function has_encloses(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
  select has_during(a,b) or has_aligns_with(a,b);
$$
SET search_path = 'temporal_relationships';

/**
 * @ingroup allen_partitions
 * @brief Evaluates the `[Excludes]` binary partition group.
 * @details
 * Evaluates whether two periods fall into the `[Excludes]` partition, which encompasses `[Before]` or `[Meets]`.
 * @param[in] a timeperiod First time period.
 * @param[in] b timeperiod Second time period.
 * @retval true Relationship is in `[Excludes]` partition (periods are disjoint or touching only at boundary).
 * @retval false Periods overlap or enclose each other.
 * @sa has_before, has_meets
 */
create or replace
function has_excludes(a timeperiod, b timeperiod)
returns boolean language SQL IMMUTABLE 
as $$
   select fst(a) >= snd(b) or fst(b) >= snd(a) ;
$$
SET search_path = 'temporal_relationships';

commit;

-- vim: set filetype=pgsql expandtab tabstop=2 shiftwidth=2:
