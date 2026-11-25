# ── EXTENSIONS ───────────────────────────────────────────────
# extensions.py
from flask_bcrypt import Bcrypt
from flask_login import LoginManager
from flask_migrate import Migrate
from flask_mail import Mail
from flask_caching import Cache
from flask_wtf.csrf import CSRFProtect
from flask_cors import CORS
from flask_jwt_extended import JWTManager

bcrypt   = Bcrypt()
login_manager = LoginManager()
migrate  = Migrate()
mail     = Mail()
cache    = Cache()
cors     = CORS()
csrf     = CSRFProtect()
jwt      = JWTManager()

# Mock db object for compatibility with routes that still reference db.session
# This prevents import errors while the migration progresses
class MockDB:
    """Mock SQLAlchemy db object for compatibility."""
    session = type('Session', (), {
        'commit': lambda: None,
        'rollback': lambda: None,
        'add': lambda x: None,
        'delete': lambda x: None,
        'query': lambda: type('Query', (), {
            'filter': lambda *a, **kw: type('Filter', (), {
                'first': lambda: None,
                'all': lambda: [],
                'first_or_404': lambda: None,
                'paginate': lambda *a, **kw: type('Pagination', (), {
                    'items': [],
                    'page': 1,
                    'total': 0,
                    'pages': 1
                })()
            })()
        })()
    })()

    # Mock Model class for SQLAlchemy model inheritance
    class Model:
        """Mock SQLAlchemy Model base class."""
        pass

    # Mock column types
    Column = lambda *args, **kwargs: None
    Integer = type('Integer', (), {})
    String = lambda *args, **kwargs: type('String', (), {})
    Text = lambda *args, **kwargs: type('Text', (), {})
    DateTime = lambda *args, **kwargs: type('DateTime', (), {})
    Date = lambda *args, **kwargs: type('Date', (), {})
    Float = lambda *args, **kwargs: type('Float', (), {})
    Boolean = lambda *args, **kwargs: type('Boolean', (), {})
    ForeignKey = lambda *args, **kwargs: None
    UniqueConstraint = lambda *args, **kwargs: None

    # Mock relationship
    relationship = lambda *args, **kwargs: None

db = MockDB()