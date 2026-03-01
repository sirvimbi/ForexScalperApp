print("Testing imports...")
try:
    import sklearn
    print(f"✅ scikit-learn {sklearn.__version__}")
except ImportError as e:
    print(f"❌ scikit-learn: {e}")

try:
    import pandas as pd
    print(f"✅ pandas {pd.__version__}")
except ImportError as e:
    print(f"❌ pandas: {e}")

try:
    import numpy as np
    print(f"✅ numpy {np.__version__}")
except ImportError as e:
    print(f"❌ numpy: {e}")

try:
    import coremltools as ct
    print(f"✅ coremltools {ct.__version__}")
except ImportError as e:
    print(f"❌ coremltools: {e}")

try:
    import ccxt
    print(f"✅ ccxt {ccxt.__version__}")
except ImportError as e:
    print(f"❌ ccxt: {e}")
