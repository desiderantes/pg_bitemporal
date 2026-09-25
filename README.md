# pg_bitemporal

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12%20%7C%2013%20%7C%2014%20%7C%2015%20%7C%2016%20%7C%2017%20%7C%2018-blue.svg)](https://www.postgresql.org/)
[![Build System](https://img.shields.io/badge/Meson-1.0%2B-green.svg)](https://mesonbuild.com/)
[![Tests](https://img.shields.io/badge/pgTAP-77%20passed-success.svg)](http://pgtap.org/)
[![Documentation](https://img.shields.io/badge/Doxygen-HTML%20%26%20XML-orange.svg)](https://www.doxygen.nl/)

**pg_bitemporal** is a PostgreSQL extension and library that brings comprehensive **bitemporal data management** and
**James Allen's 13 Temporal Interval Relationships** to PostgreSQL.

Bitemporal data models track history across two distinct temporal dimensions:

1. **Effective Time (Valid Time)**: When a business fact is, was, or will be valid in the real world
   (`effective tstzrange`).
2. **Asserted Time (Transaction/System Time)**: When a fact was asserted as true by the database system
   (`asserted tstzrange`).

---

## Key Features

- 🕒 **Bitemporal DDL & Schema Generators**: Create bitemporal tables automatically with surrogate keys, business keys,
  system timestamps (`row_created_at`), and `GiST` exclusion constraints.
- 🔄 **Bitemporal DML (CRUD)**: Insert, update, update-select, deactivate, and delete rows while automatically
  maintaining complete historical validity windows without data loss.
- 🛠️ **Bitemporal Correction**: Correct errant data in-place without creating redundant version history.
- 📐 **Allen's 13 Temporal Interval Relationships**: Full implementation of James Allen's 13 interval relationships
  (`is_before`, `is_after`, `has_starts`, `has_finishes`, `equals`, `is_during`, `is_contained_in`, `is_overlaps`,
  `is_meets`).
- 📊 **Binary Partition Groups**: Abstract relationship queries into Johnston's 5 binary partition groups
  (`has_includes`, `has_contains`, `has_encloses`, `has_aligns_with`, `has_excludes`).

---

## Bitemporal Dimensions Explained

| Dimension           | Field Name       | Type                                              | Description                                                 |
|---------------------|------------------|---------------------------------------------------|-------------------------------------------------------------|
| **Effective Time**  | `effective`      | `temporal_relationships.timeperiod` (`tstzrange`) | Business validity period (`[valid_start, valid_end)`).      |
| **Asserted Time**   | `asserted`       | `temporal_relationships.timeperiod` (`tstzrange`) | System assertion period (`[asserted_start, asserted_end)`). |
| **Audit Timestamp** | `row_created_at` | `timestamptz`                                     | Record creation timestamp (`DEFAULT now()`).                |

### Exclusion Constraint Security

Every bitemporal table created via `pg_bitemporal` includes a PostgreSQL `GiST` exclusion constraint guaranteeing that
no two active records can share the same business key over overlapping effective and asserted ranges:

```sql
CONSTRAINT devices_device_id_assert_eff_excl EXCLUDE 
USING gist (device_id WITH =, asserted WITH &&, effective WITH &&)
```

---

## Quickstart & Usage

### 1. Create a Bitemporal Table

```sql
SELECT bitemporal_internal.ll_create_bitemporal_table(
               'public', -- schema
               'devices', -- table name
               'device_id integer, device_descr text', -- business columns
               'device_id' -- natural business key
       );
```

### 2. Insert Records

```sql
SELECT bitemporal_internal.ll_bitemporal_insert(
               'public.devices',
               'device_id, device_descr',
               $$1, 'Router A'$$,
               '[2024-01-01, infinity)'::temporal_relationships.timeperiod,
               '[now(), infinity)'::temporal_relationships.timeperiod
       );
```

### 3. Update Bitemporally

Bitemporal updates close the current assertion period of matching records and insert a new historical version for the
updated effective range:

```sql
SELECT bitemporal_internal.ll_bitemporal_update(
               'public',
               'devices',
               'device_descr',
               $$'Router A (Upgraded)'$$,
               'device_id',
               $$1$$,
               '[2024-06-01, infinity)'::temporal_relationships.timeperiod,
               '[now(), infinity)'::temporal_relationships.timeperiod
       );
```

### 4. Query Allen's Temporal Relationships

```sql
-- Check if range A is strictly during range B
SELECT temporal_relationships.is_during(
               '[2024-02-01, 2024-05-01)'::temporal_relationships.timeperiod,
               '[2024-01-01, 2024-12-31)'::temporal_relationships.timeperiod
       );
-- Returns TRUE

-- Check if range A overlaps range B in either direction
SELECT temporal_relationships.has_overlaps(
               '[2024-01-01, 2024-06-01)'::temporal_relationships.timeperiod,
               '[2024-05-01, 2024-10-01)'::temporal_relationships.timeperiod
       ); -- Returns TRUE
```

---

## Allen's 13 Temporal Relationships & Partitions

The library implements Allen's 13 basic interval relationships (Allen 1983) and Johnston's binary partition groups
(Johnston 2014):

```
[starts A B]      A |---|
                  B |-------|

[finishes A B]    A |-------|
                  B     |---|

[equals A B]      A |-------|
                  B |-------|

[during A B]      A   |---|
                  B |-------|

[overlaps A B]    A |-----|
                  B    |-----|

[before A B]      A |-----|
                  B          |-----|

[meets A B]       A |-----|
                  B       |-----|
```

### Binary Partition Groups

- **`has_excludes`**: `[Before]`, `[Before^-1]`, `[Meets]`, `[Meets^-1]`
- **`has_includes`**: `[Overlaps]`, `[Overlaps^-1]`, and `Contains`
- **`has_contains`**: `[Equals]` and `Encloses`
- **`has_encloses`**: `[During]`, `[During^-1]`, and `AlignsWith`
- **`has_aligns_with`**: `[Starts]`, `[Starts^-1]`, `[Finishes]`, `[Finishes^-1]`

---

## Building, Testing & Documentation

### Prerequisites

- **PostgreSQL**: 12+ (tested through PostgreSQL 18)
- **Meson**: 1.0+
- **Ninja**: 1.10+
- **Python**: 3.8+ with `sqlparse` (`pip install sqlparse`)
- **Doxygen**: (for documentation generation)

### Setup & Installation

```bash
# Configure Meson build directory
meson setup build \
    -Dpghost=localhost \
    -Dpgport=5432 \
    -Dpguser=postgres \
    -Dpgdatabase=bitemporal

# Load functions into target database
meson compile -C build load

# Run unit test suite (pgTAP)
meson test -C build --verbose
```

### Building Documentation

Generate HTML and XML Doxygen API documentation:

```bash
meson compile -C build docs
```

Generated documentation will be output to `build/docs/html/index.html` and `build/docs/xml/`.

---

## References

1. **James F. Allen (1983)**. *"Maintaining knowledge about temporal intervals."* Commun. ACM 26, 11 (Nov 1983),
   832–843.
2. **Tom Johnston (2014)**. *"Bitemporal Data: Theory and Practice (1st ed.)."* Morgan Kaufmann.
3. **Tom Johnston & Randall Weis (2010)**. *"Managing Time in Relational Databases: How to Design, Update and Query
   Temporal Data."* Morgan Kaufmann.

---

## License

See LICENSE for more info
