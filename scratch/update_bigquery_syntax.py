import urllib.request
import json
import os
import re

# Destination path for the output JSON asset
DEST_PATH = "/home/ejangi/Sites/pocket-query/assets/metadata/bigquery_syntax.json"

# Extensive fallback lists in case scraping is blocked or offline
FALLBACK_KEYWORDS = [
    "SELECT", "FROM", "WHERE", "GROUP BY", "HAVING", "ORDER BY", "LIMIT",
    "ASC", "DESC",
    "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN", "IS NULL", "IS TRUE", "IS FALSE",
    "AS", "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "FULL JOIN", "CROSS JOIN",
    "ON", "USING", "UNION ALL", "UNION DISTINCT", "INTERSECT DISTINCT", "EXCEPT DISTINCT",
    "WITH", "CREATE", "REPLACE", "TABLE", "VIEW", "FUNCTION", "INSERT", "UPDATE",
    "DELETE", "MERGE", "CASE", "WHEN", "THEN", "ELSE", "END", "CAST", "SAFE_CAST",
    "OVER", "PARTITION BY", "ROWS BETWEEN", "UNBOUNDED PRECEDING", "UNBOUNDED FOLLOWING",
    "CURRENT ROW", "TRUE", "FALSE", "NULL", "UNNEST", "WINDOW", "QUALIFY", "SYSTEM_TIME",
    "FOR", "ALL", "ANY", "SOME", "EXISTS", "INTO", "VALUES", "SET", "DEFAULT"
]

FALLBACK_TYPES = [
    "INT64", "NUMERIC", "BIGNUMERIC", "FLOAT64", "BOOLEAN", "STRING", "BYTES",
    "DATE", "DATETIME", "TIME", "TIMESTAMP", "GEOGRAPHY", "JSON", "STRUCT",
    "ARRAY", "INTERVAL"
]

FALLBACK_FUNCTIONS = [
    # String
    "CONCAT", "SUBSTR", "LENGTH", "LOWER", "UPPER", "TRIM", "LTRIM", "RTRIM",
    "REPLACE", "REGEXP_CONTAINS", "REGEXP_EXTRACT", "REGEXP_REPLACE", "SPLIT",
    "FORMAT", "SAFE_CONVERT_BYTES_TO_STRING", "STARTS_WITH", "ENDS_WITH",
    "LPAD", "RPAD", "INSTR",
    # Math
    "ABS", "ACOS", "ASIN", "ATAN", "CEIL", "CEILING", "COS", "COSH", "EXP",
    "FLOOR", "LN", "LOG", "LOG10", "MOD", "POW", "POWER", "ROUND", "SAFE_ADD",
    "SAFE_DIVIDE", "SAFE_MULTIPLY", "SAFE_SUBTRACT", "SIGN", "SIN", "SINH",
    "SQRT", "TAN", "TANH", "TRUNC",
    # Date/Time
    "CURRENT_DATE", "CURRENT_DATETIME", "CURRENT_TIME", "CURRENT_TIMESTAMP",
    "DATE_ADD", "DATE_SUB", "DATE_DIFF", "DATE_TRUNC", "DATETIME_ADD", "DATETIME_SUB",
    "DATETIME_DIFF", "DATETIME_TRUNC", "EXTRACT", "FORMAT_DATE", "FORMAT_DATETIME",
    "FORMAT_TIME", "FORMAT_TIMESTAMP", "PARSE_DATE", "PARSE_DATETIME", "PARSE_TIME",
    "PARSE_TIMESTAMP", "TIMESTAMP_ADD", "TIMESTAMP_SUB", "TIMESTAMP_DIFF",
    "TIMESTAMP_TRUNC", "LAST_DAY",
    # Aggregate
    "ARRAY_AGG", "ARRAY_CONCAT_AGG", "AVG", "BIT_AND", "BIT_OR", "BIT_XOR",
    "COUNT", "COUNTIF", "LOGICAL_AND", "LOGICAL_OR", "MAX", "MIN", "STRING_AGG", "SUM",
    # Analytic/Window
    "ROW_NUMBER", "RANK", "DENSE_RANK", "PERCENT_RANK", "CUME_DIST", "NTILE",
    "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE", "NTH_VALUE",
    # JSON
    "JSON_QUERY", "JSON_VALUE", "JSON_QUERY_ARRAY", "JSON_VALUE_ARRAY", "PARSE_JSON",
    "TO_JSON_STRING",
    # Array
    "ARRAY_CONCAT", "ARRAY_LENGTH", "ARRAY_TO_STRING", "GENERATE_ARRAY",
    "GENERATE_DATE_ARRAY", "GENERATE_TIMESTAMP_ARRAY", "OFFSET", "ORDINAL",
    "SAFE_OFFSET", "SAFE_ORDINAL"
]

def fetch_gcp_docs():
    headers = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    
    keywords = set(FALLBACK_KEYWORDS)
    types = set(FALLBACK_TYPES)
    functions = set(FALLBACK_FUNCTIONS)
    
    # 1. Scrape keywords from GoogleSQL lexical reference
    try:
        print("Fetching GoogleSQL keywords from GCP docs...")
        req = urllib.request.Request("https://cloud.google.com/bigquery/docs/reference/standard-sql/lexical", headers=headers)
        with urllib.request.urlopen(req, timeout=10) as response:
            html = response.read().decode('utf-8')
            # Extract code elements containing uppercase words inside potential tables/lists
            words = re.findall(r'<code>([A-Z_]{2,})<\/code>', html)
            for w in words:
                if w not in FALLBACK_TYPES and w not in FALLBACK_FUNCTIONS:
                    keywords.add(w)
            print(f"Loaded {len(keywords)} keywords.")
    except Exception as e:
        print(f"Could not scrape keywords, using fallback. Details: {e}")

    # 2. Scrape functions from GoogleSQL functions & operators index
    try:
        print("Fetching GoogleSQL functions from GCP docs...")
        req = urllib.request.Request("https://cloud.google.com/bigquery/docs/reference/standard-sql/functions-and-operators", headers=headers)
        with urllib.request.urlopen(req, timeout=10) as response:
            html = response.read().decode('utf-8')
            # Scrape uppercase function names from table cells or anchors
            funcs = re.findall(r'<code>([A-Z_]{2,})\(.*?\)<\/code>', html)
            for f in funcs:
                functions.add(f)
            print(f"Loaded {len(functions)} functions.")
    except Exception as e:
        print(f"Could not scrape functions, using fallback. Details: {e}")

    return {
        "keywords": sorted(list(keywords)),
        "types": sorted(list(types)),
        "functions": sorted(list(functions))
    }

def main():
    print("Starting BigQuery SQL Syntax Spec generation...")
    data = fetch_gcp_docs()
    
    # Ensure destination folder exists
    os.makedirs(os.path.dirname(DEST_PATH), exist_ok=True)
    
    with open(DEST_PATH, 'w') as f:
        json.dump(data, f, indent=2)
    
    print(f"Successfully generated BigQuery syntax spec file at: {DEST_PATH}")
    print(f"  Keywords count: {len(data['keywords'])}")
    print(f"  Types count: {len(data['types'])}")
    print(f"  Functions count: {len(data['functions'])}")

if __name__ == "__main__":
    main()
