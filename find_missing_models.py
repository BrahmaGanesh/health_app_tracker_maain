# find_missing_models.py
import ast
import os
from pathlib import Path

ROOT = Path(__file__).parent
ROUTE_DIR = ROOT / "routes"

existing_models = set()

models_path = ROOT / "models.py"
tree = ast.parse(models_path.read_text(encoding="utf-8"))

for node in tree.body:
    if isinstance(node, ast.ClassDef):
        existing_models.add(node.name)

imported_models = set()
import_locations = {}

for path in ROUTE_DIR.rglob("*.py"):
    source = path.read_text(encoding="utf-8", errors="ignore")
    tree = ast.parse(source)

    for node in ast.walk(tree):
        if (
            isinstance(node, ast.ImportFrom)
            and node.module == "models"
        ):
            for alias in node.names:
                name = alias.name
                imported_models.add(name)
                import_locations.setdefault(name, []).append(
                    str(path.relative_to(ROOT))
                )

missing = sorted(imported_models - existing_models)

print("Models already defined in models.py:")
print("\n".join(sorted(existing_models)))

print("\nModels imported by routes:")
print("\n".join(sorted(imported_models)))

print("\nMISSING MODELS:")
if missing:
    print("\n".join(missing))
    print("\nUsed in:")
    for name in missing:
        print(f"{name}:")
        for location in import_locations[name]:
            print(f"  - {location}")
else:
    print("None. All imported model names exist.")