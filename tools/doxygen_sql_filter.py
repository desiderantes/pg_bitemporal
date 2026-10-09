#!/usr/bin/env python3
"""
doxygen_sql_filter.py - Doxygen Input Filter for PostgreSQL PL/pgSQL Files

Transforms PostgreSQL SQL and PL/pgSQL function declarations into C-compatible
prototypes so Doxygen (using `EXTENSION_MAPPING = sql=C`) can parse and generate
documentation without syntax errors caused by PL/pgSQL procedure bodies.

Usage in Doxyfile:
    EXTENSION_MAPPING = sql=C
    FILTER_PATTERNS   = *.sql="python3 /path/to/tools/doxygen_sql_filter.py"
"""

import re
import sys
import sqlparse
from sqlparse.sql import Comment

# Regex matching PL/pgSQL function headers, including schema-qualified names and types.
# Captures: Group 1 = function_name, Group 2 = raw_parameters, Group 3 = return_type
FUNCTION_PATTERN = re.compile(
    r'(?:CREATE\s+OR\s+REPLACE\s+)?FUNCTION\s+([a-zA-Z0-9_.]+)\s*\((.*?)\)\s*RETURNS\s+([a-zA-Z0-9_.]+)',
    re.IGNORECASE | re.DOTALL
)


def convert_pgsql_params_to_c(raw_params: str) -> str:
    """
    Convert PL/pgSQL parameter definitions ('name type') into C parameter definitions ('type name').

    PL/pgSQL parameter lists frequently contain inline SQL comments (e.g. `p_search_fields TEXT -- search fields`).
    We strip inline comments `-- ...` and `/* ... */` upfront so they do not bleed into C type definitions
    and cause Doxygen to fail matching function prototypes against `@param` docstrings.

    Parameter data types in PL/pgSQL may be schema-qualified (e.g., `temporal_relationships.timeperiod`).
    We preserve full package/domain type strings for accurate C prototype signatures.
    """
    if not raw_params.strip():
        return ''

    # Strip inline single-line '-- ...' and multi-line '/* ... */' comments from parameter list
    clean_params = re.sub(r'--[^\n]*', '', raw_params)
    clean_params = re.sub(r'/\*.*?\*/', '', clean_params, flags=re.DOTALL)

    c_params = []
    for p in clean_params.split(','):
        parts = p.strip().split()
        if len(parts) >= 2:
            p_name = parts[0]
            p_type = ' '.join(parts[1:])
            c_params.append(f'{p_type} {p_name}')
        elif len(parts) == 1:
            c_params.append(parts[0])

    return ', '.join(c_params)


def filter_sql_content(content: str) -> str:
    """
    Parse SQL content and convert PL/pgSQL function declarations to C header prototypes.

    AST Parsing over Regex:
    Naive regex matching for SQL function blocks fails on multiline procedure bodies
    containing dollar-quoted strings ($BODY$, $$) or embedded semicolons. We use `sqlparse`
    to reliably tokenize SQL into AST statement nodes, guaranteeing that comments
    belonging to each function are associated correctly without comment-bleeding.

    Header Docs vs Function Docstrings:
    Doxygen header comments (@file, @defgroup, @addtogroup) can appear in standalone non-function
    statements (like CREATE SCHEMA or DO blocks). We collect standalone comments from non-function
    statements upfront so Doxygen registers module groups first. For comments attached directly
    to CREATE FUNCTION statements, we strip any inline `@file` line and attach the Javadoc block
    exclusively to the generated C function prototype.
    """
    statements = sqlparse.parse(content)

    header_docs = []
    func_entries = []

    for stmt in statements:
        comment_text = ''
        for token in stmt.tokens:
            if isinstance(token, Comment):
                comment_text = str(token).strip()

        stmt_str = str(stmt)
        match = FUNCTION_PATTERN.search(stmt_str)

        if match:
            raw_func_name, raw_params, ret_type = match.groups()

            # Tricky Detail 5 (Schema Qualifier Stripping):
            # PostgreSQL function names may be schema-qualified (e.g. `bitemporal_internal.ll_bitemporal_insert`).
            # C function identifiers cannot contain dots ('.'). We extract the function basename so Doxygen
            # recognizes valid C function prototypes and correctly binds them to their docstrings.
            func_name = raw_func_name.split('.')[-1]
            c_params = convert_pgsql_params_to_c(raw_params)

            if comment_text:
                file_match = re.search(r'@file\s+([^\s]+)', comment_text)
                if file_match:
                    filename = file_match.group(1)
                    if not any(filename in h for h in header_docs):
                        header_docs.append(f'/** @file {filename}\n */')

                # Strip @file lines from function-level docstrings to prevent Doxygen from treating
                # function docstrings as file-level overviews.
                lines = [line for line in comment_text.splitlines() if not re.search(r'@file\b', line)]
                comment_text = '\n'.join(lines)

            func_entries.append((comment_text, ret_type, func_name, c_params))
        else:
            # Non-function statement: collect standalone header doc blocks if present
            if comment_text and any(tag in comment_text for tag in ('@file', '@defgroup', '@addtogroup')):
                header_docs.append(comment_text)

    # Build output buffer
    output = ['// Filtered C header generated for Doxygen using sqlparse\n']

    for hdoc in header_docs:
        output.append(hdoc + '\n\n')

    for comment_text, ret_type, func_name, c_params in func_entries:
        if comment_text:
            output.append(comment_text + '\n')
        output.append(f'{ret_type} {func_name}({c_params});\n\n')

    return ''.join(output)


def filter_sql_file(filename: str) -> str:
    """Read a SQL file and return its filtered C-header representation."""
    with open(filename, 'r', encoding='utf-8') as f:
        return filter_sql_content(f.read())


def main():
    if len(sys.argv) > 1:
        sys.stdout.write(filter_sql_file(sys.argv[1]))
    else:
        # Support reading from stdin if invoked without CLI arguments
        sys.stdout.write(filter_sql_content(sys.stdin.read()))


if __name__ == '__main__':
    main()
