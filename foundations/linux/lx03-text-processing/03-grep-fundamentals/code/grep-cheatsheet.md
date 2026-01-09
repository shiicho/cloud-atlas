# grep Quick Reference Cheatsheet

## Basic Syntax

```bash
grep [options] 'pattern' file(s)
```

## Essential Options

| Option | Description | Example |
|--------|-------------|---------|
| `-i` | Case insensitive | `grep -i 'error' log.txt` |
| `-v` | Invert match (exclude) | `grep -v 'INFO' log.txt` |
| `-n` | Show line numbers | `grep -n 'ERROR' log.txt` |
| `-c` | Count matches | `grep -c 'ERROR' log.txt` |
| `-l` | List matching files only | `grep -l 'ERROR' *.log` |
| `-L` | List non-matching files | `grep -L 'ERROR' *.log` |
| `-r` | Recursive search | `grep -r 'ERROR' /var/log/` |
| `-w` | Whole word match | `grep -w 'error' log.txt` |
| `-F` | Fixed string (no regex) | `grep -F '[error]' log.txt` |
| `-q` | Quiet (exit code only) | `grep -q 'ERROR' log.txt` |

## Context Options

| Option | Description | Example |
|--------|-------------|---------|
| `-A n` | Show n lines After | `grep -A 3 'ERROR' log.txt` |
| `-B n` | Show n lines Before | `grep -B 3 'ERROR' log.txt` |
| `-C n` | Show n lines Context | `grep -C 3 'ERROR' log.txt` |

## Multiple Patterns

```bash
# Using -e for multiple patterns
grep -e 'ERROR' -e 'WARN' log.txt

# Using -E with alternation
grep -E 'ERROR|WARN' log.txt

# Using pattern file
grep -f patterns.txt log.txt
```

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Match found |
| `1` | No match found |
| `2` | Error occurred |

## Common Patterns

```bash
# Find all errors (case insensitive)
grep -i 'error' /var/log/*.log

# Count errors per file
grep -c 'ERROR' *.log

# Show errors with context
grep -C 5 'ERROR' app.log

# Find files containing pattern
grep -rl 'pattern' /var/log/

# Exclude directories
grep -r --exclude-dir='.git' 'pattern' .

# Search specific file types
grep -r --include='*.log' 'ERROR' /var/log/
```

## ripgrep (rg) Equivalents

| grep | rg |
|------|-----|
| `grep -r 'pattern' .` | `rg 'pattern'` |
| `grep -i 'pattern'` | `rg -i 'pattern'` |
| `grep -l 'pattern' *` | `rg -l 'pattern'` |
| `grep -r --include='*.py'` | `rg -t py 'pattern'` |
| `grep -v 'pattern'` | `rg -v 'pattern'` |
