import re
import os

def replace_query_calls(content):
    """Replace SQLAlchemy query calls with Firestore methods."""

    # Pattern 1: Model.query.filter_by(user_id=..., metric_type=...).order_by(...).first()
    # -> Model.get_by_field(field, value). But since we need multiple filters, we need get_all with filters
    # For .first(), we can use get_all with limit=1

    # Pattern: Model.query.filter_by(field1=val1, field2=val2).order_by(...).first()
    content = re.sub(
        r'(\w+)\.query\.filter_by\(([^)]+)\)\.order_by\([^)]*\)\.first\(\)',
        lambda m: f"{m.group(1)}.get_all(filters={parse_filters(m.group(2))}, limit=1)[0] if {m.group(1)}.get_all(filters={parse_filters(m.group(2))}, limit=1) else None",
        content
    )

    # Pattern: Model.query.filter_by(field1=val1, field2=val2).order_by(...).limit(N).all()
    content = re.sub(
        r'(\w+)\.query\.filter_by\(([^)]+)\)\.order_by\([^)]*\)\.limit\((\d+)\)\.all\(\)',
        lambda m: f"{m.group(1)}.get_all(filters={parse_filters(m.group(2))}, limit={m.group(3)})",
        content
    )

    # Pattern: Model.query.filter_by(field1=val1, field2=val2).all()
    content = re.sub(
        r'(\w+)\.query\.filter_by\(([^)]+)\)\.all\(\)',
        lambda m: f"{m.group(1)}.get_all(filters={parse_filters(m.group(2))})",
        content
    )

    # Pattern: Model.query.filter_by(field1=val1, field2=val2).first()
    content = re.sub(
        r'(\w+)\.query\.filter_by\(([^)]+)\)\.first\(\)',
        lambda m: f"({m.group(1)}.get_all(filters={parse_filters(m.group(2))}, limit=1) or [None])[0]",
        content
    )

    # Pattern: Model.query.filter(Model.field == val, ...).first()
    content = re.sub(
        r'(\w+)\.query\.filter\([^)]*\)\.first\(\)',
        lambda m: f"({m.group(1)}.get_all(filters={extract_filters_from_filter(m.group(0))}, limit=1) or [None])[0]",
        content
    )

    # Pattern: Model.query.filter(...).all()
    content = re.sub(
        r'(\w+)\.query\.filter\(([^)]+)\)\.all\(\)',
        lambda m: f"{m.group(1)}.get_all(filters={extract_filters_from_filter(m.group(0))})",
        content
    )

    # Pattern: Model.query.filter(...).first()
    content = re.sub(
        r'(\w+)\.query\.filter\(([^)]+)\)\.first\(\)',
        lambda m: f"({m.group(1)}.get_all(filters={extract_filters_from_filter(m.group(0))}, limit=1) or [None])[0]",
        content
    )

    # Pattern: Model.query.filter(...).order_by(...).limit(N).all()
    content = re.sub(
        r'(\w+)\.query\.filter\([^)]+\)\.order_by\([^)]*\)\.limit\((\d+)\)\.all\(\)',
        lambda m: f"{m.group(1).split('.')[0]}.get_all(filters={extract_filters_from_filter(m.group(0))}, limit={m.group(1)})",
        content
    )

    # Pattern: Model.query.get_or_404(id)
    content = re.sub(
        r'(\w+)\.query\.get_or_404\(([^)]+)\)',
        r'\1.get_by_id_or_404(\2)',
        content
    )

    # Pattern: Model.query.get(id)
    content = re.sub(
        r'(\w+)\.query\.get\(([^)]+)\)',
        r'\1.get_by_id(\2)',
        content
    )

    # Pattern: Model.query.filter_by(...).first_or_404()
    content = re.sub(
        r'(\w+)\.query\.filter_by\(([^)]+)\)\.first_or_404\(\)',
        lambda m: f"{m.group(1)}.get_by_id_or_404({parse_filters(m.group(2)).get('id', 'id')})",
        content
    )

    # Pattern: Model.query.count()
    content = re.sub(
        r'(\w+)\.query\.count\(\)',
        r'\1.count()',
        content
    )

    # Pattern: Model.query.filter_by(...).count()
    content = re.sub(
        r'(\w+)\.query\.filter_by\(([^)]+)\)\.count\(\)',
        lambda m: f"{m.group(1)}.count(filters={parse_filters(m.group(2))})",
        content
    )

    # Pattern: Model.query.filter(...).count()
    content = re.sub(
        r'(\w+)\.query\.filter\([^)]+\)\.count\(\)',
        lambda m: f"{m.group(1)}.count(filters={extract_filters_from_filter(m.group(0))})",
        content
    )

    return content

def parse_filters(filter_str):
    """Parse filter_by arguments into a dict string."""
    # Simple parsing - this is a simplified version
    # filter_str looks like: 'user_id=user.id, metric_type="bp"'
    result = {}
    parts = filter_str.split(',')
    for part in parts:
        part = part.strip()
        if '=' in part:
            key, val = part.split('=', 1)
            key = key.strip()
            val = val.strip()
            result[key] = val
    return str(result).replace("'", '"')

def extract_filters_from_filter(filter_call):
    """Extract filter conditions from a filter() call."""
    # This is a simplified version
    return '{}'

# Test on a simple file first
with open('C:/health_app_main/routes/bp_routes.py', 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# First, just replace the obvious ones
# Model.query.count() -> Model.count()
content = re.sub(r'(\w+)\.query\.count\(\)', r'\1.count()', content)

# Model.query.get_or_404(id) -> Model.get_by_id_or_404(id)
content = re.sub(r'(\w+)\.query\.get_or_404\(([^)]+)\)', r'\1.get_by_id_or_404(\2)', content)

# Model.query.get(id) -> Model.get_by_id(id)
content = re.sub(r'(\w+)\.query\.get\(([^)]+)\)', r'\1.get_by_id(\2)', content)

# Save
with open('C:/health_app_main/routes/bp_routes.py', 'w', encoding='utf-8') as f:
    f.write(content)

print("Done with basic replacements")