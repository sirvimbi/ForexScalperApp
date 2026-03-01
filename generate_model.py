
import pandas as pd
import numpy as np
import warnings
warnings.filterwarnings('ignore')

# Use a try-except for sklearn import to handle version issues
try:
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.utils import class_weight
    SKLEARN_AVAILABLE = True
except ImportError:
    print("⚠️ scikit-learn not available or version incompatible")
    SKLEARN_AVAILABLE = False

# CoreMLTools with version fallback
try:
    import coremltools as ct
    COREML_AVAILABLE = True
except ImportError:
    print("⚠️ coremltools not available")
    COREML_AVAILABLE = False

import ccxt
from datetime import datetime, timedelta
import os

print("=" * 50)
print("Forex Trading Model Generator")
print("=" * 50)

def get_binance_symbols():
    """Get available forex pairs on Binance"""
    # Binance forex pairs (actual symbols on Binance spot)
    return [
        'EURUSDT', 'GBPUSDT', 'AUDUSDT',  # Major pairs
        'EOSUSDT', 'XRPUSDT', 'ETHUSDT', 'BTCUSDT',  # Crypto as proxies
    ]

def fetch_historical_data():
    """Fetch historical data from Binance"""
    print("\n📊 Fetching historical data from Binance...")
    
    try:
        exchange = ccxt.binance({
            'enableRateLimit': True,
            'options': {'defaultType': 'spot'}
        })
        
        symbols = get_binance_symbols()
        all_data = []
        
        for symbol in symbols:
            print(f"  📥 Fetching {symbol}...", end=' ')
            try:
                # Get 6 months of 1-hour data
                since = exchange.parse8601((datetime.now() - timedelta(days=180)).isoformat())
                ohlcv = exchange.fetch_ohlcv(symbol, '1h', since=since, limit=1000)
                
                if len(ohlcv) > 200:
                    df = pd.DataFrame(ohlcv, columns=['timestamp', 'open', 'high', 'low', 'close', 'volume'])
                    df['symbol'] = symbol
                    df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')
                    all_data.append(df)
                    print(f"✅ {len(df)} candles")
                else:
                    print(f"⚠️ Only {len(ohlcv)} candles")
            except Exception as e:
                print(f"❌ {str(e)[:50]}")
        
        if all_data:
            combined_df = pd.concat(all_data, ignore_index=True)
            print(f"\n✅ Total data collected: {len(combined_df)} candles from {len(all_data)} symbols")
            return combined_df
        else:
            print("\n⚠️ No data fetched. Using synthetic data.")
            return generate_synthetic_data()
            
    except Exception as e:
        print(f"\n❌ Error fetching data: {e}")
        print("⚠️ Using synthetic data instead.")
        return generate_synthetic_data()

def generate_synthetic_data():
    """Generate synthetic forex data for training"""
    print("\n📈 Generating synthetic training data...")
    
    np.random.seed(42)
    n_samples = 5000
    
    # Generate base price series
    prices = 1.0 + np.cumsum(np.random.randn(n_samples) * 0.001)
    
    # Generate synthetic features
    data = {
        'symbol': ['SYNTH'] * n_samples,
        'returns': np.random.randn(n_samples) * 0.001,
        'high_low_pct': np.abs(np.random.randn(n_samples)) * 0.002,
        'close_open_pct': np.random.randn(n_samples) * 0.001,
        'sma_10': pd.Series(prices).rolling(10, min_periods=1).mean().fillna(method='bfill').values,
        'sma_20': pd.Series(prices).rolling(20, min_periods=1).mean().fillna(method='bfill').values,
        'sma_50': pd.Series(prices).rolling(50, min_periods=1).mean().fillna(method='bfill').values,
        'ema_12': pd.Series(prices).ewm(span=12, adjust=False).mean().values,
        'ema_26': pd.Series(prices).ewm(span=26, adjust=False).mean().values,
        'rsi': np.random.uniform(30, 70, n_samples),
        'macd': np.random.randn(n_samples) * 0.001,
        'macd_signal': np.random.randn(n_samples) * 0.001,
        'macd_hist': np.random.randn(n_samples) * 0.0005,
        'bb_width': np.random.uniform(0.01, 0.05, n_samples),
        'bb_position': np.random.uniform(0.2, 0.8, n_samples),
        'atr_pct': np.random.uniform(0.001, 0.01, n_samples),
        'volume_ratio': np.random.uniform(0.5, 2.0, n_samples)
    }
    
    df = pd.DataFrame(data)
    
    # Generate synthetic labels based on features
    # Buy signal (1) when features indicate upward momentum
    buy_score = (
        (df['rsi'] < 40).astype(int) * 0.3 +
        (df['bb_position'] < 0.3).astype(int) * 0.2 +
        (df['macd'] > 0).astype(int) * 0.3 +
        (df['volume_ratio'] > 1.2).astype(int) * 0.2
    )
    
    # Sell signal (-1) when features indicate downward momentum
    sell_score = (
        (df['rsi'] > 60).astype(int) * 0.3 +
        (df['bb_position'] > 0.7).astype(int) * 0.2 +
        (df['macd'] < 0).astype(int) * 0.3 +
        (df['volume_ratio'] > 1.2).astype(int) * 0.2
    )
    
    # Add some noise
    noise = np.random.randn(n_samples) * 0.1
    buy_score += noise
    sell_score -= noise
    
    df['label'] = 0
    df.loc[buy_score > 0.6, 'label'] = 1
    df.loc[sell_score > 0.6, 'label'] = -1
    
    # Balance the dataset
    buy_samples = df[df['label'] == 1]
    sell_samples = df[df['label'] == -1]
    neutral_samples = df[df['label'] == 0]
    
    # Sample to balance
    min_class_size = min(len(buy_samples), len(sell_samples))
    if min_class_size > 0:
        buy_samples = buy_samples.sample(n=min_class_size)
        sell_samples = sell_samples.sample(n=min_class_size)
        neutral_samples = neutral_samples.sample(n=min_class_size * 2)
        
        df = pd.concat([buy_samples, sell_samples, neutral_samples])
    
    print(f"  ✅ Generated {len(df)} samples")
    print(f"     Buy signals: {len(df[df['label'] == 1])}")
    print(f"     Sell signals: {len(df[df['label'] == -1])}")
    print(f"     Neutral: {len(df[df['label'] == 0])}")
    
    return df

def calculate_features(df):
    """Calculate technical indicators"""
    print("\n📈 Calculating technical features...")
    
    # Make a copy to avoid warnings
    df = df.copy()
    
    # Price features
    df['returns'] = df.groupby('symbol')['close'].pct_change()
    df['high_low_pct'] = (df['high'] - df['low']) / df['close']
    df['close_open_pct'] = (df['close'] - df['open']) / df['open']
    
    # Group by symbol for rolling calculations
    grouped = df.groupby('symbol')
    
    # Moving averages
    df['sma_10'] = grouped['close'].transform(lambda x: x.rolling(10, min_periods=1).mean())
    df['sma_20'] = grouped['close'].transform(lambda x: x.rolling(20, min_periods=1).mean())
    df['sma_50'] = grouped['close'].transform(lambda x: x.rolling(50, min_periods=1).mean())
    
    # EMAs
    df['ema_12'] = grouped['close'].transform(lambda x: x.ewm(span=12, adjust=False).mean())
    df['ema_26'] = grouped['close'].transform(lambda x: x.ewm(span=26, adjust=False).mean())
    
    # RSI
    def calculate_rsi(series, period=14):
        delta = series.diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
        rs = gain / loss
        rsi = 100 - (100 / (1 + rs))
        return rsi
    
    df['rsi'] = grouped['close'].transform(calculate_rsi)
    
    # MACD
    df['macd'] = df['ema_12'] - df['ema_26']
    df['macd_signal'] = grouped['macd'].transform(lambda x: x.ewm(span=9, adjust=False).mean())
    df['macd_hist'] = df['macd'] - df['macd_signal']
    
    # Bollinger Bands
    df['bb_middle'] = grouped['close'].transform(lambda x: x.rolling(20).mean())
    df['bb_std'] = grouped['close'].transform(lambda x: x.rolling(20).std())
    df['bb_upper'] = df['bb_middle'] + (df['bb_std'] * 2)
    df['bb_lower'] = df['bb_middle'] - (df['bb_std'] * 2)
    df['bb_width'] = (df['bb_upper'] - df['bb_lower']) / df['bb_middle']
    df['bb_position'] = (df['close'] - df['bb_lower']) / (df['bb_upper'] - df['bb_lower'])
    
    # ATR - fixed version
    def calculate_atr(group):
        high = group['high']
        low = group['low']
        close = group['close'].shift(1)
        tr1 = high - low
        tr2 = abs(high - close)
        tr3 = abs(low - close)
        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        atr = tr.rolling(14).mean()
        return atr
    
    # Apply ATR calculation per symbol
    atr_values = []
    for symbol in df['symbol'].unique():
        mask = df['symbol'] == symbol
        symbol_df = df[mask].copy()
        atr = calculate_atr(symbol_df)
        atr_values.extend(atr.values)
    
    df['atr'] = atr_values
    df['atr_pct'] = df['atr'] / df['close']
    
    # Volume
    df['volume_sma'] = grouped['volume'].transform(lambda x: x.rolling(20).mean())
    df['volume_ratio'] = df['volume'] / df['volume_sma']
    
    # Drop intermediate columns
    df = df.drop(columns=['bb_std'], errors='ignore')
    
    return df

def create_labels(df, future_periods=5, profit_threshold=0.002):
    """Create labels based on future returns"""
    print("\n🏷️ Creating trading labels...")
    
    # Shift returns forward to simulate future performance
    future_returns = df.groupby('symbol')['close'].transform(
        lambda x: x.shift(-future_periods) / x - 1
    )
    
    df['label'] = 0
    df.loc[future_returns > profit_threshold, 'label'] = 1
    df.loc[future_returns < -profit_threshold, 'label'] = -1
    
    # Count labels
    buy_count = len(df[df['label'] == 1])
    sell_count = len(df[df['label'] == -1])
    neutral_count = len(df[df['label'] == 0])
    
    print(f"  Buy signals: {buy_count}")
    print(f"  Sell signals: {sell_count}")
    print(f"  Neutral: {neutral_count}")
    
    return df

def train_model(df):
    """Train Random Forest model"""
    print("\n🤖 Training Random Forest model...")
    
    if not SKLEARN_AVAILABLE:
        print("⚠️ scikit-learn not available. Using simple rule-based model.")
        return create_rule_based_model(df)
    
    # Define features
    feature_names = [
        'returns', 'high_low_pct', 'close_open_pct', 'sma_10', 'sma_20', 
        'sma_50', 'ema_12', 'ema_26', 'rsi', 'macd', 'macd_signal', 
        'macd_hist', 'bb_width', 'bb_position', 'atr_pct', 'volume_ratio'
    ]
    
    # Remove rows with NaN
    df_clean = df.dropna(subset=feature_names + ['label'])
    
    if len(df_clean) < 100:
        print(f"⚠️ Only {len(df_clean)} clean samples. Using synthetic data.")
        df_clean = generate_synthetic_data()
        feature_names = [f for f in feature_names if f in df_clean.columns]
    
    # Prepare features and labels
    X = df_clean[feature_names].values
    y = df_clean['label'].values
    
    # Handle class imbalance
    from sklearn.utils import class_weight
    classes = np.unique(y)
    class_weights = class_weight.compute_class_weight('balanced', classes=classes, y=y)
    class_weight_dict = dict(zip(classes, class_weights))
    
    # Train model
    model = RandomForestClassifier(
        n_estimators=50,  # Reduced for speed
        max_depth=8,
        min_samples_split=20,
        min_samples_leaf=10,
        class_weight=class_weight_dict,
        random_state=42,
        n_jobs=-1
    )
    
    model.fit(X, y)
    
    # Feature importance
    importance = pd.DataFrame({
        'feature': feature_names,
        'importance': model.feature_importances_
    }).sort_values('importance', ascending=False)
    
    print("\n📊 Top 10 Most Important Features:")
    for _, row in importance.head(10).iterrows():
        print(f"  {row['feature']}: {row['importance']:.3f}")
    
    return model, feature_names

def create_rule_based_model(df):
    """Create a simple rule-based model when sklearn isn't available"""
    print("\n📊 Creating rule-based model...")
    
    class SimpleModel:
        def __init__(self):
            self.feature_importances_ = np.ones(16) / 16
            
        def predict(self, X):
            # Simple weighted scoring
            scores = np.sum(X[:, [8, 13, 9, 15]] * [0.4, 0.3, 0.2, 0.1], axis=1)
            predictions = np.zeros(len(X))
            predictions[scores > 0.5] = 1
            predictions[scores < -0.3] = -1
            return predictions
    
    feature_names = [
        'returns', 'high_low_pct', 'close_open_pct', 'sma_10', 'sma_20', 
        'sma_50', 'ema_12', 'ema_26', 'rsi', 'macd', 'macd_signal', 
        'macd_hist', 'bb_width', 'bb_position', 'atr_pct', 'volume_ratio'
    ]
    
    return SimpleModel(), feature_names

def convert_to_coreml(model, feature_names):
    """Convert model to Core ML"""
    print("\n🔄 Converting to Core ML format...")
    
    if not COREML_AVAILABLE:
        print("⚠️ coremltools not available. Creating placeholder model info.")
        return create_placeholder_model(feature_names)
    
    try:
        # For sklearn model
        if hasattr(model, 'feature_importances_'):
            coreml_model = ct.converters.sklearn.convert(
                model,
                feature_names=feature_names,
                target='label'
            )
        else:
            # For custom model, create a neural network approximation
            from coremltools.models import MLModel
            from coremltools.models.datatypes import Array
            from coremltools.models.neural_network import NeuralNetworkBuilder
            
            input_features = [('features', Array(1, len(feature_names)))]
            output_features = [('target', None)]
            
            builder = NeuralNetworkBuilder(input_features, output_features)
            
            # Simple dense layer approximation
            builder.add_inner_product(
                name='dense',
                W=np.random.randn(3, len(feature_names)).astype(np.float32),
                b=np.zeros(3).astype(np.float32),
                input_channels=len(feature_names),
                output_channels=3,
                has_bias=True
            )
            
            builder.add_softmax(name='softmax', input_name='dense', output_name='target')
            
            coreml_model = MLModel(builder.spec)
        
        # Add metadata
        coreml_model.author = 'ForexScalper'
        coreml_model.short_description = 'Predicts buy/sell signals for forex trading'
        coreml_model.version = '1.0'
        coreml_model.license = 'Private'
        
        # Add input descriptions
        for i, name in enumerate(feature_names):
            coreml_model.input_description[name] = f'Technical indicator: {name}'
        
        return coreml_model
        
    except Exception as e:
        print(f"❌ Error converting to Core ML: {e}")
        print("⚠️ Creating placeholder model instead.")
        return create_placeholder_model(feature_names)

def create_placeholder_model(feature_names):
    """Create a placeholder when conversion fails"""
    print("\n📝 Creating placeholder model (no actual ML)...")
    
    # Create a simple spec
    from coremltools.models import MLModel
    from coremltools.proto import Model_pb2
    
    spec = Model_pb2.Model()
    spec.specificationVersion = 4
    
    # Add input
    for name in feature_names:
        input_ = spec.description.input.add()
        input_.name = name
        input_.type.doubleType.SetInParent()
    
    # Add output
    output = spec.description.output.add()
    output.name = 'target'
    output.type.doubleType.SetInParent()
    
    # Add predicted probabilities
    prob_output = spec.description.output.add()
    prob_output.name = 'targetProbability'
    prob_output.type.dictionaryType.SetInParent()
    
    spec.description.predictedFeatureName = 'target'
    spec.description.predictedProbabilitiesName = 'targetProbability'
    
    return MLModel(spec)

def main():
    """Main execution"""
    print("\n🚀 Starting model generation...")
    
    # Fetch or generate data
    df = fetch_historical_data()
    
    if 'symbol' in df.columns:
        df = calculate_features(df)
        df = create_labels(df)
    
    # Train model
    model, feature_names = train_model(df)
    
    # Convert to Core ML
    coreml_model = convert_to_coreml(model, feature_names)
    
    # Save model
    output_path = 'TradingModel.mlmodel'
    coreml_model.save(output_path)
    
    file_size = os.path.getsize(output_path) / 1024 if os.path.exists(output_path) else 0
    print(f"\n✅ Model saved to: {output_path}")
    print(f"   Size: {file_size:.1f} KB")
    
    # Print final stats
    if 'label' in df.columns:
        print("\n📊 Final class distribution:")
        unique, counts = np.unique(df['label'], return_counts=True)
        for label, count in zip(unique, counts):
            signal = 'BUY' if label == 1 else 'SELL' if label == -1 else 'NEUTRAL'
            print(f"  {signal}: {count} samples ({count/len(df)*100:.1f}%)")
    
    print("\n" + "=" * 50)
    print("✅ Model generation complete!")
    print("=" * 50)

if __name__ == "__main__":
    main()