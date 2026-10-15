<!-- Slide number: 1 -->
# Implementing Temporal Features in PostgreSQL: SQL Standard and Beyond

<!-- Slide number: 2 -->
# Temporal DB Basics

<!-- Slide number: 3 -->
# Why Time Travel is Needed?
Point in Time (Snapshot) queries: How my report looked on last day of previous month?
Change Log: When and how the state of my request was changed?
Fully Temporal:
When these objects co-exist?
Before/after/meets etc.
Temporal joins, aggregations etc.

<!-- Slide number: 4 -->
# Storing Temporal Data
Snapshots: any theoretical paper starts with it
Event Logs: Often produced by applications with a hope that they will be used for analysis in the future
Perionds: Used by everyone who actually implements temporal features in a dabase
All are equivalent but query performance may differ

<!-- Slide number: 5 -->
# Time Semantics
Discrete
Periods with closed-open semantics (I’m not are semantics is the right word on this slide)

<!-- Slide number: 6 -->
# Dimensions of Time
Theis is something beyond common sense in th real life, however, we need them
Transactional (system)
Valid = Effective
Asserted ~ transactional
Much more were defined but are not widely known

<!-- Slide number: 7 -->
# Temporal Features in the SQL Standard

<!-- Slide number: 8 -->
# Data Types and Predicates
Actually no new data types, periods are represented as pairs of timestamp columns
Closed-open periods
Predicates:
OVERLAPS
. . .

<!-- Slide number: 9 -->
# Transactional Time
Past but not future
Data can never be changed
Dose NOT require separate table for historical data, although some implementations do that

<!-- Slide number: 10 -->
# Other Time Dimensions
The standard does not specify any semantics for other time dimensions
Currently at most one additional time dimension can be specified

<!-- Slide number: 11 -->
# Queries and Manipulation
Syntax extensions for INSERT, UPDATE, DELETE to specify period(s)
Syntax extensions for SELECT

<!-- Slide number: 12 -->
# PostgreSQL Support for Temporal Data

<!-- Slide number: 13 -->
# Data Types, Operators, and Predicates
Period data types are provided although are not required by the Standard
Rich set of operators and functions for timestamps, intervals, and periods
Predicates are implemented as required by the Standard (including closed-open semantics)

<!-- Slide number: 14 -->
# Storage and Performance
Spatial indexes
With exclusion

<!-- Slide number: 15 -->
# Bitemporal Implementation

<!-- Slide number: 16 -->
# Overview of Bitemporal
Suports assered and effective time dimensions
Transactional dimension can be queries but is not explicitly supported
Heavily relies on PostgreSQL features
Does not provide any syntax extensions
Data manipulation is implemented with user-defined functions
Detailed refinement of data manipulation semantics
Integrity cnstraints

<!-- Slide number: 17 -->
# Data Manipulation
The refinements of manipulation semantics are here
INSERT
UPDATE
CORRECTION
DEACTIVATE
DELETE

<!-- Slide number: 18 -->
# StoragStorage and Indexes

<!-- Slide number: 19 -->
# Queries
Time-related conditions must be explicitly specified
Built-in predicates are helpful
Fully temporal queries are still trichy

<!-- Slide number: 20 -->
# Bi-Temporal vs. SQL Standard
Probably a table is needed here

<!-- Slide number: 21 -->
# What is Still Missing?

<!-- Slide number: 22 -->
# What is missing in th e Standard

<!-- Slide number: 23 -->
# What is missing in PostgreSQL
Of course, bi-temporal

<!-- Slide number: 24 -->
# What is Missing in Bitemporal
Syntax extensions
Design methodologies (also missing in the Standard)
Explicit support for transactional time dimension, although transactional dimension is not really needed

<!-- Slide number: 25 -->
# Conclusions

<!-- Slide number: 26 -->
# Past, Present, and Future
Of Temporal Databases
The SQL Standard provides very reasonable conservative support
PostgreSQL contains everything that is needed for efficient implementation but not an implementation
Bitemporal is not too far from the Standard
