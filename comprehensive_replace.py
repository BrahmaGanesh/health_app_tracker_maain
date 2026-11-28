import re
import os

def comprehensive_replace(content):
    """Replace all SQLAlchemy query patterns with Firestore methods."""

    # 1. Replace Model.query.count() -> Model.count()
    content = re.sub(r'(\w+)\.query\.count\(\)', r'\1.count()', content)

    # 2. Replace Model.query.filter_by(...).count() -> Model.count(filters=...)
    def replace_filter_by_count(match):
        model = match.group(1)
        filters = match.group(2).strip()
        # Parse filter_by arguments
        filter_dict = {}
        parts = filters.split(',')
        for part in parts:
            part = part.strip()
            if '=' in part:
                key, val = part.split('=', 1)
                key = key.strip()
                val = val.strip()
                if val.startswith('"') and val.endswith('"'):
                    val = val[1:-1]
                elif val.startswith("'") and val.endswith("'"):
                    val = val[1:-1]
                filter_dict[key] = val
        return f"{model}.count(filters={str(filter_dict)})"

    content = re.sub(r'(\w+)\.query\.filter_by\(([^)]+)\)\.count\(\)', replace_filter_by_count, content)

    # 3. Model.query.get_or_404(id) -> Model.get_by_id_or_404(id)
    content = re.sub(r'(\w+)\.query\.get_or_404\(([^)]+)\)', r'\1.get_by_id_or_404(\2)', content)

    # 4. Model.query.get(id) -> Model.get_by_id(id)
    content = re.sub(r'(\w+)\.query\.get\(([^)]+)\)', r'\1.get_by_id(\2)', content)

    # 5. Model.query.filter_by(...).first() -> (Model.get_all(filters=..., limit=1) or [None])[0]
    def replace_filter_by_first(match):
        model = match.group(1)
        filters = match.group(2).strip()
        # Build filter dict
        filter_dict = {}
        parts = filters.split(',')
        for part in parts:
            part = part.strip()
            if '=' in part:
                key, val = part.split('=', 1)
                key = key.strip()
                val = val.strip()
                if val.startswith('"') and val.endswith('"'):
                    val = val[1:-1]
                elif val.startswith("'") and val.endswith("'"):
                    val = val[1:-1]
                filter_dict[key] = val
        filter_str = str(filter_dict).replace("'", '"')
        return f"({model}.get_all(filters={str(filter_dict)}, limit=1) or [None])[0]"

    content = re.sub(r'(\w+)\.query\.filter_by\(([^)]+)\)\.first\(\)', replace_filter_by_first, content)

    # 6. Model.query.filter_by(...).first_or_404() -> similar
    content = re.sub(r'(\w+)\.query\.filter_by\(([^)]+)\)\.first_or_404\(\)',
                     lambda m: f"({m.group(1)}.get_all(filters={str({k.strip(): v.strip().strip('\"') for k,v in [p.split('=',1) for p in m.group(2).split(',')])}, limit=1) or [None])[0]", content)

    # 7. Model.query.filter_by(...).all() -> Model.get_all(filters=...)
    def replace_filter_by_all(match):
        model = match.group(1)
        filters = match.group(2).strip()
        filter_dict = {}
        parts = filters.split(',')
        for part in parts:
            part = part.strip()
            if '=' in part:
                key, val = part.split('=', 1)
                key = key.strip()
                val = val.strip()
                if val.startswith('"') and val.endswith('"'):
                    val = val[1:-1]
                elif val.startswith("'") and val.endswith("'"):
                    val = val[1:-1]
                filter_dict[key] = val
        return f"{model}.get_all(filters={str(filter_dict)})"

    content = re.sub(r'(\w+)\.query\.filter_by\(([^)]+)\)\.all\(\)', replace_filter_by_all, content)

    # 8. Model.query.filter_by(...).order_by(...).limit(N).all()
    def replace_filter_by_order_limit_all(match):
        model = match.group(1)
        filters = match.group(2).strip()
        limit = match.group(3)
        filter_dict = {}
        parts = filters.split(',')
        for part in parts:
            part = part.strip()
            if '=' in part:
                key, val = part.split('=', 1)
                key = key.strip()
                val = val.strip()
                if val.startswith('"') and val.endswith('"'):
                    val = val[1:-1]
                elif val.startswith("'") and val.endswith("'"):
                    val = val[1:-1]
                filter_dict[key] = val
        return f"{model}.get_all(filters={str(filter_dict)}, limit={match.group(3)})"

    content = re.sub(r'(\w+)\.query\.filter_by\(([^)]+)\)\.order_by\([^)]*\)\.limit\((\d+)\)\.all\(\)',
                     replace_filter_by_order_limit_all, content)

    # 9. Model.query.filter_by(...).order_by(...).first()
    def replace_filter_by_order_first(match):
        model = match.group(1)
        filters = match.group(2).strip()
        filter_dict = {}
        parts = filters.split(',')
        for part in parts:
            part = part.strip()
            if '=' in part:
                key, val = part.split('=', 1)
                key = key.strip()
                val = val.strip()
                if val.startswith('"') and val.endswith('"'):
                    val = val[1:-1]
                elif val.startswith("'") and val.endswith("'"):
                    val = val[1:-1]
                filter_dict[key] = val
        return f"({model}.get_all(filters={str(filter_dict)}, limit=1) or [None])[0]"

    content = re.sub(r'(\w+)\.query\.filter_by\(([^)]+)\)\.order_by\([^)]*\)\.first\(\)',
                     replace_filter_by_order_first, content)

    # 10. Model.query.filter(...).all() - complex filters
    # This is harder to parse automatically, let's just note it

    # 11. Model.query.filter(...).first() - complex filters

    # 12. Model.query.filter(...).order_by(...).limit(N).all()

    # 13. Model.query.filter(...).order_by(...).first()

    # 13. Model.query.filter(...).order_by(...).limit(N).all()

    # 14. Delete calls
    content = re.sub(r'db\.session\.delete\((\w+)\)', r'\1.delete()', content)
    content = re.sub(r'db\.session\.add\((\w+)\)', r'\1.save()', content)
    content = re.sub(r'db\.session\.commit\(\)', r'# db.session.commit()  # Firestore auto-commits', content)
    content = re.sub(r'db\.session\.add\((\w+)\)', r'\1.save()', content)

    return content

# Read the file
filepath = 'C:/health_app_main/routes/bp_routes.py'
with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Apply comprehensive replacements
content = comprehensive_replace(content)

# Save
with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

print("Done with comprehensive replacements")