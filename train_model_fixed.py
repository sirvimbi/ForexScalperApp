import pandas as pd
import numpy as np
import sklearn  # Add this import
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
import coremltools as ct
import ccxt
from datetime import datetime, timedelta
import os

print(f"scikit-learn version: {sklearn.__version__}")
print(f"coremltools version: {ct.__version__}")

# Check if scikit-learn version is compatible
if sklearn.__version__ > '1.5.1':
    print(f"⚠️ Warning: scikit-learn {sklearn.__version__} may not be fully compatible with coremltools")
    print("Consider downgrading to 1.2.2 for better compatibility:")
    print("pip install scikit-learn==1.2.2")

print("📊 Fetching historical crypto data from Binance...")

exchange = ccxt.binance({
    'enableRateLimit': True,
    'options': {
        'defaultType': 'spot'
    }
})

# Use crypto pairs that actually exist on Binance
symbols = [
    'BTC/USDT', 'ETH/USDT', 'BNB/USDT', 'ADA/USDT', 'DOGE/USDT',
    'XRP/USDT', 'DOT/USDT', 'UNI/USDT', 'LTC/USDT', 'LINK/USDT',
    'BCH/USDT', 'XLM/USDT', 'SOL/USDT', 'MATIC/USDT', 'ETC/USDT',
    'TRX/USDT', 'VET/USDT', 'EOS/USDT', 'OMG/USDT', 'NEO/USDT'
]

# Convert to Binance format (remove slash)
binance_symbols = [s.replace('/', '') for s in symbols]

def calculate_features(df):
    """Calculate technical indicators for ML features"""
    # Price features
    df['returns'] = df['close'].pct_change()
    df['high_low_pct'] = (df['high'] - df['low']) / df['close']
    df['close_open_pct'] = (df['close'] - df['open']) / df['open']
    
    # Moving averages
    df['sma_10'] = df['close'].rolling(10).mean()
    df['sma_20'] = df['close'].rolling(20).mean()
    df['sma_50'] = df['close'].rolling(50).mean()
    df['ema_12'] = df['close'].ewm(span=12, adjust=False).mean()
    df['ema_26'] = df['close'].ewm(span=26, adjust=False).mean()
    
    # RSI
    delta = df['close'].diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
    # Avoid division by zero
    rs = gain / loss.replace(0, np.nan)
    df['rsi'] = 100 - (100 / (1 + rs))
    df['rsi'] = df['rsi'].fillna(50)  # Fill NaN with neutral RSI
    
    # MACD
    df['macd'] = df['ema_12'] - df['ema_26']
    df['macd_signal'] = df['macd'].ewm(span=9, adjust=False).mean()
    df['macd_hist'] = df['macd'] - df['macd_signal']
    
    # Bollinger Bands
    df['bb_middle'] = df['close'].rolling(20).mean()
    bb_std = df['close'].rolling(20).std()
    df['bb_upper'] = df['bb_middle'] + (bb_std * 2)
    df['bb_lower'] = df['bb_middle'] - (bb_std * 2)
    # Avoid division by zero
    bb_range = (df['bb_upper'] - df['bb_lower']).replace(0, np.nan)
    df['bb_width'] = bb_range / df['bb_middle']
    df['bb_position'] = (df['close'] - df['bb_lower']) / bb_range
    df['bb_position'] = df['bb_position'].fillna(0.5)  # Fill NaN with middle position
    
    # ATR
    df['atr'] = (df['high'] - df['low']).rolling(14).mean()
    df['atr_pct'] = df['atr'] / df['close'].replace(0, np.nan)
    df['atr_pct'] = df['atr_pct'].fillna(0.01)  # Fill NaN with small default
    
    # Volume
    df['volume_sma'] = df['volume'].rolling(20).mean()
    df['volume_ratio'] = df['volume'] / df['volume_sma'].replace(0, np.nan)
    df['volume_ratio'] = df['volume_ratio'].fillna(1.0)  # Fill NaN with 1
    
    return df

def create_labels(df, future_periods=5, profit_threshold=0.005):  # 0.5% profit target for crypto
    """Create labels: 1 for profitable long, -1 for profitable short, 0 for no trade"""
    future_returns = df['close'].shift(-future_periods) / df['close'] - 1
    df['label'] = 0
    df.loc[future_returns > profit_threshold, 'label'] = 1  # Buy signal
    df.loc[future_returns < -profit_threshold, 'label'] = -1  # Sell signal
    return df

# Collect data for all symbols
all_features = []
all_labels = []

for symbol in binance_symbols:
    print(f"📥 Fetching {symbol}...")
    try:
        # Get 6 months of 1-hour data (to avoid rate limits)
        since = exchange.parse8601((datetime.now() - timedelta(days=180)).isoformat())
        ohlcv = exchange.fetch_ohlcv(symbol, '1h', since=since, limit=1000)
        
        if len(ohlcv) == 0:
            print(f"⚠️ No data for {symbol}")
            continue
            
        df = pd.DataFrame(ohlcv, columns=['timestamp', 'open', 'high', 'low', 'close', 'volume'])
        df = calculate_features(df)
        df = create_labels(df)
        
        # Remove NaN rows
        df = df.dropna()
        
        if len(df) > 100:
            features = df[['returns', 'high_low_pct', 'close_open_pct', 'sma_10', 'sma_20', 
                          'sma_50', 'ema_12', 'ema_26', 'rsi', 'macd', 'macd_signal', 
                          'macd_hist', 'bb_width', 'bb_position', 'atr_pct', 'volume_ratio']].values
            labels = df['label'].values
            
            all_features.extend(features)
            all_labels.extend(labels)
            print(f"✅ Added {len(df)} samples from {symbol}")
    except Exception as e:
        print(f"⚠️ Error with {symbol}: {e}")

# Convert to numpy arrays
if len(all_features) == 0:
    print("❌ No data collected! Using synthetic data instead...")
    # Generate synthetic data
    np.random.seed(42)
    n_samples = 1000
    all_features = np.random.randn(n_samples, 16)
    all_labels = np.random.choice([-1, 0, 1], n_samples, p=[0.2, 0.6, 0.2])
    print(f"✅ Generated {n_samples} synthetic samples")

X = np.array(all_features)
y = np.array(all_labels)

print(f"\n📊 Total samples: {len(X)}")
print(f"Buy signals: {np.sum(y == 1)}")
print(f"Sell signals: {np.sum(y == -1)}")
print(f"No trade: {np.sum(y == 0)}")

# Train model
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

model = RandomForestClassifier(n_estimators=100, max_depth=10, random_state=42)
model.fit(X_train, y_train)

# Evaluate
accuracy = model.score(X_test, y_test)
print(f"\n🎯 Model accuracy: {accuracy:.2%}")

# Convert to Core ML
feature_names = ['returns', 'high_low_pct', 'close_open_pct', 'sma_10', 'sma_20', 
                 'sma_50', 'ema_12', 'ema_26', 'rsi', 'macd', 'macd_signal', 
                 'macd_hist', 'bb_width', 'bb_position', 'atr_pct', 'volume_ratio']

# Try to convert to Core ML
try:
    # For coremltools
    coreml_model = ct.converters.sklearn.convert(model, feature_names, 'target')
    
    # Add metadata
    coreml_model.author = 'CryptoScalper'
    coreml_model.short_description = 'Predicts buy/sell signals for crypto trading'
    coreml_model.version = '1.0'
    coreml_model.license = 'For educational purposes'
    
    # Save model
    coreml_model.save('TradingModel.mlmodel')
    print("✅ Model saved as TradingModel.mlmodel")
except Exception as e:
    print(f"⚠️ Core ML conversion failed: {e}")
    print("Saving model using joblib instead...")
    import joblib
    joblib.dump(model, 'TradingModel.joblib')
    print("✅ Model saved as TradingModel.joblib")

# Feature importance
importance = pd.DataFrame({'feature': feature_names, 'importance': model.feature_importances_})
importance = importance.sort_values('importance', ascending=False)
print("\n📈 Top 10 most important features:")
print(importance.head(10))

print("\n🎉 Model creation complete!")
print("📍 File location: " + os.path.abspath('TradingModel.mlmodel'))
